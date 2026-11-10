import Photos
import Foundation

/// Assets in the library that aren't in any Good Gallery collection. Computed in the background.
@MainActor
final class UncategorizedModel: ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var hasLoaded = false

    func refresh(organized: Set<String>) async {
        let result = await Task.detached(priority: .userInitiated) { () -> [PHAsset] in
            let fetch = Assets.allAssetsFetch()
            var out: [PHAsset] = []
            fetch.enumerateObjects { asset, _, _ in
                if !organized.contains(asset.localIdentifier) { out.append(asset) }
            }
            return out
        }.value
        guard !Task.isCancelled else { return }
        assets = result
        hasLoaded = true
    }
}
