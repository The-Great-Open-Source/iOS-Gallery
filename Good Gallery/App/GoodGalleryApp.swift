import SwiftUI
import SwiftData

@main
struct GoodGalleryApp: App {
    private let container: ModelContainer
    @StateObject private var library = PhotoLibrary()
    @StateObject private var store: CollectionStore
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
        _store = StateObject(wrappedValue: CollectionStore(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(store)
                .environmentObject(searchIndex)
                .modelContainer(container)
        }
    }
}
