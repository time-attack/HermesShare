import XCTest
import HermesShared

final class HermesLayoutCodableTests: XCTestCase {

    /// decode(encode(x)) == x for every built-in sample.
    func testSampleLayoutsRoundTrip() throws {
        for (name, layout) in HermesSampleLayouts.all {
            let data = try layout.encoded()
            let decoded = try HermesLayout.decode(from: data)
            XCTAssertEqual(layout, decoded, "Round-trip mismatch for \(name)")

            // And once more through the pretty path to be sure formatting is irrelevant.
            let pretty = try layout.encoded(pretty: true)
            let decoded2 = try HermesLayout.decode(from: pretty)
            XCTAssertEqual(layout, decoded2, "Pretty round-trip mismatch for \(name)")
        }
    }

    /// CTA routing: `hermesshare://` (and empty/garbage URLs) insert a reply; any real scheme
    /// opens externally. This is the "smart CTA" fix — a display card's `https://` "Open in
    /// Spotify" must open the app, never insert a fake "✓" reply into the thread.
    func testActionSchemeRouting() {
        func reply(_ url: String) -> Bool {
            HermesAction(id: "a", label: "x", deepLinkURL: url).insertsReply
        }
        // Reply (commit) actions:
        XCTAssertTrue(reply("hermesshare://action?id=confirm"))
        XCTAssertTrue(reply("HermesShare://action?id=confirm"))   // scheme is case-insensitive
        XCTAssertTrue(reply(""))                                   // empty → fail-safe to reply
        XCTAssertTrue(reply("not a url"))                          // unparseable → fail-safe to reply
        // External-open actions (must NOT insert a reply):
        XCTAssertFalse(reply("https://open.spotify.com/playlist/37i9dQ"))
        XCTAssertFalse(reply("http://example.com"))
        XCTAssertFalse(reply("spotify:playlist:37i9dQ"))
        XCTAssertFalse(reply("maps://?q=SFO"))
        XCTAssertFalse(reply("tel:+15551234567"))
    }

    /// Decode a hand-authored JSON fixture (the format Hermes emits) → re-encode → re-decode.
    func testRawJSONFixtureRoundTrip() throws {
        let json = """
        {
          "version": 1,
          "title": "Package Out for Delivery",
          "subtitle": "Order #HS-48213",
          "accentColorHex": "#34C759",
          "root": {
            "type": "vstack",
            "spacing": 12,
            "children": [
              { "type": "statusBadge", "label": "Out for delivery", "colorHex": "#34C759" },
              { "type": "progressBar", "value": 0.78, "colorHex": "#34C759" },
              { "type": "keyValueRow", "key": "Carrier", "value": "UPS Ground" },
              { "type": "text", "text": "ETA 2:40 PM", "style": { "role": "headline", "weight": "bold" } }
            ]
          },
          "actions": [
            { "id": "track", "label": "View full tracking", "deepLinkURL": "hermesshare://action?id=track" }
          ]
        }
        """
        let layout = try HermesLayout.decode(fromJSONString: json)
        XCTAssertEqual(layout.title, "Package Out for Delivery")
        XCTAssertEqual(layout.actions?.count, 1)

        let reDecoded = try HermesLayout.decode(from: try layout.encoded())
        XCTAssertEqual(layout, reDecoded)
    }

    /// Lenient text-style decoding: role/weight omitted → defaults, not a decode error.
    func testTextStyleDefaults() throws {
        let json = #"{ "type": "text", "text": "hi", "style": {} }"#
        let node = try JSONDecoder().decode(HermesNode.self, from: Data(json.utf8))
        guard case let .text(value, style) = node else {
            return XCTFail("Expected .text node")
        }
        XCTAssertEqual(value, "hi")
        XCTAssertEqual(style.role, .body)
        XCTAssertEqual(style.weight, .regular)
    }

