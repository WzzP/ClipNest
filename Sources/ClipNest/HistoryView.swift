import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Bindable var store: HistoryStore
    var copy: () -> Void
    var paste: () -> Void
    var settings: () -> Void
    @FocusState private var searching: Bool
    @State private var deleteCandidate: Clip?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            if store.previewing, let clip = store.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(clip.source, systemImage: clip.kind == "链接" ? "link" : "text.alignleft")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("关闭预览") { store.previewing = false }
                        }
                        if clip.image != nil {
                            ClipThumbnail(url: store.imageURL(for: clip), maxPixelSize: 1600)
                                .frame(maxWidth: .infinity).frame(height: 130)
                        } else if let urls = clip.fileURLs {
                            ForEach(urls, id: \.self) { url in
                                HStack {
                                    Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .item)).resizable().frame(width: 24, height: 24)
                                    Text(url.path).textSelection(.enabled)
                                }
                            }
                        } else {
                            Text(clip.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(16)
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            } else if store.filtered.isEmpty {
                ContentUnavailableView {
                    Label(store.query.isEmpty ? (store.favoritesOnly ? "还没有收藏" : "给灵感留一个位置") : "没有匹配的记录", systemImage: "clipboard")
                } description: {
                    Text(store.query.isEmpty ? (store.favoritesOnly ? "选中一条历史，点击星标保存常用片段。" : "复制文字、图片或文件，ClipNest 会把它记录在这里。") : "试试其他关键词，或清除搜索。")
                } actions: {
                    if !store.query.isEmpty { Button("清除搜索") { store.query = "" } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(store.filtered) { clip in
                                ClipCard(store: store, clip: clip, selected: store.selectedID == clip.id)
                                    .onTapGesture(count: 2) { store.selectedID = clip.id; searching = false; paste() }
                                    .simultaneousGesture(TapGesture().onEnded {
                                        store.selectedID = clip.id
                                        searching = false
                                    })
                                    .contextMenu {
                                        Button("复制") { store.selectedID = clip.id; copy() }
                                        Button(clip.favorite ? "取消收藏" : "收藏") { store.toggleFavorite(clip.id) }
                                        Divider()
                                        Button("删除…", role: .destructive) { deleteCandidate = clip }
                                    }
                                    .accessibilityAction(named: "选择") { store.selectedID = clip.id; searching = false }
                                    .accessibilityAction(named: "复制") { store.selectedID = clip.id; copy() }
                                    .id(clip.id)
                            }
                        }.padding(3)
                    }
                    .onChange(of: store.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
            footer
            if let error = store.storageError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            } else {
                Text(store.notice.isEmpty ? store.captureStatus : store.notice)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.18)).frame(height: 1) }
        .onAppear { searching = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in searching = true }
        .onChange(of: store.query) { _, _ in store.reconcileSelection() }
        .onChange(of: store.favoritesOnly) { _, _ in store.reconcileSelection() }
        .alert("删除这条记录？", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button("取消", role: .cancel) { deleteCandidate = nil }
            Button("删除", role: .destructive) { if let clip = deleteCandidate { store.delete(clip.id) }; deleteCandidate = nil }
        } message: { Text("删除后无法恢复。") }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 24, height: 24)
                Text("ClipNest").font(.system(size: 18, weight: .semibold))
            }
            Picker("显示", selection: $store.favoritesOnly) {
                Text("全部").tag(false)
                Text("收藏").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 110)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索内容、应用…", text: $store.query).textFieldStyle(.plain).focused($searching)
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("清除搜索")
                }
            }.padding(6).background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            Button("读取当前剪贴板") { store.notice = ""; store.readCurrentClipboard() }
                .help("重新读取当前剪贴板中的文本、图片或文件")
            Button { store.paused.toggle() } label: {
                Image(systemName: store.paused ? "play.fill" : "pause.fill")
            }.help(store.paused ? "恢复记录" : "暂停记录").accessibilityLabel(store.paused ? "恢复记录" : "暂停记录")
            Button(action: settings) { Image(systemName: "gearshape") }.help("设置").accessibilityLabel("设置")
        }
    }

    private var footer: some View {
        HStack {
            Label(store.paused ? "记录已暂停" : "本机保存", systemImage: store.paused ? "pause.circle" : "internaldrive")
                .foregroundStyle(store.paused ? .orange : .secondary)
            Text("· \(store.filtered.count) 条").foregroundStyle(.secondary)
            Spacer()
            Text("↑ ↓ 选择  ·  ↵ 粘贴").foregroundStyle(.secondary)
            Button { store.previewing.toggle(); searching = false } label: { Image(systemName: "eye") }
                .help("预览（卡片选中时按空格）").accessibilityLabel("预览").disabled(store.selected == nil)
            Button {
                if let clip = store.selected { store.toggleFavorite(clip.id) }
            } label: { Image(systemName: store.selected?.favorite == true ? "star.fill" : "star") }
                .accessibilityLabel(store.selected?.favorite == true ? "取消收藏" : "收藏").disabled(store.selected == nil)
            Button("复制", action: copy).disabled(store.selected == nil)
            Button("粘贴 ↵", action: paste).buttonStyle(.borderedProminent).disabled(store.selected == nil)
        }.font(.caption)
    }
}

