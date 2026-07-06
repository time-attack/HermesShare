// HermesCardResolver.swift
// The single decision procedure for "which card does this presentContent call render?",
// extracted from MessagesViewController so the EVENT-SEQUENCE routing (not just the store)
// is unit-testable from this package.
//
// Why this exists: the "stuck on the first card" bug survived a first fix because the fix
// only corrected `didSelect`'s resolution. `didTransition(to:)` — which fires on EVERY
// expand, immediately after `didSelect` — still called presentContent with no tapped
// message, fell through to `conversation.selectedMessage` (documented stale on warm taps:
// it can still point at the PREVIOUSLY opened card), and re-rendered the old card right
// over the correct one. The store-level tests all passed because the store was never the
// problem; the caller picked the wrong key before the store was ever consulted.
//
// The view controller now feeds every lifecycle callback through this resolver with
// explicit snapshots of (a) the message the user most recently actually tapped and (b) the
// conversation's claimed selection, and renders exactly what it returns. Rules:
//   - A tapped message always beats the selection.
//   - The selection's decoded layout is only trusted for a tapped message when their
//     session keys match (Messages may hold a hydrated copy of the SAME message there).
//   - A missed lookup is answered with .unresolved — NEVER another session's card.

import Foundation

/// What the view controller knows about one MSMessage, reduced to the facts routing
/// needs: which session it belongs to, whether its URL decoded to a layout, and — for
/// the diagnostic report when nothing resolves — whether it carried a URL at all
/// (distinguishes "Messages delivered url=nil" from "URL present but payload undecodable").
public struct HermesMessageSnapshot {
    public let sessionKey: String?
    public let layout: HermesLayout?
    public let hadURL: Bool

    public init(sessionKey: String?, layout: HermesLayout?, hadURL: Bool) {
        self.sessionKey = sessionKey
        self.layout = layout
        self.hadURL = hadURL
    }

    /// Convenience for callers/tests that only model decode success: a decoded layout
    /// implies a URL was present.
    public init(sessionKey: String?, layout: HermesLayout?) {
        self.init(sessionKey: sessionKey, layout: layout, hadURL: layout != nil)
    }
}

/// Everything known about WHY a specific card failed to resolve. This is a real product
/// surface (rendered on screen by `HermesCardFailureView` and written to the debug log),
/// not debug-only scaffolding: silently showing the wrong card was the bug, and an
/// honest failure is only debuggable if the evidence is visible.
public struct HermesCardDiagnostics: Equatable {
    /// Session key of the message the user actually tapped/selected (nil if the session
    /// UUID itself couldn't be parsed).
    public let sessionKey: String?
    /// Whether any message was in play at all (always true for .unresolved — a total
    /// absence of messages resolves to .compose instead — but recorded explicitly so the
    /// on-screen report never has to infer it).
    public let messageDetected: Bool
    /// Whether the effective message carried a URL when resolution ran.
    public let hadURL: Bool
    /// Every resolution path that was attempted, in order, with its outcome.
    public let attemptedPaths: [String]

    public init(sessionKey: String?, messageDetected: Bool, hadURL: Bool, attemptedPaths: [String]) {
        self.sessionKey = sessionKey
        self.messageDetected = messageDetected
        self.hadURL = hadURL
        self.attemptedPaths = attemptedPaths
    }

    /// The canonical human-readable report. The on-screen error view and the on-device
    /// debug log both render exactly these lines, so what the user sees and what a log
    /// pull shows can never drift apart.
    public func reportLines(urlRetriesExhausted: Int, cachedSessionKeys: [String]) -> [String] {
        var lines: [String] = []
        lines.append("message detected: \(messageDetected ? "yes" : "no")")
        lines.append("session: \(sessionKey.map(Self.shortKey) ?? "unparseable (nil)")")
        lines.append("url: \(hadURL ? "present but payload undecodable" : "nil after \(urlRetriesExhausted) attempts")")
        lines.append("resolution paths attempted:")
        lines.append(contentsOf: attemptedPaths.map { "  • \($0)" })
        if cachedSessionKeys.isEmpty {
            lines.append("session cache: empty")
        } else {
            lines.append("session cache holds \(cachedSessionKeys.count) other card(s): \(cachedSessionKeys.map(Self.shortKey).joined(separator: ", "))")
        }
        return lines
    }

