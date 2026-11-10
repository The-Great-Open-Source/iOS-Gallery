import SwiftData
import SwiftUI
import SwiftData
import Photos

enum AppInfo {
    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
    /// Placeholder address — replace before shipping.
    static let feedbackEmail = "feedback@goodgallery.app"
}

struct SettingsView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("appearance") private var appearanceRaw = AppearancePreference.dark.rawValue
    @State private var scratchBytes: Int64 = 0
    @State private var databaseBytes: Int64 = 0
    @State private var cacheCleared = false

    private var statusText: String {
        switch library.status {
        case .authorized: "Full Access"
        case .limited: "Limited Access"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not Requested"
        @unknown default: "Unknown"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRaw) {
                        ForEach(AppearancePreference.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(GlassRowBackground())

                Section {
                    LabeledContent("Photos access", value: statusText)
                    if library.isLimited {
                        Button("Select More Photos") { library.presentLimitedPicker() }
                    }
                    Button("Open System Settings") { library.openSystemSettings() }
                } header: { Text("Photo Library") } footer: {
                    Text("Good Gallery reads your photos to show and organise them. It never copies, uploads, or modifies your originals.")
                }
                .listRowBackground(GlassRowBackground())

                Section("Storage & Cache") {
                    LabeledContent("Collections database", value: Format.bytes(databaseBytes))
                    LabeledContent("Thumbnail cache (max)", value: Format.bytes(Int64(ImageLoader.shared.cacheLimitBytes)))
                    LabeledContent("Temporary files", value: Format.bytes(scratchBytes))
                    Button(cacheCleared ? "Cleared" : "Clear Caches & Temporary Files") {
                        ImageLoader.shared.clearCache()
                        MediaExporter.clearScratch()
                        cacheCleared = true
                        refreshSizes()
                    }
                }
                .listRowBackground(GlassRowBackground())

                Section("About") {
                    NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    NavigationLink("About Good Gallery") { AboutView() }
                    Button("Send Feedback") {
                        if let url = URL(string: "mailto:\(AppInfo.feedbackEmail)?subject=Good%20Gallery%20Feedback") { openURL(url) }
                    }
                    LabeledContent("Version", value: AppInfo.version)
                }
                .listRowBackground(GlassRowBackground())
            }
            .foregroundStyle(GG.Palette.text)
            .ggScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { refreshSizes() }
        }
        .presentationBackground { GGBackground() }
    }

    private func refreshSizes() {
        scratchBytes = MediaExporter.scratchSize()
        let url = ModelConfiguration().url
        let base = url.deletingLastPathComponent()
        let names = [url.lastPathComponent, url.lastPathComponent + "-wal", url.lastPathComponent + "-shm"]
        databaseBytes = names.reduce(0) { total, name in
            total + Int64((try? base.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Privacy").font(GG.Typography.editorial(32)).foregroundStyle(GG.Palette.text)
                block("Your media stays on your device",
                      "Good Gallery never uploads, transmits, or shares your photos or videos. All organising, searching, and video compression happens locally.")
                block("What we store",
                      "Only lightweight metadata: your collection names, descriptions, which photos you placed in each collection (as references to your Photos library), your Good Gallery favorites, and a short history of video compressions. This data lives only on this device.")
                block("What we never do",
                      "No accounts, no analytics, no advertising, no tracking, and no third-party SDKs. We don't collect personal information.")
                block("Photos permission",
                      "Good Gallery asks for access to your photo library so it can display your photos. You can grant Limited Access to share only selected photos, and change this at any time in iOS Settings. Removing a photo from a collection never deletes it. The only time Good Gallery can delete a photo is when you explicitly choose “Delete Original” after compressing a video, and iOS asks you to confirm.")
                block("Location", "If a photo contains location metadata, the Media Inspector shows its coordinates. They're read on-device and never sent anywhere.")
            }
            .padding(GG.Spacing.page)
        }
        .ggScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(GG.Palette.accent)
            Text(text).font(.subheadline).foregroundStyle(GG.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "photo.stack").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(GG.Palette.accent)
            Text("Good Gallery").font(GG.Typography.editorial(38, weight: .medium)).foregroundStyle(GG.Palette.text)
            Text("A better home for your memories.").font(GG.Typography.editorial(17)).italic().foregroundStyle(GG.Palette.accent)
            Text("Organise your existing photos and videos into collections that reflect your life — without moving or duplicating a single file.")
                .font(.subheadline).foregroundStyle(GG.Palette.secondaryText).multilineTextAlignment(.center)
                .padding(.horizontal, 36).padding(.top, 8)
            Text("Version \(AppInfo.version)").font(.footnote).foregroundStyle(GG.Palette.secondaryText).padding(.top, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .ggScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}
