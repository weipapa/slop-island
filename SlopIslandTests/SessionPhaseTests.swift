import XCTest
@testable import SlopIsland

/// State-machine transition rules. These guard the invariant that an attention
/// state (waiting for approval / question) is never silently clobbered by plain
/// activity, while still allowing legitimate resolutions and attention swaps.
final class SessionPhaseTests: XCTestCase {

    private func permissionCtx() -> PermissionContext {
        PermissionContext(toolUseID: "t", toolName: "Bash", toolInput: "ls", receivedAt: Date(timeIntervalSince1970: 0))
    }

    private func question() -> UserQuestion {
        UserQuestion(sessionID: "s", cwd: "/tmp", items: [
            QuestionItem(header: "h", prompt: "p", options: [QuestionOption(label: "a", description: nil)], multiSelect: false)
        ])
    }

    func testSamePhaseAlwaysTransitions() {
        XCTAssertTrue(SessionPhase.idle.canTransition(to: .idle))
    }

    func testAnyPhaseMayEnd() {
        XCTAssertTrue(SessionPhase.idle.canTransition(to: .ended))
        XCTAssertTrue(SessionPhase.processing(action: "x").canTransition(to: .ended))
        XCTAssertTrue(SessionPhase.waitingForApproval(permissionCtx()).canTransition(to: .ended))
        XCTAssertTrue(SessionPhase.waitingForQuestion(question()).canTransition(to: .ended))
    }

    func testApprovalResolvesToProcessingOrIdle() {
        let p = SessionPhase.waitingForApproval(permissionCtx())
        XCTAssertTrue(p.canTransition(to: .processing(action: "continuing")))
        XCTAssertTrue(p.canTransition(to: .idle))
    }

    // P1-4: the two attention states may swap directly. This is the regression
    // guard for the fix that previously dropped such events silently.
    func testAttentionStatesMaySwap() {
        let approval = SessionPhase.waitingForApproval(permissionCtx())
        let question = SessionPhase.waitingForQuestion(question())
        XCTAssertTrue(approval.canTransition(to: question))
        XCTAssertTrue(question.canTransition(to: approval))
    }

    func testEndedReactivatesOnRealActivityButNotIdle() {
        let ended = SessionPhase.ended
        XCTAssertTrue(ended.canTransition(to: .processing(action: "x")))
        XCTAssertTrue(ended.canTransition(to: .waitingForApproval(permissionCtx())))
        XCTAssertTrue(ended.canTransition(to: .waitingForQuestion(question())))
        XCTAssertFalse(ended.canTransition(to: .idle))
    }
}
