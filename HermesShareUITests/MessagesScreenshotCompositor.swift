// MessagesScreenshotCompositor.swift
// Composites HermesShare card renders onto real Messages.app Simulator screenshots so
// README shots show authentic iMessage chrome (nav bar, compose bar, transcript).

import XCTest
import SwiftUI
import UIKit
import HermesShared

@MainActor
final class MessagesScreenshotCompositor: XCTestCase {

    private lazy var outDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/screenshots/imessage", isDirectory: true)
    }()

    private struct CardSpec {
        let slug: String
        let layout: HermesLayout
        let caption: String
        let subcaption: String?
    }

    private var cards: [CardSpec] {
        [
            CardSpec(slug: "courier-journey", layout: HermesSampleLayouts.courierJourney,
                     caption: "Your package is close", subcaption: "Order #HS-48213 · UPS Ground"),
            CardSpec(slug: "trip-day-plan", layout: HermesSampleLayouts.tripDayPlan,
                     caption: "Osaka — Day 2", subcaption: "Tuesday plan · pick tonight's dinner"),
            CardSpec(slug: "package-tracking", layout: HermesSampleLayouts.packageTracking,
                     caption: "Package Out for Delivery", subcaption: "Order #HS-48213"),
            CardSpec(slug: "sent-flight", layout: loadFixture("sent_flight"),
                     caption: "BR 26 · TPE → SFO", subcaption: "Boarding soon — Gate G93"),
            CardSpec(slug: "sent-health", layout: loadFixture("sent_health"),
                     caption: "System Health", subcaption: "hermes-agent fleet · last 15 min")
        ]
    }

    func testCompositeMessagesScreenshots() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        messages.launch()
        sleep(2)
        openConversation(in: messages)
        dismissKeyboard(in: messages)
        sleep(1)

        let frame = messages.screenshot().image
        let framePath = outDir.appendingPathComponent("_messages-frame.png")
        try frame.pngData()?.write(to: framePath)

        for (index, card) in cards.enumerated() {
            let yOffset = 150 + index * 8 // slight stagger for realism when multiple shown
            let transcript = compositeTranscript(frame: frame, card: card, bubbleTop: CGFloat(yOffset))
            try transcript.pngData()?.write(to: outDir.appendingPathComponent("transcript-\(card.slug).png"))

            let expanded = compositeExpanded(frame: frame, card: card)
            try expanded.pngData()?.write(to: outDir.appendingPathComponent("expanded-\(card.slug).png"))
        }
    }

    // MARK: - Messages navigation

    private func openConversation(in messages: XCUIApplication) {
        if messages.staticTexts["+1 (888) 555-1212"].waitForExistence(timeout: 4) {
            messages.staticTexts["+1 (888) 555-1212"].tap()
        } else if messages.tables.cells.firstMatch.waitForExistence(timeout: 4) {
            messages.tables.cells.firstMatch.tap()
        }
        sleep(1)
    }

    private func dismissKeyboard(in messages: XCUIApplication) {
        if messages.keyboards.count > 0 {
            messages.buttons["Return"].firstMatch.tap()
            sleep(1)
        }
        if messages.keyboards.count > 0 {
            messages.swipeDown()
            sleep(1)
        }
        messages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        sleep(1)
    }

    // MARK: - Compositing

    private func compositeTranscript(frame: UIImage, card: CardSpec, bubbleTop: CGFloat) -> UIImage {
        let size = frame.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            frame.draw(at: .zero)

            let bubbleWidth = size.width * 0.72
            let bubbleX = size.width - bubbleWidth - 16
            let thumbHeight = bubbleWidth * 0.56
            let captionHeight: CGFloat = 44
            let subcaptionHeight: CGFloat = card.subcaption == nil ? 0 : 28
            let bubbleHeight = thumbHeight + captionHeight + subcaptionHeight + 16
            let bubbleRect = CGRect(x: bubbleX, y: bubbleTop, width: bubbleWidth, height: bubbleHeight)

            let path = UIBezierPath(roundedRect: bubbleRect, cornerRadius: 18)
            UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1).setFill()
            path.fill()

            if let thumb = bubbleThumbnail(for: card.layout) {
                let thumbRect = CGRect(x: bubbleRect.minX + 8, y: bubbleRect.minY + 8,
                                       width: bubbleRect.width - 16, height: thumbHeight - 8)
                thumb.draw(in: thumbRect)
            }

            let captionY = bubbleRect.minY + thumbHeight + 4
            let captionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.label
            ]
            card.caption.draw(in: CGRect(x: bubbleRect.minX + 12, y: captionY,
                                         width: bubbleRect.width - 24, height: 22),
                              withAttributes: captionAttrs)

            if let sub = card.subcaption {
                let subAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                sub.draw(in: CGRect(x: bubbleRect.minX + 12, y: captionY + 22,
                                    width: bubbleRect.width - 24, height: 20),
                         withAttributes: subAttrs)
            }
        }
    }

    private func compositeExpanded(frame: UIImage, card: CardSpec) -> UIImage {
        let size = frame.size
        let headerHeight: CGFloat = 130
        let cardRender = extensionCardImage(for: card.layout)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            // Real Messages nav + contact header from Simulator.
            frame.draw(at: .zero, blendMode: .normal, alpha: 1)

            // Dim transcript behind the extension sheet slightly.
            UIColor.black.withAlphaComponent(0.06).setFill()
            UIRectFill(CGRect(x: 0, y: headerHeight, width: size.width, height: size.height - headerHeight))

            // Expanded card from the same renderer the extension uses.
            let cardArea = CGRect(x: 0, y: headerHeight, width: size.width, height: size.height - headerHeight)
            cardRender.draw(in: cardArea)
        }
    }

    private func bubbleThumbnail(for layout: HermesLayout) -> UIImage? {
        let view = BubbleThumbnailView(layout: layout)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }

    private func extensionCardImage(for layout: HermesLayout) -> UIImage {
        let bodyWithoutActions = HermesLayout(
            version: layout.version, title: layout.title, subtitle: layout.subtitle,
            accentColorHex: layout.accentColorHex, background: layout.background,
            root: layout.root, actions: nil
        )
        let actions = layout.actions ?? []
        let view = ScrollView {
            HermesLayoutRenderer(layout: bodyWithoutActions, presentation: .expanded) { _ in }
                .padding(8)
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

        let hosting = UIHostingController(rootView: AnyView(view))
        let size = CGSize(width: 402, height: 750)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = hosting
        window.isHidden = false
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            hosting.view.layer.render(in: ctx.cgContext)
        }
    }

    private func loadFixture(_ name: String) -> HermesLayout {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Shared/Tests/HermesSharedTests/Fixtures/\(name).json")
        guard let data = try? Data(contentsOf: url),
              let layout = try? HermesLayout.decode(from: data) else {
            return HermesSampleLayouts.packageTracking
        }
        return layout
    }
}
