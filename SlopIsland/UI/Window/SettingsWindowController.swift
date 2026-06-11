import AppKit
import SwiftUI

/// Owns the single Settings window. Reuses one window across opens so we never
/// stack duplicates. The app is an `LSUIElement` (menu-bar only), so it must
/// activate itself before showing the window or it can appear unfocused.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private init() {}

    private var window: NSWindow?

    func show() {
        if let window = window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsContentView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "SlopIsland Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
