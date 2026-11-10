import Foundation
import SwiftData

/// A user-defined collection. Holds *references* to PhotoKit assets, never media itself.
@Model
final class MediaCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var details: String
    var coverAssetIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    var sortModeRaw: String
    /// When true, new items in this collection are uploaded to Google Drive automatically.
    var autoBackupDrive: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \CollectionMedia.collection)
    var items: [CollectionMedia] = []

    init(name: String, sortOrder: Int, coverAssetIdentifier: String? = nil) {
        self.id = UUID()
        self.name = name
        self.details = ""
        self.coverAssetIdentifier = coverAssetIdentifier
        self.createdAt = .now
        self.updatedAt = .now
        self.sortOrder = sortOrder
        self.sortModeRaw = MediaSort.addedNewest.rawValue
    }

    var sortMode: MediaSort {
        get { MediaSort(rawValue: sortModeRaw) ?? .addedNewest }
        set { sortModeRaw = newValue.rawValue }
    }

    /// Cover identifier, falling back to the most recently added item.
    var effectiveCoverIdentifier: String? {
        coverAssetIdentifier ?? items.max(by: { $0.addedAt < $1.addedAt })?.photoKitLocalIdentifier
    }
}

/// Join record: one PhotoKit asset inside one collection. The same asset may appear in many collections.
@Model
final class CollectionMedia {
    @Attribute(.unique) var id: UUID
    var collection: MediaCollection?
    var photoKitLocalIdentifier: String
    var addedAt: Date
    var sortOrder: Int

    init(identifier: String, sortOrder: Int, addedAt: Date = .now) {
        self.id = UUID()
        self.photoKitLocalIdentifier = identifier
        self.addedAt = addedAt
        self.sortOrder = sortOrder
    }
}

/// Good Gallery's own favourites. Deliberately separate from Apple Photos' ♥︎ so we never modify the user's library.
@Model
final class FavoriteMedia {
    @Attribute(.unique) var photoKitLocalIdentifier: String
    var createdAt: Date
    init(identifier: String) {
        self.photoKitLocalIdentifier = identifier
        self.createdAt = .now
    }
}

@Model
final class CompressionRecord {
    @Attribute(.unique) var id: UUID
    var originalAssetIdentifier: String
    var originalFileSize: Int64
    var outputFileSize: Int64
    var outputResolution: String
    var compressionPreset: String
    var createdAt: Date

    init(originalAssetIdentifier: String, originalFileSize: Int64, outputFileSize: Int64,
         outputResolution: String, compressionPreset: String) {
        self.id = UUID()
        self.originalAssetIdentifier = originalAssetIdentifier
        self.originalFileSize = originalFileSize
        self.outputFileSize = outputFileSize
        self.outputResolution = outputResolution
        self.compressionPreset = compressionPreset
        self.createdAt = .now
    }
}

enum MediaSort: String, CaseIterable, Identifiable {
    case addedNewest, addedOldest, takenNewest, takenOldest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .addedNewest: "Recently Added"
        case .addedOldest: "Oldest Added"
        case .takenNewest: "Newest Photos First"
        case .takenOldest: "Oldest Photos First"
        }
    }
}

/// Remembers which asset was already sent where, so nothing is uploaded twice.
@Model
final class BackupRecord {
    var destination: String            // "drive" | "telegram"
    var photoKitLocalIdentifier: String
    var createdAt: Date
    init(destination: String, identifier: String) {
        self.destination = destination
        self.photoKitLocalIdentifier = identifier
        self.createdAt = .now
    }
}

/// On-device image labels from Apple's Vision classifier, used for smart search.
@Model
final class PhotoTags {
    @Attribute(.unique) var photoKitLocalIdentifier: String
    var labels: [String]
    var scores: [Float]
    var indexedAt: Date
    init(identifier: String, labels: [String], scores: [Float]) {
        self.photoKitLocalIdentifier = identifier
        self.labels = labels
        self.scores = scores
        self.indexedAt = .now
    }
}
