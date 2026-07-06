HermesShare — the no-silent-fallback fix from the previous session is INCOMPLETE

## User's exact new report (verbatim)
"It still doesn't show the error log but it kinda works it's just that flight tracking
and system health don't work and fall back but I don't see error logs or diagnostic
instead they just fall back."

Read precisely: tapping the FLIGHT BOARD card and the SYSTEM HEALTH (gauge cluster) card
specifically still shows WRONG CONTENT (a fallback to some other card), NOT the new
diagnostic HermesCardFailureView the previous session built. Other card types (seat
picker, option pickers) apparently work correctly now. This means the previous
session's audit that claimed "no code path can substitute a different session's card"
was WRONG, or incomplete, or there is a remaining path specific to these two card types
(flightBoard, gaugeCluster) that still resolves to a wrong/cached layout instead of
either the correct one or the new failure view.

## What to actually investigate (concrete, narrow)
1. Read the CURRENT actual code in MessagesViewController.swift, HermesCardResolver.swift,
   and wherever HermesLayoutSessionCache / the session store now lives - verify with fresh
   reads, not memory of prior session reports.
2. Specifically check: is there ANYTHING different about how flightBoard and gaugeCluster
   cards are composed/sent/cached versus seatChart/optionPicker cards that could cause them
   to take a different code path? Candidates to check:
   - Are flightBoard/gaugeCluster cards perhaps missing a proper `actions` array (no reply
     button), and does the resolver or view controller have ANY special-case behavior for
     layouts with no actions that accidentally bypasses the new failure-view logic?
   - Is CardThumbnailRenderer or the compose/insert path for these two node types doing
     something (e.g. a synchronous render that blocks, or a crash that gets silently
     caught) that a different card type doesn't hit, causing the app to fall through to
     showing a stale/previous view rather than actually reaching presentContent's resolved
     failure branch at all?
   - Is it possible the app is not failing to RESOLVE these cards at all, but instead
     CRASHING or getting suspended while attempting to render the flightBoard/gaugeCluster
     SwiftUI view specifically (the split-flap board and the arc-gauge Canvas drawing are
     more complex custom rendering than a plain list/picker), and what the user is actually
     seeing is: the extension crashes/hangs on these two specific card types, gets
     relaunched, and lands back on whatever was already-visible (the previous card) BEFORE
     ever reaching the new error-view code path? This would perfectly explain "falls back,
     no error view shown" - if the process dies, no SwiftUI error view ever gets a chance
     to render, because the failure-view code lives inside presentContent, and a crash
     bypasses it entirely. Check crash logs / process liveness specifically after tapping
     these two card types if the device is reachable (xcrun devicectl device info processes
     --device <UDID> | grep -i hermes right after a repro tap, and check for a Jetsam event
     or a genuine crash - this exact class of "silent crash disguised as a stuck UI" was a
     real cause found earlier in this project's history for a different bug, so it's a
     credible hypothesis here too, not a guess pulled from nowhere).
3. Reproduce locally: use the debug harness or extend HermesRenderSmokeTests.swift to
   specifically render standalone flightBoard and gaugeCluster layouts through the exact
   same view-tree construction path as the real extension (ScrollView + safeAreaInset +
   UIHostingController, matching showRenderer's actual structure) and confirm there is no
   crash, hang, or nil-unwrap in that specific rendering path. This is more informative
   than yet another cache/resolver logic review, since the resolver logic was already
   fixed and tested last session - the NEW information here is that it's specific to two
   visually-complex card types, which points at rendering, not resolution logic.

## If it IS a rendering crash/hang in flightBoard or gaugeCluster specifically
Fix the actual rendering bug (likely candidates: a GeometryReader or Canvas receiving a
zero/negative/NaN size, a force-unwrap on optional route/gauge data, an array index out of
bounds when a gauge/tile array is empty or has unexpected count). Do not simplify/revert the
ADA-doctrine visual design to "fix" this - find and fix the actual defect in the drawing
code, keep the custom-drawn centerpieces intact.

## If it's genuinely NOT a crash and the resolver really is still substituting content for these two card types
Then the previous session's fix has a real gap - find the specific code path that still
lets it happen for these two types only, and close it, following the same "never
substitute, always show the diagnostic failure view" requirement as the prior brief.

## Verification requirements - same as before, do not repeat the pattern of unverified claims
- Paste real evidence in your final report: either genuine on-device log/crash evidence (if
  the device is reachable - check `xcrun devicectl list devices` first and throughout your
  session), or literal test-runner output for a new test that specifically renders
  flightBoard and gaugeCluster through the real view-tree path and asserts no crash/hang,
  plus confirms the resolver's never-substitute invariant still holds for these two types
  specifically.
- Do not write a narrative-only report. If you cannot get device access, say so and rely on
  code-level/test verification, stated honestly.

## Constraints
- Keep .safeAreaInset(edge: .bottom) pinned-action-bar pattern intact.
- Keep ALL ADA-doctrine visuals intact (flightBoard split-flap board, gaugeCluster arc
  gauges, platedDish, cabin-framed seatChart, timeline, optionPicker) - fix the actual bug,
  don't simplify/revert the design.
- Keep the diagnostic HermesCardFailureView and the "never substitute a cached card"
  resolver behavior from the previous session intact - if you find it has a genuine logic
  gap for these two card types, fix the gap, don't remove the feature.
- Photon transport: customizedMiniApp() needs https:// URLs with p= query param; layout.image
  needs JPEG bytes, not PNG.
- Fixed JSON-schema interpreter model - no arbitrary code execution.

## Delivery
1. Build Release for generic iOS device (xcodebuild -destination "generic/platform=iOS").
2. Package + host a fresh .ipa per ~/.hermes/skills/software-development/hermesshare-ipa-sideload/SKILL.md.
   Curl-verify HTTP 200 and exact byte-size match against disk BEFORE writing the link into
   your report. Note in your report that this tunnel dies when your session exits (a real,
   repeated problem this project has hit) - the user or a follow-up session may need to
   re-host from the built .app/.ipa on disk rather than assuming the link stays live.
3. Send fresh test cards through Photon specifically re-testing flightBoard and gaugeCluster
   (the two reported-broken types) plus 1-2 other types for comparison, each with a real
   restrained JPEG thumbnail (~/.hermes/skills/productivity/hermesshare-cards/scripts/make_thumbnails_restrained.py).
4. Final report: real pasted evidence, what was actually wrong (crash vs. resolver gap),
   what you changed, the verified-live IPA link.
