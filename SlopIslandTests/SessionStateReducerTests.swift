import XCTest
@testable import SlopIsland

/// Pure reducers over the session map. No singletons, timers or sockets — just
/// (state, input) -> state. These back the side-effectful SessionStore.
final class SessionStateReducerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    // MARK: ensuring

    func testEnsuringInsertsNewSession() {
        let out = SessionState.ensuring([:], id: "s1", projectDir: "dir", projectName: "Proj", now: t0)
        XCTAssertEqual(out["s1"]?.projectName, "Proj")
        XCTAssertEqual(out["s1"]?.phase, .idle)
        XCTAssertEqual(out["s1"]?.lastActivity, t0)
    }

    func testEnsuringIsIdempotentForExisting() {
        let first = SessionState.ensuring([:], id: "s1", projectDir: "dir", projectName: "Proj", now: t0)
        let second = SessionState.ensuring(first, id: "s1", projectDir: "dir", projectName: "Other", now: t1)
        // Existing session is preserved untouched (name not overwritten).
        XCTAssertEqual(second["s1"]?.projectName, "Proj")
        XCTAssertEqual(second["s1"]?.lastActivity, t0)
    }

    func testEnsuringBackfillsTranscriptPathOnce() {
        let first = SessionState.ensuring([:], id: "s1", projectDir: "dir", projectName: "Proj", now: t0)
        XCTAssertEqual(first["s1"]?.transcriptPath, "")
        let second = SessionState.ensuring(first, id: "s1", projectDir: "dir", projectName: "Proj", transcriptPath: "/x.jsonl", now: t1)
        XCTAssertEqual(second["s1"]?.transcriptPath, "/x.jsonl")
        // Backfill must not bump lastActivity.
        XCTAssertEqual(second["s1"]?.lastActivity, t0)
    }

    func testEnsuringEmptyNameFallsBackToProject() {
        let out = SessionState.ensuring([:], id: "s1", projectDir: "dir", projectName: "", now: t0)
        XCTAssertEqual(out["s1"]?.projectName, "project")
    }

    // MARK: applyingPhase

    func testApplyingPhaseAdvancesWhenAllowed() {
        let base = SessionState.ensuring([:], id: "s1", projectDir: "d", projectName: "P", now: t0)
        let r = SessionState.applyingPhase(base, id: "s1", phase: .processing(action: "go"), now: t1)
        XCTAssertTrue(r.changed)
        XCTAssertEqual(r.sessions["s1"]?.phase, .processing(action: "go"))
        XCTAssertEqual(r.sessions["s1"]?.lastActivity, t1)
    }

    func testApplyingPhaseRejectsDisallowedTransition() {
        // ended -> idle is disallowed; map must be returned unchanged.
        var base = SessionState.ensuring([:], id: "s1", projectDir: "d", projectName: "P", now: t0)
        base = SessionState.applyingPhase(base, id: "s1", phase: .ended, now: t0).sessions
        let r = SessionState.applyingPhase(base, id: "s1", phase: .idle, now: t1)
        XCTAssertFalse(r.changed)
        XCTAssertEqual(r.sessions["s1"]?.phase, .ended)
    }

    func testApplyingPhaseUnknownSessionIsNoOp() {
        let r = SessionState.applyingPhase([:], id: "ghost", phase: .idle, now: t0)
        XCTAssertFalse(r.changed)
        XCTAssertTrue(r.sessions.isEmpty)
    }

    // MARK: shouldRemoveEnded (grace-period predicate)

    func testShouldRemoveEndedWhenStillEndedAndUntouched() {
        let s = SessionState(sessionID: "s", projectDir: "d", projectName: "P", phase: .ended, lastActivity: t0)
        XCTAssertTrue(SessionState.shouldRemoveEnded(s, endedAt: t0))
    }

    func testShouldNotRemoveWhenReactivated() {
        let s = SessionState(sessionID: "s", projectDir: "d", projectName: "P", phase: .processing(action: "x"), lastActivity: t1)
        XCTAssertFalse(SessionState.shouldRemoveEnded(s, endedAt: t0))
    }

    func testShouldNotRemoveWhenTimestampAdvanced() {
        // Re-ended later: same phase but a newer timestamp means a fresh end.
        let s = SessionState(sessionID: "s", projectDir: "d", projectName: "P", phase: .ended, lastActivity: t1)
        XCTAssertFalse(SessionState.shouldRemoveEnded(s, endedAt: t0))
    }
}

/// P0-1: project display name derives from the real cwd, with a safe fallback.
final class ProjectNameTests: XCTestCase {

    func testPrefersCwdLastComponent() {
        let name = AgentMonitor.projectName(cwd: "/Users/someone/project/slop-island", projectDir: "-Users-someone-project-slop-island")
        XCTAssertEqual(name, "slop-island")
    }

    func testFallsBackToLastDashSegmentWhenNoCwd() {
        let name = AgentMonitor.projectName(cwd: nil, projectDir: "-Users-anybody-project-foo")
        XCTAssertEqual(name, "foo")
    }

    func testEmptyCwdUsesFallback() {
        let name = AgentMonitor.projectName(cwd: "", projectDir: "-a-b-bar")
        XCTAssertEqual(name, "bar")
    }
}
