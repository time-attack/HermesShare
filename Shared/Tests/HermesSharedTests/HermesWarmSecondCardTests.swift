// HermesWarmSecondCardTests.swift
// Round 7: the WARM SECOND-CARD gap. The user's exact reported sequence: a seatChart card
// (EVA 777) was open and interacted with (its action tapped, a reply sent), then a second,
// different card (UA1 flightBoard) arrived moments later and was tapped — and the FIRST
// card's content showed instead of the second's, with no failure view.
//
// Why every prior test missed this: they covered "warm re-tap of an old card" (didSelect
// delivered, stale selection must lose to the tap) and "cold first tap of a fresh Photon
// card" (no tap remembered, provisional render + selection recheck). Neither covered a
// LONG-LIVED WARM ACTIVATION: the extension never resigns between interacting with card A
// and tapping card B, so `tappedThisActivation` still holds card A's tap from minutes ago.
// If card B's tap reaches the extension as anything other than a clean didSelect(B) — only
// a didTransition(.expanded), or a didSelect dropped/delivered late (the same iOS 26
// delivery flakiness this project has already documented for nil-url didSelects and
// unguaranteed didSelect/willBecomeActive ordering) — the stale remembered tap outranked
// the live selection forever: `selectionProvisional` was false while a tap was remembered,
// so no rechecks were armed, and selectionRecheck hard-guarded on "no tap". Card A stuck.
//
// The disambiguating signal that makes a fix safe: the stale-selection pathology (the whole
// reason taps outrank selections) is always the selection LAGGING toward an older,
// previously-opened card. A selection identifying a session whose message ARRIVED via
// didReceive during this activation provably isn't that — the message didn't even exist
// when the remembered tap happened. The router now tracks received sessions per activation
// and lets such a selection outrank (and invalidate) the remembered tap.

import XCTest
import HermesShared

final class HermesWarmSecondCardTests: XCTestCase {

