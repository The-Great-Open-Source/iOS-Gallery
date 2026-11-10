import Photos
import AVFoundation
import CoreLocation
import UniformTypeIdentifiers

/// Technical details about a photo or video, assembled from PhotoKit and AVFoundation.
struct MediaInfo {
    var filename: String?
    var isVideo: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    var creationDate: Date?
    var format: String?
    var fileSize: Int64?
    var fileSizeNote: String?
    var duration: TimeInterval?
    var frameRate: Float?
    var codec: String?
    var hasAudio: Bool?
    var location: CLLocationCoordinate2D?
    var isLivePhoto = false
    var isScreenshot = false

    static func load(for asset: PHAsset) async -> MediaInfo {
        let isVideo = asset.mediaType == .video
        var info = MediaInfo(filename: nil, isVideo: isVideo, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
                             creationDate: asset.creationDate, location: asset.location?.coordinate)
        info.isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
        info.isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)

        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first { $0.type == (isVideo ? .video : .photo) } ?? resources.first
        info.filename = primary?.originalFilename
        if let uti = primary?.uniformTypeIdentifier, let type = UTType(uti) {
            info.format = type.localizedDescription ?? type.preferredFilenameExtension?.uppercased()
        }

        if isVideo {
            await info.loadVideoDetails(asset)
        } else {
            await info.loadPhotoSize(asset)
        }
        return info
    }

    private mutating func loadPhotoSize(_ asset: PHAsset) async {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false          // never silently download for an inspector
        options.version = .current
        let size: Int64? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data.map { Int64($0.count) })
            }
        }
        if let size { fileSize = size } else { fileSizeNote = "Stored in iCloud" }
    }

    private mutating func loadVideoDetails(_ asset: PHAsset) async {
        duration = asset.duration
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.version = .current
        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
        guard let avAsset else { fileSizeNote = "Stored in iCloud"; return }
        if let url = (avAsset as? AVURLAsset)?.url,
           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            fileSize = Int64(size)
        }
        if let track = try? await avAsset.loadTracks(withMediaType: .video).first {
            frameRate = try? await track.load(.nominalFrameRate)
            if let formats = try? await track.load(.formatDescriptions), let first = formats.first {
                codec = Self.codecName(CMFormatDescriptionGetMediaSubType(first))
            }
        }
        hasAudio = ((try? await avAsset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false
    }

    static func codecName(_ subtype: FourCharCode) -> String {
        switch subtype {
        case kCMVideoCodecType_HEVC: return "HEVC (H.265)"
        case kCMVideoCodecType_H264: return "H.264 (AVC)"
        case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes4444: return "Apple ProRes"
        case kCMVideoCodecType_JPEG: return "Motion JPEG"
        default:
            let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((subtype >> UInt32($0)) & 0xFF))) }
            return String(chars).trimmingCharacters(in: .whitespaces)
        }
    }

    var resolutionText: String { "\(pixelWidth) × \(pixelHeight)" }
    var megapixels: String? {
        isVideo ? nil : String(format: "%.1f MP", Double(pixelWidth * pixelHeight) / 1_000_000)
    }
}
