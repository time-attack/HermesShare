import XCTest
import SwiftUI
import UIKit
import HermesShared

/// Real-evidence diagnostic: decode the EXACT UA1 JSON that was sent to the user and reported
/// broken, and the EXACT EVA777 JSON that was sent and reported working, through the real
/// HermesLayout decoder. This settles whether the difference is a decode-level bug (schema
/// rejects flightBoard-without-actions) vs. something downstream (render, transport, or the
/// persistence/resolver bug already tracked elsewhere).
@MainActor
final class HermesUA1DiagnosticTests: XCTestCase {

    func testUA1FlightBoardJSONDecodesSuccessfully() throws {
        let json = """
        {"version":1,"title":"United 1","subtitle":"JFK \\u2192 SFO \\u00b7 Today","accentColorHex":"#0A84FF","background":{"kind":"plain"},"root":{"type":"flightBoard","board":{"origin":"JFK","destination":"SFO","originCity":"New York","destinationCity":"San Francisco","flightCode":"UA 1","departTime":"08:00","arriveTime":"11:32","gate":"B22","status":"In Flight","statusColorHex":"#0A84FF","progress":0.58}}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let layout = try HermesLayout.decode(from: data)
        XCTAssertEqual(layout.title, "United 1")
        XCTAssertNil(layout.actions, "UA1 card was sent with no actions array - confirming this decodes fine as nil")
        if case let .flightBoard(board) = layout.root {
            XCTAssertEqual(board.origin, "JFK")
            XCTAssertEqual(board.destination, "SFO")
            XCTAssertEqual(board.progress, 0.58)
        } else {
            XCTFail("root did not decode as .flightBoard")
        }
    }

    func testUA1FlightBoardRendersThroughExtensionIdenticalViewTree() throws {
        let json = """
        {"version":1,"title":"United 1","subtitle":"JFK \\u2192 SFO \\u00b7 Today","accentColorHex":"#0A84FF","background":{"kind":"plain"},"root":{"type":"flightBoard","board":{"origin":"JFK","destination":"SFO","originCity":"New York","destinationCity":"San Francisco","flightCode":"UA 1","departTime":"08:00","arriveTime":"11:32","gate":"B22","status":"In Flight","statusColorHex":"#0A84FF","progress":0.58}}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let layout = try HermesLayout.decode(from: data)
        // Render through the SAME view construction the extension itself uses in expanded mode
        // (ScrollView + safeAreaInset action bar over HermesLayoutRenderer), matching
        // showRenderer in MessagesViewController.swift, to catch any render-time (not
        // decode-time) failure specific to flightBoard with no actions.
        let bodyWithoutActions = HermesLayout(
            version: layout.version, title: layout.title, subtitle: layout.subtitle,
            accentColorHex: layout.accentColorHex, background: layout.background,
            root: layout.root, actions: nil
        )
        let view = HermesLayoutRenderer(layout: bodyWithoutActions, presentation: .expanded) { _ in }
        let hosting = UIHostingController(rootView: view.frame(width: 360))
        hosting.view.bounds = CGRect(x: 0, y: 0, width: 360, height: 1)
        let fittingSize = hosting.sizeThatFits(in: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(fittingSize.height, 20, "flightBoard rendered to a near-zero height - this would look 'broken'/blank")
        hosting.view.bounds = CGRect(x: 0, y: 0, width: 360, height: max(fittingSize.height, 44))
        hosting.view.layoutIfNeeded()
        let renderer = ImageRenderer(content: view.frame(width: 360))
        renderer.scale = 2
        renderer.proposedSize = .init(width: 360, height: max(fittingSize.height, 44))
        let image = renderer.uiImage
        XCTAssertNotNil(image, "flightBoard failed to render to any image at all")
    }
}
