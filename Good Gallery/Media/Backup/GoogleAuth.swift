import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Google Cloud needs an OAuth *iOS* client ID (Drive API and/or YouTube Data API enabled).
/// Paste it here, e.g. "1234567890-abcdef.apps.googleusercontent.com". Leave empty to hide Drive/YouTube backup.
enum GoogleConfig {
    static let clientID = ""

    static var isConfigured: Bool { !clientID.isEmpty }
    /// Google's iOS redirect scheme is the client ID with its parts reversed.
    static var redirectScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
}

enum GoogleAuthError: LocalizedError {
    case notConfigured, notSignedIn, cancelled
    case api(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google sign-in isn't configured in this build."
        case .notSignedIn: "Sign in with Google first."
        case .cancelled: "Sign-in was cancelled."
        case .api(let message): message
        }
    }
}

/// OAuth 2.0 + PKCE for one Google service (its own scope and Keychain slot). No SDK.
@MainActor
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let name: String
    private let scope: String

    /// - Parameter name: Keychain prefix. "drive" keeps existing Drive sign-ins working.
    init(name: String, scope: String) { self.name = name; self.scope = scope }

    private var refreshKey: String { "\(name).refreshToken" }
    private var accessKey: String { "\(name).accessToken" }
    private var expiryKey: String { "\(name).accessExpiry" }

    var hasToken: Bool { Keychain.get(refreshKey) != nil }

    func signIn() async throws {
        guard GoogleConfig.isConfigured else { throw GoogleAuthError.notConfigured }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: GoogleConfig.clientID),
            .init(name: "redirect_uri", value: GoogleConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: GoogleConfig.redirectScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { continuation.resume(throwing: GoogleAuthError.cancelled) }
                else { continuation.resume(throwing: error ?? GoogleAuthError.cancelled) }
            }
            session.presentationContextProvider = self
            session.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.api("Google didn't return an authorisation code.")
        }
        try await tokenRequest([
            "code": code, "client_id": GoogleConfig.clientID, "code_verifier": verifier,
            "redirect_uri": GoogleConfig.redirectURI, "grant_type": "authorization_code"
        ])
    }

    func signOut() {
        Keychain.set(nil, for: refreshKey); Keychain.set(nil, for: accessKey); Keychain.set(nil, for: expiryKey)
    }

    func accessToken() async throws -> String {
        guard let refresh = Keychain.get(refreshKey) else { throw GoogleAuthError.notSignedIn }
        if let token = Keychain.get(accessKey), let expiry = Double(Keychain.get(expiryKey) ?? ""), expiry > Date().timeIntervalSince1970 {
            return token
        }
        try await tokenRequest(["client_id": GoogleConfig.clientID, "refresh_token": refresh, "grant_type": "refresh_token"])
        guard let token = Keychain.get(accessKey) else { throw GoogleAuthError.notSignedIn }
        return token
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
            throw GoogleAuthError.api(message ?? "Google sign-in failed.")
        }
        Keychain.set(access, for: accessKey)
        Keychain.set(String(Date().timeIntervalSince1970 + ((json["expires_in"] as? Double) ?? 3600) - 60), for: expiryKey)
        if let refresh = json["refresh_token"] as? String { Keychain.set(refresh, for: refreshKey) }
    }

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
