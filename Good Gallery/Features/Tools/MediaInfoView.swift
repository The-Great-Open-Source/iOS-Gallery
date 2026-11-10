import SwiftUI
import Photos
import CoreLocation

struct MediaInfoContent: View {
    let info: MediaInfo

    var body: some View {
        VStack(spacing: 14) {
            GGCard {
                VStack(spacing: 6) {
                    if let name = info.filename { InfoRow(label: "File name", value: name) }
                    InfoRow(label: "Type", value: typeText)
                    if let format = info.format { InfoRow(label: "Format", value: format) }
                    InfoRow(label: "Resolution", value: info.resolutionText + (info.megapixels.map { " (\($0))" } ?? ""))
                    if let date = info.creationDate {
                        InfoRow(label: "Created", value: date.formatted(date: .long, time: .shortened))
                    }
                    InfoRow(label: "File size", value: info.fileSize.map(Format.bytes) ?? info.fileSizeNote ?? "Unavailable")
                }
            }
            if info.isVideo {
                GGCard {
                    VStack(spacing: 6) {
                        if let d = info.duration { InfoRow(label: "Duration", value: Format.duration(d)) }
                        if let fps = info.frameRate, fps > 0 { InfoRow(label: "Frame rate", value: String(format: "%.0f fps", fps)) }
                        if let codec = info.codec { InfoRow(label: "Codec", value: codec) }
                        if let audio = info.hasAudio { InfoRow(label: "Audio", value: audio ? "Yes" : "None") }
                    }
                }
            }
            if let location = info.location {
                GGCard {
                    VStack(spacing: 6) {
                        InfoRow(label: "Latitude", value: String(format: "%.5f°", location.latitude))
                        InfoRow(label: "Longitude", value: String(format: "%.5f°", location.longitude))
                    }
                }
            }
        }
    }

    private var typeText: String {
        if info.isVideo { return "Video" }
        if info.isLivePhoto { return "Live Photo" }
        if info.isScreenshot { return "Screenshot" }
        return "Photo"
    }
}

/// Loads info for one asset and renders it.
struct MediaInfoLoader: View {
    let asset: PHAsset
    @State private var info: MediaInfo?

    var body: some View {
        Group {
            if let info { MediaInfoContent(info: info).transition(.opacity) }
            else { ProgressView().tint(GG.Palette.accent).padding(40) }
        }
        .animation(.easeOut(duration: 0.2), value: info == nil)
        .task(id: asset.localIdentifier) { info = await MediaInfo.load(for: asset) }
    }
}

struct MediaInfoSheet: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MediaInfoLoader(asset: asset).padding(GG.Spacing.page)
            }
            .ggScreen()
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
