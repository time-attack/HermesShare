#!/usr/bin/env python3
"""Generate a HermesShare bubble-preview JPEG from a HermesLayout JSON file.

Caption/subcaption carry all text — the image is graphic-only: a cropped hero photo when the
layout has one, otherwise a rich scene illustration on an accent atmosphere (never bare gradient).

Usage:
  python3 make_thumbnail.py layout.json [output.jpg]

Exports 600×400 JPEG q90 (Photon rejects PNG).
"""
import json
import sys
import urllib.request
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageOps

W, H = 600, 400

SCENE_TYPES = (
    "flightBoard", "gaugeCluster", "seatChart", "optionPicker", "platedDish",
    "skyScene", "journeyArc", "sparkline", "scoreBoard", "eventTicket",
    "mediaList", "quickReplyRow", "photoCatalog", "collapsible",
    "checklist", "timeline", "mapPreview", "progressBar", "barChart", "gallery",
)

UA = "HermesShare/1.0 (bubble-thumbnail)"


def hexc(h):
    h = (h or "#0A84FF").lstrip("#")
    if len(h) == 6:
        return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))
    return (10, 132, 255)


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


def find_hero_image_url(node, initial_expanded=None):
    """First real photo URL in the layout — photo catalog hero, picker thumb, etc."""
    if not isinstance(node, dict):
        return None
    t = node.get("type")

    if t == "photoCatalog":
        items = node.get("catalogItems") or []
        exp = node.get("initialExpandedId") or initial_expanded
        if exp:
            for item in items:
                if item.get("id") == exp and item.get("heroImageUrl"):
                    return item["heroImageUrl"]
        for item in items:
            if item.get("heroImageUrl"):
                return item["heroImageUrl"]
            for room in item.get("rooms") or []:
                if room.get("imageUrl"):
                    return room["imageUrl"]

    if t == "optionPicker":
        for opt in node.get("options") or []:
            if opt.get("imageUrl"):
                return opt["imageUrl"]

    if t == "mediaList":
        for item in node.get("mediaItems") or []:
            if item.get("imageUrl"):
                return item["imageUrl"]

    if t == "gallery":
        urls = node.get("urls") or []
        if urls:
            return urls[0]

    if t == "image" and node.get("url"):
        return node["url"]

    if t == "person" and node.get("imageUrl"):
        return node["imageUrl"]

    if t == "collapsible" and node.get("imageUrl"):
        return node["imageUrl"]

    for key in ("children", "child"):
        child = node.get(key)
        if isinstance(child, list):
            for c in child:
                found = find_hero_image_url(c, initial_expanded)
                if found:
                    return found
        elif isinstance(child, dict):
            found = find_hero_image_url(child, initial_expanded)
            if found:
                return found
    return None


def fetch_image(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=12) as resp:
        data = resp.read()
    img = Image.open(BytesIO(data)).convert("RGB")
    return img


