import AppKit

final class SessionDotsView: NSView {

    private var dotLayers: [CALayer] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func configure(sessions: [SessionState]) {
        dotLayers.forEach { $0.removeFromSuperlayer() }
        dotLayers.removeAll()

        let activeSessions = sessions
            .filter { $0.phase != .ended }
            .sorted { priority($0.phase) < priority($1.phase) }

        let dotSize: CGFloat = 6
        let spacing: CGFloat = 4
        let maxDots = 8
        let displaySessions = activeSessions.prefix(maxDots)

        let totalWidth = CGFloat(displaySessions.count) * dotSize + CGFloat(max(0, displaySessions.count - 1)) * spacing
        var x = (bounds.width - totalWidth) / 2

        for session in displaySessions {
            let dot = CALayer()
            dot.frame = NSRect(x: x, y: (bounds.height - dotSize) / 2, width: dotSize, height: dotSize)
            dot.cornerRadius = dotSize / 2
            dot.backgroundColor = color(for: session.phase).cgColor
            layer?.addSublayer(dot)
            dotLayers.append(dot)
            x += dotSize + spacing
        }
    }

    private func priority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval: return 0
        case .processing: return 1
        case .ended: return 2
        case .idle: return 3
        }
    }

    private func color(for phase: SessionPhase) -> NSColor {
        switch phase {
        case .waitingForApproval:
            return NSColor(red: 0.38, green: 0.55, blue: 1.0, alpha: 1)
        case .processing:
            return NSColor(red: 0.204, green: 0.831, blue: 0.600, alpha: 1)
        case .ended:
            return NSColor(red: 0.204, green: 0.831, blue: 0.600, alpha: 0.6)
        case .idle:
            return NSColor(white: 0.35, alpha: 1)
        }
    }
}
