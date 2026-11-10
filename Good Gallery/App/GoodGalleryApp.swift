import SwiftUI
import SwiftData

@main
struct GoodGalleryApp: App {
    private let container: ModelContainer
    @StateObject private var library = PhotoLibrary()
    @StateObject private var store: CollectionStore
    @StateObject private var searchIndex = MediaSearchIndex()

    init() {
        let schema = Schema([MediaCollection.self, CollectionMedia.self, FavoriteMedia.self, CompressionRecord.self])
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
        Self.configureAppearance()
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

    private static func configureAppearance() {
        if #unavailable(iOS 26.0) {
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = UIColor(GG.Palette.background).withAlphaComponent(0.85)
        tab.shadowColor = UIColor(GG.Palette.separator)
        let normal = UIColor(GG.Palette.secondaryText)
        let selected = UIColor(GG.Palette.accent)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.foregroundColor: normal]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        }

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor(GG.Palette.text)]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor(GG.Palette.text),
            .font: UIFont(descriptor: UIFont.systemFont(ofSize: 34, weight: .regular).fontDescriptor.withDesign(.serif)!, size: 34)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}
