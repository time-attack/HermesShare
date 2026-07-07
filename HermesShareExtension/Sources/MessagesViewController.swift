// MessagesViewController.swift
// The real native iMessage App Extension. `MSMessagesAppViewController` is the principal
// class (declared in Info.plist via NSExtensionPrincipalClass — no storyboard). It does two
// things:
//
//   1. COMPOSE: when the user opens HermesShare in the Messages app drawer, it shows a
//      gallery of sample HermesLayout cards. Tapping one inserts an MSMessage whose `url`
//      carries the layout as a base64url-encoded compact-JSON query item (the transport
//      documented in the README). A native MSMessageTemplateLayout gives the in-transcript
//      bubble its caption/subcaption chrome.
//
//   2. RENDER: when a HermesShare message is selected/opened in a transcript, it decodes the
//      embedded HermesLayout and renders it with the *same* shared `HermesLayoutRenderer` —
//      compact in the small bubble, expanded when tapped open. No code is downloaded or
//      compiled: the JSON only parameterizes the fixed native vocabulary.

import UIKit
import SwiftUI
import Messages
import HermesShared

final class MessagesViewController: MSMessagesAppViewController {

    /// Query item name that carries the base64url layout payload inside `MSMessage.url`.
    static let payloadQueryItem = "p"
    static let urlScheme = "hermesshare"
    static let urlHost = "card"

    private var currentChild: UIViewController?

    /// The message the user most recently EXPLICITLY tapped during this activation burst.
    /// `didSelect` is the only trustworthy "the user touched THIS card" signal; the
    /// `didTransition(to: .expanded)` that fires right after it carries no message and
    /// `conversation.selectedMessage` can still point at the PREVIOUSLY opened card at that
    /// moment — so didTransition must re-resolve from this, not from the stale selection.
    /// Cleared ONLY on resign — NOT in willBecomeActive: iOS doesn't guarantee
    /// didSelect-vs-willBecomeActive ordering on a launch-by-bubble-tap, and clearing on
    /// activation discarded a just-delivered tap and handed the render to the stale
    /// selection (the Photon fresh-card silent-substitution gap). The router mirrors this
    /// rule; this property only keeps the MSMessage itself for session reuse / re-snapshots.
    private var lastTappedMessage: MSMessage?

    /// Monotonic counter guarding the presentContent retry loop and the stale-selection
    /// recheck loop: each new lifecycle event bumps it, so a delayed retry/recheck scheduled
    /// for an older event can never clobber the render of a newer one.
    private var presentGeneration = 0

    /// All routing decisions (which card does this event render?) live in the tested
    /// HermesEventRouter/HermesCardResolver pair — never re-derive them ad hoc here.
    private let router = HermesEventRouter(resolver: HermesCardResolver(store: .shared))

    // MARK: - Debug logging (temporary, to diagnose selectedMessage.url delivery)

