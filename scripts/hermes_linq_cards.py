#!/usr/bin/env python3
"""HermesShare CARD sending + card-reply reading, packaged for a Hermes `linq` platform plugin.

Two capabilities, one module:

  send_card(...)          POST a native HermesShare card into an iMessage thread via the Linq
                          partner API.
  read_card_replies(...)  Read the structured form submissions back out of the LOCAL
                          ~/Library/Messages/chat.db.

Why the reply path is not Linq: an inbound `imessage_app` part from an extension with no
`app_store_id` is flattened by Linq's ingest to a single text part containing one U+FFFD
character BEFORE any REST response or webhook sees it. Verified across a full 86-message chat
history: the only inbound app parts that survive are GamePigeon's (app_store_id 1124197642).
So replies must be read from a Mac signed into the same Apple ID as the phone.

Dependencies:
  * stdlib only for the two capabilities themselves (urllib, sqlite3, plistlib, base64, json, re).
  * Pillow — ONLY for auto-rendering a bubble preview via scripts/make_thumbnail.py. Absent
    Pillow degrades to "send the card without a preview image", never to a failed send.
  * the `git` binary + push credentials — ONLY for publishing that preview to GitHub Pages.
    Same degradation.

Self-check:  python3 hermes_linq_cards.py --selftest
"""
from __future__ import annotations

import base64
import binascii
import datetime as _dt
import hashlib
import importlib.util
import json
import os
import plistlib
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Iterable, Optional

# --------------------------------------------------------------------------------------
# Transport constants — device-verified 2026-07-28. Do not "simplify" any of these.
# --------------------------------------------------------------------------------------

LINQ_BASE = "https://api.linqapp.com/api/partner/v3"
LINQ_CHATS_ENDPOINT = f"{LINQ_BASE}/chats"

# The iMessage extension the balloon is attributed to. No app_store_id: HermesShare is
# side-loaded, not on the App Store. (That absence is exactly why Linq flattens the reply.)
APP_IDENTITY = {
    "name": "HermesShare",
    "team_id": "6PPS68Y9RP",
    "bundle_id": "com.hermesshare.app.MessagesExtension",
}

# Linq accepts only https:// or data: in `url` — never a custom scheme like hermesshare://.
DATA_URL_PREFIX = "data:application/json;base64,"
MAX_URL_CHARS = 16384

REPO = Path(os.environ.get("HERMESSHARE_REPO", "~/Documents/HermesShare")).expanduser()
PREVIEW_SUBDIR = "docs/card-previews"
PAGES_BASE = "https://time-attack.github.io/HermesShare/card-previews"
PREVIEW_UA = "Mozilla/5.0 (HermesShare preview check)"

CHAT_DB = Path(os.environ.get("HERMES_CHAT_DB", "~/Library/Messages/chat.db")).expanduser()

# The submission rides in MSMessage.summaryText (persisted as `ldtext`) wrapped in
# U+2E22 … U+2E23. iOS keeps MSMessage.url in the local archive for a SENT message only when
# the balloon is a live layout, and referencing MSMessageLiveLayout makes the extension fail to
# load on iOS 26 — so this is the ONLY channel. Do not "optimise" it back to reading the URL.
TOKEN_RE = re.compile("⸢hs:([A-Za-z0-9_-]+)⸣")

# Apple epoch (2001-01-01) offset for message.date, which is in nanoseconds.
APPLE_EPOCH_OFFSET = 978307200

# What Linq substitutes for an inbound HermesShare balloon. Not a user message.
LINQ_FLATTENED_APP_PART = "�"


class LinqCardError(RuntimeError):
    """Anything that stops a card from being sent."""


class ChatDBAccessError(RuntimeError):
    """chat.db could not be opened — almost always missing Full Disk Access."""


# --------------------------------------------------------------------------------------
# Credentials
# --------------------------------------------------------------------------------------


def load_linq_env(path: str | os.PathLike = "~/.linq.env") -> None:
    """Populate LINQ_API_TOKEN / LINQ_FROM_NUMBER from a dotenv file (existing env wins).

    Never logs or returns the token.
    """
    p = Path(path).expanduser()
    if not p.is_file():
        return
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def _creds(api_token: Optional[str], from_number: Optional[str]) -> tuple[str, str]:
    token = api_token or os.environ.get("LINQ_API_TOKEN")
    sender = from_number or os.environ.get("LINQ_FROM_NUMBER")
    if not token or not sender:
        raise LinqCardError(
            "LINQ_API_TOKEN and LINQ_FROM_NUMBER must be set "
            "(call load_linq_env() or export them)."
        )
    return token, sender


