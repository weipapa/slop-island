import XCTest
@testable import SlopIsland

/// Lenient decoding of Claude Code transcript lines. The format varies across
/// record types (notably `message.content` being a string vs an array), so the
/// decoder must extract what it can without failing whole records.
final class TranscriptRecordTests: XCTestCase {

    func testDecodesCwd() {
        let line = #"{"type":"user","cwd":"/Users/x/project/foo","message":{"content":"hi"}}"#
        let r = TranscriptRecord.decode(line: line)
        XCTAssertEqual(r?.cwd, "/Users/x/project/foo")
    }

    func testStringContentDecodesToNilBlocksNotFailure() {
        // Some user records carry a plain-string content; the record must still
        // decode (cwd/type intact), with content simply absent.
        let line = #"{"type":"user","cwd":"/tmp","message":{"content":"plain string"}}"#
        let r = TranscriptRecord.decode(line: line)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.type, "user")
        XCTAssertNil(r?.message?.content)
    }

    func testAssistantToolUseBlockExtracted() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]}}"#
        let r = TranscriptRecord.decode(line: line)
        let block = r?.firstAssistantBlock
        XCTAssertEqual(block?.type, "tool_use")
        XCTAssertEqual(block?.name, "Bash")
        XCTAssertEqual(block?.input?.command, "ls -la")
    }

    func testAssistantTextBlockExtracted() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"thinking..."}]}}"#
        XCTAssertEqual(TranscriptRecord.decode(line: line)?.firstAssistantBlock?.type, "text")
    }

    func testFilePathInputDecoded() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b/c.swift"}}]}}"#
        XCTAssertEqual(TranscriptRecord.decode(line: line)?.firstAssistantBlock?.input?.filePath, "/a/b/c.swift")
    }

    func testSystemStopSubtype() {
        let line = #"{"type":"system","subtype":"stop"}"#
        let r = TranscriptRecord.decode(line: line)
        XCTAssertEqual(r?.type, "system")
        XCTAssertEqual(r?.subtype, "stop")
    }

    func testBlankAndGarbageLinesReturnNil() {
        XCTAssertNil(TranscriptRecord.decode(line: ""))
        XCTAssertNil(TranscriptRecord.decode(line: "not json"))
    }

    func testFirstAssistantBlockNilForNonAssistant() {
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result"}]}}"#
        XCTAssertNil(TranscriptRecord.decode(line: line)?.firstAssistantBlock)
    }
}
