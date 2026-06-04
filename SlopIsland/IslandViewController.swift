import AppKit

final class IslandViewController {

    private let panel: IslandPanel
    private let rootView = FirstMouseView()
    private let contentContainer = NSView()
    private weak var currentListView: SessionListView?

    private(set) var currentIslandState: IslandState = .idle
    private var dismissTimer: Timer?
    private var isExpanded = false

    init(panel: IslandPanel) {
        self.panel = panel
        setupViews()
        setupPanelCallbacks()
        subscribeToStore()
    }

    private func setupViews() {
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.black.cgColor
        rootView.layer?.masksToBounds = true
        rootView.autoresizingMask = [.width, .height]

        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        rootView.addSubview(contentContainer)

        panel.contentView = rootView
    }

    private func setupPanelCallbacks() {
        panel.onNotchClicked = { [weak self] in
            guard let self = self else { return }
            if self.isExpanded {
                self.collapse()
            } else {
                self.expandToList()
            }
        }

        panel.onClickedOutside = { [weak self] in
            self?.collapse()
        }

        panel.onHoverEnter = { [weak self] in
            guard let self = self, !self.isExpanded else { return }
            self.expandToList()
        }

        panel.onHoverExit = { [weak self] in
            guard let self = self, self.isExpanded else { return }
            let hasPermission = SessionStore.shared.allSessions.contains { $0.phase.needsAttention }
            if hasPermission { return }
            self.collapse()
        }
    }

    private func subscribeToStore() {
        SessionStore.shared.observe { [weak self] changedSessionID, sessions in
            guard let self = self else { return }

            let session = sessions.first(where: { $0.sessionID == changedSessionID })

            if self.isExpanded {
                self.refreshList()

                if let s = session, case .ended = s.phase {
                    self.panel.bounce()
                    NSSound(named: .init("Tink"))?.play()
                }
                return
            }

            guard let session = session else { return }

            switch session.phase {
            case .waitingForApproval:
                self.expandToList()
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKeyAndOrderFront(nil)

            case .ended:
                self.panel.bounce()
                NSSound(named: .init("Tink"))?.play()
                self.expandToList()

            default:
                break
            }
        }
    }

    private func expandToList() {
        let sessions = SessionStore.shared.allSessions
        guard !sessions.isEmpty else { return }

        isExpanded = true
        dismissTimer?.invalidate()

        let state = IslandState.expandedList(sessions: sessions)
        transition(to: state)
    }

    private func refreshList() {
        let sessions = SessionStore.shared.allSessions
        if sessions.isEmpty {
            collapse()
            return
        }

        currentListView?.configure(sessions: sessions)

        let newState = IslandState.expandedList(sessions: sessions)
        if newState.belowHeight != currentIslandState.belowHeight {
            currentIslandState = newState
            panel.animateToSize(width: newState.width, belowHeight: newState.belowHeight)
        }
    }

    private func collapse() {
        isExpanded = false
        dismissTimer?.invalidate()
        dismissTimer = nil
        currentIslandState = .idle
        currentListView = nil
        panel.hide()
    }

    func transition(to newState: IslandState) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        currentIslandState = newState

        if case .idle = newState {
            panel.hide()
            return
        }

        let w = newState.width
        let belowH = newState.belowHeight

        contentContainer.alphaValue = 0
        contentContainer.frame = NSRect(x: 0, y: 0, width: w, height: belowH)
        updateContent(for: newState)

        rootView.layer?.cornerRadius = newState.cornerRadius
        rootView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        panel.ignoresMouseEvents = false
        if !panel.isShowing {
            panel.show(width: w, belowHeight: belowH)
        } else {
            panel.animateToSize(width: w, belowHeight: belowH)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.contentContainer.animator().alphaValue = 1
            }
        }
    }

    private func updateContent(for state: IslandState) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        currentListView = nil

        let frame = NSRect(x: 0, y: 0, width: state.width, height: state.belowHeight)

        switch state {
        case .idle:
            break

        case .compact(let session):
            let cv = CompactContentView(frame: frame)
            cv.configure(session: session)
            contentContainer.addSubview(cv)

        case .expandedPermission(let session, let context):
            let pv = PermissionContentView(frame: frame)
            pv.configure(session: session, context: context)
            pv.onAllow = { [weak self] in
                SessionStore.shared.process(.permissionApproved(sessionID: session.sessionID))
                self?.collapse()
            }
            pv.onDeny = { [weak self] in
                SessionStore.shared.process(.permissionDenied(sessionID: session.sessionID))
                self?.collapse()
            }
            contentContainer.addSubview(pv)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)

        case .done(let session):
            let dv = DoneContentView(frame: frame)
            dv.configure(session: session)
            contentContainer.addSubview(dv)

        case .expandedList(let sessions):
            let lv = SessionListView(frame: frame)
            lv.configure(sessions: sessions)
            lv.onAllow = { sessionID in
                SessionStore.shared.process(.permissionApproved(sessionID: sessionID))
            }
            lv.onDeny = { sessionID in
                SessionStore.shared.process(.permissionDenied(sessionID: sessionID))
            }
            contentContainer.addSubview(lv)
            currentListView = lv
        }
    }
}
