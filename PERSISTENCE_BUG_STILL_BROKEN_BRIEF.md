HermesShare — persistence/navigation bug STILL NOT FIXED after previous "fix", investigate why

## Critical context: your previous fix did not work
A previous Claude Code session (this same repo, same bug report) diagnosed and fixed what it believed was the root cause: presentContent in MessagesViewController.swift preferring conversation.selectedMessage over the actually-tapped message, plus a bad global-latest-layout fallback, plus a missing return in a retry branch. It shipped a new build, the user installed the new IPA, tapped between multiple different cards (seat select, system health, flight status) sent fresh into the conversation - and reports the EXACT SAME BUG: stuck on the first card tapped, everything else routes back to it, completing an interaction and sending a reply still shows the same stuck card type.

Do not re-explain or re-assert the previous diagnosis as if fixing it - it demonstrably did not resolve the user-visible symptom. Either:
(a) the previous fix was incomplete / had a bug in its own logic, or
(b) there's a SECOND, different cause still active, or
(c) the fix never actually reached the device the user tested (e.g. stale build, wrong binary, Feather re-signing issue, or the .ipa the user grabbed was actually an old cached one) - VERIFY this possibility first before assuming the code is wrong, since IPA-hosting tunnels in this project have repeatedly died silently this session and mismatched builds have been a real recurring problem.

## What you have available to investigate (device is NOT currently connected)
The physical iPhone is unreachable via devicectl right now (unavailable state) - the user is away from their Mac. Do not assume you'll get a fresh on-device debug log pull this session. Verification must happen primarily through:
1. Careful code re-reading of the ACTUAL current state of MessagesViewController.swift, HermesLayoutStore.swift (or wherever the session cache landed after the previous fix), and any related session-key logic - read the CURRENT file contents fresh, do not trust the previous session's description of what it changed; verify byte-for-byte what's actually in the file right now.
2. The existing HermesCardPersistenceTests.swift (added by the previous fix) - run it, confirm it still passes, but then SCRUTINIZE whether it actually tests the real bug or a narrower/different scenario than what's actually happening on-device. A passing test suite alongside a persisting live bug strongly suggests the test doesn't cover the real failure path - find the gap.
3. If devicectl device list shows the phone reachable at any point during your session, immediately pull the fresh debug log (xcrun devicectl device copy from --device <UDID> --source "/Documents/hermesshare-debug.log" --domain-type appDataContainer --domain-identifier com.hermesshare.app.MessagesExtension --destination /tmp/out3.log) and use real evidence from it.
4. Consider adding MORE granular debug logging than currently exists if the current log statements don't capture enough detail to diagnose - specifically log: the exact session UUID string being looked up, the exact session UUID string(s) currently in the cache/store, whether the lookup hit or missed and why, and which code path (direct decode / session-cache hit / retry / fallback / error-state) actually rendered for every single presentContent call. This is the kind of forensic logging needed to catch a subtle session-matching bug that unit tests didn't reproduce.

## A concrete alternative hypothesis to actively check, not assume
The previous fix changed message resolution to prefer the tapped message's session over selectedMessage, and changed the fallback to show an explicit "couldn't load, tap again" error state instead of substituting the wrong card. If the user is reporting the SAME stuck-on-one-card behavior (not a new "couldn't load" error state), that's actually informative: it suggests either
- the per-session cache IS being hit, but with the WRONG cached layout (i.e., multiple different cards are somehow being stored under the SAME session key - check whether MSSession identity is actually unique per distinct card, or whether something reuses/shares a session across different composed/received messages), or
- the "tapped message" resolution itself still isn't correctly identifying which distinct card was tapped (e.g. still falling through to some code path that resolves to conversation.selectedMessage in a case the previous fix didn't cover), or
- the fix was applied to the wrong build/target, or the IPA the user tested was stale (check git status / file modification timestamps against when the previous session says it made changes, to rule this out concretely).

Actually read HermesLayoutStore's store/lookup implementation now (not from memory of the previous report) and check: is the store's key genuinely unique per distinct tapped card, or could two unrelated cards collide onto the same key? Trace this with actual code inspection, not assumption.

## What to build/verify
1. Find the REAL reason the symptom persists - with concrete evidence (code inspection at minimum, on-device log if the device becomes reachable).
2. Fix it properly.
3. Meaningfully strengthen the test coverage so this specific regression (multiple distinct cards, tap between them, confirm each renders correctly) is actually caught - if the existing test already claims to do this, explain concretely why it passed despite the bug still being live, and fix the test's blind spot too.
4. Build fresh Release for generic iOS device (xcodebuild ... -destination "generic/platform=iOS" ...).
5. Package + host a fresh .ipa exactly per ~/.hermes/skills/software-development/hermesshare-ipa-sideload/SKILL.md - build, zip Payload folder, host via python3 http.server plus cloudflared tunnel, curl-verify 200 status AND matching byte size against the file on disk BEFORE reporting the link as ready. This verification step is not optional - a dead/stale link has been sent to the user multiple times this session already.
6. Send fresh test cards (at least 2-3 different card types, e.g. seatChart/optionPicker plus gaugeCluster or flightBoard) through Photon into the user's conversation, each with a real restrained JPEG thumbnail (use the existing generator at ~/.hermes/skills/productivity/hermesshare-cards/scripts/make_thumbnails_restrained.py as a starting point, or regenerate similarly - one hero title, one subtitle, one simple accent graphic, dark canvas with soft glow, no screenshot crops).
7. In your final report, be explicit and honest about: what you found was ACTUALLY different from the previous session's diagnosis (or confirm if it turns out to be the same root cause with an implementation bug in the fix itself - either is fine, just be accurate), what you changed, and concrete evidence the fix now works (or an honest statement of what remains unverified given the device is unreachable).

## Constraints - do not break these
- Keep .safeAreaInset(edge: .bottom) pinned-action-bar pattern in MessagesViewController.swift intact.
- Keep the ADA-doctrine visual redesign (flightBoard, platedDish, gaugeCluster, cabin-framed seatChart, enriched timeline) intact - this bug is purely navigation/persistence, not visuals.
- Photon transport: customizedMiniApp() needs https:// URLs with a p= query param; layout.image needs JPEG bytes, not PNG.
- Fixed JSON-schema interpreter model must not be broken - no arbitrary code execution.
