import SwiftUI
import SwiftData

enum LibraryRoute: Hashable { case uncategorized }

struct LibraryView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var store: CollectionStore
    @Query(sort: \MediaCollection.sortOrder) private var collections: [MediaCollection]
    @Query private var allItems: [CollectionMedia]
    @StateObject private var uncategorized = UncategorizedModel()
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
            VStack(alignment: .leading, spacing: 28) {
                LimitedAccessBanner()

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

                uncategorizedSection
            }
            .padding(.horizontal, GG.Spacing.page)
            .padding(.bottom, 30)
        }
        .ggScreen()
        .navigationTitle("Library")
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
        .navigationDestination(for: LibraryRoute.self) { _ in
            UncategorizedView(model: uncategorized)
        }
        .task(id: RefreshKey(count: allItems.count, token: library.changeToken, ids: allItems.first?.photoKitLocalIdentifier.hashValue ?? 0)) {
            await uncategorized.refresh(organized: Set(allItems.map(\.photoKitLocalIdentifier)))
        }
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

    private var uncategorizedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Uncategorized")
            NavigationLink(value: LibraryRoute.uncategorized) {
                HStack(spacing: 14) {
                    CoverImage(identifier: uncategorized.assets.first?.localIdentifier, pixels: 200)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not Yet Organised").font(.body).foregroundStyle(.primary)
                        Text(uncategorized.hasLoaded ? Format.count(uncategorized.assets.count) : "Counting…")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(GG.Palette.surface, in: RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
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

struct UncategorizedView: View {
    @ObservedObject var model: UncategorizedModel
    @EnvironmentObject private var store: CollectionStore
    @Query private var favorites: [FavoriteMedia]
    @StateObject private var share = SharePreparer()
    @StateObject private var deleter = LibraryDeleter()
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var viewer: ViewerContext?
    @State private var showAddTo = false

    var body: some View {
        ScrollView {
            if !model.hasLoaded {
                LoadingGrid()
            } else if model.assets.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: "All Organised",
                               message: "Every photo and video you've shared with Good Gallery belongs to a collection.")
                    .padding(.top, 80)
            } else {
                AssetGrid(assets: model.assets, favorites: Set(favorites.map(\.photoKitLocalIdentifier)),
                          isSelecting: selecting, selection: $selection) { index in
                    viewer = ViewerContext(assets: model.assets, index: index)
                }
            }
        }
        .ggScreen()
        .navigationTitle("Uncategorized")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Select") {
                    withAnimation(.snappy) { selecting.toggle(); if !selecting { selection = [] } }
                }
                .disabled(model.assets.isEmpty)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if selecting {
                    Button { share.share(model.assets.filter { selection.contains($0.localIdentifier) }) } label: {
                        Image(systemName: "square.and.arrow.up")
                    }.disabled(selection.isEmpty)
                    Spacer()
                    Text(selection.isEmpty ? "Select Items" : Format.count(selection.count) + " selected").font(.footnote)
                    Spacer()
                    Button("Add to Collection") { showAddTo = true }.disabled(selection.isEmpty).fontWeight(.semibold)
                    Button(role: .destructive) {
                        deleter.request(model.assets.filter { selection.contains($0.localIdentifier) })
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
        .deleteFromLibrary(deleter) { _ in selection = []; selecting = false }
    }
}
