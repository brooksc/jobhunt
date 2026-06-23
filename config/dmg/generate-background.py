#!/usr/bin/env python3
# Regenerates the JobHunt DMG window background (TASK-566).
#   python3 config/dmg/generate-background.py
# Writes config/dmg/background.png (640x400) and background@2x.png (1280x800).
# Run from the repo root; requires Pillow.

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

# Render at 2x (retina). Window is 640x400 points -> @2x is 1280x800.
W, H = 1280, 800

def find_font(paths, size):
    for p, idx in paths:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size, index=idx)
            except Exception:
                pass
    return ImageFont.load_default()

bold = lambda s: find_font([
    ("/System/Library/Fonts/SFNS.ttf", 0),
    ("/System/Library/Fonts/Helvetica.ttc", 1),
    ("/Library/Fonts/Arial Bold.ttf", 0),
], s)
reg = lambda s: find_font([
    ("/System/Library/Fonts/SFNS.ttf", 0),
    ("/System/Library/Fonts/Helvetica.ttc", 0),
    ("/Library/Fonts/Arial.ttf", 0),
], s)

# --- vertical gradient background (dark navy) ---
top = (11, 14, 20)      # #0b0e14
bot = (18, 24, 38)      # #121826
bg = Image.new("RGB", (W, H), top)
px = bg.load()
for y in range(H):
    t = y / (H - 1)
    r = int(top[0] + (bot[0]-top[0])*t)
    g = int(top[1] + (bot[1]-top[1])*t)
    b = int(top[2] + (bot[2]-top[2])*t)
    for x in range(W):
        px[x, y] = (r, g, b)

# --- soft accent glow near top center ---
glow = Image.new("RGBA", (W, H), (0,0,0,0))
gd = ImageDraw.Draw(glow)
gd.ellipse([W//2-360, -260, W//2+360, 300], fill=(59,130,246,60))  # #3b82f6 soft
glow = glow.filter(ImageFilter.GaussianBlur(120))
bg = Image.alpha_composite(bg.convert("RGBA"), glow)

d = ImageDraw.Draw(bg)

def center_text(draw, cx, y, text, font, fill):
    l, t, r, b = draw.textbbox((0,0), text, font=font)
    draw.text((cx-(r-l)/2, y), text, font=font, fill=fill)

# --- title + tagline ---
center_text(d, W//2, 78, "JobHunt", bold(72), (240, 244, 250))
center_text(d, W//2, 168, "Local-first job tracker for macOS", reg(30), (150, 160, 178))

# --- arrow (blue->cyan), centered between the two icon slots ---
# icons sit at x=320 (app) and x=960 (Applications), 256px wide each at 2x.
ay = 372
x0, x1 = 506, 760           # shaft start/end (between icon right edge ~448 and Apps left ~832)
shaft_h = 26
head_w, head_h = 70, 84
arrow = Image.new("RGBA", (W, H), (0,0,0,0))
ad = ImageDraw.Draw(arrow)
# horizontal gradient color along the arrow
def lerp(a, b, t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
cA, cB = (59,130,246), (34,211,238)   # blue -> cyan
# shaft as vertical strips for gradient
for x in range(x0, x1):
    t = (x - x0) / max(1,(x1 - x0 + head_w))
    ad.line([(x, ay-shaft_h//2), (x, ay+shaft_h//2)], fill=lerp(cA,cB,t)+(255,))
# arrowhead
ad.polygon([(x1, ay-head_h//2), (x1+head_w, ay), (x1, ay+head_h//2)], fill=lerp(cA,cB,1.0)+(255,))
# glow copy
glow2 = arrow.filter(ImageFilter.GaussianBlur(14))
bg = Image.alpha_composite(bg, glow2)
bg = Image.alpha_composite(bg, arrow)

d = ImageDraw.Draw(bg)
# --- hint under icons ---
center_text(d, W//2, 612, "Drag JobHunt onto the Applications folder to install", reg(27), (150, 160, 178))

bg = bg.convert("RGB")
os.makedirs("config/dmg", exist_ok=True)
bg.save("config/dmg/background@2x.png")
bg.resize((W//2, H//2), Image.LANCZOS).save("config/dmg/background.png")
print("wrote config/dmg/background.png (640x400) and background@2x.png (1280x800)")
