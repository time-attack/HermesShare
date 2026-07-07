#!/usr/bin/env python3
"""Generate a plain HermesShare bubble-preview JPEG from a HermesLayout JSON file.

Apple's MSMessageTemplateLayout already renders caption / subcaption / imageTitle /
imageSubtitle around the bubble — the image must be graphic-only (dark canvas + one simple
accent metaphor). No titles, stats, or IATA codes in the image itself.

Usage:
  python3 make_thumbnail.py layout.json [output.jpg]

Exports 600×400 JPEG q90 (Photon rejects PNG). See references/thumbnail-generation-avoid-clutter.md.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

W, H = 600, 400

SCENE_TYPES = (
    "flightBoard", "gaugeCluster", "seatChart", "optionPicker", "platedDish",
    "skyScene", "journeyArc", "sparkline", "scoreBoard", "eventTicket",
    "mediaList", "quickReplyRow", "photoCatalog", "collapsible",
)


def hexc(h):
    h = (h or "#0A84FF").lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def find_scene(node):
    if not isinstance(node, dict):
        return None
    t = node.get("type")
    if t in SCENE_TYPES:
        return t
    for key in ("children", "child"):
        child = node.get(key)
        if isinstance(child, list):
            for c in child:
                found = find_scene(c)
                if found:
                    return found
        elif isinstance(child, dict):
            found = find_scene(child)
            if found:
                return found
    return None


def canvas(accent, glow_center=(W // 2, H // 2 - 20), tint=(19, 21, 26)):
    img = Image.new("RGB", (W, H), tint)
    glow = Image.new("RGB", (W, H), tint)
    d = ImageDraw.Draw(glow)
    a = hexc(accent)
    cx, cy = glow_center
    d.ellipse([cx - 200, cy - 200, cx + 200, cy + 200],
              fill=(tint[0] + a[0] // 7, tint[1] + a[1] // 7, tint[2] + a[2] // 7))
    glow = glow.filter(ImageFilter.GaussianBlur(95))
    return Image.blend(img, glow, 0.85)


def draw_flight(d, accent):
    y = H * 0.46
    x0, x1 = W * 0.18, W * 0.82
    progress = 0.62
    d.line([x0, y, x1, y], fill=(70, 78, 88), width=4)
    px = x0 + (x1 - x0) * progress
    d.line([x0, y, px, y], fill=hexc(accent), width=4)
    d.ellipse([px - 8, y - 8, px + 8, y + 8], fill=hexc(accent))


def draw_gauge(d, accent):
    cx, cy, r = W // 2, int(H * 0.52), 74
    box = [cx - r, cy - r, cx + r, cy + r]
    d.arc(box, start=135, end=45, fill=(60, 66, 74), width=14)
    d.arc(box, start=135, end=135 + int(270 * 0.82), fill=hexc(accent), width=14)


def draw_picker(d, accent):
    sz, gap = 44, 12
    total = 5 * sz + 4 * gap
    x0, y0 = (W - total) / 2, H * 0.38
    for i in range(5):
        x = x0 + i * (sz + gap)
        if i == 2:
            d.rounded_rectangle([x, y0, x + sz, y0 + sz], radius=10, fill=hexc(accent))
        else:
            d.rounded_rectangle([x, y0, x + sz, y0 + sz], radius=10,
                                outline=(90, 100, 110), width=3)


def draw_dish(d, accent):
    cx, cy = W // 2, int(H * 0.46)
    d.ellipse([cx - 52, cy - 52, cx + 52, cy + 52], outline=(90, 100, 110), width=3)
    d.ellipse([cx - 34, cy - 10, cx + 34, cy + 24], fill=hexc(accent))


def draw_sky(d, accent):
    cx, cy = W // 2, int(H * 0.44)
    d.ellipse([cx - 48, cy - 48, cx + 48, cy + 48], fill=hexc(accent))


def draw_journey(d, accent):
    pts = [(W * 0.14, H * 0.62), (W * 0.5, H * 0.22), (W * 0.86, H * 0.38)]
    d.line(pts, fill=(70, 78, 88), width=4)
    mid = (W * 0.58, H * 0.48)
    d.line([pts[0], mid], fill=hexc(accent), width=4)
    d.ellipse([mid[0] - 8, mid[1] - 8, mid[0] + 8, mid[1] + 8], fill=hexc(accent))


def draw_sparkline(d, accent):
    ys = [0.58, 0.42, 0.52, 0.32, 0.38, 0.48, 0.28, 0.36]
    xs = [W * (0.12 + i * 0.11) for i in range(len(ys))]
    ys = [H * y for y in ys]
    for i in range(len(xs) - 1):
        d.line([xs[i], ys[i], xs[i + 1], ys[i + 1]], fill=hexc(accent), width=3)


def draw_scoreboard(d, accent):
    y0 = int(H * 0.38)
    d.rounded_rectangle([W // 2 - 80, y0, W // 2 - 20, y0 + 52], radius=8, fill=(40, 44, 50))
    d.rounded_rectangle([W // 2 + 20, y0, W // 2 + 80, y0 + 52], radius=8, fill=hexc(accent))


def draw_ticket(d, accent):
    x0, y0 = W // 2 - 70, int(H * 0.34)
    d.rounded_rectangle([x0, y0, x0 + 140, y0 + 80], radius=10, outline=hexc(accent), width=2)
    d.line([x0 + 90, y0, x0 + 90, y0 + 80], fill=(90, 100, 110), width=1)


def draw_media(d, accent):
    y0 = int(H * 0.38)
    for i, x in enumerate([W // 2 - 70, W // 2 - 20, W // 2 + 30]):
        fill = hexc(accent) if i == 1 else (40, 44, 50)
        d.rounded_rectangle([x, y0, x + 40, y0 + 40], radius=8, fill=fill)


def draw_poll(d, accent):
    y0 = int(H * 0.42)
    for i, x in enumerate([W // 2 - 86, W // 2 - 26, W // 2 + 34]):
        fill = hexc(accent) if i == 1 else (40, 44, 50)
        d.rounded_rectangle([x, y0, x + 52, y0 + 28], radius=14, fill=fill)


def draw_generic(d, accent):
    # Plain fallback: canvas glow only — no extra shapes at bubble scale.
    pass


DRAWERS = {
    "flightBoard": draw_flight,
    "gaugeCluster": draw_gauge,
    "seatChart": draw_picker,
    "optionPicker": draw_picker,
    "platedDish": draw_dish,
    "skyScene": draw_sky,
    "journeyArc": draw_journey,
    "sparkline": draw_sparkline,
    "scoreBoard": draw_scoreboard,
    "eventTicket": draw_ticket,
    "mediaList": draw_media,
    "quickReplyRow": draw_poll,
    "photoCatalog": draw_media,
    "collapsible": draw_picker,
}


def render(layout):
    accent = layout.get("accentColorHex") or "#0A84FF"
    scene = find_scene(layout.get("root", {})) or "generic"
    img = canvas(accent)
    d = ImageDraw.Draw(img)
    DRAWERS.get(scene, draw_generic)(d, accent)
    return img


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    layout_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else layout_path.with_suffix(".jpg")
    layout = json.loads(layout_path.read_text())
    img = render(layout)
    img.save(out_path, "JPEG", quality=90)
    print(out_path)


if __name__ == "__main__":
    main()
