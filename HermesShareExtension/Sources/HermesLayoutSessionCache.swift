// HermesLayoutSessionCache.swift
// Thin MSSession-facing adapter over the shared, string-keyed HermesLayoutStore (see that
// file for the full rationale: iOS 26 delivers url=nil on warm bubble taps, so decoded and
// composed layouts are cached per session UUID for later recovery).
//
// There is intentionally no "latest layout" fallback anymore: it silently substituted a
// different card whenever the per-session lookup missed, which in any conversation with two
// or more HermesShare cards routed every unresolved tap to the wrong card.

import Foundation
import Messages
import HermesShared

enum HermesLayoutSessionCache {

    static func key(for session: MSSession?) -> String? {
        guard let session else { return nil }
        return HermesLayoutStore.sessionKey(fromSessionDescription: String(describing: session))
    }

    static func store(layout: HermesLayout, for session: MSSession?) {
        guard let key = key(for: session) else { return }
        HermesLayoutStore.shared.store(layout: layout, key: key)
    }

    static func layout(for session: MSSession?) -> HermesLayout? {
        guard let key = key(for: session) else { return nil }
        return HermesLayoutStore.shared.layout(forKey: key)
    }
}
