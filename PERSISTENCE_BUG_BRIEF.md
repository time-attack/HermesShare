HermesShare — critical navigation/persistence bug, root cause already found, needs a real fix

## The bug (exact user report)
User taps a "seat select" card - works. Taps a different card ("system health") - it shows seat selection again, not system health. Goes back to seat selection, completes the interaction, sends a reply. It still shows seat selection afterward (a NEW seat selection state), not whatever card should show next. Every tap after the first effectively gets routed to the wrong card. User: "We need persistency between all of these stickers."

## Root cause - already identified by reading the code, do not re-diagnose from scratch
File: HermesShareExtension/Sources/MessagesViewController.swift, function presentContent (around line 102-141).

The real, exact bug is in the final fallback branch:

if let message, let latest = HermesLayoutSessionCache.latestLayout() {
    showRenderer(layout: latest, style: style, conversation: conversation)
}

HermesLayoutSessionCache.latestLayout() returns the MOST RECENTLY CACHED layout GLOBALLY, not the layout for the specific message/session the user actually tapped. This fallback exists because of an earlier, real bug: Messages frequently delivers didSelect/selectedMessage with url=nil even when the extension is warm (documented in the comment above presentContent, confirmed via on-device debug logs earlier this session - decoded layout? true then later nil for the same message). When that nil-url case hits and the per-session cache lookup (HermesLayoutSessionCache.layout(for: message.session)) also misses, the code falls back to showing whatever card was cached most recently across ALL sessions - which is exactly the "stuck on one card, everything routes to it" symptom the user is hitting, and explains why after completing an interaction and sending a reply, it shows a NEW instance of the SAME card type (the reply itself gets cached and becomes the new "latest").

## What needs to actually happen (the real fix, not a patch over the symptom)
1. Investigate WHY the per-session cache lookup is missing in the first place - HermesLayoutSessionCache.store is called at compose time (makeMessage) and receive time (didReceive), keyed by message.session. The bug is likely one of:
   - message.session is nil or inconsistent between when a card was cached and when it's later looked up (MSSession identity not being preserved/reused correctly across taps)
   - Multiple distinct cards are incorrectly sharing the same session, so they overwrite each other's cache entry
   - The session key derivation (HermesLayoutSessionCache.key(for:)) has a bug causing collisions
   Read HermesLayoutSessionCache's actual implementation (search the Shared/Sources/HermesShared directory or HermesShareExtension - find wherever it's defined) and trace the real cause with actual evidence (add debug logging if needed, pull the on-device log via: xcrun devicectl device copy from --device <UDID> --source "/Documents/hermesshare-debug.log" --domain-type appDataContainer --domain-identifier com.hermesshare.app.MessagesExtension --destination /tmp/out.log - check xcrun devicectl list devices first for the current UDID since it changes connection state often this session).
