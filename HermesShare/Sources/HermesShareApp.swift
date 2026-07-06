// HermesShareApp.swift
// The host/container app. Apple requires an iMessage extension to ship inside a container
// app; beyond satisfying that, this app is a *debug harness* for the renderer — the fastest
// iteration loop for the shared `HermesLayoutRenderer` without going through the full iMessage
// insert flow every time.

import SwiftUI

@main
struct HermesShareApp: App {
    var body: some Scene {
        WindowGroup {
            DebugHarnessView()
                .onOpenURL { url in
                    // Deep links fired by action buttons land here (hermesshare://…).
                    LastDeepLink.shared.url = url
                }
        }
    }
}

/// Tiny observable so the debug screen can show that a deep-link action actually fired.
final class LastDeepLink: ObservableObject {
    static let shared = LastDeepLink()
    @Published var url: URL?
}
