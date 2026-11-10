import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Google Drive needs an OAuth *iOS* client ID created in Google Cloud Console (Drive API enabled).
/// Paste it here, e.g. "1234567890-abcdef.apps.googleusercontent.com". Leave empty to hide Drive backup.
enum GoogleDriveConfig {
    static let clientID = ""

    static var isConfigured: Bool { !clientID.isEmpty }
    /// Google's iOS redirect scheme is the client ID with its parts reversed.
    static var redirectScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
    /// `drive.file` only lets the app see files it created itself, so Google doesn't treat it as a restricted scope.
    static let scope = "https://www.googleapis.com/auth/drive.file"
}

enum DriveError: LocalizedError {
    case notConfigured, notSignedIn, cancelled
    case api(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google Drive isn't configured in this build."
        case .notSignedIn: "Sign in to Google Drive first."
        case .cancelled: "Sign-in was cancelled."
        case .api(let message): message
        }
    }
}

@MainActor
final class GoogleDriveService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleDriveService()

    private enum Key {
        static let refresh = "drive.refreshToken"
        static let access = "drive.accessToken"
        static let expiry = "drive.accessExpiry"
    }

    @Published private(set) var isSignedIn: Bool
    private var folderCache: [String: String] = [:]

    private override init() {
        isSignedIn = Keychain.get(Key.refresh) != nil
        super.init()
    }

    // MARK: Sign in (OAuth 2.0 + PKCE, no SDK)

    func signIn() async throws {
        guard GoogleDriveConfig.isConfigured else { throw DriveError.notConfigured }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: GoogleDriveConfig.clientID),
            .init(name: "redirect_uri", value: GoogleDriveConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: GoogleDriveConfig.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: GoogleDriveConfig.redirectScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { continuation.resume(throwing: DriveError.cancelled) }
                else { continuation.resume(throwing: error ?? DriveError.cancelled) }
            }
            session.presentationContextProvider = self
            session.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw DriveError.api("Google didn't return an authorisation code.")
        }
        try await tokenRequest([
            "code": code, "client_id": GoogleDriveConfig.clientID, "code_verifier": verifier,
            "redirect_uri": GoogleDriveConfig.redirectURI, "grant_type": "authorization_code"
        ])
        isSignedIn = true
    }

    func signOut() {
        Keychain.set(nil, for: Key.refresh); Keychain.set(nil, for: Key.access); Keychain.set(nil, for: Key.expiry)
        folderCache = [:]
        isSignedIn = false
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    private func tokenRequest(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\(Self.escape($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error_description"] as? String
            throw DriveError.api(message ?? "Google sign-in failed.")
        }
        Keychain.set(access, for: Key.access)
        Keychain.set(String(Date().timeIntervalSince1970 + ((json["expires_in"] as? Double) ?? 3600) - 60), for: Key.expiry)
        if let refresh = json["refresh_token"] as? String { Keychain.set(refresh, for: Key.refresh) }
    }

    private func accessToken() async throws -> String {
        guard let refresh = Keychain.get(Key.refresh) else { throw DriveError.notSignedIn }
        if let token = Keychain.get(Key.access), let expiry = Double(Keychain.get(Key.expiry) ?? ""), expiry > Date().timeIntervalSince1970 {
            return token
        }
        try await tokenRequest(["client_id": GoogleDriveConfig.clientID, "refresh_token": refresh, "grant_type": "refresh_token"])
        guard let token = Keychain.get(Key.access) else { throw DriveError.notSignedIn }
        return token
    }

    // MARK: Drive API

    /// Finds or creates "Good Gallery Backup" and, optionally, a subfolder (one per collection).
    func ensureFolder(subfolder: String?) async throws -> String {
        let root = try await folder(named: "Good Gallery Backup", parent: nil)
        guard let subfolder, !subfolder.isEmpty else { return root }
        return try await folder(named: subfolder, parent: root)
    }

    private func folder(named name: String, parent: String?) async throws -> String {
        let cacheKey = "\(parent ?? "root")/\(name)"
        if let cached = folderCache[cacheKey] { return cached }
        let token = try await accessToken()
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        var q = "name='\(escaped)' and mimeType='application/vnd.google-apps.folder' and trashed=false"
        if let parent { q += " and '\(parent)' in parents" }
        var list = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        list.queryItems = [.init(name: "q", value: q), .init(name: "fields", value: "files(id)"), .init(name: "spaces", value: "drive")]
        var request = URLRequest(url: list.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        if let files = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["files"] as? [[String: Any]],
           let id = files.first?["id"] as? String {
            folderCache[cacheKey] = id
            return id
        }
        var create = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        create.httpMethod = "POST"
        create.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["name": name, "mimeType": "application/vnd.google-apps.folder"]
        if let parent { body["parents"] = [parent] }
        create.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (created, _) = try await URLSession.shared.data(for: create)
        guard let id = (try? JSONSerialization.jsonObject(with: created) as? [String: Any])?["id"] as? String else {
            throw DriveError.api("Couldn't create the backup folder in Google Drive.")
        }
        folderCache[cacheKey] = id
        return id
    }

    /// Resumable upload streamed from disk.
    func upload(fileURL: URL, folderID: String) async throws {
        let token = try await accessToken()
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var start = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id")!)
        start.httpMethod = "POST"
        start.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue("application/octet-stream", forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue("\(size)", forHTTPHeaderField: "X-Upload-Content-Length")
        start.httpBody = try JSONSerialization.data(withJSONObject: ["name": fileURL.lastPathComponent, "parents": [folderID]])
        let (_, startResponse) = try await URLSession.shared.data(for: start)
        guard let http = startResponse as? HTTPURLResponse, http.statusCode == 200,
              let location = http.value(forHTTPHeaderField: "Location"), let sessionURL = URL(string: location) else {
            throw DriveError.api("Google Drive refused the upload (\((startResponse as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        var put = URLRequest(url: sessionURL)
        put.httpMethod = "PUT"
        put.timeoutInterval = 900
        let (_, response) = try await URLSession.shared.upload(for: put, fromFile: fileURL)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw DriveError.api("Upload to Google Drive failed.")
        }
    }

    // MARK: Helpers

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
