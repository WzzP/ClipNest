import AppKit

@main struct KeyboardRoutingChecks {
    @MainActor static func main() {
        let editor = NSTextView()
        editor.setMarkedText("db", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(editor.hasMarkedText())
        for key: UInt16 in [36, 53, 49, 123, 124, 125, 126, 18, 19] {
            precondition(KeyboardRouting.action(keyCode: key, editing: true, composing: editor.hasMarkedText()) == .passThrough)
        }
        editor.unmarkText()
        precondition(KeyboardRouting.action(keyCode: 36, editing: true, composing: editor.hasMarkedText()) == .paste)
        precondition(KeyboardRouting.action(keyCode: 49, editing: true, composing: false) == .passThrough)
        precondition(KeyboardRouting.action(keyCode: 123, editing: true, composing: false) == .passThrough)
        precondition(KeyboardRouting.action(keyCode: 49, editing: false, composing: false) == .preview)
        precondition(KeyboardRouting.action(keyCode: 125, editing: false, composing: false) == .passThrough)
        precondition(KeyboardRouting.action(keyCode: 126, editing: false, composing: false) == .passThrough)
        precondition(KeyboardRouting.action(keyCode: 123, editing: false, composing: false) == .move(-1))
        precondition(KeyboardRouting.action(keyCode: 124, editing: false, composing: false) == .move(1))
        precondition(KeyboardRouting.action(keyCode: 53, editing: false, composing: false) == .dismiss)
        precondition(KeyboardRouting.action(keyCode: 123, editing: true, composing: false, modifiers: .command) == .passThrough)
        print("PASS: marked-text IME keys, confirmed input, editor and card shortcuts")
    }
}