# --------------------------------------------------------------------------------------
# Card validation — reuses scripts/validate_card.py, which scrapes the Swift enums at runtime
# so it cannot drift from the schema. HermesLayout decoding is ALL-OR-NOTHING: one unknown
# enum raw value throws and the whole card fails on device with
# "url: present but payload undecodable".
# --------------------------------------------------------------------------------------


def _load_validator(repo: Path):
    path = Path(repo) / "scripts/validate_card.py"
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location("hermes_validate_card", path)
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_layout(layout: dict, *, repo: Path = REPO) -> tuple[list[str], list[str]]:
    """(hard_errors, warnings). Raises if the validator/Swift source is not reachable —
    an unvalidated send costs a device round-trip, so refusing is the cheaper failure."""
    module = _load_validator(repo)
    if module is None:
        raise LinqCardError(
            f"validator not found at {repo}/scripts/validate_card.py — set HERMESSHARE_REPO "
            "to a checkout of time-attack/HermesShare, or pass validate=False and accept "
            "that a bad enum value will fail silently on device."
        )
    schema = module.load_schema()
    if not schema.get("role"):
        raise LinqCardError(
            f"could not scrape enums from the Swift source under {repo}/Shared/Sources — "
            "the checkout is incomplete."
        )
    issues = module.validate(layout, schema)
    hard = [i for i in issues if not i.startswith("WARN")]
    warn = [i for i in issues if i.startswith("WARN")]
    return hard, warn


def form_fields(layout: dict) -> list[str]:
    """Every `fieldId` in the tree, in document order. A card with any of these is a FORM."""
    found: list[str] = []

    def walk(node: Any) -> None:
        if isinstance(node, list):
            for n in node:
                walk(n)
        elif isinstance(node, dict):
            if node.get("fieldId"):
                found.append(node["fieldId"])
            for key in ("children", "child"):
                if key in node:
                    walk(node[key])

    walk(layout.get("root"))
    return found


def mint_form_id(prefix: str = "card") -> str:
    """Fresh, unique, opaque correlation token. The prefix is yours to encode context in
    (e.g. "checkin:CX885:AGZQ9B"); the suffix guarantees two sends are never confusable."""
    return f"{prefix}:{uuid.uuid4().hex[:8]}"


# --------------------------------------------------------------------------------------
# Bubble preview: render -> commit -> push -> wait for GitHub Pages
# --------------------------------------------------------------------------------------


def preview_slug(layout: dict, prefix: Optional[str] = None) -> str:
    """Deterministic per card content, so re-sending the same card reuses a published file."""
    compact = json.dumps(layout, separators=(",", ":"), sort_keys=True)
    digest = hashlib.sha1(compact.encode()).hexdigest()[:8]
    base = prefix or (layout.get("title") or "card")
    base = re.sub(r"[^a-z0-9]+", "-", str(base).lower()).strip("-")[:40] or "card"
    return f"{base}-{digest}"


def _url_is_live_image(url: str, timeout: float = 8.0) -> bool:
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": PREVIEW_UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status == 200 and resp.headers.get("Content-Type", "").startswith("image/")
    except Exception:
        return False


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, timeout=120
    )


def publish_preview(
    layout: dict,
    *,
    repo: Path = REPO,
    slug: Optional[str] = None,
    wait_seconds: float = 90.0,
) -> Optional[str]:
    """Render a text-free bubble thumbnail, publish it to GitHub Pages, return its URL.

    Returns None (never raises) if Pillow is missing, the render fails, git push fails, or
    Pages has not served the file within `wait_seconds`. The caller then sends the card with
    no `image_url` — and MUST NOT send image_title/image_subtitle, which Linq rejects on their
    own. A card with no preview still delivers; it just gets a plain caption bubble.
    """
    repo = Path(repo)
    slug = slug or preview_slug(layout)
    url = f"{PAGES_BASE}/{slug}.jpg"
    if _url_is_live_image(url):
        return url

    thumb_script = repo / "scripts/make_thumbnail.py"
    if not thumb_script.is_file():
        return None
    try:
        spec = importlib.util.spec_from_file_location("hermes_make_thumbnail", thumb_script)
        if spec is None or spec.loader is None:
            return None
        maker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(maker)  # imports PIL
        image = maker.render(layout)
    except Exception:
        return None  # no Pillow, no network for a hero photo, bad layout — all non-fatal

    out = repo / PREVIEW_SUBDIR / f"{slug}.jpg"
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        image.save(out, "JPEG", quality=92, optimize=True)
        rel = f"{PREVIEW_SUBDIR}/{slug}.jpg"
        if _git(repo, "add", "--", rel).returncode != 0:
            return None
        # No-op commit when the bytes are unchanged; that is fine, we only need the push.
        _git(repo, "commit", "-m", f"Add card preview {slug}", "--", rel)
        if _git(repo, "push").returncode != 0:
            return None
    except Exception:
        return None

    deadline = time.monotonic() + wait_seconds
    while time.monotonic() < deadline:
        if _url_is_live_image(url):
            return url
        time.sleep(3.0)
    return None


