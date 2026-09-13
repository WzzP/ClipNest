import SwiftUI

/// Enforces the history strip's no-scrollbar design even with macOS's
/// "Show scroll bars: Always" preference. Scrolling itself stays enabled.
struct ScrollIndicatorSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.scheduleUpdate() }

    final class Probe: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleUpdate()
        }

        override func layout() {
            super.layout()
            suppressIndicators()
        }

        func scheduleUpdate() {
            DispatchQueue.main.async { [weak self] in self?.suppressIndicators() }
        }

        private func suppressIndicators() {
            guard let scrollView = enclosingScrollView else { return }
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
        }
    }
}
