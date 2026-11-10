import SwiftUI
import Photos

/// Deletes assets from the user's Photos library (they go to Recently Deleted). Always confirmed twice:
/// once by us, once by iOS.
@MainActor
final class LibraryDeleter: ObservableObject {
    @Published var pending: [PHAsset] = []
    @Published var isConfirming = false
    @Published var errorMessage: String?

    func request(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        pending = assets
        isConfirming = true
    }

    /// Returns the deleted identifiers (empty if the user cancelled the system prompt).
    func performDelete() async -> Set<String> {
        let assets = pending
        pending = []
        let ids = Set(assets.map(\.localIdentifier))
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            Haptics.success()
            return ids
        } catch {
            // Cancelling iOS's own confirmation also lands here; only surface real failures.
            let code = (error as NSError).code
            if code != PHPhotosError.userCancelled.rawValue {
                errorMessage = "The items couldn't be deleted: \(error.localizedDescription)"
            }
            return []
        }
    }
}

struct DeleteFromLibraryModifier: ViewModifier {
    @ObservedObject var deleter: LibraryDeleter
    @EnvironmentObject private var store: CollectionStore
    var onDeleted: (Set<String>) -> Void

    private var title: String {
        let n = deleter.pending.count
        return n == 1 ? "Delete this \(deleter.pending.first?.mediaType == .video ? "video" : "photo")?" : "Delete \(n) items?"
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $deleter.isConfirming, titleVisibility: .visible) {
                Button("Delete from Photos Library", role: .destructive) {
                    Task {
                        let ids = await deleter.performDelete()
                        guard !ids.isEmpty else { return }
                        store.purge(ids)
                        onDeleted(ids)
                    }
                }
                Button("Cancel", role: .cancel) { deleter.pending = [] }
            } message: {
                Text("This removes them from your iPhone's Photos library (they stay in Recently Deleted for 30 days) and from every Good Gallery collection. To keep them, use Remove from Collection instead.")
            }
            .alert("Couldn't Delete", isPresented: Binding(get: { deleter.errorMessage != nil },
                                                           set: { if !$0 { deleter.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(deleter.errorMessage ?? "") }
    }
}

extension View {
    func deleteFromLibrary(_ deleter: LibraryDeleter, onDeleted: @escaping (Set<String>) -> Void = { _ in }) -> some View {
        modifier(DeleteFromLibraryModifier(deleter: deleter, onDeleted: onDeleted))
    }
}
