import Foundation
import SwiftData

/// All mutations of Good Gallery metadata live here, keeping business logic out of views.
/// Nothing in this type ever touches the user's actual photo library.
@MainActor
final class CollectionStore: ObservableObject {
    let context: ModelContext

    init(context: ModelContext) { self.context = context }

    private func save() {
        do { try context.save() } catch { print("CollectionStore save failed: \(error)") }
    }

    // MARK: Collections

    @discardableResult
    func createCollection(name: String, coverIdentifier: String? = nil) -> MediaCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = (try? context.fetch(FetchDescriptor<MediaCollection>())) ?? []
        let next = (existing.map(\.sortOrder).max() ?? -1) + 1
        let collection = MediaCollection(name: trimmed.isEmpty ? "Untitled" : trimmed, sortOrder: next,
                                         coverAssetIdentifier: coverIdentifier)
        context.insert(collection)
        if let coverIdentifier { append([coverIdentifier], to: collection) }
        save()
        return collection
    }

    func rename(_ collection: MediaCollection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collection.name = trimmed
        touch(collection)
    }

    func setDetails(_ collection: MediaCollection, _ text: String) {
        collection.details = text.trimmingCharacters(in: .whitespacesAndNewlines)
        touch(collection)
    }

    func setCover(_ collection: MediaCollection, identifier: String?) {
        collection.coverAssetIdentifier = identifier
        if let identifier { append([identifier], to: collection, touchCollection: false) }
        touch(collection)
    }

    func setSort(_ collection: MediaCollection, _ sort: MediaSort) {
        collection.sortMode = sort
        save()
    }

    /// Deleting a collection removes only metadata (cascade deletes join rows). Original media is untouched.
    func delete(_ collection: MediaCollection) {
        context.delete(collection)
        save()
    }

    func reorder(_ ordered: [MediaCollection]) {
        for (index, collection) in ordered.enumerated() { collection.sortOrder = index }
        save()
    }

    private func touch(_ collection: MediaCollection) {
        collection.updatedAt = .now
        save()
    }

    // MARK: Membership

    /// Adds identifiers, skipping any already present. Returns the number actually added.
    @discardableResult
    func add(_ identifiers: [String], to collection: MediaCollection) -> Int {
        let added = append(identifiers, to: collection)
        return added
    }

    @discardableResult
    private func append(_ identifiers: [String], to collection: MediaCollection, touchCollection: Bool = true) -> Int {
        let present = Set(collection.items.map(\.photoKitLocalIdentifier))
        var order = (collection.items.map(\.sortOrder).max() ?? -1) + 1
        var added = 0
        let base = Date.now
        for identifier in identifiers where !present.contains(identifier) {
            let item = CollectionMedia(identifier: identifier, sortOrder: order,
                                       addedAt: base.addingTimeInterval(Double(added) * 0.001))
            item.collection = collection
            context.insert(item)
            order += 1
            added += 1
        }
        if touchCollection { touch(collection) } else { save() }
        return added
    }

    func remove(_ identifiers: Set<String>, from collection: MediaCollection) {
        for item in collection.items where identifiers.contains(item.photoKitLocalIdentifier) {
            context.delete(item)
        }
        if let cover = collection.coverAssetIdentifier, identifiers.contains(cover) {
            collection.coverAssetIdentifier = nil
        }
        touch(collection)
    }

    // MARK: Favourites

    func setFavorite(_ identifiers: [String], _ isFavorite: Bool) {
        let existing = (try? context.fetch(FetchDescriptor<FavoriteMedia>())) ?? []
        let byID = Dictionary(existing.map { ($0.photoKitLocalIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        for id in identifiers {
            if isFavorite, byID[id] == nil { context.insert(FavoriteMedia(identifier: id)) }
            if !isFavorite, let record = byID[id] { context.delete(record) }
        }
        save()
    }

    func toggleFavorite(_ identifier: String) {
        let descriptor = FetchDescriptor<FavoriteMedia>(predicate: #Predicate { $0.photoKitLocalIdentifier == identifier })
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        } else {
            context.insert(FavoriteMedia(identifier: identifier))
        }
        save()
    }

    // MARK: Compression history

    func recordCompression(_ record: CompressionRecord) {
        context.insert(record)
        save()
    }

    // MARK: Library deletion

    /// After assets were deleted from the photo library, drop every reference to them.
    func purge(_ identifiers: Set<String>) {
        let items = (try? context.fetch(FetchDescriptor<CollectionMedia>())) ?? []
        for item in items where identifiers.contains(item.photoKitLocalIdentifier) {
            item.collection?.updatedAt = .now
            context.delete(item)
        }
        for collection in (try? context.fetch(FetchDescriptor<MediaCollection>())) ?? [] {
            if let cover = collection.coverAssetIdentifier, identifiers.contains(cover) { collection.coverAssetIdentifier = nil }
        }
        pruneFavorites(identifiers)
        save()
    }

    // MARK: Reconciliation

    /// Removes join rows for assets that no longer exist. Only call when the app has *full* library access —
    /// under limited access "missing" may simply mean "not shared with Good Gallery".
    func prune(_ identifiers: Set<String>, from collection: MediaCollection) {
        remove(identifiers, from: collection)
    }

    /// Removes favourites for assets that no longer exist (full access only).
    func pruneFavorites(_ identifiers: Set<String>) {
        let existing = (try? context.fetch(FetchDescriptor<FavoriteMedia>())) ?? []
        for record in existing where identifiers.contains(record.photoKitLocalIdentifier) { context.delete(record) }
        save()
    }
}
