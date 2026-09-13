import AppKit

enum PanelKeyAction: Equatable {
    case passThrough, dismiss, preview, paste
    case move(Int)
}

enum KeyboardRouting {
    static func action(keyCode: UInt16, editing: Bool, composing: Bool,
                       modifiers: NSEvent.ModifierFlags = []) -> PanelKeyAction {
        // The input method owns all keys while a marked-text composition exists,
        // including Return, Escape, arrows, Space and candidate-number keys.
        guard !composing else { return .passThrough }
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return .passThrough }
        switch keyCode {
        case 53: return .dismiss
        case 123 where !editing: return .move(-1)
        case 124 where !editing: return .move(1)
        case 49 where !editing: return .preview
        case 36: return .paste
        default: return .passThrough
        }
    }
}
