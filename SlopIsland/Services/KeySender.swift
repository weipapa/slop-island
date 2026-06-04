import AppKit

struct KeySender {
    static func sendToTerminal(text: String) {
        TerminalFocuser.shared.focusTerminal()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for char in text {
                sendKey(char)
            }
            sendReturn()
        }
    }

    private static func sendKey(_ char: Character) {
        let str = String(char)
        guard let chars = str.utf16.first else { return }

        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            var utf16 = [UniChar](str.utf16)
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            var utf16 = [UniChar](str.utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private static func sendReturn() {
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }
}
