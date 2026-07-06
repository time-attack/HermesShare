# HermesShare — Real ADA-doctrine redesign (not the shallow pass done last time)

## Context
HermesShare is a real native iMessage App Extension at ~/Documents/HermesShare. Its renderer, Shared/Sources/HermesShared/HermesLayoutRenderer.swift, is a FIXED interpreter for a JSON schema (HermesLayout.swift) — it draws SwiftUI primitives selected/parameterized by JSON, never executes arbitrary code (security model, do not break this: no eval, no dynamic Swift).

The ada-swiftui-design skill is installed at ~/.hermes/skills/creative/ada-swiftui-design/SKILL.md — READ IT FULLY before writing any code, and follow its Step 0 process for real this time. A prior pass on this renderer (bigger progress-ring numeral, a "jeweled" gradient progress bar, small-caps header) was correctly rejected by the user as "just checking boxes to feel nice" — bland, plain, nothing like what the skill actually produces. That prior pass skipped Step 0 entirely and never built a real scene/centerpiece (rule 10) — it was surface-level typography tweaks, not the doctrine.

## Your job: do Step 0 for real, then redesign properly

For each of HermesShare's current card "genres" (not every literal node type — group by what a real card actually represents), answer Step 0's four questions explicitly as a code comment, THEN redesign the rendering to match:

1. Flight/travel checklist and pre-flight cards (checklist, progressRing, progressBar combos, timeline entries about flights) — METAPHOR is airport departure boards / boarding passes. This has a real STAGE (an airport/gate) — per rule 10 Architecture A or an instrument-panel treatment, not a flat list.
2. Recipe / food cards — METAPHOR is an editorial cookbook card. STAGE is a kitchen counter or plated dish.
3. Seat/option pickers (seatChart, optionPicker) — METAPHOR is a boarding pass seat map / restaurant table layout. STAGE is the seat/table grid itself, which already exists as a real instrument — but push it further per rule 7 (physical controls) and rule 10 (jewelry: labeled endpoints, real state).
4. Itinerary/timeline cards (timeline) — already has decent contextual dimming (rule 6) from a prior pass, verify it still meets the bar, don't regress it.
5. Comparison/stat cards (table, barChart, stat) — METAPHOR is a finance/instrument-cluster look per the genre playbook table in the skill.

For at least 2 of these (your choice of the most impactful), build an ACTUAL custom-drawn Canvas centerpiece per rule 10 — e.g. a real departure-board flip-style header for flight cards, or a simple procedural "plated dish" icon/scene for recipes — using the skill's "How to build with zero assets" recipes (seeded procedural Canvas, pseudo-3D, glow/atmosphere). This is the part that was skipped entirely last time and is the actual difference between "bland" and ADA-grade. Don't just retint existing flat elements — add a genuine drawn/instrument centerpiece.

Score your own output against the skill's Pre-flight checklist (18-point rubric) before considering this done. Note honestly in your final report if you score below 16/18 on any card type and why.

## Constraints (the actual JSON schema is fixed — work within it, extend it if needed)
- HermesLayout.swift, HermesLayoutCodable.swift, HermesLayoutRenderer.swift are the three files that define and render the schema. You MAY add new fields/node types if genuinely needed for a real scene (e.g. a flightBoard node), following the existing pattern (Codable case plus hand-written encode/decode plus SwiftUI render case) — but don't blow up scope; prefer enriching the RENDERING of existing nodes (checklist, progressRing, timeline, seatChart, optionPicker, stat, barChart) with real scenes/instruments over adding many new node types.
- Keep the existing safeAreaInset(edge: .bottom) pinned-action-bar pattern in MessagesViewController.swift — this was a real, hard-won fix for a blank-screen regression earlier this session, do not touch or revert it.
- Two known Photon transport realities, don't relitigate: (1) Photon's customizedMiniApp() requires the URL to be https:// with a p= query param, never a custom scheme; (2) Photon's layout.image (bubble thumbnail) requires JPEG bytes specifically — PNG is rejected with "layout.image must contain JPEG data".

## Verification — real evidence only, the established rule this whole session
1. Use the host app's debug harness (HermesShare/Sources/DebugHarnessView.swift, JSON-paste editor mode) OR the existing HermesRenderSmokeTests.swift (extend it with new fixtures) to render your new designs and get REAL screenshots — own vision or vision_analyze, never a self-report.
2. Build Release for generic iOS device (xcodebuild with destination "generic/platform=iOS" — the physical device is NOT reliably connected this session, don't assume devicectl device install will work; if a device IS connected when you check, destination "id=UDID" is also fine).
3. Package a fresh .ipa and host it — the user is remote (using Feather to self-sign, no cable). Follow ~/.hermes/skills/software-development/hermesshare-ipa-sideload/SKILL.md exactly for this (build, zip Payload folder, host plus cloudflared tunnel, curl-verify 200 and correct byte size before considering it done).
4. Generate genuinely designed thumbnail images for your test cards (not screenshot crops of the app's own UI — a prior lazy attempt did that and was called out; use PIL to build a real preview graphic, or the ai-image-generation skill if it adds real value) — remember Photon needs JPEG, not PNG.
5. Send 4-5 fresh test cards (one per genre above) through Photon to the user's thread (PHOTON_ALLOWED_USERS from ~/.hermes/.env; use ~/.hermes/hermes-agent/plugins/platforms/photon/sidecar/send_card_photon_v3.mjs or send_card_photon.mjs, both working reference senders taking layout-json, to-e164, https-url-with-p-query, and optionally a thumbnail.jpg path), each with a real JPEG thumbnail.
6. Report back: your Step 0 answers per genre, what you actually built (be specific about the drawn scene/instrument, not just "improved styling"), your honest 18-point score per card type, the fresh .ipa download URL, and confirmation the cards sent successfully.
