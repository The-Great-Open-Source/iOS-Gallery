import Photos
import UIKit

/// Writes original asset resources to temporary files (for sharing) and manages Good Gallery's scratch space.
enum MediaExporter {
    static var scratchDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GoodGallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies the original resources to temp files so they can be shared. Downloads from iCloud if needed.
    static func shareURLs(for assets: [PHAsset]) async throws -> [URL] {
        let folder = scratchDirectory.appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        for asset in assets {
            try Task.checkCancellation()
            let resources = PHAssetResource.assetResources(for: asset)
            let wanted: PHAssetResourceType = asset.mediaType == .video ? .video : .photo
            guard let resource = resources.first(where: { $0.type == wanted }) ?? resources.first else { continue }
            var name = resource.originalFilename
            var destination = folder.appendingPathComponent(name)
            var n = 1
            while FileManager.default.fileExists(atPath: destination.path) {
                n += 1
                let base = (resource.originalFilename as NSString).deletingPathExtension
                let ext = (resource.originalFilename as NSString).pathExtension
                name = "\(base)-\(n).\(ext)"
                destination = folder.appendingPathComponent(name)
            }
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options)
            urls.append(destination)
        }
        return urls
    }

    static func scratchSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: scratchDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    static func clearScratch() {
        try? FileManager.default.removeItem(at: scratchDirectory)
    }

    static func availableDiskBytes() -> Int64 {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }
}

/// SwiftUI wrappers for UIKit sharing/exporting UI.
import SwiftUI

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct FileExporter: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (Bool) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(onFinish) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Bool) -> Void
        init(_ onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish(false) }
    }
}

/// Identifiable wrapper so share sheets can be driven by `.sheet(item:)`.
struct ShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}
