import Foundation
import Network

/// User-configurable backup options, persisted in UserDefaults (non-secret values only).
enum BackupSettings {
    enum Key {
        static let maxFileSizeMB = "backup.maxFileSizeMB"
        static let includePhotos = "backup.includePhotos"
        static let includeVideos = "backup.includeVideos"
        static let wifiOnly = "backup.wifiOnly"
        static let driveAuto = "backup.driveAuto"
        static let telegramChatID = "backup.telegram.chatID"
        static let telegramBotName = "backup.telegram.botName"
    }

    static let defaultMaxFileSizeMB = 100
    /// Telegram bots cannot upload files larger than this.
    static let telegramLimitBytes: Int64 = 50 * 1_000_000

    static func register() {
        UserDefaults.standard.register(defaults: [
            Key.maxFileSizeMB: defaultMaxFileSizeMB,
            Key.includePhotos: true,
            Key.includeVideos: true,
            Key.wifiOnly: true,
            Key.driveAuto: false
        ])
    }

    static var maxFileBytes: Int64 { Int64(UserDefaults.standard.integer(forKey: Key.maxFileSizeMB)) * 1_000_000 }
    static var includePhotos: Bool { UserDefaults.standard.bool(forKey: Key.includePhotos) }
    static var includeVideos: Bool { UserDefaults.standard.bool(forKey: Key.includeVideos) }
    static var wifiOnly: Bool { UserDefaults.standard.bool(forKey: Key.wifiOnly) }
    static var driveAuto: Bool { UserDefaults.standard.bool(forKey: Key.driveAuto) }
}

/// One-shot network check used to honour "Wi-Fi only".
enum NetworkCheck {
    static func isOnWiFi() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "gg.netcheck")
            var done = false
            monitor.pathUpdateHandler = { path in
                guard !done else { return }
                done = true
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.isExpensive)
            }
            monitor.start(queue: queue)
        }
    }
    static func isOnline() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            var done = false
            monitor.pathUpdateHandler = { path in
                guard !done else { return }
                done = true
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "gg.netcheck2"))
        }
    }
}
