import PhotosUI
import Photos
import UIKit

/// Authorization state + change notifications for the user's photo library.
@MainActor
final class PhotoLibrary: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var status: PHAuthorizationStatus
    /// Increments whenever the underlying library changes; views key `.task(id:)` off this to refresh.
    @Published private(set) var changeToken = 0

    override init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    var hasAccess: Bool { status == .authorized || status == .limited }
    var isLimited: Bool { status == .limited }
    var isFull: Bool { status == .authorized }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func refreshStatus() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current != status {
            status = current
            changeToken += 1
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.changeToken += 1 }
    }

    /// Lets the user add more photos to a limited selection.
    func presentLimitedPicker() {
        guard let controller = UIApplication.topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension UIApplication {
    static func topViewController() -> UIViewController? {
        let scene = shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Synchronous PhotoKit lookups. Call from background tasks for large inputs.
enum Assets {
    /// Resolves identifiers to assets. Missing ones are absent from the dictionary.
    nonisolated static func resolve(_ identifiers: [String]) -> [String: PHAsset] {
        guard !identifiers.isEmpty else { return [:] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var map: [String: PHAsset] = [:]
        map.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in map[asset.localIdentifier] = asset }
        return map
    }

    nonisolated static func asset(_ identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    nonisolated static func allAssetsFetch(filter: MediaFilter = .all) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch filter {
        case .all: break
        case .photos: options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        case .videos: options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        }
        return PHAsset.fetchAssets(with: options)
    }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all = "All", photos = "Photos", videos = "Videos"
    var id: String { rawValue }
}

/// Asynchronously resolves a list of identifiers into ordered PHAssets off the main thread.
@MainActor
final class ResolvedAssets: ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var missingIdentifiers: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    /// Drops assets immediately (e.g. right after they were deleted) without waiting for a reload.
    func remove(_ identifiers: Set<String>) {
        assets.removeAll { identifiers.contains($0.localIdentifier) }
    }

    /// - Parameter identifiers: already ordered by "added" order, newest first.
    func load(identifiers: [String], sort: MediaSort = .addedNewest) async {
        isLoading = true
        let result = await Task.detached(priority: .userInitiated) { () -> ([PHAsset], Set<String>) in
            let map = Assets.resolve(identifiers)
            var ordered = identifiers.compactMap { map[$0] }
            let missing = Set(identifiers).subtracting(map.keys)
            switch sort {
            case .addedNewest: break
            case .addedOldest: ordered.reverse()
            case .takenNewest: ordered.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            case .takenOldest: ordered.sort { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            }
            return (ordered, missing)
        }.value
        guard !Task.isCancelled else { return }
        assets = result.0
        missingIdentifiers = result.1
        isLoading = false
        hasLoaded = true
    }
}
