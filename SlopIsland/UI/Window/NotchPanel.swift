import AppKit

/// The window is created once at its maximum (fully-opened) size and never
/// resizes. All open/close/resize transitions are driven by SwiftUI animating
/// the content inside this fixed window — so AppKit never re-lays-out the panel
/// frame mid-animation (which caused the jitter the old setFrame path had).
///
/// Because the window is large but mostly transparent, two things keep clicks
/// behaving correctly:
/// - `currentInteractiveRect` is the live screen-space rect the content actually
///   occupies; the hosting view's `hitTest` returns nil outside it so clicks
///   pass through to apps underneath.
/// - the view model still drives open/close from the global mouse monitor.
class NotchPanel: NSPanel {
    private(set) var geometry: NotchGeometry

    /// Screen-space rect currently covered by visible content. Updated by the
    /// view model as the notch opens/closes and as content height changes.
    /// Points outside it are passed through to the windows below.
    var currentInteractiveRect: NSRect = .zero

    init(geometry: NotchGeometry) {
        self.geometry = geometry

        let frame = NotchPanel.maxFrame(geometry: geometry)
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        ignoresMouseEvents = false
        // Start with only the bare notch interactive.
        currentInteractiveRect = NotchPanel.notchRect(geometry: geometry)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Re-detect the notch/screen geometry and move the fixed-size window to the
    /// new max frame. Called when screens change (display plugged/unplugged,
    /// resolution change, lid open/close). Returns the fresh geometry so the
    /// view model can rebuild its interactive rect.
    @discardableResult
    func reposition(to newGeometry: NotchGeometry) -> NotchGeometry {
        geometry = newGeometry
        setFrame(NotchPanel.maxFrame(geometry: newGeometry), display: true)
        return newGeometry
    }

    /// The full opened-size window frame: notch width is irrelevant here, the
    /// window spans the widest content (permission card) and the tallest
    /// allowable height, centered on the notch and pinned to the screen top.
    static func maxFrame(geometry: NotchGeometry) -> NSRect {
        let width = maxWidth
        let height = geometry.notchHeight + maxBelowHeight(geometry: geometry)
        let x = geometry.notchCenterX - width / 2
        let y = geometry.screenTopY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Widest content the panel ever shows (the 420pt permission card).
    static let maxWidth: CGFloat = 420

    /// Tallest content area, leaving the panel fully on-screen.
    static func maxBelowHeight(geometry: NotchGeometry) -> CGFloat {
        geometry.screenRect.height - geometry.notchHeight - 40
    }

    /// Screen-space rect of just the closed notch, centered in the window.
    static func notchRect(geometry: NotchGeometry) -> NSRect {
        let frame = maxFrame(geometry: geometry)
        return NSRect(
            x: geometry.notchCenterX - geometry.notchWidth / 2,
            y: frame.maxY - geometry.notchHeight,
            width: geometry.notchWidth,
            height: geometry.notchHeight
        )
    }
}