    /// The base64url transport used by the iMessage extension survives a round trip.
    func testBase64URLPayloadRoundTrip() throws {
        let payload = try HermesSampleLayouts.statDashboard.base64URLPayload()
        XCTAssertFalse(payload.contains("+"))
        XCTAssertFalse(payload.contains("/"))
        XCTAssertFalse(payload.contains("="))
        let decoded = try HermesLayout.decode(base64URLPayload: payload)
        XCTAssertEqual(decoded, HermesSampleLayouts.statDashboard)
    }

    /// Unknown discriminator decodes to a visible `.unsupported` node (v5 forward-compat)
    /// instead of throwing — so a card can carry vocabulary newer than the installed build
    /// without the whole card failing to decode. The marker survives re-encoding.
    func testUnknownNodeTypeDecodesToUnsupported() throws {
        let json = #"{ "type": "hologram", "shimmer": 0.9 }"#
        let node = try JSONDecoder().decode(HermesNode.self, from: Data(json.utf8))
        guard case let .unsupported(typeName) = node else {
            return XCTFail("expected .unsupported, got \(node)")
        }
        XCTAssertEqual(typeName, "hologram")
        let reencoded = try JSONDecoder().decode(
            HermesNode.self, from: JSONEncoder().encode(node))
        XCTAssertEqual(reencoded, node)
    }

