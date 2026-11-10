import SwiftUI
import Photos

/// Multi-selection browser over the user's existing library. Never copies or modifies assets.
struct MediaPickerView: View {
    enum Mode { case multiple, single }

    var title = "Add Photos"
    var mode: Mode = .multiple
    var initialFilter: MediaFilter = .all
    var allowedFilters: [MediaFilter] = MediaFilter.allCases
    /// Already-present items: shown dimmed and not selectable.
    var disabledIdentifiers: Set<String> = []
    var confirmTitle: (Int) -> String = { $0 == 0 ? "Select Items" : "Add \(Format.count($0))" }
    var onDone: ([String]) -> Void

    @EnvironmentObject private var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var filter: MediaFilter = .all
    @State private var fetch: PHFetchResult<PHAsset>?
    @State private var order: [String] = []
    @State private var selected: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: GG.Spacing.grid)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.isLimited {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Showing only the photos you've shared with Good Gallery.")
                            .font(.footnote)
                        Spacer()
                        Button("Select More") { library.presentLimitedPicker() }.font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(GG.Palette.secondaryText)
                    .padding(.horizontal, GG.Spacing.page).padding(.vertical, 10)
                }
                if let fetch {
                    if fetch.count == 0 {
                        EmptyStateView(icon: "photo.on.rectangle", title: "Nothing Here",
                                       message: filter == .all
                                       ? "No photos or videos are available to Good Gallery."
                                       : "No \(filter.rawValue.lowercased()) found.")
                            .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: GG.Spacing.grid) {
                            ForEach(0..<fetch.count, id: \.self) { index in
                                cell(fetch.object(at: index))
                            }
                        }
                        .dragToSelect(isEnabled: mode == .multiple,
                                      isSelected: { selected.contains($0) },
                                      apply: { id, on in setSelected(id, on) })
                    }
                } else {
                    LoadingGrid()
                }
            }
            .safeAreaInset(edge: .bottom) { confirmBar }
            .ggScreen()
            .navigationTitle(selected.isEmpty ? title : Format.count(selected.count, "item") + " selected")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if allowedFilters.count > 1 {
                    ToolbarItem(placement: .principal) { EmptyView() }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Show", selection: $filter) {
                                ForEach(allowedFilters) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Label(filter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .task { filter = initialFilter }
            .task(id: FetchKey(filter: filter, token: library.changeToken)) {
                fetch = Assets.allAssetsFetch(filter: filter)
            }
        }
        .tint(GG.Palette.accent)
    }

    private struct FetchKey: Hashable { let filter: MediaFilter; let token: Int }

    private func cell(_ asset: PHAsset) -> some View {
        let id = asset.localIdentifier
        let disabled = disabledIdentifiers.contains(id)
        return AssetThumbnail(asset: asset, isSelecting: true, isSelected: selected.contains(id), isDisabled: disabled)
            .trackFrame(id: id)
            .onTapGesture {
                guard !disabled else { return }
                Haptics.selection()
                toggle(id)
            }
    }

    /// Used by drag-to-select; skips items that are already in the collection.
    private func setSelected(_ id: String, _ on: Bool) {
        guard !disabledIdentifiers.contains(id) else { return }
        if on, !selected.contains(id) { selected.insert(id); order.append(id) }
        if !on, selected.contains(id) { selected.remove(id); order.removeAll { $0 == id } }
    }

    private func toggle(_ id: String) {
        if mode == .single {
            selected = selected.contains(id) ? [] : [id]
            order = Array(selected)
            return
        }
        if selected.contains(id) {
            selected.remove(id)
            order.removeAll { $0 == id }
        } else {
            selected.insert(id)
            order.append(id)
        }
    }

    private var confirmBar: some View {
        VStack(spacing: 0) {
            Button(confirmTitle(selected.count)) {
                Haptics.success()
                onDone(order)
                dismiss()
            }
            .buttonStyle(GGPrimaryButtonStyle())
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.45 : 1)
            .padding(.horizontal, GG.Spacing.page).padding(.vertical, 12)
        }
    }
}
