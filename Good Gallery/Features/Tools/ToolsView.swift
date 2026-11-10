import SwiftUI
import Photos

struct ToolsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { VideoCompressorView() } label: {
                    ToolRow(icon: "arrow.down.right.and.arrow.up.left", color: .orange,
                            title: "Video Compressor", subtitle: "Make large videos smaller")
                }
                NavigationLink { MediaInspectorView() } label: {
                    ToolRow(icon: "info.circle.fill", color: .blue,
                            title: "Media Inspector", subtitle: "Resolution, codec, size and dates")
                }
            }
        }
        .tint(GG.Palette.accent)
        .scrollContentBackground(.hidden)
        .background(GGBackground(grouped: true))
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings-style row: coloured rounded-square icon, title and subtitle.
struct ToolRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
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
                    EmptyStateView(icon: "info.circle", title: "Media Inspector",
                                   message: "Choose a photo or video to see its details.",
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