2. The "show latest cached card as a last-resort fallback" design is fundamentally wrong for a multi-card conversation - it will ALWAYS pick the wrong card whenever two or more different HermesShare cards exist in the same conversation and the per-message lookup fails. Either:
   a. Fix the per-session lookup so it reliably hits (the real fix, strongly preferred), or
   b. If a fallback is still needed for genuine edge cases, it must NEVER silently substitute a different card - showing a clear "couldn't load this card, tap again" state is far better than silently showing the wrong content, since the wrong-content case is actively misleading (the user thinks they're interacting with card A but it's actually card B's state).
3. Verify the fix handles the exact user-reported sequence: tap card A (seat select) - interact - tap card B (system health, a DIFFERENT card, never before opened this session) - confirm card B actually renders, not card A. Then tap back to card A - confirm it shows card A's own state, not card B's or a fresh/reset instance.

## Verification requirements (same rules as the rest of this session)
- Real evidence only - use the debug harness (HermesShare/Sources/DebugHarnessView.swift, JSON editor mode) or extend HermesRenderSmokeTests.swift with a test that simulates opening multiple distinct cards in sequence and asserts each renders its own correct content, not another's.
- Build Release for a real device target (xcodebuild with destination "generic/platform=iOS" is safest since the physical device connection is unreliable this session - do not assume devicectl device install will succeed, check first).
- Package a fresh .ipa per ~/.hermes/skills/software-development/hermesshare-ipa-sideload/SKILL.md exactly (build, zip Payload folder into an .ipa, host via python3 http.server + cloudflared tunnel, curl-verify 200 and correct byte size) - the user is remote, uses Feather to self-sign, no cable. This is now the standing distribution pipeline, always required after any change like this.
- Send fresh test cards through Photon (PHOTON_ALLOWED_USERS from ~/.hermes/.env, use ~/.hermes/hermes-agent/plugins/platforms/photon/sidecar/send_card_photon_v3.mjs or send_card_photon.mjs) that specifically exercise the bug: at least 2-3 DIFFERENT card types (e.g. a seatChart/optionPicker card and a gaugeCluster or flightBoard card) sent as separate messages in the same conversation, so the user can literally tap between them and confirm persistence works.
- Also generate real designed JPEG thumbnails for these test cards (not app-screenshot crops - a prior lazy attempt did that and was explicitly called out by the user as bad; use PIL for a genuinely composed preview graphic). Photon requires JPEG specifically - PNG bytes are rejected with "layout.image must contain JPEG data".

## Second, separate issue to also address: thumbnail quality/clutter direction
User feedback, verbatim: "a lot of the thumbnails are overcluttered and interfere with UI elements so we need to give it direction on how to generate thumbnails properly." This means: when generating a real designed preview-image thumbnail for a card (the JPEG sent via Photon's layout.image field, NOT the CardThumbnailRenderer in-app screenshot renderer used for locally-composed messages), avoid packing so much text/graphic content into the 600x400-ish preview that it visually competes with or obscures the actual card content once tapped open, or looks cluttered/busy as a standalone bubble image. Concrete guidance to bake into the thumbnail-generation approach (update the hermesshare-cards skill's guidance on this, at ~/.hermes/skills/productivity/hermesshare-cards/SKILL.md and/or references/schema.md):
- One hero title, one short subtitle/stat line, one accent-colored icon badge or simple graphic element - not multiple competing text blocks, not a screenshot crop of the full card's UI.
- Generous negative space - the thumbnail is a bubble preview, not the card itself; it should tease the content, not replicate it in miniature (which just looks cluttered at small size).
- Consistent, restrained composition: dark/tinted-neutral background with a soft accent glow (per the ada-swiftui-design skill's canvas guidance - reference ~/.hermes/skills/creative/ada-swiftui-design/SKILL.md for the visual language), one accent color matching the card's own accentColorHex, real SF-rendered typography (not a small default bitmap font).
Update the actual thumbnail-generation guidance/examples in the hermesshare-cards skill so future agents (including yourself, next time) generate clean, uncluttered thumbnails by default - this should be a documented rule, not something re-explained each time.

## Constraints - do not break these
- Keep the existing .safeAreaInset(edge: .bottom) pinned-action-bar pattern in MessagesViewController.swift (a real, hard-won fix for an earlier blank-screen regression this session) - do not touch or revert it.
- Keep the ADA-doctrine visual redesign (flightBoard, platedDish, gaugeCluster, cabin-framed seatChart, enriched timeline) intact - do not revert to the old bland flat styling while fixing this bug. The user approved this direction; this bug report is purely about navigation/persistence, not the visuals.
- Photon transport realities, don't relitigate: customizedMiniApp() requires https:// URLs with a p= query param (never custom schemes); layout.image requires JPEG bytes specifically.
- The JSON schema (HermesLayout.swift / HermesLayoutCodable.swift / HermesLayoutRenderer.swift) is a fixed, parameterized interpreter - no arbitrary code execution, ever. Fixing this bug should not require breaking that model.

Report back: the actual root cause of the session/cache mismatch (with real evidence, not a guess), what you changed, the fresh .ipa URL, and confirmation the multi-card persistence test actually passed.
