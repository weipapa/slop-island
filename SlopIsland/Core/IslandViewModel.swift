import AppKit
import Observation

@Observable
final class IslandViewModel {
    enum Status: Equatable { case closed, opened }
    enum ContentType: Equatable {
        case sessions
        case settings
        case chat(String)
        case question(UserQuestion)
        case permission(SessionState, PermissionContext)

        static func == (lhs: ContentType, rhs: ContentType) -> Bool {
            switch (lhs, rhs) {
            case (.sessions, .sessions), (.settings, .settings): return true
            case (.chat(let a), .chat(let b)): return a == b
            case (.question(let a), .question(let b)): return a.sessionID == b.sessionID
            case (.permission(let a, _), .permission(let b, _)): return a.sessionID == b.sessionID
            default: return false
            }
        }
    }

    let geometry: NotchGeometry

    var status: Status = .closed
    var contentType: ContentType = .sessions
    var isHovering = false

    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hoverTask: Task<Void, Never>?
    weak var panel: NotchPanel?

    private var panelWidth: CGFloat {
        switch contentType {
        case .permission:
            return 420
        default:
            return 350
        }
    }

    private var contentHeight: CGFloat {
        switch contentType {
        case .sessions:
            let count = max(SessionStore.shared.allSessions.count, 1)
            return 40 + CGFloat(count) * 56 + 16
        case .settings:
            return 200
        case .chat:
            return 400
        case .question(let q):
            return 60 + CGFloat(max(q.options.count, 1)) * 44
        case .permission:
            return 180
        }
    }

    var openedSize: CGSize {
        CGSize(width: panelWidth, height: contentHeight + geometry.notchHeight)
    }

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        setupMouseMonitor()
    }

    func notchOpen() {
        guard status == .closed else { return }
        status = .opened
        if let panel = findPanel() {
            panel.makeKeyAndOrderFront(nil)
            panel.animateToSize(width: panelWidth, belowHeight: contentHeight)
        }
    }

    func notchClose() {
        if case .question = contentType { return }
        if case .permission = contentType { return }
        status = .closed
        contentType = .sessions
        if let panel = findPanel() {
            panel.animateToSize(width: geometry.notchWidth, belowHeight: 0)
        }
    }

    func toggleSettings() {
        contentType = contentType == .settings ? .sessions : .settings
        syncPanelSize()
    }

    func showChat(sessionID: String) {
        contentType = .chat(sessionID)
        syncPanelSize()
    }

    func exitChat() {
        contentType = .sessions
        syncPanelSize()
    }

    func showQuestion(_ question: UserQuestion) {
        contentType = .question(question)
        status = .opened
        if let panel = findPanel() {
            panel.makeKeyAndOrderFront(nil)
            panel.setSize(width: panelWidth, belowHeight: contentHeight)
        }
    }

    func dismissQuestion() {
        if case .question = contentType {
            contentType = .sessions
            status = .closed
            if let panel = findPanel() {
                panel.setSize(width: geometry.notchWidth, belowHeight: 0)
            }
        }
    }

    func showPermission(session: SessionState, context: PermissionContext) {
        contentType = .permission(session, context)
        status = .opened
        if let panel = findPanel() {
            panel.makeKeyAndOrderFront(nil)
            panel.setSize(width: panelWidth, belowHeight: contentHeight)
        }
    }

    func dismissPermission() {
        guard case .permission = contentType else { return }

        // Check if another session needs permission attention
        let nextPermission = SessionStore.shared.allSessions.first { session in
            if case .waitingForApproval = session.phase {
                return true
            }
            return false
        }

        if let next = nextPermission, case .waitingForApproval(let ctx) = next.phase {
            contentType = .permission(next, ctx)
            if let panel = findPanel() {
                panel.animateToSize(width: panelWidth, belowHeight: contentHeight)
            }
        } else {
            contentType = .sessions
            if let panel = findPanel() {
                panel.animateToSize(width: panelWidth, belowHeight: contentHeight)
            }
        }
    }

    private func syncPanelSize() {
        if let panel = findPanel(), status == .opened {
            panel.animateToSize(width: panelWidth, belowHeight: contentHeight)
        }
    }

    private func findPanel() -> NotchPanel? {
        panel
    }

    private func setupMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleMouse(event)
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleMouse(event)
            }
            return event
        }
    }

    private func handleMouse(_ event: NSEvent) {
        let loc = NSEvent.mouseLocation

        switch event.type {
        case .mouseMoved:
            let inNotch = geometry.isPointInNotch(loc)
            let inPanel = status == .opened && geometry.isPointInOpenedPanel(loc, size: openedSize)
            let nowHovering = inNotch || inPanel

            if nowHovering && !isHovering {
                isHovering = true
                hoverTask?.cancel()
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.8))
                    guard !Task.isCancelled, self.isHovering else { return }
                    self.notchOpen()
                }
            } else if !nowHovering && isHovering {
                isHovering = false
                hoverTask?.cancel()
                hoverTask = nil
            }

        case .leftMouseDown:
            let inNotch = geometry.isPointInNotch(loc)

            if inNotch {
                if status == .opened {
                    if case .question = contentType {
                        dismissQuestion()
                    } else if case .permission = contentType {
                        dismissPermission()
                    } else {
                        notchClose()
                    }
                } else {
                    notchOpen()
                }
            }

        default: break
        }
    }

    deinit {
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m) }
        hoverTask?.cancel()
    }
}
