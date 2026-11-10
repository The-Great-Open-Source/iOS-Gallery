import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct GoodGalleryApp: App {
    private let container: ModelContainer
    @StateObject private var library = PhotoLibrary()
    @StateObject private var store: CollectionStore
    @StateObject private var backup: BackupEngine
    @Environment(\.scenePhase) private var scenePhase
    static let backupTaskID = "com.harshanacz.Good-Gallery.backup"
    @StateObject private var searchIndex = MediaSearchIndex()

    init() {
        let schema = Schema([MediaCollection.self, CollectionMedia.self, FavoriteMedia.self, CompressionRecord.self,
                              BackupRecord.self, PhotoTags.self])
        // Make sure Application Support exists so SwiftData can create its store on first launch.
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema)
        } catch {
            // Never crash on launch because of a store problem; fall back to a temporary in-memory store.
            print("Persistent store failed (\(error)); using in-memory store.")
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        self.container = container
        let store = CollectionStore(context: container.mainContext)
        _store = StateObject(wrappedValue: store)
        let engine = BackupEngine(store: store)
        _backup = StateObject(wrappedValue: engine)
        BackupSettings.register()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backupTaskID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            let work = Task { @MainActor in
                await engine.runAutomatic()
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(store)
                .environmentObject(searchIndex)
                .environmentObject(backup)
                .modelContainer(container)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: Task { await backup.runAutomatic() }
                    case .background: Self.scheduleBackup()
                    default: break
                    }
                }
        }
    }

    /// Asks iOS to wake the app for automatic Drive backup. iOS decides when (usually idle, on Wi-Fi/power).
    private static func scheduleBackup() {
        guard BackupSettings.driveAuto, GoogleDriveService.shared.isSignedIn else { return }
        let request = BGProcessingTaskRequest(identifier: backupTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
