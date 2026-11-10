import SwiftUI
import Photos

/// Deletes assets from the user's Photos library (they go to Recently Deleted). Always confirmed twice:
/// once by us, once by iOS.
@MainActor
final class LibraryDeleter: ObservableObject {
    @Published var pending: [PHAsset] = []
    @Published private(set) var trigger = UUID()
    @Published var errorMessage: String?

    /// Starts the deletion. iOS itself shows the one and only confirmation ("Delete N Photos?").
    func request(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        pending = assets
        trigger = UUID()
    }

    /// Returns the deleted identifiers (empty if the user cancelled iOS's prompt).
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

    func body(content: Content) -> some View {
        content
            .onChange(of: deleter.trigger) { _, _ in
                Task {
                    let ids = await deleter.performDelete()
                    guard !ids.isEmpty else { return }
                    store.purge(ids)
                    onDeleted(ids)
                }
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
