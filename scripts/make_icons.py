#!/usr/bin/env python3
"""Generate app icons for HermesShare (host AppIcon) and the iMessage App Icon set.
Draws a simple, legible glyph (winged 'H') on a blue->green gradient — no external fonts."""
import os, json
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def gradient(w, h):
    img = Image.new("RGB", (w, h))
    top = (10, 132, 255)      # #0A84FF
    bot = (48, 209, 88)       # #30D158
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        for x in range(w):
            img.putpixel((x, y), (r, g, b))
    return img

def draw_icon(w, h):
    # Gradient is cheap enough at these sizes; build at target size directly.
    img = gradient(w, h).convert("RGBA")
    d = ImageDraw.Draw(img)
    # Draw a bold white "H" from three rounded rectangles, centered.
    cx, cy = w / 2, h / 2
    bar_h = h * 0.44
    stem_w = w * 0.11
    gap = w * 0.16
    top_y = cy - bar_h / 2
    bot_y = cy + bar_h / 2
    white = (255, 255, 255, 255)
    # left stem
    d.rounded_rectangle([cx - gap - stem_w, top_y, cx - gap, bot_y],
                        radius=stem_w * 0.4, fill=white)
    # right stem
    d.rounded_rectangle([cx + gap, top_y, cx + gap + stem_w, bot_y],
                        radius=stem_w * 0.4, fill=white)
    # crossbar
    d.rounded_rectangle([cx - gap, cy - stem_w * 0.55, cx + gap, cy + stem_w * 0.55],
                        radius=stem_w * 0.4, fill=white)
    # small "wing" tick above the crossbar for a Hermes cue
    d.polygon([(cx - gap - stem_w, top_y - h * 0.02),
               (cx - gap - stem_w - w * 0.08, top_y - h * 0.09),
               (cx - gap - stem_w, top_y - h * 0.11)], fill=(255, 255, 255, 210))
    return img.convert("RGB")

def emit(path, wpx, hpx):
    draw_icon(wpx, hpx).save(path, "PNG")
    return os.path.basename(path)

# ---- Host app AppIcon (single 1024 universal) ----
appicon_dir = os.path.join(ROOT, "HermesShare/Resources/Assets.xcassets/AppIcon.appiconset")
os.makedirs(appicon_dir, exist_ok=True)
emit(os.path.join(appicon_dir, "icon-1024.png"), 1024, 1024)
json.dump({
    "images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon-1024.png"}],
    "info": {"version": 1, "author": "xcode"}
}, open(os.path.join(appicon_dir, "Contents.json"), "w"), indent=2)

# ---- iMessage App Icon set ----
msg_dir = os.path.join(ROOT, "HermesShareExtension/Resources/Assets.xcassets/iMessage App Icon.stickersiconset")
os.makedirs(msg_dir, exist_ok=True)

# (size_pts, idiom, scale, platform) -> pixel dims
specs = [
    ("1024x768", "ios-marketing", "1x", "ios", 1024, 768),
    ("27x20",    "universal",     "2x", "ios", 54, 40),
    ("27x20",    "universal",     "3x", "ios", 81, 60),
    ("32x24",    "universal",     "2x", "ios", 64, 48),
    ("32x24",    "universal",     "3x", "ios", 96, 72),
    ("60x45",    "iphone",        "2x", None, 120, 90),
    ("60x45",    "iphone",        "3x", None, 180, 135),
    ("67x50",    "ipad",          "2x", None, 134, 100),
    ("74x55",    "ipad",          "2x", None, 148, 110),
]
images = []
for size, idiom, scale, platform, wpx, hpx in specs:
    fname = f"imsg-{size}-{scale}-{idiom}.png"
    emit(os.path.join(msg_dir, fname), wpx, hpx)
    entry = {"size": size, "idiom": idiom, "scale": scale, "filename": fname}
    if platform:
        entry["platform"] = platform
    images.append(entry)
json.dump({"images": images, "info": {"version": 1, "author": "xcode"}},
          open(os.path.join(msg_dir, "Contents.json"), "w"), indent=2)

print("icons generated")
