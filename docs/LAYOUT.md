# HermesLayout Authoring Guide

The complete JSON schema for HermesShare cards. Read this instead of re-deriving the schema
from `HermesLayout.swift` / `HermesLayoutCodable.swift`. Every card is one JSON document that
the fixed native renderer (`HermesLayoutRenderer.swift`) interprets — no code ships in the
payload, only parameters for a fixed vocabulary of SwiftUI primitives.

## Transport

The layout JSON is compact-encoded, base64url'd, and carried in `MSMessage.url`. Two accepted
URL shapes (see `MessagesViewController.layout(from:)`):

1. `hermesshare://card?p=<base64url-json>` — internal scheme.
2. `data:application/json;base64,<base64>` — **required for the Linq API** (`imessage_app`
   message part), which only accepts `https://` or `data:` URLs, never custom schemes.

## Top-level document

```json
{
  "version": 1,
  "title": "Pick Your Seat",                  // optional — card header line
  "subtitle": "BR 26 · TPE → SFO",            // optional — header second line
  "accentColorHex": "#00875A",                // optional — tints icons, CTAs, seat fills
  "background": { "kind": "plain" },          // optional — "plain" or {"kind":"gradient","colorsHex":["#...","#..."]}
  "root": { "type": "vstack", ... },          // required — the node tree (see below)
  "actions": [                                 // optional — bottom-of-card primary CTA button(s)
    { "id": "book", "label": "Book on EVA Air", "systemImage": "airplane",
      "deepLinkURL": "hermesshare://action?id=book" }
  ]
}
```

Tapping an action button inside iMessage composes a reply `MSMessage` and inserts it into the
conversation (the GamePigeon mechanic). Outside iMessage it opens `deepLinkURL`.

## Interaction design grammar (important — read before designing a card)

