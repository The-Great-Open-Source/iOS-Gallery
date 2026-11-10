import Photos
import Foundation

/// In-memory, on-device index of searchable media metadata (filename, month/year, media type).
/// Built in the background in chunks so search is usable immediately and gets more complete.
@MainActor
final class MediaSearchIndex: ObservableObject {
    struct Entry: Sendable {
        let identifier: String
        let haystack: String      // lower-cased searchable text
        let filename: String
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isIndexing = false
    private var builtForToken = -1
    private var task: Task<Void, Never>?

    func buildIfNeeded(changeToken: Int) {
        guard builtForToken != changeToken else { return }
        builtForToken = changeToken
        task?.cancel()
        isIndexing = true
        entries = []
        task = Task { [weak self] in
            let stream = Self.makeEntries()
            for await chunk in stream {
                guard !Task.isCancelled else { return }
                self?.entries.append(contentsOf: chunk)
            }
            self?.isIndexing = false
        }
    }

    nonisolated private static func makeEntries() -> AsyncStream<[Entry]> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .utility) {
                let fetch = Assets.allAssetsFetch()
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM MMM yyyy"
                var monthCache: [Int: String] = [:]
                var chunk: [Entry] = []
                let total = min(fetch.count, 30_000)
                for index in 0..<total {
                    if Task.isCancelled { break }
                    let asset = fetch.object(at: index)
                    let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
                    var words = [filename]
                    if let date = asset.creationDate {
                        let key = Calendar.current.dateComponents([.year, .month], from: date)
                        let bucket = (key.year ?? 0) * 100 + (key.month ?? 0)
                        if monthCache[bucket] == nil { monthCache[bucket] = formatter.string(from: date) }
                        words.append(monthCache[bucket]!)
                    }
                    words.append(asset.mediaType == .video ? "video" : "photo")
                    if asset.mediaSubtypes.contains(.photoScreenshot) { words.append("screenshot") }
                    if asset.mediaSubtypes.contains(.photoLive) { words.append("live") }
                    if asset.mediaSubtypes.contains(.videoHighFrameRate) { words.append("slo-mo slow") }
                    if asset.mediaSubtypes.contains(.photoPanorama) { words.append("panorama") }
                    if asset.isFavorite { words.append("apple favorite") }
                    chunk.append(Entry(identifier: asset.localIdentifier,
                                       haystack: words.joined(separator: " ").lowercased(), filename: filename))
                    if chunk.count >= 1500 { continuation.yield(chunk); chunk = [] }
                }
                if !chunk.isEmpty { continuation.yield(chunk) }
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    func search(_ query: String, limit: Int = 300) -> [Entry] {
        let tokens = query.lowercased().split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }
        var results: [Entry] = []
        for entry in entries where tokens.allSatisfy({ entry.haystack.contains($0) }) {
            results.append(entry)
            if results.count >= limit { break }
        }
        return results
    }
}
