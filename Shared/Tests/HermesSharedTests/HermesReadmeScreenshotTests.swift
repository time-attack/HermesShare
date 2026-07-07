// HermesReadmeScreenshotTests.swift
// Generates curated PNGs for the README gallery. Runs on the iOS Simulator via
// `xcodebuild test` — same UIHostingController render path as the iMessage extension.

import XCTest
import SwiftUI
import UIKit
import HermesShared

@MainActor
final class HermesReadmeScreenshotTests: XCTestCase {

    private let outDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/screenshots", isDirectory: true)

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
        .tint(Color(hermesHex: layout.accentColorHex) ?? .accentColor)
        .environment(\.hermesAccent, Color(hermesHex: layout.accentColorHex) ?? .accentColor)
    }

    private func writePNG(
        layout: HermesLayout,
        filename: String,
        presentation: HermesPresentation = .expanded,
        size: CGSize = CGSize(width: 390, height: 780),
        interfaceStyle: UIUserInterfaceStyle = .light,
        settle: TimeInterval = 0.35
    ) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let hosting = UIHostingController(rootView: AnyView(extensionStyleView(for: layout, presentation: presentation)))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = interfaceStyle
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            hosting.view.layer.render(in: ctx.cgContext)
        }
        let url = outDir.appendingPathComponent(filename)
        try image.pngData()?.write(to: url)
    }

    private func writeBubblePNG(layout: HermesLayout, filename: String) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let view = BubbleThumbnailView(layout: layout)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("bubble thumbnail nil for \(filename)")
            return
        }
        try data.write(to: outDir.appendingPathComponent(filename))
    }

    private func loadFixture(_ name: String) throws -> HermesLayout {
        guard let url = TestFixtures.url(named: name) else {
            throw XCTSkip("fixture \(name).json missing")
        }
        return try HermesLayout.decode(from: Data(contentsOf: url))
    }

    private func slug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// Writes compact JSON for every built-in sample + key sent fixtures — used by
    /// `scripts/send_all_examples_photon.sh`.
    func testDumpSampleJSONsForPhoton() throws {
        let out = URL(fileURLWithPath: "/tmp/hermes-photon-batch")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        for (name, layout) in HermesSampleLayouts.all {
            let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
            let data = try layout.encoded(pretty: false)
            try data.write(to: out.appendingPathComponent("\(slug).json"))
        }
        for fixture in ["sent_flight", "sent_health", "sent_dinner",
                        "sent_spotify_ranking", "sent_kyoto_catalog",
                        "demo_picture_restaurants", "demo_picture_flights",
                        "demo_app_designs", "demo_collapsible_trip"] {
            let layout = try loadFixture(fixture)
            try layout.encoded(pretty: false).write(to: out.appendingPathComponent("\(fixture).json"))
        }
    }

    /// One-shot generator: `xcodebuild test -only-testing:HermesSharedTests/HermesReadmeScreenshotTests/testGenerateReadmeGallery`
    func testGenerateReadmeGallery() throws {
        // v5 scene heroes
        let v5 = ["Courier Journey", "Weather Tonight", "Concert Ticket", "Market Pulse", "Game Final"]
        for (name, layout) in HermesSampleLayouts.all where v5.contains(name) {
            try writePNG(layout: layout, filename: "card-\(slug(name)).png")
        }

        // Interactive + classic samples
        let classics = ["Trip Day Plan", "Package Tracking", "Stat Dashboard", "Map Preview",
                        "Seat Chart", "Quick Reply"]
        for (name, layout) in HermesSampleLayouts.all where classics.contains(name) {
            try writePNG(layout: layout, filename: "card-\(slug(name)).png")
        }

        // Real sent fixtures (flight board, health gauges, dinner vote)
        try writePNG(layout: try loadFixture("sent_flight"), filename: "card-sent-flight.png")
        try writePNG(layout: try loadFixture("sent_health"), filename: "card-sent-health.png")
        try writePNG(layout: try loadFixture("sent_dinner"), filename: "card-sent-dinner.png")
        try writePNG(layout: try loadFixture("sent_spotify_ranking"), filename: "card-spotify-ranking.png",
                     size: CGSize(width: 390, height: 900), settle: 3.0)
        try writePNG(layout: try loadFixture("sent_kyoto_catalog"), filename: "card-kyoto-catalog.png",
                     size: CGSize(width: 390, height: 1200), settle: 4.0)

        // Compact bubble previews (in-transcript chrome)
        let flight = try loadFixture("sent_flight")
        try writeBubblePNG(layout: flight, filename: "bubble-sent-flight.png")
        try writePNG(layout: flight, filename: "card-sent-flight-compact.png",
                     presentation: .compact, size: CGSize(width: 390, height: 320))

        // Debug harness JSON editor preview (sample layout in split editor)
        let editorLayout = HermesSampleLayouts.packageTracking
        let editorView = NavigationStack {
            VStack(spacing: 0) {
                Text("HermesShare · Debug").font(.headline).padding(8)
                HermesLayoutRenderer(layout: editorLayout, presentation: .expanded)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        let hosting = UIHostingController(rootView: AnyView(editorView))
        let size = CGSize(width: 390, height: 844)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in hosting.view.layer.render(in: ctx.cgContext) }
        try image.pngData()?.write(to: outDir.appendingPathComponent("card-debug-preview.png"))
    }
}
