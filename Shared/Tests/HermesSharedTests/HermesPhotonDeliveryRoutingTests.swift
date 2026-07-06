// HermesPhotonDeliveryRoutingTests.swift
// Reproduces the PHOTON DELIVERY GAP: a brand-new card delivered externally via Photon
// (customizedMiniApp → https://…?p=… URL) while the extension is NOT running is never
// cached by didReceive (didReceive fires zero times for messages arriving while the
// extension is inactive — a previously-diagnosed, real behavior). Its FIRST-EVER tap
// therefore reaches the extension through the ACTIVATION path — willBecomeActive /
// didSelect in unguaranteed order, with conversation.selectedMessage possibly still
// pointing at whatever card was open BEFORE this message existed.
//
// The earlier simulator verification never exercised this: simulator-inserted cards are
// composed by the same running instance (cached at compose time) and every tested tap
// delivered didSelect while the extension was already active. These tests drive
// HermesEventRouter — the extracted event-sequence state machine the view controller now
// delegates to — through the exact cold-first-tap-of-a-fresh-Photon-message sequences,
// with OTHER, perfectly renderable cards already in the cache from prior activity
// (maximum substitution temptation).

import XCTest
import HermesShared

final class HermesPhotonDeliveryRoutingTests: XCTestCase {

    private var store: HermesLayoutStore!
    private var router: HermesEventRouter!
    private let suiteName = "hermes-photon-delivery-routing-tests"

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

    // MARK: Fixtures — the user's exact scenario

    /// The fresh Photon-delivered card the user reported broken: a new flightBoard,
    /// "Cutting It Close", HND → LAX. NEVER pre-cached in any of these tests — exactly
    /// like a real Photon send while the extension wasn't running.
    private var freshFlightCard: HermesLayout {
        HermesLayout(
            title: "Cutting It Close", subtitle: "HND → LAX", accentColorHex: "#0A84FF",
            root: .flightBoard(HermesFlightBoard(
                origin: "HND", destination: "LAX", originCity: "Tokyo",
                destinationCity: "Los Angeles", flightCode: "NH 106",
                departTime: "16:50", arriveTime: "10:35", gate: "114",
                status: "Boarding", statusColorHex: "#FF9F0A", progress: nil
            ))
        )
    }

    /// An older card that was open before the fresh one arrived (the substitution target).
    private var oldSeatCard: HermesLayout {
        HermesLayout(
            title: "Pick Your Seat", subtitle: "BR 26 · TPE → SFO", accentColorHex: "#00875A",
            root: .seatChart(rows: [
                HermesSeatRow(rowNumber: 21, seats: [
                    HermesSeat(id: "21A", letter: "A", state: .taken),
                    HermesSeat(id: "21B", letter: "B", state: .available)
                ])
            ], selectedSeatId: nil)
        )
    }

    private var oldDinnerCard: HermesLayout {
        HermesLayout(
            title: "Dinner Vote", subtitle: "Tonight", accentColorHex: "#FF375F",
            root: .text("Ramen vs sushi", style: .init(role: .headline))
        )
    }

    private let keyOld = HermesLayoutStore.sessionKey(
        fromSessionDescription: "<MSSession 0x1> - 505B1814-EF2E-47B4-8514-20061D078043")!
    private let keyDinner = HermesLayoutStore.sessionKey(
        fromSessionDescription: "<MSSession 0x2> - 2B06556A-A00F-43EF-991D-6FE736B4E723")!
    private let keyFresh = HermesLayoutStore.sessionKey(
        fromSessionDescription: "<MSSession 0x3> - 8CFBF009-7BE1-4AE4-9F52-FC394479E458")!

    private func snapshot(_ layout: HermesLayout?, key: String?) -> HermesMessageSnapshot {
        HermesMessageSnapshot(sessionKey: key, layout: layout)
    }

    /// Prior activity: other, different cards already cached/visible from earlier sessions.
    private func seedPriorActivity() {
        store.store(layout: oldSeatCard, key: keyOld)
        store.store(layout: oldDinnerCard, key: keyDinner)
    }

    private func assertRenders(_ decision: HermesEventRouter.Decision,
                               title: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .layout(let layout, _, _)? = decision.resolution else {
            return XCTFail("expected a layout render, got \(String(describing: decision.resolution))",
                           file: file, line: line)
        }
        XCTAssertEqual(layout.title, title, file: file, line: line)
    }

    // MARK: The Photon wire shape itself (https://…?p=…, exactly what send_card_photon.mjs builds)

