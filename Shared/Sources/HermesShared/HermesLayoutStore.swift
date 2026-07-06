// HermesLayoutStore.swift
// String-keyed persistent layout cache backing the extension's per-session recovery path.
//
// Why this exists: on iOS 26, tapping a HermesShare bubble while the extension is warm
// delivers an MSMessage whose `url` is nil (didSelect AND conversation.selectedMessage),
// even though the same message carried its full URL in willBecomeActive moments earlier.
// Every layout the extension composes or successfully decodes is stored here, keyed by the
// message's session UUID, so a later nil-url selection can still render the RIGHT card.
//
// Deliberately NO "most recent layout" accessor: a global latest-card fallback silently
// substitutes a different card whenever the per-session lookup misses, which in a
// multi-card conversation means every unresolved tap renders someone else's content
// (the exact "everything routes to one card" bug this replaced). Unresolved is a valid
// answer; callers must surface it, not guess.
//
// The store is keyed by plain strings (not MSSession) so the lookup/routing logic is unit
// testable from the HermesShared package, which cannot link the Messages framework.

import Foundation

public struct HermesLayoutStore {

    public static let appGroupSuite = "group.com.hermesshare.app"

    /// The production store, shared between the extension processes via the app group.
    public static let shared = HermesLayoutStore(
        defaults: UserDefaults(suiteName: appGroupSuite) ?? .standard
    )

    private static let keyPrefix = "hermes-layout-cache:"
    private static let indexKey = "hermes-layout-cache-index"
    private static let maxEntries = 24

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// MSSession exposes no public identifier, but its description embeds the session UUID
    /// ("<MSSession 0x...> - 5433A1DB-...."). That UUID is stable across warm re-taps of the
    /// same message (verified on-device, iOS 26: same UUID delivered through different
    /// MSSession object instances), so it is a sound cache key. If Apple ever changes the
    /// description format this returns nil and callers must treat the card as unresolved —
    /// never fall back to a different card.
    public static func sessionKey(fromSessionDescription description: String) -> String? {
        guard let range = description.range(
            of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
            options: .regularExpression
        ) else { return nil }
        return keyPrefix + description[range].uppercased()
    }

    public func store(layout: HermesLayout, key: String) {
        guard let data = try? layout.encoded() else { return }
        defaults.set(data, forKey: key)

        // Simple LRU-ish index so the suite doesn't grow forever.
        var index = defaults.stringArray(forKey: Self.indexKey) ?? []
        index.removeAll { $0 == key }
        index.append(key)
        while index.count > Self.maxEntries {
            defaults.removeObject(forKey: index.removeFirst())
        }
        defaults.set(index, forKey: Self.indexKey)
    }

    public func layout(forKey key: String) -> HermesLayout? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? HermesLayout.decode(from: data)
    }

    /// Every key currently indexed, oldest first. Forensic logging only — routing must never
    /// iterate the store looking for "some card to show" (that's the fallback bug reborn).
    public func indexedKeys() -> [String] {
        defaults.stringArray(forKey: Self.indexKey) ?? []
    }

    /// Test helper: wipe every entry this store has indexed.
    public func removeAll() {
        for key in defaults.stringArray(forKey: Self.indexKey) ?? [] {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: Self.indexKey)
    }
}
