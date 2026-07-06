HermesShare — persistence bug STILL happening on REAL DEVICE via Photon, despite simulator-verified fix. Find the real gap.

## Critical signal: this is now failing in a way the simulator test did NOT catch
The previous session (this repo, same bug) built a real fix, verified it two ways: (1) unit
tests including "never substitute" invariants for flightBoard/gaugeCluster specifically, all
passing, and (2) drove the ACTUAL extension in a dedicated iOS SIMULATOR's Messages app,
composing/inserting cards via the simulator's own compose flow, tapping between them, and
confirmed via on-device log + screenshot that each card rendered correctly and the diagnostic
failure view appeared correctly when a card was deliberately made unresolvable.

The user just tested a REAL card (a new flightBoard, "Cutting It Close" - HND to LAX) sent to
their REAL PHONE via Photon (customizedMiniApp, https:// URL with a p= query param - NOT the
simulator's in-app compose/insert flow) and reports: it re-routes to the OLD card (silent
substitution is BACK), and no error log / diagnostic view is shown at all.

This is the critical new information: **the simulator verification exercised cards inserted
via conversation.insert() from WITHIN the extension (the compose path). It did NOT exercise
a card delivered externally via Photon's customizedMiniApp / didReceive path, which is a
fully different code path into the extension.** The bug may live specifically in how a
Photon-delivered (didReceive) message's layout gets cached/resolved, as opposed to a
locally-composed (insert) message, which the simulator test never touched.

## What to actually investigate - this specific gap
1. Read the CURRENT actual code for didReceive(_:conversation:) in MessagesViewController.swift.
   Confirm exactly what it does when a NEW message arrives via the Photon delivery path (this
   is genuinely different from a locally-inserted message - didReceive fires for messages
   the OTHER party sent or that arrive via the extension's own send API, not for messages this
   same running instance just composed and inserted).
2. Specifically check: does didReceive reliably cache the just-arrived layout BEFORE the user
   taps it? The project's own history notes "didReceive fired zero times in two days" was a
   real, previously-diagnosed problem (Photon cards arriving while the extension isn't active
   don't trigger didReceive at all) - verify whether that's still true, and if so, what
   actually happens on FIRST TAP of a Photon-delivered card that was never cached via
   didReceive: does it decode directly from the message's URL (which should work if the URL
   is present), or does something route it through a stale-selection/cache path that picks up
   whatever was already on screen?
3. The user's exact sequence: multiple different cards already existed in the conversation
   from earlier testing (seat picker, dinner picker, health, flight, sent across several
   previous sessions/tests). The NEW card ("Cutting It Close") was sent via Photon into this
   existing conversation. The user tapped it and got the OLD card instead. This means: a
   message that has NEVER been tapped before, arriving fresh via Photon, on FIRST tap, shows
   WRONG content. Trace this exact cold-first-tap-of-a-fresh-Photon-message path in the code -
   this is likely different from anything the "warm re-tap of an already-seen card" tests
   covered.
4. Check whether the resolver's decode-from-own-URL path is even being reached at all for this
   case, or whether something upstream (e.g. willBecomeActive firing with a STALE
   conversation.selectedMessage still pointing at whatever was open before this new message
   existed) short-circuits before the new message's own URL is ever consulted.

## Do not just re-run the existing simulator test and declare success again
The existing tests and the existing simulator repro did NOT catch this - they must be missing
the actual failure path. Build a NEW test/repro that specifically simulates: a layout that
was NEVER cached via didReceive (because it was never active when the message arrived, exactly
like a real Photon send while the phone was locked or the extension wasn't running), then a
FIRST-EVER tap on that specific message while OTHER, different cards are already
cached/visible from prior activity. Assert that this fresh, first-tap resolves to its OWN
content, not to whatever was previously cached/visible. This is the scenario that's actually
broken; make sure your reproduction genuinely covers it before claiming a fix.

## Show the honest limitation clearly if you cannot get real device access
Both devices have been unreachable via devicectl for multiple sessions now. If still
unreachable, say so explicitly and rely on: (a) very careful code tracing of the actual
didReceive / willBecomeActive / presentContent call sequence for a genuinely fresh incoming
Photon message (not a simulator-inserted one), and (b) a new test that as closely as possible
simulates that real sequence (cache empty for this message, this message's own URL present,
OTHER sessions' layouts already in the cache from "prior activity") - and be honest in your
report that on-device Photon-delivery confirmation is still outstanding if the phone stays
unreachable.

## Constraints
- Keep .safeAreaInset(edge: .bottom) pinned-action-bar pattern intact.
- Keep ALL ADA-doctrine visuals intact.
- Keep the diagnostic HermesCardFailureView and never-substitute resolver behavior - if
  there's a gap specifically in the Photon/didReceive path, fix that gap, don't remove the
  feature.
- Photon transport: customizedMiniApp() needs https:// URLs with p= query param; layout.image
  needs JPEG bytes, not PNG.
- Fixed JSON-schema interpreter model - no arbitrary code execution.

## Delivery
1. Build Release for generic iOS device.
2. Package + host a fresh .ipa per ~/.hermes/skills/software-development/hermesshare-ipa-sideload/SKILL.md.
   Curl-verify HTTP 200 and exact byte match against disk BEFORE reporting the link.
3. Send fresh test cards through Photon (the REAL delivery path, not simulator-inserted) -
   several different types, sent close together into the existing conversation, replicating
   the exact scenario that's broken: a brand new card, never before seen, arriving via Photon
   while other different cards already exist in the thread.
4. Final report: paste real evidence (test output or log), be explicit about whether the
   Photon-delivery-specific gap was found and fixed, and be honest about what remains
   unverified given device unavailability.
