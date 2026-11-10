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

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private struct RefreshKey: Hashable { let count: Int; let token: Int; let ids: Int }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("A better home for your memories.")
                    .font(GG.Typography.editorial(16)).italic()
                    .foregroundStyle(GG.Palette.accent)
                    .padding(.top, -6)

                LimitedAccessBanner()

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionHeader(title: "Collections")
                        Button { showCreate = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .ggGlass(Circle(), interactive: true)
                        }
                        .accessibilityLabel("New Collection")
                    }
                    if collections.isEmpty {
                        firstRunEmptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(collections) { collection in
                                NavigationLink(value: collection) {
                                    CollectionCard(collection: collection)
                                        .zoomSource(id: collection.id, in: zoom)
                                }
                                .buttonStyle(PressableStyle())
                                .contextMenu { menu(for: collection) }
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
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
        .navigationTitle("Good Gallery")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search")
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
        VStack(spacing: 6) {
            EmptyStateView(
                icon: "square.stack.3d.up",
                title: "Create your first collection",
                message: "Travel, Family, University, Cars — group your photos and videos around what matters to you. Originals never move.",
                actionTitle: "New Collection") { showCreate = true }
        }
        .ggGlass(RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
    }

    private var uncategorizedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Uncategorized")
            NavigationLink(value: LibraryRoute.uncategorized) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                        if let first = uncategorized.assets.first {
                            CoverImage(identifier: first.localIdentifier, pixels: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            Image(systemName: "tray").foregroundStyle(GG.Palette.accent)
                        }
                    }
                    .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Not yet organised").font(.body.weight(.medium)).foregroundStyle(GG.Palette.text)
                        Text(uncategorized.hasLoaded ? Format.count(uncategorized.assets.count) : "Counting…")
                            .font(.subheadline).foregroundStyle(GG.Palette.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(GG.Palette.secondaryText)
                }
                .padding(12)
                .ggGlass(RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }
}

struct CollectionCard: View {
    let collection: MediaCollection

    var body: some View {
        CoverImage(identifier: collection.effectiveCoverIdentifier)
            .aspectRatio(0.88, contentMode: .fit)
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(GG.Typography.editorial(20, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(Format.count(collection.items.count))
                        .font(.caption).opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ggGlass(RoundedRectangle(cornerRadius: GG.Radius.card - 6, style: .continuous))
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
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
                Text("Select photos, then add them to a collection. Nothing is moved automatically.")
                    .font(.footnote).foregroundStyle(GG.Palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, GG.Spacing.page).padding(.bottom, 8)
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
