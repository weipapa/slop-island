import AppKit

struct NotchGeometry: Equatable {
    let notchCenterX: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let screenTopY: CGFloat
    let screenRect: CGRect

    static func detect() -> NotchGeometry {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            let screen = NSScreen.main ?? NSScreen.screens[0]
            return NotchGeometry(
                notchCenterX: screen.frame.midX,
                notchWidth: 185,
                notchHeight: 32,
                screenTopY: screen.frame.maxY,
                screenRect: screen.frame
            )
        }

        let left = screen.auxiliaryTopLeftArea ?? .zero
        let right = screen.auxiliaryTopRightArea ?? .zero

        let notchWidth: CGFloat
        let notchCenterX: CGFloat
        if left != .zero && right != .zero {
            notchWidth = right.minX - left.maxX
            notchCenterX = (left.maxX + right.minX) / 2
        } else {
            notchWidth = 185
            notchCenterX = screen.frame.midX
        }

        return NotchGeometry(
            notchCenterX: notchCenterX,
            notchWidth: notchWidth,
            notchHeight: screen.safeAreaInsets.top,
            screenTopY: screen.frame.maxY,
            screenRect: screen.frame
        )
    }

    func isPointInNotch(_ point: CGPoint) -> Bool {
        let zoneW = notchWidth + 20
        let zoneRect = NSRect(
            x: notchCenterX - zoneW / 2,
            y: screenTopY - notchHeight,
            width: zoneW,
            height: notchHeight
        )
        return zoneRect.contains(point)
    }

    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize) -> Bool {
        let panelRect = NSRect(
            x: notchCenterX - size.width / 2,
            y: screenTopY - size.height,
            width: size.width,
            height: size.height
        )
        return panelRect.contains(point)
    }
}
