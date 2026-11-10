import SwiftUI
import SwiftData
import Photos

struct FavoritesView: View {
    @EnvironmentObject private var store: CollectionStore
    @EnvironmentObject private var library: PhotoLibrary
    @Query(sort: \FavoriteMedia.createdAt, order: .reverse) private var favorites: [FavoriteMedia]
    @StateObject private var resolved = ResolvedAssets()
    @StateObject private var share = SharePreparer()
    @StateObject private var deleter = LibraryDeleter()
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var viewer: ViewerContext?
    @State private var showAddTo = false

    private struct LoadKey: Hashable { let ids: [String]; let token: Int }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Good Gallery favorites are separate from the ♥︎ in Apple Photos. Favoriting here never changes your Photos library.",
                      systemImage: "star")
                    .font(.footnote).foregroundStyle(GG.Palette.secondaryText)
                    .padding(.horizontal, GG.Spacing.page)

                if favorites.isEmpty {
                    EmptyStateView(icon: "star", title: "No favorites yet",
                                   message: "Open any photo or video and tap the star to keep it here.")
                        .padding(.top, 50)
                } else if !resolved.hasLoaded {
                    LoadingGrid()
                } else {
                    AssetGrid(assets: resolved.assets, isSelecting: selecting, selection: $selection) { index in
                        viewer = ViewerContext(assets: resolved.assets, index: index)
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .ggScreen()
        .navigationTitle("Favorites")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Select") {
                    withAnimation(.snappy) { selecting.toggle(); if !selecting { selection = [] } }
                }.disabled(resolved.assets.isEmpty)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if selecting {
                    Button { share.share(resolved.assets.filter { selection.contains($0.localIdentifier) }) } label: {
                        Image(systemName: "square.and.arrow.up")
                    }.disabled(selection.isEmpty)
                    Button { showAddTo = true } label: { Image(systemName: "folder.badge.plus") }.disabled(selection.isEmpty)
                    Spacer()
                    Text(selection.isEmpty ? "Select Items" : Format.count(selection.count) + " selected").font(.footnote)
                    Spacer()
                    Menu {
                        Button {
                            store.setFavorite(Array(selection), false)
                            selection = []; selecting = false
                        } label: { Label("Remove from Favorites", systemImage: "star.slash") }
                        Button(role: .destructive) {
                            deleter.request(resolved.assets.filter { selection.contains($0.localIdentifier) })
                        } label: { Label("Delete from Library", systemImage: "trash") }
                    } label: { Image(systemName: "trash") }.disabled(selection.isEmpty)
                }
            }
        }
        .toolbar(selecting ? .hidden : .visible, for: .tabBar)
        .task(id: LoadKey(ids: favorites.map(\.photoKitLocalIdentifier), token: library.changeToken)) {
            await resolved.load(identifiers: favorites.map(\.photoKitLocalIdentifier))
        }
        .sheet(isPresented: $showAddTo) {
            AddToCollectionSheet(identifiers: Array(selection)) { selection = []; selecting = false }
        }
        .fullScreenCover(item: $viewer) { ViewerView(context: $0) }
        .shareSheet(share)
        .deleteFromLibrary(deleter) { _ in selection = []; selecting = false }
    }
}
