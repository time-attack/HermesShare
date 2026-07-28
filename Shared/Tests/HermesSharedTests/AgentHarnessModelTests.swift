// AgentHarnessModelTests.swift
// Verifies the Swift side decodes exactly what harness/server.mjs emits.

import XCTest
@testable import HermesShared

final class AgentHarnessModelTests: XCTestCase {

    /// A verbatim envelope as produced by the Node harness server.
    private let serverEnvelopeJSON = """
    {
      "type": "state",
      "state": {
        "sessionID": "4C1D2A9B-0000-4000-8000-123456789ABC",
        "title": "Build live harness",
        "status": "working",
        "currentTask": "Run unit tests",
        "currentAction": "xcodebuild test…",
        "todos": [
          { "id": "a", "content": "Add models", "status": "completed" },
          { "id": "b", "content": "Run tests", "status": "in_progress" },
          { "id": "c", "content": "Install to phone", "status": "pending" },
          { "id": "d", "content": "Old idea", "status": "cancelled" }
        ],
        "screenshotSeq": 3,
        "updatedAt": 1751932800
      }
    }
    """

    func testDecodesServerEnvelope() throws {
        let envelope = try AgentHarnessCoding.decoder()
            .decode(AgentHarnessEnvelope.self, from: Data(serverEnvelopeJSON.utf8))
        XCTAssertEqual(envelope.type, .state)

        let state = try XCTUnwrap(envelope.state)
        XCTAssertEqual(state.status, .working)
        XCTAssertEqual(state.currentTask, "Run unit tests")
        XCTAssertEqual(state.todos.count, 4)
        XCTAssertEqual(state.todos[1].status, .inProgress)
        XCTAssertEqual(state.screenshotSeq, 3)
    }

    func testProgressExcludesCancelled() throws {
        let envelope = try AgentHarnessCoding.decoder()
            .decode(AgentHarnessEnvelope.self, from: Data(serverEnvelopeJSON.utf8))
        let state = try XCTUnwrap(envelope.state)
        XCTAssertEqual(state.completedCount, 1)
        XCTAssertEqual(state.totalCount, 3)   // cancelled todo excluded
        XCTAssertEqual(state.progress, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testHeadlineFallbacks() {
        var state = AgentSessionState(sessionID: "s", title: "Title")
        XCTAssertEqual(state.headline, "Title")

        state.todos = [AgentTodoItem(id: "1", content: "Active todo", status: .inProgress)]
        XCTAssertEqual(state.headline, "Active todo")

        state.currentTask = "Explicit task"
        XCTAssertEqual(state.headline, "Explicit task")
    }

    func testRoundTrip() throws {
        let state = AgentSessionState(
            sessionID: "abc",
            title: "T",
            status: .waiting,
            currentTask: "task",
            currentAction: "action",
            todos: [AgentTodoItem(id: "1", content: "x", status: .pending)],
            screenshotSeq: 7,
            updatedAt: 1000
        )
        let data = try AgentHarnessCoding.encoder().encode(AgentHarnessEnvelope(type: .hello, state: state))
        let decoded = try AgentHarnessCoding.decoder().decode(AgentHarnessEnvelope.self, from: data)
        XCTAssertEqual(decoded.state, state)
    }

    func testSessionEndEnvelopeWithoutState() throws {
        let json = #"{ "type": "sessionEnd" }"#
        let envelope = try AgentHarnessCoding.decoder()
            .decode(AgentHarnessEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.type, .sessionEnd)
        XCTAssertNil(envelope.state)
    }
}