    private func debugLog(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)\n"
        NSLog("HermesShareDebug: %@", message)
        let dir: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.hermesshare.app")
            ?? (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
        guard let dir else { return }
        let logURL = dir.appendingPathComponent("hermesshare-debug.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    // MARK: - Lifecycle / conversation events

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        // NOTE: deliberately does NOT clear lastTappedMessage. On a launch-by-bubble-tap,
        // didSelect can be delivered BEFORE willBecomeActive; the old clear here discarded
        // that tap and rendered from conversation.selectedMessage — which can still point
        // at the card that was open BEFORE the tapped (Photon-delivered, never-cached)
        // message existed. willResignActive is the only place taps go stale.
        presentGeneration += 1
        // Cache while the URL is still present — before iOS strips it on warm re-taps.
        if let selected = conversation.selectedMessage, let layout = Self.layout(from: selected) {
            HermesLayoutSessionCache.store(layout: layout, for: selected.session)
        }
        debugLog("EVENT willBecomeActive gen=\(presentGeneration) build=\(HermesBuildInfo.stamp) — lastTappedSession=\(HermesLayoutSessionCache.key(for: lastTappedMessage?.session) ?? "nil"), selectedMessage.url=\(conversation.selectedMessage?.url?.absoluteString.prefix(60) ?? "nil"), selectedSession=\(HermesLayoutSessionCache.key(for: conversation.selectedMessage?.session) ?? "nil")")
        let decision = router.willBecomeActive(selected: snapshot(of: conversation.selectedMessage))
        apply(decision, event: "willBecomeActive", conversation: conversation,
              style: presentationStyle, tappedMessage: lastTappedMessage)
    }

    override func willResignActive(with conversation: MSConversation) {
        super.willResignActive(with: conversation)
        debugLog("EVENT willResignActive — clearing lastTappedMessage (was session=\(HermesLayoutSessionCache.key(for: lastTappedMessage?.session) ?? "nil"))")
        lastTappedMessage = nil
        router.willResignActive()
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        guard let conversation = activeConversation else {
            debugLog("EVENT didTransition — no activeConversation")
            return
        }
        presentGeneration += 1
        // CRITICAL: didTransition fires right after didSelect on every warm tap, with
        // conversation.selectedMessage possibly still pointing at the PREVIOUSLY opened card.
        // Re-resolving from the stale selection here is exactly what kept re-rendering the
        // first-opened card over every newly tapped one (the bug the first fix missed —
        // it corrected didSelect but left this path routing through the stale selection).
        // The remembered tapped message must keep winning through the transition.
        debugLog("EVENT didTransition gen=\(presentGeneration) style=\(presentationStyle.rawValue) — lastTappedSession=\(HermesLayoutSessionCache.key(for: lastTappedMessage?.session) ?? "nil"), selectedMessage.url=\(conversation.selectedMessage?.url?.absoluteString.prefix(60) ?? "nil"), selectedSession=\(HermesLayoutSessionCache.key(for: conversation.selectedMessage?.session) ?? "nil")")
        let decision = router.didTransition(selected: snapshot(of: conversation.selectedMessage))
        apply(decision, event: "didTransition", conversation: conversation,
              style: presentationStyle, tappedMessage: lastTappedMessage)
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        lastTappedMessage = message
        presentGeneration += 1
        if let layout = Self.layout(from: message) {
            HermesLayoutSessionCache.store(layout: layout, for: message.session)
        }
        debugLog("EVENT didSelect gen=\(presentGeneration) — message.url=\(message.url?.absoluteString.prefix(60) ?? "nil"), tappedSession=\(HermesLayoutSessionCache.key(for: message.session) ?? "nil"), selectedSession=\(HermesLayoutSessionCache.key(for: conversation.selectedMessage?.session) ?? "nil")")
        let decision = router.didSelect(tapped: snapshot(of: message)!,
                                        selected: snapshot(of: conversation.selectedMessage))
        apply(decision, event: "didSelect", conversation: conversation,
              style: presentationStyle, tappedMessage: message)
    }

    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        super.didReceive(message, conversation: conversation)
        // Cache incoming cards the moment they arrive (while their URL is still present),
        // so a later nil-url selection of this message can still render from cache.
        if let layout = Self.layout(from: message) {
            HermesLayoutSessionCache.store(layout: layout, for: message.session)
            debugLog("didReceive — cached layout '\(layout.title ?? "untitled")' for \(HermesLayoutSessionCache.key(for: message.session) ?? "nil")")
        }
        // Round 7 (warm second-card gap): tell the router this session arrived DURING the
        // activation. A later selection of it outranks the tap remembered from an earlier
        // card — the message didn't exist when that tap happened, so the tap-priority
        // rule (built for selections lagging toward OLDER cards) must not pin the screen.
        // Also arm rechecks now: if the user taps this new bubble and iOS delivers no
        // didSelect (only a selection change), one of these catches it.
        let arrivedKey = HermesLayoutSessionCache.key(for: message.session)
        router.didReceive(sessionKey: arrivedKey)
        debugLog("didReceive — arrival noted for \(arrivedKey ?? "nil"), receivedThisActivation=\(router.sessionsReceivedThisActivation.map { String($0.suffix(8)) })")
        scheduleSelectionRechecks(afterEvent: "didReceive", generation: presentGeneration)
    }

