import Foundation

enum DriveError: LocalizedError {
    case api(String)
    var errorDescription: String? { if case .api(let m) = self { m } else { nil } }
}

@MainActor
final class GoogleDriveService: ObservableObject {
    static let shared = GoogleDriveService()

    /// `drive.file` only lets the app see files it created itself, so Google doesn't treat it as a restricted scope.
    private let auth = GoogleAuth(name: "drive", scope: "https://www.googleapis.com/auth/drive.file")
    @Published private(set) var isSignedIn: Bool
    private var folderCache: [String: String] = [:]

    private init() { isSignedIn = auth.hasToken }

    func signIn() async throws {
        try await auth.signIn()
        isSignedIn = true
    }

    func signOut() {
        auth.signOut()
        folderCache = [:]
        isSignedIn = false
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
        let token = try await auth.accessToken()
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
        let token = try await auth.accessToken()
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
}
