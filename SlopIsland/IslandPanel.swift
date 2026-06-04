import AppKit
import CoreGraphics

class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class IslandPanel: NSWindow {

    private(set) var notchCenterX: CGFloat = 0
    private(set) var notchWidth: CGFloat = 185
    private(set) var notchHeight: CGFloat = 32
    private(set) var screenTopY: CGFloat = 0

    var isShowing = false

    private var mouseMonitor: Any?
    private var hoverTimer: Timer?
    var onNotchClicked: (() -> Void)?
    var onClickedOutside: (() -> Void)?
    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        calculateNotchMetrics()
        setupMouseMonitor()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    private func calculateNotchMetrics() {
        guard let screen = notchScreen else { return }

        screenTopY = screen.frame.maxY
        notchHeight = screen.safeAreaInsets.top

        let left = screen.auxiliaryTopLeftArea ?? .zero
        let right = screen.auxiliaryTopRightArea ?? .zero

        if left != .zero && right != .zero {
            notchWidth = right.minX - left.maxX
            notchCenterX = (left.maxX + right.minX) / 2
        } else {
            notchWidth = 185
            notchCenterX = screen.frame.midX
        }
    }

    func show(width: CGFloat, belowHeight: CGFloat) {
        isShowing = true
        ignoresMouseEvents = false

        let start = computeFrame(width: notchWidth, belowHeight: 0)
        setFrame(start, display: true)
        alphaValue = 1
        orderFrontRegardless()

        let target = computeFrame(width: width, belowHeight: belowHeight)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().setFrame(target, display: true)
        }
    }

    func animateToSize(width: CGFloat, belowHeight: CGFloat) {
        let target = computeFrame(width: width, belowHeight: belowHeight)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().setFrame(target, display: true)
        }
    }

    func hide() {
        isShowing = false
        let collapsed = computeFrame(width: notchWidth, belowHeight: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)
            self.animator().setFrame(collapsed, display: true)
        }, completionHandler: {
            self.orderOut(nil)
            self.ignoresMouseEvents = true
        })
    }

    func bounce() {
        guard isShowing else { return }
        let base = frame
        let up = NSRect(x: base.origin.x, y: base.origin.y - 6, width: base.width, height: base.height + 6)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(up, display: true)
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().setFrame(base, display: true)
            }
        })
    }

    private func computeFrame(width: CGFloat, belowHeight: CGFloat) -> NSRect {
        let totalH = notchHeight + belowHeight
        let x = notchCenterX - width / 2
        let y = screenTopY - totalH
        return NSRect(x: x, y: y, width: width, height: totalH)
    }

    // MARK: - Mouse Tracking

    private var isHovering = false

    private func setupMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            self?.handleGlobalMouse(event)
        }
    }

    private func handleGlobalMouse(_ event: NSEvent) {
        let loc = NSEvent.mouseLocation

        switch event.type {
        case .mouseMoved:
            let inNotchZone = isPointInNotchZone(loc)
            let inPanel = isShowing && frame.contains(loc)

            if (inNotchZone || inPanel) && !isHovering {
                isHovering = true
                hoverTimer?.invalidate()
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                    guard let self = self, self.isHovering else { return }
                    self.onHoverEnter?()
                }
            } else if !inNotchZone && !inPanel && isHovering {
                isHovering = false
                hoverTimer?.invalidate()
                hoverTimer = nil
                onHoverExit?()
            }

        case .leftMouseDown:
            if isShowing {
                if isPointInNotchZone(loc) {
                    onNotchClicked?()
                } else if !frame.contains(loc) {
                    onClickedOutside?()
                }
            } else if isPointInNotchZone(loc) {
                onNotchClicked?()
            }

        default:
            break
        }
    }

    private func isPointInNotchZone(_ point: CGPoint) -> Bool {
        let zoneW = notchWidth + 20
        let zoneH = notchHeight
        let zoneRect = NSRect(
            x: notchCenterX - zoneW / 2,
            y: screenTopY - zoneH,
            width: zoneW,
            height: zoneH
        )
        return zoneRect.contains(point)
    }

    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hoverTimer?.invalidate()
    }
}
