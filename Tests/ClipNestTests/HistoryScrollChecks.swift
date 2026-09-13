import AppKit
import SwiftUI

@main struct HistoryScrollChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        if CommandLine.arguments.contains("--screenshot") { app.applicationIconImage = NSImage(contentsOfFile: "docs/assets/app-icon.png") }
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
        if CommandLine.arguments.contains("--screenshot") {
            store.clearHistory()
            for (text, source) in [("周末计划\n整理书桌，读完一本书，去公园散步。", "备忘录"), ("https://github.com/WzzP/ClipNest", "Safari"), ("会议纪要\n确认本周安排，周五一起回顾进展。", "备忘录"), ("让复制过的内容，随时找得到。", "ClipNest")] {
                store.insert(text: text, source: source)
            }
            store.toggleFavorite(store.clips[0].id)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/assets/app-screenshot.png"))
        }
        print("PASS: overflowing history hides native scrollbars and remains scrollable")
    }
}
