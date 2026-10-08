#!/usr/bin/env python3
"""
Hardwood StatScout app icon: basketball sibling of the baseball and football
percentile-slider icons.

Four horizontal percentile tracks, each filled to a different value, with a
basketball sitting on the leading edge of every fill like a slider thumb. Rendered
at 4x and downsampled so the seams stay clean at 40px.
"""

import math
import os

from PIL import Image, ImageChops, ImageDraw

SS = 4                      # supersample factor
SIZE = 1024
S = SIZE * SS

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "docs", "icon-concepts")

# --- palette (from StatScout/Views/SavantDesign.swift) ---
MIDNIGHT        = (0x09, 0x14, 0x12)
MIDNIGHT_TOP    = (0x0D, 0x1F, 0x1B)
TURF            = (0x14, 0x5C, 0x33)
PERF_HIGH       = (0x05, 0x75, 0x33)
LEATHER         = (0xD9, 0x6A, 0x2B)   # basketball orange
LEATHER_LIGHT   = (0xE8, 0x7E, 0x3A)
LEATHER_DARK    = (0xB5, 0x4F, 0x1C)
SEAM            = (0x2A, 0x16, 0x0C)
GOLD            = (0xD6, 0xA1, 0x30)
CANVAS          = (0xF0, 0xED, 0xE3)
PERF_LOW        = (0xB2, 0x33, 0x14)

TRACK_DARK      = (0x20, 0x2C, 0x28)
TRACK_LIGHT     = (0xDB, 0xD7, 0xC9)

# ramp variants: fill colour per bar, high percentile first
RAMP_HEAT = [PERF_HIGH, TURF, GOLD, PERF_LOW]
RAMP_TWO  = [PERF_HIGH, TURF, (0xC2, 0x51, 0x2A), (0x8C, 0x28, 0x10)]

FRACTIONS = [0.90, 0.72, 0.50, 0.28]
FRACTIONS_3 = [0.85, 0.58, 0.30]

# --- geometry, in 1024 space ---
BAR_H     = 118
BAR_GAP   = 84
TRACK_X0  = 104
TRACK_X1  = 920
BALL_TILT = -18            # degrees, clockwise: seams off-axis read as a ball, not a target
BALL_DIAM = 1.30           # multiples of BAR_H


def vgradient(top, bottom, w, h):
    img = Image.new("RGB", (1, max(2, h)))
    px = img.load()
    for y in range(img.height):
        t = y / (img.height - 1)
        px[0, y] = tuple(round(top[c] + (bottom[c] - top[c]) * t) for c in range(3))
    return img.resize((w, h), Image.BILINEAR)


def gradient_bg(top, bottom):
    return vgradient(top, bottom, S, S)


def rotate(cx, cy, pts, tilt_deg):
    t = math.radians(tilt_deg)
    cos_t, sin_t = math.cos(t), math.sin(t)
    return [(cx + x * cos_t - y * sin_t, cy + x * sin_t + y * cos_t) for x, y in pts]


def draw_seams(draw, cx, cy, r, tilt, colour, bar_h):
    """The eight-panel basketball seam: one vertical, one horizontal, two side arcs.

    Every stroke is the same weight and well above 12px at 1024 so the seams are
    still the thing that says "basketball" at 40px, where an orange disc alone
    reads as a dot.
    """
    w = round(bar_h * 0.075 * SS)
    draw.line(rotate(cx, cy, [(-r, 0), (r, 0)], tilt), fill=colour, width=w)
    draw.line(rotate(cx, cy, [(0, -r), (0, r)], tilt), fill=colour, width=w)
    # side arcs: circles of radius ~1.15r centred 1.55r to either side, clipped by
    # the ball mask, give the classic curved panels
    for side in (-1, 1):
        pts = []
        R = r * 1.15
        ox = side * r * 1.55
        for i in range(181):
            a = math.radians(90 + 180 * i / 180)
            x = ox + R * math.cos(a) * -side
            y = R * math.sin(a)
            if x * side < r:            # keep only the part inside the ball
                pts.append((x, y))
        if len(pts) > 1:
            draw.line(rotate(cx, cy, pts, tilt), fill=colour, width=w, joint="curve")


