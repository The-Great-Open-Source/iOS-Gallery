import AVFoundation
import Photos
import UIKit

// MARK: - Settings

enum CompressionPreset: String, CaseIterable, Identifiable {
    case high, balanced, small
    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: "High Quality"
        case .balanced: "Balanced"
        case .small: "Small Size"
        }
    }
    var subtitle: String {
        switch self {
        case .high: "Prioritises visual quality with a moderate size reduction."
        case .balanced: "A good mix of quality and size. Recommended."
        case .small: "Maximum storage savings; compression may be visible."
        }
    }
    /// Target bits per pixel per frame for HEVC. H.264 needs more for similar quality (see `codecFactor`).
    var bitsPerPixel: Double {
        switch self {
        case .high: 0.090
        case .balanced: 0.050
        case .small: 0.025
        }
    }
    var audioBitrate: Int {
        switch self {
        case .high: 160_000
        case .balanced: 128_000
        case .small: 96_000
        }
    }
}

enum OutputResolution: String, CaseIterable, Identifiable {
    case original, p1080, p720, p480
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        }
    }
    /// Length of the shorter side, so portrait and landscape clips are treated alike.
    var shortSide: CGFloat? {
        switch self {
        case .original: nil
        case .p1080: 1080
        case .p720: 720
        case .p480: 480
        }
    }
}

enum CompressionError: LocalizedError {
    case unsupportedAsset
    case noVideoTrack
    case insufficientStorage(needed: Int64, available: Int64)
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedAsset:
            "This video can't be compressed directly (for example, Slo-mo or some edited clips). Try a standard video."
        case .noVideoTrack: "No video track was found in this file."
        case .insufficientStorage(let needed, let available):
            "Not enough free space. About \(Format.bytes(needed)) is needed, but only \(Format.bytes(available)) is available."
        case .failed(let message): "Compression failed: \(message)"
        case .cancelled: "Compression was cancelled."
        }
    }
}

// MARK: - Source analysis

struct VideoSourceInfo {
    var displaySize: CGSize          // after preferredTransform
    var naturalSize: CGSize          // as encoded
    var transform: CGAffineTransform
    var duration: TimeInterval
    var frameRate: Float
    var videoBitrate: Double         // bits per second (estimated)
    var fileSize: Int64
    var codec: String
    var hasAudio: Bool

    static func load(from asset: AVAsset) async throws -> VideoSourceInfo {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CompressionError.noVideoTrack }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let fps = try await track.load(.nominalFrameRate)
        let rate = try await track.load(.estimatedDataRate)
        let duration = try await asset.load(.duration).seconds
        let display = natural.applying(transform)
        var codec = "Unknown"
        if let formats = try? await track.load(.formatDescriptions), let first = formats.first {
            codec = MediaInfo.codecName(CMFormatDescriptionGetMediaSubType(first))
        }
        var fileSize: Int64 = 0
        if let url = (asset as? AVURLAsset)?.url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            fileSize = Int64(size)
        }
        let hasAudio = !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
        return VideoSourceInfo(displaySize: CGSize(width: abs(display.width), height: abs(display.height)),
                               naturalSize: natural, transform: transform, duration: duration,
                               frameRate: fps > 0 ? fps : 30, videoBitrate: Double(rate), fileSize: fileSize,
                               codec: codec, hasAudio: hasAudio)
    }
}

/// Resolved output parameters shared by the estimate and the encoder so they never disagree.
struct CompressionPlan {
    let encodedSize: CGSize       // dimensions written to the file (pre-transform)
    let displaySize: CGSize
    let videoBitrate: Int
    let audioBitrate: Int
    let useHEVC: Bool
    let frameRate: Float
    let estimatedBytes: Int64

    static var hevcAvailable: Bool {
        AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality)
    }

    init(source: VideoSourceInfo, preset: CompressionPreset, resolution: OutputResolution) {
        let shortSide = min(source.displaySize.width, source.displaySize.height)
        var scale: CGFloat = 1
        if let target = resolution.shortSide, target < shortSide { scale = target / shortSide }
        func even(_ v: CGFloat) -> CGFloat { max(2, (v / 2).rounded() * 2) }
        encodedSize = CGSize(width: even(source.naturalSize.width * scale), height: even(source.naturalSize.height * scale))
        displaySize = CGSize(width: even(source.displaySize.width * scale), height: even(source.displaySize.height * scale))
        useHEVC = Self.hevcAvailable
        frameRate = min(source.frameRate, 60)

        let codecFactor = useHEVC ? 1.0 : 1.6
        let pixelsPerSecond = Double(encodedSize.width * encodedSize.height) * Double(frameRate)
        var target = pixelsPerSecond * preset.bitsPerPixel * codecFactor
        // Never encode larger than the source stream: that would only grow the file.
        if source.videoBitrate > 0 { target = min(target, source.videoBitrate * 0.9) }
        videoBitrate = Int(max(target, 150_000))
        audioBitrate = source.hasAudio ? preset.audioBitrate : 0
        estimatedBytes = Int64(Double(videoBitrate + audioBitrate) * source.duration / 8 * 1.02)
    }
}

