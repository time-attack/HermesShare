# HermesShare v2 — What Changed (handoff summary)

Executed per `V2_EXPANSION_BRIEF.md` on 2026-07-05. All builds/tests/screenshots verified.

## New HermesNode cases (schema additions)

- `seatChart(rows: [HermesSeatRow], selectedSeatId: String?)` — interactive airplane seat map.
  Wire format: `{ "type": "seatChart", "rows": [...], "selectedSeatId": null }`.
  New supporting structs in `HermesLayout.swift`:
  - `HermesSeat` (`id`, `letter`, `state: available|taken|selected|unavailable`; state optional,
    defaults `available`)
  - `HermesSeatRow` (`rowNumber`, `seats`, `aisleAfterIndices: [Int]` for 3-3-3/2-4-2 aisle gaps,
    `isExitRow` / `isBulkhead` / `hasExtraLegroom` — all optional, default false/[])
- `quickReplyRow(options: [HermesQuickReplyOption])` — one-tap reply chips.
  Wire format: `{ "type": "quickReplyRow", "options": [...] }`.
  - `HermesQuickReplyOption` (`id`, `label`, `systemImage?`, `deepLinkURL?` — defaults to
    `hermesshare://action?id=<id>` when omitted)

## Interaction model (the important design decision)

- Seat taps are **local selection only** (fill/border change on the seat cell, no button chrome).
  A separate `HermesPrimaryCTA` labeled "Confirm Seat X" (disabled until a seat is picked)
  fires a synthesized `HermesAction(id: "seat-confirm", deepLinkURL: ...&seat=<id>)`.
- Quick-reply chips commit immediately on tap (capsule `.glass` buttons — visually distinct
  from the primary CTA).
- Both flow through the existing GamePigeon reply-insert mechanism: the renderer's `onAction`
  closure is now also published to nested node views via a new `\.hermesOnAction` environment
  key, so in the extension both routes hit the untouched
  `MessagesViewController.handle(_:sourceLayout:conversation:)`.

## Files touched

- `Shared/Sources/HermesShared/HermesLayout.swift` — new node cases + `HermesSeat`,
  `HermesSeatRow`, `HermesQuickReplyOption` structs.
- `Shared/Sources/HermesShared/HermesLayoutCodable.swift` — hand-written Codable for the two
  new cases (Kind + CodingKeys extended) and lenient Codable for `HermesSeat`/`HermesSeatRow`.
- `Shared/Sources/HermesShared/HermesLayoutRenderer.swift` —
  - New `HermesPrimaryCTA` public component: the single primary-action button (full-width,
    `.buttonStyle(.glassProminent)`, `.controlSize(.large)`), now used by BOTH the layout-level
    `actionBar` (previously `.borderedProminent`) and the seat chart's Confirm button.
  - New `HermesSeatChartView` (local `@State` selection, legend, aisle gaps, row-metadata
    caption under the row, 24×28pt cells so a 9-abreast 3-3-3 grid fits a card without
    horizontal scrolling; wider layouts scroll horizontally).
  - New `HermesQuickReplyRowView` (horizontal scrolling capsule `.glass` chips).
  - New `\.hermesOnAction` environment key (default `HermesActionHandler.openDeepLink`).
- `Shared/Sources/HermesShared/HermesSampleLayouts.swift` — added `seatSelection` (BR 26
  TPE→SFO, 5 rows, bulkhead/exit-row metadata, mixed availability) and `quickReply`
  (dinner RSVP) samples; both in `all`.
- `Shared/Sources/HermesShared/HERMES_LAYOUT_GUIDE.md` — **new**: full JSON schema doc for
  every node case with example snippets; the reference a future Hermes session should read
  instead of the Swift source.
- `Shared/Package.swift` — added `exclude: ["HERMES_LAYOUT_GUIDE.md"]` only (tools-version /
  platform / language-mode untouched).
- `Shared/Tests/HermesSharedTests/HermesLayoutCodableTests.swift` — 3 new tests (seatChart
  raw-JSON + lenient defaults, quickReplyRow raw-JSON, unknown seat state throws); the
  existing sample round-trip test now covers the new nodes via `all`.
- `HermesShare/Sources/DebugHarnessView.swift` — harness now passes an explicit `onAction`
  that records the fired action in-app (shows the "Action fired" sheet) instead of
  round-tripping a `hermesshare://` URL through the OS. Reason: on a shared simulator another
  app claimed the `hermesshare` scheme and stole the deep link; in production the extension
  handles actions itself anyway.

## NOT changed (per brief)

- `MessagesViewController.swift` — zero changes; reply-insert mechanism and the `data:` URL
  decode path are untouched. New interactions route through the existing `onAction` → `handle()`.
- `Shared/Package.swift` tools-version 6.2 / `.iOS(.v26)` / `swiftLanguageMode(.v5)`.

## Verification performed

- `xcodegen generate` + `xcodebuild -configuration Release -destination "generic/platform=iOS"`
  → `** BUILD SUCCEEDED **` (run twice: after schema work and again after final renderer polish).
- All 8 unit tests pass on iPhone 17 Pro simulator (`** TEST SUCCEEDED **`).
- Simulator screenshots (in `build/screenshots/`, taken on a dedicated iPhone 17 sim,
  inspected by eye):
  - `seatchart-mid-selection.png` — seat 22A solid green/white, available seats outlined,
    taken gray, two aisle gaps, "Bulkhead"/"Exit row · Extra legroom" captions, CTA reads
    "Confirm Seat 22A".
  - `seatchart-after-confirm.png` — "Action fired" sheet with
    `hermesshare://action?id=seat-confirm&seat=22A`.
  - `quickreply-row.png` — RSVP card with purple capsule glass chips (third chip peeking,
    row scrolls).
  - `package-tracking-regression.png` — pre-existing card still renders correctly with the
    unified glass CTA style.

## Known rough edges

- Seat cells are 24×28pt — below the 44pt HIG tap-target minimum (inherent to fitting a
  9-abreast grid in an iMessage card; GamePigeon boards make the same trade).
- The seat-chart confirm flow was verified in the host debug harness, not inside a live
  Messages conversation; it routes through the exact same `onAction` path the extension wires
  to `handle()`, but a physical-device iMessage round-trip of specifically the seat card has
  not been re-run.
- Chips row: on narrow cards the trailing chip is intentionally cut at the card edge to
  signal horizontal scrollability.
