import SwiftUI
import Photos

/// Exports originals to temp files and presents the system share sheet.
@MainActor
final class SharePreparer: ObservableObject {
    @Published var items: ShareItems?
    @Published var isPreparing = false
    @Published var errorMessage: String?
    private var task: Task<Void, Never>?

    func share(_ assets: [PHAsset]) {
        guard !assets.isEmpty, !isPreparing else { return }
        isPreparing = true
        task = Task {
            do {
                let urls = try await MediaExporter.shareURLs(for: assets)
                items = urls.isEmpty ? nil : ShareItems(urls: urls)
                if urls.isEmpty { errorMessage = "These items couldn't be prepared for sharing." }
            } catch is CancellationError {
            } catch {
                errorMessage = "Sharing failed: \(error.localizedDescription)"
            }
            isPreparing = false
        }
    }

    func cancel() { task?.cancel() }
}

struct ShareSheetModifier: ViewModifier {
    @ObservedObject var preparer: SharePreparer

    func body(content: Content) -> some View {
        content
            .sheet(item: $preparer.items) { items in
                ActivityView(items: items.urls).presentationDetents([.medium, .large]).ignoresSafeArea()
            }
            .overlay {
                if preparer.isPreparing {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().tint(GG.Palette.accent)
                            Text("Preparing…").font(.footnote).foregroundStyle(GG.Palette.text)
                            Button("Cancel") { preparer.cancel() }.font(.footnote)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: GG.Radius.card))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: preparer.isPreparing)
            .alert("Couldn't Share", isPresented: Binding(get: { preparer.errorMessage != nil },
                                                          set: { if !$0 { preparer.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(preparer.errorMessage ?? "") }
    }
}

extension View {
    func shareSheet(_ preparer: SharePreparer) -> some View { modifier(ShareSheetModifier(preparer: preparer)) }
}
