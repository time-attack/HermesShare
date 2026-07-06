# HermesShare — URGENT regression fix (model: claude-opus-4-8)

## What just happened
A prior Claude Code session just patched `Shared/Sources/HermesShared/HermesLayoutRenderer.swift` to apply visual-design improvements from the `ada-swiftui-design` skill (installed at `~/.hermes/skills/creative/ada-swiftui-design/SKILL.md` — read it fully, it's the design doctrine driving these changes and should keep driving your fix). The three changes made:

1. `progressRing(_:_:_:)` — rewrote the hero numeral as a SwiftUI `Text` concatenation: `Text("...").font(...).monospacedDigit().foregroundStyle(.primary) + Text("%").font(...).foregroundStyle(.secondary)`.
2. Replaced the `.progressBar` case's bare `ProgressView` with a call to a new `jeweledProgressBar(value:color:)` function, built as a `GeometryReader { ... }.frame(height: 6)` containing a `ZStack(alignment: .leading)` with two `Capsule()` layers (track + gradient-filled lit trail with `.shadow`).
3. Rewrote `header` to show the subtitle as an uppercase/kerned small-caps micro-label ABOVE the title (previously title-then-subtitle), with the title now `.system(size: 24, weight: .bold, design: .rounded)` in expanded presentation.

The app was rebuilt (`xcodebuild ... Release ... BUILD SUCCEEDED` — confirmed, it compiles fine) and installed to the physical device, then a test card (`/tmp/ada_test_card.json`, sent via `/tmp/ada_test_compact.json` through the Photon send script) was sent to the user's iMessage thread. **The user reports it now renders completely blank — not even the "Waiting for a card" empty state, which is a DIFFERENT and WORSE symptom than the "blank card" bug fixed earlier this session** (that one at least still showed empty-state chrome around the missing content; this one appears to render literally nothing, per the user's description).

## Confirmed via on-device evidence (not guessed)
Pulled the debug log via:
```
xcrun devicectl device copy from --device E111536C-8461-5ABC-BE2D-E57F77A7165A --source "/Documents/hermesshare-debug.log" --domain-type appDataContainer --domain-identifier com.hermesshare.app.MessagesExtension --destination /tmp/out.log
```
Shows `decoded layout? true` for every tap on the new test card — JSON decode succeeds every time, same as the last regression. Checked running processes via:
```
xcrun devicectl device info processes --device E111536C-8461-5ABC-BE2D-E57F77A7165A | grep -i hermes
```
`HermesShareExtension` is NOT in the process list after the tap — meaning the extension process is crashing (or being Jetsam-killed — a prior session found a real JetsamEvent/memory-kill during earlier debugging of a similar symptom, worth re-checking `xcrun devicectl device info processes` / crash logs for a fresh Jetsam event too, don't assume it's the same cause without checking).

