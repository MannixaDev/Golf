"""Composites the itch.io page banner: a real course plate, the wordmark, a line.

The plate comes from tools/banner_shot.gd rather than being drawn, because the
art in this game *is* the course -- a banner illustrating something else would be
advertising a different game.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

# The project, relative to this file, so the script travels with the repo.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Where banner_shot.gd drops its plates, and where these are written back to.
SHOTS = os.path.expanduser(
    "~/AppData/Roaming/Godot/app_userdata/Fairway Fiends")

W, H = 1920, 600

plate = Image.open(os.path.join(SHOTS, "banner_3.png")).convert("RGBA")
plate = plate.resize((W, H), Image.LANCZOS)

# A dark wash from the left, so the wordmark has something to sit on however busy
# the course behind it happens to be. Eased rather than linear, because a straight
# ramp reads as a band edge drawn across the fairway.
wash = Image.new("L", (W, H))
px = wash.load()
for x in range(W):
    t = max(0.0, 1.0 - x / (W * 0.62))
    v = int(205 * (t ** 1.7))
    for y in range(H):
        px[x, y] = v
shade = Image.new("RGBA", (W, H), (8, 20, 12, 255))
shade.putalpha(wash)
banner = Image.alpha_composite(plate, shade)

# A gentle vignette so the edges do not fight whatever the page puts around them.
vig = Image.new("L", (W, H), 0)
ImageDraw.Draw(vig).ellipse(
    (-W * 0.30, -H * 0.85, W * 1.30, H * 1.85), fill=255)
vig = vig.filter(ImageFilter.GaussianBlur(160))
dark = Image.new("RGBA", (W, H), (6, 14, 9, 255))
dark.putalpha(Image.eval(vig, lambda v: int((255 - v) * 0.30)))
banner = Image.alpha_composite(banner, dark)

logo = Image.open(os.path.join(ROOT, "resources/art/logo.png")).convert("RGBA")
target_h = 396
logo = logo.resize(
    (round(logo.width * target_h / logo.height), target_h), Image.LANCZOS)
lx, ly = 96, (H - target_h) // 2 - 30

# Its own soft shadow, so it sits on the course rather than being pasted onto it.
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
glow.paste(Image.new("RGBA", logo.size, (0, 0, 0, 195)), (lx, ly + 10), logo)
banner = Image.alpha_composite(banner, glow.filter(ImageFilter.GaussianBlur(24)))
banner.alpha_composite(logo, (lx, ly))

draw = ImageDraw.Draw(banner)

# Sized to the wordmark rather than set at a fixed point, because a line wider
# than the block it sits under has nowhere to go: at 33pt with wide tracking it
# ran off the left edge of the image and lost its first letter.
line = "THE COURSE IS THE ENEMY"
block = logo.width + 96
size = 44
while size > 20:
    font = ImageFont.truetype(
        os.path.join(ROOT, "resources/fonts/Lato-Bold.ttf"), size)
    if draw.textlength(line, font=font) <= block:
        break
    size -= 1
tw = draw.textlength(line, font=font)
tx = lx + (logo.width - tw) / 2
ty = ly + target_h + 6
for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2), (0, 0)):
    draw.text((tx + dx, ty + dy), line, font=font,
              fill=(233, 224, 196, 255) if (dx == 0 and dy == 0)
              else (8, 18, 11, 235))

sub = ImageFont.truetype(
    os.path.join(ROOT, "resources/fonts/Lato-Semibold.ttf"), 27)
# Accurate as well as short: a run is nine holes, so the earlier "played in
# eighteen" was simply wrong about the game it was advertising.
line2 = "roguelike deckbuilding golf"
sw = draw.textlength(line2, font=sub)
sx = lx + (logo.width - sw) / 2
sy = ty + size + 16
for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (0, 0)):
    draw.text((sx + dx, sy + dy), line2, font=sub,
              fill=(216, 180, 106, 235) if (dx == 0 and dy == 0)
              else (8, 18, 11, 220))

out = os.path.join(SHOTS, "itch_banner.png")
banner.convert("RGB").save(out, quality=96)
print("wrote", out, banner.size)


# --- The cover ------------------------------------------------------------
#
# A different job from the banner and it needs a different picture. The cover is
# shown at a couple of hundred pixels in a grid of other games, so it has to work
# as a thumbnail: the wordmark carries it and the course is atmosphere behind.
CW, CH = 630, 500

src = Image.open(os.path.join(SHOTS, "banner_3.png")).convert("RGBA")
# Crop a squarer region from the green end, then scale to the cover.
side = src.height
box = (int(src.width * 0.62), 0, int(src.width * 0.62) + int(side * CW / CH), side)
cover = src.crop(box).resize((CW, CH), Image.LANCZOS)

wash = Image.new("RGBA", (CW, CH), (8, 20, 12, 150))
cover = Image.alpha_composite(cover, wash)

vig = Image.new("L", (CW, CH), 0)
ImageDraw.Draw(vig).ellipse((-CW * 0.25, -CH * 0.25, CW * 1.25, CH * 1.25), fill=255)
vig = vig.filter(ImageFilter.GaussianBlur(110))
dark = Image.new("RGBA", (CW, CH), (6, 14, 9, 255))
dark.putalpha(Image.eval(vig, lambda v: int((255 - v) * 0.75)))
cover = Image.alpha_composite(cover, dark)

mark = Image.open(os.path.join(ROOT, "resources/art/logo.png")).convert("RGBA")
mh = 352
mark = mark.resize((round(mark.width * mh / mark.height), mh), Image.LANCZOS)
mx, my = (CW - mark.width) // 2, 24

glow = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
glow.paste(Image.new("RGBA", mark.size, (0, 0, 0, 205)), (mx, my + 8), mark)
cover = Image.alpha_composite(cover, glow.filter(ImageFilter.GaussianBlur(20)))
cover.alpha_composite(mark, (mx, my))

cd = ImageDraw.Draw(cover)
cline = "THE COURSE IS THE ENEMY"
csize = 34
while csize > 14:
    cfont = ImageFont.truetype(
        os.path.join(ROOT, "resources/fonts/Lato-Bold.ttf"), csize)
    if cd.textlength(cline, font=cfont) <= CW - 72:
        break
    csize -= 1
cw_ = cd.textlength(cline, font=cfont)
cy = my + mh + 8
for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2), (0, 0)):
    cd.text(((CW - cw_) / 2 + dx, cy + dy), cline, font=cfont,
            fill=(233, 224, 196, 255) if (dx == 0 and dy == 0)
            else (8, 18, 11, 235))

csub = ImageFont.truetype(
    os.path.join(ROOT, "resources/fonts/Lato-Semibold.ttf"), 23)
sline = "roguelike deckbuilding golf"
sw_ = cd.textlength(sline, font=csub)
for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (0, 0)):
    cd.text(((CW - sw_) / 2 + dx, cy + csize + 14 + dy), sline, font=csub,
            fill=(216, 180, 106, 240) if (dx == 0 and dy == 0)
            else (8, 18, 11, 220))

cout = os.path.join(SHOTS, "itch_cover.png")
cover.convert("RGB").save(cout, quality=96)
print("wrote", cout, cover.size)
