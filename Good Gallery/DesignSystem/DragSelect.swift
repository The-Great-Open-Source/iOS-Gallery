import SwiftUI
import UIKit

/// Collects each cell's frame (in the grid's coordinate space) so a drag can be hit-tested against cells.
private struct CellFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Mark a grid cell so `dragToSelect` can find it.
    func trackFrame(id: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: CellFramesKey.self, value: [id: proxy.frame(in: .named(DragSelectModifier.space))])
        })
    }

    /// Press-and-hold, then slide across cells to select (or deselect) all of them in one motion — like Photos.
    /// The first cell touched decides the mode: starting on an unselected cell selects, otherwise deselects.
    func dragToSelect(isEnabled: Bool, isSelected: @escaping (String) -> Bool, apply: @escaping (String, Bool) -> Void) -> some View {
        modifier(DragSelectModifier(isEnabled: isEnabled, isSelected: isSelected, apply: apply))
    }
}

struct DragSelectModifier: ViewModifier {
    static let space = "dragSelectSpace"

    let isEnabled: Bool
    let isSelected: (String) -> Bool
    let apply: (String, Bool) -> Void

    @State private var frames: [String: CGRect] = [:]
    @State private var dragging = false
    @State private var mode: Bool?
    @State private var touched: Set<String> = []

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(CellFramesKey.self) { frames = $0 }
            .background(ScrollLocker(locked: dragging))
            .simultaneousGesture(gesture, including: isEnabled ? .all : .none)
            .onChange(of: isEnabled) { _, enabled in if !enabled { finish() } }
            .onDisappear { finish() }
    }

    private var gesture: some Gesture {
        LongPressGesture(minimumDuration: 0.22)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !dragging { dragging = true; Haptics.impact(.light) }
                if let point = drag?.location { handle(point) }
            }
            .onEnded { _ in finish() }
    }

    private func handle(_ point: CGPoint) {
        guard let id = frames.first(where: { $0.value.contains(point) })?.key, !touched.contains(id) else { return }
        if mode == nil { mode = !isSelected(id) }
        touched.insert(id)
        apply(id, mode ?? true)
        Haptics.selection()
    }

    private func finish() {
        dragging = false
        mode = nil
        touched = []
    }
}

/// Temporarily freezes the enclosing UIScrollView so a drag-selection doesn't also scroll the page.
private struct ScrollLocker: UIViewRepresentable {
    let locked: Bool
    func makeUIView(context: Context) -> UIView { let v = UIView(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            var current = view.superview
            while let candidate = current {
                if let scroll = candidate as? UIScrollView { scroll.isScrollEnabled = !locked; return }
                current = candidate.superview
            }
        }
    }
}