    // MARK: - Content routing

    /// Decide what to show: a received HermesShare card, or the compose gallery.
    ///
    /// REAL BUGS this handles (both confirmed via the on-device debug log, iOS 26):
    ///
    /// 1. Warm-tap nil URL: tapping a HermesShare bubble while the extension is warm
    ///    delivers an MSMessage whose `url` is nil — and `conversation.selectedMessage?.url`
    ///    is nil too — even though the very same message had a full URL in `willBecomeActive`
    ///    moments earlier. Recovery: every decoded/composed layout is cached in the app group
    ///    keyed by the message's session UUID (stable across warm re-taps, verified in the
    ///    log: same UUID through different MSSession instances), plus a brief decode retry
    ///    in case Messages materializes the URL lazily.
    ///
    /// 2. Stale selection: on warm taps `conversation.selectedMessage` can still point at
    ///    the PREVIOUSLY opened card. The old `selectedMessage ?? tappedMessage` priority
    ///    therefore keyed the cache lookup off the wrong session and routed every tap to
    ///    whatever card was opened first. `didSelect`'s message is the one the user actually
    ///    touched — it must win. `selectedMessage` is only consulted as a decode source when
    ///    it provably belongs to the same session as the tapped message.
    ///
    /// If a tapped card can't be resolved at all, we show an explicit "couldn't load" state.
    /// NEVER a different cached card: silently substituting content is worse than failing,
    /// because the user interacts with card A's state believing it is card B.
    private func snapshot(of message: MSMessage?) -> HermesMessageSnapshot? {
        message.map {
            HermesMessageSnapshot(sessionKey: HermesLayoutSessionCache.key(for: $0.session),
                                  layout: Self.layout(from: $0),
                                  hadURL: $0.url != nil)
        }
    }