# --------------------------------------------------------------------------------------
# send_card
# --------------------------------------------------------------------------------------


def build_card_body(
    layout: dict,
    *,
    to: str,
    from_number: str,
    caption: str,
    subcaption: Optional[str] = None,
    image_url: Optional[str] = None,
    fallback_text: str = "Open in HermesShare",
) -> dict:
    """The exact JSON body POSTed to /chats. Pure — no I/O, so it is unit-testable."""
    compact = json.dumps(layout, separators=(",", ":"), ensure_ascii=False)
    data_url = DATA_URL_PREFIX + base64.b64encode(compact.encode("utf-8")).decode("ascii")
    if len(data_url) > MAX_URL_CHARS:
        raise LinqCardError(
            f"payload is {len(data_url)} chars, over the {MAX_URL_CHARS} cap. Shorten the card: "
            "fewer options/rows, drop long image URLs, collapse prose into badges."
        )

    layout_meta: dict[str, str] = {"caption": caption}
    if subcaption:
        layout_meta["subcaption"] = subcaption
    if image_url:
        # image_title/image_subtitle are NEVER sent: Linq rejects them without image_url, and
        # Apple renders image_title in a footer strip that duplicates the caption.
        layout_meta["image_url"] = image_url

    return {
        "from": from_number,
        "to": [to],
        "message": {
            "parts": [
                {
                    "type": "imessage_app",
                    "app": dict(APP_IDENTITY),
                    "url": data_url,
                    "fallback_text": fallback_text,
                    # Linq DEFAULTS this to true, which wraps the balloon in an
                    # MSMessageLiveLayout. iOS then runs the extension inside the bubble in
                    # .transcript style and on iOS 26 the tap is never delivered — the card
                    # cannot be opened at all, and a live layout has no image slot. false emits
                    # a plain MSMessageTemplateLayout that the system opens on tap.
                    # NOT inherited by card updates — re-send it on every update.
                    "interactive": False,
                    "layout": layout_meta,
                }
            ]
        },
    }


def _post_json(url: str, body: dict, token: str, timeout: float) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:2000]
        raise LinqCardError(f"Linq HTTP {exc.code}: {detail}") from None
    except urllib.error.URLError as exc:
        raise LinqCardError(f"Linq unreachable: {exc.reason}") from None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}


