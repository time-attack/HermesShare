// HermesEventRouter.swift
// The event-sequence state machine between MSMessagesAppViewController's lifecycle
// callbacks and HermesCardResolver, extracted (like the resolver before it) so the part
// of routing that actually broke on-device is unit-testable from this package.
//
// Why this exists: the Photon delivery gap. The resolver already never substitutes a
// different session's card when it is TOLD which message the user tapped. But a card
// delivered externally via Photon (customizedMiniApp → didReceive path) while the
// extension isn't running is never cached, and its FIRST tap reaches the extension
// through the activation path — where two holes let a stale-but-resolvable
// conversation.selectedMessage (the previously opened card) win silently:
//
//   1. willBecomeActive unconditionally cleared the remembered tap. iOS does not
//      guarantee didSelect-vs-willBecomeActive ordering on a launch-by-bubble-tap; when
//      didSelect fires first, the clear discarded the user's tap and the render fell
//      through to selectedMessage — documented stale on warm state, still pointing at
//      the card that was open BEFORE the new message existed.
//   2. When no didSelect fires at all for the launching tap, the activation render
//      trusted selectedMessage once and never looked again. A momentarily stale
//      selection rendered the old card and nothing ever corrected it — silently,
//      because every individual decision (fresh activation + resolvable selection)
//      looked legitimate, so no failure view and no suspicious log line was produced.
//
// Neither hole was reachable from the simulator verification: cards inserted via
// conversation.insert() are cached at compose time by the same running instance, and the
// tested taps all delivered didSelect while the extension was already active.
//
// Rules encoded here:
//   - A tap remembered from THIS activation burst survives willBecomeActive. Only
//     willResignActive clears it (a stale tap from a previous activation therefore
//     cannot leak in — it was cleared when that activation ended).
//   - Any render decided WITHOUT an explicit user tap is provisional: the caller must
//     re-read the live conversation.selectedMessage shortly after and feed it back via
//     selectionRecheck. If the selection turns out to identify a DIFFERENT session than
//     what was rendered, it is re-resolved (through the same never-substitute resolver).
//   - selectionRecheck never overrides an explicit tap in favor of a PREVIOUSLY OPENED
//     card, and is a no-op while the selection still matches what is on screen.
//   - Round 7 (the warm second-card gap): a remembered tap must NOT outrank a selection
//     identifying a session whose message ARRIVED (didReceive) during this activation.
//     The extension never resigns between "user interacts with card A" and "card B
//     arrives and is tapped", so A's tap was outranking B's live selection forever when
//     B's tap wasn't delivered as a clean didSelect (only a didTransition, or a dropped/
//     late didSelect — the documented iOS 26 delivery flakiness class). The stale-
//     selection pathology that justifies tap-priority is always the selection LAGGING
//     toward an older, previously-opened card; a selection pointing at a message that
//     did not exist when the tap happened provably isn't that, so it wins — and the
//     stale tap is dropped, re-arming the provisional/recheck machinery.

import Foundation

public final class HermesEventRouter {

    public struct Decision {
        /// What to render now; nil means leave whatever is on screen untouched.
        public let resolution: HermesCardResolution?
        /// True when this render was decided without an explicit user tap — the live
        /// selection may be stale, so the caller must schedule selectionRecheck calls.
        public let selectionProvisional: Bool
    }

    private let resolver: HermesCardResolver

    /// Snapshot of the message the user explicitly tapped (didSelect) in this
    /// activation burst. Exposed for the controller's forensic logging.
    public private(set) var tappedThisActivation: HermesMessageSnapshot?

    /// Session key of the content currently on screen (a layout OR the failure view
    /// for that session; nil after rendering the compose/empty state).
    public private(set) var renderedSessionKey: String?

    /// Session keys of messages that ARRIVED (didReceive) during this activation. A live
    /// selection identifying one of these outranks a remembered tap of a DIFFERENT
    /// session: the message didn't exist when that tap happened, so the selection cannot
    /// be the stale previously-opened-card lag that tap-priority protects against.
    /// Cleared only on willResignActive, like the tap itself.
    public private(set) var sessionsReceivedThisActivation: Set<String> = []

    public init(resolver: HermesCardResolver) {
        self.resolver = resolver
    }

