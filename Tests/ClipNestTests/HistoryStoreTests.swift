import AppKit

@MainActor
final class HistoryStoreTests {
    private func fixture() -> (HistoryStore, URL, UserDefaults, NSPasteboard) {
        let id = UUID().uuidString
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ClipNestTests-\(id)/history.json")
        let defaults = UserDefaults(suiteName: "ClipNestTests-\(id)")!
        let pasteboard = NSPasteboard.withUniqueName()
        return (HistoryStore(file: file, defaults: defaults, pasteboard: pasteboard, monitoring: false), file, defaults, pasteboard)
    }

    func testDuplicatePreservesIdentityAndFavoriteAcrossReload() throws {
        let (store, file, defaults, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        store.insert(text: "a", source: "Editor")
        let id = try unwrap(store.clips.first?.id)
        store.toggleFavorite(id)
        store.insert(text: "b", source: "Safari")
        store.insert(text: "a", source: "Terminal")
        let reloaded = HistoryStore(file: file, defaults: defaults, pasteboard: board, monitoring: false)
        expectEqual(reloaded.clips.count, 2)
        expectEqual(reloaded.clips.first?.id, id)
        expectEqual(reloaded.clips.first?.favorite, true)
        expectEqual(reloaded.clips.first?.source, "Terminal")
    }

    func testLimitAndClearPreserveFavorites() throws {
        let (store, file, _, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        store.limit = 2
        store.insert(text: "saved", source: "Notes")
        store.toggleFavorite(try unwrap(store.clips.first?.id))
        for text in ["one", "two", "three"] { store.insert(text: text, source: "Notes") }
        expectEqual(store.clips.map(\.text), ["three", "two", "saved"])
        store.clearHistory()
        expectEqual(store.clips.map(\.text), ["saved"])
    }

    func testSensitivePausedAndSelfCopiesAreNotRecorded() {
        let (store, file, _, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        board.clearContents()
        board.setString("secret", forType: .string)
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        store.poll()
        expectTrue(store.clips.isEmpty)
        store.paused = true
        board.clearContents(); board.setString("paused", forType: .string)
        store.poll()
        store.paused = false
        store.poll()
        expectTrue(store.clips.isEmpty)
        store.insert(text: "ordinary", source: "Notes")
        expectTrue(store.copySelected())
        store.poll()
        expectEqual(store.clips.count, 1)
        expectEqual(board.string(forType: .string), "ordinary")
    }

    func testCorruptFileIsNotOverwritten() throws {
        let (_, file, defaults, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data("broken history".utf8)
        try data.write(to: file)
        let store = HistoryStore(file: file, defaults: defaults, pasteboard: board, monitoring: false)
        expectNotNil(store.storageError)
        store.insert(text: "new", source: "Notes")
        expectEqual(try Data(contentsOf: file), data)
    }

    func testMonitoringImportsCurrentAndContinuesInTrackingMode() {
        let (store, file, _, board) = fixture()
        defer { store.stopMonitoring(); try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        board.clearContents()
        board.setString("before launch", forType: .string)
        store.startMonitoring()
        expectEqual(store.clips.first?.text, "before launch")
        expectEqual(store.clips.first?.source, "当前剪贴板")
        board.clearContents()
        board.setString("after launch", forType: .string)
        // A command-line runner does not install AppKit's tracking common mode.
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString))
        let deadline = Date().addingTimeInterval(2)
        while store.clips.first?.text != "after launch" && Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: Date().addingTimeInterval(0.1))
        }
        expectEqual(store.clips.first?.text, "after launch")
        expectEqual(store.clips.count, 2)
    }

    func testSourceIdentityPersistenceAndOldHistoryCompatibility() throws {
        let (store, file, defaults, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        store.insert(text: "source icon", source: "Safari", sourceBundleID: "com.apple.Safari")
        let reloaded = HistoryStore(file: file, defaults: defaults, pasteboard: board, monitoring: false)
        expectEqual(reloaded.clips.first?.sourceBundleID, "com.apple.Safari")
        var old = try unwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        old[0].removeValue(forKey: "sourceBundleID")
        try JSONSerialization.data(withJSONObject: old).write(to: file)
        let legacy = HistoryStore(file: file, defaults: defaults, pasteboard: board, monitoring: false)
        expectNil(legacy.storageError)
        expectEqual(legacy.clips.first?.text, "source icon")
    }

    private func imageData(_ type: NSBitmapImageRep.FileType) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<12 { for y in 0..<8 { rep.setColor(NSColor(deviceRed: 0.1, green: 0.3, blue: 0.8, alpha: 1), atX: x, y: y) } }
        return rep.representation(using: type, properties: [:])!
    }

    func testImageCaptureRestoreReloadAndCleanup() throws {
        let (store, file, defaults, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        let png = imageData(.png)
        board.clearContents(); board.setData(png, forType: .png)
        board.setString("image description", forType: .string)
        store.poll()
        let clip = try unwrap(store.clips.first)
        expectEqual(clip.kind, "图片")
        expectEqual(clip.image?.width, 12)
        expectEqual(clip.image?.height, 8)
        expectNotNil(store.thumbnail(for: clip))
        expectTrue(store.copySelected())
        expectEqual(board.data(forType: .png), png)
        expectNil(board.string(forType: .string))
        store.poll()
        expectEqual(store.clips.count, 1)
        board.clearContents(); board.setData(png, forType: .png)
        store.poll()
        expectEqual(store.clips.count, 1)
        let restored = HistoryStore(file: file, defaults: defaults, pasteboard: board, monitoring: false)
        expectEqual(restored.clips.first?.image, clip.image)
        expectTrue(restored.copySelected())
        let attachmentURL = try unwrap(store.imageURL(for: clip))
        restored.delete(clip.id)
        expectFalse(FileManager.default.fileExists(atPath: attachmentURL.path))
    }

    func testTIFFGetsPNGCompatibilityRepresentation() throws {
        let (store, file, _, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        let tiff = imageData(.tiff)
        board.clearContents(); board.setData(tiff, forType: .tiff)
        store.poll()
        expectEqual(store.clips.first?.kind, "图片")
        expectTrue(store.copySelected())
        expectEqual(board.data(forType: .tiff), tiff)
        expectNotNil(board.data(forType: .png))
    }

    func testMultipleFilesRoundTripAndMissingFilePreservesClipboard() throws {
        let (store, file, defaults, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let urls = [file.deletingLastPathComponent().appendingPathComponent("示例 image.png"), file.deletingLastPathComponent().appendingPathComponent("report.txt")]
        try imageData(.png).write(to: urls[0])
        try Data("file content".utf8).write(to: urls[1])
        board.clearContents(); board.writeObjects(urls.map { $0 as NSURL })
        store.poll()
        expectEqual(store.clips.first?.kind, "文件")
        expectEqual(store.clips.first?.fileURLs, urls)
        expectTrue(store.copySelected())
        expectEqual(board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], urls)
        let restored = HistoryStore(file: file, defaults: defaults, pasteboard: board, monitoring: false)
        expectEqual(restored.clips.first?.fileURLs, urls)
        try FileManager.default.removeItem(at: urls[1])
        board.clearContents(); board.setString("keep me", forType: .string)
        expectFalse(restored.copySelected())
        expectEqual(board.string(forType: .string), "keep me")
        restored.clearHistory()
        expectTrue(FileManager.default.fileExists(atPath: urls[0].path))
    }

    func testSensitiveImagesAndMissingAttachments() throws {
        let (store, file, _, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        let png = imageData(.png)
        board.clearContents(); board.setData(png, forType: .png)
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        store.poll()
        expectTrue(store.clips.isEmpty)
        board.clearContents(); board.setData(png, forType: .png)
        store.poll()
        let url = try unwrap(store.imageURL(for: try unwrap(store.clips.first)))
        try FileManager.default.removeItem(at: url)
        board.clearContents(); board.setString("keep me", forType: .string)
        expectFalse(store.copySelected())
        expectEqual(board.string(forType: .string), "keep me")
    }

    func testSavedPreferencesDoNotOverwriteHistoryDuringInitialization() throws {
        let (store, file, defaults, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        store.limit = 200
        store.insert(text: "must survive restart", source: "Notes")
        board.clearContents(); board.setData(imageData(.png), forType: .png)
        store.poll()
        let before = try Data(contentsOf: file)
        let ids = store.clips.map(\.id)
        let attachment = try unwrap(store.imageURL(for: try unwrap(store.clips.first)))
        let restarted = HistoryStore(file: file, defaults: defaults, pasteboard: board, monitoring: false)
        expectEqual(restarted.clips.map(\.id), ids)
        expectEqual(try Data(contentsOf: file), before)
        expectTrue(FileManager.default.fileExists(atPath: attachment.path))
        restarted.startMonitoring()
        restarted.stopMonitoring()
        expectEqual(restarted.clips.count, 2)
    }

    func testFilteringAndSelection() {
        let (store, file, _, board) = fixture()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); board.releaseGlobally() }
        store.insert(text: "Hello World", source: "Notes")
        store.insert(text: "https://example.com", source: "Safari")
        store.query = "WORLD"
        store.reconcileSelection()
        expectEqual(store.selected?.text, "Hello World")
        store.query = "safari"
        store.reconcileSelection()
        expectEqual(store.selected?.kind, "链接")
        store.query = "nothing"
        store.reconcileSelection()
        store.moveSelection(1)
        expectNil(store.selected)
        expectFalse(store.copySelected())
    }
}

private func expectEqual<T: Equatable>(_ a: T, _ b: T, line: UInt = #line) { precondition(a == b, "Equality check failed at line \(line)") }
private func expectTrue(_ value: Bool, line: UInt = #line) { precondition(value, "Expected true at line \(line)") }
private func expectFalse(_ value: Bool, line: UInt = #line) { precondition(!value, "Expected false at line \(line)") }
private func expectNil<T>(_ value: T?, line: UInt = #line) { precondition(value == nil, "Expected nil at line \(line)") }
private func expectNotNil<T>(_ value: T?, line: UInt = #line) { precondition(value != nil, "Expected value at line \(line)") }
private func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw CheckError.missingValue }; return value }
private enum CheckError: Error { case missingValue }

@main
struct RunHistoryChecks {
    @MainActor static func main() throws {
        let suite = HistoryStoreTests()
        try suite.testDuplicatePreservesIdentityAndFavoriteAcrossReload()
        try suite.testLimitAndClearPreserveFavorites()
        suite.testSensitivePausedAndSelfCopiesAreNotRecorded()
        try suite.testCorruptFileIsNotOverwritten()
        suite.testFilteringAndSelection()
        suite.testMonitoringImportsCurrentAndContinuesInTrackingMode()
        try suite.testSourceIdentityPersistenceAndOldHistoryCompatibility()
        try suite.testImageCaptureRestoreReloadAndCleanup()
        try suite.testTIFFGetsPNGCompatibilityRepresentation()
        try suite.testMultipleFilesRoundTripAndMissingFilePreservesClipboard()
        try suite.testSensitiveImagesAndMissingAttachments()
        try suite.testSavedPreferencesDoNotOverwriteHistoryDuringInitialization()
        print("PASS: 12 history integration checks")
    }
}
