import sys
from PIL import Image, ImageDraw, ImageFont
src_dir, out_dir = sys.argv[1:3]
W, H = 2064, 2752
BG1, BG2, INK = (0x09, 0x14, 0x12), (0x10, 0x28, 0x1f), (0xfc, 0xfa, 0xf0)
FRAMES = [
    ("01_leaders", "Find who scores efficiently", "10-ipad-find-who-scores-efficiently.png"),
    ("02_player_profile", "See what makes a player great", "11-ipad-see-what-makes-a-player-great.png"),
    ("05_team_profile", "Scout all 30 teams in percentiles", "12-ipad-scout-all-30-teams.png"),
]
font_path = "/System/Library/Fonts/SFNSRounded.ttf"
def font(size):
    try:
        f = ImageFont.truetype(font_path, size)
        try: f.set_variation_by_name("Semibold")
        except Exception: pass
        return f
    except OSError:
        return ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
def wrap(draw, text, f, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=f) <= width: cur = t
        else: lines.append(cur); cur = w
    lines.append(cur); return lines
for src, header, name in FRAMES:
    bg = Image.new("RGB", (1, H)); px = bg.load()
    for y in range(H):
        t = y / (H - 1); px[0, y] = tuple(round(BG1[c] + (BG2[c] - BG1[c]) * t) for c in range(3))
    img = bg.resize((W, H))
    d = ImageDraw.Draw(img)
    f = font(150)
    lines = wrap(d, header, f, W - 200)
    assert len(lines) <= 2 and "." not in header, header
    y = 120
    for line in lines:
        w = d.textlength(line, font=f); d.text(((W - w) / 2, y), line, font=f, fill=INK); y += 175
    shot = Image.open(f"{src_dir}/{src}.png").convert("RGB")
    sw = 1840; sh = round(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    top = y + 60
    avail = H - top - 60
    shot = shot.crop((0, 0, sw, min(sh, avail + 200)))
    # device bezel
    bez = 22; r = 70
    frame = Image.new("RGB", (sw + 2 * bez, shot.height + 2 * bez), (0x05, 0x0a, 0x09))
    m = Image.new("L", shot.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, sw - 1, shot.height + 400], radius=r - bez, fill=255)
    frame.paste(shot, (bez, bez), m)
    fm = Image.new("L", frame.size, 0); ImageDraw.Draw(fm).rounded_rectangle([0, 0, frame.width - 1, frame.height + 400], radius=r, fill=255)
    img.paste(frame, ((W - frame.width) // 2, top), fm)
    img.save(f"{out_dir}/{name}")
    print("wrote", name, img.size)