    /// End-to-end wire coverage the old tests lacked: they round-tripped
    /// base64URLPayload directly, never the FULL Photon URL shape (https host, extra
    /// query params, payload in the query string). This builds the URL byte-for-byte the
    /// way send_card_photon.mjs does and decodes it the way the extension does.
    func testPhotonHTTPSURLShapeDecodes() throws {
        let payload = try freshFlightCard.base64URLPayload()

        // Exactly the sender's construction: hostArg + (contains "?" ? "&" : "?") + "p=" + payload
        let plain = URL(string: "https://example.trycloudflare.com/card?p=\(payload)")!
        XCTAssertEqual(HermesLayout.decode(fromMessageURL: plain), freshFlightCard)

        // Host arg that already carries query params (the sender appends with "&"),
        // plus params AFTER ours — the decoder must find `p` positionally anywhere.
        let extras = URL(string: "https://h.example.com/x.json?v=2&p=\(payload)&utm_source=photon")!
        XCTAssertEqual(HermesLayout.decode(fromMessageURL: extras), freshFlightCard)

        // Our own scheme and Linq's data: shape still decode.
        let custom = URL(string: "hermesshare://card?p=\(payload)")!
        XCTAssertEqual(HermesLayout.decode(fromMessageURL: custom), freshFlightCard)
        let std = try freshFlightCard.encoded().base64EncodedString()
        let dataURL = URL(string: "data:application/json;base64,\(std)")!
        XCTAssertEqual(HermesLayout.decode(fromMessageURL: dataURL), freshFlightCard)

        // A URL with no payload must decode to nothing (never garbage).
        XCTAssertNil(HermesLayout.decode(fromMessageURL: URL(string: "https://example.com/card")!))
        XCTAssertNil(HermesLayout.decode(fromMessageURL: URL(string: "https://example.com/card?p=")!))
    }

    // MARK: Cold first tap — didSelect BEFORE willBecomeActive (hole 1: the discarded tap)

    /// iOS does not guarantee didSelect-vs-willBecomeActive ordering on a launch-by-
    /// bubble-tap. Old behavior: willBecomeActive unconditionally cleared the remembered
    /// tap, then rendered from the stale selection (the old card, fully resolvable) —
    /// silent substitution, no failure view, no suspicious log line. The user's exact
    /// report for the Photon-delivered "Cutting It Close" card.
    func testDidSelectBeforeWillBecomeActiveSurvivesStaleSelection() throws {
        seedPriorActivity()

        // First-ever tap of the fresh message: URL present (Photon https shape), never cached.
        let tap = router.didSelect(tapped: snapshot(freshFlightCard, key: keyFresh),
                                   selected: snapshot(oldSeatCard, key: keyOld))
        assertRenders(tap, title: "Cutting It Close")

        // willBecomeActive lands AFTER the tap, selection still stale on the old card.
        // The tap must keep winning (old code rendered "Pick Your Seat" here).
        let activate = router.willBecomeActive(selected: snapshot(oldSeatCard, key: keyOld))
        assertRenders(activate, title: "Cutting It Close")

        // The didTransition(.expanded) that follows must also keep the tapped card.
        let transition = router.didTransition(selected: snapshot(oldSeatCard, key: keyOld))
        assertRenders(transition, title: "Cutting It Close")

        // And the fresh card is now cached under ITS OWN key for future warm nil-url taps.
        XCTAssertEqual(store.layout(forKey: keyFresh)?.title, "Cutting It Close")
        XCTAssertEqual(store.layout(forKey: keyOld)?.title, "Pick Your Seat",
                       "the old card's cache entry must be untouched")
    }

    // MARK: Cold first tap — no didSelect at all (hole 2: the never-corrected stale selection)

    /// When only willBecomeActive fires for the launching tap and its selectedMessage is
    /// momentarily stale, the old card renders (that decision alone is legitimate — a
    /// fresh activation with a resolvable selection is indistinguishable from the user
    /// re-opening the old card). The fix: that render is PROVISIONAL, and the live
    /// selection is re-checked; when it moves to the fresh message, the fresh card's own
    /// URL must render — never stick on the old card.
    func testStaleSelectionAtActivationIsCorrectedByRecheck() throws {
        seedPriorActivity()

        // Activation with the stale selection: renders the old card, but flagged provisional.
        let activate = router.willBecomeActive(selected: snapshot(oldSeatCard, key: keyOld))
        assertRenders(activate, title: "Pick Your Seat")
        XCTAssertTrue(activate.selectionProvisional,
                      "a render decided without a user tap must be marked provisional so the live selection gets re-checked")

        // Recheck while the selection hasn't moved: leave the screen alone.
        let unchanged = router.selectionRecheck(selected: snapshot(oldSeatCard, key: keyOld))
        XCTAssertNil(unchanged.resolution)

        // Messages updates selectedMessage to the fresh Photon message (its https URL
        // present, still nothing cached for it): must render ITS OWN content.
        let corrected = router.selectionRecheck(selected: snapshot(freshFlightCard, key: keyFresh))
        assertRenders(corrected, title: "Cutting It Close")
        XCTAssertEqual(store.layout(forKey: keyFresh)?.title, "Cutting It Close",
                       "the corrected render must cache the fresh card under its own session")
    }

    /// Same as above but the activation selection is nil (also observed: selectedMessage
    /// can materialize late). The compose/empty render must be corrected too.
    func testNilSelectionAtActivationIsCorrectedByRecheck() throws {
        seedPriorActivity()

        let activate = router.willBecomeActive(selected: nil)
        guard case .compose? = activate.resolution else {
            return XCTFail("no message at all resolves to compose/empty, got \(String(describing: activate.resolution))")
        }
        XCTAssertTrue(activate.selectionProvisional)

        let corrected = router.selectionRecheck(selected: snapshot(freshFlightCard, key: keyFresh))
        assertRenders(corrected, title: "Cutting It Close")
    }

