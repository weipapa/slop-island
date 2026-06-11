import SwiftUI

struct SessionListContentView: View {
    var viewModel: IslandViewModel
    private let store = SessionStore.shared
    @State private var terminalName = "Terminal"

    var body: some View {
        let sessions = sortedSessions
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 2) {
                    ForEach(sessions) { session in
                        SessionRowContentView(
                            session: session,
                            terminalName: terminalName,
                            onTap: { handleTap(session) },
                            onApprove: { store.process(.permissionApproved(sessionID: session.sessionID)) },
                            onDeny: { store.process(.permissionDenied(sessionID: session.sessionID)) }
                        )
                    }
                }
            }
        }
        // Detect the terminal name off the render path: only when the set of
        // sessions changes (e.g. a new `claude` appears), never on every body
        // re-evaluation. Writing state from inside `body` would re-trigger
        // `body`, spinning a `/bin/ps` fork loop that pins the CPU.
        .task(id: sessions.count) {
            terminalName = await detectTerminalName()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            Text("Run claude in terminal")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sortedSessions: [SessionState] {
        store.allSessions.sorted { priority($0.phase) < priority($1.phase) }
    }

    private func priority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval: return 0
        case .waitingForQuestion: return 0
        case .processing: return 1
        case .ended: return 2
        case .idle: return 3
        }
    }

    private func handleTap(_ session: SessionState) {
        switch session.phase {
        case .waitingForQuestion(let question):
            viewModel.showQuestion(question)
        default:
            TerminalFocuser.shared.focusTerminal(cwd: session.cwd)
        }
    }

    private func detectTerminalName() async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let tree = ProcessTreeBuilder.shared.buildTree()
                for (_, info) in tree {
                    guard info.command.lowercased().contains("claude") else { continue }
                    if let termPID = ProcessTreeBuilder.shared.findTerminalPID(forProcess: info.pid, tree: tree),
                       let termInfo = tree[termPID] {
                        let name = URL(fileURLWithPath: termInfo.command).deletingPathExtension().lastPathComponent
                        continuation.resume(returning: name.capitalized)
                        return
                    }
                }
                continuation.resume(returning: "Terminal")
            }
        }
    }
}
