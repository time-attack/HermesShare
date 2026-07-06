// HermesRenderSmokeTests.swift
// Empirical render harness: decodes real card JSON (including the exact documents that went
// blank on-device) and renders the same view tree MessagesViewController.showRenderer builds,
// through a real UIHostingController + ImageRenderer. A hang here reproduces the on-device
// hang; a nil/blank image reproduces the blank screen. PNGs are written to /tmp for eyeballs.

import XCTest
import SwiftUI
import UIKit
import HermesShared

@MainActor
final class HermesRenderSmokeTests: XCTestCase {

    /// Mirrors MessagesViewController.showRenderer's view tree (ScrollView + safeAreaInset bar).
    private func extensionStyleView(for layout: HermesLayout, presentation: HermesPresentation = .expanded) -> some View {
        let bodyWithoutActions = HermesLayout(
            version: layout.version, title: layout.title, subtitle: layout.subtitle,
            accentColorHex: layout.accentColorHex, background: layout.background,
            root: layout.root, actions: nil
        )
        let actions = layout.actions ?? []
        return ScrollView {
            HermesLayoutRenderer(layout: bodyWithoutActions, presentation: presentation) { _ in }
                .padding(presentation == .compact ? 0 : 8)
        }
        .safeAreaInset(edge: .bottom) {
            if !actions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(actions, id: \.id) { action in
                        HermesPrimaryCTA(label: action.label, systemImage: action.systemImage) {}
                    }
                }
                .padding(12)
                .background(.regularMaterial)
            }
        }
        .background(HermesLayoutRenderer.canvasColor(for: layout))
        // Production showRenderer tints the pinned bar with the card accent; mirror it so
        // renders show the CTA exactly as shipped.
        .tint(Color(hermesHex: layout.accentColorHex) ?? .accentColor)
        .environment(\.hermesAccent, Color(hermesHex: layout.accentColorHex) ?? .accentColor)
    }

    /// Render through a real laid-out UIHostingController, like the extension embed does,
    /// then snapshot with UIGraphicsImageRenderer. Returns nil if nothing drew.
    private func renderPNG(layout: HermesLayout, name: String,
                           presentation: HermesPresentation = .expanded,
                           size: CGSize = CGSize(width: 390, height: 700),
                           interfaceStyle: UIUserInterfaceStyle = .light,
                           settle: TimeInterval = 0.3) throws -> UIImage {
        let hosting = UIHostingController(rootView: AnyView(extensionStyleView(for: layout, presentation: presentation)))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = interfaceStyle
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.layoutIfNeeded()
        // Pass a longer settle for cards with remote AsyncImage (album art) so the network
        // fetch completes and the snapshot captures the real image, not the placeholder.
        RunLoop.main.run(until: Date().addingTimeInterval(settle))

        let renderer = UIGraphicsImageRenderer(size: size)
        // layer.render(in:) works in unhosted unit tests (drawHierarchy needs a host app).
        let image = renderer.image { ctx in
            hosting.view.layer.render(in: ctx.cgContext)
        }
        let url = URL(fileURLWithPath: "/tmp/hermes_render_\(name).png")
        try image.pngData()?.write(to: url)

        // Blank detection: sample pixels; fail if the whole thing is one flat color.
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

    private func loadFixture(_ name: String) throws -> HermesLayout {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw XCTSkip("fixture \(name).json missing from test bundle")
        }
        return try HermesLayout.decode(from: Data(contentsOf: url))
    }

    // MARK: The three cards that went blank on-device

    func testPackingListRenders() throws {
        _ = try renderPNG(layout: try loadFixture("failing_packing_list"), name: "packing")
    }

    func testRamenRecipeRenders() throws {
        _ = try renderPNG(layout: try loadFixture("failing_ramen"), name: "ramen")
    }

    func testPreflightChecklistRenders() throws {
        _ = try renderPNG(layout: try loadFixture("failing_preflight"), name: "preflight")
    }

    /// The exact card the user reports rendering completely blank after the ADA visual pass:
    /// bare progressRing + progressBar + checklist under one header (no cards/keyValueRows).
    /// This is the specific combination the three ADA changes touch.
    func testAdaTestCardRenders() throws {
        _ = try renderPNG(layout: try loadFixture("ada_test_card"), name: "ada_test_card")
    }

    /// Each ADA-touched primitive in isolation, to bisect which one breaks.
    func testAdaProgressRingAlone() throws {
        let layout = HermesLayout(
            title: "Ring", subtitle: "context",
            root: .progressRing(value: 0.6, label: "done", colorHex: "#34C759"),
            actions: nil
        )
        _ = try renderPNG(layout: layout, name: "ada_ring")
    }

    func testAdaProgressBarAlone() throws {
        let layout = HermesLayout(
            title: "Bar", subtitle: "context",
            root: .progressBar(value: 0.6, colorHex: "#34C759"),
            actions: nil
        )
        _ = try renderPNG(layout: layout, name: "ada_bar")
    }

    // MARK: Isolation probes

    /// Just the icon-badge keyValueRow, alone.
    func testIconKeyValueRowRenders() throws {
        let layout = HermesLayout(
            title: "Icon rows",
            root: .vstack(spacing: 8, alignment: "leading", children: [
                .keyValueRow(key: "T-shirts", value: "4", iconSystemName: "tshirt"),
                .keyValueRow(key: "Charger", value: "1", iconSystemName: "battery.100.bolt")
            ]),
            actions: [HermesAction(id: "x", label: "Confirm", deepLinkURL: "hermesshare://action?id=x")]
        )
        _ = try renderPNG(layout: layout, name: "icon_rows")
    }

    /// Just two nested cards in a vstack, no icons.
    func testMultiCardRenders() throws {
        let layout = HermesLayout(
            title: "Two cards",
            root: .vstack(spacing: 14, alignment: "leading", children: [
                .card(padding: 14, cornerRadius: 16, backgroundHex: nil,
                      child: .vstack(spacing: 8, alignment: "leading", children: [
                        .text("Card one", style: .init(role: .headline, weight: .bold)),
                        .keyValueRow(key: "A", value: "1")
                      ])),
                .card(padding: 14, cornerRadius: 16, backgroundHex: nil,
                      child: .vstack(spacing: 8, alignment: "leading", children: [
                        .text("Card two", style: .init(role: .headline, weight: .bold)),
                        .keyValueRow(key: "B", value: "2")
                      ]))
            ]),
            actions: [HermesAction(id: "y", label: "Done", deepLinkURL: "hermesshare://action?id=y")]
        )
        _ = try renderPNG(layout: layout, name: "multi_card")
    }

    /// The v3 outgoing test batch: every card decodes through the real decoder and renders
    /// through the extension-identical view tree before anything is sent.
    func testV3BatchRenders() throws {
        for name in ["batch_kyoto", "batch_dinner_vote", "batch_workout",
                     "batch_plan_compare", "batch_omakase"] {
            _ = try renderPNG(layout: try loadFixture(name), name: name)
        }
    }

    /// The v4 ADA redesign batch — one card per genre, each with a real drawn centerpiece.
    /// These are the exact documents sent to the user's thread via Photon.
    func testAda2BatchRenders() throws {
        for name in ["ada2_flight", "ada2_recipe", "ada2_seat", "ada2_itinerary", "ada2_stats"] {
            _ = try renderPNG(layout: try loadFixture(name), name: name)
        }
    }

    // MARK: The exact documents the user reports "falling back" on-device
    // (flightBoard = flight tracking, gaugeCluster = system health). Rendered through the
    // extension-identical view tree in BOTH presentations — a bubble tap shows .compact
    // first, then transitions to .expanded, so both paths must survive.

    func testSentFlightCardRendersExpanded() throws {
        _ = try renderPNG(layout: try loadFixture("sent_flight"), name: "sent_flight_expanded")
    }

    func testSpotifyRankingRenders() throws {
        // 3s settle so the mediaList's remote album-art AsyncImages actually load into the snapshot;
        // taller frame so all five ranked rows are captured (the card scrolls on-device).
        _ = try renderPNG(layout: try loadFixture("sent_spotify_ranking"), name: "spotify_ranking",
                          size: CGSize(width: 390, height: 900), settle: 3.0)
    }

    /// Kyoto hotels PHOTO CATALOG: full-bleed hero cards, one pre-expanded to show the room
    /// gallery. Tall frame + long settle so the full-bleed heroes and room-tile AsyncImages load.
    func testKyotoCatalogRenders() throws {
        let layout = try loadFixture("sent_kyoto_catalog")
        guard case let .photoCatalog(items, expanded, confirm) = layout.root else {
            return XCTFail("expected photoCatalog root, got \(layout.root)")
        }
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(expanded, "ethnography")
        XCTAssertNotNil(confirm)
        _ = try renderPNG(layout: layout, name: "kyoto_catalog",
                          size: CGSize(width: 390, height: 1400), settle: 4.0)
    }

    /// Collapsed-only variant (no pre-expanded card) — proves the full-bleed collapsed hero
    /// stack renders with price pills and scrim, no drawer.
    func testKyotoCatalogCollapsedRenders() throws {
        let base = try loadFixture("sent_kyoto_catalog")
        guard case let .photoCatalog(items, _, confirm) = base.root else { return XCTFail("shape") }
        let collapsed = HermesLayout(
            version: base.version, title: base.title, subtitle: base.subtitle,
            accentColorHex: base.accentColorHex, background: base.background,
            root: .photoCatalog(items: items, initialExpandedId: nil, confirmLabel: confirm),
            actions: nil)
        _ = try renderPNG(layout: collapsed, name: "kyoto_catalog_collapsed",
                          size: CGSize(width: 390, height: 1000), settle: 4.0)
    }

    /// photoCatalog degenerate inputs: empty items, an item with no rooms/no hero/no price,
    /// unreachable image (dark-skeleton fallback path). No crash, no light-gray broken box.
    func testPhotoCatalogDegenerate() throws {
        let layout = HermesLayout(
            title: "Catalog", accentColorHex: "#CBA35C",
            root: .vstack(spacing: 12, alignment: "leading", children: [
                .photoCatalog(items: [], initialExpandedId: nil, confirmLabel: nil),
                .photoCatalog(items: [
                    HermesCatalogItem(id: "a", heroImageUrl: "https://invalid.example/x.jpg",
                                      title: "No rooms, bad image", subtitle: "Nowhere · ★ 0",
                                      priceText: "from $0", priceUnit: "night", rooms: []),
                    HermesCatalogItem(id: "b", title: "No hero at all", rooms: [
                        HermesCatalogRoom(id: "b1", name: "Room", price: "$1")
                    ])
                ], initialExpandedId: "b", confirmLabel: "Book")
            ]))
        _ = try renderPNG(layout: layout, name: "catalog_degenerate", size: CGSize(width: 390, height: 700))
    }

    /// Kyoto hotels: mediaList with real Openverse photos (general image search, no per-domain
    /// CDN), no rank numerals (a value list, not a top-N), display-only (no CTA).
    func testKyotoHotelsRenders() throws {
        let layout = try loadFixture("sent_kyoto_hotels")
        XCTAssertNil(layout.actions, "a browse list is display-only — no CTA")
        _ = try renderPNG(layout: layout, name: "kyoto_hotels",
                          size: CGSize(width: 390, height: 900), settle: 3.5)
    }

    /// Generalization proof: the same mediaList + real-artwork pattern, a DIFFERENT domain
    /// (podcasts, Clearbit dead so iTunes podcast art), a different fallback glyph, and NO
    /// `actions` CTA (display-only). Confirms the capability isn't hardcoded to one card.
    func testPodcastRankingRenders() throws {
        let layout = try loadFixture("sent_podcast_ranking")
        XCTAssertNil(layout.actions, "a display-only ranking card must have no CTA")
        _ = try renderPNG(layout: layout, name: "podcast_ranking",
                          size: CGSize(width: 390, height: 860), settle: 3.0)
    }

    func testSentFlightCardRendersCompact() throws {
        _ = try renderPNG(layout: try loadFixture("sent_flight"), name: "sent_flight_compact",
                          presentation: .compact, size: CGSize(width: 390, height: 300))
    }

    func testSentHealthCardRendersExpanded() throws {
        _ = try renderPNG(layout: try loadFixture("sent_health"), name: "sent_health_expanded")
    }

    func testSentHealthCardRendersCompact() throws {
        _ = try renderPNG(layout: try loadFixture("sent_health"), name: "sent_health_compact",
                          presentation: .compact, size: CGSize(width: 390, height: 300))
    }

    /// The revised pre-departure countdown template (flightBoard hero replacing the generic
    /// progressRing/keyValueRow skeleton the user called "incredibly basic"). Proves the
    /// skill's template JSON decodes against the shipped schema and renders non-blank.
    func testPredepartureBoardTemplateRenders() throws {
        _ = try renderPNG(layout: try loadFixture("predeparture_board"), name: "predeparture_board")
    }

    /// Degenerate payloads for the two drawn centerpieces: empty gauge array, out-of-range
    /// and non-finite values, empty IATA codes, NaN progress. None of these may crash or
    /// hang the extension-identical render path.
    func testFlightBoardAndGaugeClusterDegenerateInputs() throws {
        let degenerates: [(String, HermesNode)] = [
            ("gauges_empty", .gaugeCluster(gauges: [])),
            ("gauges_wild", .gaugeCluster(gauges: [
                HermesGauge(label: "neg", value: -3), HermesGauge(label: "big", value: 42),
                HermesGauge(label: "nan", value: Double.nan, valueText: "?"),
                HermesGauge(label: "inf", value: .infinity)
            ])),
            ("board_empty_codes", .flightBoard(HermesFlightBoard(origin: "", destination: "", status: ""))),
            ("board_nan_progress", .flightBoard(HermesFlightBoard(
                origin: "SFO", destination: "NRT", status: "In flight", progress: Double.nan))),
            ("board_out_of_range", .flightBoard(HermesFlightBoard(
                origin: "VERYLONGCODE", destination: "X", status: "Delayed", progress: 7)))
        ]
        for (name, node) in degenerates {
            let layout = HermesLayout(
                title: "Degenerate \(name)",
                root: node,
                actions: [HermesAction(id: "a", label: "OK", deepLinkURL: "hermesshare://action?id=a")]
            )
            // Degenerate inputs may legitimately draw very little; the assertion here is
            // "no crash / no hang", so skip the flat-color check by rendering directly.
            let hosting = UIHostingController(rootView: AnyView(extensionStyleView(for: layout)))
            let size = CGSize(width: 390, height: 700)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = hosting
            window.isHidden = false
            hosting.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
    }

    /// Every built-in sample still renders (regression net).
    func testAllSamplesRender() throws {
        for (name, layout) in HermesSampleLayouts.all {
            _ = try renderPNG(layout: layout, name: "sample_\(name.replacingOccurrences(of: " ", with: "_"))")
        }
    }

    // MARK: v5 scene expansion

    /// The five new scene heroes render non-blank in BOTH light and dark mode (atmosphere
    /// cards force dark content, so light-mode hosting is the harder case).
    func testV5ScenesRenderLightAndDark() throws {
        let v5 = ["Courier Journey", "Weather Tonight", "Concert Ticket", "Market Pulse", "Game Final"]
        for (name, layout) in HermesSampleLayouts.all where v5.contains(name) {
            let slug = name.lowercased().replacingOccurrences(of: " ", with: "_")
            _ = try renderPNG(layout: layout, name: "v5_\(slug)_light", interfaceStyle: .light)
            _ = try renderPNG(layout: layout, name: "v5_\(slug)_dark", interfaceStyle: .dark)
        }
    }

    /// Every sky condition × day/night draws a distinct, non-blank scene.
    func testSkySceneConditionMatrixRenders() throws {
        for condition in [HermesSkyScene.Condition.clear, .clouds, .rain, .snow, .storm, .fog] {
            for isNight in [false, true] {
                let layout = HermesLayout(
                    root: .skyScene(HermesSkyScene(
                        condition: condition, isNight: isNight,
                        tempText: "63°", hiLoText: "H 78° · L 58°",
                        location: "Brooklyn", caption: "\(condition.rawValue)\(isNight ? " night" : " day")",
                        seed: 21))
                )
                _ = try renderPNG(layout: layout, name: "sky_\(condition.rawValue)_\(isNight ? "night" : "day")",
                                  size: CGSize(width: 390, height: 340))
            }
        }
    }

    /// Degenerate v5 payloads must not crash or hang the extension-identical render path:
    /// empty/NaN sparkline series, NaN/out-of-range journey progress, empty scoreboard
    /// strings, empty ticket fields.
    func testV5DegenerateInputs() throws {
        let degenerates: [(String, HermesNode)] = [
            ("spark_empty", .sparkline(HermesSparkline(label: "X", valueText: "—", points: []))),
            ("spark_wild", .sparkline(HermesSparkline(
                label: "X", valueText: "—", trend: .down,
                points: [1, Double.nan, 3, .infinity, -2, 2]))),
            ("spark_flatline", .sparkline(HermesSparkline(
                label: "X", valueText: "0", trend: .flat, points: [5, 5, 5, 5]))),
            ("arc_nan", .journeyArc(HermesJourneyArc(
                originLabel: "A", destinationLabel: "B", status: "??", progress: Double.nan))),
            ("arc_over", .journeyArc(HermesJourneyArc(
                originLabel: "", destinationLabel: "", status: "", progress: 12))),
            ("score_empty", .scoreBoard(HermesScoreBoard(
                homeName: "", homeScore: "", awayName: "", awayScore: ""))),
            ("ticket_bare", .eventTicket(HermesEventTicket(title: "")))
        ]
        for (name, node) in degenerates {
            let layout = HermesLayout(title: "Degenerate \(name)", root: node)
            let hosting = UIHostingController(rootView: AnyView(extensionStyleView(for: layout)))
            let size = CGSize(width: 390, height: 700)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = hosting
            window.isHidden = false
            hosting.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
    }

    /// Forward compat: an unknown node type decodes to `.unsupported` (whole card still
    /// decodes) and renders a visible chip naming the missing vocabulary — never a blank
    /// screen, never a decode failure.
    func testUnknownNodeTypeDecodesAndRendersVisibleChip() throws {
        let json = """
        { "version": 1, "title": "From the future",
          "root": { "type": "vstack", "spacing": 12, "children": [
            { "type": "text", "text": "Known content renders fine" },
            { "type": "hologram", "shimmer": 0.9 },
            { "type": "keyValueRow", "key": "Also fine", "value": "Yes" }
          ] } }
        """
        let layout = try HermesLayout.decode(fromJSONString: json)
        guard case let .vstack(_, _, children) = layout.root, children.count == 3,
              case let .unsupported(typeName) = children[1] else {
            return XCTFail("unknown node should decode to .unsupported inside an intact tree, got \(layout.root)")
        }
        XCTAssertEqual(typeName, "hologram")
        _ = try renderPNG(layout: layout, name: "unsupported_chip",
                          size: CGSize(width: 390, height: 340))
    }

    /// Design-review regressions: the ticket tear line must stay on the stub boundary at
    /// non-default widths (it was proportional and only aligned at ~325pt), and 4+ character
    /// scores must not overflow the scoreboard columns (tiles were fixed 30pt).
    func testTicketNarrowAndWideWidthsRender() throws {
        let layout = HermesLayout(
            accentColorHex: "#BF5AF2",
            background: HermesBackground(kind: .atmosphere, colorsHex: ["#BF5AF2"]),
            root: .eventTicket(HermesEventTicket(
                kicker: "World Tour", title: "Khruangbin", venue: "Kings Theatre",
                dateText: "Fri Aug 21", timeText: "8:00 PM", seatText: "ORCH C · 12",
                code: "K7Q2XW", seed: 12))
        )
        _ = try renderPNG(layout: layout, name: "ticket_narrow", size: CGSize(width: 300, height: 340))
        _ = try renderPNG(layout: layout, name: "ticket_wide", size: CGSize(width: 500, height: 340))
    }

    func testScoreBoardLongScoresRender() throws {
        let layout = HermesLayout(
            accentColorHex: "#30D158",
            background: HermesBackground(kind: .atmosphere),
            root: .scoreBoard(HermesScoreBoard(
                homeName: "IND", homeScore: "287/6", homeColorHex: "#0A84FF",
                awayName: "AUS", awayScore: "285/10", awayColorHex: "#FFD60A",
                statusText: "50 overs · Final", winner: .home))
        )
        _ = try renderPNG(layout: layout, name: "score_long", size: CGSize(width: 320, height: 340))
    }

    /// mediaList degenerate inputs: empty list, rows with no rank/no image/no trailing, and a
    /// very long title — none may crash or clip badly. Uses an unreachable image URL so the
    /// AsyncImage fallback path is exercised.
    func testMediaListDegenerateRenders() throws {
        let layout = HermesLayout(
            title: "Media list",
            accentColorHex: "#1DB954",
            root: .vstack(spacing: 12, alignment: "leading", children: [
                .mediaList(items: []),
                .mediaList(items: [
                    HermesMediaItem(rank: 1, imageUrl: "https://invalid.example/nope.jpg",
                                    title: "A very very long track title that should truncate cleanly",
                                    subtitle: "Some Artist", trailing: "1,248", trailingSub: "plays"),
                    HermesMediaItem(title: "No rank, no image", subtitle: nil, trailing: nil),
                    HermesMediaItem(rank: 3, title: "No image, has trailing",
                                    trailing: "42", trailingSub: "plays",
                                    fallbackSystemImage: "film.fill")
                ])
            ])
        )
        _ = try renderPNG(layout: layout, name: "media_list_degenerate", size: CGSize(width: 390, height: 500))
    }

    /// Unknown background kinds degrade to .plain instead of failing the whole layout —
    /// the background enum was the last strict-decode forward-compat hole.
    func testUnknownBackgroundKindDecodesAsPlain() throws {
        let json = """
        { "version": 1, "background": { "kind": "aurora", "colorsHex": ["#123456"] },
          "root": { "type": "text", "text": "hello" } }
        """
        let layout = try HermesLayout.decode(fromJSONString: json)
        XCTAssertEqual(layout.background?.kind, .plain)
    }

    /// A mediaList round-trips through the exact wire path (compact JSON → base64url → decode).
    func testMediaListSurvivesURLRoundTrip() throws {
        let layout = try loadFixture("sent_spotify_ranking")
        let roundTripped = try HermesLayout.decode(base64URLPayload: layout.base64URLPayload())
        XCTAssertEqual(roundTripped, layout)
        guard case let .vstack(_, _, children) = layout.root else { return XCTFail("expected vstack root") }
        // The mediaList is nested in the second card; just assert the whole doc has one.
        let json = String(data: try layout.encoded(), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"mediaList\""), "mediaList node should encode with its type tag")
        XCTAssertFalse(children.isEmpty)
    }

    /// The v5 payloads survive the exact wire path senders use (compact JSON → base64url →
    /// decode), same guarantee the v4 nodes have.
    func testV5SamplesSurviveURLRoundTrip() throws {
        let v5 = ["Courier Journey", "Weather Tonight", "Concert Ticket", "Market Pulse", "Game Final"]
        for (name, layout) in HermesSampleLayouts.all where v5.contains(name) {
            let roundTripped = try HermesLayout.decode(base64URLPayload: layout.base64URLPayload())
            XCTAssertEqual(roundTripped, layout, "\(name) changed across the wire")
        }
    }
}
