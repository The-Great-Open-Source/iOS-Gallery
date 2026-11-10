import SwiftUI

// MARK: - Button styles

struct GGPrimaryButtonStyle: ButtonStyle {
    var fullWidth = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(GG.Palette.onAccent)
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(GG.Palette.accent, in: RoundedRectangle(cornerRadius: GG.Radius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct GGSecondaryButtonStyle: ButtonStyle {
    var fullWidth = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .foregroundStyle(GG.Palette.text)
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(GG.Palette.surface, in: RoundedRectangle(cornerRadius: GG.Radius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Layout pieces

struct GGBackground: View {
    var grouped = false
    var body: some View { (grouped ? GG.Palette.grouped : GG.Palette.background).ignoresSafeArea() }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GG.Palette.text)
            Spacer()
            if let trailing {
                Text(trailing).font(.footnote).foregroundStyle(GG.Palette.secondaryText)
            }
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(GG.Palette.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(GG.Palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GGPrimaryButtonStyle(fullWidth: false))
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }
}

struct GGCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GG.Palette.surface, in: RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(GG.Palette.secondaryText)
            Spacer(minLength: 16)
            Text(value).foregroundStyle(GG.Palette.text).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }
}

struct Pill: View {
    let text: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .ggGlass(Capsule())
    }
}

// MARK: - Modifiers

extension View {
    /// Liquid Glass on iOS 26+, translucent material before that.
    @ViewBuilder
    func ggGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else if let tint {
            self.background(tint, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        }
    }

    @available(iOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    /// Applies the Good Gallery screen background and hides default scroll backgrounds.
    func ggScreen(grouped: Bool = false) -> some View {
        self
            .background(GGBackground(grouped: grouped))
            .scrollContentBackground(.hidden)
            .tint(GG.Palette.accent)
    }

    /// iOS 18 zoom transition where available; plain push otherwise.
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else { self }
    }

    @ViewBuilder
    func zoomDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { self }
    }
}

// MARK: - Formatting

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "–" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    static func count(_ n: Int, _ noun: String = "item") -> String {
        "\(n.formatted()) \(noun)\(n == 1 ? "" : "s")"
    }
}
