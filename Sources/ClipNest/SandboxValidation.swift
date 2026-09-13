import AppKit

/// Explicit, synthetic checks for the separate sandbox bundle. Never uses the general clipboard.
@MainActor
enum SandboxValidation {
    static func runIfRequested() -> Bool {
        guard let index = CommandLine.arguments.firstIndex(of: "--sandbox-check"),
              CommandLine.arguments.indices.contains(index + 1) else { return false }
        let phase = CommandLine.arguments[index + 1]
        var results: [String: Any] = ["phase": phase, "accessibilityTrusted": AXIsProcessTrusted(),
                                     "automaticPaste": "not tested; requires an authorized target app"]
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SandboxValidation", isDirectory: true)
        results["directory"] = directory.path
        do {
            if phase == "seed", FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let defaults = UserDefaults(suiteName: "com.clipnest.sandbox.validation")!
            let file = directory.appendingPathComponent("history.json")
            let store = HistoryStore(file: file, defaults: defaults, pasteboard: board, monitoring: false)
            store.excludedApplications = ""
            store.paused = false
            if phase == "seed" {
                store.insert(text: "sandbox-text-fixture", source: "Validation")
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 32, bitsPerPixel: 32)!
                bitmap.bitmapData?.initialize(repeating: 128, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                board.clearContents()
                board.setData(bitmap.representation(using: .png, properties: [:])!, forType: .png)
                store.poll()
                let sample = directory.appendingPathComponent("fixture.txt")
                try Data("sandbox-file-fixture".utf8).write(to: sample, options: .atomic)
                board.clearContents()
                board.writeObjects([sample as NSURL])
                store.poll()
            }
            var copied: [String: Bool] = [:]
            for clip in store.clips {
                store.selectedID = clip.id
                let written = store.copySelected()
                if clip.image != nil {
                    copied["image"] = written && board.data(forType: .png) != nil
                } else if let urls = clip.fileURLs {
                    copied["containerFile"] = written && (try? String(contentsOf: urls[0], encoding: .utf8)) == "sandbox-file-fixture"
                } else {
                    copied["text"] = written && board.string(forType: .string) == "sandbox-text-fixture"
                }
            }
            results["copyRoundTrips"] = copied
            results["recordCount"] = store.clips.count
            results["passed"] = store.clips.count == 3 && copied.count == 3 && copied.values.allSatisfy { $0 } && store.storageError == nil
            // Caller supplies only a synthetic file, to prove sandbox enforcement without reading user data.
            if let probe = CommandLine.arguments.firstIndex(of: "--external-fixture"),
               CommandLine.arguments.indices.contains(probe + 1) {
                do {
                    _ = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[probe + 1]))
                    results["externalFileDenied"] = false
                } catch { results["externalFileDenied"] = true }
            }
        } catch { results["error"] = error.localizedDescription; results["passed"] = false }
        do {
            let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("\(phase == "seed" ? "seed" : "verify").json"), options: .atomic)
            print(String(decoding: data, as: UTF8.self))
        } catch { print("Sandbox validation report failed: \(error)") }
        return true
    }
}
