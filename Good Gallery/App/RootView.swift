import SwiftUI
import Photos
import SwiftData

struct RootView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @AppStorage("appearance") var appearanceRaw = AppearancePreference.system.rawValue

    var appearance: AppearancePreference { AppearancePreference(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        Group {
            switch library.status {
            case .notDetermined: WelcomeView()
            case .denied, .restricted: AccessDeniedView()
            default: MainTabView()
            }
        }
        .background(GGBackground())
        .tint(GG.Palette.accent)
        .animation(.easeInOut(duration: 0.35), value: library.status)
        .onAppear { applyAppearance() }
        .onChange(of: appearanceRaw) { _, _ in applyAppearance() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            library.refreshStatus()
            applyAppearance()
        }
    }
}

extension RootView {
    /// Overrides the style on every window so sheets and covers that are already on screen update too.
    func applyAppearance() {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .dark: .dark
        case .light: .light
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}

enum AppTab: Hashable { case library, favorites, albums, tools }

struct MainTabView: View {
    @State private var tab: AppTab = {
        #if DEBUG
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-gg-tab"),
           ProcessInfo.processInfo.arguments.indices.contains(i + 1) {
            switch ProcessInfo.processInfo.arguments[i + 1] {
            case "favorites": return .favorites
            case "albums": return .albums
            case "tools": return .tools
            default: break
            }
        }
        #endif
        return .library
    }()

    @State private var libraryPath = NavigationPath()
    @EnvironmentObject private var store: CollectionStore

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $libraryPath) { LibraryView() }
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
                .tag(AppTab.library)
            NavigationStack { FavoritesView() }
                .tabItem { Label("Favorites", systemImage: "star") }
                .tag(AppTab.favorites)
            NavigationStack { AlbumsView() }
                .tabItem { Label("Albums", systemImage: "rectangle.stack") }
                .tag(AppTab.albums)
            NavigationStack { ToolsView() }
                .tabItem { Label("Tools", systemImage: "wand.and.sparkles") }
                .tag(AppTab.tools)
        }
        .sensoryFeedback(.selection, trigger: tab)
        #if DEBUG
        .task {
            if DebugHarness.has("-gg-seed") { DebugHarness.seed(store: store) }
            if DebugHarness.has("-gg-selftest") { await DebugHarness.selfTest() }
            switch DebugHarness.value("-gg-open") {
            case "collection":
                try? await Task.sleep(for: .seconds(1))
                if let c = try? store.context.fetch(FetchDescriptor<MediaCollection>(sortBy: [SortDescriptor(\.sortOrder)])).first { libraryPath.append(c) }
            case "uncategorized": libraryPath.append(LibraryRoute.uncategorized)
            default: break
            }
        }
        #endif
    }
}

// MARK: - Permission screens

struct WelcomeView: View {
    @EnvironmentObject private var library: PhotoLibrary

    var body: some View {
        ZStack {
            GGBackground()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(GG.Palette.accent)
                    Text("Good Gallery")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(GG.Palette.text)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 18) {
                    WelcomePoint(icon: "folder", title: "Organise without moving anything",
                                 text: "Group your existing photos and videos into collections. Originals stay exactly where they are.")
                    WelcomePoint(icon: "lock", title: "Private by design",
                                 text: "Everything happens on this device. Nothing is uploaded, ever.")
                    WelcomePoint(icon: "photo.on.rectangle", title: "Your Photos access",
                                 text: "Good Gallery needs access to your library to show your photos. You can share only selected photos if you prefer.")
                }
                .padding(.horizontal, GG.Spacing.page + 4)
                Spacer()
                Button("Continue") { Task { await library.requestAccess() } }
                    .buttonStyle(GGPrimaryButtonStyle())
                    .padding(.horizontal, GG.Spacing.page)
                    .padding(.bottom, 24)
            }
        }
    }
}

private struct WelcomePoint: View {
    let icon: String, title: String, text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(GG.Palette.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(GG.Palette.text)
                Text(text).font(.footnote).foregroundStyle(GG.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AccessDeniedView: View {
    @EnvironmentObject private var library: PhotoLibrary
    var body: some View {
        ZStack {
            GGBackground()
            EmptyStateView(
                icon: "lock",
                title: library.status == .restricted ? "Photos Access Restricted" : "Photos Access Needed",
                message: library.status == .restricted
                    ? "Access to Photos is restricted on this device (for example by Screen Time or a device profile), so Good Gallery can't show your library."
                    : "Good Gallery can't see your photos. Open Settings → Photos and choose “Selected Photos” or “Full Access”. Your media never leaves your device.",
                actionTitle: library.status == .restricted ? nil : "Open Settings",
                action: { library.openSystemSettings() })
        }
    }
}

struct LimitedAccessBanner: View {
    @EnvironmentObject private var library: PhotoLibrary
    var body: some View {
        if library.isLimited {
            GGCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Limited Photos Access", systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(GG.Palette.accent)
                    Text("Good Gallery can only see the photos you've chosen to share. Add more, or allow full access in Settings to organise your whole library.")
                        .font(.footnote).foregroundStyle(GG.Palette.secondaryText)
                    HStack(spacing: 10) {
                        Button("Select More Photos") { library.presentLimitedPicker() }
                            .buttonStyle(GGSecondaryButtonStyle(fullWidth: false))
                        Button("Open Settings") { library.openSystemSettings() }
                            .buttonStyle(GGSecondaryButtonStyle(fullWidth: false))
                    }
                    .font(.footnote)
                }
            }
        }
    }
}
