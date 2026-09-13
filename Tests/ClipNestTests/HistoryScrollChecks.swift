import AppKit
import SwiftUI

@main struct HistoryScrollChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        // Process-local preference: do not change the user's system settings.
        UserDefaults.standard.register(defaults: ["AppleShowScrollBars": "Always"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNest-Scroll-\(UUID().uuidString)")
        let board = NSPasteboard.withUniqueName()
        defer { try? FileManager.default.removeItem(at: directory); board.releaseGlobally() }
        let store = HistoryStore(file: directory.appendingPathComponent("history.json"), pasteboard: board, monitoring: false)
        for index in 1...12 { store.insert(text: "历史记录 \(index)", source: "测试") }
        let view = NSHostingView(rootView: HistoryView(store: store, copy: {}, paste: {}, settings: {}))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 250), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 1100, height: 250)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        func scrollViews(in node: NSView) -> [NSScrollView] {
            (node as? NSScrollView).map { [$0] } ?? node.subviews.flatMap(scrollViews)
        }
        let strips = scrollViews(in: view).filter { ($0.documentView?.frame.width ?? 0) > $0.contentSize.width }
        precondition(!strips.isEmpty, "Expected an overflowing native history scroll view")
        for strip in strips {
            precondition(!strip.hasHorizontalScroller && !strip.hasVerticalScroller, "Scrollbars must remain disabled")
            strip.contentView.scroll(to: NSPoint(x: 150, y: 0))
            strip.reflectScrolledClipView(strip.contentView)
            precondition(strip.contentView.bounds.origin.x > 0, "Content must still scroll")
        }
        store.moveSelection(1)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(strips.allSatisfy { !$0.hasHorizontalScroller && !$0.hasVerticalScroller })
        print("PASS: overflowing history hides native scrollbars and remains scrollable")
    }
}
