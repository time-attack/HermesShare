HermesShare — REMOVE the silent cache-fallback entirely. Show a real error + logs instead.

## The actual instruction (from the user, direct correction of a previous framing)
"When a message app fails don't just fallback to cached apps, show the logs and show
the error message." This is a PRODUCT BEHAVIOR requirement, not just a bug hunt. The
user does not want any code path that silently substitutes a different (cached / most
recent / stale) card when the correct one can't be resolved. Ever. If HermesShare
cannot determine what the tapped/selected message actually is, it must show a real,
visible ERROR STATE - with diagnostic detail on screen - not another card's content.

## Background context (for your own diagnosis, but the fix below is the priority)
Two previous sessions attempted to fix a "stuck on the wrong card" bug via increasingly
precise root-causing (stale selectedMessage, didTransition not receiving the tapped
message, etc.) and both shipped fixes that still exhibited SOME version of the symptom
on retest - most recently: "works fine sending one card at a time, breaks when multiple
cards are sent in quick succession" and "gets stuck showing the MOST RECENTLY sent card
regardless of what's tapped." Do not spend your whole session trying to root-cause the
exact race condition first - that diagnosis has already eaten two full sessions. Instead,
prioritize: **remove every code path that can silently show a different card than the
one the user actually opened.** Once wrong-content-is-impossible, the remaining
"sometimes shows an error" experience is honest and debuggable (which is what the user
explicitly wants), rather than another round of "maybe I found the real race this time."

## Concrete required change
1. Read the CURRENT actual state of MessagesViewController.swift and whatever the
   session/layout cache is now called (it has been renamed/restructured across two prior
   sessions - verify current reality, don't trust old descriptions) - find every place
   that currently falls back to ANY notion of "latest", "most recent", or "last cached"
   layout when the specifically-tapped/selected message can't be resolved. This may
   already be partially removed by previous sessions - re-verify, don't assume.
2. DELETE that fallback entirely. There should be no function/property left that answers
   "what's the most recently shown/cached card" and no caller that uses such a thing as
   a substitute for "I don't know what was tapped."
3. In its place, when the specific tapped/selected message's layout genuinely cannot be
   decoded or found (after any reasonable retry for the known late-URL-materialization
   case), render a real, visible ERROR VIEW - not a blank screen, not another card - that
   shows:
   - A clear human message, e.g. "Couldn't load this card."
   - Actual diagnostic detail visible on screen (not just in an off-device log file): at
     minimum, whether a message was detected at all, whether it had a URL, what the
     session identifier was, and what internal resolution path was attempted (e.g.
     "message detected, session abc123, no cached layout found, URL was nil after 3
     retries"). This should look like a real diagnostic/debug panel, not a polished
     empty-state graphic - the user wants to SEE what actually happened, not a friendly
     dead end.
   - This error view is a permanent, real product surface - not a temporary DEBUG-only
     view. It should ship in Release builds too, since debugging this exact class of bug
     without any visible signal is what has made it hard to fix over multiple sessions.
4. Also surface the equivalent detail in the existing on-device debug log (which already
   exists in this project) so a log pull remains useful too - the on-screen error view
   and the log should show consistent/overlapping information.
5. Keep existing legitimate retry-for-late-URL logic (Messages sometimes populates
   MSMessage.url asynchronously - retrying briefly before giving up is reasonable and
   already exists) - the requirement is about what happens AFTER retries are exhausted,
   not about removing retries.

## Verification
1. Extend or add tests confirming: when a message's layout cannot be resolved (simulate
   nil URL + no session cache hit), the render path produces the ERROR VIEW, and
   critically, NEVER renders a layout belonging to a different, unrelated session/message.
   Assert on that "never substitutes" property directly - this is the single most
   important invariant to lock in with a test, since it's the thing that's regressed
   silently before.
2. If the physical device becomes reachable at any point (check `xcrun devicectl list
   devices`), pull the debug log after a real test tap and confirm log content matches
   what's shown on screen. If the device is unreachable all session, say so plainly and
   rely on the test suite + code review for verification - do not claim on-device
   confirmation you don't have.
3. Paste real evidence into your final report: either an actual on-device log excerpt, or
   the literal test-runner output (not just "tests pass" prose).

## Constraints - do not break these
- Keep .safeAreaInset(edge: .bottom) pinned-action-bar pattern intact.
- Keep the ADA-doctrine visual redesign (flightBoard, platedDish, gaugeCluster,
  cabin-framed seatChart, enriched timeline, optionPicker with badge/sublabel) intact -
  this change is about error handling, not visuals, for every OTHER card.
- Photon transport: customizedMiniApp() needs https:// URLs with a p= query param;
  layout.image needs JPEG bytes, not PNG.
- Fixed JSON-schema interpreter model must not be broken - no arbitrary code execution.

## Delivery
1. Build Release for generic iOS device (xcodebuild -destination "generic/platform=iOS").
2. Package + host a fresh .ipa exactly per
   ~/.hermes/skills/software-development/hermesshare-ipa-sideload/SKILL.md. Curl-verify
   HTTP 200 AND exact byte-size match against the file on disk BEFORE writing the link
   into your report - prior links have died before the user could grab them because the
   hosting tunnel/http.server are children of the dispatched session and die when it
   exits. Explicitly flag this limitation in your report rather than omitting it.
3. Send 3-4 fresh test cards through Photon (PHOTON_ALLOWED_USERS from ~/.hermes/.env,
   use ~/.hermes/hermes-agent/plugins/platforms/photon/sidecar/send_card_photon_v3.mjs),
   each with a real restrained JPEG thumbnail (reuse/extend
   ~/.hermes/skills/productivity/hermesshare-cards/scripts/make_thumbnails_restrained.py).
   Include a mix of card types so the user can tap between them and, ideally, deliberately
   try to trigger the error state (e.g. by rapid-tapping between cards) to see the new
   honest error view in action rather than a wrong-content substitution.
4. Final report must include real pasted evidence (log excerpt or literal test output),
   per the verification section above.