    /// Hand-authored seatChart JSON (the wire format Hermes emits) decodes with lenient
    /// defaults and round-trips.
    func testSeatChartRawJSON() throws {
        let json = """
        {
          "type": "seatChart",
          "rows": [
            {
              "rowNumber": 22,
              "isExitRow": true,
              "hasExtraLegroom": true,
              "aisleAfterIndices": [2, 5],
              "seats": [
                { "id": "22A", "letter": "A" },
                { "id": "22B", "letter": "B", "state": "taken" },
                { "id": "22C", "letter": "C", "state": "selected" }
              ]
            }
          ]
        }
        """
        let node = try JSONDecoder().decode(HermesNode.self, from: Data(json.utf8))
        guard case let .seatChart(rows, selectedSeatId) = node else {
            return XCTFail("Expected .seatChart node")
        }
        XCTAssertNil(selectedSeatId)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].rowNumber, 22)
        XCTAssertTrue(rows[0].isExitRow)
        XCTAssertFalse(rows[0].isBulkhead)          // omitted → false
        XCTAssertTrue(rows[0].hasExtraLegroom)
        XCTAssertEqual(rows[0].aisleAfterIndices, [2, 5])
        XCTAssertEqual(rows[0].seats[0].state, .available)   // omitted → available
        XCTAssertEqual(rows[0].seats[1].state, .taken)
        XCTAssertEqual(rows[0].seats[2].state, .selected)

        let reDecoded = try JSONDecoder().decode(HermesNode.self, from: JSONEncoder().encode(node))
        XCTAssertEqual(node, reDecoded)
    }

    /// Hand-authored quickReplyRow JSON decodes (deepLinkURL optional) and round-trips.
    func testQuickReplyRowRawJSON() throws {
        let json = """
        {
          "type": "quickReplyRow",
          "options": [
            { "id": "yes", "label": "I'm in", "systemImage": "checkmark" },
            { "id": "no", "label": "Can't make it", "deepLinkURL": "hermesshare://action?id=no&e=1" }
          ]
        }
        """
        let node = try JSONDecoder().decode(HermesNode.self, from: Data(json.utf8))
        guard case let .quickReplyRow(options) = node else {
            return XCTFail("Expected .quickReplyRow node")
        }
        XCTAssertEqual(options.count, 2)
        XCTAssertNil(options[0].deepLinkURL)
        XCTAssertEqual(options[1].deepLinkURL, "hermesshare://action?id=no&e=1")

        let reDecoded = try JSONDecoder().decode(HermesNode.self, from: JSONEncoder().encode(node))
        XCTAssertEqual(node, reDecoded)
    }

    /// Unknown seat state should throw (strict vocabulary), not default.
    func testUnknownSeatStateThrows() {
        let json = #"{ "id": "1A", "letter": "A", "state": "levitating" }"#
        XCTAssertThrowsError(try JSONDecoder().decode(HermesSeat.self, from: Data(json.utf8)))
    }

    /// keyValueRow accepts BOTH icon keys: the documented "iconSystemName" and the legacy
    /// "systemName" the first decoder shipped with (regression: icons silently dropped).
    func testKeyValueRowIconKeyCompatibility() throws {
        for key in ["iconSystemName", "systemName"] {
            let json = #"{ "type": "keyValueRow", "key": "Gate", "value": "B12", "\#(key)": "airplane" }"#
            let node = try JSONDecoder().decode(HermesNode.self, from: Data(json.utf8))
            guard case let .keyValueRow(_, _, icon) = node else { return XCTFail("Expected keyValueRow") }
            XCTAssertEqual(icon, "airplane", "icon not decoded from key '\(key)'")
        }
        // And the encoder emits the documented key.
        let encoded = try JSONEncoder().encode(HermesNode.keyValueRow(key: "k", value: "v", iconSystemName: "star"))
        let str = String(data: encoded, encoding: .utf8)!
        XCTAssertTrue(str.contains("\"iconSystemName\""), "encoder should emit the documented key: \(str)")
    }

    /// The full v3 vocabulary decodes from hand-authored wire-format JSON (lenient defaults)
    /// and round-trips.
    func testV3NodesRawJSONRoundTrip() throws {
        let json = """
        { "type": "vstack", "spacing": 10, "children": [
          { "type": "checklist", "items": [
            { "text": "Passport", "state": "checked" },
            { "text": "Charger", "state": "unchecked", "detail": "USB-C" },
            { "text": "Just a bullet" }
          ]},
          { "type": "timeline", "entries": [
            { "time": "9:00", "title": "Depart", "state": "past" },
            { "title": "Layover", "subtitle": "NRT", "state": "current" },
            { "time": "18:20", "title": "Arrive" }
          ]},
          { "type": "rating", "value": 4.5, "label": "324 reviews" },
          { "type": "table", "headers": ["Plan", "Price"], "rows": [["Basic", "$5"], ["Pro", "$12"]] },
          { "type": "gallery", "urls": ["https://example.com/a.jpg"], "heightPt": 100 },
          { "type": "tagRow", "labels": ["Spicy", "Vegan"] },
          { "type": "stat", "value": "1.2M", "label": "Requests", "iconSystemName": "bolt.fill" },
          { "type": "dateBadge", "month": "Jul", "day": "8", "weekday": "Tue" },
          { "type": "person", "name": "Marcus T.", "detail": "Driver · ★ 4.96" },
          { "type": "barChart", "bars": [
            { "label": "Yes", "value": 7 }, { "label": "No", "value": 2, "valueLabel": "2 votes" }
          ]},
          { "type": "optionPicker", "options": [
            { "id": "a", "label": "Option A", "badge": "$10" },
            { "id": "b", "label": "Option B", "disabled": true }
          ], "confirmLabel": "Book", "pickerStyle": "grid" }
        ]}
        """
        let node = try JSONDecoder().decode(HermesNode.self, from: Data(json.utf8))
        let reDecoded = try JSONDecoder().decode(HermesNode.self, from: JSONEncoder().encode(node))
        XCTAssertEqual(node, reDecoded)

        // Spot-check lenient defaults.
        guard case let .vstack(_, _, children) = node else { return XCTFail() }
        guard case let .checklist(items) = children[0] else { return XCTFail("Expected checklist") }
        XCTAssertEqual(items[2].state, .none)                       // omitted → none
        guard case let .timeline(entries) = children[1] else { return XCTFail("Expected timeline") }
        XCTAssertEqual(entries[2].state, .future)                   // omitted → future
        guard case let .rating(_, maxValue, _, _) = children[2] else { return XCTFail("Expected rating") }
        XCTAssertEqual(maxValue, 5)                                 // omitted → 5
        guard case let .optionPicker(options, selectedId, _, style) = children[10] else { return XCTFail("Expected optionPicker") }
        XCTAssertNil(selectedId)
        XCTAssertEqual(style, .grid)
        XCTAssertFalse(options[0].disabled)
        XCTAssertTrue(options[1].disabled)
    }
}
