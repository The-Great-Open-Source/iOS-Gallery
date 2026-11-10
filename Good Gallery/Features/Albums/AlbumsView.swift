import SwiftData
import SwiftUI
import Photos

struct AlbumInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
    let coverIdentifier: String?
    let collection: PHAssetCollection
    static func == (l: AlbumInfo, r: AlbumInfo) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
final class AlbumsModel: ObservableObject {
    @Published private(set) var smart: [AlbumInfo] = []
    @Published private(set) var user: [AlbumInfo] = []
    @Published private(set) var hasLoaded = false

    func load() async {
        let result = await Task.detached(priority: .userInitiated) { () -> ([AlbumInfo], [AlbumInfo]) in
            func infos(_ fetch: PHFetchResult<PHAssetCollection>, hideEmpty: Bool) -> [AlbumInfo] {
                var out: [AlbumInfo] = []
                fetch.enumerateObjects { collection, _, _ in
                    let options = PHFetchOptions()
                    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                    options.fetchLimit = 1
                    let cover = PHAsset.fetchAssets(in: collection, options: options).firstObject
                    let count = PHAsset.fetchAssets(in: collection, options: nil).count
                    if hideEmpty && count == 0 { return }
                    out.append(AlbumInfo(id: collection.localIdentifier, title: collection.localizedTitle ?? "Untitled",
                                         count: count, coverIdentifier: cover?.localIdentifier, collection: collection))
                }
                return out
            }
            let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
            let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            return (infos(smart, hideEmpty: true), infos(user, hideEmpty: true))
        }.value
        smart = result.0
        user = result.1
        hasLoaded = true
    }
}

struct AlbumsView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @StateObject private var model = AlbumsModel()
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LimitedAccessBanner()
                if !model.hasLoaded {
                    ProgressView().tint(GG.Palette.accent).frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    if !model.user.isEmpty { section("My Albums", model.user) }
                    if !model.smart.isEmpty { section("Smart Albums", model.smart) }
                    if model.user.isEmpty && model.smart.isEmpty {
                        EmptyStateView(icon: "rectangle.stack", title: "No albums",
                                       message: "No Apple Photos albums are available to Good Gallery.")
                    }
                }
            }
            .padding(.horizontal, GG.Spacing.page).padding(.bottom, 30)
        }
        .ggScreen()
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AlbumInfo.self) { AlbumDetailView(album: $0) }
        .task(id: library.changeToken) { await model.load() }
    }

    private func section(_ title: String, _ albums: [AlbumInfo]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        VStack(alignment: .leading, spacing: 8) {
                            CoverImage(identifier: album.coverIdentifier, pixels: 500)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(album.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                Text(album.count.formatted()).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

struct AlbumDetailView: View {
    let album: AlbumInfo
    @EnvironmentObject private var library: PhotoLibrary
    @Query private var favorites: [FavoriteMedia]
    @StateObject private var share = SharePreparer()
    @StateObject private var deleter = LibraryDeleter()
    @State private var assets: [PHAsset] = []
    @State private var loaded = false
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var viewer: ViewerContext?
    @State private var showAddTo = false

    var body: some View {
        ScrollView {
            if !loaded { LoadingGrid() }
            else if assets.isEmpty {
                EmptyStateView(icon: "photo", title: "Empty Album", message: "This album has no photos or videos.").padding(.top, 60)
            } else {
                AssetGrid(assets: assets, favorites: Set(favorites.map(\.photoKitLocalIdentifier)),
                          isSelecting: selecting, selection: $selection) { index in
                    viewer = ViewerContext(assets: assets, index: index)
                }
            }
        }
        .ggScreen()
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Select") {
                    withAnimation(.snappy) { selecting.toggle(); if !selecting { selection = [] } }
                }.disabled(assets.isEmpty)
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
        .task(id: library.changeToken) {
            let collection = album.collection
            assets = await Task.detached(priority: .userInitiated) {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                var out: [PHAsset] = []
                PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { a, _, _ in out.append(a) }
                return out
            }.value
            loaded = true
        }
        .sheet(isPresented: $showAddTo) {
            AddToCollectionSheet(identifiers: Array(selection)) { selection = []; selecting = false }
        }
        .fullScreenCover(item: $viewer) { ViewerView(context: $0) }
        .shareSheet(share)
        .deleteFromLibrary(deleter) { _ in selection = []; selecting = false }
    }
}