def send_card(
    to: str,
    layout: dict,
    *,
    caption: Optional[str] = None,
    subcaption: Optional[str] = None,
    form_id: Optional[str] = None,
    image_url: Optional[str] = None,
    publish_preview_image: bool = True,
    fallback_text: str = "Open in HermesShare",
    from_number: Optional[str] = None,
    api_token: Optional[str] = None,
    repo: Path = REPO,
    validate: bool = True,
    preview_timeout: float = 90.0,
    timeout: float = 30.0,
    dry_run: bool = False,
) -> dict:
    """Send a native HermesShare card into `to`'s iMessage thread via Linq.

    to          recipient in E.164 ("+15551234567").
    layout      a HermesLayout dict (see docs/LAYOUT.md). MUTATED only to stamp `formId`.
    caption     bubble title; defaults to layout["title"].
    subcaption  bubble subtitle; defaults to layout["subtitle"].
    form_id     correlation PREFIX for a form card. A fresh unique suffix is always appended,
                so the returned formId — not this argument — is what the reply echoes.
    image_url   skip preview generation and use this HTTPS image instead.
    validate    run scripts/validate_card.py first; hard errors abort the send.

    Returns {"ok", "formId", "fields", "caption", "subcaption", "preview_url",
             "payload_chars", "warnings", "response"}.
    """
    token, sender = ("", "") if dry_run else _creds(api_token, from_number)

    fields = form_fields(layout)
    if fields:
        prefix = form_id or layout.get("formId") or "card"
        layout["formId"] = mint_form_id(prefix)
    elif form_id:
        layout["formId"] = mint_form_id(form_id)

    warnings: list[str] = []
    if validate:
        hard, warn = validate_layout(layout, repo=repo)
        if hard:
            raise LinqCardError("card failed validation:\n  " + "\n  ".join(hard))
        warnings += warn

    caption = caption or layout.get("title") or "HermesShare"
    subcaption = subcaption if subcaption is not None else layout.get("subtitle")

    preview = image_url
    if preview is None and publish_preview_image:
        preview = publish_preview(layout, repo=repo, wait_seconds=preview_timeout)
        if preview is None:
            warnings.append(
                "WARN no preview published — sending without image_url (bubble shows "
                "caption/subcaption only). Never add image_title/image_subtitle to compensate."
            )

    body = build_card_body(
        layout,
        to=to,
        from_number=sender or "+00000000000",
        caption=caption,
        subcaption=subcaption,
        image_url=preview,
        fallback_text=fallback_text,
    )
    payload_chars = len(body["message"]["parts"][0]["url"])

    result = {
        "ok": True,
        "formId": layout.get("formId"),
        "fields": fields,
        "caption": caption,
        "subcaption": subcaption,
        "preview_url": preview,
        "payload_chars": payload_chars,
        "warnings": warnings,
        "response": None,
    }
    if dry_run:
        result["body"] = body
        return result
    result["response"] = _post_json(LINQ_CHATS_ENDPOINT, body, token, timeout)
    return result


# --------------------------------------------------------------------------------------
# read_card_replies
# --------------------------------------------------------------------------------------

# The reply row is authored by the USER on their phone and syncs to this Mac as is_from_me=1.
# ROWID (not date) is the high-water mark: a row that syncs late still gets a NEW, higher
# ROWID, so nothing is ever missed, whereas date ordering can backfill below the mark.
#
# NEVER filter on time with strftime: strftime('%s',…) returns TEXT and SQLite ranks every
# INTEGER below every TEXT, so `date/1000000000+978307200 > strftime('%s',…)` is ALWAYS FALSE
# and silently returns zero rows.
REPLY_SQL = """
SELECT m.ROWID, m.guid, m.date, m.payload_data, h.id AS handle, c.chat_identifier
FROM message m
LEFT JOIN handle h ON h.ROWID = m.handle_id
LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
LEFT JOIN chat c ON c.ROWID = cmj.chat_id
WHERE m.is_from_me = 1
  AND m.balloon_bundle_id LIKE '%hermesshare%'
  AND m.payload_data IS NOT NULL
  AND m.ROWID > :since_rowid
ORDER BY m.ROWID DESC
LIMIT :limit
"""


def _connect_chat_db(db_path: Path) -> sqlite3.Connection:
    try:
        return sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    except sqlite3.OperationalError as exc:
        pass
    # ponytail: a 600 MB copy is a heavy fallback, but it is the only way to read a WAL-mode
    # chat.db that will not hand out a -shm mapping. Only reached when the direct open fails.
    try:
        tmp = Path(tempfile.mkdtemp(prefix="hermes-chatdb-"))
        for suffix in ("", "-wal", "-shm"):
            src = Path(str(db_path) + suffix)
            if src.exists():
                shutil.copy2(src, tmp / (db_path.name + suffix))
        return sqlite3.connect(f"file:{tmp / db_path.name}?mode=ro", uri=True)
    except Exception:
        raise ChatDBAccessError(
            f"cannot open {db_path}. Grant Full Disk Access to the process that runs the Hermes "
            "gateway (System Settings > Privacy & Security > Full Disk Access — add the actual "
            "binary, e.g. /usr/bin/python3 or Terminal.app, then restart it). Also confirm this "
            "Mac is signed into the same Apple ID as the phone and Messages in iCloud is on."
        ) from None


