#!/usr/bin/env python3
"""Send a HermesShare interactive card into an iMessage conversation via the Linq API.

Usage:
    python3 send_card.py --to +1XXXXXXXXXX --layout '<json>' --caption "Title" --subcaption "Sub"
    python3 send_card.py --to +1XXXXXXXXXX --layout-file card.json --caption "Title"

Requires env vars:
    LINQ_API_TOKEN   - Bearer token from your Linq dashboard (API Playground shows it)
    LINQ_FROM_NUMBER - Your Linq virtual number, E.164 format (e.g. +13107287885)

This mirrors the exact wire format HermesShare's Swift decoder expects
(HermesLayoutCodable.decode(base64URLPayload:)) and the transport Linq requires
(data: URL, since Linq rejects custom URL schemes like hermesshare://).
"""
import argparse
import base64
import json
import os
import sys
import urllib.request
from typing import Optional

TEAM_ID = "6PPS68Y9RP"
EXTENSION_BUNDLE_ID = "com.hermesshare.app.MessagesExtension"
LINQ_ENDPOINT = "https://api.linqapp.com/api/partner/v3/chats"


def build_payload(layout: dict, to: str, from_number: str, caption: str, subcaption: Optional[str],
                   image_url: Optional[str] = None, image_title: Optional[str] = None,
                   image_subtitle: Optional[str] = None) -> dict:
    compact_json = json.dumps(layout, separators=(",", ":"))
    b64 = base64.b64encode(compact_json.encode("utf-8")).decode("ascii")
    data_url = f"data:application/json;base64,{b64}"

    layout_meta = {"caption": caption}
    if subcaption:
        layout_meta["subcaption"] = subcaption
    if image_url:
        layout_meta["image_url"] = image_url
    if image_title:
        layout_meta["image_title"] = image_title
    if image_subtitle:
        layout_meta["image_subtitle"] = image_subtitle

    return {
        "from": from_number,
        "to": [to],
        "message": {
            "parts": [
                {
                    "type": "imessage_app",
                    "app": {
                        "name": "HermesShare",
                        "team_id": TEAM_ID,
                        "bundle_id": EXTENSION_BUNDLE_ID,
                    },
                    "url": data_url,
                    "fallback_text": f"Open in HermesShare",
                    # Linq defaults to interactive=true, which wraps the balloon in an
                    # MSMessageLiveLayout. iOS then runs the extension INSIDE the bubble
                    # (presentationStyle == .transcript) and, on iOS 26, never delivers the tap —
                    # so the bubble could not be opened. A plain MSMessageTemplateLayout is opened
                    # by the system, which fires didSelect and expands the card normally.
                    # NOTE: not inherited by card updates — re-send it on any update_app_card call.
                    "interactive": False,
                    "layout": layout_meta,
                }
            ]
        },
    }


def send(payload: dict, token: str) -> dict:
    req = urllib.request.Request(
        LINQ_ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        print(f"HTTP {e.code}: {body}", file=sys.stderr)
        raise


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--to", required=True, help="Recipient phone number, E.164")
    ap.add_argument("--layout", help="HermesLayout JSON as a string")
    ap.add_argument("--layout-file", help="Path to a file containing HermesLayout JSON")
    ap.add_argument("--caption", required=True, help="Card title shown in the bubble")
    ap.add_argument("--subcaption", help="Card subtitle shown in the bubble")
    ap.add_argument("--image-url", help="HTTPS preview image URL (needs an established chat, see skill README)")
    ap.add_argument("--image-title", help="Bold text overlaid on the preview image")
    ap.add_argument("--image-subtitle", help="Text overlaid below image-title")
    args = ap.parse_args()

    token = os.environ.get("LINQ_API_TOKEN")
    from_number = os.environ.get("LINQ_FROM_NUMBER")
    if not token or not from_number:
        print("Set LINQ_API_TOKEN and LINQ_FROM_NUMBER env vars first.", file=sys.stderr)
        sys.exit(1)

    if args.layout:
        layout = json.loads(args.layout)
    elif args.layout_file:
        with open(args.layout_file) as f:
            layout = json.load(f)
    else:
        print("Provide --layout or --layout-file", file=sys.stderr)
        sys.exit(1)

    payload = build_payload(
        layout, args.to, from_number, args.caption, args.subcaption,
        args.image_url, args.image_title, args.image_subtitle,
    )
    result = send(payload, token)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