// MARK: - Transcoder

/// Re-encodes a video with AVAssetReader/AVAssetWriter. One instance per job.
final class VideoTranscoder: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?

    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    func run(asset: AVAsset, source: VideoSourceInfo, plan: CompressionPlan, outputURL: URL,
             progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw CompressionError.noVideoTrack }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        try? FileManager.default.removeItem(at: outputURL)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        self.reader = reader
        self.writer = writer

        // Video
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw CompressionError.unsupportedAsset }
        reader.add(videoOutput)

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: plan.videoBitrate,
            AVVideoExpectedSourceFrameRateKey: Int(plan.frameRate.rounded()),
            AVVideoAllowFrameReorderingKey: true
        ]
        if !plan.useHEVC { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: plan.useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(plan.encodedSize.width),
            AVVideoHeightKey: Int(plan.encodedSize.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: compression
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = source.transform
        guard writer.canAdd(videoInput) else { throw CompressionError.failed("Unsupported output configuration.") }
        writer.add(videoInput)

        // Audio (re-encoded to AAC for broad compatibility)
        var audioPair: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
        if let audioTrack, plan.audioBitrate > 0 {
            let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: plan.audioBitrate
            ])
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(out), writer.canAdd(input) {
                reader.add(out); writer.add(input)
                audioPair = (out, input)
            }
        }

        guard reader.startReading() else {
            throw CompressionError.failed(reader.error?.localizedDescription ?? "Couldn't read the source video.")
        }
        guard writer.startWriting() else {
            throw CompressionError.failed(writer.error?.localizedDescription ?? "Couldn't start writing.")
        }
        writer.startSession(atSourceTime: .zero)

        let duration = max(source.duration, 0.001)
        let group = DispatchGroup()

        func pump(_ output: AVAssetReaderOutput, _ input: AVAssetWriterInput, queueLabel: String, reportsProgress: Bool) {
            let queue = DispatchQueue(label: queueLabel)
            group.enter()
            input.requestMediaDataWhenReady(on: queue) { [self] in
                while input.isReadyForMoreMediaData {
                    if isCancelled { input.markAsFinished(); group.leave(); return }
                    guard let buffer = output.copyNextSampleBuffer() else {
                        input.markAsFinished(); group.leave(); return
                    }
                    if reportsProgress {
                        let t = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                        progress(min(max(t / duration, 0), 1))
                    }
                    if !input.append(buffer) { input.markAsFinished(); group.leave(); return }
                }
            }
        }

        pump(videoOutput, videoInput, queueLabel: "gg.transcode.video", reportsProgress: true)
        if let audioPair { pump(audioPair.0, audioPair.1, queueLabel: "gg.transcode.audio", reportsProgress: false) }

        // Wait for both pumps, then finalise.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { continuation.resume() }
        }

        if isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw CompressionError.cancelled
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw CompressionError.failed(reader.error?.localizedDescription ?? "Reading the source failed.")
        }
        await writer.finishWriting()
        if writer.status != .completed {
            try? FileManager.default.removeItem(at: outputURL)
            throw CompressionError.failed(writer.error?.localizedDescription ?? "Writing the output failed.")
        }
        progress(1)
    }
}

// MARK: - Loading from Photos

enum VideoLoader {
    /// Fetches an AVAsset for a PHAsset, downloading from iCloud when necessary.
    static func avAsset(for asset: PHAsset, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.progressHandler = { value, _, _, _ in progress(value) }
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    let message = (info?[PHImageErrorKey] as? NSError)?.localizedDescription ?? "The video couldn't be loaded."
                    continuation.resume(throwing: CompressionError.failed(message))
                }
            }
        }
    }

    static func saveToPhotos(url: URL, matching original: PHAsset?) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            request?.creationDate = original?.creationDate
            request?.location = original?.location
        }
    }

    static func deleteOriginal(_ asset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }
}
