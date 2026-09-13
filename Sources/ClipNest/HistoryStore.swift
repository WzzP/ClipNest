import AppKit
import Observation
import CryptoKit
import ImageIO

struct ImageAttachment: Codable, Equatable {
    var filename: String
    var pasteboardType: String
    var width: Int
    var height: Int
    var byteCount: Int
}

struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var source: String
    var sourceBundleID: String?
    var image: ImageAttachment?
    var fileURLs: [URL]?
    var date = Date()
    var favorite = false

    var title: String { String(text.split(whereSeparator: \.isNewline).first.map(String.init)?.prefix(100) ?? text.prefix(100)) }
    var detail: String {
        if let image { return "\(image.width) × \(image.height)" }
        if let fileURLs { return "\(fileURLs.count) 个项目" }
        return "\(text.count) 字符"
    }
    var kind: String {
        if image != nil { return "图片" }
        if fileURLs != nil { return "文件" }
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: \.isWhitespace) else { return "文本" }
        return "链接"
    }
}

@MainActor @Observable
final class HistoryStore {
    private(set) var clips: [Clip] = []
    var query = ""
    var favoritesOnly = false
    var selectedID: UUID?
    var previewing = false
    var notice = ""
    private(set) var captureStatus = "等待复制文本、图片或文件"
    private(set) var storageError: String?
    var paused = false {
        didSet { defaults.set(paused, forKey: "paused"); lastChange = pasteboard.changeCount }
    }
    var limit = 200 {
        didSet { defaults.set(limit, forKey: "limit"); trim(); save() }
    }
    var excludedApplications = "com.agilebits.onepassword7\ncom.1password.1password" {
        didSet { defaults.set(excludedApplications, forKey: "excludedApplications") }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChange: Int
    @ObservationIgnored private var canSave = true
    @ObservationIgnored private var hasLoadedHistory = false
    @ObservationIgnored private var lastAccessBehavior: Int?
    @ObservationIgnored private let thumbnailCache = NSCache<NSString, NSImage>()

    init(file: URL? = nil, defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general, monitoring: Bool = true) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipNest/history.json")
        lastChange = pasteboard.changeCount
        paused = defaults.bool(forKey: "paused")
        if defaults.object(forKey: "limit") != nil { limit = max(50, defaults.integer(forKey: "limit")) }
        if let value = defaults.string(forKey: "excludedApplications") { excludedApplications = value }
        do {
            if FileManager.default.fileExists(atPath: self.file.path) {
                clips = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: self.file))
            }
        } catch {
            canSave = false
            storageError = "无法读取历史文件，已停止写入以保护原文件。请检查设置中的存储位置。"
        }
        hasLoadedHistory = true
        selectedID = clips.first?.id
        if monitoring { startMonitoring() }
    }

    func startMonitoring() {
        guard timer == nil else { return }
        // Include the existing clipboard; do not wait for a new changeCount.
        lastChange = -1
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.05
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        poll(initialSnapshot: true)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func readCurrentClipboard() {
        guard !paused else { captureStatus = "记录已暂停，恢复后再读取"; return }
        lastChange = -1
        poll(initialSnapshot: true)
    }

    var filtered: [Clip] {
        clips.filter { (!favoritesOnly || $0.favorite) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query)) }
    }
    var selected: Clip? { filtered.first { $0.id == selectedID } }
    var storagePath: String { file.path }

    func reconcileSelection() {
        if !filtered.contains(where: { $0.id == selectedID }) { selectedID = filtered.first?.id }
    }

    func moveSelection(_ delta: Int) {
        let items = filtered
        guard !items.isEmpty else { return }
        let index = items.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = items[min(max(index + delta, 0), items.count - 1)].id
    }

    func poll(initialSnapshot: Bool = false) {
        guard !paused else { lastChange = pasteboard.changeCount; return }
        if #available(macOS 15.4, *) {
            let behavior = pasteboard.accessBehavior
            if lastAccessBehavior != behavior.rawValue {
                lastAccessBehavior = behavior.rawValue
                if behavior == .alwaysAllow { lastChange = -1 }
            }
            if behavior == .alwaysDeny {
                captureStatus = "剪贴板读取被系统拒绝，请在系统设置中允许 ClipNest 从其他应用粘贴"
                return
            }
        }
        let change = pasteboard.changeCount
        guard change != lastChange else { return }
        lastChange = change
        let blockedTypes = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"]
        let types = (pasteboard.pasteboardItems?.flatMap { $0.types.map(\.rawValue) } ?? pasteboard.types?.map(\.rawValue)) ?? []
        guard !blockedTypes.contains(where: types.contains) else {
            captureStatus = "已跳过带敏感或临时标记的内容"
            return
        }
        let app = NSWorkspace.shared.frontmostApplication
        let excluded = excludedApplications.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !excluded.contains(app?.bundleIdentifier ?? "") else {
            captureStatus = "已跳过排除应用的内容"
            return
        }
        let source = initialSnapshot ? "当前剪贴板" : (app?.localizedName ?? "未知应用")
        let bundleID = initialSnapshot ? nil : app?.bundleIdentifier
        // Finder supplies both URLs and text; keep the file semantics first.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            guard pasteboard.changeCount == change else { lastChange = -1; return }
            insertClip(Clip(text: urls.map(\.lastPathComponent).joined(separator: "\n"), source: source,
                            sourceBundleID: bundleID, fileURLs: urls))
            captured()
            return
        }
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg"), .init("public.heic")]
        if let type = imageTypes.first(where: { types.contains($0.rawValue) }) {
            guard let data = pasteboard.data(forType: type) else { captureStatus = "图片读取失败，请检查剪贴板权限后重试"; return }
            guard pasteboard.changeCount == change else { lastChange = -1; return }
            guard data.count <= 25 * 1024 * 1024 else { captureStatus = "图片超过 25 MB，未记录"; return }
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, Double(width) * Double(height) <= 100_000_000 else {
                captureStatus = "图片无效或分辨率过大，未记录"
                return
            }
            guard canSave else { captureStatus = "历史文件异常，暂时无法保存图片"; return }
            let filename = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".image"
            do {
                try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let url = attachmentDirectory.appendingPathComponent(filename)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try data.write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }
                let attachment = ImageAttachment(filename: filename, pasteboardType: type.rawValue, width: width, height: height, byteCount: data.count)
                insertClip(Clip(text: "图片 \(width) × \(height)", source: source, sourceBundleID: bundleID, image: attachment))
                captured()
            } catch { captureStatus = "图片保存失败：\(error.localizedDescription)" }
            return
        }
        guard let text = pasteboard.string(forType: .string) else {
            captureStatus = types.isEmpty ? "剪贴板为空" : "未能读取支持的内容，请检查权限或复制文本、图片、文件"
            return
        }
        guard pasteboard.changeCount == change else { lastChange = -1; return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { captureStatus = "已跳过空白内容"; return }
        guard text.utf8.count <= 1_000_000 else { captureStatus = "已跳过超过 1 MB 的文本"; return }
        insert(text: text, source: source, sourceBundleID: bundleID)
        captured()
    }

    private func captured() {
        notice = ""
        captureStatus = "正在监听 · 最近记录于 \(Date().formatted(date: .omitted, time: .standard))"
    }

    var attachmentDirectory: URL { file.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true) }

    func imageURL(for clip: Clip) -> URL? {
        guard let filename = clip.image?.filename, filename.range(of: "^[a-f0-9]{64}\\.image$", options: .regularExpression) != nil else { return nil }
        return attachmentDirectory.appendingPathComponent(filename)
    }

    func thumbnail(for clip: Clip, maxPixelSize: Int = 440) -> NSImage? {
        guard let url = imageURL(for: clip) else { return nil }
        let key = "\(url.lastPathComponent)-\(maxPixelSize)" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache.totalCostLimit = 32 * 1024 * 1024
        thumbnailCache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    func insert(text: String, source: String, sourceBundleID: String? = nil) {
        insertClip(Clip(text: text, source: source, sourceBundleID: sourceBundleID))
    }

    private func insertClip(_ incoming: Clip) {
        if let i = clips.firstIndex(where: { existing in
            if let image = incoming.image { return existing.image?.filename == image.filename }
            if let urls = incoming.fileURLs { return existing.fileURLs == urls }
            return existing.image == nil && existing.fileURLs == nil && existing.text == incoming.text
        }) {
            var clip = clips.remove(at: i)
            clip.date = Date()
            if incoming.source != "当前剪贴板" {
                clip.source = incoming.source
                clip.sourceBundleID = incoming.sourceBundleID
            }
            clips.insert(clip, at: 0)
        } else { clips.insert(incoming, at: 0) }
        trim()
        reconcileSelection()
        save()
    }

    func toggleFavorite(_ id: UUID) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].favorite.toggle()
        trim()
        reconcileSelection()
        save()
    }

    func delete(_ id: UUID) {
        clips.removeAll { $0.id == id }
        reconcileSelection()
        save()
    }

    func clearHistory() {
        clips.removeAll { !$0.favorite }
        reconcileSelection()
        save()
    }

    @discardableResult func copySelected() -> Bool {
        guard let clip = selected else { return false }
        let success: Bool
        // Validate attachments before replacing the user's current clipboard.
        if let urls = clip.fileURLs {
            guard !urls.isEmpty, urls.allSatisfy({ $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }) else {
                notice = "文件已移动或删除，无法再次复制；原剪贴板未更改"
                return false
            }
            pasteboard.clearContents()
            success = pasteboard.writeObjects(urls.map { $0 as NSURL })
        } else if let attachment = clip.image {
            guard let url = imageURL(for: clip), let data = try? Data(contentsOf: url), CGImageSourceCreateWithData(data as CFData, nil) != nil else {
                notice = "图片附件丢失或损坏，无法复制；原剪贴板未更改"
                return false
            }
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(attachment.pasteboardType))
            // Supply PNG alongside TIFF/JPEG/HEIC for apps expecting PNG.
            if attachment.pasteboardType != NSPasteboard.PasteboardType.png.rawValue,
               let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
                item.setData(png, forType: .png)
            }
            pasteboard.clearContents()
            success = pasteboard.writeObjects([item])
        } else {
            pasteboard.clearContents()
            success = pasteboard.setString(clip.text, forType: .string)
        }
        lastChange = pasteboard.changeCount
        notice = success ? "已复制 · 回到原应用按 ⌘V 粘贴" : "复制失败，请重试"
        return success
    }

    private func trim() {
        var ordinaryCount = 0
        clips = clips.filter { clip in
            if clip.favorite { return true }
            ordinaryCount += 1
            return ordinaryCount <= limit
        }
    }

    private func save() {
        guard hasLoadedHistory, canSave else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(clips).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            storageError = nil
            removeUnusedAttachments()
        } catch { storageError = "本地保存失败：\(error.localizedDescription)" }
    }
    private func removeUnusedAttachments() {
        let retained = Set(clips.compactMap { $0.image?.filename })
        guard let files = try? FileManager.default.contentsOfDirectory(at: attachmentDirectory, includingPropertiesForKeys: nil) else { return }
        for url in files where url.lastPathComponent.range(of: "^[a-f0-9]{64}\\.image$", options: .regularExpression) != nil && !retained.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

}
