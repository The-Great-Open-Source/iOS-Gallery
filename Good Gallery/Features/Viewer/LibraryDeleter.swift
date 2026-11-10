import SwiftUI
import Photos

/// Deletes assets from the user's Photos library (they go to Recently Deleted).
/// iOS shows the one and only confirmation ("Delete N Photos?").
@MainActor
final class LibraryDeleter: ObservableObject {
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false
    /// Set by `deleteFromLibrary`; called with the deleted identifiers after a successful delete.
    var onDeleted: ((Set<String>) -> Void)?

    func request(_ assets: [PHAsset]) {
        guard !assets.isEmpty, !isWorking else { return }
        isWorking = true
        Task {
            // Let any dismissing menu/sheet finish first, otherwise iOS may not present its confirmation.
            try? await Task.sleep(for: .milliseconds(400))
            let ids = Set(assets.map(\.localIdentifier))
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(assets as NSArray)
                }
                Haptics.success()
                onDeleted?(ids)
            } catch {
                let nsError = error as NSError
                // Tapping "Don't Allow" on iOS's prompt is a cancel, not an error.
                if nsError.code != PHPhotosError.userCancelled.rawValue && nsError.code != NSUserCancelledError {
                    errorMessage = "The items couldn't be deleted: \(error.localizedDescription)"
                }
            }
            isWorking = false
        }
    }
}

struct DeleteFromLibraryModifier: ViewModifier {
    @ObservedObject var deleter: LibraryDeleter
    @EnvironmentObject private var store: CollectionStore
    var onDeleted: (Set<String>) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { configure() }
            .alert("Couldn't Delete", isPresented: Binding(get: { deleter.errorMessage != nil },
                                                           set: { if !$0 { deleter.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(deleter.errorMessage ?? "") }
    }

    private func configure() {
        deleter.onDeleted = { [store, onDeleted] ids in
            store.purge(ids)
            onDeleted(ids)
        }
    }
}

extension View {
    func deleteFromLibrary(_ deleter: LibraryDeleter, onDeleted: @escaping (Set<String>) -> Void = { _ in }) -> some View {
        modifier(DeleteFromLibraryModifier(deleter: deleter, onDeleted: onDeleted))
    }
}
