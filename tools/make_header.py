#!/usr/bin/env python3
"""Builds the 1300x372 Nexus header banner from a gameplay screenshot.

    pip install pillow
    python tools/make_header.py
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "media", "circle-perfect.jpg")
OUT = os.path.join(ROOT, "media", "nexus-header.jpg")
FONTS = os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts")
W, H = 1300, 372
CIRCLE = (960, 720)   # centre of the timing circle in the screenshot
CIRCLE_X = 975        # where it should sit in the banner


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def spaced(draw, xy, text, fnt, fill, spacing):
    """Draw text with extra letter spacing; returns the end x."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + spacing
    return x - spacing


src = Image.open(SRC).convert("RGB")
x0 = CIRCLE[0] - CIRCLE_X
y0 = CIRCLE[1] - H // 2
img = src.crop((x0, y0, x0 + W, y0 + H)).convert("RGBA")

# hide the game's own HUD in the left corners (defense prompts bottom-left,
# turn order top-left): blur them away, then darken
blurred = img.filter(ImageFilter.GaussianBlur(18))
mask = Image.new("L", (W, H), 0)
md = ImageDraw.Draw(mask)
md.rectangle((0, 250, 330, H), fill=255)
md.rectangle((0, 0, 140, 70), fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(28))
img = Image.composite(blurred, img, mask)
corner = Image.new("RGBA", (W, H), (8, 12, 14, 0))
corner.putalpha(mask.point(lambda v: int(v * 0.55)))
img = Image.alpha_composite(img, corner)

# darken the left side for the title, and soften top and bottom edges
shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
px = shade.load()
for x in range(W):
    a = max(0.0, 1.0 - x / 760.0)
    a = int(205 * a ** 1.4)
    for y in range(H):
        edge = min(y, H - 1 - y) / 60.0
        b = int(70 * max(0.0, 1.0 - edge))
        px[x, y] = (8, 12, 14, min(255, a + b))
img = Image.alpha_composite(img, shade)

title_font = font("palab.ttf", 104)
tag_font = font("segoeuil.ttf", 31)
small_font = font("segoeui.ttf", 19)
accent = (51, 255, 89, 255)   # the parry-window green

# soft shadow behind the title
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
spaced(gd, (66, 74), "RIPOSTE", title_font, (0, 0, 0, 200), 10)
glow = glow.filter(ImageFilter.GaussianBlur(8))
img = Image.alpha_composite(img, glow)

d = ImageDraw.Draw(img)
end = spaced(d, (62, 70), "RIPOSTE", title_font, (245, 245, 240, 255), 10)
d.rectangle((66, 198, 66 + 110, 201), fill=accent)
d.text((64, 216), "Timing circle  ·  Grace period", font=tag_font, fill=(235, 235, 230, 235))
d.text((66, 268), "Clair Obscur: Expedition 33   ·   UE4SS Lua mod", font=small_font, fill=(200, 205, 205, 190))

img.convert("RGB").save(OUT, quality=93)
print("wrote", OUT, img.size)
