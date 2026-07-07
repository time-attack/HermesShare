# HermesShare

**Native iMessage cards, described by JSON, rendered by SwiftUI.**

HermesShare is an open-source iMessage App Extension that turns structured JSON into rich,
interactive cards inside Messages — package tracking, flight boards, trip plans, polls, hotel
catalogs, dashboards, and more. An AI agent (or any backend) sends a `HermesLayout` document
per message; a fixed native renderer draws it. No dynamic code execution, no web views in the
bubble — the same model as Scriptable or Widgy, App Store legal.

<p align="center">
  <img src="docs/screenshots/launch/05-courier-journey-delivery.png" width="280" alt="Courier journey card in iMessage" />
  <img src="docs/screenshots/launch/10-flight-board-boarding-pass.png" width="280" alt="Flight boarding pass card" />
  <img src="docs/screenshots/launch/13-trip-day-plan-vote.png" width="280" alt="Trip plan with dinner vote" />
</p>

## Why HermesShare

| Problem | HermesShare |
| --- | --- |
| Long markdown walls in iMessage | Structured cards with native UI |
| Web-view mini-apps feel disconnected | Real `MSMessageTemplateLayout` bubbles |
| Custom UI per message seems impossible on iOS | JSON selects from a fixed SwiftUI vocabulary |
| Agent replies are plain text | Tap-to-reply actions insert real messages back into the thread |

## Screenshots

Real device captures from Messages.app (tap a bubble to expand).

### Agent & productivity

| | |
| --- | --- |
| ![Agent checklist dashboard](docs/screenshots/launch/01-agent-checklist-dashboard.png) | **Agent checklist dashboard** — multi-section checklist with done/pending states (NYU enrollment re-check). |
| ![System health gauges](docs/screenshots/launch/11-system-health-gauges.png) | **System health** — gauge cluster for uptime, latency, and error rate with deploy summary. |

### Travel & logistics

| | |
| --- | --- |
| ![Japan itinerary flight board](docs/screenshots/launch/02-itinerary-flight-board.png) | **Trip itinerary** — flight board hero (NRT → SJC) inside a multi-day plan. |
| ![Hotel and flight timeline](docs/screenshots/launch/03-itinerary-hotel-and-flight.png) | **Hotel + flight timeline** — hotel stay block and chronological departure schedule. |
| ![Travel checklist](docs/screenshots/launch/04-itinerary-travel-checklist.png) | **Travel checklist** — pre-departure todos (train QR, check-in, baggage). |
| ![Flight boarding pass](docs/screenshots/launch/10-flight-board-boarding-pass.png) | **Flight board** — split-flap codes, boarding status, seat/baggage rows, boarding-pass CTA. |
| ![Courier journey](docs/screenshots/launch/05-courier-journey-delivery.png) | **Courier journey** — delivery arc, live timeline, door notification CTA. |
| ![Driver map preview](docs/screenshots/launch/07-map-preview-driver-arriving.png) | **Map preview** — MapKit preview with driver and vehicle details. |

### Interactive & social

| | |
| --- | --- |
| ![Trip day plan vote](docs/screenshots/launch/13-trip-day-plan-vote.png) | **Trip day plan** — date badge, timeline, and option picker to vote on dinner. |
| ![Quick reply RSVP](docs/screenshots/launch/09-quick-reply-dinner-rsvp.png) | **Quick reply** — one-tap RSVP chips for a group dinner invite. |
| ![Kyoto hotel catalog](docs/screenshots/launch/12-kyoto-hotel-catalog.png) | **Photo catalog** — full-bleed hotel cards with price pills and room gallery. |

### Live data & scenes

| | |
| --- | --- |
| ![Weather sky scene](docs/screenshots/launch/14-weather-tonight-sky.png) | **Weather tonight** — drawn sky scene with temp, location, and stat strip. |
| ![Market sparklines](docs/screenshots/launch/08-market-pulse-sparklines.png) | **Market pulse** — dual sparkline tiles for stock positions. |
| ![Game scoreboard](docs/screenshots/launch/06-game-final-scoreboard.png) | **Game final** — scoreboard hero with shooting-splits bar chart. |

## How it works

```text
Agent / backend                iMessage                    Device
─────────────                  ────────                    ──────
HermesLayout JSON  ──send──►  MSMessage bubble  ──tap──►  HermesLayoutRenderer
(base64url in URL)             (thumbnail + caption)        (native SwiftUI tree)
```

1. **Schema** — `HermesLayout` is a JSON document: metadata + recursive `HermesNode` tree.
2. **Transport** — payload is base64url-encoded in `MSMessage.url` (`?p=...`), via Photon
   `customizedMiniApp()` with an `https://` URL.
