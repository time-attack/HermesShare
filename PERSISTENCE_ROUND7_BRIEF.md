HermesShare persistence bug - round 7. NEW evidence rules out decode/render as the cause.

## New, definitive evidence gathered this session (real test output, pasted below)
The user sent two cards in quick succession: a working 187-seat EVA Air 777 seatChart card
(confirmed working - user could interact with it), then a UA1 flightBoard card sent moments
later (JFK to SFO, In Flight, progress 0.58) - which failed, reproducing the exact long-running
symptom. To rule out a card-specific bug before re-blaming the resolver, I wrote and ran a real
XCTest against the EXACT UA1 JSON payload that was sent:

```
Test Case '-[HermesSharedTests.HermesUA1DiagnosticTests testUA1FlightBoardJSONDecodesSuccessfully]' passed (0.002 seconds).
Test Case '-[HermesSharedTests.HermesUA1DiagnosticTests testUA1FlightBoardRendersThroughExtensionIdenticalViewTree]' passed (0.059 seconds).
Executed 2 tests, with 0 failures (0 unexpected) in 0.060 seconds
** TEST SUCCEEDED **
```

The first test decodes the literal UA1 JSON string through HermesLayout.decode and asserts
the flightBoard fields are correct. The second constructs the EXACT view tree
MessagesViewController.showRenderer uses (ScrollView + safeAreaInset action bar, expanded
presentation) with that decoded layout, and asserts the rendered content has real height
(not near-zero/blank) via UIHostingController.sizeThatFits + ImageRenderer.uiImage != nil.

**This DEFINITIVELY rules out**: a decode-level schema bug in flightBoard, a render-level
crash/hang/blank-view bug in flightBoard specifically. Both are proven fine in isolation.
This is now a confirmed, narrowed problem: something in message delivery, caching, or
resolution - specifically when a SECOND distinct card arrives shortly after a first one that
was just interacted with - shows the wrong (first) card's content instead of the second
card's content. The test file, kept in the repo for future reference, is at
Shared/Tests/HermesSharedTests/HermesUA1DiagnosticTests.swift.

## Full history of this bug across previous sessions (for context, do not re-litigate settled facts)
1. Original report: stuck on first card tapped, everything routes back to it.
2. Session 1 fix: found selectedMessage preferred over tappedMessage in presentContent -
   fixed didSelect path. Still broken (didTransition had the same hole).
3. Session 2 fix: fixed didTransition too via lastTappedMessage + generation counter. Still
   broken on real device (though simulator-verified).
4. Session 3 (user's direct correction): "don't fall back to cached apps, show logs/errors" -
   removed the "latest cached layout" global fallback entirely, added a real on-screen
   HermesCardFailureView with diagnostics, wired into the debug log. Verified via 30 passing
   tests. Still reported broken: "flight tracking and system health don't work, they fall
   back" with NO error view shown at all.
5. Session 4 investigated whether flightBoard/gaugeCluster specifically crash (bypassing the
   failure-view code entirely, which would explain "falls back, no diagnostic"). Concluded:
   NOT a crash - drove the real extension in a simulator, tapped between cards including
   flightBoard/gaugeCluster, all rendered correctly, failure view appeared correctly when
   deliberately made unresolvable. Concluded the user's phone had a STALE build (old IPA link
   died before install). Added a build stamp (HermesBuildInfo.stamp) visible on-screen and in
   logs specifically so stale-build confusion can be caught immediately going forward.
