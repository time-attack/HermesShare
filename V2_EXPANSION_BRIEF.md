# HermesShare v2 — Capability Expansion Brief

## Context

HermesShare is a real, working native iOS iMessage App Extension that renders JSON-driven
SwiftUI cards ("mini apps") inside iMessage, driven by an AI agent (Hermes) sending structured
layout JSON via the Linq API (imessage_app message part). This is NOT a web view — it's real
native SwiftUI, rendered on-device by a fixed interpreter (`HermesLayoutRenderer.swift`) that
walks a JSON tree (`HermesLayout`/`HermesNode`, in `Shared/Sources/HermesShared/HermesLayout.swift`
and `HermesLayoutCodable.swift`). No code is ever downloaded or compiled on-device — only a
fixed vocabulary of native primitives is parameterized by JSON, the same trick as Scriptable's
ListWidget or Widgy's layout engine.

Currently working end-to-end and verified on a physical device:
- Real Liquid Glass cards via `.glassEffect()` (iOS 26, `Shared/Package.swift` targets `.iOS(.v26)`)
- GamePigeon-style interaction: tapping an action button inside a rendered card composes a NEW
  reply MSMessage and inserts it back into the conversation (`handle(_:sourceLayout:conversation:)`
  in `HermesShareExtension/Sources/MessagesViewController.swift`) — this is the core "send input
  back" mechanic and must be preserved/extended, not replaced.
- A working example: an EVA Air flight card with status badge, key-value rows, and a
  "Book on EVA Air" action button.

## What's missing / what to build

### 1. A seat-chart layout primitive (the actual motivating use case)

Add a new `HermesNode` case for rendering an airplane seat map: a grid of tappable seat icons,
grouped into rows, with per-seat state (available / taken / selected) and per-row metadata
(exit row, bulkhead, extra legroom). This needs:

- A new case in `HermesNode` (in `HermesLayout.swift`) — something like:
  `case seatChart(rows: [HermesSeatRow], selectedSeatId: String?)` where `HermesSeatRow` has
  a row number, an array of seats (id, letter, state: available/taken/selected/unavailable,
  isExitRow, isBulkhead), and an aisle-gap marker so a 3-3-3 or 2-4-2 economy layout renders
  correctly with a visible center aisle.
- Hand-written Codable conformance in `HermesLayoutCodable.swift` (follow the existing pattern
  for other node cases — look at how `.card` or `.mapPreview` do it).
- A SwiftUI rendering branch in `HermesLayoutRenderer.swift` (`HermesNodeView.body`) that draws
  a compact horizontally-scrollable or vertically-stacked seat grid, each seat a tappable
  circle/rounded-square colored by state (green/blue = available, gray = taken, accent color =
  selected), with a visible aisle gap.
- Tapping an available seat should NOT immediately insert a reply message — it should update
  local UI selection state first (a real interactive picker, not a fire-and-forget tap), and
  then a separate, clearly-labeled CTA button ("Confirm Seat 22A") does the actual
  `conversation.insert()` reply. This is the single most important design requirement: **the
  user must not be confused about what a tap does vs. what confirms/sends.** Model this after
  how GamePigeon's board games work — you interact with the board freely, then a distinct
  "send move" action commits your turn.

### 2. Clear, consistent call-to-action design language

Right now there's exactly one action button style (`.buttonStyle(.borderedProminent)` in the
`actionBar` of `HermesLayoutRenderer`). For an interactive seat-chart or any future interactive
layout (polls, quick-reply chips, forms), there needs to be an unambiguous visual grammar:

- A PRIMARY action (the thing that actually sends/confirms/commits) should always look the
  same way across every card type — same color treatment (should read as "this button DOES
  something, deliberately, right now"), same placement (bottom of the card, full-width,
  never buried).
- Non-committing interactions (selecting a seat, expanding a section, toggling an option)
  should look visually distinct from the primary CTA — e.g. selection states use fill/border
  color changes on the tappable element itself, not button chrome, so the user's eye is never
  confused about which taps are "just browsing" vs. which one is "submit."
