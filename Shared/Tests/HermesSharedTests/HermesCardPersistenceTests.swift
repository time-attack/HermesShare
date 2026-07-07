// HermesCardPersistenceTests.swift
// Reproduces the multi-card navigation/persistence bug at the layer where it actually lived:
// per-session layout caching + resolution. The user-reported sequence was: open card A (seat
// select) → tap card B (system health) → B showed A's content; and after replying, every
// subsequent tap kept routing to A. Root causes: (1) warm taps deliver url=nil so rendering
// depends on the session cache, (2) a global "latest cached layout" fallback silently
// substituted the most recently cached card whenever a per-session lookup missed.
//
// These tests drive the shared HermesLayoutStore exactly the way MessagesViewController does
// (store on decode/compose keyed by session UUID, look up by session UUID on nil-url taps)
// and assert every step resolves to that card's OWN content — plus renders each resolved
// layout through the real render harness to prove the right content actually draws.

import XCTest
import SwiftUI
import UIKit
import HermesShared

@MainActor
final class HermesCardPersistenceTests: XCTestCase {

    private var store: HermesLayoutStore!
    private let suiteName = "hermes-card-persistence-tests"

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: suiteName)!
        store = HermesLayoutStore(defaults: defaults)
        store.removeAll()
    }

    override func tearDown() {
        store.removeAll()
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: Fixtures — two deliberately different card types (per the bug report)

    private var seatSelectCard: HermesLayout {
        HermesLayout(
            title: "Pick Your Seat", subtitle: "BR 26 · TPE → SFO", accentColorHex: "#00875A",
            root: .seatChart(rows: [
                HermesSeatRow(rowNumber: 21, seats: [
                    HermesSeat(id: "21A", letter: "A", state: .taken),
                    HermesSeat(id: "21B", letter: "B", state: .available),
                    HermesSeat(id: "21C", letter: "C", state: .available)
                ])
            ], selectedSeatId: nil),
            actions: [HermesAction(id: "confirm-seat", label: "Confirm Seat",
                                   deepLinkURL: "hermesshare://action?id=confirm-seat")]
        )
    }

    private var systemHealthCard: HermesLayout {
        HermesLayout(
            title: "System Health", subtitle: "All services", accentColorHex: "#FF9500",
            root: .vstack(spacing: 10, alignment: "leading", children: [
                .stat(value: "99.98%", label: "Uptime", iconSystemName: "waveform.path.ecg", colorHex: "#34C759"),
                .keyValueRow(key: "API latency", value: "212 ms"),
                .keyValueRow(key: "Error rate", value: "0.02%")
            ])
        )
    }

    /// Simulates what Messages transport does to a layout (URL round-trip) and what
    /// MessagesViewController does on a successful decode (store keyed by session).
    private func openWithURL(_ layout: HermesLayout, sessionKey: String) throws -> HermesLayout {
        let decoded = try HermesLayout.decode(base64URLPayload: layout.base64URLPayload())
        store.store(layout: decoded, key: sessionKey)
        return decoded
    }

    /// Simulates a warm tap where Messages delivers url=nil: the only recovery path is the
    /// per-session cache. Returns whatever the cache resolves — the assertion target.
    private func warmTap(sessionKey: String) -> HermesLayout? {
        store.layout(forKey: sessionKey)
    }

    // MARK: Session-key derivation (the exact on-device MSSession description format)

    func testSessionKeyParsesRealMSSessionDescription() {
        // Verbatim shape from the on-device debug log.
        let desc = "<MSSession 0x1060d6130> - F2EB150E-F3CF-4374-A277-8DCCAC878973"
        let key = HermesLayoutStore.sessionKey(fromSessionDescription: desc)
        XCTAssertNotNil(key)
        XCTAssertTrue(key!.contains("F2EB150E-F3CF-4374-A277-8DCCAC878973"))

        // Same session UUID delivered through a different MSSession instance (different
        // address) must produce the SAME key — this is what warm re-taps rely on.
        let rehydrated = "<MSSession 0x105cdaa90> - f2eb150e-f3cf-4374-a277-8dccac878973"
        XCTAssertEqual(key, HermesLayoutStore.sessionKey(fromSessionDescription: rehydrated))

        // Unparseable description → nil, never a colliding/garbage key.
        XCTAssertNil(HermesLayoutStore.sessionKey(fromSessionDescription: "<MSSession 0x1060d6130>"))
    }

    // MARK: The exact user-reported sequence

    func testMultiCardTapSequenceResolvesEachCardsOwnContent() throws {
        let keyA = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x1> - 505B1814-EF2E-47B4-8514-20061D078043")!
        let keyB = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x2> - 2B06556A-A00F-43EF-991D-6FE736B4E723")!

        // 1. Open card A (seat select) with its URL present — works, gets cached.
        let openedA = try openWithURL(seatSelectCard, sessionKey: keyA)
        XCTAssertEqual(openedA.title, "Pick Your Seat")

        // 2. Open card B (system health) — a DIFFERENT card in the same conversation.
        let openedB = try openWithURL(systemHealthCard, sessionKey: keyB)
        XCTAssertEqual(openedB.title, "System Health")

        // 3. Warm tap card B (url=nil): must resolve to B's own content, NOT card A's
        //    (the old global latest-fallback would also have returned B here only by luck
        //    of recency — the next step is the one it always got wrong).
        let tapB = warmTap(sessionKey: keyB)
        XCTAssertEqual(tapB?.title, "System Health", "warm tap of card B resolved someone else's card")

        // 4. Warm tap back to card A: A was cached FIRST, so any most-recently-cached
        //    fallback returns B here. The per-session lookup must return A's own state.
        let tapA = warmTap(sessionKey: keyA)
        XCTAssertEqual(tapA?.title, "Pick Your Seat", "warm tap of card A resolved someone else's card")
        XCTAssertEqual(tapA, openedA, "card A must come back with its own exact state")

        // 5. Complete an interaction on A: the reply reuses A's session (updates that bubble
        //    in place) and overwrites A's cache entry — B must be completely unaffected.
        let reply = HermesLayout(title: "✓ Confirm Seat", subtitle: openedA.title,
                                 root: .text("Tapped from Pick Your Seat", style: .init(role: .footnote)))
        store.store(layout: reply, key: keyA)
        XCTAssertEqual(warmTap(sessionKey: keyB)?.title, "System Health",
                       "replying on card A must not change what card B resolves to")
        XCTAssertEqual(warmTap(sessionKey: keyA)?.title, "✓ Confirm Seat")

        // 6. Render both resolved layouts through the real harness — each draws its own,
        //    visibly different content (belt and braces on top of the title assertions).
        let imgA = try renderPNG(layout: tapA!, name: "persistence_cardA")
        let imgB = try renderPNG(layout: tapB!, name: "persistence_cardB")
        XCTAssertFalse(imagesLookIdentical(imgA, imgB), "cards A and B rendered identical pixels")
    }

    // MARK: Event-sequence routing (the layer the first fix's tests never covered)
    //
    // WHY THE OLD TESTS PASSED WHILE THE BUG STAYED LIVE: everything above drives the STORE
    // with the correct key already chosen ("warm tap card B" == look up B's key). On-device,
    // the failing step happened BEFORE the store was consulted: `didTransition(to:)` fires on
    // every expand right after `didSelect`, carried no tapped message, and the old
    // presentContent resolved it from `conversation.selectedMessage` — which on warm taps
    // still points at the PREVIOUSLY opened card. So the wrong message (with a perfectly
    // valid URL/cache entry of its own) was rendered over the card the user actually tapped.
    // Correct store + wrong caller-side key choice = green tests, live bug.
    //
    // These tests exercise HermesCardResolver — the decision procedure the view controller
    // now delegates to — through the REAL on-device event sequences, stale selection included.

    private func snapshot(_ layout: HermesLayout?, key: String?) -> HermesMessageSnapshot {
        HermesMessageSnapshot(sessionKey: key, layout: layout)
    }

    func testDidTransitionWithStaleSelectionMustNotRenderThePreviousCard() throws {
        let resolver = HermesCardResolver(store: store)
        let keyA = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x1> - 505B1814-EF2E-47B4-8514-20061D078043")!
        let keyB = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x2> - 2B06556A-A00F-43EF-991D-6FE736B4E723")!

        // 1. Cold open card A: willBecomeActive, no tap yet, selection is fresh and carries
        //    A's URL. Renders (and caches) A — correct.
        let coldA = resolver.resolve(tapped: nil, selected: snapshot(seatSelectCard, key: keyA))
        guard case .layout(let a, _, _) = coldA else { return XCTFail("cold open A must render") }
        XCTAssertEqual(a.title, "Pick Your Seat")

        // 2. Warm tap card B: didSelect delivers B (url present this time), but
        //    conversation.selectedMessage STILL points at A with A's URL. B must win.
        let tapB = resolver.resolve(tapped: snapshot(systemHealthCard, key: keyB),
                                    selected: snapshot(seatSelectCard, key: keyA))
        guard case .layout(let b, _, _) = tapB else { return XCTFail("tap of B must render") }
        XCTAssertEqual(b.title, "System Health", "tapped card lost to the stale selection")

        // 3. THE STEP THE BUG LIVED IN: didTransition(.expanded) fires immediately after,
        //    with no fresh message of its own — the VC re-resolves with the REMEMBERED tapped
        //    message and the still-stale selection. Old behavior: selection (A) rendered over
        //    B. Required behavior: still B.
        let transition = resolver.resolve(tapped: snapshot(systemHealthCard, key: keyB),
                                          selected: snapshot(seatSelectCard, key: keyA))
        guard case .layout(let afterTransition, _, _) = transition else {
            return XCTFail("didTransition re-resolution must render")
        }
        XCTAssertEqual(afterTransition.title, "System Health",
                       "didTransition's stale selectedMessage clobbered the tapped card — the exact reported bug")
    }

    func testWarmNilURLTapWithStaleSelectionRecoversTappedCardFromCache() throws {
        let resolver = HermesCardResolver(store: store)
        let keyA = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x1> - 505B1814-EF2E-47B4-8514-20061D078043")!
        let keyB = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x2> - 2B06556A-A00F-43EF-991D-6FE736B4E723")!

        // Both cards were rendered (hence cached) at some point.
        _ = resolver.resolve(tapped: nil, selected: snapshot(seatSelectCard, key: keyA))
        _ = resolver.resolve(tapped: nil, selected: snapshot(systemHealthCard, key: keyB))

        // Warm tap B with the iOS 26 nil-url delivery AND a stale selection that still holds
        // A's fully hydrated URL. The resolver must recover B from ITS OWN cache entry — the
        // stale selection's decodable layout must not be trusted across sessions.
        let warmTapB = resolver.resolve(tapped: snapshot(nil, key: keyB),
                                        selected: snapshot(seatSelectCard, key: keyA))
        XCTAssertEqual(warmTapB, .layout(systemHealthCard, sessionKey: keyB, source: .sessionCache),
                       "nil-url tap of B must recover B from cache, never decode the stale selection")

        // Same-session hydrated selection IS trusted (Messages holding a hydrated copy of the
        // same message the user tapped).
        let sameSession = resolver.resolve(tapped: snapshot(nil, key: keyA),
                                           selected: snapshot(seatSelectCard, key: keyA))
        XCTAssertEqual(sameSession, .layout(seatSelectCard, sessionKey: keyA, source: .decodedSameSessionSelection))
    }

    func testUnresolvableTappedCardStaysUnresolvedDespiteRenderableStaleSelection() throws {
        let resolver = HermesCardResolver(store: store)
        let keyA = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x1> - 505B1814-EF2E-47B4-8514-20061D078043")!
        let keyC = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x3> - 8CFBF009-7BE1-4AE4-9F52-FC394479E458")!

        // A is cached and even sits in selectedMessage with a decodable URL. C — the card the
        // user tapped — arrived while the extension was inactive (didReceive never fires for
        // API-sent cards) and its tap delivered url=nil. There is genuinely nothing to show
        // for C: the answer must be .unresolved(C), never A in any form.
        _ = resolver.resolve(tapped: nil, selected: snapshot(seatSelectCard, key: keyA))
        let tapC = resolver.resolve(tapped: snapshot(nil, key: keyC),
                                    selected: snapshot(seatSelectCard, key: keyA))
        guard case .unresolved(let diagnostics) = tapC else {
            return XCTFail("an unresolvable tapped card must fail honestly, not substitute the stale selection — got \(tapC)")
        }
        XCTAssertEqual(diagnostics.sessionKey, keyC,
                       "the failure must be attributed to the card the user actually tapped")
    }

    // MARK: The no-silent-fallback contract (the product requirement this build locks in)
    //
    // "When a message app fails don't just fallback to cached apps, show the logs and show
    // the error message." The single most important invariant: an unresolvable tap NEVER
    // renders a layout belonging to a different session — no matter how many other cards
    // are cached, how stale the selection is, or how rapidly taps arrive. It must produce
    // the diagnostic failure view instead, with the evidence visible on screen.

    func testUnresolvedNeverSubstitutesAnyCachedCardAndCarriesFullDiagnostics() throws {
        let resolver = HermesCardResolver(store: store)
        let keyA = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x1> - 505B1814-EF2E-47B4-8514-20061D078043")!
        let keyB = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x2> - 2B06556A-A00F-43EF-991D-6FE736B4E723")!
        let keyC = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x3> - 8CFBF009-7BE1-4AE4-9F52-FC394479E458")!

        // The store is FULL of perfectly renderable other cards — maximum temptation for
        // any latest/most-recent fallback.
        store.store(layout: seatSelectCard, key: keyA)
        store.store(layout: systemHealthCard, key: keyB)

        // Rapid-tap simulation: the unresolvable card C is resolved repeatedly (as the
        // didSelect → didTransition → retry sequence does), against every stale-selection
        // variant seen on-device. Every single answer must be .unresolved(C).
        let staleSelections: [HermesMessageSnapshot?] = [
            snapshot(seatSelectCard, key: keyA),   // stale selection with decodable URL
            snapshot(nil, key: keyB),              // stale nil-url selection, cached session
            nil                                    // no selection at all
        ]
        for (i, selected) in staleSelections.enumerated() {
            for round in 0..<4 {  // didSelect + 3 retry rounds
                let result = resolver.resolve(tapped: snapshot(nil, key: keyC), selected: selected)
                if case .layout(let layout, let sessionKey, let source) = result {
                    XCTFail("variant \(i) round \(round): unresolvable card C silently substituted '\(layout.title ?? "?")' (session=\(sessionKey ?? "nil"), source=\(source.rawValue)) — the exact regression this test exists to catch")
                }
                guard case .unresolved(let d) = result else {
                    return XCTFail("variant \(i) round \(round): expected .unresolved, got \(result)")
                }
                XCTAssertEqual(d.sessionKey, keyC)
            }
        }

        // The diagnostics must carry the on-screen evidence the brief requires: message
        // detected, URL status, session id, and the attempted resolution paths.
        guard case .unresolved(let diagnostics) = resolver.resolve(
            tapped: snapshot(nil, key: keyC),
            selected: snapshot(seatSelectCard, key: keyA)
        ) else { return XCTFail("expected .unresolved") }

        XCTAssertTrue(diagnostics.messageDetected)
        XCTAssertFalse(diagnostics.hadURL, "snapshot had no URL, diagnostics must say so")
        XCTAssertEqual(diagnostics.sessionKey, keyC)
        let trail = diagnostics.attemptedPaths.joined(separator: "\n")
        XCTAssertTrue(trail.contains("nil"), "trail must record the nil URL: \(trail)")
        XCTAssertTrue(trail.contains("DIFFERENT session"),
                      "trail must record the refused cross-session selection: \(trail)")
        XCTAssertTrue(trail.contains("no entry"),
                      "trail must record the cache miss: \(trail)")

        // And the report lines rendered on screen / logged must name the exact session and
        // the retry exhaustion, so a screenshot alone is enough to debug from.
        let report = diagnostics.reportLines(urlRetriesExhausted: 4,
                                             cachedSessionKeys: store.indexedKeys())
        let flat = report.joined(separator: "\n")
        XCTAssertTrue(flat.contains("message detected: yes"))
        XCTAssertTrue(flat.contains(HermesCardDiagnostics.shortKey(keyC)))
        XCTAssertTrue(flat.contains("nil after 4 attempts"))
        XCTAssertTrue(flat.contains("2 other card(s)"))
    }

    func testFailureViewRendersDiagnosticPanelNotBlank() throws {
        let keyC = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x3> - 8CFBF009-7BE1-4AE4-9F52-FC394479E458")!
        let otherKey = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x9> - 505B1814-EF2E-47B4-8514-20061D078043")!
        store.store(layout: seatSelectCard, key: otherKey)

        let resolver = HermesCardResolver(store: store)
        guard case .unresolved(let diagnostics) = resolver.resolve(
            tapped: snapshot(nil, key: keyC), selected: nil
        ) else { return XCTFail("expected .unresolved") }

        let view = HermesCardFailureView(diagnostics: diagnostics,
                                         urlRetriesExhausted: 4,
                                         cachedSessionKeys: store.indexedKeys())
        // On-screen content and log content come from the same reportLines — assert the
        // view exposes exactly what the VC logs, plus the build stamp (stale installed
        // builds are a documented cause of "the fix didn't work" reports).
        XCTAssertEqual(view.reportLines,
                       diagnostics.reportLines(urlRetriesExhausted: 4,
                                               cachedSessionKeys: store.indexedKeys())
                           + ["build: \(HermesBuildInfo.stamp)"])

        // The error view is a real render path — prove it draws actual content, exactly
        // like the card render smoke tests do.
        let hosting = UIHostingController(rootView: AnyView(view))
        let size = CGSize(width: 390, height: 700)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in hosting.view.layer.render(in: ctx.cgContext) }
        try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/hermes_render_failure_view.png"))
        XCTAssertFalse(isFlatColor(image), "failure view rendered a flat/blank image")
    }

    func testReplyFlowThenTappingOtherCardsResolvesEachOwnContent() throws {
        // The full reported loop: open A, interact (reply reuses A's session and overwrites
        // A's cache entry), then warm-tap B and warm-tap A again — every step must resolve to
        // its own session's content even with a maximally stale selection.
        let resolver = HermesCardResolver(store: store)
        let keyA = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x1> - 505B1814-EF2E-47B4-8514-20061D078043")!
        let keyB = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x2> - 2B06556A-A00F-43EF-991D-6FE736B4E723")!

        _ = resolver.resolve(tapped: nil, selected: snapshot(seatSelectCard, key: keyA))
        _ = resolver.resolve(tapped: snapshot(systemHealthCard, key: keyB),
                             selected: snapshot(seatSelectCard, key: keyA))

        // Reply on A (compose-time cache write under A's session, as makeMessage does).
        let reply = HermesLayout(title: "✓ Confirm Seat", subtitle: "Pick Your Seat",
                                 root: .text("Tapped from Pick Your Seat", style: .init(role: .footnote)))
        store.store(layout: reply, key: keyA)

        // Warm nil-url tap B with selection stale on A: must be B.
        XCTAssertEqual(resolver.resolve(tapped: snapshot(nil, key: keyB),
                                        selected: snapshot(seatSelectCard, key: keyA)),
                       .layout(systemHealthCard, sessionKey: keyB, source: .sessionCache))

        // Warm nil-url tap back to A with selection stale on B: must be A's latest (the reply).
        XCTAssertEqual(resolver.resolve(tapped: snapshot(nil, key: keyA),
                                        selected: snapshot(systemHealthCard, key: keyB)),
                       .layout(reply, sessionKey: keyA, source: .sessionCache))
    }

    /// A card whose session was never successfully decoded (didReceive doesn't fire for
    /// API-sent cards, and its first-ever tap arrived with url=nil) must resolve to NOTHING —
    /// the caller shows an explicit "couldn't load" state. Silently substituting another
    /// cached card was the bug.
    func testUnknownSessionResolvesToNothingNotAnotherCard() throws {
        let keyA = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x1> - 505B1814-EF2E-47B4-8514-20061D078043")!
        _ = try openWithURL(seatSelectCard, sessionKey: keyA)

        let keyC = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x3> - 8CFBF009-7BE1-4AE4-9F52-FC394479E458")!
        XCTAssertNil(warmTap(sessionKey: keyC),
                     "an unresolvable card must never fall back to a different card's layout")
    }

    // MARK: flightBoard / gaugeCluster specific never-substitute invariant
    //
    // The user's follow-up report singled out the flight-tracking (flightBoard) and
    // system-health (gaugeCluster) cards as still "falling back". These tests pin the
    // resolver's behavior for the EXACT sent documents: resolution either returns that
    // card's own session content or .unresolved — never another session's card.

    private func loadFixture(_ name: String) throws -> HermesLayout {
        guard let url = TestFixtures.url(named: name) else {
            throw XCTSkip("fixture \(name).json missing from test bundle")
        }
        return try HermesLayout.decode(from: Data(contentsOf: url))
    }

    func testSentFlightAndHealthDocumentsSurviveTheURLRoundTrip() throws {
        // The full wire path: JSON → base64url payload (what send_card_photon.mjs builds)
        // → decode (what the extension does). Any decode gap here is exactly what would
        // make only these cards unresolvable on-device.
        for name in ["sent_flight", "sent_health", "sent_seat", "sent_dinner"] {
            let layout = try loadFixture(name)
            let roundTripped = try HermesLayout.decode(base64URLPayload: layout.base64URLPayload())
            XCTAssertEqual(roundTripped, layout, "\(name) mutated in the URL round-trip")
        }
    }

    func testFlightAndHealthTapsNeverResolveToAnotherSessionsCard() throws {
        let resolver = HermesCardResolver(store: store)
        let flight = try loadFixture("sent_flight")
        let health = try loadFixture("sent_health")
        let dinner = try loadFixture("sent_dinner")

        let keyFlight = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x1> - 505B1814-EF2E-47B4-8514-20061D078043")!
        let keyHealth = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x2> - 2B06556A-A00F-43EF-991D-6FE736B4E723")!
        let keyDinner = HermesLayoutStore.sessionKey(
            fromSessionDescription: "<MSSession 0x3> - 8CFBF009-7BE1-4AE4-9F52-FC394479E458")!

        // Dinner (a working card) is open and cached; flight/health arrive by API so
        // didReceive never cached them.
        _ = resolver.resolve(tapped: nil, selected: snapshot(dinner, key: keyDinner))

        // Warm nil-url tap on the flight card with the stale dinner selection: must be
        // unresolved-for-flight, never the dinner card.
        let flightTap = resolver.resolve(tapped: snapshot(nil, key: keyFlight),
                                         selected: snapshot(dinner, key: keyDinner))
        guard case .unresolved(let dFlight) = flightTap else {
            return XCTFail("unresolvable flightBoard tap substituted a card: \(flightTap)")
        }
        XCTAssertEqual(dFlight.sessionKey, keyFlight)

        // Same for the health (gaugeCluster) card.
        let healthTap = resolver.resolve(tapped: snapshot(nil, key: keyHealth),
                                         selected: snapshot(dinner, key: keyDinner))
        guard case .unresolved(let dHealth) = healthTap else {
            return XCTFail("unresolvable gaugeCluster tap substituted a card: \(healthTap)")
        }
        XCTAssertEqual(dHealth.sessionKey, keyHealth)

        // Once their URLs DO decode (cold open), each resolves to its own content and is
        // cached; subsequent warm nil-url taps recover the right card from cache.
        XCTAssertEqual(resolver.resolve(tapped: snapshot(flight, key: keyFlight),
                                        selected: snapshot(dinner, key: keyDinner)),
                       .layout(flight, sessionKey: keyFlight, source: .decodedMessage))
        XCTAssertEqual(resolver.resolve(tapped: snapshot(nil, key: keyFlight),
                                        selected: snapshot(dinner, key: keyDinner)),
                       .layout(flight, sessionKey: keyFlight, source: .sessionCache))
        XCTAssertEqual(resolver.resolve(tapped: snapshot(health, key: keyHealth),
                                        selected: snapshot(flight, key: keyFlight)),
                       .layout(health, sessionKey: keyHealth, source: .decodedMessage))
        XCTAssertEqual(resolver.resolve(tapped: snapshot(nil, key: keyHealth),
                                        selected: snapshot(flight, key: keyFlight)),
                       .layout(health, sessionKey: keyHealth, source: .sessionCache))
    }

    // MARK: Render harness (mirrors HermesRenderSmokeTests / MessagesViewController.showRenderer)

    private func renderPNG(layout: HermesLayout, name: String) throws -> UIImage {
        let view = ScrollView {
            HermesLayoutRenderer(layout: layout, presentation: .expanded) { _ in }
                .padding(8)
        }
        .background(Color(.systemGroupedBackground))
        let hosting = UIHostingController(rootView: AnyView(view))
        let size = CGSize(width: 390, height: 700)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            hosting.view.layer.render(in: ctx.cgContext)
        }
        try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/hermes_render_\(name).png"))
        XCTAssertFalse(isFlatColor(image), "\(name) rendered a flat/blank image")
        return image
    }

    private func isFlatColor(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let w = cg.width, h = cg.height
        guard let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return true }
        let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        var first: [UInt8]? = nil
        for y in stride(from: 0, to: h, by: max(1, h / 24)) {
            for x in stride(from: 0, to: w, by: max(1, w / 24)) {
                let off = y * bpr + x * bpp
                let px = [ptr[off], ptr[off + 1], ptr[off + 2]]
                if let f = first {
                    if f != px { return false }
                } else {
                    first = px
                }
            }
        }
        return true
    }

    private func imagesLookIdentical(_ a: UIImage, _ b: UIImage) -> Bool {
        guard let da = a.pngData(), let db = b.pngData() else { return false }
        return da == db
    }
}