    /// Render whatever the router decided, then arm the two correction loops:
    /// the unresolved retry (URL can materialize late) and — for renders decided without
    /// an explicit tap — the stale-selection recheck (the Photon delivery gap: on a
    /// launch-by-tap of a fresh, never-cached message, conversation.selectedMessage can
    /// momentarily still point at the previously opened card).
    private func apply(
        _ decision: HermesEventRouter.Decision,
        event: String,
        conversation: MSConversation,
        style: MSMessagesAppPresentationStyle,
        tappedMessage: MSMessage?,
        attempt: Int = 0
    ) {
        guard let resolution = decision.resolution else { return }

        // If the router dethroned a stale tap (warm second-card rule), drop our MSMessage
        // copy too — keeping it would re-inject the stale tap through the retry path and
        // hand its session to replies composed from a DIFFERENT card.
        if router.tappedThisActivation == nil, lastTappedMessage != nil {
            debugLog("presentContent[\(event)] router dropped the remembered tap (stale vs newer arrival) — clearing lastTappedMessage (was session=\(HermesLayoutSessionCache.key(for: lastTappedMessage?.session) ?? "nil"))")
            lastTappedMessage = nil
        }

        // Forensic detail: exact keys in play, every key currently in the store, and which
        // path won — enough to catch any future session-matching bug from the log alone.
        debugLog("presentContent[\(event)] gen=\(presentGeneration) attempt=\(attempt) — routerTappedKey=\(router.tappedThisActivation?.sessionKey ?? "nil"), renderedKey=\(router.renderedSessionKey ?? "nil"), receivedThisActivation=\(router.sessionsReceivedThisActivation.map { String($0.suffix(8)) }), storeKeys=\(HermesLayoutStore.shared.indexedKeys().map { String($0.suffix(8)) })")

        switch resolution {
        case .layout(let layout, let sessionKey, let source):
            debugLog("presentContent[\(event)] RENDER '\(layout.title ?? "untitled")' via \(source.rawValue), session=\(sessionKey ?? "nil")")
            // The session handed to the renderer decides which bubble an action-reply
            // updates and which cache entry it overwrites — it must MATCH the rendered
            // card, not default to the last tapped message (which can be a different,
            // older card when this render was decided from the selection). No match →
            // nil, and replies get a fresh session rather than corrupting another card's.
            let session = [tappedMessage, conversation.selectedMessage]
                .compactMap { $0?.session }
                .first { HermesLayoutSessionCache.key(for: $0) == sessionKey && sessionKey != nil }
            if session == nil {
                debugLog("presentContent[\(event)] no in-hand MSSession matches rendered session \(sessionKey ?? "nil") — replies from this render will use a fresh session")
            }
            showRenderer(layout: layout, style: style, conversation: conversation, sourceSession: session)

        case .compose:
            debugLog("presentContent[\(event)] RENDER compose/empty state")
            showComposeGallery(conversation: conversation)

        case .unresolved(let diagnostics):
            // Retry briefly in case Messages materializes the URL late. Leave whatever is on
            // screen untouched while waiting — never render a guess. A newer lifecycle event
            // (fresh tap, transition, activation) bumps presentGeneration and voids the retry.
            if attempt < 3 {
                let generation = presentGeneration
                debugLog("presentContent[\(event)] UNRESOLVED session=\(diagnostics.sessionKey ?? "nil") — retry \(attempt + 1)/3 scheduled (gen=\(generation))")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, let conv = self.activeConversation else { return }
                    guard self.presentGeneration == generation else {
                        self.debugLog("presentContent retry dropped — generation moved on (\(generation) → \(self.presentGeneration))")
                        return
                    }
                    // Re-snapshot: the same message, whose URL may have appeared by now.
                    // But NEVER re-inject a tap the router has since dropped as stale
                    // (warm second-card rule) — retry(tapped:) would re-enthrone it.
                    let tappedForRetry = self.router.tappedThisActivation != nil ? tappedMessage : nil
                    let retryDecision = self.router.retry(tapped: self.snapshot(of: tappedForRetry),
                                                          selected: self.snapshot(of: conv.selectedMessage))
                    self.apply(retryDecision, event: event, conversation: conv,
                               style: self.presentationStyle, tappedMessage: tappedMessage,
                               attempt: attempt + 1)
                }
                return
            }

            // Exhausted: this exact card is unresolvable right now. Render the diagnostic
            // failure view — NEVER a different cached card — and write the exact same report
            // lines to the on-device debug log so screen and log always agree.
            let failureView = HermesCardFailureView(
                diagnostics: diagnostics,
                urlRetriesExhausted: attempt + 1,
                cachedSessionKeys: HermesLayoutStore.shared.indexedKeys()
            )
            debugLog("presentContent[\(event)] UNRESOLVED after \(attempt + 1) attempts — showing diagnostic failure view:")
            for line in failureView.reportLines {
                debugLog("  FAILURE-REPORT \(line)")
            }
            embed(UIHostingController(rootView: AnyView(failureView)))
        }