def decode_submission(payload_data: bytes) -> Optional[dict]:
    """Pull the HermesSubmission out of a message's NSKeyedArchiver payload_data.

    The token lives in the archived summaryText string (`ldtext`) as ⸢hs:<base64url>⸣. We scan
    every string in $objects rather than walking $top->root, so a change in the archive's key
    layout cannot break this.
    """
    try:
        archive = plistlib.loads(payload_data)
    except Exception:
        return None
    for obj in archive.get("$objects", []):
        if not isinstance(obj, str):
            continue
        match = TOKEN_RE.search(obj)
        if not match:
            continue
        token = match.group(1)
        padded = token.replace("-", "+").replace("_", "/")
        padded += "=" * (-len(padded) % 4)
        try:
            submission = json.loads(base64.b64decode(padded).decode("utf-8"))
        except (binascii.Error, UnicodeDecodeError, json.JSONDecodeError, ValueError):
            continue
        return submission if _submission_is_sane(submission) else None
    return None


def _submission_is_sane(sub: Any) -> bool:
    """Trust boundary: this arrived from a device, validate its shape before acting on it."""
    if not isinstance(sub, dict):
        return False
    if sub.get("protocol") != 2:
        return False
    if not isinstance(sub.get("actionId"), str) or not sub["actionId"]:
        return False
    values = sub.get("values")
    if not isinstance(values, dict):
        return False
    # values are ALWAYS arrays of raw option ids, never labels. An unanswered field is OMITTED
    # (absent never means false); a deliberately emptied multi-select is [].
    return all(
        isinstance(k, str) and isinstance(v, list) and all(isinstance(i, str) for i in v)
        for k, v in values.items()
    )


def _apple_date_to_iso(raw: Optional[int]) -> Optional[str]:
    if not raw:
        return None
    seconds = raw / 1_000_000_000 + APPLE_EPOCH_OFFSET if raw > 10**11 else raw + APPLE_EPOCH_OFFSET
    return _dt.datetime.fromtimestamp(seconds, _dt.timezone.utc).isoformat()


def read_card_replies(
    *,
    since_rowid: int = 0,
    limit: int = 50,
    form_id: Optional[str] = None,
    form_id_prefix: Optional[str] = None,
    db_path: Path = CHAT_DB,
) -> list[dict]:
    """Structured HermesShare form submissions, oldest first.

    since_rowid      only rows with message.ROWID greater than this (the dedup high-water mark).
    form_id          exact match against the value send_card() returned.
    form_id_prefix   match everything minted from one correlation prefix.

    Each item: {rowid, guid, date, chat_identifier, handle, formId, actionId, protocol, values}.
    Advance your stored high-water mark to max(rowid) of what you processed — NOT to a
    timestamp, and not before processing succeeds.
    """
    con = _connect_chat_db(Path(db_path))
    con.row_factory = sqlite3.Row
    try:
        rows = con.execute(
            REPLY_SQL, {"since_rowid": int(since_rowid), "limit": int(limit)}
        ).fetchall()
    finally:
        con.close()

    out: list[dict] = []
    for row in rows:
        submission = decode_submission(row["payload_data"])
        if submission is None:
            continue
        fid = submission.get("formId")
        if form_id is not None and fid != form_id:
            continue
        if form_id_prefix is not None and not (
            isinstance(fid, str) and fid.startswith(form_id_prefix)
        ):
            continue
        out.append(
            {
                "rowid": row["ROWID"],
                "guid": row["guid"],
                "date": _apple_date_to_iso(row["date"]),
                "chat_identifier": row["chat_identifier"],
                "handle": row["handle"],
                "formId": fid,
                "actionId": submission["actionId"],
                "protocol": submission["protocol"],
                "values": submission["values"],
            }
        )
    out.reverse()  # oldest first: process in the order the user submitted
    return out


def poll_card_replies(
    state_path: str | os.PathLike = "~/.hermes/linq_card_replies.json",
    **kwargs: Any,
) -> list[dict]:
    """read_card_replies() with the ROWID high-water mark persisted, so a submission is never
    processed twice. The mark advances only after this call returns rows to you — if your
    handler raises, do not call again until it has succeeded, or pass since_rowid yourself."""
    path = Path(state_path).expanduser()
    mark = 0
    if path.is_file():
        try:
            mark = int(json.loads(path.read_text()).get("last_rowid", 0))
        except Exception:
            mark = 0
    replies = read_card_replies(since_rowid=mark, **kwargs)
    if replies:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"last_rowid": max(r["rowid"] for r in replies)}))
    return replies