def draw_basketball(base, cx, cy, halo_colour, seam_colour, bar_h):
    r = bar_h * BALL_DIAM / 2 * SS

    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # a halo in the background colour knocks the ball out of the track, so it
    # reads as a thumb sitting on the bar rather than a sticker glued over it
    hr = r * 1.10
    d.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=halo_colour)

    # orange body, one subtle top-to-bottom shade for form, no gloss
    bx, by = int(cx - r), int(cy - r)
    bw = bh = int(2 * r) + 1
    mask = Image.new("L", (bw, bh), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, bw - 1, bh - 1], fill=255)
    layer.paste(vgradient(LEATHER_LIGHT, LEATHER_DARK, bw, bh), (bx, by), mask)

    seams = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw_seams(ImageDraw.Draw(seams), cx, cy, r, BALL_TILT, seam_colour, bar_h)
    clip = Image.new("L", base.size, 0)
    ImageDraw.Draw(clip).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    layer.paste(seams, (0, 0), ImageChops.multiply(seams.split()[3], clip))

    base.alpha_composite(layer)


def build(path, *, bg_top, bg_bottom, track, ramp, halo, laces=SEAM,
          fractions=FRACTIONS, bar_h=BAR_H, bar_gap=BAR_GAP):
    img = gradient_bg(bg_top, bg_bottom).convert("RGBA")
    draw = ImageDraw.Draw(img)

    n = len(fractions)
    total = n * bar_h + (n - 1) * bar_gap
    y0 = (SIZE - total) / 2

    for i, frac in enumerate(fractions):
        top = (y0 + i * (bar_h + bar_gap)) * SS
        bot = top + bar_h * SS
        r = bar_h * SS / 2
        x0, x1 = TRACK_X0 * SS, TRACK_X1 * SS

        draw.rounded_rectangle([x0, top, x1, bot], radius=r, fill=track)

        fill_x = x0 + (x1 - x0) * frac
        draw.rounded_rectangle([x0, top, fill_x, bot], radius=r, fill=ramp[i])

        draw_basketball(img, fill_x, (top + bot) / 2, halo, laces, bar_h)

    img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(path)
    print("wrote", path)


def proof(src, path, label_bg):
    icon = Image.open(src).convert("RGB")
    sizes = [180, 120, 80, 60, 40]
    pad, gap = 40, 32
    w = pad * 2 + sum(sizes) + gap * (len(sizes) - 1)
    h = pad * 2 + max(sizes)
    sheet = Image.new("RGB", (w, h), label_bg)
    x = pad
    for s in sizes:
        # iOS-style squircle mask, approximated with a rounded rect at 4x
        m = Image.new("L", (s * 4, s * 4), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, s * 4 - 1, s * 4 - 1],
                                           radius=int(s * 4 * 0.2237), fill=255)
        m = m.resize((s, s), Image.LANCZOS)
        tile = icon.resize((s, s), Image.LANCZOS)
        sheet.paste(tile, (x, pad + (max(sizes) - s) // 2), m)
        x += s + gap
    sheet.save(path)
    print("wrote", path)


def main():
    os.makedirs(OUT, exist_ok=True)

    build(os.path.join(OUT, "concept_a_dark.png"),
          bg_top=MIDNIGHT_TOP, bg_bottom=MIDNIGHT, track=TRACK_DARK,
          ramp=RAMP_HEAT, halo=MIDNIGHT)

    build(os.path.join(OUT, "concept_b_two_hue.png"),
          bg_top=MIDNIGHT_TOP, bg_bottom=MIDNIGHT, track=TRACK_DARK,
          ramp=RAMP_TWO, halo=MIDNIGHT)

    build(os.path.join(OUT, "concept_c_cream.png"),
          bg_top=(0xF6, 0xF3, 0xE9), bg_bottom=CANVAS, track=TRACK_LIGHT,
          ramp=RAMP_HEAT, halo=CANVAS)

    build(os.path.join(OUT, "concept_d_three_bar.png"),
          bg_top=MIDNIGHT_TOP, bg_bottom=MIDNIGHT, track=TRACK_DARK,
          ramp=[PERF_HIGH, GOLD, PERF_LOW], halo=MIDNIGHT,
          fractions=FRACTIONS_3, bar_h=152, bar_gap=106)

    for name in ("concept_a_dark", "concept_b_two_hue", "concept_c_cream",
                 "concept_d_three_bar"):
        src = os.path.join(OUT, f"{name}.png")
        proof(src, os.path.join(OUT, f"proof_{name}_light.png"), (0xE8, 0xE8, 0xE8))
        proof(src, os.path.join(OUT, f"proof_{name}_dark.png"), (0x18, 0x18, 0x1A))


if __name__ == "__main__":
    main()
