// MessagesScreenshotTests.swift
// Drives Messages.app in the Simulator, inserts HermesShare cards via the DEBUG compose
// gallery, and writes PNGs to docs/screenshots/imessage/ for the README.

import XCTest

final class MessagesScreenshotTests: XCTestCase {

    private let messagesBundleID = "com.apple.MobileSMS"
    private lazy var outDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/screenshots/imessage", isDirectory: true)
    }()

    private struct CardShot {
        let composeID: String
        let transcriptFilename: String
        let expandedFilename: String
        /// Caption text on the inserted bubble — used to re-open it for the expanded shot.
        let bubbleCaption: String
    }

    private let cards: [CardShot] = [
        CardShot(composeID: "hermes-compose-courier-journey",
                 transcriptFilename: "transcript-courier-journey.png",
                 expandedFilename: "expanded-courier-journey.png",
                 bubbleCaption: "Your package is close"),
        CardShot(composeID: "hermes-compose-trip-day-plan",
                 transcriptFilename: "transcript-trip-day-plan.png",
                 expandedFilename: "expanded-trip-day-plan.png",
                 bubbleCaption: "Osaka — Day 2"),
        CardShot(composeID: "hermes-compose-sent_flight",
                 transcriptFilename: "transcript-sent-flight.png",
                 expandedFilename: "expanded-sent-flight.png",
                 bubbleCaption: "BR 26 · TPE → SFO"),
        CardShot(composeID: "hermes-compose-package-tracking",
                 transcriptFilename: "transcript-package-tracking.png",
                 expandedFilename: "expanded-package-tracking.png",
                 bubbleCaption: "Package Out for Delivery"),
        CardShot(composeID: "hermes-compose-sent_health",
                 transcriptFilename: "transcript-sent-health.png",
                 expandedFilename: "expanded-sent-health.png",
                 bubbleCaption: "System Health")
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    /// One-shot: `./scripts/capture_readme_screenshots.sh` or
    /// `xcodebuild test -only-testing:HermesShareUITests/MessagesScreenshotTests/testCaptureMessagesScreenshots`
    func testCaptureMessagesScreenshots() throws {
        let messages = XCUIApplication(bundleIdentifier: messagesBundleID)
        messages.launch()

        dismissSystemAlerts(in: messages)
        openFirstConversation(in: messages)

        for card in cards {
            try insertAndCapture(card, in: messages)
        }
    }

    // MARK: - Flow

    private func insertAndCapture(_ card: CardShot, in messages: XCUIApplication) throws {
        openHermesShareExtension(in: messages)

        let composeButton = messages.buttons[card.composeID]
        XCTAssertTrue(composeButton.waitForExistence(timeout: 12),
                      "Compose button \(card.composeID) not found — is the DEBUG gallery visible?")
        composeButton.tap()

        // insert() calls requestPresentationStyle(.compact) — wait for the bubble in transcript.
        let bubble = messages.staticTexts[card.bubbleCaption].firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 10),
                      "Bubble caption '\(card.bubbleCaption)' not visible in transcript")
        sleep(1)
        saveScreenshot(from: messages, named: card.transcriptFilename)

        bubble.tap()
        sleep(2)
        saveScreenshot(from: messages, named: card.expandedFilename)

        // Collapse back to transcript for the next card.
        if messages.buttons["Done"].waitForExistence(timeout: 2) {
            messages.buttons["Done"].tap()
        } else if messages.navigationBars.buttons.firstMatch.waitForExistence(timeout: 2) {
            messages.navigationBars.buttons.firstMatch.tap()
        }
        sleep(1)
    }

    private func openHermesShareExtension(in messages: XCUIApplication) {
        dismissSystemAlerts(in: messages)
        focusComposeField(in: messages)

        let add = messages.buttons["add"]
        XCTAssertTrue(add.waitForExistence(timeout: 8), "Messages '+' compose button not found")

        // iOS 18+: iMessage apps live under + → More (or the App Store icon beside +).
        add.tap()
        sleep(2)
        for label in ["More", "App Store", "Store"] {
            let b = messages.buttons[label]
            if b.waitForExistence(timeout: 2) { b.tap(); sleep(2); break }
        }
        if !tapHermesShareIcon(in: messages) {
            add.coordinate(withNormalizedOffset: CGVector(dx: 1.3, dy: 0.5)).tap()
            sleep(2)
        }
        var opened = tapHermesShareIcon(in: messages)
        if !opened {
            messages.swipeLeft()
            sleep(1)
            opened = tapHermesShareIcon(in: messages)
        }
        XCTAssertTrue(opened, "HermesShare extension icon not found in the Messages app drawer")

        let galleryVisible = messages.otherElements["hermes-debug-compose-title"].waitForExistence(timeout: 10)
            || messages.staticTexts["DEBUG compose"].waitForExistence(timeout: 2)
        XCTAssertTrue(galleryVisible,
                      "DEBUG compose gallery did not appear — open HermesShare from the drawer without a card selected")
    }

    private func focusComposeField(in messages: XCUIApplication) {
        if messages.textFields.firstMatch.waitForExistence(timeout: 2) {
            messages.textFields.firstMatch.tap()
        } else if messages.textViews.firstMatch.waitForExistence(timeout: 2) {
            messages.textViews.firstMatch.tap()
        } else {
            messages.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88)).tap()
        }
        sleep(1)
        // Hide keyboard so the app drawer strip stays visible above it.
        if messages.keyboards.count > 0 {
            messages.buttons["Return"].firstMatch.tap()
            sleep(1)
        }
    }

    private func tapHermesShareIcon(in messages: XCUIApplication) -> Bool {
        let hermes = messages.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Hermes' OR identifier CONTAINS[c] 'Hermes'"))
            .firstMatch
        if hermes.waitForExistence(timeout: 3) {
            hermes.tap()
            return true
        }
        return false
    }

    private func openFirstConversation(in messages: XCUIApplication) {
        dismissSystemAlerts(in: messages)

        if messages.navigationBars["Messages"].waitForExistence(timeout: 3) {
            if messages.tables.cells.firstMatch.waitForExistence(timeout: 4) {
                messages.tables.cells.firstMatch.tap()
                sleep(1)
                return
            }
            if messages.staticTexts["+1 (888) 555-1212"].waitForExistence(timeout: 4) {
                messages.staticTexts["+1 (888) 555-1212"].tap()
                sleep(1)
                return
            }
            if messages.collectionViews.cells.firstMatch.waitForExistence(timeout: 4) {
                messages.collectionViews.cells.firstMatch.tap()
                sleep(1)
                return
            }
        }

        if messages.buttons["BackButton"].waitForExistence(timeout: 2)
            || messages.buttons["Messages"].waitForExistence(timeout: 1) {
            return
        }

        XCTFail("Could not open a Messages conversation — seed the Simulator with at least one thread")
    }

    private func dismissSystemAlerts(in app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 1) {
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap() }
            else if alert.buttons.element(boundBy: 0).exists { alert.buttons.element(boundBy: 0).tap() }
        }
    }

    private func saveScreenshot(from app: XCUIApplication, named filename: String) {
        let shot = app.screenshot()
        let url = outDir.appendingPathComponent(filename)
        do {
            try shot.pngRepresentation.write(to: url)
        } catch {
            XCTFail("Failed writing \(filename): \(error)")
        }
    }
}
