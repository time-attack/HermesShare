// AgentHarnessModels.swift
// Wire format shared by the harness server, the host-app dashboard, and the Live Activity
// widget. The harness server (harness/server.mjs) is the source of truth; the app receives
// full `AgentSessionState` snapshots over WebSocket and mirrors them into ActivityKit.

import Foundation

// MARK: - Run status

public enum AgentRunStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case idle
    case working
    case waiting   // blocked on user input
    case done
    case error

    public var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .waiting: return "Needs input"
        case .done: return "Done"
        case .error: return "Error"
        }
    }

    public var systemImage: String {
        switch self {
        case .idle: return "moon.zzz.fill"
        case .working: return "bolt.fill"
        case .waiting: return "person.fill.questionmark"
        case .done: return "checkmark.seal.fill"
        case .error: return "exclamationmark.octagon.fill"
        }
    }

    /// Accent hex used by both the dashboard and the Live Activity so they match.
    public var accentHex: String {
        switch self {
        case .idle: return "#8E8E93"
        case .working: return "#0A84FF"
        case .waiting: return "#FF9F0A"
        case .done: return "#30D158"
        case .error: return "#FF453A"
        }
    }
}

// MARK: - Todos

public struct AgentTodoItem: Codable, Hashable, Identifiable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
        case cancelled
    }

    public var id: String
    public var content: String
    public var status: Status

    public init(id: String, content: String, status: Status) {
        self.id = id
        self.content = content
        self.status = status
    }
}

// MARK: - Session state snapshot

public struct AgentSessionState: Codable, Hashable, Sendable {
    public var sessionID: String
    /// Human title for the whole run, e.g. "Build HermesShare live harness".
    public var title: String
    public var status: AgentRunStatus
    /// The todo currently being worked on ("what task it's on right now").
    public var currentTask: String?
    /// The concrete thing happening at this instant, e.g. "Running xcodebuild…".
    public var currentAction: String?
    public var todos: [AgentTodoItem]
    /// Monotonic counter bumped every time the agent uploads a new preview image.
    /// The app refetches `GET /api/screenshot` whenever this changes. 0 = no image yet.
    public var screenshotSeq: Int
    /// Unix epoch seconds. Plain number to keep the JS side trivial.
    public var updatedAt: TimeInterval

    public init(
        sessionID: String,
        title: String,
        status: AgentRunStatus = .idle,
        currentTask: String? = nil,
        currentAction: String? = nil,
        todos: [AgentTodoItem] = [],
        screenshotSeq: Int = 0,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.sessionID = sessionID
        self.title = title
        self.status = status
        self.currentTask = currentTask
        self.currentAction = currentAction
        self.todos = todos
        self.screenshotSeq = screenshotSeq
        self.updatedAt = updatedAt
    }

    public var completedCount: Int { todos.filter { $0.status == .completed }.count }
    /// Cancelled todos don't count against progress.
    public var totalCount: Int { todos.filter { $0.status != .cancelled }.count }
    public var progress: Double {
        totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
    }

    /// Falls back through task → first in-progress todo so the UI always has a headline.
    public var headline: String {
        if let currentTask, !currentTask.isEmpty { return currentTask }
        if let active = todos.first(where: { $0.status == .inProgress }) { return active.content }
        return title
    }
}

// MARK: - WebSocket envelope (server → app)

public struct AgentHarnessEnvelope: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case hello       // first message after connecting; carries current state
        case state       // state changed
        case sessionEnd  // agent finished; app should end the Live Activity
        case ping
    }

    public var type: Kind
    public var state: AgentSessionState?

    public init(type: Kind, state: AgentSessionState? = nil) {
        self.type = type
        self.state = state
    }
}

public enum AgentHarnessCoding {
    public static func decoder() -> JSONDecoder { JSONDecoder() }
    public static func encoder() -> JSONEncoder { JSONEncoder() }
}

// MARK: - Live Activity attributes

#if canImport(ActivityKit)
import ActivityKit

public struct AgentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: AgentRunStatus
        public var currentTask: String?
        public var currentAction: String?
        public var completedCount: Int
        public var totalCount: Int
        public var updatedAt: TimeInterval

        public init(
            status: AgentRunStatus,
            currentTask: String?,
            currentAction: String?,
            completedCount: Int,
            totalCount: Int,
            updatedAt: TimeInterval
        ) {
            self.status = status
            self.currentTask = currentTask
            self.currentAction = currentAction
            self.completedCount = completedCount
            self.totalCount = totalCount
            self.updatedAt = updatedAt
        }

        public init(from state: AgentSessionState) {
            self.init(
                status: state.status,
                currentTask: state.headline,
                currentAction: state.currentAction,
                completedCount: state.completedCount,
                totalCount: state.totalCount,
                updatedAt: state.updatedAt
            )
        }

        public var progress: Double {
            totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
        }
    }

    public var sessionID: String
    public var title: String

    public init(sessionID: String, title: String) {
        self.sessionID = sessionID
        self.title = title
    }
}
#endif
