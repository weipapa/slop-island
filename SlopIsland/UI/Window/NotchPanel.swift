import AppKit

class NotchPanel: NSPanel {
    let geometry: NotchGeometry

    init(geometry: NotchGeometry) {
        self.geometry = geometry

        let initialRect = NotchPanel.computeFrame(geometry: geometry, width: geometry.notchWidth, belowHeight: 0)
        super.init(
            contentRect: initialRect,
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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setSize(width: CGFloat, belowHeight: CGFloat) {
        let target = NotchPanel.computeFrame(geometry: geometry, width: width, belowHeight: belowHeight)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        animator().setFrame(target, display: true)
        NSAnimationContext.endGrouping()
        setFrame(target, display: true)
    }

    func animateToSize(width: CGFloat, belowHeight: CGFloat) {
        let target = NotchPanel.computeFrame(geometry: geometry, width: width, belowHeight: belowHeight)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().setFrame(target, display: true)
        }
    }

    private static func computeFrame(geometry: NotchGeometry, width: CGFloat, belowHeight: CGFloat) -> NSRect {
        let totalH = geometry.notchHeight + belowHeight
        let x = geometry.notchCenterX - width / 2
        let y = geometry.screenTopY - totalH
        return NSRect(x: x, y: y, width: width, height: totalH)
    }
}
