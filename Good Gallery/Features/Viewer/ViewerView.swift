import SwiftUI
import SwiftData
import Photos
import AVKit

struct ViewerContext: Identifiable {
    let id = UUID()
    let assets: [PHAsset]
    let index: Int
    /// When set, the viewer offers "Remove from collection".
    var collection: MediaCollection? = nil
}

struct ViewerView: View {
    let context: ViewerContext

    @EnvironmentObject private var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @Query private var favorites: [FavoriteMedia]
    @StateObject private var share = SharePreparer()
    @StateObject private var deleter = LibraryDeleter()

    @State private var assets: [PHAsset]
    @State private var position: String?
    @State private var chromeVisible = true
    @State private var showInfo = false
    @State private var showAddTo = false
    @State private var confirmRemove = false
    @State private var favoriteBounce = 0

    init(context: ViewerContext) {
        self.context = context
        _assets = State(initialValue: context.assets)
        _position = State(initialValue: context.assets.indices.contains(context.index)
                          ? context.assets[context.index].localIdentifier : context.assets.first?.localIdentifier)
    }

    private var currentIndex: Int { assets.firstIndex { $0.localIdentifier == position } ?? 0 }
    private var current: PHAsset? { assets.indices.contains(currentIndex) ? assets[currentIndex] : nil }
    private var isFavorite: Bool {
        guard let id = current?.localIdentifier else { return false }
        return favorites.contains { $0.photoKitLocalIdentifier == id }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        MediaPage(asset: asset, isActive: asset.localIdentifier == position,
                                  chromeVisible: chromeVisible) {
                            withAnimation(.easeInOut(duration: 0.22)) { chromeVisible.toggle() }
                        }
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(asset.localIdentifier)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position)
            .ignoresSafeArea()

            if chromeVisible {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!chromeVisible)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showInfo) { if let current { MediaInfoSheet(asset: current) } }
        .sheet(isPresented: $showAddTo) {
            if let current { AddToCollectionSheet(identifiers: [current.localIdentifier]) }
        }
        .confirmationDialog("Remove from “\(context.collection?.name ?? "")”?", isPresented: $confirmRemove,
                            titleVisibility: .visible) {
            Button("Remove from Collection", role: .destructive) { removeCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The \(current?.mediaType == .video ? "video" : "photo") stays in your photo library.") }
        .shareSheet(share)
        .deleteFromLibrary(deleter) { ids in
            let idx = currentIndex
            withAnimation(.snappy) {
                assets.removeAll { ids.contains($0.localIdentifier) }
                if assets.isEmpty { dismiss() }
                else { position = assets[min(idx, assets.count - 1)].localIdentifier }
            }
        }
    }

    private var topBar: some View {
        HStack {
            circleButton("xmark", label: "Close") { dismiss() }
            Spacer()
            Text("\(currentIndex + 1) of \(assets.count)")
                .font(.footnote.weight(.medium)).monospacedDigit()
                .padding(.horizontal, 12).padding(.vertical, 7)
                .ggGlass(Capsule())
            Spacer()
            if let date = current?.creationDate {
                Text(date.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.5)
            } else { Color.clear.frame(width: 44, height: 44) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton(isFavorite ? "star.fill" : "star", label: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      tint: isFavorite ? GG.Palette.accent : .white) {
                guard let id = current?.localIdentifier else { return }
                Haptics.impact(.medium)
                favoriteBounce += 1
                store.toggleFavorite(id)
            }
            .symbolEffect(.bounce, value: favoriteBounce)
            barButton("square.and.arrow.up", label: "Share") { if let current { share.share([current]) } }
            barButton("folder.badge.plus", label: "Add to Collection") { showAddTo = true }
            barButton("info.circle", label: "Info") { showInfo = true }
            if context.collection != nil {
                barButton("minus.circle", label: "Remove from Collection") { confirmRemove = true }
            }
            barButton("trash", label: "Delete from Library", tint: .red.opacity(0.9)) {
                if let current { deleter.request([current]) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .ggGlass(Capsule())
        .padding(.bottom, 10)
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40).ggGlass(Circle(), interactive: true)
        }
        .accessibilityLabel(label)
    }

    private func barButton(_ icon: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(tint)
                .frame(width: 56, height: 46)
        }
        .accessibilityLabel(label)
    }

    private func removeCurrent() {
        guard let collection = context.collection, let id = current?.localIdentifier else { return }
        let idx = currentIndex
        store.remove([id], from: collection)
        withAnimation(.snappy) {
            assets.removeAll { $0.localIdentifier == id }
            if assets.isEmpty { dismiss() }
            else { position = assets[min(idx, assets.count - 1)].localIdentifier }
        }
    }
}

// MARK: - Pages

private struct MediaPage: View {
    let asset: PHAsset
    let isActive: Bool
    let chromeVisible: Bool
    let onTap: () -> Void

    var body: some View {
        if asset.mediaType == .video {
            VideoPage(asset: asset, isActive: isActive, chromeVisible: chromeVisible)
        } else {
            PhotoPage(asset: asset, onTap: onTap)
        }
    }
}

private struct PhotoPage: View {
    let asset: PHAsset
    let onTap: () -> Void
    @StateObject private var model = FullImageModel()
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = model.image {
                    ZoomableImageView(image: image, onTap: onTap)
                }
                if model.image == nil && !model.failed { ProgressView().tint(.white) }
                if let progress = model.progress, model.image != nil || progress > 0 {
                    VStack {
                        Spacer()
                        ProgressView(value: progress).tint(GG.Palette.accent).frame(width: 120)
                        Text("Downloading from iCloud…").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }.padding(.bottom, 90)
                }
                if model.failed {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.icloud").font(.largeTitle)
                        Text("This photo couldn't be loaded.").font(.footnote)
                    }.foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                let pixels = CGSize(width: proxy.size.width * scale * 1.5, height: proxy.size.height * scale * 1.5)
                model.load(asset, targetPixels: pixels)
            }
            .onDisappear { model.cancel() }
        }
    }
}

private struct VideoPage: View {
    let asset: PHAsset
    let isActive: Bool
    let chromeVisible: Bool
    @State private var player: AVPlayer?
    @State private var poster: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let player {
                NativeVideoPlayer(player: player)
                    .padding(.top, 56)
                    .padding(.bottom, 84)          // keep clear of our bottom bar
            } else if let poster {
                Image(uiImage: poster).resizable().scaledToFit().overlay { ProgressView().tint(.white) }
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.icloud").font(.largeTitle)
                    Text("This video couldn't be loaded.").font(.footnote)
                }.foregroundStyle(.white.opacity(0.7))
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: isActive) {
            if isActive {
                if poster == nil { poster = await ImageLoader.shared.thumbnail(for: asset, pixels: 900) }
                if player == nil { await loadPlayer() }
                PlaybackAudio.activate()
                player?.play()
            } else {
                player?.pause()
                player?.seek(to: .zero, completionHandler: { _ in })
            }
        }
        .onDisappear { player?.pause() }
    }

    private func loadPlayer() async {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        let item: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
        if let item {
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.actionAtItemEnd = .pause
            player = newPlayer
        } else { failed = true }
    }
}
