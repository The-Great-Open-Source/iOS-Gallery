import Photos
import SwiftData
import Vision
import UIKit

/// Builds and queries an on-device index of what each photo shows (sky, beach, food, car…), using Apple's
/// built-in Vision classifier. Nothing is uploaded and no model has to be downloaded.
@MainActor
final class PhotoTagIndexer: ObservableObject {
    struct Entry { let id: String; let labels: [String]; let scores: [Float] }

    @Published private(set) var indexed = 0
    @Published private(set) var total = 0
    @Published private(set) var isIndexing = false
    @Published private(set) var revision = 0          // bumps as the index grows so searches can refresh

    private let container: ModelContainer
    private var entries: [Entry] = []
    private var loaded = false
    private var task: Task<Void, Never>?
    private var vocabulary: [String] = []
    private var weightCache: [String: [String: Float]] = [:]

    init(container: ModelContainer) { self.container = container }

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "smartSearch.enabled") as? Bool ?? true }

    // MARK: Indexing

    func start() {
        guard isEnabled, task == nil else { return }
        isIndexing = true
        let container = container
        task = Task { [weak self] in
            // 1. Load what's already indexed.
            let existing: [Entry] = await Task.detached(priority: .utility) {
                let context = ModelContext(container)
                let rows = (try? context.fetch(FetchDescriptor<PhotoTags>())) ?? []
                return rows.map { Entry(id: $0.photoKitLocalIdentifier, labels: $0.labels, scores: $0.scores) }
            }.value
            guard let self else { return }
            self.entries = existing
            self.loaded = true
            self.indexed = existing.count
            self.revision += 1

            // 2. Classify the rest in the background, saving in batches.
            let known = Set(existing.map(\.id))
            let stream = Self.classifyNewPhotos(skipping: known, container: container)
            for await update in stream {
                if Task.isCancelled { break }
                self.entries.append(contentsOf: update.newEntries)
                self.indexed = update.done
                self.total = update.total
                self.revision += 1
            }
            self.isIndexing = false
            self.task = nil
        }
    }

    func stop() { task?.cancel(); task = nil; isIndexing = false }

    func rebuild() {
        stop()
        let container = container
        Task {
            await Task.detached {
                let context = ModelContext(container)
                try? context.delete(model: PhotoTags.self)
                try? context.save()
            }.value
            entries = []; indexed = 0; total = 0; revision += 1
            start()
        }
    }

    struct Update { let newEntries: [Entry]; let done: Int; let total: Int }

    nonisolated private static func classifyNewPhotos(skipping known: Set<String>, container: ModelContainer) -> AsyncStream<Update> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .utility) {
                let options = PHFetchOptions()
                options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let fetch = PHAsset.fetchAssets(with: options)
                let context = ModelContext(container)
                let imageOptions = PHImageRequestOptions()
                imageOptions.isSynchronous = true
                imageOptions.isNetworkAccessAllowed = false     // never download from iCloud just to index
                imageOptions.deliveryMode = .highQualityFormat
                imageOptions.resizeMode = .fast
                var pending: [Entry] = []
                var done = known.count
                let total = fetch.count
                var sinceSave = 0

                for index in 0..<fetch.count {
                    if Task.isCancelled { break }
                    let asset = fetch.object(at: index)
                    if known.contains(asset.localIdentifier) { continue }
                    var cg: CGImage?
                    PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 299, height: 299),
                                                          contentMode: .aspectFill, options: imageOptions) { image, _ in cg = image?.cgImage }
                    guard let cg else { continue }          // not available locally: try again next time
                    let request = VNClassifyImageRequest()
                    guard (try? VNImageRequestHandler(cgImage: cg).perform([request])) != nil else { continue }
                    let top = (request.results ?? []).filter { $0.confidence >= 0.12 }.prefix(10)
                    let labels = top.map(\.identifier), scores = top.map(\.confidence)
                    context.insert(PhotoTags(identifier: asset.localIdentifier, labels: labels, scores: scores))
                    pending.append(Entry(id: asset.localIdentifier, labels: labels, scores: scores))
                    done += 1; sinceSave += 1
                    if sinceSave >= 100 {
                        try? context.save(); sinceSave = 0
                        continuation.yield(Update(newEntries: pending, done: done, total: total)); pending = []
                    }
                }
                try? context.save()
                continuation.yield(Update(newEntries: pending, done: done, total: total))
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    // MARK: Querying

    private static let stopWords: Set<String> = ["a", "an", "the", "of", "in", "at", "on", "with", "and", "my", "me", "photo", "photos",
                                                 "picture", "pictures", "pic", "pics", "image", "images", "day", "days", "time", "times",
                                                 "show", "find", "some", "all", "from", "for", "to"]

    /// Identifiers of photos best matching the query, most relevant first.
    func search(_ query: String, limit: Int = 300) -> [String] {
        guard loaded, !entries.isEmpty else { return [] }
        let tokens = query.lowercased().split { !$0.isLetter }.map(String.init).filter { !Self.stopWords.contains($0) && $0.count > 1 }
        guard !tokens.isEmpty else { return [] }
        let weights = tokens.map { labelWeights(for: $0) }
        if weights.allSatisfy(\.isEmpty) { return [] }

        var scored: [(String, Float)] = []
        for entry in entries {
            var total: Float = 0
            for tokenWeights in weights {
                var best: Float = 0
                for (label, score) in zip(entry.labels, entry.scores) {
                    if let weight = tokenWeights[label] { best = max(best, weight * score) }
                }
                total += best
            }
            if total > 0.06 { scored.append((entry.id, total)) }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// How strongly each Vision label relates to a query word: curated concepts first, then exact label words.
    private func labelWeights(for token: String) -> [String: Float] {
        if let cached = weightCache[token] { return cached }
        if vocabulary.isEmpty { vocabulary = (try? VNClassifyImageRequest().supportedIdentifiers()) ?? [] }
        var result = SearchConcepts.labels(for: token) ?? [:]
        for label in vocabulary where SearchConcepts.directMatch(token: token, label: label) {
            result[label] = max(result[label] ?? 0, 1)
        }
        weightCache[token] = result
        return result
    }
}
