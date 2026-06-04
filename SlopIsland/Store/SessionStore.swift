import Foundation
import Observation

@Observable
final class SessionStore {

    static let shared = SessionStore()
    private init() {}

    private(set) var sessions: [String: SessionState] = [:]
    private var observers: [(String, [SessionState]) -> Void] = []
    private var pendingResponders: [String: (String) -> Void] = [:]

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

    func setPermissionResponder(sessionID: String, responder: @escaping (String) -> Void) {
        pendingResponders[sessionID] = responder
    }

    func process(_ event: SessionEvent) {
        switch event {
        case .hookReceived(let payload):
            processHook(payload)

        case .permissionApproved(let sessionID):
            if let responder = pendingResponders.removeValue(forKey: sessionID) {
                responder("Allow Once")
            }
            updatePhase(sessionID: sessionID, phase: .processing(action: "continuing"))

        case .permissionDenied(let sessionID):
            if let responder = pendingResponders.removeValue(forKey: sessionID) {
                responder("Deny")
            }
            updatePhase(sessionID: sessionID, phase: .idle)

        case .questionReceived(let question):
            let projectDir = question.cwd.replacingOccurrences(of: "/", with: "-")
            let projectName = URL(fileURLWithPath: question.cwd).lastPathComponent
            ensureSession(id: question.sessionID, projectDir: projectDir, projectName: projectName.isEmpty ? "Claude" : projectName)
            updatePhase(sessionID: question.sessionID, phase: .waitingForQuestion(question))

        case .questionAnswered(let sessionID, let answer):
            if let responder = pendingResponders.removeValue(forKey: sessionID) {
                responder(answer)
            }
            updatePhase(sessionID: sessionID, phase: .processing(action: "continuing"))

        case .activityDetected(let sessionID, let action, let projectDir, let projectName):
            ensureSession(id: sessionID, projectDir: projectDir, projectName: projectName)
            updatePhase(sessionID: sessionID, phase: .processing(action: action))

        case .sessionEnded(let sessionID):
            updatePhase(sessionID: sessionID, phase: .ended)

        case .sessionIdle(let sessionID):
            updatePhase(sessionID: sessionID, phase: .idle)
        }
    }

    private func processHook(_ payload: HookPayload) {
        let projectDir = payload.cwd.replacingOccurrences(of: "/", with: "-")
        let projectName = URL(fileURLWithPath: payload.cwd).lastPathComponent
        ensureSession(id: payload.sessionID, projectDir: projectDir, projectName: projectName)

        if payload.permissionMode == "ask" {
            let ctx = PermissionContext(
                toolUseID: payload.sessionID,
                toolName: payload.toolName,
                toolInput: payload.toolInput,
                receivedAt: Date()
            )
            updatePhase(sessionID: payload.sessionID, phase: .waitingForApproval(ctx))
        } else {
            updatePhase(sessionID: payload.sessionID, phase: .processing(action: payload.toolName))
        }
    }

    private func ensureSession(id: String, projectDir: String, projectName: String) {
        guard sessions[id] == nil else { return }
        sessions[id] = SessionState(
            sessionID: id,
            projectDir: projectDir,
            projectName: projectName.isEmpty ? "project" : projectName,
            phase: .idle,
            lastActivity: Date()
        )
    }

    private func updatePhase(sessionID: String, phase: SessionPhase) {
        guard let session = sessions[sessionID] else { return }
        guard session.phase.canTransition(to: phase) else { return }
        sessions[sessionID] = SessionState(
            sessionID: session.sessionID,
            projectDir: session.projectDir,
            projectName: session.projectName,
            phase: phase,
            lastActivity: Date()
        )
        notifyObservers(changedSessionID: sessionID)
    }

    private func notifyObservers(changedSessionID: String) {
        let snapshot = allSessions
        for observer in observers {
            observer(changedSessionID, snapshot)
        }
    }
}
