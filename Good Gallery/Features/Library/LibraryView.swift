import SwiftUI
import SwiftData
import Photos

enum LibraryRoute: Hashable { case allPhotos, uncategorized, largeFiles }

struct LibraryView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var store: CollectionStore
    @Query(sort: \MediaCollection.sortOrder) private var collections: [MediaCollection]
    @Query private var allItems: [CollectionMedia]
    @StateObject private var uncategorized = UncategorizedModel()
    @StateObject private var allPhotos = AllPhotosModel()
    @Namespace private var zoom

    @State private var showCreate = false
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showReorder = false
    @State private var editing: MediaCollection?
    @State private var coverTarget: MediaCollection?
    @State private var deleting: MediaCollection?

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    private struct RefreshKey: Hashable { let count: Int; let token: Int; let ids: Int }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LimitedAccessBanner()

                StorageCard()

                VStack(spacing: 0) {
                    libraryRow(icon: "photo.on.rectangle", title: "All Photos", route: .allPhotos,
                               count: allPhotos.hasLoaded ? allPhotos.assets.count.formatted() : "")
                    Divider().padding(.leading, 52)
                    libraryRow(icon: "tray", title: "Uncategorized", route: .uncategorized,
                               count: uncategorized.hasLoaded ? uncategorized.assets.count.formatted() : "")
                }
                .background(GG.Palette.surface, in: RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Collections")
                    if collections.isEmpty {
                        firstRunEmptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(collections) { collection in
                                NavigationLink(value: collection) {
                                    CollectionCard(collection: collection)
                                        .zoomSource(id: collection.id, in: zoom)
                                }
                                .buttonStyle(PressableStyle())
                                .contextMenu { menu(for: collection) }
                            }
                        }
                        .animation(.snappy(duration: 0.35), value: collections.map(\.id))
                    }
                }

            }
            .padding(.horizontal, GG.Spacing.page)
            .padding(.bottom, 30)
        }
        .ggScreen()
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search")
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Collection")
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .navigationDestination(for: MediaCollection.self) { collection in
            CollectionDetailView(collection: collection)
                .zoomDestination(id: collection.id, in: zoom)
        }
        .navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .allPhotos:
                AllPhotosScreen(model: allPhotos)
            case .uncategorized:
                UncategorizedScreen(model: uncategorized)
            case .largeFiles:
                LargeFilesView()
            }
        }
        .task(id: RefreshKey(count: allItems.count, token: library.changeToken, ids: allItems.first?.photoKitLocalIdentifier.hashValue ?? 0)) {
            await uncategorized.refresh(organized: Set(allItems.map(\.photoKitLocalIdentifier)))
        }
        .task(id: library.changeToken) { await allPhotos.refresh() }
        .sheet(isPresented: $showCreate) { CollectionEditorSheet(mode: .create) }
        .sheet(isPresented: $showSearch) { SearchView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showReorder) { ReorderCollectionsSheet(collections: collections) }
        .sheet(item: $editing) { CollectionEditorSheet(mode: .edit($0)) }
        .sheet(item: $coverTarget) { target in
            MediaPickerView(title: "Change Cover", mode: .single, initialFilter: .photos,
                            confirmTitle: { _ in "Use as Cover" }) { ids in
                store.setCover(target, identifier: ids.first)
            }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) {
                if let deleting { withAnimation(.snappy) { store.delete(deleting) } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Your photos and videos stay safely in your library. Only the collection is removed.")
        }
    }

    @ViewBuilder
    private func menu(for collection: MediaCollection) -> some View {
        Button { editing = collection } label: { Label("Rename & Describe", systemImage: "pencil") }
        Button { coverTarget = collection } label: { Label("Change Cover", systemImage: "photo") }
        if collections.count > 1 {
            Button { showReorder = true } label: { Label("Reorder Collections", systemImage: "arrow.up.arrow.down") }
        }
        Divider()
        Button(role: .destructive) { deleting = collection } label: { Label("Delete Collection", systemImage: "trash") }
    }

    private var firstRunEmptyState: some View {
        EmptyStateView(
            icon: "square.stack",
            title: "No Collections",
            message: "Group your photos and videos into collections. Originals never move.",
            actionTitle: "New Collection") { showCreate = true }
    }

    private func libraryRow(icon: String, title: String, route: LibraryRoute, count: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(GG.Palette.accent).frame(width: 28)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(count).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Photos-style album tile: square cover, name and count underneath.
struct CollectionCard: View {
    let collection: MediaCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(identifier: collection.effectiveCoverIdentifier)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(collection.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                Text(collection.items.count.formatted()).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collection.name), \(Format.count(collection.items.count))")
    }
}

