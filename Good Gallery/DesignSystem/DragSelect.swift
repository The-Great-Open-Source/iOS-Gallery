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

    /// Swipe sideways across cells to select (or deselect) them, like Photos. Vertical swipes scroll as normal.
    /// Press and hold, then drag, also works in any direction. Near the top/bottom the page auto-scrolls.
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
    @State private var controller = DragSelectController()
    @State private var mode: Bool?
    @State private var touched: Set<String> = []

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(CellFramesKey.self) { frames = $0 }
            .background(DragSelectBridge(controller: controller, isEnabled: isEnabled, configure: configure))
    }

    private func configure(_ controller: DragSelectController) {
        controller.onBegin = { local in
            mode = nil; touched = []
            hit(local)
        }
        controller.onMove = { local in hit(local) }
        controller.onEnd = { mode = nil; touched = [] }
    }

    private func hit(_ local: CGPoint) {
        guard let id = frames.first(where: { $0.value.contains(local) })?.key, !touched.contains(id) else { return }
        if mode == nil { mode = !isSelected(id) }
        touched.insert(id)
        apply(id, mode ?? true)
        Haptics.selection()
    }
}

// MARK: - UIKit

private struct DragSelectBridge: UIViewRepresentable {
    let controller: DragSelectController
    let isEnabled: Bool
    let configure: (DragSelectController) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView(); v.isUserInteractionEnabled = false
        controller.gridView = v
        return v
    }

    func updateUIView(_ view: UIView, context: Context) {
        controller.gridView = view
        controller.isEnabled = isEnabled
        configure(controller)
        // The scroll view only exists once we're in the window hierarchy.
        DispatchQueue.main.async { controller.attachIfNeeded() }
    }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {}
}

/// Owns two recognizers attached to the enclosing UIScrollView:
/// - a pan that **only begins for horizontal motion** (so vertical scrolling is never touched), and
/// - a long-press-then-drag for any direction.
/// UIKit always reports ended/cancelled, so scrolling can never stay locked.
final class DragSelectController: NSObject, UIGestureRecognizerDelegate {
    weak var gridView: UIView?
    var isEnabled = false { didSet { if !isEnabled { unlock() } } }
    var onBegin: ((CGPoint) -> Void)?
    var onMove: ((CGPoint) -> Void)?
    var onEnd: (() -> Void)?

    private let pan = UIPanGestureRecognizer()
    private let hold = UILongPressGestureRecognizer()
    private weak var attached: UIScrollView?
    private var autoScroll: CADisplayLink?
    private var globalPoint: CGPoint = .zero
    private var active = false
    private var pausedRecognizers: [UIGestureRecognizer] = []
    private var pausedScrollViews: [(UIScrollView, Bool)] = []

    override init() {
        super.init()
        pan.addTarget(self, action: #selector(handle(_:)))
        hold.addTarget(self, action: #selector(handle(_:)))
        hold.minimumPressDuration = 0.25
        hold.allowableMovement = 12
        for g in [pan, hold] as [UIGestureRecognizer] {
            g.delegate = self
            g.cancelsTouchesInView = false
            g.delaysTouchesBegan = false
        }
    }

    var scrollView: UIScrollView? {
        var current = gridView?.superview
        while let candidate = current {
            if let scroll = candidate as? UIScrollView { return scroll }
            current = candidate.superview
        }
        return nil
    }

    func attachIfNeeded() {
        guard let scroll = scrollView, attached !== scroll else { return }
        detach()
        scroll.addGestureRecognizer(pan)
        scroll.addGestureRecognizer(hold)
        attached = scroll
    }

    func detach() {
        attached?.removeGestureRecognizer(pan)
        attached?.removeGestureRecognizer(hold)
        attached = nil
    }

    deinit { detach(); autoScroll?.invalidate() }

    // MARK: Delegate

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard isEnabled, let grid = gridView, grid.window != nil else { return false }
        guard grid.bounds.contains(recognizer.location(in: grid)) else { return false }
        if recognizer === pan {
            let v = pan.velocity(in: attached)
            return abs(v.x) > abs(v.y) * 1.1          // sideways only; vertical belongs to the scroll view
        }
        return true
    }

    func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
        // Only cooperate with the page's own scroll view; everything else must not fire together with us.
        b === attached?.panGestureRecognizer || a === attached?.panGestureRecognizer
    }

    /// Other pans (tab swiping, interactive back swipe…) must wait until our sideways pan has decided.
    func gestureRecognizer(_ a: UIGestureRecognizer, shouldBeRequiredToFailBy b: UIGestureRecognizer) -> Bool {
        isEnabled && a === pan && b is UIPanGestureRecognizer && b !== attached?.panGestureRecognizer
    }

    // MARK: Handling

    @objc private func handle(_ recognizer: UIGestureRecognizer) {
        guard let grid = gridView else { return }
        let local = recognizer.location(in: grid)
        globalPoint = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            if recognizer === hold { Haptics.impact(.light) }
            active = true
            attached?.isScrollEnabled = false
            pauseAncestors()
            startAutoScroll()
            onBegin?(local)
        case .changed:
            if active { onMove?(local) }
        case .ended, .cancelled, .failed:
            unlock()
        default: break
        }
    }

    private func unlock() {
        let wasActive = active
        active = false
        autoScroll?.invalidate(); autoScroll = nil
        attached?.isScrollEnabled = true
        resumeAncestors()
        if wasActive { onEnd?() }
    }

    // MARK: Pausing competing gestures

    /// While selecting, nothing above the grid may react to the same swipe (tab paging, back swipe, outer scrolling).
    private func pauseAncestors() {
        resumeAncestors()
        var view = attached?.superview
        while let current = view {
            if let scroll = current as? UIScrollView { pausedScrollViews.append((scroll, scroll.isScrollEnabled)); scroll.isScrollEnabled = false }
            for g in current.gestureRecognizers ?? [] where g is UIPanGestureRecognizer && g !== pan && g.isEnabled {
                g.isEnabled = false
                pausedRecognizers.append(g)
            }
            view = current.superview
        }
    }

    private func resumeAncestors() {
        pausedRecognizers.forEach { $0.isEnabled = true }
        pausedRecognizers = []
        pausedScrollViews.forEach { $0.0.isScrollEnabled = $0.1 }
        pausedScrollViews = []
    }

    // MARK: Auto-scroll near the edges

    private func startAutoScroll() {
        autoScroll?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        autoScroll = link
    }

    @objc private func tick() {
        guard active, let scroll = attached, let grid = gridView else { return }
        let frame = scroll.convert(scroll.bounds, to: nil)
        let inset = scroll.adjustedContentInset
        let top = frame.minY + inset.top
        let bottom = frame.maxY - max(inset.bottom, 90)       // floating toolbars sit over the grid
        let zone = max(120, (bottom - top) * 0.22)
        let y = globalPoint.y
        var delta: CGFloat = 0
        if y < top + zone { delta = -speed(top + zone - y, zone) }
        else if y > bottom - zone { delta = speed(y - (bottom - zone), zone) }
        guard delta != 0 else { return }
        let minY = -inset.top
        let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
        let target = min(max(scroll.contentOffset.y + delta, minY), maxY)
        guard abs(target - scroll.contentOffset.y) > 0.01 else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: false)
        // The finger hasn't moved but the content has, so re-test what's under it.
        onMove?(grid.convert(globalPoint, from: nil))
    }

    private func speed(_ depth: CGFloat, _ zone: CGFloat) -> CGFloat { 6 + 22 * min(depth / zone, 1.5) }
}