private struct ClipThumbnail: View {
    let url: URL?
    let maxPixelSize: Int
    @State private var image: NSImage?
    @State private var loading = true

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if loading {
                ProgressView().controlSize(.small)
            } else {
                Label("图片无法读取", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: "\(url?.path ?? "")-\(maxPixelSize)") {
            image = nil
            loading = true
            let data: Data?
            if let url { data = await ThumbnailLoader.shared.load(url: url, maxPixelSize: maxPixelSize) }
            else { data = nil }
            guard !Task.isCancelled else { return }
            image = data.flatMap { NSImage(data: $0) }
            loading = false
        }
    }
}

private struct SourceAppIcon: View {
    var bundleID: String?
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable() }
            else { Image(systemName: "app.dashed").resizable().padding(3) }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
        .task(id: bundleID) {
            icon = nil
            if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            }
        }
    }
}

private struct ClipCard: View {
    var store: HistoryStore
    var clip: Clip
    var selected: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                SourceAppIcon(bundleID: clip.sourceBundleID)
                Text(clip.source).lineLimit(1)
                Spacer(minLength: 4)
                Text(clip.kind).fixedSize()
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 32)

            Divider()

            content
                .frame(width: 190, height: 72, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)

            HStack(spacing: 4) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(relativeTime(at: context.date)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if clip.favorite { Image(systemName: "star.fill").foregroundStyle(.tint) }
                Text(clip.detail).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 27)
        }
        .frame(width: 210, height: 142)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: selected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clip.source)，\(clip.kind)，\(clip.title)\(clip.favorite ? "，已收藏" : "")")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
    }

    @ViewBuilder private var content: some View {
        if clip.image != nil {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .underPageBackgroundColor))
                ClipThumbnail(url: store.imageURL(for: clip), maxPixelSize: 440)
                    .frame(width: 182, height: 68)
            }.frame(width: 190, height: 72)
        } else if let urls = clip.fileURLs, let first = urls.first {
            HStack(alignment: .top, spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: first.pathExtension) ?? .item)).resizable().frame(width: 30, height: 30)
                Text(clip.text).font(.system(size: 12, weight: .medium)).lineLimit(4)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(String(clip.text.prefix(500)))
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineSpacing(2)
                .lineLimit(4)
                .frame(width: 190, height: 72, alignment: .topLeading)
        }
    }

    private func relativeTime(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(clip.date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }
        if seconds < 86400 { return "\(seconds / 3600) 小时前" }
        return "\(seconds / 86400) 天前"
    }
}

struct SettingsView: View {
    @Bindable var store: HistoryStore
    @State private var confirmingClear = false
    @State private var accessibilityAllowed = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("常规") {
                LoginItemSettings()
                LabeledContent("唤出快捷键", value: "⌘ ⇧ V")
                Picker("历史数量上限", selection: $store.limit) {
                    Text("50 条").tag(50)
                    Text("200 条").tag(200)
                    Text("500 条").tag(500)
                    Text("1,000 条").tag(1000)
                }
                Toggle("暂停记录", isOn: $store.paused)
            }
            Section("自动粘贴") {
                LabeledContent("辅助功能", value: accessibilityAllowed ? "当前版本已授权" : "当前版本未获系统授权")
                HStack {
                    Button("打开辅助功能设置") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Button("重新检查") { accessibilityAllowed = AXIsProcessTrusted() }
                }
                if !accessibilityAllowed {
                    Text("若开关已打开，请移除旧 ClipNest，再添加当前应用并开启。开发版更新后签名可能变化；重新授权后重启应用。复制历史不需要辅助功能权限。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("在 Finder 中显示当前应用") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
            }
            Section("隐私与存储") {
                Text("排除应用的 Bundle ID（每行一个）").font(.caption)
                TextEditor(text: $store.excludedApplications).font(.system(.caption, design: .monospaced)).frame(height: 64)
                Text("仅保存在本机；尊重敏感剪贴板标记。收藏不受数量上限影响。").font(.caption).foregroundStyle(.secondary)
                Button("在 Finder 中显示历史文件") { NSWorkspace.shared.selectFile(store.storagePath, inFileViewerRootedAtPath: "") }
                Button("清空普通历史…", role: .destructive) { confirmingClear = true }
                if let error = store.storageError { Text(error).foregroundStyle(.red).font(.caption) }
            }
            HStack {
                Text("ClipNest · 剪贴巢 0.1").foregroundStyle(.secondary)
                Spacer()
                Button("退出 ClipNest") { NSApplication.shared.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityAllowed = AXIsProcessTrusted()
        }
        .alert("清空普通历史？", isPresented: $confirmingClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.clearHistory() }
        } message: { Text("收藏会保留。其他记录将永久删除。") }
    }
}
