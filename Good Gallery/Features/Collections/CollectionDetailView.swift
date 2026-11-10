import SwiftUI
import SwiftData
import Photos

struct CollectionDetailView: View {
    let collection: MediaCollection

    @EnvironmentObject private var store: CollectionStore
    @EnvironmentObject private var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    @Query private var favorites: [FavoriteMedia]
    @StateObject private var resolved = ResolvedAssets()
    @StateObject private var share = SharePreparer()
    @StateObject private var deleter = LibraryDeleter()

    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var viewer: ViewerContext?
    @State private var showPicker = false
    @State private var showEdit = false
    @State private var showCoverPicker = false
    @State private var showStats = false
    @State private var showBackup = false
    @State private var showAddTo = false
    @State private var confirmDelete = false
    @State private var confirmRemoveSelected = false
    @State private var confirmPrune = false

    private struct LoadKey: Hashable { let count: Int; let updated: Date; let sort: MediaSort; let token: Int }

    private var orderedIdentifiers: [String] {
        collection.items.sorted { $0.addedAt > $1.addedAt }.map(\.photoKitLocalIdentifier)
    }
    private var photoCount: Int { resolved.assets.filter { $0.mediaType == .image }.count }
    private var videoCount: Int { resolved.assets.filter { $0.mediaType == .video }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    if !collection.details.isEmpty {
                        Text(collection.details).font(.subheadline).foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, GG.Spacing.page)

                if !resolved.missingIdentifiers.isEmpty { unavailableBanner.padding(.horizontal, GG.Spacing.page) }

                if !resolved.hasLoaded && !collection.items.isEmpty {
                    LoadingGrid()
                } else if resolved.assets.isEmpty {
                    EmptyStateView(icon: "photo.on.rectangle.angled", title: "No Photos",
                                   message: "Add photos and videos from your library.",
                                   actionTitle: "Add Photos") { showPicker = true }
                } else {
                    AssetGrid(assets: resolved.assets, favorites: Set(favorites.map(\.photoKitLocalIdentifier)),
                              isSelecting: selecting, selection: $selection) { index in
                        viewer = ViewerContext(assets: resolved.assets, index: index, collection: collection)
                    }
                }
            }
            .padding(.bottom, 30)
        }
        .ggScreen()
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbar }
        .toolbar(selecting ? .hidden : .visible, for: .tabBar)
        .task(id: LoadKey(count: collection.items.count, updated: collection.updatedAt,
                          sort: collection.sortMode, token: library.changeToken)) {
            await resolved.load(identifiers: orderedIdentifiers, sort: collection.sortMode)
            #if DEBUG
            if let n = DebugHarness.value("-gg-viewer").flatMap(Int.init), viewer == nil, resolved.assets.indices.contains(n) {
                viewer = ViewerContext(assets: resolved.assets, index: n, collection: collection)
            }
            #endif
        }
        .sheet(isPresented: $showPicker) {
            MediaPickerView(title: "Add to \(collection.name)",
                            disabledIdentifiers: Set(collection.items.map(\.photoKitLocalIdentifier))) { ids in
                withAnimation(.snappy) { _ = store.add(ids, to: collection) }
            }
        }
        .sheet(isPresented: $showEdit) { CollectionEditorSheet(mode: .edit(collection)) }
        .sheet(isPresented: $showCoverPicker) {
            MediaPickerView(title: "Change Cover", mode: .single, initialFilter: .photos,
                            confirmTitle: { _ in "Use as Cover" }) { ids in
                if let id = ids.first { store.setCover(collection, identifier: id) }
            }
        }
        .sheet(isPresented: $showStats) {
            CollectionStatsSheet(collection: collection, assets: resolved.assets, missing: resolved.missingIdentifiers.count)
        }
        .sheet(isPresented: $showBackup) { BackupSheet(assets: resolved.assets, folderName: collection.name) }
        .sheet(isPresented: $showAddTo) {
            AddToCollectionSheet(identifiers: Array(selection)) {
                withAnimation(.snappy) { selecting = false; selection = [] }
            }
        }
        .fullScreenCover(item: $viewer) { ViewerView(context: $0) }
        .confirmationDialog("Delete “\(collection.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) {
                let target = collection
                dismiss()
                Task { try? await Task.sleep(for: .milliseconds(450)); store.delete(target) }
            }
        } message: { Text("Your photos and videos stay safely in your library. Only the collection is removed.") }
        .confirmationDialog("Remove \(Format.count(selection.count)) from this collection?",
                            isPresented: $confirmRemoveSelected, titleVisibility: .visible) {
            Button("Remove from Collection", role: .destructive) {
                withAnimation(.snappy) { store.remove(selection, from: collection); selection = []; selecting = false }
            }
        } message: { Text("They stay in your photo library.") }
        .confirmationDialog("Remove unavailable items?", isPresented: $confirmPrune, titleVisibility: .visible) {
            Button("Remove \(resolved.missingIdentifiers.count) Unavailable", role: .destructive) {
                store.prune(resolved.missingIdentifiers, from: collection)
            }
        } message: { Text("These photos were deleted from your library. This only updates the collection.") }
        .shareSheet(share)
        .deleteFromLibrary(deleter) { ids in
            withAnimation(.snappy) { resolved.remove(ids); selection = []; selecting = false }
        }
    }

    // MARK: Pieces

    private var subtitle: String {
        var parts = [Format.count(collection.items.count)]
        if resolved.hasLoaded, photoCount > 0, videoCount > 0 {
            parts.append(Format.count(photoCount, "photo"))
            parts.append(Format.count(videoCount, "video"))
        }
        return parts.joined(separator: " · ")
    }

    private var unavailableBanner: some View {
        GGCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(Format.count(resolved.missingIdentifiers.count)) unavailable", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(GG.Palette.accent)
                if library.isFull {
                    Text("These photos or videos no longer exist in your library.")
                        .font(.footnote).foregroundStyle(GG.Palette.secondaryText)
                    Button("Remove from Collection") { confirmPrune = true }
                        .buttonStyle(GGSecondaryButtonStyle(fullWidth: false)).font(.footnote)
                } else {
                    Text("They may be outside the photos you've shared with Good Gallery. Share more photos or allow full access to see them. Nothing has been removed.")
                        .font(.footnote).foregroundStyle(GG.Palette.secondaryText)
                    Button("Select More Photos") { library.presentLimitedPicker() }
                        .buttonStyle(GGSecondaryButtonStyle(fullWidth: false)).font(.footnote)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(selecting ? "Done" : "Select") {
                withAnimation(.snappy) { selecting.toggle(); if !selecting { selection = [] } }
            }
            .fontWeight(selecting ? .semibold : .regular)
            .disabled(resolved.assets.isEmpty)
        }
        if !selecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showPicker = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add Photos")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Menu {
                        Picker("Sort", selection: Binding(get: { collection.sortMode }, set: { store.setSort(collection, $0) })) {
                            ForEach(MediaSort.allCases) { Text($0.title).tag($0) }
                        }
                    } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                    Divider()
                    Button { showEdit = true } label: { Label("Rename & Describe", systemImage: "pencil") }
                    Button { showCoverPicker = true } label: { Label("Change Cover", systemImage: "photo") }
                    Button { showStats = true } label: { Label("Statistics", systemImage: "chart.bar") }
                    Button { showBackup = true } label: { Label("Back Up…", systemImage: "icloud.and.arrow.up") }
                        .disabled(resolved.assets.isEmpty)
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Collection", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            if selecting {
                Button { share.share(resolved.assets.filter { selection.contains($0.localIdentifier) }) } label: {
                    Image(systemName: "square.and.arrow.up")
                }.disabled(selection.isEmpty)
                Button { showAddTo = true } label: { Image(systemName: "folder.badge.plus") }.disabled(selection.isEmpty)
                Button {
                    if selection.count == 1, let id = selection.first { store.setCover(collection, identifier: id); Haptics.success() }
                } label: { Image(systemName: "photo") }.disabled(selection.count != 1)
                Spacer()
                Text(selection.isEmpty ? "Select Items" : Format.count(selection.count) + " selected").font(.footnote)
                Spacer()
                Menu {
                    Button { confirmRemoveSelected = true } label: { Label("Remove from Collection", systemImage: "minus.circle") }
                    Button(role: .destructive) {
                        deleter.request(resolved.assets.filter { selection.contains($0.localIdentifier) })
                    } label: { Label("Delete from Library", systemImage: "trash") }
                } label: { Image(systemName: "trash") }
                    .disabled(selection.isEmpty)
            }
        }
    }
}

