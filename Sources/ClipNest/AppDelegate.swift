import AppKit
import Carbon
import SwiftUI

final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = HistoryStore(monitoring: false)
    private var statusItem: NSStatusItem!
    private var panel: HistoryPanel!
    private var settingsWindow: NSWindow?
    private var target: NSRunningApplication?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var keyMonitor: Any?
    private var pastePending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.bundleIdentifier == "com.clipnest.sandbox", SandboxValidation.runIfRequested() {
            NSApp.terminate(nil)
            return
        }
        store.startMonitoring()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipNest 剪贴板历史")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.toolTip = "ClipNest · ⌘⇧V"
        panel = HistoryPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "ClipNest"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HistoryView(store: store, copy: { [weak self] in self?.copySelection() }, paste: { [weak self] in self?.paste() }, settings: { [weak self] in self?.showSettings() }))
        registerHotKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleKey(event) == nil
            }
            return consumed ? nil : event
        }
        // A normal Finder launch must show a window even for a menu-bar app.
        // Delay until AppKit has finished its initial activation sequence.
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = launchEvent?.eventID == kAEOpenApplication &&
            launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !CommandLine.arguments.contains("--background") && !loginLaunch {
            DispatchQueue.main.async { [weak self] in self?.showPanel() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard panel != nil else { return true }
        showPanel()
        return false
    }

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerResult = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().togglePanel()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let sandbox = Bundle.main.bundleIdentifier == "com.clipnest.sandbox"
        var shortcut = "⌘⇧V"
        var result = handlerResult
        if handlerResult == noErr {
            result = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x434C504E, id: 1), GetApplicationEventTarget(), 0, &hotKey)
            if result != noErr && sandbox {
                shortcut = "⌃⌘⇧V"
                result = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey | controlKey), EventHotKeyID(signature: 0x434C504E, id: 1), GetApplicationEventTarget(), 0, &hotKey)
            }
        }
        let name = "ClipNest"
        statusItem.button?.toolTip = "\(name) · \(shortcut)"
        if result != noErr {
            store.notice = "\(shortcut) 注册失败（\(result)），请点击菜单栏打开。"
        }
        if sandbox {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SandboxValidation", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let report: [String: Any] = ["shortcut": shortcut, "handlerStatus": handlerResult, "registrationStatus": result]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) {
                try? data.write(to: directory.appendingPathComponent("hotkey.json"), options: .atomic)
            }
        }
    }

    @objc func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { showPanel() }
    }

    func showPanel() {
        guard !pastePending else { return }
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { target = app }
        store.query = ""
        store.previewing = false
        store.reconcileSelection()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let frame = screen.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.minY, width: frame.width,
                              height: min(250, screen.visibleFrame.height)), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === panel { panel.orderOut(nil) }
    }

    private func copySelection() {
        if store.copySelected() { panel.orderOut(nil) }
    }

    private func paste() {
        guard !pastePending, store.selected != nil else { return }
        guard AXIsProcessTrusted() else {
            store.notice = "自动粘贴需要辅助功能权限，请在设置中授权；也可右键记录选择「复制」。"
            return
        }
        guard let target, !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            store.notice = "没有可用的目标应用，请使用「复制」。"
            return
        }
        guard store.copySelected() else { return }
        pastePending = true
        panel.orderOut(nil)
        target.activate()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pastePending = false }
            // Wait for focus to return before posting Cmd-V; never paste into a different app.
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(50))
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier { break }
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                  AXIsProcessTrusted(), let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                self.store.notice = "已复制，但无法自动粘贴；请在目标应用按 ⌘V。"
                return
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            self.store.notice = "已向 \(target.localizedName ?? "原应用") 发送粘贴指令"
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return event }
        let editor = panel.firstResponder as? NSTextView
        let action = KeyboardRouting.action(keyCode: event.keyCode,
                                            editing: editor != nil && !store.query.isEmpty,
                                            composing: editor?.hasMarkedText() == true,
                                            modifiers: event.modifierFlags)
        switch action {
        case .passThrough: return event
        case .dismiss:
            if store.previewing { store.previewing = false } else { panel.orderOut(nil) }
        case .move(let delta): store.moveSelection(delta)
        case .preview: store.previewing.toggle()
        case .paste: paste()
        }
        return nil
    }

    func showSettings() {
        panel.orderOut(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "ClipNest 设置"
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
