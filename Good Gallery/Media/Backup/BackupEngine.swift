import Photos
import SwiftData
import SwiftUI

enum BackupDestination: String, CaseIterable, Identifiable {
    case drive, telegram, youtube
    var id: String { rawValue }
    var title: String {
        switch self { case .drive: "Google Drive"; case .telegram: "Telegram"; case .youtube: "YouTube" }
    }
    var icon: String {
        switch self { case .drive: "externaldrive.badge.icloud"; case .telegram: "paperplane"; case .youtube: "play.rectangle" }
    }
    var videosOnly: Bool { self == .youtube }

    /// Largest file this destination accepts, honouring the user's own limit.
    var effectiveLimit: Int64 {
        let user = BackupSettings.maxFileBytes
        return self == .telegram ? min(user, BackupSettings.telegramLimitBytes) : user
    }
}

struct BackupSummary {
    var sent = 0
    var alreadyDone = 0
    var tooLarge = 0
    var filteredByType = 0
    var failed = 0
    var firstError: String?
}

/// Runs a backup job: exports each original to a temp file, uploads it, records it, deletes the temp file.
/// Telegram is manual only; Google Drive can also run automatically (see `runAutomatic`).
@MainActor
final class BackupEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var total = 0
    @Published private(set) var processed = 0
    @Published private(set) var currentName = ""
    @Published private(set) var summary: BackupSummary?
    @Published private(set) var destination: BackupDestination = .drive
    private var task: Task<Void, Never>?
    private let store: CollectionStore

    init(store: CollectionStore) { self.store = store }

    var progress: Double { total == 0 ? 0 : Double(processed) / Double(total) }

    func start(assets: [PHAsset], to destination: BackupDestination, folderName: String?) {
        guard !isRunning else { return }
        task = Task { _ = await run(assets: assets, to: destination, folderName: folderName) }
    }

    func cancel() { task?.cancel() }
    func resetSummary() { if !isRunning { summary = nil } }

    @discardableResult
    func run(assets: [PHAsset], to destination: BackupDestination, folderName: String?) async -> BackupSummary {
        isRunning = true
        self.destination = destination
        summary = nil
        total = assets.count
        processed = 0
        var result = BackupSummary()
        defer { isRunning = false; summary = result; MediaExporter.clearScratch() }

        let done = alreadyBackedUp(destination)
        let limit = destination.effectiveLimit
        var driveFolder: String?
        if destination == .drive {
            do { driveFolder = try await GoogleDriveService.shared.ensureFolder(subfolder: folderName) }
            catch { result.failed = assets.count; result.firstError = error.localizedDescription; return result }
        } else if !TelegramService.isConfigured {
            result.failed = assets.count; result.firstError = TelegramError.notConfigured.localizedDescription
            return result
        }

        for asset in assets {
            if Task.isCancelled { break }
            defer { processed += 1 }
            let id = asset.localIdentifier
            if done.contains(id) { result.alreadyDone += 1; continue }
            let isVideo = asset.mediaType == .video
            if (destination.videosOnly && !isVideo) || (isVideo && !BackupSettings.includeVideos) || (!isVideo && !BackupSettings.includePhotos) {
                result.filteredByType += 1; continue
            }
            if let known = Self.originalSize(of: asset), known > limit { result.tooLarge += 1; continue }
            currentName = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""

            do {
                guard let url = try await MediaExporter.shareURLs(for: [asset]).first else { throw TelegramError.api("Couldn't read the original.") }
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                if size > limit { result.tooLarge += 1; continue }
                switch destination {
                case .drive: try await GoogleDriveService.shared.upload(fileURL: url, folderID: driveFolder!)
                case .telegram: try await TelegramService.sendDocument(fileURL: url, caption: folderName)
                case .youtube:
                    let stem = url.deletingPathExtension().lastPathComponent
                    let title = [folderName, stem].compactMap { $0 }.joined(separator: " – ")
                    try await YouTubeService.shared.uploadPrivate(fileURL: url, title: title, description: "Uploaded from Good Gallery")
                }
                store.context.insert(BackupRecord(destination: destination.rawValue, identifier: id))
                result.sent += 1
            } catch is CancellationError {
                break
            } catch TelegramError.tooLarge {
                result.tooLarge += 1
            } catch {
                result.failed += 1
                result.firstError = result.firstError ?? error.localizedDescription
            }
        }
        try? store.context.save()
        return result
    }

    // MARK: Automatic (Google Drive)

    /// Uploads new items from collections flagged for automatic backup. Safe to call repeatedly.
    func runAutomatic() async {
        guard !isRunning, BackupSettings.driveAuto, GoogleDriveService.shared.isSignedIn else { return }
        if BackupSettings.wifiOnly ? !(await NetworkCheck.isOnWiFi()) : !(await NetworkCheck.isOnline()) { return }
        let collections = ((try? store.context.fetch(FetchDescriptor<MediaCollection>())) ?? []).filter(\.autoBackupDrive)
        for collection in collections {
            if Task.isCancelled { return }
            let done = alreadyBackedUp(.drive)
            let ids = collection.items.map(\.photoKitLocalIdentifier).filter { !done.contains($0) }
            guard !ids.isEmpty else { continue }
            let assets = Array(Assets.resolve(ids).values)
            await run(assets: assets, to: .drive, folderName: collection.name)
        }
    }

    func pendingAutomaticCount() -> Int {
        let done = alreadyBackedUp(.drive)
        let collections = ((try? store.context.fetch(FetchDescriptor<MediaCollection>())) ?? []).filter(\.autoBackupDrive)
        return Set(collections.flatMap { $0.items.map(\.photoKitLocalIdentifier) }).subtracting(done).count
    }

    // MARK: Helpers

    private func alreadyBackedUp(_ destination: BackupDestination) -> Set<String> {
        let raw = destination.rawValue
        let records = (try? store.context.fetch(FetchDescriptor<BackupRecord>(predicate: #Predicate { $0.destination == raw }))) ?? []
        return Set(records.map(\.photoKitLocalIdentifier))
    }

    /// Best-effort original size without downloading (PhotoKit's `fileSize` is not formally documented).
    nonisolated static func originalSize(of asset: PHAsset) -> Int64? {
        let resources = PHAssetResource.assetResources(for: asset)
        let wanted: PHAssetResourceType = asset.mediaType == .video ? .video : .photo
        guard let resource = resources.first(where: { $0.type == wanted }) ?? resources.first,
              resource.responds(to: Selector(("fileSize"))),
              let value = resource.value(forKey: "fileSize") as? NSNumber else { return nil }
        return value.int64Value
    }
}
