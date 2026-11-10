#if DEBUG
import SwiftUI
import SwiftData
import Photos
import AVFoundation

/// Debug-only helpers used to verify flows on a simulator without UI scripting.
/// Launch arguments: -gg-seed, -gg-open collection|uncategorized, -gg-viewer N, -gg-selftest
enum DebugHarness {
    static var args: [String] { ProcessInfo.processInfo.arguments }
    static func has(_ flag: String) -> Bool { args.contains(flag) }
    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    static func log(_ s: String) { print(s); fflush(stdout) }

    @MainActor
    static func seed(store: CollectionStore) {
        let existing = (try? store.context.fetch(FetchDescriptor<MediaCollection>())) ?? []
        guard existing.isEmpty else { return }
        let fetch = Assets.allAssetsFetch()
        var ids: [String] = []
        fetch.enumerateObjects { a, _, _ in ids.append(a.localIdentifier) }
        guard ids.count >= 6 else { return }
        let travel = store.createCollection(name: "Travel", coverIdentifier: ids[0])
        store.add(Array(ids[0..<8]), to: travel)
        let friends = store.createCollection(name: "Friends")
        store.add(Array(ids[3..<10]), to: friends)
        store.setDetails(friends, "Weekends, birthdays and everything in between.")
        let cars = store.createCollection(name: "Cars")
        store.add([ids[1], ids[2]], to: cars)
        _ = store.createCollection(name: "University")
        store.setFavorite([ids[0], ids[2], ids[5]], true)
    }

    /// Compresses real videos from the library and logs results to stdout.
    @MainActor
    static func selfTest() async {
        DebugHarness.log("SELFTEST begin")
        let fetch = Assets.allAssetsFetch(filter: .videos)
        var videos: [PHAsset] = []
        fetch.enumerateObjects { a, _, _ in videos.append(a) }
        DebugHarness.log("SELFTEST videos: \(videos.count)")
        let combos: [(CompressionPreset, OutputResolution)] = [(.balanced, .p720), (.small, .p480), (.high, .original)]
        for (n, asset) in videos.enumerated() {
            do {
                let av = try await VideoLoader.avAsset(for: asset)
                let info = try await VideoSourceInfo.load(from: av)
                DebugHarness.log("SELFTEST [\(n)] source \(Int(info.displaySize.width))x\(Int(info.displaySize.height)) \(info.codec) \(Int(info.frameRate))fps size=\(info.fileSize) dur=\(info.duration) audio=\(info.hasAudio) isURLAsset=\(av is AVURLAsset)")
                for (preset, res) in combos {
                    let plan = CompressionPlan(source: info, preset: preset, resolution: res)
                    let out = MediaExporter.scratchDirectory.appendingPathComponent("selftest-\(n)-\(preset.rawValue)-\(res.rawValue).mp4")
                    let started = Date()
                    try await VideoTranscoder().run(asset: av, source: info, plan: plan, outputURL: out) { _ in }
                    let size = (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let outAsset = AVURLAsset(url: out)
                    let outInfo = try await VideoSourceInfo.load(from: outAsset)
                    DebugHarness.log("SELFTEST [\(n)] \(preset.rawValue)/\(res.rawValue): est=\(plan.estimatedBytes) actual=\(size) out=\(Int(outInfo.displaySize.width))x\(Int(outInfo.displaySize.height)) \(outInfo.codec) dur=\(String(format: "%.2f", outInfo.duration)) audio=\(outInfo.hasAudio) t=\(String(format: "%.1f", Date().timeIntervalSince(started)))s")
                }
                // Cancellation
                let t = VideoTranscoder()
                let plan = CompressionPlan(source: info, preset: .balanced, resolution: .original)
                let out = MediaExporter.scratchDirectory.appendingPathComponent("cancel-\(n).mp4")
                Task { try? await Task.sleep(for: .milliseconds(300)); t.cancel() }
                do { try await t.run(asset: av, source: info, plan: plan, outputURL: out) { _ in }; DebugHarness.log("SELFTEST [\(n)] cancel: finished before cancel") }
                catch CompressionError.cancelled { DebugHarness.log("SELFTEST [\(n)] cancel: OK, file removed=\(!FileManager.default.fileExists(atPath: out.path))") }
                catch { DebugHarness.log("SELFTEST [\(n)] cancel: unexpected \(error)") }
            } catch {
                DebugHarness.log("SELFTEST [\(n)] ERROR \(error)")
            }
        }
        // Inspector
        for asset in [videos.first, Assets.allAssetsFetch(filter: .photos).firstObject].compactMap({ $0 }) {
            let i = await MediaInfo.load(for: asset)
            let size: String = i.fileSize.map { String($0) } ?? i.fileSizeNote ?? "-"
            let fps: String = i.frameRate.map { String($0) } ?? "-"
            DebugHarness.log("SELFTEST inspector video=\(i.isVideo) \(i.resolutionText) format=\(i.format ?? "-") size=\(size) codec=\(i.codec ?? "-") fps=\(fps) name=\(i.filename ?? "-")")
        }
        // Save to photos
        if let url = try? FileManager.default.contentsOfDirectory(at: MediaExporter.scratchDirectory, includingPropertiesForKeys: nil).first(where: { $0.lastPathComponent.hasPrefix("selftest") }) {
            do { try await VideoLoader.saveToPhotos(url: url, matching: videos.first); DebugHarness.log("SELFTEST saveToPhotos OK") }
            catch { DebugHarness.log("SELFTEST saveToPhotos ERROR \(error)") }
        }
        // Share export
        if let a = videos.first, let urls = try? await MediaExporter.shareURLs(for: [a]) { DebugHarness.log("SELFTEST share urls: \(urls.map(\.lastPathComponent))") }
        DebugHarness.log("SELFTEST end")
    }
}
#endif
