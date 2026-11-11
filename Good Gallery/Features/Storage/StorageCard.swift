import SwiftUI

/// iPhone storage summary at the top of Library. Can be minimised; tapping it opens the largest files.
struct StorageCard: View {
    @AppStorage("storage.collapsed") private var collapsed = false
    @State private var storage = DeviceStorage.current()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationLink(value: LibraryRoute.largeFiles) {
            Group {
                if collapsed { compact } else { expanded }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GG.Palette.surface, in: RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { collapsed.toggle() }
                } label: {
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsed ? "Expand storage" : "Minimise storage")
            }
        }
        .buttonStyle(PressableStyle())
        .onAppear { storage = DeviceStorage.current() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { storage = DeviceStorage.current() } }
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iPhone Storage").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            StorageBar(fraction: storage.usedFraction, isLow: storage.isLow)
            HStack {
                Text("\(Format.bytes(storage.used)) of \(Format.bytes(storage.total)) used")
                Spacer()
                Text("\(Format.bytes(storage.free)) free")
            }
            .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if storage.isLow { Image(systemName: "exclamationmark.triangle.fill").font(.footnote) }
                Text(storage.isLow ? "Storage almost full · Free up space" : "See largest files")
                    .font(.footnote.weight(.medium))
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(storage.isLow ? Color.orange : GG.Palette.accent)
        }
        .padding(.trailing, 28)
    }

    private var compact: some View {
        HStack(spacing: 12) {
            Image(systemName: "internaldrive").foregroundStyle(storage.isLow ? .orange : GG.Palette.accent)
            StorageBar(fraction: storage.usedFraction, isLow: storage.isLow).frame(maxWidth: 110)
            Text(storage.isLow ? "\(Format.bytes(storage.free)) free · Free up space" : "\(Format.bytes(storage.free)) free")
                .font(.footnote).foregroundStyle(storage.isLow ? Color.orange : Color.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 36)
    }
}

struct StorageBar: View {
    let fraction: Double
    let isLow: Bool
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(isLow ? Color.orange : GG.Palette.accent)
                    .frame(width: max(8, proxy.size.width * fraction))
            }
        }
        .frame(height: 8)
    }
}
