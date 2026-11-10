import SwiftUI
import AVFoundation
import Photos

@MainActor
final class VideoCompressorViewModel: ObservableObject {
    enum Stage: Equatable {
        case empty
        case loading(Double?)
        case ready
        case compressing(Double)
        case done
        case failed(String)
    }

    @Published var stage: Stage = .empty
    @Published var preset: CompressionPreset = .balanced
    @Published var resolution: OutputResolution = .original
    @Published private(set) var sourceInfo: VideoSourceInfo?
    @Published private(set) var sourcePlayer: AVPlayer?
    @Published private(set) var outputURL: URL?
    @Published private(set) var outputSize: Int64 = 0
    @Published private(set) var outputDimensions: CGSize = .zero
    @Published var savedToPhotos = false
    @Published var originalDeleted = false
    @Published var statusMessage: String?

    private(set) var asset: PHAsset?
    private var avAsset: AVAsset?
    private var transcoder: VideoTranscoder?
    private var task: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var plan: CompressionPlan? {
        guard let sourceInfo else { return nil }
        return CompressionPlan(source: sourceInfo, preset: preset, resolution: resolution)
    }

    /// Fraction of the source size the estimate represents (nil if file size is unknown).
    var estimatedSavings: Double? {
        guard let plan, let info = sourceInfo, info.fileSize > 0 else { return nil }
        return 1 - Double(plan.estimatedBytes) / Double(info.fileSize)
    }

    func select(identifier: String) {
        reset()
        guard let phAsset = Assets.asset(identifier) else { stage = .failed("That video is no longer available."); return }
        asset = phAsset
        stage = .loading(nil)
        task = Task {
            do {
                let av = try await VideoLoader.avAsset(for: phAsset) { [weak self] value in
                    Task { @MainActor in self?.stage = .loading(value) }
                }
                guard av is AVURLAsset else { throw CompressionError.unsupportedAsset }
                let info = try await VideoSourceInfo.load(from: av)
                avAsset = av
                sourceInfo = info
                sourcePlayer = AVPlayer(playerItem: AVPlayerItem(asset: av))
                stage = .ready
            } catch is CancellationError {
            } catch {
                stage = .failed(error.localizedDescription)
            }
        }
    }

    func start() {
        guard let avAsset, let sourceInfo, let plan else { return }
        let needed = Int64(Double(plan.estimatedBytes) * 1.3)
        let available = MediaExporter.availableDiskBytes()
        if available < needed {
            stage = .failed(CompressionError.insufficientStorage(needed: needed, available: available).localizedDescription)
            Haptics.error()
            return
        }
        sourcePlayer?.pause()
        let output = MediaExporter.scratchDirectory.appendingPathComponent("compressed-\(UUID().uuidString).mp4")
        let transcoder = VideoTranscoder()
        self.transcoder = transcoder
        stage = .compressing(0)
        beginBackgroundGrace()
        UIApplication.shared.isIdleTimerDisabled = true

        task = Task {
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                endBackgroundGrace()
            }
            do {
                try await transcoder.run(asset: avAsset, source: sourceInfo, plan: plan, outputURL: output) { [weak self] value in
                    Task { @MainActor in
                        if case .compressing = self?.stage { self?.stage = .compressing(value) }
                    }
                }
                let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                outputURL = output
                outputSize = size
                outputDimensions = plan.displaySize
                stage = .done
                Haptics.success()
                if let asset {
                    context?.recordCompression(CompressionRecord(
                        originalAssetIdentifier: asset.localIdentifier, originalFileSize: sourceInfo.fileSize,
                        outputFileSize: size, outputResolution: "\(Int(plan.displaySize.width))×\(Int(plan.displaySize.height))",
                        compressionPreset: preset.title))
                }
            } catch CompressionError.cancelled {
                stage = .ready
            } catch is CancellationError {
                stage = .ready
            } catch {
                try? FileManager.default.removeItem(at: output)
                stage = .failed(error.localizedDescription)
                Haptics.error()
            }
        }
    }

    weak var context: CollectionStore?

    func cancel() {
        transcoder?.cancel()
    }

    func compressAgain() {
        discardOutput()
        stage = .ready
    }

    func saveToPhotos() async {
        guard let outputURL else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        // Full/limited read-write access also allows adding.
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited || current == .authorized || current == .limited else {
            statusMessage = "Allow Good Gallery to add photos in Settings to save the compressed video."
            return
        }
        do {
            try await VideoLoader.saveToPhotos(url: outputURL, matching: asset)
            savedToPhotos = true
            Haptics.success()
        } catch {
            statusMessage = "Couldn't save to Photos: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    func deleteOriginal() async {
        guard let asset else { return }
        do {
            try await VideoLoader.deleteOriginal(asset)
            originalDeleted = true
        } catch {
            statusMessage = "The original wasn't deleted: \(error.localizedDescription)"
        }
    }

    func reset() {
        task?.cancel()
        transcoder?.cancel()
        sourcePlayer?.pause()
        sourcePlayer = nil
        discardOutput()
        sourceInfo = nil; avAsset = nil; asset = nil
        stage = .empty
    }

    private func discardOutput() {
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil; outputSize = 0; savedToPhotos = false; originalDeleted = false
    }

    private func beginBackgroundGrace() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "GoodGallery.compress") { [weak self] in
            self?.transcoder?.cancel()
        }
    }

    private func endBackgroundGrace() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}