- **Primary CTA** (`actions` array, or the seat chart's built-in Confirm button): full-width
  tinted Liquid Glass button at the bottom of the card. This is the ONLY element that looks
  like "press me to commit." One per card is ideal.
- **Quick-reply chips** (`quickReplyRow`): capsule glass buttons; a tap commits immediately.
  Use only for one-step choices (yes/no, RSVP, pick-one) — never for multi-step flows.
- **Selection state** (`seatChart` seats): tapping changes fill/border on the element itself,
  no button chrome. Selection never sends anything — the primary CTA does.

If an interaction needs "pick, then confirm," model it like `seatChart` (local state + CTA).
If it's a single irreversible choice, use `quickReplyRow`.

## Node types (`root` tree)

Every node is `{ "type": "<name>", ...payload }`. Unknown types fail decoding — the whole
card is rejected, so never invent node types.

### `vstack` / `hstack` — containers

```json
{ "type": "vstack", "spacing": 12, "alignment": "leading", "children": [ ... ] }
{ "type": "hstack", "spacing": 8, "alignment": "center", "children": [ ... ] }
```
- `spacing` optional (default 8). `alignment` optional: vstack takes
  `"leading" | "center" | "trailing"`, hstack takes `"top" | "center" | "bottom" | "firstTextBaseline"`.

### `text`

```json
{ "type": "text", "text": "ETA 2:40 PM",
  "style": { "role": "headline", "weight": "semibold", "colorHex": "#8E8E93", "alignment": "leading" } }
```
- `style` and all its fields optional (defaults: `body` / `regular` / primary color / leading).
- `role`: `largeTitle | title | title2 | title3 | headline | body | subheadline | footnote | caption`
- `weight`: `regular | medium | semibold | bold`

### `icon`

```json
{ "type": "icon", "systemName": "airplane", "sizePt": 20, "colorHex": "#00875A" }
```
- SF Symbol name. `sizePt` optional (default 20); `colorHex` optional (defaults to accent).

### `statusBadge`

```json
{ "type": "statusBadge", "label": "On Time", "colorHex": "#34C759" }
```
Capsule pill with a colored dot. Both fields required.

### `progressRing` / `progressBar`

```json
{ "type": "progressRing", "value": 0.92, "label": "uptime", "colorHex": "#30D158" }
{ "type": "progressBar", "value": 0.78, "colorHex": "#34C759" }
```
`value` is 0.0–1.0 (required); `label`/`colorHex` optional.

### `divider` / `spacer`

```json
{ "type": "divider" }
{ "type": "spacer", "minLength": 8 }
```
`minLength` optional.

### `keyValueRow`

```json
{ "type": "keyValueRow", "key": "Gate", "value": "B12" }
```
Left-aligned secondary key, right-aligned medium-weight value. Both required.

### `mapPreview`

```json
{ "type": "mapPreview", "latitude": 37.7793, "longitude": -122.4192, "label": "Civic Center" }
```
Static (non-pannable) map snapshot with a marker. `label` optional.

### `image`

```json
{ "type": "image", "url": "https://example.com/photo.jpg", "aspectRatio": 1.78, "cornerRadius": 12 }
```
Remote image with placeholder/progress states. `aspectRatio`/`cornerRadius` optional.

### `card`

```json
{ "type": "card", "padding": 16, "cornerRadius": 18, "backgroundHex": null,
  "child": { "type": "vstack", ... } }
```
- Omit `backgroundHex` (or set null) to get **real Liquid Glass** (`.glassEffect()`); set a
  hex color only when a flat fill is explicitly wanted. Prefer glass.
- `padding` default 16, `cornerRadius` default 16. `child` required (wrap multiple children
  in a `vstack`).

### `seatChart` — interactive two-step seat picker

```json
{
  "type": "seatChart",
  "selectedSeatId": null,
  "rows": [
    {
      "rowNumber": 22,
      "isExitRow": true,
      "isBulkhead": false,
      "hasExtraLegroom": true,
      "aisleAfterIndices": [2, 5],
      "seats": [
        { "id": "22A", "letter": "A", "state": "available" },
        { "id": "22B", "letter": "B", "state": "taken" },
        { "id": "22C", "letter": "C", "state": "available" },
        { "id": "22D", "letter": "D", "state": "available" },
        { "id": "22E", "letter": "E", "state": "unavailable" },
        { "id": "22F", "letter": "F", "state": "available" },
        { "id": "22G", "letter": "G", "state": "available" },
        { "id": "22H", "letter": "H", "state": "taken" },
        { "id": "22K", "letter": "K", "state": "available" }
      ]
    }
  ]
}
```
- Seat `state`: `available | taken | selected | unavailable` (optional, default `available`).
  `selected` pre-picks that seat (the user can still change it); `unavailable` renders dim.
- `aisleAfterIndices` (optional, default `[]`): 0-based seat indices after which an aisle gap
  is drawn. `[2, 5]` → 3-3-3 economy; `[1, 5]` → 2-4-2.
- Row flags `isExitRow` / `isBulkhead` / `hasExtraLegroom` all optional (default false);
  shown as a trailing "Exit · Legroom+" caption on the row.
- `selectedSeatId` (optional): alternative way to pre-select a seat by id.
- **The chart renders its own "Confirm Seat X" primary CTA** — do NOT also add a layout-level
  `actions` button for confirming the seat. Tapping seats only changes local selection; the
  Confirm button is what inserts the reply, carrying
  `hermesshare://action?id=seat-confirm&seat=<id>`.

### `quickReplyRow` — one-tap reply chips

```json
{ "type": "quickReplyRow", "options": [
  { "id": "rsvp-yes", "label": "I'm in", "systemImage": "checkmark" },
  { "id": "rsvp-no", "label": "Can't make it", "systemImage": "xmark" },
  { "id": "rsvp-later", "label": "Ask me later", "systemImage": "clock",
    "deepLinkURL": "hermesshare://action?id=rsvp-later&event=E-1" }
] }
```
- `systemImage` and `deepLinkURL` optional; `deepLinkURL` defaults to
  `hermesshare://action?id=<id>`.
- A chip tap **immediately** composes and inserts the reply — no confirm step. Only use for
  choices where instant commit is obviously the right behavior.

## Options with pictures (read this before saying "collapsibles aren't supported")

HermesShare **already supports** rich picture-based option cards and collapsible sections.
Use the node below that matches the interaction — never tell the user to wait for a schema update.

| Goal | Node | Interaction |
| --- | --- | --- |
| Pick one option (restaurants, flights, designs, products) with photos | `optionPicker` + `imageUrl` on each option | Tap to highlight → Confirm CTA |
| Browse hotels/listings with expandable photo cards | `photoCatalog` | Tap card to expand accordion → room gallery → optional Book CTA |
| Ranked "top N" with artwork per row | `mediaList` | Read-only list with thumbnails |
| Big hero gallery + detail blocks | `gallery` + `vstack` of `card` nodes | Scroll; no collapse needed |
| Multi-section plan with tap-to-expand sections | `collapsible` (stack in `vstack`) | Tap header to expand/collapse nested content |
| Always-visible steps | `timeline` | No collapse — use when everything should stay open |

### `optionPicker` with photos

Same as the standard picker, plus optional `imageUrl` per option (52×52 thumbnail in list style,
56×56 in grid style). `systemImage` is the fallback when the image fails to load.

```json
{
  "type": "optionPicker",
  "confirmLabel": "Book",
  "pickerStyle": "list",
  "options": [
    {
      "id": "mizuno",
      "label": "Okonomiyaki Mizuno",
      "sublabel": "Michelin Bib · ~20 min wait",
      "badge": "¥1,400",
      "imageUrl": "https://example.com/mizuno.jpg"
    }
  ]
}
```

### `photoCatalog` — collapsible listing cards (hotels, rentals, restaurants)

Full-bleed hero photos with **accordion expand/collapse** (one open at a time). Expanded state
reveals a horizontal room/photo gallery, amenity tags, detail text, and optional per-item
confirm button.

```json
{
  "type": "photoCatalog",
  "initialExpandedId": "millennials",
  "confirmLabel": "Book",
  "catalogItems": [
    {
      "id": "millennials",
      "heroImageUrl": "https://example.com/hero.jpg",
      "title": "The Millennials Kyoto",
      "subtitle": "Nakagyo · ★ 4.4",
      "priceText": "from $88",
      "priceUnit": "night",
      "rooms": [
        { "id": "pod", "imageUrl": "https://example.com/pod.jpg", "name": "Smart Pod", "price": "$88" }
      ],
      "tags": ["Free WiFi", "Smart pods"],
      "detail": "Capsule-style pods in central Kyoto."
    }
  ]
}
```

See `Shared/Tests/HermesSharedTests/Fixtures/sent_kyoto_catalog.json` for a complete example.

### `collapsible` — generic expand/collapse sections

For itineraries, FAQs, multi-step plans, or any section that should hide detail until tapped.
Stack several in a `vstack`. Each section wraps **any** child node (timeline, checklist, nested
cards, etc.).

```json
{
  "type": "collapsible",
  "sectionId": "osaka",
  "title": "Day 1–3 · Osaka",
  "subtitle": "Dotonbori, Namba, USJ",
  "badge": "3 nights",
  "initiallyExpanded": true,
  "imageUrl": "https://example.com/osaka.jpg",
  "child": {
    "type": "timeline",
    "entries": [
      { "time": "Day 1", "title": "Arrive KIX", "state": "past" }
    ]
  }
}
```

### `mediaList` — ranked rows with artwork

```json
{
  "type": "mediaList",
  "mediaItems": [
    {
      "id": "1",
      "rank": 1,
      "imageUrl": "https://example.com/cover.jpg",
      "title": "Midnight City",
      "subtitle": "M83",
      "trailing": "412M",
      "trailingSub": "streams"
    }
  ]
}
```

Demo fixtures: `demo_picture_restaurants.json`, `demo_picture_flights.json`,
`demo_app_designs.json`, `demo_collapsible_trip.json`, `sent_kyoto_catalog.json`.

## Scene heroes (v4 + v5) — the drawn centerpieces

This guide's node list above is the v1/v2 core. The vocabulary has since grown three
generations; the AUTHORITATIVE, fully-documented reference (exact JSON per node, examples,
composition doctrine) is the hermesshare-cards skill's `references/schema.md`. Summary:

- v3 content nodes: `checklist`, `timeline`, `rating`, `table`, `gallery`, `tagRow`, `stat`,
  `dateBadge`, `person`, `barChart`, `optionPicker` (supports `imageUrl` per option).
- v3+ picture/collapse nodes: `mediaList`, `photoCatalog` (accordion listings),
  `collapsible` (generic tap-to-expand sections).
- v4 scene heroes (payload nests under the noted key): `flightBoard` (`board`) — split-flap
  departure board; `platedDish` (`dish`) — procedural plated-dish scene; `gaugeCluster`
  (`gauges`) — cockpit arc gauges. Drawn in `HermesSceneViews.swift`.
- v5 scene heroes: `journeyArc` (`arc`) — route arc with vehicle at real progress;
  `skyScene` (`sky`) — procedural weather sky; `eventTicket` (`ticket`) — drawn ticket stub;
  `sparkline` (`spark`) — trend tile; `scoreBoard` (`score`) — split-flap scoreboard. Drawn
  in `HermesSceneViewsV5.swift`. Plus `"background": {"kind": "atmosphere"}` (dark scene
  canvas, content forced dark) and forward-compat: unknown node types decode to a visible
  `.unsupported` chip instead of failing the card (builds ≥ 2026-07-06.5 only).

Rule: if a card's genre has a scene hero, the hero LEADS the card; generic-node-only
compositions are the fallback, not the default.

## Working examples

`HermesSampleLayouts.swift` has eleven complete, tested layouts — five core
(`packageTracking`, `statDashboard`, `mapPreview`, `seatSelection`, `quickReply`), one v3
showcase (`tripDayPlan`), and five v5 scene showcases (`courierJourney`, `weatherTonight`,
`concertTicket`, `marketPulse`, `gameFinal`). To get their exact JSON, run the host app's
debug harness and tap the `{}` toolbar button, or call `try layout.encoded(pretty: true)`.

## Rules of thumb

- Always set `accentColorHex`, derived from the real content's brand/state (airline green,
  delivery green, alert red) — never decorative.
- Wrap supporting content in `card` nodes (flat adaptive background — never glass in the
  content layer). Scene heroes draw their own panels; never wrap them in a `card`.
- Pair dark scene heroes with the `atmosphere` background so the card reads as one world.
- Keep one primary CTA per card. Chips and seat taps are not CTAs.
- Colors: `#RRGGBB` or `#RRGGBBAA`.
