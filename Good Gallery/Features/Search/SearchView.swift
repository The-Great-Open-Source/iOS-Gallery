import SwiftUI
import SwiftData
import Photos

struct SearchView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var index: MediaSearchIndex
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MediaCollection.sortOrder) private var collections: [MediaCollection]
    @StateObject private var albums = AlbumsModel()
    @StateObject private var resolved = ResolvedAssets()

    @State private var query = ""
    @State private var viewer: ViewerContext?
    @State private var openCollection: MediaCollection?
    @State private var openAlbum: AlbumInfo?
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matchedCollections: [MediaCollection] {
        collections.filter { $0.name.localizedCaseInsensitiveContains(trimmed) || $0.details.localizedCaseInsensitiveContains(trimmed) }
    }
    private var matchedAlbums: [AlbumInfo] {
        (albums.user + albums.smart).filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
    private var mediaHits: [MediaSearchIndex.Entry] { index.search(trimmed) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if trimmed.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "Search Good Gallery",
                                   message: "Find collections, Apple Photos albums, file names, months and years (“June 2025”), or types like “video” and “screenshot”.")
                        .padding(.top, 60)
                } else if matchedCollections.isEmpty && matchedAlbums.isEmpty && mediaHits.isEmpty {
                    if index.isIndexing {
                        ProgressView("Searching your library…").tint(GG.Palette.accent).padding(.top, 80)
                    } else {
                        EmptyStateView(icon: "magnifyingglass", title: "No Results", message: "Nothing matched “\(trimmed)”.")
                            .padding(.top, 60)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 26) {
                        if !matchedCollections.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Collections")
                                ForEach(matchedCollections) { collection in
                                    resultRow(title: collection.name, subtitle: Format.count(collection.items.count),
                                              cover: collection.effectiveCoverIdentifier) { openCollection = collection }
                                }
                            }
                        }
                        if !matchedAlbums.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Apple Photos Albums")
                                ForEach(matchedAlbums) { album in
                                    resultRow(title: album.title, subtitle: Format.count(album.count),
                                              cover: album.coverIdentifier) { openAlbum = album }
                                }
                            }
                        }
                        if !mediaHits.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Photos & Videos", trailing: index.isIndexing ? "Still indexing…" : nil)
                                AssetGrid(assets: resolved.assets, isSelecting: false, selection: .constant([])) { i in
                                    viewer = ViewerContext(assets: resolved.assets, index: i)
                                }
                                .padding(.horizontal, -GG.Spacing.page)
                            }
                        }
                    }
                    .padding(GG.Spacing.page)
                }
            }
            .ggScreen()
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Collections, albums, files, dates")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(item: $openCollection) { CollectionDetailView(collection: $0) }
            .navigationDestination(item: $openAlbum) { AlbumDetailView(album: $0) }
            .task { await albums.load() }
            .task(id: library.changeToken) { index.buildIfNeeded(changeToken: library.changeToken) }
            .task(id: SearchKey(query: trimmed, count: index.entries.count)) {
                let ids = mediaHits.map(\.identifier)
                await resolved.load(identifiers: ids)
            }
        }
        .fullScreenCover(item: $viewer) { ViewerView(context: $0) }
    }

    private struct SearchKey: Hashable { let query: String; let count: Int }

    private func resultRow(title: String, subtitle: String, cover: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                CoverImage(identifier: cover, pixels: 160).frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(GG.Palette.text)
                    Text(subtitle).font(.caption).foregroundStyle(GG.Palette.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(GG.Palette.secondaryText)
            }
            .padding(10)
            .ggGlass(RoundedRectangle(cornerRadius: GG.Radius.control, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}
