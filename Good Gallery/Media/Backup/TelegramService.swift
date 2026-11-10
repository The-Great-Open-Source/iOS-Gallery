import Foundation

enum TelegramError: LocalizedError {
    case notConfigured
    case api(String)
    case tooLarge
    case noChatFound

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Telegram isn't set up yet."
        case .api(let message): message
        case .tooLarge: "Telegram bots can only send files up to 50 MB."
        case .noChatFound: "No chat found. Send any message to your bot in Telegram, then try again."
        }
    }
}

/// Sends files to the user's *own* Telegram bot/chat via the Bot API. The token never leaves the device
/// except in requests to api.telegram.org, and is stored in the Keychain.
enum TelegramService {
    static let tokenKey = "telegram.botToken"

    static var token: String? { Keychain.get(tokenKey) }
    static var chatID: String? { UserDefaults.standard.string(forKey: BackupSettings.Key.telegramChatID) }
    static var isConfigured: Bool { token != nil && !(chatID ?? "").isEmpty }

    private static func endpoint(_ method: String, token: String) -> URL {
        URL(string: "https://api.telegram.org/bot\(token)/\(method)")!
    }

    /// Verifies the token and returns the bot's username.
    static func verify(token: String) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: endpoint("getMe", token: token))
        let json = try parse(data)
        guard let result = json["result"] as? [String: Any], let name = result["username"] as? String else {
            throw TelegramError.api("Invalid bot token.")
        }
        return name
    }

    /// Finds the chat that most recently messaged the bot (the user messages their own bot once).
    static func detectChat(token: String) async throws -> (id: String, title: String) {
        let (data, _) = try await URLSession.shared.data(from: endpoint("getUpdates", token: token))
        let json = try parse(data)
        let updates = (json["result"] as? [[String: Any]]) ?? []
        for update in updates.reversed() {
            let message = (update["message"] ?? update["channel_post"] ?? update["my_chat_member"]) as? [String: Any]
            if let chat = message?["chat"] as? [String: Any], let id = chat["id"] {
                let title = (chat["title"] as? String) ?? (chat["first_name"] as? String) ?? (chat["username"] as? String) ?? "Chat"
                return ("\(id)", title)
            }
        }
        throw TelegramError.noChatFound
    }

    static func sendDocument(fileURL: URL, caption: String?) async throws {
        guard let token, let chatID, !chatID.isEmpty else { throw TelegramError.notConfigured }
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if size > BackupSettings.telegramLimitBytes { throw TelegramError.tooLarge }

        // Stream the multipart body from a temp file so large videos never sit in memory.
        let boundary = "GG-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory.appendingPathComponent("tg-\(UUID().uuidString).body")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        let handle = try FileHandle(forWritingTo: bodyURL)
        func write(_ string: String) { handle.write(Data(string.utf8)) }
        func field(_ name: String, _ value: String) {
            write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("chat_id", chatID)
        if let caption { field("caption", caption) }
        field("disable_content_type_detection", "true")
        write("--\(boundary)\r\nContent-Disposition: form-data; name=\"document\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n")
        let input = try FileHandle(forReadingFrom: fileURL)
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty { handle.write(chunk) }
        try input.close()
        write("\r\n--\(boundary)--\r\n")
        try handle.close()

        var request = URLRequest(url: endpoint("sendDocument", token: token))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
        if (response as? HTTPURLResponse)?.statusCode == 413 { throw TelegramError.tooLarge }
        _ = try parse(data)
    }

    private static func parse(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TelegramError.api("Unexpected response from Telegram.")
        }
        if json["ok"] as? Bool != true {
            throw TelegramError.api((json["description"] as? String) ?? "Telegram rejected the request.")
        }
        return json
    }

    static func disconnect() {
        Keychain.set(nil, for: tokenKey)
        UserDefaults.standard.removeObject(forKey: BackupSettings.Key.telegramChatID)
        UserDefaults.standard.removeObject(forKey: BackupSettings.Key.telegramBotName)
    }
}
