import AppKit

struct KeySender {
    /// Whether SlopIsland currently has Accessibility permission (required for
    /// synthetic key events). Does not prompt.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission (opens System Settings).
    static func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    /// Focus the session's terminal, then inject `text` followed by Return.
    /// Returns false immediately if Accessibility permission is missing.
    /// `cwd` targets the exact terminal tab; empty falls back to app activation.
    @discardableResult
    static func sendToTerminal(text: String, cwd: String = "") -> Bool {
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return false
        }

        TerminalFocuser.shared.focusTerminal(cwd: cwd) { focused in
            guard focused else {
                send(text)
                return
            }
            // Small settle delay after focus actually completes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                send(text)
            }
        }
        return true
    }

    /// Answer a multi-question AskUserQuestion: for each question inject its
    /// option number, advancing to the next question with Tab, and submitting
    /// after the last with Return. Each keystroke is spaced out so the terminal
    /// TUI can process and re-render between steps.
    @discardableResult
    static func sendAnswerSequence(numbers: [Int], cwd: String = "") -> Bool {
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            return false
        }
        guard !numbers.isEmpty else { return false }

        TerminalFocuser.shared.focusTerminal(cwd: cwd) { focused in
            let start: Double = focused ? 0.12 : 0.0
            var delay = start
            let step = 0.12

            for (i, number) in numbers.enumerated() {
                let isLast = i == numbers.count - 1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    for char in "\(number)" { sendKey(char) }
                }
                delay += step
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if isLast {
                        sendReturn()
                    } else {
                        sendTab()
                    }
                }
                delay += step
            }
        }
        return true
    }

    private static func sendTab() {
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0x30, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: 0x30, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
    }

    private static func send(_ text: String) {
        for char in text { sendKey(char) }
        sendReturn()
    }

    private static func sendKey(_ char: Character) {
        let str = String(char)
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