## The likely root cause (a real, specific hypothesis — verify, don't just trust this)
The three changes above are the only diff between the last known-working build and this one. Most suspicious candidates, roughly in order:
1. **The `Text + Text` concatenation in `progressRing`** — mixing a plain `Text(...).font(...).monospacedDigit()` with a `+` operator chain is valid SwiftUI, but double-check the exact syntax used compiles to a genuinely valid `Text` concatenation (operator precedence with the trailing `.foregroundStyle` calls on each side, not accidentally applied to the whole expression) and doesn't produce something that infinite-loops or force-unwraps badly at layout time.
2. **`jeweledProgressBar`'s `GeometryReader`** — GeometryReader wrapped in `.frame(height: 6)` with no width constraint from the caller could report a zero/NaN width in some layout contexts (e.g. if a parent doesn't propose a width before this view is asked to lay out), and `max(6, geo.size.width * value)` would still produce a real number, but check for a genuine infinite-layout-recursion risk or an actual crash (NaN in a `.frame(width:)` call crashes SwiftUI hostng in a way that's hard to distinguish from a hang).
3. **Something about how these three changes compose together** in a real card (the test card put a `progressRing` + `progressBar` + `checklist` in the same `vstack` — check whether that specific combination, not any one primitive alone, is what breaks).

## Your job
1. **Reproduce first, with real evidence** — don't guess-fix. Use the host app's debug harness (`HermesShare/Sources/DebugHarnessView.swift`, JSON-paste editor mode) or build a tiny standalone SwiftUI preview/render harness (a previous session considered a small SwiftPM executable importing `HermesShared`, decoding a JSON file, constructing the exact view tree, and rendering via `ImageRenderer` to a PNG — this fully avoids needing the Messages extension or simulator taps and is the fastest reliable loop) to actually render `/tmp/ada_test_card.json` (or recreate its content — it's a Pre-Flight Checklist card combining `progressRing`, `progressBar`, and `checklist` under one header) and see what specifically breaks. If it renders fine standalone, the bug may be more specific to the Messages extension embedding context (`UIHostingController` sizing, `.safeAreaInset` interaction from the earlier fix) — test in that context too if the standalone render looks fine.
2. **Fix the actual root cause.** If it's the Text concatenation, fix the syntax/logic error. If it's the GeometryReader sizing, give it an explicit safe width fallback or restructure to avoid the unconstrained-width risk. Whatever it is, verify your fix with a real screenshot (own vision or `vision_analyze`) before considering it done — this session's established rule is no self-reported "should work now," only verified-with-evidence claims.
3. **Do NOT revert the ADA visual improvements outright** — the goal is a fixed version of the hero-numeral ring, jeweled progress bar, and hero-typography header, not reverting to the old bland/generic versions. If truly necessary to unblock the user quickly, you may temporarily simplify (e.g. drop the Text-concatenation `+` in favor of two separate Text views styled similarly) as long as the visual improvement's INTENT survives — bigger hero numeral, glowing jeweled bar, hero-typography header — rather than reverting to the flat pre-ADA styling.
4. **Rebuild for the physical device** (UDID `E111536C-8461-5ABC-BE2D-E57F77A7165A`, should be connected — check with `xcrun devicectl list devices` first) and install (`xcrun devicectl device install app`).
5. **Send a fresh test card through Photon** to the same thread this session has been using all along (`PHOTON_ALLOWED_USERS` from `~/.hermes/.env`; use `~/.hermes/hermes-agent/plugins/platforms/photon/sidecar/send_card_photon_v3.mjs` or `send_card_photon.mjs` — both are working reference senders that take `<layout-json> <to-e164> <https-url-with-p-query> [thumbnail.jpg]`; note thumbnails MUST be JPEG, Photon's API rejects PNG bytes with "layout.image must contain JPEG data" — this was discovered and fixed earlier this session, don't reintroduce a PNG thumbnail).
6. **Pull the debug log after your own test tap** and confirm `decoded layout? true` AND the process still running afterward (or better, get a real screenshot of the rendered card) before reporting success.
7. Report back plainly: what the actual bug was, what you changed, and the real evidence it's fixed.

## Reference: known-working transport details
- Physical device UDID: `E111536C-8461-5ABC-BE2D-E57F77A7165A`
- Photon env vars: `PHOTON_PROJECT_ID`, `PHOTON_PROJECT_SECRET`, `PHOTON_ALLOWED_USERS` in `~/.hermes/.env`
- A live cloudflare tunnel may or may not still be up serving `/tmp/v3-host/card.json` at `https://artists-whats-adjusted-various.trycloudflare.com` — check with `curl -fsSL -o /dev/null -w "%{http_code}\n" <url>/card.json` first; if dead (likely, tunnels are ephemeral), start a fresh one: `python3 -m http.server <port>` in a directory containing at least an empty `card.json`, then `cloudflared tunnel --url http://localhost:<port>` in the background, and use its printed `https://*.trycloudflare.com` URL with a `?p=<payload>` query string appended by the send script (the send scripts handle the `?p=` construction themselves, just pass the bare tunnel URL + `/card.json` as the 3rd argument).
- Bundle IDs: `com.hermesshare.app`, extension `com.hermesshare.app.MessagesExtension`, team `6PPS68Y9RP`.
