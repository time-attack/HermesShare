# Sending cards to iMessage

HermesShare cards travel as compact JSON embedded in `MSMessage.url`. Senders must use an
**`https://` URL** with a `?p=<base64url-payload>` query item (Photon requirement — custom
schemes are not reliably delivered).

## Photon (recommended)

Requirements:

- [Photon](https://photon.codes) project with cloud/dedicated mode (`PHOTON_PROJECT_ID`,
  `PHOTON_PROJECT_SECRET` in your environment)
- HermesShare installed on the recipient device
- An existing iMessage thread with the recipient

### Send one card

```bash
# 1. Author a HermesLayout JSON file (see docs/LAYOUT.md)
# 2. Generate a text-free bubble thumbnail (JPEG — Photon rejects PNG)
python3 scripts/make_thumbnail.py my-card.json thumb.jpg

# 3. Host any https URL (payload lives in the query string, body optional)
python3 -m http.server 8934 --directory /path/to/static &
cloudflared tunnel --url http://localhost:8934   # copy the https://*.trycloudflare.com URL

# 4. Send (from a directory with spectrum-ts installed, e.g. your Photon sidecar)
export PHOTON_PROJECT_ID=… PHOTON_PROJECT_SECRET=… HERMES_TEAM_ID=YOUR_TEAM_ID
node scripts/send_card_photon.mjs \
  "$(python3 -c 'import json;print(json.dumps(json.load(open("my-card.json")),separators=(",",":")))')" \
  "+15551234567" \
  "https://YOUR-TUNNEL.trycloudflare.com/card.json" \
  thumb.jpg
```

A successful send prints `SENT:` with a message id. Photon rate-limits bursts (~10 messages per
30 seconds per recipient) — pace batch sends with a few seconds between cards.

### Send all built-in samples

From the repo root (exports JSON via unit test, then sends every sample + key fixtures):

```bash
./scripts/send_all_examples_photon.sh
```

Set `PHOTON_SEND_TO=+1...` to override the default recipient from `PHOTON_ALLOWED_USERS`.

## Wire format

```text
https://example.com/any-path?p=<base64url-compact-json>
```

The extension decodes the `p` query item back into a `HermesLayout`. Caption/subcaption on the
in-transcript bubble come from Photon's `customizedMiniApp` layout fields:

```javascript
{
  image: jpegBytes,
  imageTitle: "\u2060",      // invisible placeholder — real copy goes in caption/subcaption
  caption: layout.title,
  subcaption: layout.subtitle
}
```

## Action round-trip

Tapping a card action with a `hermesshare://action?...` deep link inserts a reply message into
the thread (GamePigeon-style). Wiring those taps to your agent backend is application-specific;
the extension UI and reply insert path are implemented in `MessagesViewController`.

## Linq alternative

Linq's `imessage_app` API accepts `data:application/json;base64,<payload>` URLs. See
[Photon interactive content docs](https://photon.codes/docs) and the Hermes agent
`hermesshare-cards` skill for a ready-made `send_card.py` sender.