3. **Renderer** — one SwiftUI interpreter maps each node type to native controls (fixed
   vocabulary — no eval, no downloaded code).
4. **Actions** — `hermesshare://action?...` buttons insert reply messages into the thread.

Full JSON reference: [docs/LAYOUT.md](docs/LAYOUT.md)  
Sending guide: [docs/SENDING.md](docs/SENDING.md)

## Repository layout

```text
HermesShare/
├── Shared/                    Swift package — schema, Codable, renderer, samples
├── HermesShare/               Host app (debug harness for fast iteration)
├── HermesShareExtension/      iMessage App Extension (MessagesViewController)
├── docs/
│   ├── LAYOUT.md              HermesLayout authoring guide
│   ├── SENDING.md             Photon / transport instructions
│   └── screenshots/launch/    Product screenshots (this README)
├── scripts/                   Thumbnail helper, batch send, screenshot tools
└── project.yml                XcodeGen project definition
```

## Requirements

- macOS with **Xcode 26+**
- **iOS 26+** device or Simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Apple Development signing identity (free account works for Simulator and sideloading)

## Quick start

### 1. Clone and generate the Xcode project

```bash
git clone https://github.com/time-attack/HermesShare.git
cd HermesShare
xcodegen generate
open HermesShare.xcodeproj
```

### 2. Configure code signing

In `project.yml`, set `DEVELOPMENT_TEAM` under `settings.base` to your Apple team ID, then
regenerate:

```bash
xcodegen generate
```

Or set your team in Xcode → Signing & Capabilities for both **HermesShare** and
**HermesShareExtension**.

### 3. Build and run on Simulator

```bash
# Pick a simulator UDID
xcrun simctl list devices available | grep iPhone

xcodebuild -project HermesShare.xcodeproj -scheme HermesShare \
  -destination 'platform=iOS Simulator,id=YOUR_UDID' \
  -derivedDataPath build/DD build
```

Install and launch the host app, or run from Xcode (⌘R).

### 4. Try the debug harness (fastest iteration loop)

Open the **HermesShare** app in Simulator. Use the segmented control to flip between sample
layouts, or tap `{}` to paste/edit live JSON and watch it render with inline validation errors.

### 5. Try the iMessage extension

1. Run/install **HermesShare** on Simulator (embeds the extension).
2. Open **Messages** → any conversation → tap **+** → App Store icon → **HermesShare**.
3. In **Debug** Simulator builds, a compose gallery inserts sample cards into the thread.
4. Tap a bubble to expand; action buttons insert reply messages.

### 6. Run tests

```bash
xcodebuild -project HermesShare.xcodeproj -scheme HermesShare \
  -destination 'platform=iOS Simulator,id=YOUR_UDID' \
  -derivedDataPath build/DD test
```

Covers schema round-trip, transport encoding, routing logic, and render smoke tests.

## Sending cards from your agent

See [docs/SENDING.md](docs/SENDING.md) for Photon setup. Minimal flow:

```bash
python3 scripts/make_thumbnail.py my-card.json thumb.jpg
# … host https tunnel …
node send_card_photon.mjs '<compact-json>' '+1…' 'https://…/card.json' thumb.jpg
```

Copy `scripts/send_card_photon.mjs` into your Photon sidecar directory (or run from a folder
with `npm install spectrum-ts`), set `HERMES_TEAM_ID`, and send.

## Example JSON

```json
{
  "version": 1,
  "title": "Package Out for Delivery",
  "subtitle": "Order #HS-48213",
  "accentColorHex": "#34C759",
  "root": {
    "type": "vstack", "spacing": 12,
    "children": [
      { "type": "statusBadge", "label": "Out for delivery", "colorHex": "#34C759" },
      { "type": "progressBar", "value": 0.78, "colorHex": "#34C759" },
      { "type": "keyValueRow", "key": "Carrier", "value": "UPS Ground" }
    ]
  },
  "actions": [
    { "id": "track", "label": "View full tracking", "systemImage": "location.fill",
      "deepLinkURL": "hermesshare://action?id=track" }
  ]
}
```

More examples live in `Shared/Sources/HermesShared/HermesSampleLayouts.swift` and
`Shared/Tests/HermesSharedTests/Fixtures/`.

## Contributing

Contributions welcome — especially new `HermesNode` types, renderer polish, and fixture cards.
Open an issue before large schema changes. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) — use freely, attribution appreciated.

## Acknowledgments

Built for [Hermes](https://github.com/time-attack) agent-driven iMessage via
[Photon](https://photon.codes). Inspired by Scriptable and Widgy's declarative native UI model.