    private var store: HermesLayoutStore!
    private var router: HermesEventRouter!
    private let suiteName = "hermes-warm-second-card-tests"

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: suiteName)!
        store = HermesLayoutStore(defaults: defaults)
        store.removeAll()
        router = HermesEventRouter(resolver: HermesCardResolver(store: store))
    }

    override func tearDown() {
        store.removeAll()
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: Fixtures — the user's exact two cards from the round-7 report

    /// Card A: the EVA Air 777 seat chart the user interacted with successfully.
    private var evaSeatCard: HermesLayout {
        HermesLayout(
            title: "EVA Air 777", subtitle: "BR 26 · Pick Your Seat", accentColorHex: "#00875A",
            root: .seatChart(rows: [
                HermesSeatRow(rowNumber: 39, seats: [
                    HermesSeat(id: "39A", letter: "A", state: .available),
                    HermesSeat(id: "39B", letter: "B", state: .taken)
                ])
            ], selectedSeatId: nil)
        )
    }

    /// Card B: the EXACT UA1 flightBoard JSON from the user's failing send (already proven
    /// to decode and render fine in isolation by HermesUA1DiagnosticTests).
    private var ua1FlightCard: HermesLayout {
        let json = """
        {"version":1,"title":"United 1","subtitle":"JFK \\u2192 SFO \\u00b7 Today","accentColorHex":"#0A84FF","background":{"kind":"plain"},"root":{"type":"flightBoard","board":{"origin":"JFK","destination":"SFO","originCity":"New York","destinationCity":"San Francisco","flightCode":"UA 1","departTime":"08:00","arriveTime":"11:32","gate":"B22","status":"In Flight","statusColorHex":"#0A84FF","progress":0.58}}}
        """
        return try! HermesLayout.decode(from: json.data(using: .utf8)!)
    }

    private let keyEVA = HermesLayoutStore.sessionKey(
        fromSessionDescription: "<MSSession 0x1> - 1D1D3FAE-7B60-4E11-9AF7-9E9C4E62B7D1")!
    private let keyUA1 = HermesLayoutStore.sessionKey(
        fromSessionDescription: "<MSSession 0x2> - 6C0A2E17-53D0-49B6-8B4B-3C7E1A9B4F02")!

    private func snapshot(_ layout: HermesLayout?, key: String?) -> HermesMessageSnapshot {
        HermesMessageSnapshot(sessionKey: key, layout: layout)
    }

    private func assertRenders(_ decision: HermesEventRouter.Decision,
                               title: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .layout(let layout, _, _)? = decision.resolution else {
            return XCTFail("expected a layout render, got \(String(describing: decision.resolution))",
                           file: file, line: line)
        }
        XCTAssertEqual(layout.title, title, file: file, line: line)
    }

    /// Puts the router in the user's exact pre-failure state: extension active, EVA card
    /// tapped open (didSelect delivered normally) and rendered — the activation is WARM
    /// and `tappedThisActivation` holds the EVA tap. The action-tap/reply itself is not a
    /// router event; what matters is that no willResignActive ever happens.
    private func openAndInteractWithEVA() {
        _ = router.willBecomeActive(selected: nil)
        let tap = router.didSelect(tapped: snapshot(evaSeatCard, key: keyEVA),
                                   selected: snapshot(evaSeatCard, key: keyEVA))
        assertRenders(tap, title: "EVA Air 777")
        let transition = router.didTransition(selected: snapshot(evaSeatCard, key: keyEVA))
        assertRenders(transition, title: "EVA Air 777")
    }

    // MARK: The gap itself

    /// UA1 arrives while the extension is warm (didReceive caches it and notifies the
    /// router), then the user's tap on it manifests ONLY as a didTransition whose live
    /// selection already points at UA1. The stale EVA tap must NOT outrank a selection
    /// identifying a message that arrived AFTER that tap.
    func testSecondCardTapArrivingOnlyAsTransitionRendersSecondCard() throws {
        openAndInteractWithEVA()

        // UA1 arrives: exactly what MessagesViewController.didReceive now does.
        store.store(layout: ua1FlightCard, key: keyUA1)
        router.didReceive(sessionKey: keyUA1)

        // The tap reaches us only as a transition; selection is already correct.
        let transition = router.didTransition(selected: snapshot(ua1FlightCard, key: keyUA1))
        assertRenders(transition, title: "United 1")

        // And the warm nil-url variant of the same thing (url stripped, cache must serve).
        let nilURL = router.didTransition(selected: snapshot(nil, key: keyUA1))
        assertRenders(nilURL, title: "United 1")
    }

    /// Same arrival, but the transition's selection is still LAGGING on the EVA card
    /// (selection updates late — the documented behavior that motivated tap-priority in
    /// the first place). Rendering EVA at that instant is legitimate; what's mandatory is
    /// that the render is PROVISIONAL (rechecks armed) and that a recheck seeing the
    /// selection move to the freshly-arrived UA1 session re-routes to UA1 — even though a
    /// tap is still remembered.
    func testSecondCardTapWithLaggingSelectionIsCorrectedByRecheck() throws {
        openAndInteractWithEVA()
        store.store(layout: ua1FlightCard, key: keyUA1)
        router.didReceive(sessionKey: keyUA1)

        let transition = router.didTransition(selected: snapshot(evaSeatCard, key: keyEVA))
        assertRenders(transition, title: "EVA Air 777")
        XCTAssertTrue(transition.selectionProvisional,
                      "with a newer message received this activation, a tap-decided render must arm selection rechecks")

        // Recheck while the selection hasn't moved: leave the screen alone.
        XCTAssertNil(router.selectionRecheck(selected: snapshot(evaSeatCard, key: keyEVA)).resolution)

        // Selection catches up to the freshly-arrived UA1: must re-route to UA1.
        let corrected = router.selectionRecheck(selected: snapshot(ua1FlightCard, key: keyUA1))
        assertRenders(corrected, title: "United 1")
    }

    /// Doctrine: if the freshly-arrived selection can't be resolved (nil url, nothing
    /// cached), the answer is .unresolved for UA1's session — never the EVA card that's
    /// on screen.
    func testUnresolvablePostArrivalSelectionFailsHonestlyNotWithOldCard() throws {
        openAndInteractWithEVA()
        router.didReceive(sessionKey: keyUA1) // arrival noted but nothing cached, no url

        let transition = router.didTransition(selected: snapshot(nil, key: keyUA1))
        guard case .unresolved(let diagnostics)? = transition.resolution else {
            return XCTFail("unresolvable post-arrival selection must fail honestly, got \(String(describing: transition.resolution))")
        }
        XCTAssertEqual(diagnostics.sessionKey, keyUA1,
                       "the failure must be attributed to UA1, not silently repaint the EVA card")
    }

    // MARK: Regression guards — the original tap-priority fixes must survive

    /// The warm re-tap bug (rounds 1–2): a didSelect'd tap must still beat a stale
    /// selection pointing at a PREVIOUSLY OPENED card — that session did not arrive this
    /// activation, so tap priority is untouched.
    func testStaleSelectionOfPreviouslyOpenedCardStillLosesToTap() throws {
        openAndInteractWithEVA()
        store.store(layout: ua1FlightCard, key: keyUA1)
        router.didReceive(sessionKey: keyUA1)

        // didSelect DOES fire for UA1 this time; the transition's selection lags on EVA.
        let tap = router.didSelect(tapped: snapshot(ua1FlightCard, key: keyUA1),
                                   selected: snapshot(evaSeatCard, key: keyEVA))
        assertRenders(tap, title: "United 1")
        let transition = router.didTransition(selected: snapshot(evaSeatCard, key: keyEVA))
        assertRenders(transition, title: "United 1")

        // A straggling recheck seeing the stale EVA selection must not repaint either:
        // EVA did not arrive this activation, so the remembered UA1 tap keeps winning.
        XCTAssertNil(router.selectionRecheck(selected: snapshot(evaSeatCard, key: keyEVA)).resolution)
    }

    /// A remote update to the SAME card the user is looking at (didReceive for the tapped
    /// session) must not dethrone the tap or repaint anything.
    func testSameSessionArrivalDoesNotDropTheTap() throws {
        openAndInteractWithEVA()
        router.didReceive(sessionKey: keyEVA) // e.g. the reply bubble updating in place

        let transition = router.didTransition(selected: snapshot(evaSeatCard, key: keyEVA))
        assertRenders(transition, title: "EVA Air 777")
        XCTAssertNil(router.selectionRecheck(selected: snapshot(evaSeatCard, key: keyEVA)).resolution)
    }

    /// Arrivals must not leak across activations: after resign + fresh activation, the
    /// cold-launch rules (provisional render from selection, recheck corrections) apply
    /// unchanged.
    func testResignClearsArrivalTracking() throws {
        openAndInteractWithEVA()
        store.store(layout: ua1FlightCard, key: keyUA1)
        router.didReceive(sessionKey: keyUA1)
        router.willResignActive()

        let activate = router.willBecomeActive(selected: snapshot(evaSeatCard, key: keyEVA))
        assertRenders(activate, title: "EVA Air 777")
        XCTAssertTrue(activate.selectionProvisional)
    }

    // MARK: The user's full reported sequence, end to end

    /// EVA seatChart opened and interacted with (reply composed on its session — which,
    /// per makeMessage, overwrites its cache entry with the reply layout, exactly as on
    /// device), THEN UA1 arrives and is tapped moments later. Every plausible delivery
    /// shape of that second tap must land on UA1's own content.
    func testUserReportedSequenceEndToEnd() throws {
        openAndInteractWithEVA()

        // The action tap: a reply layout is composed on EVA's session and cached over it
        // (makeMessage's compose-time caching), extension collapses to compact — no resign.
        let reply = HermesLayout(title: "✓ Confirm Seat", subtitle: "EVA Air 777",
                                 root: .text("Tapped from EVA Air 777", style: .init(role: .footnote)))
        store.store(layout: reply, key: keyEVA)
        _ = router.didTransition(selected: snapshot(evaSeatCard, key: keyEVA)) // compact transition

        // Moments later: UA1 arrives via Photon while the extension is still warm.
        store.store(layout: ua1FlightCard, key: keyUA1)
        router.didReceive(sessionKey: keyUA1)

        // Shape 1: clean didSelect (the always-worked path).
        let tap = router.didSelect(tapped: snapshot(ua1FlightCard, key: keyUA1),
                                   selected: snapshot(evaSeatCard, key: keyEVA))
        assertRenders(tap, title: "United 1")
        assertRenders(router.didTransition(selected: snapshot(evaSeatCard, key: keyEVA)),
                      title: "United 1")

        router.willResignActive()

        // Shape 2 (the bug): warm activation again, EVA re-opened and interacted with,
        // then a SECOND new arrival tapped with NO didSelect at all.
        _ = router.willBecomeActive(selected: snapshot(nil, key: keyEVA)) // warm nil-url, cache serves reply
        _ = router.didSelect(tapped: snapshot(nil, key: keyEVA),
                             selected: snapshot(nil, key: keyEVA))
        let keyUA1b = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x9> - 0F9D64C1-8A2E-4B77-9D30-5E2C81B6A913")!
        store.store(layout: ua1FlightCard, key: keyUA1b)
        router.didReceive(sessionKey: keyUA1b)

        assertRenders(router.didTransition(selected: snapshot(nil, key: keyUA1b)),
                      title: "United 1")
    }
}
