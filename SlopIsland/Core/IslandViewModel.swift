import AppKit
import Observation

@Observable
final class IslandViewModel {
    enum Status: Equatable { case closed, opened }
    enum ContentType: Equatable {
        case sessions
        case chat(String)
        case question(UserQuestion)
        case permission(SessionState, PermissionContext)

        static func == (lhs: ContentType, rhs: ContentType) -> Bool {
            switch (lhs, rhs) {
            case (.sessions, .sessions): return true
            case (.chat(let a), .chat(let b)): return a == b
            case (.question(let a), .question(let b)): return a.sessionID == b.sessionID
            case (.permission(let a, _), .permission(let b, _)): return a.sessionID == b.sessionID
            default: return false
            }
        }
    }

    private(set) var geometry: NotchGeometry

    var status: Status = .closed
    var contentType: ContentType = .sessions
    var isHovering = false

    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hoverTask: Task<Void, Never>?
    private var lastMouseMovedAt: TimeInterval = 0
    weak var panel: NotchPanel?

    private var panelWidth: CGFloat {
        switch contentType {
        case .permission:
            return 420
        default:
            return 350
        }
    }

    /// Maximum height the content area may occupy, leaving the panel on-screen.
    private var maxContentHeight: CGFloat {
        geometry.screenRect.height - geometry.notchHeight - 40
    }

    /// Which question page is currently shown (for paginated multi-question
    /// prompts). Drives the per-page height so the panel hugs the visible page.
    private var currentQuestionPage: Int = 0

    private var contentHeight: CGFloat {
        switch contentType {
        case .sessions:
            let count = max(SessionStore.shared.allSessions.count, 1)
            // header row (28) + VStack spacing (8) + list + vertical padding.
            return 28 + 8 + 10 + CGFloat(count) * 56 + 16
        case .chat:
            return 400
        case .permission:
            return 220
        case .question(let q):
            return min(questionHeight(q, page: currentQuestionPage), maxContentHeight)
        }
    }

    /// Called by the question view when the user turns to another page, so the
    /// content can resize to hug just that page.
    func setQuestionPage(_ page: Int) {
        guard case .question = contentType, page != currentQuestionPage else { return }
        currentQuestionPage = page
        if status == .opened { updateInteractiveRect() }
    }

    /// Deterministic height estimate for the currently shown question page. Only
    /// ONE question shows at a time, so size to exactly that page.
    private func questionHeight(_ q: UserQuestion, page: Int) -> CGFloat {
        let chrome: CGFloat = 20 + 28 + 14   // padding + header row + spacing
        guard q.items.indices.contains(page) else { return chrome + 200 }
        let item = q.items[page]
        var block: CGFloat = 0
        if q.items.count > 1, !item.header.isEmpty { block += 22 }
        block += 40                          // prompt
        for opt in item.options {
            block += (opt.description?.isEmpty == false) ? 64 : 44
            block += 8
        }
        if item.multiSelect { block += 48 }  // Next/Submit button
        return chrome + block
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
        findPanel()?.makeKeyAndOrderFront(nil)
        updateInteractiveRect()
    }

    func notchClose() {
        if case .question = contentType { return }
        if case .permission = contentType { return }
        status = .closed
        contentType = .sessions
        updateInteractiveRect()
    }

    func showChat(sessionID: String) {
        contentType = .chat(sessionID)
        updateInteractiveRect()
    }

    func exitChat() {
        contentType = .sessions
        updateInteractiveRect()
    }

    func showQuestion(_ question: UserQuestion) {
        // Idempotent: the store re-notifies on every state change, but we must
        // not reset the measured height while already showing the same prompt.
        if case .question(let current) = contentType,
           current.sessionID == question.sessionID,
           current.items.count == question.items.count {
            return
        }
        currentQuestionPage = 0
        contentType = .question(question)
        status = .opened
        findPanel()?.makeKeyAndOrderFront(nil)
        updateInteractiveRect()
    }

    func dismissQuestion() {
        if case .question = contentType {
            contentType = .sessions
            status = .closed
            updateInteractiveRect()
        }
    }

    func showPermission(session: SessionState, context: PermissionContext) {
        // Idempotent for the same session (store re-notifies repeatedly).
        if case .permission(let cur, _) = contentType, cur.sessionID == session.sessionID {
            return
        }
        contentType = .permission(session, context)
        status = .opened
        findPanel()?.makeKeyAndOrderFront(nil)
        updateInteractiveRect()
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
        } else {
            contentType = .sessions
        }
        updateInteractiveRect()
    }

    /// Recompute the screen-space rect the visible content currently occupies
    /// and hand it to the panel for hit-testing. The window itself never moves
    /// or resizes — only this interactive region (and the SwiftUI content) change.
    private func updateInteractiveRect() {
        guard let panel = findPanel() else { return }
        if status == .closed {
            panel.currentInteractiveRect = NotchPanel.notchRect(geometry: geometry)
        } else {
            let size = openedSize
            panel.currentInteractiveRect = NSRect(
                x: geometry.notchCenterX - size.width / 2,
                y: geometry.screenTopY - size.height,
                width: size.width,
                height: size.height
            )
        }
    }

    /// Re-detect geometry and reposition the panel after a screen change
    /// (display plugged/unplugged, resolution change, lid open/close). Without
    /// this the island stays pinned to the old screen's coordinates.
    func handleScreenChange() {
        let fresh = NotchGeometry.detect()
        guard fresh != geometry else { return }
        geometry = fresh
        findPanel()?.reposition(to: fresh)
        updateInteractiveRect()
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
            // Throttle high-frequency move events: hit-testing on every sample
            // is wasted work when the pointer is sweeping across the screen.
            let now = Foundation.ProcessInfo.processInfo.systemUptime
            guard now - lastMouseMovedAt >= 0.05 else { return }
            lastMouseMovedAt = now

            let inNotch = geometry.isPointInNotch(loc)
            let inPanel = status == .opened && geometry.isPointInOpenedPanel(loc, size: openedSize)
            let nowHovering = inNotch || inPanel

            if nowHovering && !isHovering {
                isHovering = true
                hoverTask?.cancel()
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.2))
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
