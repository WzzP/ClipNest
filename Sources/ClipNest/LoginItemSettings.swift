import SwiftUI
import ServiceManagement

struct LoginItemSettings: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage: String?
    @State private var updating = false
    private var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var body: some View {
        Toggle("登录时启动 ClipNest", isOn: Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: { enabled in update(enabled) }
        ))
        .disabled(updating || !isAppBundle)

        if !isAppBundle {
            Text("请运行打包后的 ClipNest.app，再开启登录启动。")
                .font(.caption).foregroundStyle(.secondary)
        } else if status == .requiresApproval {
            HStack {
                Text("等待系统允许登录启动").font(.caption).foregroundStyle(.secondary)
                Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        if let errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(.red)
        }
        Text("开启后，登录 macOS 时在菜单栏后台运行，不自动展开历史面板。")
            .font(.caption).foregroundStyle(.secondary)
            .onAppear { refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        status = SMAppService.mainApp.status
    }

    private func update(_ enabled: Bool) {
        guard !updating else { return }
        updating = true
        errorMessage = nil
        Task { @MainActor in
            defer { refresh(); updating = false }
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status != .notRegistered {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                errorMessage = "登录启动设置失败：\(error.localizedDescription)"
            }
        }
    }
}