/// Observes the model directly so the grid updates live (a navigation destination closure alone captures a stale copy).
struct AllPhotosScreen: View {
    @ObservedObject var model: AllPhotosModel
    var body: some View {
        AssetBrowserView(title: "All Photos", assets: model.assets, hasLoaded: model.hasLoaded,
                         emptyTitle: "No Photos", emptyMessage: "No photos or videos are available to Good Gallery.")
    }
}

struct UncategorizedScreen: View {
    @ObservedObject var model: UncategorizedModel
    var body: some View {
        AssetBrowserView(title: "Uncategorized", assets: model.assets, hasLoaded: model.hasLoaded,
                         emptyTitle: "All Organised", emptyMessage: "Every photo and video belongs to a collection.")
    }
}

struct AssetBrowserView: View {
    let title: String
    let allAssets: [PHAsset]
    let hasLoaded: Bool
    let emptyTitle: String
    let emptyMessage: String
    @State private var filter: MediaFilter = .all
    @State private var removedIDs: Set<String> = []
    @EnvironmentObject private var store: CollectionStore
    @Query private var favorites: [FavoriteMedia]
    @StateObject private var share = SharePreparer()
    @StateObject private var deleter = LibraryDeleter()
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var viewer: ViewerContext?
    @State private var showAddTo = false

    init(title: String, assets: [PHAsset], hasLoaded: Bool, emptyTitle: String, emptyMessage: String) {
        self.title = title; self.allAssets = assets; self.hasLoaded = hasLoaded
        self.emptyTitle = emptyTitle; self.emptyMessage = emptyMessage
    }

    private var assets: [PHAsset] {
        let base = removedIDs.isEmpty ? allAssets : allAssets.filter { !removedIDs.contains($0.localIdentifier) }
        switch filter {
        case .all: return base
        case .photos: return base.filter { $0.mediaType == .image }
        case .videos: return base.filter { $0.mediaType == .video }
        }
    }

    var body: some View {
        ScrollView {
            if !hasLoaded {
                LoadingGrid()
            } else if assets.isEmpty {
                EmptyStateView(icon: "photo.on.rectangle", title: emptyTitle, message: emptyMessage)
                    .padding(.top, 80)
            } else {
                AssetGrid(assets: assets, favorites: Set(favorites.map(\.photoKitLocalIdentifier)),
                          isSelecting: selecting, selection: $selection) { index in
                    viewer = ViewerContext(assets: assets, index: index)
                }
            }
        }
        .ggScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Show", selection: $filter) { ForEach(MediaFilter.allCases) { Text($0.rawValue).tag($0) } }
                } label: { Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Select") {
                    withAnimation(.snappy) { selecting.toggle(); if !selecting { selection = [] } }
                }
                .disabled(assets.isEmpty)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if selecting {
                    Button { share.share(assets.filter { selection.contains($0.localIdentifier) }) } label: {
                        Image(systemName: "square.and.arrow.up")
                    }.disabled(selection.isEmpty)
                    Spacer()
                    Text(selection.isEmpty ? "Select Items" : Format.count(selection.count) + " selected").font(.footnote)
                    Spacer()
                    Button("Add to Collection") { showAddTo = true }.disabled(selection.isEmpty).fontWeight(.semibold)
                    Button(role: .destructive) {
                        deleter.request(assets.filter { selection.contains($0.localIdentifier) })
                    } label: { Image(systemName: "trash") }.disabled(selection.isEmpty)
                }
            }
        }
        .toolbar(selecting ? .hidden : .visible, for: .tabBar)
        .sheet(isPresented: $showAddTo) {
            AddToCollectionSheet(identifiers: Array(selection)) {
                withAnimation(.snappy) { selecting = false; selection = [] }
            }
        }
        .fullScreenCover(item: $viewer) { ViewerView(context: $0) }
        .shareSheet(share)
        .deleteFromLibrary(deleter) { ids in
            withAnimation(.snappy) { removedIDs.formUnion(ids); selection = []; selecting = false }
        }
    }
}
