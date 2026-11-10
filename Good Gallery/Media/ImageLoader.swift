import Photos
import UIKit

/// Thumbnail + full-size image loading with a small in-memory cache on top of PHCachingImageManager.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 80 * 1024 * 1024   // ~80 MB of decoded thumbnails
        manager.allowsCachingHighQualityImages = false
    }

    func clearCache() { cache.removeAllObjects() }

    /// Approximate bytes in cache are not observable; we expose the configured ceiling instead.
    var cacheLimitBytes: Int { cache.totalCostLimit }

    // MARK: Thumbnails

    /// Square-ish thumbnail suitable for grids. `pixels` is the longest edge in pixels.
    func thumbnail(for asset: PHAsset, pixels: CGFloat) async -> UIImage? {
        let key = "\(asset.localIdentifier)#\(Int(pixels))" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let box = RequestBox()
        let image: UIImage? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let id = manager.requestImage(for: asset, targetSize: CGSize(width: pixels, height: pixels),
                                              contentMode: .aspectFill, options: options) { image, _ in
                    continuation.resume(returning: image)
                }
                box.set(id)
            }
        } onCancel: {
            if let id = box.id { self.manager.cancelImageRequest(id) }
        }
        if let image {
            cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        }
        return image
    }

    func thumbnail(forIdentifier identifier: String, pixels: CGFloat) async -> UIImage? {
        let asset = await Task.detached { Assets.asset(identifier) }.value
        guard let asset else { return nil }
        return await thumbnail(for: asset, pixels: pixels)
    }

    func startCaching(_ assets: [PHAsset], pixels: CGFloat) {
        manager.startCachingImages(for: assets, targetSize: CGSize(width: pixels, height: pixels), contentMode: .aspectFill, options: nil)
    }

    func stopCachingAll() { manager.stopCachingImagesForAllAssets() }
}

private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _id: PHImageRequestID?
    var id: PHImageRequestID? { lock.lock(); defer { lock.unlock() }; return _id }
    func set(_ id: PHImageRequestID) { lock.lock(); _id = id; lock.unlock() }
}

/// Loads a screen-sized image (progressively, with iCloud download progress) for the full-screen viewer.
@MainActor
final class FullImageModel: ObservableObject {
    @Published var image: UIImage?
    @Published var progress: Double?
    @Published var failed = false
    private var requestID: PHImageRequestID?
    private var loadedIdentifier: String?

    func load(_ asset: PHAsset, targetPixels: CGSize) {
        guard loadedIdentifier != asset.localIdentifier else { return }
        loadedIdentifier = asset.localIdentifier
        cancel()
        failed = false
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.progressHandler = { [weak self] value, _, _, _ in
            Task { @MainActor in self?.progress = value < 1 ? value : nil }
        }
        requestID = ImageLoader.shared.manager.requestImage(
            for: asset, targetSize: targetPixels, contentMode: .aspectFit, options: options
        ) { [weak self] image, info in
            Task { @MainActor in
                guard let self else { return }
                if let image { self.image = image; self.failed = false }
                else if (info?[PHImageErrorKey] as? NSError) != nil, self.image == nil { self.failed = true }
            }
        }
    }

    func cancel() {
        if let requestID { ImageLoader.shared.manager.cancelImageRequest(requestID) }
        requestID = nil
    }

    deinit {
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
    }
}
