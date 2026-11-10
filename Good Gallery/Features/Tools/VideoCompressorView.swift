import SwiftUI
import AVKit
import Photos

struct VideoCompressorView: View {
    /// Optionally start with a video already chosen (e.g. from Largest Files).
    var initialIdentifier: String? = nil
    @EnvironmentObject private var store: CollectionStore
    @StateObject private var model = VideoCompressorViewModel()
    @State private var showPicker = false
    @State private var showExporter = false
    @State private var showPreview = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                switch model.stage {
                case .empty: emptyState
                case .loading(let progress): loading(progress)
                case .ready: readyContent
                case .compressing(let progress): compressing(progress)
                case .done: doneContent
                case .failed(let message): failure(message)
                }
            }
            .frame(maxWidth: .infinity)          // keep full width in every stage (compressing/done/failed)
            .padding(GG.Spacing.page)
            .animation(.snappy(duration: 0.3), value: model.stage)
        }
        .ggScreen()
        .navigationTitle("Video Compressor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.context = store }
        .task {
            if let id = initialIdentifier, case .empty = model.stage { model.select(identifier: id) }
        }
        .onDisappear { if case .compressing = model.stage {} else { model.sourcePlayer?.pause() } }
        .sheet(isPresented: $showPicker) {
            MediaPickerView(title: "Choose a Video", mode: .single, initialFilter: .videos, allowedFilters: [.videos],
                            confirmTitle: { _ in "Choose Video" }) { ids in
                if let id = ids.first { model.select(identifier: id) }
            }
        }
        .sheet(isPresented: $showExporter) {
            if let url = model.outputURL { FileExporter(url: url) { _ in showExporter = false }.ignoresSafeArea() }
        }
        .sheet(isPresented: $showPreview) {
            if let url = model.outputURL { OutputPreview(url: url) }
        }
        .alert("Notice", isPresented: Binding(get: { model.statusMessage != nil }, set: { if !$0 { model.statusMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.statusMessage ?? "") }
    }

    // MARK: Stages

    private var emptyState: some View {
        EmptyStateView(icon: "arrow.down.right.and.arrow.up.left.video", title: "Compress a video",
                       message: "Choose a video from your library. Compression happens on this device and your original stays untouched.",
                       actionTitle: "Choose Video") { showPicker = true }
            .padding(.top, 50)
    }

    private func loading(_ progress: Double?) -> some View {
        VStack(spacing: 14) {
            ProgressView().tint(GG.Palette.accent)
            Text(progress != nil ? "Downloading from iCloud…" : "Loading video…")
                .font(.subheadline).foregroundStyle(GG.Palette.secondaryText)
            if let progress { ProgressView(value: progress).tint(GG.Palette.accent).frame(width: 160) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    @ViewBuilder
    private var readyContent: some View {
        if let info = model.sourceInfo {
            if let player = model.sourcePlayer {
                VideoPlayer(player: player)
                    .aspectRatio(max(info.displaySize.width, 1) / max(info.displaySize.height, 1), contentMode: .fit)
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
            }

            GGCard {
                VStack(spacing: 6) {
                    Text("Original").font(GG.Typography.eyebrow).foregroundStyle(GG.Palette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    InfoRow(label: "Size", value: info.fileSize > 0 ? Format.bytes(info.fileSize) : "Unknown")
                    InfoRow(label: "Resolution", value: "\(Int(info.displaySize.width)) × \(Int(info.displaySize.height))")
                    InfoRow(label: "Duration", value: Format.duration(info.duration))
                    InfoRow(label: "Frame rate", value: String(format: "%.0f fps", info.frameRate))
                    InfoRow(label: "Codec", value: info.codec)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Quality").font(GG.Typography.eyebrow).foregroundStyle(GG.Palette.secondaryText)
                ForEach(CompressionPreset.allCases) { preset in
                    PresetRow(preset: preset, selected: model.preset == preset) {
                        Haptics.selection(); model.preset = preset
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Resolution").font(GG.Typography.eyebrow).foregroundStyle(GG.Palette.secondaryText)
                Picker("Resolution", selection: $model.resolution) {
                    ForEach(OutputResolution.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if let plan = model.plan {
                GGCard {
                    VStack(spacing: 6) {
                        Text("Estimate").font(GG.Typography.eyebrow).foregroundStyle(GG.Palette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        InfoRow(label: "Output size", value: "≈ " + Format.bytes(plan.estimatedBytes))
                        InfoRow(label: "Output resolution", value: "\(Int(plan.displaySize.width)) × \(Int(plan.displaySize.height))")
                        InfoRow(label: "Codec", value: plan.useHEVC ? "HEVC (H.265)" : "H.264")
                        if let savings = model.estimatedSavings, savings > 0.02 {
                            InfoRow(label: "Estimated saving", value: "≈ \(Int((savings * 100).rounded()))%")
                        } else if model.estimatedSavings != nil {
                            InfoRow(label: "Estimated saving", value: "Little — already well compressed")
                        }
                    }
                }
            }

            VStack(spacing: 10) {
                Button("Compress") { model.start() }.buttonStyle(GGPrimaryButtonStyle())
                Button("Choose a Different Video") { showPicker = true }.buttonStyle(GGSecondaryButtonStyle())
            }
        }
    }

    private func compressing(_ progress: Double) -> some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(GG.Palette.separator, lineWidth: 6)
                Circle().trim(from: 0, to: progress)
                    .stroke(GG.Palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)
                Text("\(Int(progress * 100))%")
                    .font(GG.Typography.heading(40)).monospacedDigit().foregroundStyle(GG.Palette.text)
            }
            .frame(width: 170, height: 170)
            VStack(spacing: 4) {
                Text("Compressing…").font(.headline)
            }
            Button("Cancel") { model.cancel() }.buttonStyle(GGSecondaryButtonStyle(fullWidth: false))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private var doneContent: some View {
        if let info = model.sourceInfo {
            let saved = info.fileSize > 0 ? 1 - Double(model.outputSize) / Double(info.fileSize) : nil
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.system(size: 38, weight: .light)).foregroundStyle(GG.Palette.accent)
                Text("Done").font(GG.Typography.heading(30)).foregroundStyle(GG.Palette.text)
                if let saved, saved > 0 {
                    Text("\(Int((saved * 100).rounded()))% smaller").font(.subheadline).foregroundStyle(GG.Palette.accent)
                } else if saved != nil {
                    Text("The result isn't smaller than the original. Keep the original.")
                        .font(.subheadline).foregroundStyle(GG.Palette.secondaryText).multilineTextAlignment(.center)
                }
            }
            .padding(.top, 10)

            GGCard {
                VStack(spacing: 6) {
                    InfoRow(label: "Original", value: info.fileSize > 0 ? Format.bytes(info.fileSize) : "Unknown")
                    InfoRow(label: "Compressed", value: Format.bytes(model.outputSize))
                    InfoRow(label: "Resolution", value: "\(Int(model.outputDimensions.width)) × \(Int(model.outputDimensions.height))")
                    InfoRow(label: "Preset", value: model.preset.title)
                }
            }

            VStack(spacing: 10) {
                Button { showPreview = true } label: { Label("Preview Result", systemImage: "play.circle") }
                    .buttonStyle(GGSecondaryButtonStyle())
                if model.savedToPhotos {
                    Label("Saved to Photos", systemImage: "checkmark").foregroundStyle(GG.Palette.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                } else {
                    Button { Task { await model.saveToPhotos() } } label: { Label("Save to Photos", systemImage: "photo.badge.plus") }
                        .buttonStyle(GGPrimaryButtonStyle())
                }
                Button { showExporter = true } label: { Label("Save to Files", systemImage: "folder") }
                    .buttonStyle(GGSecondaryButtonStyle())
                Button("Compress with Different Settings") { model.compressAgain() }
                    .font(.subheadline).foregroundStyle(GG.Palette.secondaryText).padding(.top, 4)
                if model.savedToPhotos && !model.originalDeleted {
                    Button("Delete Original", role: .destructive) { Task { await model.deleteOriginal() } }
                        .font(.subheadline).padding(.top, 2)
                } else if model.originalDeleted {
                    Text("Original moved to Recently Deleted.").font(.footnote).foregroundStyle(GG.Palette.secondaryText)
                }
            }
        }
    }

    private func failure(_ message: String) -> some View {
        EmptyStateView(icon: "exclamationmark.triangle", title: "Couldn't Compress", message: message,
                       actionTitle: model.sourceInfo != nil ? "Try Again" : "Choose Video") {
            if model.sourceInfo != nil { model.compressAgain() } else { showPicker = true }
        }
        .padding(.top, 50)
    }
}

private struct PresetRow: View {
    let preset: CompressionPreset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? GG.Palette.accent : GG.Palette.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(preset.title).font(.body.weight(.medium)).foregroundStyle(GG.Palette.text)
                        if preset == .balanced { Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(GG.Palette.accent) }
                    }
                    Text(preset.subtitle).font(.footnote).foregroundStyle(GG.Palette.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(selected ? GG.Palette.accent.opacity(0.18) : GG.Palette.surface, in: RoundedRectangle(cornerRadius: GG.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GG.Radius.control, style: .continuous)
                    .strokeBorder(selected ? GG.Palette.accent.opacity(0.8) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct OutputPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player { VideoPlayer(player: player) }
            }
            .navigationTitle("Compressed Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { player = AVPlayer(url: url); player?.play() }
            .onDisappear { player?.pause() }
        }
        .presentationBackground(.black)
    }
}