    // MARK: - Lifecycle events

    /// Deliberately does NOT clear `tappedThisActivation` (hole 1 above): a didSelect
    /// delivered just before willBecomeActive in the same launch burst is the user's
    /// actual tap and must keep outranking the possibly-stale selection.
    public func willBecomeActive(selected: HermesMessageSnapshot?) -> Decision {
        route(selected: selected)
    }

    public func didSelect(tapped: HermesMessageSnapshot, selected: HermesMessageSnapshot?) -> Decision {
        tappedThisActivation = tapped
        // A didSelect is the user's explicit tap, delivered right now — it can never be
        // dethroned by the selection in its own routing pass.
        return route(selected: selected, canDethroneTap: false)
    }

    public func didTransition(selected: HermesMessageSnapshot?) -> Decision {
        route(selected: selected)
    }

    public func willResignActive() {
        tappedThisActivation = nil
        renderedSessionKey = nil
        sessionsReceivedThisActivation = []
    }

    /// A message arrived (didReceive) while the extension is running. Not a render
    /// trigger by itself — it records that any later selection of this session is
    /// provably NEWER than the currently remembered tap (see route()).
    public func didReceive(sessionKey: String?) {
        guard let sessionKey else { return }
        sessionsReceivedThisActivation.insert(sessionKey)
    }

    // MARK: - Corrections

    /// Delayed re-read of the live `conversation.selectedMessage` after a provisional
    /// render (hole 2 above). Acts when the selection identifies a DIFFERENT session
    /// than what was rendered AND either no tap is remembered (the cold-launch case) or
    /// the selection points at a session that ARRIVED after the remembered tap (the warm
    /// second-card case — a stale tap must not pin the screen against a newer message).
    /// The re-resolution goes through the same resolver, so an unresolvable late
    /// selection still produces .unresolved (an honest failure view), never a
    /// substituted card.
    public func selectionRecheck(selected: HermesMessageSnapshot?) -> Decision {
        let noOp = Decision(resolution: nil, selectionProvisional: false)
        guard let selected,
              let key = selected.sessionKey,
              key != renderedSessionKey
        else { return noOp }
        if let tapped = tappedThisActivation {
            guard key != tapped.sessionKey,
                  sessionsReceivedThisActivation.contains(key)
            else { return noOp }
        }
        return route(selected: selected)
    }

    /// Unresolved-retry re-resolution with freshly recomputed snapshots (Messages can
    /// materialize a URL late). A non-nil `tapped` refreshes the remembered tap in
    /// place — it is the SAME message, re-snapshotted.
    public func retry(tapped: HermesMessageSnapshot?, selected: HermesMessageSnapshot?) -> Decision {
        if let tapped { tappedThisActivation = tapped }
        return route(selected: selected)
    }

    // MARK: - Core

    private func route(selected: HermesMessageSnapshot?, canDethroneTap: Bool = true) -> Decision {
        // The warm second-card rule: a selection identifying a session that ARRIVED
        // during this activation is provably newer than a remembered tap of a different
        // session (the message didn't exist when that tap happened), so the tap is stale
        // — drop it and let the selection resolve. Never applies inside didSelect's own
        // routing pass, and the resolution still goes through the never-substitute
        // resolver (an unresolvable new arrival yields the failure view, not a repaint).
        if canDethroneTap,
           let tapped = tappedThisActivation,
           let selectedKey = selected?.sessionKey,
           selectedKey != tapped.sessionKey,
           sessionsReceivedThisActivation.contains(selectedKey) {
            tappedThisActivation = nil
        }
        let resolution = resolver.resolve(tapped: tappedThisActivation, selected: selected)
        switch resolution {
        case .layout(_, let sessionKey, _):
            renderedSessionKey = sessionKey
        case .unresolved(let diagnostics):
            renderedSessionKey = diagnostics.sessionKey
        case .compose:
            renderedSessionKey = nil
        }
        // Provisional also when messages have arrived this activation: even a tap-decided
        // render must arm rechecks then, because the user's NEXT tap (on the new arrival)
        // may reach us only as a selection change with no didSelect at all.
        return Decision(resolution: resolution,
                        selectionProvisional: tappedThisActivation == nil
                            || !sessionsReceivedThisActivation.isEmpty)
    }
}