def atmosphere_gradient(accent, layout):
    bg = layout.get("background") or {}
    colors = bg.get("colorsHex") or []
    a = hexc(accent)
    top = hexc(colors[0]) if colors else (max(8, a[0] // 5), max(8, a[1] // 5), max(12, a[2] // 4))
    bot = (19, 21, 26)
    img = Image.new("RGB", (W, H))
    for y in range(H):
        t = y / max(H - 1, 1)
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        for x in range(W):
            img.putpixel((x, y), (r, g, b))
    glow = Image.new("RGB", (W, H), bot)
    d = ImageDraw.Draw(glow)
    cx, cy = W // 2, int(H * 0.38)
    d.ellipse([cx - 180, cy - 140, cx + 180, cy + 140],
              fill=(bot[0] + a[0] // 6, bot[1] + a[1] // 6, bot[2] + a[2] // 6))
    glow = glow.filter(ImageFilter.GaussianBlur(80))
    return Image.blend(img, glow, 0.72)


def photo_thumbnail(url, accent):
    """Full-bleed cropped hero with cinematic scrim — no text."""
    raw = fetch_image(url)
    img = ImageOps.fit(raw, (W, H), method=Image.Resampling.LANCZOS, centering=(0.5, 0.45))
    img = img.filter(ImageFilter.GaussianBlur(0.6))

    # Bottom-weighted scrim so caption area reads cleanly over any photo.
    scrim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scrim)
    for y in range(H):
        t = max(0, (y - H * 0.35) / (H * 0.65))
        alpha = int(180 * (t**1.4))
        sd.line([(0, y), (W, y)], fill=(8, 10, 14, alpha))
    top_fade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    td = ImageDraw.Draw(top_fade)
    for y in range(int(H * 0.22)):
        alpha = int(90 * (1 - y / (H * 0.22)))
        td.line([(0, y), (W, y)], fill=(8, 10, 14, alpha))
    scrim = Image.alpha_composite(scrim, top_fade)

    base = img.convert("RGBA")
    base = Image.alpha_composite(base, scrim)

    # Accent edge glow — ties photo to card accent without covering content.
    a = hexc(accent)
    edge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ed = ImageDraw.Draw(edge)
    ed.rounded_rectangle([4, 4, W - 4, H - 4], radius=16,
                         outline=(a[0], a[1], a[2], 55), width=3)
    base = Image.alpha_composite(base, edge)
    return base.convert("RGB")


# --- Scene illustrations (text-free, larger + richer than bare gradient dots) ---

def draw_flight(d, accent):
    y = H * 0.48
    x0, x1 = W * 0.12, W * 0.88
    progress = 0.58
    a = hexc(accent)
    d.rounded_rectangle([W * 0.22, H * 0.18, W * 0.78, H * 0.72], radius=18, fill=(28, 30, 36))
    d.line([x0, y, x1, y], fill=(55, 60, 68), width=5)
    px = x0 + (x1 - x0) * progress
    d.line([x0, y, px, y], fill=a, width=5)
    d.polygon([(px + 14, y), (px - 6, y - 8), (px - 6, y + 8)], fill=a)
    for code, x in [("AAA", x0 - 8), ("BBB", x1 + 8)]:
        d.rounded_rectangle([x - 28, y - 38, x + 28, y - 8], radius=6, fill=(40, 44, 52))
        # no text — tile blocks only
        for i in range(3):
            d.rectangle([x - 20 + i * 14, y - 32, x - 10 + i * 14, y - 14], fill=(70, 76, 86))


def draw_gauge(d, accent):
    cx, cy, r = W // 2, int(H * 0.52), 88
    a = hexc(accent)
    d.ellipse([cx - r - 16, cy - r - 16, cx + r + 16, cy + r + 16], fill=(28, 30, 36))
    box = [cx - r, cy - r, cx + r, cy + r]
    d.arc(box, start=135, end=45, fill=(50, 56, 64), width=16)
    d.arc(box, start=135, end=135 + int(270 * 0.78), fill=a, width=16)
    d.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=(220, 224, 230))


def draw_picker(d, accent):
    a = hexc(accent)
    d.rounded_rectangle([W * 0.08, H * 0.22, W * 0.92, H * 0.78], radius=20, fill=(28, 30, 36))
    sz, gap = 52, 14
    total = 4 * sz + 3 * gap
    x0, y0 = (W - total) / 2, H * 0.36
    for i in range(4):
        x = x0 + i * (sz + gap)
        fill = a if i == 1 else (44, 48, 56)
        d.rounded_rectangle([x, y0, x + sz, y0 + sz], radius=12, fill=fill)
        if i == 1:
            d.polygon([(x + sz - 14, y0 + sz - 14), (x + sz - 4, y0 + sz - 4),
                       (x + sz - 4, y0 + sz - 18)], fill=(255, 255, 255))


def draw_dish(d, accent):
    cx, cy = W // 2, int(H * 0.48)
    a = hexc(accent)
    d.ellipse([cx - 100, cy - 20, cx + 100, cy + 60], fill=(32, 34, 40))
    d.ellipse([cx - 78, cy - 58, cx + 78, cy + 58], outline=(90, 98, 108), width=4)
    d.ellipse([cx - 52, cy - 8, cx + 52, cy + 32], fill=a)
    d.ellipse([cx - 18, cy - 28, cx + 8, cy - 4], fill=(min(255, a[0] + 40), min(255, a[1] + 40), min(255, a[2] + 40)))


def draw_sky(d, accent):
    a = hexc(accent)
    d.rectangle([0, int(H * 0.55), W, H], fill=(22, 28, 48))
    d.ellipse([W // 2 - 56, int(H * 0.22) - 56, W // 2 + 56, int(H * 0.22) + 56], fill=a)
    for i, x in enumerate([80, 160, 420, 500]):
        d.ellipse([x - 22, 60 + i * 8, x + 38, 90 + i * 8], fill=(40, 44, 58))


def draw_journey(d, accent):
    a = hexc(accent)
    pts = [(W * 0.12, H * 0.65), (W * 0.48, H * 0.22), (W * 0.88, H * 0.42)]
    d.line(pts, fill=(50, 56, 64), width=5)
    d.line([pts[0], (W * 0.62, H * 0.38)], fill=a, width=5)
    d.ellipse([W * 0.62 - 12, H * 0.38 - 12, W * 0.62 + 12, H * 0.38 + 12], fill=a)
    d.rounded_rectangle([W * 0.08, H * 0.72, W * 0.28, H * 0.84], radius=8, fill=(32, 36, 44))
    d.rounded_rectangle([W * 0.72, H * 0.14, W * 0.92, H * 0.26], radius=8, fill=(32, 36, 44))


def draw_sparkline(d, accent):
    a = hexc(accent)
    d.rounded_rectangle([W * 0.1, H * 0.28, W * 0.9, H * 0.72], radius=16, fill=(28, 30, 36))
    ys = [0.62, 0.48, 0.55, 0.38, 0.42, 0.52, 0.32, 0.40, 0.28, 0.35]
    xs = [W * (0.14 + i * 0.075) for i in range(len(ys))]
    ys = [H * (0.28 + y * 0.44) for y in ys]
    for i in range(len(xs) - 1):
        d.line([xs[i], ys[i], xs[i + 1], ys[i + 1]], fill=a, width=4)
    d.ellipse([xs[-1] - 6, ys[-1] - 6, xs[-1] + 6, ys[-1] + 6], fill=a)


def draw_scoreboard(d, accent):
    a = hexc(accent)
    d.rounded_rectangle([W * 0.12, H * 0.26, W * 0.88, H * 0.74], radius=18, fill=(24, 26, 32))
    y0 = int(H * 0.38)
    d.rounded_rectangle([W // 2 - 100, y0, W // 2 - 24, y0 + 56], radius=10, fill=(44, 48, 56))
    d.rounded_rectangle([W // 2 + 24, y0, W // 2 + 100, y0 + 56], radius=10, fill=a)
    d.rectangle([W // 2 - 2, y0 + 8, W // 2 + 2, y0 + 48], fill=(70, 76, 86))


def draw_ticket(d, accent):
    a = hexc(accent)
    x0, y0 = W // 2 - 90, int(H * 0.28)
    d.rounded_rectangle([x0, y0, x0 + 180, y0 + 100], radius=14, outline=a, width=3)
    d.line([x0 + 118, y0 + 8, x0 + 118, y0 + 92], fill=(70, 76, 86), width=2)
    for i in range(6):
        d.rectangle([x0 + 20, y0 + 62 + i * 5, x0 + 100, y0 + 65 + i * 5], fill=(60, 66, 74))


def draw_media(d, accent):
    a = hexc(accent)
    positions = [(W * 0.18, 0.32), (W * 0.38, 0.28), (W * 0.58, 0.32)]
    sizes = [(100, 120), (120, 140), (100, 120)]
    for i, ((x, y), (w, h)) in enumerate(zip(positions, sizes)):
        fill = a if i == 1 else (36, 40, 48)
        d.rounded_rectangle([x, H * y, x + w, H * y + h], radius=12, fill=fill)
        d.rounded_rectangle([x + 8, H * y + 8, x + w - 8, H * y + h * 0.55], radius=8,
                            fill=(min(255, fill[0] + 20), min(255, fill[1] + 20), min(255, fill[2] + 20))
                            if isinstance(fill, tuple) else a)


def draw_poll(d, accent):
    a = hexc(accent)
    d.rounded_rectangle([W * 0.1, H * 0.34, W * 0.9, H * 0.66], radius=20, fill=(28, 30, 36))
    for i, x in enumerate([W * 0.16, W * 0.38, W * 0.60]):
        fill = a if i == 1 else (44, 48, 56)
        d.rounded_rectangle([x, H * 0.42, x + 100, H * 0.58], radius=22, fill=fill)


def draw_checklist(d, accent):
    a = hexc(accent)
    d.rounded_rectangle([W * 0.12, H * 0.2, W * 0.88, H * 0.8], radius=18, fill=(28, 30, 36))
    for i, done in enumerate([True, True, False, False]):
        y = H * (0.32 + i * 0.12)
        color = a if done else (60, 66, 74)
        d.ellipse([W * 0.18, y - 10, W * 0.18 + 20, y + 10], fill=color)
        d.rounded_rectangle([W * 0.26, y - 6, W * 0.78, y + 6], radius=4, fill=(44, 48, 56))


def draw_timeline(d, accent):
    a = hexc(accent)
    x = W * 0.22
    d.line([(x, H * 0.22), (x, H * 0.78)], fill=(50, 56, 64), width=4)
    for i, filled in enumerate([True, True, False]):
        y = H * (0.28 + i * 0.2)
        if filled:
            d.ellipse([x - 10, y - 10, x + 10, y + 10], fill=a)
        else:
            d.ellipse([x - 10, y - 10, x + 10, y + 10], outline=(70, 76, 86), width=3)
        d.rounded_rectangle([x + 24, y - 8, W * 0.82, y + 8], radius=6, fill=(36, 40, 48))


def draw_map(d, accent):
    a = hexc(accent)
    d.rounded_rectangle([W * 0.1, H * 0.22, W * 0.9, H * 0.78], radius=18, fill=(34, 38, 44))
    for gx in range(6):
        for gy in range(4):
            d.rectangle([W * 0.14 + gx * 72, H * 0.28 + gy * 48,
                         W * 0.14 + gx * 72 + 64, H * 0.28 + gy * 48 + 40],
                        fill=(42 + gx * 2, 46 + gy * 2, 52))
    d.ellipse([W * 0.52 - 16, H * 0.46 - 16, W * 0.52 + 16, H * 0.46 + 16], fill=a)
    d.ellipse([W * 0.52 - 6, H * 0.46 - 6, W * 0.52 + 6, H * 0.46 + 6], fill=(240, 242, 248))


def draw_progress(d, accent):
    a = hexc(accent)
    d.rounded_rectangle([W * 0.12, H * 0.42, W * 0.88, H * 0.58], radius=14, fill=(36, 40, 48))
    d.rounded_rectangle([W * 0.12, H * 0.42, W * 0.12 + (W * 0.76) * 0.72, H * 0.58], radius=14, fill=a)


def draw_bars(d, accent):
    a = hexc(accent)
    d.rounded_rectangle([W * 0.1, H * 0.26, W * 0.9, H * 0.74], radius=16, fill=(28, 30, 36))
    vals = [0.85, 0.62, 0.48, 0.35]
    for i, v in enumerate(vals):
        y = H * (0.34 + i * 0.1)
        d.rounded_rectangle([W * 0.16, y, W * 0.84, y + 22], radius=8, fill=(40, 44, 52))
        d.rounded_rectangle([W * 0.16, y, W * 0.16 + (W * 0.68) * v, y + 22], radius=8,
                            fill=a if i == 0 else (a[0], a[1], a[2]))


def draw_gallery(d, accent):
    draw_media(d, accent)


def draw_generic(d, accent):
    a = hexc(accent)
    cx, cy = W // 2, H // 2
    d.rounded_rectangle([cx - 70, cy - 50, cx + 70, cy + 50], radius=20, fill=(32, 36, 44))
    d.rounded_rectangle([cx - 40, cy - 28, cx + 40, cy + 28], radius=12, fill=(a[0] // 2, a[1] // 2, a[2] // 2))


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
    "checklist": draw_checklist,
    "timeline": draw_timeline,
    "mapPreview": draw_map,
    "progressBar": draw_progress,
    "barChart": draw_bars,
    "gallery": draw_gallery,
}


def render_illustrated(layout):
    accent = layout.get("accentColorHex") or "#0A84FF"
    scene = find_scene(layout.get("root", {})) or "generic"
    img = atmosphere_gradient(accent, layout)
    d = ImageDraw.Draw(img)
    DRAWERS.get(scene, draw_generic)(d, accent)
    return img


def render(layout):
    accent = layout.get("accentColorHex") or "#0A84FF"
    hero = find_hero_image_url(layout.get("root", {}))
    if hero:
        try:
            return photo_thumbnail(hero, accent)
        except Exception:
            pass  # fall through to illustrated
    return render_illustrated(layout)


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    layout_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else layout_path.with_suffix(".jpg")
    layout = json.loads(layout_path.read_text())
    img = render(layout)
    img.save(out_path, "JPEG", quality=92, optimize=True)
    print(out_path)


if __name__ == "__main__":
    main()
