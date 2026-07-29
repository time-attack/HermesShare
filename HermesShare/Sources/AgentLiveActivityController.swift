// AgentLiveActivityController.swift
// Mirrors harness session state into an ActivityKit Live Activity. Started when the
// first state arrives for a session, updated on every change, ended on sessionEnd.

import ActivityKit
import Foundation
import HermesShared

@MainActor
final class AgentLiveActivityController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var lastError: String?

    private var activity: Activity<AgentActivityAttributes>?
    private var activeSessionID: String?

    var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func apply(state: AgentSessionState) {
        let content = ActivityContent(
            state: AgentActivityAttributes.ContentState(from: state),
            staleDate: Date().addingTimeInterval(60 * 30)
        )

        if let activity, activeSessionID == state.sessionID {
            Task { await activity.update(content) }
            return
        }

        // New session (or first state): replace any stale activity.
        endCurrentActivity(immediately: true)
        do {
            let attributes = AgentActivityAttributes(sessionID: state.sessionID, title: state.title)
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            activeSessionID = state.sessionID
            isActive = true
            lastError = nil
        } catch {
            lastError = "Live Activity failed: \(error.localizedDescription)"
            isActive = false
        }
    }

    func endSession(finalState: AgentSessionState?) {
        guard let activity else { return }
        let content: ActivityContent<AgentActivityAttributes.ContentState>?
        if let finalState {
            content = ActivityContent(
                state: AgentActivityAttributes.ContentState(from: finalState),
                staleDate: nil
            )
        } else {
            content = nil
        }
        Task {
            // Keep the final "Done" state on the lock screen for a bit before dismissal.
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(60 * 5)))
        }
        self.activity = nil
        activeSessionID = nil
        isActive = false
    }

    func endCurrentActivity(immediately: Bool = false) {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: immediately ? .immediate : .default)
        }
        self.activity = nil
        activeSessionID = nil
        isActive = false
    }
}