        if decision.selectionProvisional {
            scheduleSelectionRechecks(afterEvent: event, generation: presentGeneration)
        }
    }

    /// The correction loop for the Photon cold-first-tap gap: a render decided without an
    /// explicit didSelect trusted `conversation.selectedMessage`, which can be momentarily
    /// stale (still the previously opened card) when a fresh externally-delivered message
    /// is tapped. Re-read the LIVE selection a few times; if it turns out to identify a
    /// different session than what was rendered, re-route (never-substitute rules intact —
    /// an unresolvable late selection produces the failure view, not a guess).
    private func scheduleSelectionRechecks(afterEvent event: String, generation: Int) {
        for delay in [0.5, 1.2, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let conv = self.activeConversation else { return }
                guard self.presentGeneration == generation else { return }
                let previouslyRenderedKey = self.router.renderedSessionKey
                let decision = self.router.selectionRecheck(selected: self.snapshot(of: conv.selectedMessage))
                guard decision.resolution != nil else { return }
                self.presentGeneration += 1
                self.debugLog("EVENT selectionRecheck(after \(event), +\(delay)s) gen=\(self.presentGeneration) — live selection moved to session=\(HermesLayoutSessionCache.key(for: conv.selectedMessage?.session) ?? "nil"), re-routing (was renderedKey=\(previouslyRenderedKey ?? "nil"))")
                self.apply(decision, event: "selectionRecheck", conversation: conv,
                           style: self.presentationStyle, tappedMessage: nil)
            }
        }
    }

    private func showRenderer(layout: HermesLayout, style: MSMessagesAppPresentationStyle, conversation: MSConversation, sourceSession: MSSession?) {
        let presentation: HermesPresentation = (style == .expanded) ? .expanded : .compact
        // The primary CTA (layout.actions) must always be visible without scrolling. Use
        // `.safeAreaInset(edge: .bottom)` — the standard SwiftUI idiom for "pinned bar under
        // scrolling content" — rather than a raw VStack{ScrollView; footer}, which rendered a
        // blank white screen when embedded via UIHostingController (the VStack's height wasn't
        // resolving correctly against the extension's edge-pinned autoresizing constraints).
        let bodyWithoutActions = HermesLayout(
            version: layout.version, title: layout.title, subtitle: layout.subtitle,
            accentColorHex: layout.accentColorHex, background: layout.background,
            root: layout.root, actions: nil
        )
        let actions = layout.actions ?? []
        let view = ScrollView {
            HermesLayoutRenderer(layout: bodyWithoutActions, presentation: presentation) { [weak self] action in
                self?.handle(action, sourceLayout: layout, sourceSession: sourceSession, conversation: conversation)
            }
            .padding(presentation == .compact ? 0 : 8)
        }
        .safeAreaInset(edge: .bottom) {
            if !actions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(actions, id: \.id) { action in
                        HermesPrimaryCTA(label: action.label, systemImage: action.systemImage) { [weak self] in
                            self?.handle(action, sourceLayout: layout, sourceSession: sourceSession, conversation: conversation)
                        }
                    }
                }
                .padding(12)
                .background(.regularMaterial)
            }
        }
        // Atmosphere cards extend their dark canvas past the renderer's bounds (scroll
        // overshoot, safe areas) instead of flashing grouped-gray around a dark scene.
        .background(HermesLayoutRenderer.canvasColor(for: layout))
        // The pinned bar lives outside HermesLayoutRenderer, so it must be tinted with the
        // card's accent explicitly (otherwise its CTA renders default blue on every card).
        // The accent environment rides along so the CTA can pick a legible label color.
        .tint(Color(hermesHex: layout.accentColorHex) ?? .accentColor)
        .environment(\.hermesAccent, Color(hermesHex: layout.accentColorHex) ?? .accentColor)
        embed(UIHostingController(rootView: view))
    }

    private func showComposeGallery(conversation: MSConversation) {
        // No hardcoded demo samples here on purpose — HermesShare is driven entirely by
        // Hermes/Photon sending real cards via the API, never by manually picking a sample
        // from inside Messages. This state only appears if the extension is opened without
        // a selected HermesShare message (e.g. tapped the app icon directly in the drawer).
        #if targetEnvironment(simulator) && DEBUG
        // Simulator-only test harness: lets automated UI tests insert real fixture cards
        // into the sim's Messages conversation so the full bubble-tap → didSelect →
        // expanded-render path can be exercised without a network sender.
        let gallery = DebugComposeGallery { [weak self] layout in
            self?.insert(layout: layout, into: conversation)
        }
        embed(UIHostingController(rootView: AnyView(gallery)))
        #else
        let empty = EmptyStateView()
        embed(UIHostingController(rootView: AnyView(empty)))
        #endif
    }

    // MARK: - Compose / insert

    private func insert(layout: HermesLayout, into conversation: MSConversation) {
        let message = Self.makeMessage(for: layout, session: MSSession())
        conversation.insert(message) { error in
            if let error { NSLog("HermesShare insert failed: \(error)") }
        }
        // Collapse back to the transcript so the composed bubble is visible.
        requestPresentationStyle(.compact)
    }

    /// Build an MSMessage whose URL embeds the layout, with native template-layout chrome.
    /// The session is passed explicitly by the caller: a reply must reuse the session of the
    /// card the user was actually interacting with (so it updates that bubble in place and
    /// its cache entry), NOT `conversation.selectedMessage?.session` — on warm taps the
    /// selected message can be stale and point at a completely different card.
    @MainActor
    static func makeMessage(for layout: HermesLayout, session: MSSession) -> MSMessage {
        let message = MSMessage(session: session)

        var components = URLComponents()
        components.scheme = urlScheme
        components.host = urlHost
        components.queryItems = [
            URLQueryItem(name: payloadQueryItem, value: (try? layout.base64URLPayload()) ?? "")
        ]
        message.url = components.url

        let template = MSMessageTemplateLayout()
        let caption = layout.title ?? "HermesShare"
        let thumb = CardThumbnailRenderer.image(for: layout)
        template.image = thumb
        if thumb != nil {
            // Real labels live in caption/subcaption. imageTitle is required when image is set
            // (spectrum-ts pairing) but Apple also renders imageTitle in a footer strip — use an
            // invisible placeholder so the title is not duplicated (device-confirmed 2026-07-07).
            template.caption = caption
            template.subcaption = layout.subtitle
            template.imageTitle = "\u{2060}"
        } else {
            template.caption = caption
            template.subcaption = layout.subtitle
        }
        message.layout = template
        message.summaryText = layout.title ?? "HermesShare card"
        // Cache at compose time: if this bubble is later selected with a nil url (see
        // presentContent), the renderer can recover the layout from the session cache.
        HermesLayoutSessionCache.store(layout: layout, for: session)
        return message
    }

    /// Decode the embedded HermesLayout from a received message, if present. The actual
    /// URL-shape parsing lives in HermesShared (`HermesLayout.decode(fromMessageURL:)`) so
    /// the exact wire shapes real senders produce — including Photon's https://…?p= form —
    /// are covered by package unit tests, not just exercised on-device.
    static func layout(from message: MSMessage?) -> HermesLayout? {
        guard let url = message?.url else { return nil }
        return HermesLayout.decode(fromMessageURL: url)
    }

    // MARK: - Actions

    /// An action does ONE of two things, decided by its `deepLinkURL` scheme — never both,
    /// so a card's CTA can't accidentally send a meaningless reply:
    ///
    ///   • `hermesshare://…` → a REPLY/commit action (GamePigeon-style): compose a genuine
    ///     reply MSMessage and insert it into the conversation. Use for choices, RSVPs,
    ///     "Mark all packed", "Remind me" — anything where "✓ <label>" is a real message back.
    ///   • `https://…` / `http://…` / any real app scheme (`spotify:`, `maps:`, `tel:`) → an
    ///     OPEN action: open the URL externally (launch the app / web), and DO NOT insert a
    ///     reply. This is how a display card offers "Open in Spotify" / "View in Maps" without
    ///     spamming the thread with a fake "✓ Open in Spotify" bubble — the exact bug this
    ///     split fixes.
    private func handle(_ action: HermesAction, sourceLayout: HermesLayout, sourceSession: MSSession?, conversation: MSConversation) {
        // Routing decision lives in the Shared package (HermesAction.insertsReply) so it's
        // unit-tested and both targets agree.
        if action.insertsReply {
            insertReply(for: action, sourceLayout: sourceLayout, sourceSession: sourceSession, conversation: conversation)
        } else {
            openDeepLink(action)
        }
    }

    private func insertReply(for action: HermesAction, sourceLayout: HermesLayout, sourceSession: MSSession?, conversation: MSConversation) {
        let reply = HermesLayout(
            version: 1,
            title: "✓ \(action.label)",
            subtitle: sourceLayout.title,
            accentColorHex: sourceLayout.accentColorHex,
            background: .init(kind: .plain),
            root: .vstack(spacing: 8, alignment: "leading", children: [
                .hstack(spacing: 8, alignment: "center", children: [
                    .icon(systemName: action.systemImage ?? "checkmark.circle.fill", sizePt: 22, colorHex: sourceLayout.accentColorHex),
                    .text(action.label, style: .init(role: .headline, weight: .semibold))
                ]),
                .text("Tapped from \(sourceLayout.title ?? "HermesShare")", style: .init(role: .footnote, colorHex: "#8E8E93"))
            ])
        )
        // Reuse the source card's session so the reply updates that card's bubble in place.
        let message = Self.makeMessage(for: reply, session: sourceSession ?? MSSession())
        conversation.insert(message) { [weak self] error in
            if let error {
                NSLog("HermesShare action-reply insert failed: \(error)")
                // Fall back to opening the deep link if the insert genuinely failed.
                self?.openDeepLink(action)
            }
        }
        requestPresentationStyle(.compact)
    }

    private func openDeepLink(_ action: HermesAction) {
        guard let url = URL(string: action.deepLinkURL) else { return }
        // From inside an app extension we can't call UIApplication.shared.open directly, so we
        // walk the responder chain to the shared application's open(_:).
        // TODO(hermes-roundtrip): also deliver this tap to the Hermes/Photon webhook (see README)
        // so Hermes can react server-side to which action the user picked, not just show a reply
        // bubble locally.
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let r = responder {
            if r.responds(to: selector) {
                _ = r.perform(selector, with: url)
                break
            }
            responder = r.next
        }
    }

    // MARK: - Child VC embedding

    private func embed(_ child: UIViewController) {
        currentChild?.willMove(toParent: nil)
        currentChild?.view.removeFromSuperview()
        currentChild?.removeFromParent()

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        child.didMove(toParent: self)
        currentChild = child
    }
}