6. Session 5: after user reinstalled and reported the SAME bug, found a genuinely different,
   deeper gap: the fix only correctly handled cards inserted via conversation.insert() (the
   simulator's compose path) - never a card delivered externally via Photon's real
   customizedMiniApp/didReceive path, which is what every real test card actually uses. Found
   two holes: willBecomeActive was clearing a trusted tap before use, and provisional renders
   never re-checked a late-arriving correct selection. Fixed both, and PROVED the bug's exact
   reported symptom reproduces by temporarily reverting the fix and watching a new test fail
   with literally "Pick Your Seat" is not equal to "Cutting It Close" - then confirmed passing
   after re-applying the fix. Build stamp bumped to 2026-07-06.3.
7. User re-tested (this session): reports the SAME bug still happening - now specifically
   isolated to a second card (UA1 flightBoard) sent shortly after a first, already-interacted
   card (EVA777 seatChart). The new diagnostic test in section above proves the SECOND card's
   OWN json/render is fine - so the bug is real, is NOT a stale build this time (or if it is,
   that must be re-verified, not assumed), and is specifically about handling closely-spaced,
   sequential card delivery.

## What to actually do this round
1. Confirm current build stamp reality: check HermesBuildInfo.stamp's current value in the
   source, and if possible, ask about or verify (if device becomes reachable) what stamp value
   is actually showing on the user's installed app right now, to definitively rule in/out
   "still testing a stale build" one more time - do not simply assume this again without
   checking, since it was correctly the cause once before and could recur if a link died
   before install again.
2. Assuming NOT a stale build (default assumption per the new evidence unless proven
   otherwise): re-examine the ACTUAL sequence of what happens when a second, distinct Photon
   card arrives shortly after a first card was open/interacted with. The previous session's
   HermesEventRouter fix handled "first tap ever, nothing cached, other different cards
   already exist from PRIOR (settled, no-longer-active) sessions." It may not correctly handle
   "a second card arrives WHILE the extension is still actively showing/just finished
   interacting with the first card" - i.e., a still-warm, still-active extension state, not a
   cold relaunch. Trace this specific timing scenario in the current HermesEventRouter /
   MessagesViewController code: what happens to `lastTappedMessage`, the generation counter,
   and any in-flight provisional-render retry timers when a NEW message's didReceive/tap
   arrives before a PREVIOUS resolution/retry cycle has finished?
3. Build a new test that specifically simulates: card A is open and its action was just
   tapped (a reply was sent, matching the user's exact reported sequence: seat card
   interacted with, THEN a new card arrives and is tapped). Assert the new card (card B)
   resolves correctly even when card A's interaction/reply/retry machinery might still be
   settling. This is a genuinely different timing scenario than prior tests (which tested
   "warm re-tap of an old card" and "cold first-tap of a fresh card with OTHER SETTLED cards
   already cached" - neither tested "brand new card arriving in the narrow window right after
   a DIFFERENT card's own interaction just completed").
4. Fix whatever gap this reveals. If, after careful tracing, the code is actually already
   correct for this scenario and you cannot find a code-level gap, say so explicitly and focus
   instead on maximizing on-device diagnostic output (the failure view / logs) so the NEXT
   real occurrence produces conclusive on-device evidence instead of another guessing round -
   this is an acceptable, honest outcome, not a failure, if you truly cannot find the bug from
   code alone.

## Verification
- Paste real test output for any new test, plus confirm the full existing suite still passes.
- If the device becomes reachable at any point, pull a real debug log/build-stamp check.
- Do not write a narrative-only report.

## Constraints
- Keep .safeAreaInset(edge: .bottom) pinned-action-bar pattern intact.
- Keep ALL ADA-doctrine visuals intact.
- Keep HermesCardFailureView + never-substitute resolver + HermesEventRouter's tap-survival
  logic - if there's a gap in a specific timing window, fix that gap, don't remove the
  features.
- Photon transport: customizedMiniApp() needs https:// URLs with p= query param; layout.image
  needs JPEG bytes, not PNG.
- Fixed JSON-schema interpreter model - no arbitrary code execution.

## Delivery
1. Build Release for generic iOS device.
2. Package + host a fresh .ipa per ~/.hermes/skills/software-development/hermesshare-ipa-sideload/SKILL.md.
   Curl-verify HTTP 200 and exact byte match against disk BEFORE reporting the link. Bump
   HermesBuildInfo.stamp to a new distinct value so this build is unambiguously identifiable.
3. Send 3-4 fresh cards through Photon INCLUDING the specific new scenario: send one card,
   wait a moment then interact with/reply to it (if your test harness allows simulating this),
   then immediately send a second, different card and tap it - as close to the user's exact
   reported sequence as you can reproduce.
4. Final report: real pasted evidence, honest statement of what was found (or not found) and
   why, the verified-live IPA link.