    /// Last 8 chars of the session UUID — enough to match against the log without
    /// filling the screen.
    public static func shortKey(_ key: String) -> String {
        String(key.suffix(8))
    }
}

public enum HermesCardResolution: Equatable {
    /// Render this layout (and cache it under `sessionKey` if non-nil).
    case layout(HermesLayout, sessionKey: String?, source: Source)
    /// No message in play at all — show the compose/empty state.
    case compose
    /// A specific message is in play but its content is unobtainable right now.
    /// Callers retry briefly, then render `HermesCardFailureView` with these diagnostics.
    case unresolved(HermesCardDiagnostics)

    public enum Source: String, Equatable {
        case decodedMessage        // the message's own URL decoded
        case decodedSameSessionSelection  // selectedMessage's URL, proven same session
        case sessionCache          // recovered from the per-session store
    }
}

public struct HermesCardResolver {

    private let store: HermesLayoutStore

    public init(store: HermesLayoutStore) {
        self.store = store
    }

    /// - Parameters:
    ///   - tapped: the message the user most recently explicitly tapped in THIS activation
    ///     (didSelect's message, remembered across the didTransition that follows it), or nil
    ///     if no tap has happened since activation.
    ///   - selected: `conversation.selectedMessage` right now — possibly stale on warm taps.
    public func resolve(
        tapped: HermesMessageSnapshot?,
        selected: HermesMessageSnapshot?
    ) -> HermesCardResolution {
        // The user's actual tap always outranks the conversation's claimed selection.
        guard let effective = tapped ?? selected else { return .compose }

        // Record every path as it fails so an unresolved answer carries the full trail —
        // the on-screen error view and debug log render these lines verbatim.
        var attempted: [String] = []

        if let layout = effective.layout {
            cache(layout, key: effective.sessionKey)
            return .layout(layout, sessionKey: effective.sessionKey, source: .decodedMessage)
        }
        attempted.append(tapped != nil
            ? "tapped message's own URL: \(effective.hadURL ? "present but failed to decode" : "nil")"
            : "selected message's own URL: \(effective.hadURL ? "present but failed to decode" : "nil")")

        // Tapped message has no decodable URL, but Messages may hold a hydrated copy of the
        // SAME message in selectedMessage — trust it only when the session keys prove it.
        if tapped != nil, let selected, let selectedLayout = selected.layout,
           let tappedKey = effective.sessionKey, tappedKey == selected.sessionKey {
            cache(selectedLayout, key: tappedKey)
            return .layout(selectedLayout, sessionKey: tappedKey, source: .decodedSameSessionSelection)
        }
        if tapped != nil {
            if let selected, selected.sessionKey != effective.sessionKey {
                attempted.append("selectedMessage belongs to a DIFFERENT session (\(selected.sessionKey.map(HermesCardDiagnostics.shortKey) ?? "nil")) — refused as a substitute")
            } else if selected != nil {
                attempted.append("selectedMessage is same session but also has no decodable URL")
            } else {
                attempted.append("no selectedMessage to cross-check")
            }
        }

        if let key = effective.sessionKey, let cached = store.layout(forKey: key) {
            return .layout(cached, sessionKey: key, source: .sessionCache)
        }
        attempted.append(effective.sessionKey.map { "session cache lookup for \(HermesCardDiagnostics.shortKey($0)): no entry" }
            ?? "session cache lookup skipped: session UUID unparseable")

        return .unresolved(HermesCardDiagnostics(
            sessionKey: effective.sessionKey,
            messageDetected: true,
            hadURL: effective.hadURL,
            attemptedPaths: attempted
        ))
    }

    private func cache(_ layout: HermesLayout, key: String?) {
        guard let key else { return }
        store.store(layout: layout, key: key)
    }
}