// MARK: - Card-unavailable state
//
// Shown ONLY when a tapped card cannot be resolved (nil-url delivery, no cache entry, decode
// retries exhausted). Deliberately not a substitute card: showing a different cached card
// here is actively misleading — the user would interact with card A's state believing it is
// card B. Backing out to the transcript and re-tapping the bubble re-delivers the URL.

private struct CardUnavailableView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Couldn't load this card")
                .font(.headline)
            Text("Messages didn't hand over this card's contents. Close it and tap the bubble again.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Empty state (no gallery — HermesShare is driven by the API, not manual compose)

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Waiting for a card")
                .font(.headline)
            Text("HermesShare cards are sent by Hermes — nothing to compose here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            // Build stamp: any screenshot of this state identifies the installed build
            // (stale installs have repeatedly masqueraded as regressions).
            Text("build \(HermesBuildInfo.stamp)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#if targetEnvironment(simulator) && DEBUG
/// Simulator-only compose gallery: inserts fixture cards (the exact JSON documents that went
/// blank on the physical device) so the received-message render path can be UI-tested.
private struct DebugComposeGallery: View {
    let onInsert: (HermesLayout) -> Void

    private var fixtures: [(String, HermesLayout)] {
        // v3 showcase first — the interactive optionPicker card is the one UI tests drive.
        var out: [(String, HermesLayout)] = [("Trip Day Plan", HermesSampleLayouts.tripDayPlan)]
        // sent_flight / sent_health are the EXACT documents the user reports "falling back"
        // on-device (flightBoard + gaugeCluster); sent_dinner is the working comparison card.
        for name in ["sent_flight", "sent_health", "sent_dinner",
                     "failing_packing_list", "failing_ramen", "failing_preflight"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let layout = try? HermesLayout.decode(from: data) {
                out.append((name, layout))
            }
        }
        out.append(contentsOf: HermesSampleLayouts.all.map { ($0.name, $0.layout) })
        return out
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("DEBUG compose").font(.headline)
                    .accessibilityIdentifier("hermes-debug-compose-title")
                ForEach(fixtures, id: \.0) { name, layout in
                    Button(name) { onInsert(layout) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("hermes-compose-\(Self.slug(name))")
                }
            }
            .padding()
        }
    }

    private static func slug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
#endif

// MARK: - Bubble thumbnail

/// Renders a small snapshot of the card for the MSMessageTemplateLayout image slot, so the
/// in-transcript bubble shows a native preview even before the message is tapped open.
enum CardThumbnailRenderer {
    @MainActor
    static func image(for layout: HermesLayout) -> UIImage? {
        let view = BubbleThumbnailView(layout: layout)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}
