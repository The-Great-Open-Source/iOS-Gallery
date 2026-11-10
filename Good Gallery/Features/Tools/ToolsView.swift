import SwiftUI

struct ToolsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NavigationLink { VideoCompressorView() } label: {
                    ToolCard(icon: "arrow.down.right.and.arrow.up.left.video", title: "Video Compressor",
                             text: "Make large videos smaller.")
                }
                NavigationLink { MediaInspectorView() } label: {
                    ToolCard(icon: "info.viewfinder", title: "Media Inspector",
                             text: "Resolution, codec, size and dates.")
                }
            }
            .buttonStyle(PressableStyle())
            .padding(GG.Spacing.page)
        }
        .ggScreen()
        .navigationTitle("Tools")
    }
}

struct ToolCard: View {
    let icon: String, title: String, text: String
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon).font(.system(size: 24, weight: .regular))
                .foregroundStyle(GG.Palette.accent).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(text).font(.subheadline).foregroundStyle(GG.Palette.secondaryText)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GG.Palette.surface, in: RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
    }
}

struct MediaInspectorView: View {
    @State private var asset: PHAsset?
    @State private var showPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let asset {
                    CoverImage(identifier: asset.localIdentifier, pixels: 900)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
                    MediaInfoLoader(asset: asset)
                    Button("Choose Another") { showPicker = true }.buttonStyle(GGSecondaryButtonStyle())
                } else {
                    EmptyStateView(icon: "info.viewfinder", title: "Inspect any media",
                                   message: "Pick a photo or video to see its technical details.",
                                   actionTitle: "Choose Media") { showPicker = true }
                        .padding(.top, 60)
                }
            }
            .padding(GG.Spacing.page)
        }
        .ggScreen()
        .navigationTitle("Media Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            MediaPickerView(title: "Choose Media", mode: .single, confirmTitle: { _ in "Inspect" }) { ids in
                if let id = ids.first { asset = Assets.asset(id) }
            }
        }
    }
}

import Photos
