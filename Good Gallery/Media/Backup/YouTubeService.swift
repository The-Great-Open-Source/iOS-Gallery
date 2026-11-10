import Foundation

enum YouTubeError: LocalizedError {
    case api(String)
    case quotaExceeded
    var errorDescription: String? {
        switch self {
        case .api(let message): message
        case .quotaExceeded: "YouTube's daily upload limit for this app has been reached. Try again tomorrow."
        }
    }
}

/// Uploads videos to the user's own YouTube channel as **Private** (resumable upload, streamed from disk).
@MainActor
final class YouTubeService: ObservableObject {
    static let shared = YouTubeService()

    private let auth = GoogleAuth(name: "youtube", scope: "https://www.googleapis.com/auth/youtube.upload")
    @Published private(set) var isSignedIn: Bool

    private init() { isSignedIn = auth.hasToken }

    func signIn() async throws {
        try await auth.signIn()
        isSignedIn = true
    }

    func signOut() {
        auth.signOut()
        isSignedIn = false
    }

    func uploadPrivate(fileURL: URL, title: String, description: String) async throws {
        let token = try await auth.accessToken()
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        var start = URLRequest(url: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")!)
        start.httpMethod = "POST"
        start.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        start.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        start.setValue("video/*", forHTTPHeaderField: "X-Upload-Content-Type")
        start.setValue("\(size)", forHTTPHeaderField: "X-Upload-Content-Length")
        let body: [String: Any] = [
            "snippet": ["title": String(title.prefix(100)), "description": description, "categoryId": "22"],
            "status": ["privacyStatus": "private", "selfDeclaredMadeForKids": false]
        ]
        start.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (startData, startResponse) = try await URLSession.shared.data(for: start)
        guard let http = startResponse as? HTTPURLResponse else { throw YouTubeError.api("No response from YouTube.") }
        guard http.statusCode == 200, let location = http.value(forHTTPHeaderField: "Location"), let sessionURL = URL(string: location) else {
            throw Self.error(from: startData, status: http.statusCode)
        }

        var put = URLRequest(url: sessionURL)
        put.httpMethod = "PUT"
        put.setValue("video/*", forHTTPHeaderField: "Content-Type")
        put.timeoutInterval = 1800
        let (data, response) = try await URLSession.shared.upload(for: put, fromFile: fileURL)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw Self.error(from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    private static func error(from data: Data, status: Int) -> YouTubeError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let err = json?["error"] as? [String: Any]
        let reasons = (err?["errors"] as? [[String: Any]])?.compactMap { $0["reason"] as? String } ?? []
        if reasons.contains(where: { $0 == "quotaExceeded" || $0 == "uploadLimitExceeded" || $0 == "rateLimitExceeded" }) { return .quotaExceeded }
        if reasons.contains("youtubeSignupRequired") { return .api("This Google account has no YouTube channel. Create one in the YouTube app first.") }
        return .api((err?["message"] as? String) ?? "YouTube refused the upload (\(status)).")
    }
}
