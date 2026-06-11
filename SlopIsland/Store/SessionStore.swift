import Foundation
import Observation

@Observable
final class SessionStore {

    static let shared = SessionStore()
    private init() {}

    /// Set by AppDelegate; owns the open permission fds and writes decisions back.
    weak var hookServer: HookServer?

    /// How long an ended session stays visible before being recycled.
    private let endedRetentionSeconds: TimeInterval = 30

    /// Notified when a session is removed, so other components (e.g.
    /// AgentMonitor) can drop their per-session caches.
    private var removalObservers: [(String) -> Void] = []

    private(set) var sessions: [String: SessionState] = [:]
    private var observers: [(String, [SessionState]) -> Void] = []

    var allSessions: [SessionState] {
        Array(sessions.values).sorted { $0.lastActivity > $1.lastActivity }
    }

    var activeSession: SessionState? {
        sessions.values.first { $0.phase.isActive || $0.phase.needsAttention }
            ?? sessions.values.max(by: { $0.lastActivity < $1.lastActivity })
    }

    func observe(_ handler: @escaping (String, [SessionState]) -> Void) {
        observers.append(handler)
    }

    /// Answer an AskUserQuestion by injecting each question's chosen option
    /// number into the terminal (Claude's own TUI is still showing it). For
    /// multiple questions the sequence advances with Tab and submits with Return.
    func answerQuestion(_ question: UserQuestion, optionIndices: [Int]) {
        let numbers = optionIndices.map { $0 + 1 }
        KeySender.sendAnswerSequence(numbers: numbers, cwd: question.cwd)
        updatePhase(sessionID: question.sessionID, phase: .processing(action: "continuing"))
    }

    func observeRemoval(_ handler: @escaping (String) -> Void) {
        removalObservers.append(handler)
    }

    func process(_ event: SessionEvent) {
        switch event {
        case .hookReceived(let hook):
            processHook(hook)

        case .permissionApproved(let sessionID):
            hookServer?.respond(sessionID: sessionID, decision: "allow")
            updatePhase(sessionID: sessionID, phase: .processing(action: "continuing"))

        case .permissionDenied(let sessionID):
            hookServer?.respond(sessionID: sessionID, decision: "deny")
            updatePhase(sessionID: sessionID, phase: .idle)

        case .permissionTimedOut(let sessionID):
            // fd already closed by HookServer; just reflect that we're no longer waiting.
            updatePhase(sessionID: sessionID, phase: .idle)

        case .questionReceived(let question):
            let projectDir = question.cwd.replacingOccurrences(of: "/", with: "-")
            let projectName = URL(fileURLWithPath: question.cwd).lastPathComponent
            ensureSession(id: question.sessionID, projectDir: projectDir, projectName: projectName.isEmpty ? "Claude" : projectName, cwd: question.cwd)
            updatePhase(sessionID: question.sessionID, phase: .waitingForQuestion(question))

        case .questionAnswered(let sessionID, _):
            // Answers are delivered to the terminal via KeySender, not the socket.
            updatePhase(sessionID: sessionID, phase: .processing(action: "continuing"))

        case .activityDetected(let sessionID, let action, let projectDir, let projectName, let cwd):
            ensureSession(id: sessionID, projectDir: projectDir, projectName: projectName, cwd: cwd)
            updatePhase(sessionID: sessionID, phase: .processing(action: action))

        case .sessionEnded(let sessionID):
            updatePhase(sessionID: sessionID, phase: .ended)

        case .sessionIdle(let sessionID):
            updatePhase(sessionID: sessionID, phase: .idle)
        }
    }

    private func processHook(_ hook: HookEvent) {
        let projectDir = hook.cwd.replacingOccurrences(of: "/", with: "-")
        ensureSession(id: hook.sessionID, projectDir: projectDir, projectName: hook.projectName,
                      transcriptPath: hook.transcriptPath, cwd: hook.cwd)

        switch hook.status {
        case "waiting_for_approval":
            let ctx = PermissionContext(
                toolUseID: hook.sessionID,
                toolName: hook.toolName,
                toolInput: hook.toolInputSummary,
                receivedAt: Date()
            )
            updatePhase(sessionID: hook.sessionID, phase: .waitingForApproval(ctx))

        case "ended":
            updatePhase(sessionID: hook.sessionID, phase: .ended)

        case "waiting_for_input", "idle":
            updatePhase(sessionID: hook.sessionID, phase: .idle)

        case "processing":
            updatePhase(sessionID: hook.sessionID, phase: .processing(action: "processing"))

        default:
            break
        }
    }

    private func ensureSession(id: String, projectDir: String, projectName: String, transcriptPath: String = "", cwd: String = "") {
        sessions = SessionState.ensuring(
            sessions, id: id, projectDir: projectDir,
            projectName: projectName, transcriptPath: transcriptPath, cwd: cwd, now: Date())
    }

    private func updatePhase(sessionID: String, phase: SessionPhase) {
        let result = SessionState.applyingPhase(sessions, id: sessionID, phase: phase, now: Date())
        guard result.changed else { return }
        sessions = result.sessions
        notifyObservers(changedSessionID: sessionID)

        if case .ended = phase {
            scheduleRemoval(sessionID: sessionID)
        }
    }

    /// Remove an ended session after a grace period, unless it has reactivated
    /// (its phase changed away from .ended or its activity timestamp advanced).
    private func scheduleRemoval(sessionID: String) {
        let endedAt = sessions[sessionID]?.lastActivity
        DispatchQueue.main.asyncAfter(deadline: .now() + endedRetentionSeconds) { [weak self] in
            guard let self = self, let session = self.sessions[sessionID] else { return }
            guard SessionState.shouldRemoveEnded(session, endedAt: endedAt) else { return }
            self.sessions.removeValue(forKey: sessionID)
            for observer in self.removalObservers { observer(sessionID) }
            self.notifyObservers(changedSessionID: sessionID)
        }
    }

    private func notifyObservers(changedSessionID: String) {
        let snapshot = allSessions
        for observer in observers {
            observer(changedSessionID, snapshot)
        }
    }
}