- Add a `HermesNode.quickReplyRow(options: [HermesQuickReplyOption])` case too, while you're
  extending the schema: a horizontal row of tappable chips (like iMessage's own quick-reply
  suggestions) that, when tapped, immediately composes and inserts a reply. Use this for
  simple confirm/deny or multiple-choice interactions where there's no multi-step state (unlike
  the seat chart, which needs a two-step select-then-confirm flow).

Read `~/.hermes/skills/creative/swiftui-design/SKILL.md` before touching any visual styling —
it documents hard-won lessons from earlier design work on this exact codebase: real Liquid Glass
is mandatory (never `.ultraThinMaterial` as a substitute), atmosphere/color must be bounded and
derived from real content state (not decorative gradients or manufactured "hero" numbers), and
there's a documented pitfall about never hand-editing generated SwiftUI to paper over one flaw —
read `references/fix-defects-via-skill-not-hand-edit.md` in that skill if you find a defect in
existing code and are tempted to just patch around it locally.

### 3. Make new card types "super easy" to author

The `HermesSampleLayouts.swift` file currently has 2-3 hardcoded example layouts used only by
the (now-removed) compose gallery. Repurpose/expand this into a genuinely useful reference:
add a `seatChart` example and a `quickReply` example there, AND write a short
`Shared/Sources/HermesShared/HERMES_LAYOUT_GUIDE.md` reference doc (plain markdown, not code)
that documents the full JSON schema for every `HermesNode` case with a real example JSON
snippet for each — this doc is what a future Hermes agent session will read to know how to
author a new card type without re-deriving the schema from source each time.

## Verification requirements (non-negotiable — read this)

1. Run `xcodegen generate` then `xcodebuild -project HermesShare.xcodeproj -scheme HermesShare
   -configuration Release -destination "generic/platform=iOS" -derivedDataPath build/verify
   build` and confirm `** BUILD SUCCEEDED **` in the actual output before claiming anything works.
2. Use `xcrun simctl` to boot a simulator, install the built .app, and take real screenshots
   (`xcrun simctl io <udid> screenshot`) of: the seat chart mid-selection, the seat chart after
   tapping "Confirm," and the quick-reply row. Actually look at these screenshots yourself
   (you have vision) and describe honestly what you see, including any remaining rough edges —
   do not claim something looks correct without having actually inspected the pixels.
3. Do NOT claim the Liquid Glass / interactive round-trip is broken or needs fixing unless you
   have re-verified it broke — it was working as of this brief. If your changes touch shared
   rendering code, re-verify the existing EVA Air flight card example still renders/builds
   correctly, not just the new seat chart.
4. When finished, write a plain summary of exactly what was added (new HermesNode cases, new
   Swift files touched, any schema/JSON shape changes) so a fresh agent picking this up next
   doesn't have to re-diff the whole repo to find out what changed.

## What NOT to change

- Do not touch the GamePigeon-style reply-insertion mechanism in `handle(_:sourceLayout:
  conversation:)` except to route the new seat-chart "Confirm" button and quick-reply chips
  through it (it's the right mechanism, reuse it).
- Do not revert `Shared/Package.swift`'s `swift-tools-version:6.2` / `.iOS(.v26)` / 
  `swiftLanguageMode(.v5)` settings — these were deliberately chosen to unlock `.glassEffect()`
  while avoiding Swift 6 strict-concurrency retrofitting pain across the whole package.
- Do not remove the `data:` URL decode path in `MessagesViewController.layout(from:)` — that's
  required for the current Linq-API send pipeline (Linq only accepts https:// or data: URLs,
  never custom schemes).
- AddFishSheet-equivalent: there is no such legacy file in this project, ignore that reference
  pattern from other unrelated projects if you happen to have seen it in training data.

## Repo location

`~/Documents/HermesShare/` — real git-less local project (no remote yet), Xcode project
generated via `xcodegen` from `project.yml`. Bundle IDs: `com.hermesshare.app` (host),
`com.hermesshare.app.MessagesExtension` (extension). Team ID `6PPS68Y9RP`, signed with
"Apple Development: SIna Matian (TA89948CWL)".