struct CollectionStatsSheet: View {
    let collection: MediaCollection
    let assets: [PHAsset]
    let missing: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let photos = assets.filter { $0.mediaType == .image }.count
        let videos = assets.filter { $0.mediaType == .video }
        let dates = assets.compactMap(\.creationDate)
        NavigationStack {
            ScrollView {
                GGCard {
                    VStack(spacing: 6) {
                        InfoRow(label: "Total items", value: collection.items.count.formatted())
                        InfoRow(label: "Photos", value: photos.formatted())
                        InfoRow(label: "Videos", value: videos.count.formatted())
                        if !videos.isEmpty {
                            InfoRow(label: "Total video length", value: Format.duration(videos.reduce(0) { $0 + $1.duration }))
                        }
                        if let first = dates.min(), let last = dates.max() {
                            InfoRow(label: "Earliest", value: first.formatted(date: .abbreviated, time: .omitted))
                            InfoRow(label: "Latest", value: last.formatted(date: .abbreviated, time: .omitted))
                        }
                        InfoRow(label: "Created", value: collection.createdAt.formatted(date: .abbreviated, time: .omitted))
                        if missing > 0 { InfoRow(label: "Unavailable", value: missing.formatted()) }
                    }
                }
                .padding(GG.Spacing.page)
            }
            .ggScreen()
            .navigationTitle(collection.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
