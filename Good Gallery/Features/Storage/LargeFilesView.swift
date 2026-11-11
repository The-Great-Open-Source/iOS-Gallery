import SwiftUI
import Photos

/// Finds the biggest photos and videos in the library so they can be compressed or deleted.
@MainActor
final class LargeFilesModel: ObservableObject {
    struct Item: Identifiable {
        let asset: PHAsset
        let bytes: Int64
        var id: String { asset.localIdentifier }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var scanned = 0
    @Published private(set) var total = 0
    @Published private(set) var libraryBytes: Int64 = 0
    @Published private(set) var isScanning = false
    @Published private(set) var sizesAvailable = true
    private var task: Task<Void, Never>?

    func scan() {
        guard task == nil else { return }
        isScanning = true
        scanned = 0
        task = Task { [weak self] in
            for await update in Self.stream() {
                guard let self else { return }
                self.items = update.top
                self.scanned = update.scanned
                self.total = update.total
                self.libraryBytes = update.libraryBytes
                self.sizesAvailable = update.sawAnySize || update.scanned < 50
            }
            self?.isScanning = false
            self?.task = nil
        }
    }

    func rescan() { task?.cancel(); task = nil; scan() }
    func remove(_ ids: Set<String>) { items.removeAll { ids.contains($0.id) } }

    struct Update { let top: [Item]; let scanned: Int; let total: Int; let libraryBytes: Int64; let sawAnySize: Bool }

    nonisolated private static func stream() -> AsyncStream<Update> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .utility) {
                let fetch = Assets.allAssetsFetch()
                let total = fetch.count
                var top: [Item] = []
                var sum: Int64 = 0
                var sawSize = false
                let keep = 400
                for index in 0..<total {
                    if Task.isCancelled { break }
                    let asset = fetch.object(at: index)
                    if let bytes = BackupEngine.originalSize(of: asset), bytes > 0 {
                        sawSize = true
                        sum += bytes
                        if top.count < keep || bytes > (top.last?.bytes ?? 0) {
                            top.append(Item(asset: asset, bytes: bytes))
                            top.sort { $0.bytes > $1.bytes }
                            if top.count > keep { top.removeLast() }
                        }
                    }
                    if (index + 1) % 400 == 0 {
                        continuation.yield(Update(top: top, scanned: index + 1, total: total, libraryBytes: sum, sawAnySize: sawSize))
                    }
                }
                continuation.yield(Update(top: top, scanned: total, total: total, libraryBytes: sum, sawAnySize: sawSize))
                continuation.finish()
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}

struct LargeFilesView: View {
    @StateObject private var model = LargeFilesModel()
    @StateObject private var deleter = LibraryDeleter()
    @State private var filter: MediaFilter = .all
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<String> = []
    @State private var viewer: ViewerContext?
    @State private var compressTarget: CompressTarget?

    private struct CompressTarget: Identifiable, Hashable { let id: String }

    @State private var over100MB = false
    @State private var olderThanYear = false

    private var hasActiveFilter: Bool { filter != .all || over100MB || olderThanYear }

    private var visible: [LargeFilesModel.Item] {
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        return model.items.filter { item in
            switch filter {
            case .all: break
            case .photos: if item.asset.mediaType != .image { return false }
            case .videos: if item.asset.mediaType != .video { return false }
            }
            if over100MB, item.bytes < 100_000_000 { return false }
            if olderThanYear, (item.asset.creationDate ?? .distantFuture) >= yearAgo { return false }
            return true
        }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.libraryBytes > 0 ? Format.bytes(model.libraryBytes) : "—").font(.title.weight(.semibold))
                    Text(model.isScanning
                         ? "Scanning your library… \(model.scanned.formatted()) of \(model.total.formatted())"
                         : "Photos & videos in your library")
                        .font(.footnote).foregroundStyle(.secondary)
                    if model.isScanning { ProgressView(value: Double(model.scanned), total: Double(max(model.total, 1))).tint(GG.Palette.accent) }
                }
                .padding(.vertical, 4)
            }
            if !model.sizesAvailable {
                Section { Text("File sizes aren't available on this device.").foregroundStyle(.secondary) }
            }
            Section("Largest") {
                ForEach(visible) { item in
                    row(item)
                        .tag(item.id)
                }
                if visible.isEmpty && !model.isScanning {
                    Text(hasActiveFilter ? "Nothing matches these filters." : "No files found.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .environment(\.editMode, $editMode)
        .tint(GG.Palette.accent)
        .scrollContentBackground(.hidden)
        .background(GGBackground(grouped: true))
        .navigationTitle("Largest Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Show", selection: $filter) { ForEach(MediaFilter.allCases) { Text($0.rawValue).tag($0) } }
                    Section {
                        Toggle("Over 100 MB", isOn: $over100MB)
                        Toggle("Older than a year", isOn: $olderThanYear)
                    }
                    if hasActiveFilter {
                        Button("Clear Filters", role: .destructive) { filter = .all; over100MB = false; olderThanYear = false }
                    }
                } label: { Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Done" : "Select") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active; if !editMode.isEditing { selection = [] } }
                }
                .disabled(visible.isEmpty)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if editMode.isEditing {
                    Text(selection.isEmpty ? "Select Items" : "\(selection.count) selected · \(Format.bytes(selectedBytes))").font(.footnote)
                    Spacer()
                    Button(role: .destructive) {
                        deleter.request(visible.filter { selection.contains($0.id) }.map(\.asset))
                    } label: { Image(systemName: "trash") }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .toolbar(editMode.isEditing ? .hidden : .visible, for: .tabBar)
        .navigationDestination(item: $compressTarget) { VideoCompressorView(initialIdentifier: $0.id) }
        .fullScreenCover(item: $viewer) { ViewerView(context: $0) }
        .onAppear { model.scan() }
        .deleteFromLibrary(deleter) { ids in
            withAnimation { model.remove(ids); selection = []; editMode = .inactive }
        }
    }

    private var selectedBytes: Int64 { visible.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.bytes } }

    private func row(_ item: LargeFilesModel.Item) -> some View {
        let asset = item.asset
        return HStack(spacing: 12) {
            CoverImage(identifier: asset.localIdentifier, pixels: 170)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if asset.mediaType == .video { Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(.white).padding(4) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.bytes(item.bytes)).font(.headline)
                Text(subtitle(for: asset)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if asset.mediaType == .video && !editMode.isEditing {
                Button("Compress") { compressTarget = CompressTarget(id: asset.localIdentifier) }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(GG.Palette.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editMode.isEditing, let index = visible.firstIndex(where: { $0.id == item.id }) else { return }
            viewer = ViewerContext(assets: visible.map(\.asset), index: index)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleter.request([asset]) } label: { Label("Delete", systemImage: "trash") }
            if asset.mediaType == .video {
                Button { compressTarget = CompressTarget(id: asset.localIdentifier) } label: { Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left") }
                    .tint(.orange)
            }
        }
    }

    private func subtitle(for asset: PHAsset) -> String {
        var parts: [String] = [asset.mediaType == .video ? "Video · \(Format.duration(asset.duration))" : "Photo"]
        parts.append("\(asset.pixelWidth)×\(asset.pixelHeight)")
        if let date = asset.creationDate { parts.append(date.formatted(.dateTime.day().month(.abbreviated).year())) }
        return parts.joined(separator: " · ")
    }
}
