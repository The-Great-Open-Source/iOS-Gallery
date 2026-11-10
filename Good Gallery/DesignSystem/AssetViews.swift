import SwiftUI
import Photos

/// A square, lazily-loaded thumbnail for a PHAsset with optional selection/favourite/video decorations.
struct AssetThumbnail: View {
    let asset: PHAsset
    var isSelecting = false
    var isSelected = false
    var isFavorite = false
    var isDisabled = false
    var pixels: CGFloat = 330

    @State private var image: UIImage?

    var body: some View {
        Color(GG.Palette.surface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Pill(text: Format.duration(asset.duration), systemImage: "play.fill").padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isFavorite && !isSelecting {
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(GG.Palette.accent)
                        .shadow(radius: 2).padding(5)
                }
            }
            .overlay {
                if isDisabled { Color.black.opacity(0.55) }
                if isSelected { Rectangle().strokeBorder(GG.Palette.accent, lineWidth: 3) }
            }
            .overlay(alignment: .topTrailing) {
                if isDisabled {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.white.opacity(0.8)).padding(5)
                } else if isSelecting {
                    SelectionBadge(isSelected: isSelected).padding(5)
                }
            }
            .animation(.snappy(duration: 0.18), value: isSelected)
            .animation(.easeOut(duration: 0.2), value: image == nil)
            .task(id: asset.localIdentifier) {
                image = nil
                image = await ImageLoader.shared.thumbnail(for: asset, pixels: pixels)
            }
            .contentShape(Rectangle())
            .accessibilityLabel(asset.mediaType == .video ? "Video" : "Photo")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SelectionBadge: View {
    let isSelected: Bool
    var body: some View {
        ZStack {
            Circle().fill(isSelected ? GG.Palette.accent : Color.black.opacity(0.3))
            Circle().strokeBorder(.white.opacity(isSelected ? 0 : 0.9), lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(GG.Palette.onAccent)
            }
        }
        .frame(width: 22, height: 22)
        .scaleEffect(isSelected ? 1 : 0.92)
    }
}

/// Grid of assets with tap-to-open and multi-selection.
struct AssetGrid: View {
    let assets: [PHAsset]
    var favorites: Set<String> = []
    var isSelecting = false
    @Binding var selection: Set<String>
    var onOpen: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: GG.Spacing.grid)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: GG.Spacing.grid) {
            ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                let id = asset.localIdentifier
                AssetThumbnail(asset: asset, isSelecting: isSelecting, isSelected: selection.contains(id),
                               isFavorite: favorites.contains(id))
                    .onTapGesture {
                        if isSelecting {
                            Haptics.selection()
                            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                        } else {
                            onOpen(index)
                        }
                    }
            }
        }
    }
}

/// Cover image for a collection/album card, loaded by identifier. It fills whatever frame the caller gives it
/// and never influences layout itself.
struct CoverImage: View {
    let identifier: String?
    var pixels: CGFloat = 600
    @State private var image: UIImage?

    var body: some View {
        GG.Palette.surface
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                } else {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.25), value: image == nil)
            .task(id: identifier) {
                image = nil
                guard let identifier else { return }
                image = await ImageLoader.shared.thumbnail(forIdentifier: identifier, pixels: pixels)
            }
    }
}

struct LoadingGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: GG.Spacing.grid)], spacing: GG.Spacing.grid) {
            ForEach(0..<18, id: \.self) { _ in
                Color(GG.Palette.surface).aspectRatio(1, contentMode: .fit)
            }
        }
        .redacted(reason: .placeholder)
    }
}
