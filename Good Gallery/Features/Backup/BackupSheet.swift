import SwiftUI
import Photos

/// Manual backup of a set of assets (usually a whole collection) to Google Drive or Telegram.
struct BackupSheet: View {
    let assets: [PHAsset]
    let folderName: String?

    @EnvironmentObject private var engine: BackupEngine
    @ObservedObject private var drive = GoogleDriveService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var destination: BackupDestination = .telegram

    private var available: [BackupDestination] {
        var list: [BackupDestination] = []
        if GoogleDriveConfig.isConfigured && drive.isSignedIn { list.append(.drive) }
        if TelegramService.isConfigured { list.append(.telegram) }
        return list
    }

    var body: some View {
        NavigationStack {
            Group {
                if let summary = engine.summary, !engine.isRunning { SummaryView(summary: summary, destination: engine.destination) }
                else if engine.isRunning { progress }
                else if available.isEmpty { notConfigured }
                else { configure }
            }
            .navigationTitle("Back Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !engine.isRunning { Button(engine.summary == nil ? "Cancel" : "Done") { engine.resetSummary(); dismiss() } }
                }
            }
            .onAppear { engine.resetSummary(); if let first = available.first, !available.contains(destination) { destination = first } }
        }
        .interactiveDismissDisabled(engine.isRunning)
        .presentationDetents([.medium, .large])
    }

    private var configure: some View {
        Form {
            Section {
                if available.count > 1 {
                    Picker("Send to", selection: $destination) { ForEach(available) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented)
                } else if let only = available.first {
                    Label(only.title, systemImage: only.icon)
                }
                LabeledContent("Items", value: assets.count.formatted())
                LabeledContent("Maximum file size", value: sizeText(destination.effectiveLimit))
                if let folderName { LabeledContent(destination == .drive ? "Drive folder" : "Caption", value: folderName) }
            } footer: {
                Text("Originals are sent as files. Items over the size limit are skipped, and items already sent are not sent again.")
            }
            Section {
                Button("Start Backup") { engine.start(assets: assets, to: destination, folderName: folderName) }
                    .disabled(assets.isEmpty)
            }
        }
        .tint(GG.Palette.accent)
    }

    private var progress: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView(value: engine.progress).padding(.horizontal, 40)
            Text("Sending \(min(engine.processed + 1, engine.total)) of \(engine.total)").font(.headline)
            if !engine.currentName.isEmpty { Text(engine.currentName).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            Button("Stop", role: .destructive) { engine.cancel() }
            Spacer()
        }
        .padding()
    }

    private var notConfigured: some View {
        EmptyStateView(icon: "paperplane", title: "No Backup Destination",
                       message: "Set up Telegram or Google Drive in Settings → Backup.")
    }

    private func sizeText(_ bytes: Int64) -> String { Format.bytes(bytes) }
}

private struct SummaryView: View {
    let summary: BackupSummary
    let destination: BackupDestination

    var body: some View {
        List {
            Section {
                row("Sent", summary.sent, "checkmark.circle.fill", .green)
                if summary.alreadyDone > 0 { row("Already sent", summary.alreadyDone, "clock.arrow.circlepath", .secondary) }
                if summary.tooLarge > 0 { row("Skipped (too large)", summary.tooLarge, "arrow.up.right.and.arrow.down.left", .orange) }
                if summary.filteredByType > 0 { row("Skipped (type excluded)", summary.filteredByType, "line.3.horizontal.decrease", .secondary) }
                if summary.failed > 0 { row("Failed", summary.failed, "exclamationmark.triangle.fill", .red) }
            } header: { Text("Sent to \(destination.title)") } footer: {
                if let error = summary.firstError { Text(error) }
            }
        }
    }

    private func row(_ title: String, _ count: Int, _ icon: String, _ color: Color) -> some View {
        HStack { Label { Text(title) } icon: { Image(systemName: icon).foregroundStyle(color) }; Spacer(); Text(count.formatted()).foregroundStyle(.secondary) }
    }
}
