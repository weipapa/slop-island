import Foundation

struct AgentInfo {
    let name: String
    let sessionId: String
    let workingDirectory: String
    let model: String

    static let placeholder = AgentInfo(
        name: "Claude Code",
        sessionId: "demo-session",
        workingDirectory: "~/project",
        model: "opus-4"
    )
}