def is_flattened_card_reply(text: Optional[str]) -> bool:
    """True for the single U+FFFD text part Linq substitutes for an inbound HermesShare
    balloon. The plugin's Linq inbound handler must NOT treat this as a user message — it is
    the signal to go read chat.db instead."""
    return bool(text) and text.strip() == LINQ_FLATTENED_APP_PART


# --------------------------------------------------------------------------------------
# Self-check
# --------------------------------------------------------------------------------------


def _selftest() -> None:
    # -- 1. wire body -------------------------------------------------------------------
    layout = {
        "version": 1,
        "title": "Check in for CX885",
        "subtitle": "Departs 09:45",
        "root": {
            "type": "vstack",
            "spacing": 12,
            "children": [
                {
                    "type": "flightBoard",
                    "board": {"origin": "HKG", "destination": "LAX", "status": "On time"},
                },
                {
                    "type": "optionPicker",
                    "fieldId": "bags",
                    "pickerStyle": "list",
                    "options": [
                        {"id": "bag-0", "label": "No checked bag"},
                        {"id": "bag-2", "label": "2 checked bags"},
                    ],
                },
            ],
        },
        "actions": [
            {
                "id": "checkin-submit",
                "label": "Confirm check-in",
                "deepLinkURL": "hermesshare://action?id=checkin-submit",
            }
        ],
    }
    result = send_card(
        "+15551234567",
        layout,
        dry_run=True,
        validate=False,
        publish_preview_image=False,
        form_id="checkin:CX885:AGZQ9B",
    )
    part = result["body"]["message"]["parts"][0]
    assert part["interactive"] is False, "interactive MUST be false"
    assert part["app"] == APP_IDENTITY and "app_store_id" not in part["app"]
    assert part["url"].startswith(DATA_URL_PREFIX)
    assert "image_title" not in part["layout"] and "image_subtitle" not in part["layout"]
    assert part["layout"]["caption"] == "Check in for CX885"
    assert result["fields"] == ["bags"]
    assert result["formId"].startswith("checkin:CX885:AGZQ9B:")
    assert layout["formId"] == result["formId"], "formId must be stamped into the sent layout"
    assert mint_form_id("x") != mint_form_id("x"), "formIds must be unique per send"
    # the base64 in the data: URL round-trips to the exact layout we passed in
    decoded = json.loads(base64.b64decode(part["url"][len(DATA_URL_PREFIX):]))
    assert decoded == layout

    # -- 2. payload cap -----------------------------------------------------------------
    fat = {"version": 1, "title": "x", "root": {"type": "text", "text": "y" * 20000}}
    try:
        build_card_body(fat, to="+1", from_number="+1", caption="x")
        raise AssertionError("oversized payload must be rejected")
    except LinqCardError as exc:
        assert str(MAX_URL_CHARS) in str(exc)

    # -- 3. validator wiring ------------------------------------------------------------
    if (REPO / "scripts/validate_card.py").is_file():
        hard, _ = validate_layout(layout, repo=REPO)
        assert hard == [], hard
        bad = json.loads(json.dumps(layout))
        bad["root"]["children"][1]["pickerStyle"] = "carousel"
        hard, _ = validate_layout(bad, repo=REPO)
        assert any("pickerStyle" in h for h in hard), hard

    # -- 4. submission decode, against the verified real payload shape ------------------
    real = {
        "protocol": 2,
        "formId": "checkin:CX885:AGZQ9B:live1",
        "actionId": "checkin-submit",
        "values": {"seat": ["22F"], "bags": ["bag-2"]},
    }
    token = (
        base64.b64encode(json.dumps(real, separators=(",", ":")).encode())
        .decode()
        .replace("+", "-")
        .replace("/", "_")
        .rstrip("=")
    )
    archive = plistlib.dumps(
        {
            "$version": 100000,
            "$archiver": "NSKeyedArchiver",
            "$top": {"root": plistlib.UID(1)},
            "$objects": [
                "$null",
                {"ldtext": plistlib.UID(2), "caption": plistlib.UID(3)},
                f"Check in for CX885 ⸢hs:{token}⸣",
                "Check in for CX885",
            ],
        },
        fmt=plistlib.FMT_BINARY,
    )
    assert decode_submission(archive) == real
    assert decode_submission(b"not a plist") is None
    # a card bubble with no submission (an outbound card) yields nothing
    plain = plistlib.dumps({"$objects": ["$null", "Check in for CX885"]}, fmt=plistlib.FMT_BINARY)
    assert decode_submission(plain) is None
    # protocol/shape guards
    for broken in (
        {"protocol": 1, "actionId": "a", "values": {}},
        {"protocol": 2, "actionId": "", "values": {}},
        {"protocol": 2, "actionId": "a", "values": {"seat": "22F"}},  # not an array
    ):
        tok = base64.b64encode(json.dumps(broken).encode()).decode().rstrip("=")
        arch = plistlib.dumps({"$objects": [f"⸢hs:{tok}⸣"]}, fmt=plistlib.FMT_BINARY)
        assert decode_submission(arch) is None, broken

    # -- 5. SQL + dedup, against a synthetic chat.db ------------------------------------
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / "chat.db"
        con = sqlite3.connect(db)
        con.executescript(
            """
            CREATE TABLE message (ROWID INTEGER PRIMARY KEY, guid TEXT, date INTEGER,
                is_from_me INTEGER, handle_id INTEGER, balloon_bundle_id TEXT, payload_data BLOB);
            CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
            CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT);
            CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
            INSERT INTO handle VALUES (1, '+13105551212');
            INSERT INTO chat VALUES (1, '+13105551212');
            """
        )
        bid = "com.hermesshare.app.MessagesExtension:HermesShare"
        con.execute(
            "INSERT INTO message VALUES (10,'g10',780000000000000000,1,1,?,?)", (bid, archive)
        )
        con.execute("INSERT INTO message VALUES (11,'g11',780000000000000001,0,1,?,?)", (bid, archive))
        con.execute("INSERT INTO message VALUES (12,'g12',780000000000000002,1,1,'com.apple.messages.text',NULL)")
        con.executemany("INSERT INTO chat_message_join VALUES (1, ?)", [(10,), (11,), (12,)])
        con.commit()
        con.close()

        got = read_card_replies(db_path=db)
        assert len(got) == 1, got            # inbound + non-card rows excluded
        assert got[0]["rowid"] == 10
        assert got[0]["values"] == {"seat": ["22F"], "bags": ["bag-2"]}
        assert got[0]["formId"] == "checkin:CX885:AGZQ9B:live1"
        assert got[0]["chat_identifier"] == "+13105551212"
        assert got[0]["date"].startswith("2025-09-")
        assert read_card_replies(db_path=db, since_rowid=10) == []   # high-water mark works
        assert read_card_replies(db_path=db, form_id="nope") == []
        assert len(read_card_replies(db_path=db, form_id_prefix="checkin:CX885")) == 1

        state = Path(tmp) / "hwm.json"
        assert len(poll_card_replies(state, db_path=db)) == 1
        assert poll_card_replies(state, db_path=db) == []  # not processed twice

    assert is_flattened_card_reply("�") and not is_flattened_card_reply("hello")
    print("selftest OK")