    // MARK: Never-substitute invariants for the new paths

    /// The recheck path must obey the same doctrine as every other path: if the late
    /// selection is the fresh message but its URL is nil and nothing is cached for it,
    /// the answer is .unresolved for THAT session — never the old card that's on screen.
    func testRecheckNeverSubstitutesWhenLateSelectionIsUnresolvable() throws {
        seedPriorActivity()
        _ = router.willBecomeActive(selected: snapshot(oldSeatCard, key: keyOld))

        let late = router.selectionRecheck(selected: snapshot(nil, key: keyFresh))
        guard case .unresolved(let diagnostics)? = late.resolution else {
            return XCTFail("unresolvable late selection must fail honestly, got \(String(describing: late.resolution))")
        }
        XCTAssertEqual(diagnostics.sessionKey, keyFresh,
                       "the failure must be attributed to the fresh message, not the rendered one")
    }

    /// An explicit tap always outranks the recheck loop: once the user has tapped a card
    /// in this activation, a straggling recheck (from a timer armed earlier) must never
    /// repaint from the conversation's selection.
    func testRecheckNeverOverridesAnExplicitTap() throws {
        seedPriorActivity()
        _ = router.willBecomeActive(selected: snapshot(oldSeatCard, key: keyOld))
        _ = router.didSelect(tapped: snapshot(freshFlightCard, key: keyFresh),
                             selected: snapshot(oldSeatCard, key: keyOld))

        let straggler = router.selectionRecheck(selected: snapshot(oldDinnerCard, key: keyDinner))
        XCTAssertNil(straggler.resolution, "a recheck must never override an explicit tap")
    }

    /// Taps must not leak ACROSS activations: hole 1's fix keeps the tap through
    /// willBecomeActive, so prove the willResignActive clear still isolates activations.
    func testResignClearsTheTapSoNextActivationTrustsItsSelection() throws {
        seedPriorActivity()
        _ = router.didSelect(tapped: snapshot(freshFlightCard, key: keyFresh),
                             selected: snapshot(oldSeatCard, key: keyOld))
        router.willResignActive()

        // Next activation: the user genuinely opened the old card. Its selection must win
        // now — the previous activation's tap is gone.
        let reopened = router.willBecomeActive(selected: snapshot(oldSeatCard, key: keyOld))
        assertRenders(reopened, title: "Pick Your Seat")
    }

    // MARK: The user's full reported sequence, end to end

    /// Multiple different cards exist from prior sessions; the new "Cutting It Close"
    /// flightBoard arrives via Photon while the extension is not running (didReceive never
    /// fires → nothing cached for it); the user taps it for the FIRST time. Both plausible
    /// on-device event orderings must land on the fresh card's own content.
    func testUserReportedSequenceEndToEnd() throws {
        seedPriorActivity()

        // Wire trip: the layout arrives only as Photon's https URL, decoded on tap.
        let payload = try freshFlightCard.base64URLPayload()
        let wireURL = URL(string: "https://abc.trycloudflare.com/card.json?p=\(payload)")!
        let decodedFromWire = HermesLayout.decode(fromMessageURL: wireURL)
        XCTAssertEqual(decodedFromWire, freshFlightCard)

        // Ordering A: willBecomeActive(stale) → didSelect(fresh) → didTransition(stale).
        let a1 = router.willBecomeActive(selected: snapshot(oldDinnerCard, key: keyDinner))
        assertRenders(a1, title: "Dinner Vote") // provisional, would be corrected
        let a2 = router.didSelect(tapped: snapshot(decodedFromWire, key: keyFresh),
                                  selected: snapshot(oldDinnerCard, key: keyDinner))
        assertRenders(a2, title: "Cutting It Close")
        let a3 = router.didTransition(selected: snapshot(oldDinnerCard, key: keyDinner))
        assertRenders(a3, title: "Cutting It Close")

        router.willResignActive()

        // Ordering B: didSelect(fresh) → willBecomeActive(stale) → didTransition(stale).
        let b1 = router.didSelect(tapped: snapshot(decodedFromWire, key: keyFresh),
                                  selected: snapshot(oldSeatCard, key: keyOld))
        assertRenders(b1, title: "Cutting It Close")
        let b2 = router.willBecomeActive(selected: snapshot(oldSeatCard, key: keyOld))
        assertRenders(b2, title: "Cutting It Close")
        let b3 = router.didTransition(selected: snapshot(oldSeatCard, key: keyOld))
        assertRenders(b3, title: "Cutting It Close")

        // After all of it: every card still resolves to its OWN content.
        XCTAssertEqual(store.layout(forKey: keyFresh)?.title, "Cutting It Close")
        XCTAssertEqual(store.layout(forKey: keyOld)?.title, "Pick Your Seat")
        XCTAssertEqual(store.layout(forKey: keyDinner)?.title, "Dinner Vote")
    }
}
