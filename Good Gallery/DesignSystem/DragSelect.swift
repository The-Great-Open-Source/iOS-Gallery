import SwiftUI
import UIKit

/// Collects each cell's frame (in the grid's own coordinate space, so it doesn't change while scrolling).
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

    /// Swipe across cells to select (or deselect) them all in one motion, like Photos.
    ///
    /// - A mostly **horizontal** swipe starts selecting; a vertical swipe still scrolls normally.
    /// - Or press and hold a cell, then drag in any direction.
    /// - The first cell touched decides the mode: unselected → select, selected → deselect.
    /// - Near the top/bottom edge the page auto-scrolls so you can keep going.
    func dragToSelect(isEnabled: Bool, isSelected: @escaping (String) -> Bool, apply: @escaping (String, Bool) -> Void) -> some View {
        modifier(DragSelectModifier(isEnabled: isEnabled, isSelected: isSelected, apply: apply))
    }
}

struct DragSelectModifier: ViewModifier {
    static let space = "dragSelectSpace"

    let isEnabled: Bool
    let isSelected: (String) -> Bool
    let apply: (String, Bool) -> Void

    private enum Source { case swipe, hold }

    @State private var frames: [String: CGRect] = [:]
    @State private var bridge = ScrollBridge()
    @State private var scroller = AutoScroller()
    @State private var source: Source?
    @State private var rejectedSwipe = false
    @State private var mode: Bool?
    @State private var touched: Set<String> = []
    @State private var lastGlobal: CGPoint = .zero
    // GestureState resets automatically when a gesture ends *or is cancelled*, so the scroll lock can never get stuck.
    @GestureState private var swipeActive = false
    @GestureState private var holdActive = false

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(CellFramesKey.self) { frames = $0 }
            .background(ScrollBridgeView(bridge: bridge))
            .simultaneousGesture(swipeGesture, including: isEnabled ? .all : .none)
            .simultaneousGesture(holdGesture, including: isEnabled ? .all : .none)
            .onChange(of: isEnabled) { _, enabled in if !enabled { finish() } }
            .onChange(of: swipeActive) { _, active in if !active { finish() } }
            .onChange(of: holdActive) { _, active in if !active { finish() } }
            .onDisappear { finish() }
    }

    // MARK: Gestures

    /// Quick swipe: decides on the first movement whether it's a selection (horizontal) or a scroll (vertical).
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($swipeActive) { _, state, _ in state = true }
            .onChanged { value in
                if source == .hold || rejectedSwipe { return }
                if source == nil {
                    bridge.setScrollEnabled(true)          // safety: a new touch always starts unlocked
                    let dx = abs(value.translation.width), dy = abs(value.translation.height)
                    guard dx > dy * 0.9 else { rejectedSwipe = true; return }   // vertical: let the page scroll
                    begin(.swipe)
                    handle(globalPoint: value.startLocation)
                }
                move(to: value.location)
            }
            .onEnded { _ in finish() }
    }

    /// Press and hold, then drag in any direction.
    private var holdGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.22)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($holdActive) { value, state, _ in if case .second(true, _) = value { state = true } }
            .onChanged { value in
                guard case .second(true, let drag) = value, source != .swipe else { return }
                if source == nil { begin(.hold); Haptics.impact(.light) }
                if let point = drag?.location { move(to: point) }
            }
            .onEnded { _ in finish() }
    }

    // MARK: Selection

    private func begin(_ new: Source) {
        source = new
        bridge.setScrollEnabled(false)
        scroller.start(bridge: bridge) { handle(globalPoint: lastGlobal) }
    }

    private func move(to globalPoint: CGPoint) {
        lastGlobal = globalPoint
        scroller.update(globalPoint: globalPoint)
        handle(globalPoint: globalPoint)
    }

    private func handle(globalPoint: CGPoint) {
        guard let local = bridge.localPoint(fromGlobal: globalPoint),
              let id = frames.first(where: { $0.value.contains(local) })?.key, !touched.contains(id) else { return }
        if mode == nil { mode = !isSelected(id) }
        touched.insert(id)
        apply(id, mode ?? true)
        Haptics.selection()
    }

    private func finish() {
        scroller.stop()
        bridge.setScrollEnabled(true)
        source = nil
        rejectedSwipe = false
        mode = nil
        touched = []
    }
}

// MARK: - UIKit bridge

/// Finds the enclosing UIScrollView so selection can freeze it and auto-scroll it.
final class ScrollBridge {
    weak var view: UIView?
    var scrollView: UIScrollView? {
        var current = view?.superview
        while let candidate = current {
            if let scroll = candidate as? UIScrollView { return scroll }
            current = candidate.superview
        }
        return nil
    }
    func setScrollEnabled(_ enabled: Bool) { scrollView?.isScrollEnabled = enabled }
    /// Converts a window-space point into the grid's coordinate space (accounts for current scroll offset).
    func localPoint(fromGlobal point: CGPoint) -> CGPoint? { view?.convert(point, from: nil) }
}

private struct ScrollBridgeView: UIViewRepresentable {
    let bridge: ScrollBridge
    func makeUIView(context: Context) -> UIView {
        let v = UIView(); v.isUserInteractionEnabled = false
        bridge.view = v
        return v
    }
    func updateUIView(_ view: UIView, context: Context) { bridge.view = view }
}

/// Scrolls the page while a drag-selection is held near the top or bottom edge.
final class AutoScroller {
    private var link: CADisplayLink?
    private weak var bridge: ScrollBridge?
    private var onTick: (() -> Void)?
    private var globalPoint: CGPoint = .zero

    func start(bridge: ScrollBridge, onTick: @escaping () -> Void) {
        stop()
        self.bridge = bridge
        self.onTick = onTick
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func update(globalPoint: CGPoint) { self.globalPoint = globalPoint }

    func stop() { link?.invalidate(); link = nil; onTick = nil }

    @objc private func tick() {
        guard let scroll = bridge?.scrollView else { return }
        let frame = scroll.convert(scroll.bounds, to: nil)          // window space
        let inset = scroll.adjustedContentInset
        let top = frame.minY + inset.top
        // Floating toolbars sit over the grid, so start the bottom zone well above the screen edge.
        let bottom = frame.maxY - max(inset.bottom, 90)
        let zone = max(120, (bottom - top) * 0.22)
        var delta: CGFloat = 0
        if globalPoint.y < top + zone { delta = -speed(top + zone - globalPoint.y, zone) }
        else if globalPoint.y > bottom - zone { delta = speed(globalPoint.y - (bottom - zone), zone) }
        guard delta != 0 else { return }
        let minY = -inset.top
        let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
        let target = min(max(scroll.contentOffset.y + delta, minY), maxY)
        guard abs(target - scroll.contentOffset.y) > 0.01 else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: false)
        onTick?()
    }

    private func speed(_ depth: CGFloat, _ zone: CGFloat) -> CGFloat { 6 + 22 * min(depth / zone, 1.5) }
}