def _cli() -> int:
    import argparse

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--send", metavar="E164", help="recipient phone number")
    ap.add_argument("--layout-file")
    ap.add_argument("--caption")
    ap.add_argument("--subcaption")
    ap.add_argument("--form-id", help="correlation prefix; a unique suffix is appended")
    ap.add_argument("--image-url")
    ap.add_argument("--no-preview", action="store_true")
    ap.add_argument("--no-validate", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--read", action="store_true", help="read card replies from chat.db")
    ap.add_argument("--since-rowid", type=int, default=0)
    ap.add_argument("--form-id-prefix")
    args = ap.parse_args()

    if args.selftest:
        _selftest()
        return 0
    load_linq_env()
    if args.send:
        if not args.layout_file:
            ap.error("--send needs --layout-file")
        layout = json.loads(Path(args.layout_file).read_text())
        result = send_card(
            args.send,
            layout,
            caption=args.caption,
            subcaption=args.subcaption,
            form_id=args.form_id,
            image_url=args.image_url,
            publish_preview_image=not args.no_preview,
            validate=not args.no_validate,
            dry_run=args.dry_run,
        )
        print(json.dumps(result, indent=2))
        return 0
    if args.read:
        print(
            json.dumps(
                read_card_replies(
                    since_rowid=args.since_rowid, form_id_prefix=args.form_id_prefix
                ),
                indent=2,
            )
        )
        return 0
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(_cli())
