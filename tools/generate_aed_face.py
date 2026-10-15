#!/usr/bin/env python3
"""Draws the AED front graphics (red panel, placement pictogram, numbered steps,
speaker, labels) into assets/models/aed_face.png for tools/generate_models.py.

Layout follows the common single-button public-access AED face (white housing,
red panel, black step panel, automatic-shock indicator). Manufacturer marks are
deliberately replaced by the NaReT label. Coordinates are millimetres on the
256 x 250 mm front, origin top-left; the image maps 256 mm to its full width.
Run: python3 tools/generate_aed_face.py   (needs Pillow)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / "assets/models/aed_face.png"
S = 8                      # pixels per mm: a 2048 px texture
W_MM, H_MM = 256, 250
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

WHITE = (236, 238, 240)
RED = (214, 30, 45)
BLACK = (22, 22, 24)
INK = (40, 40, 44)
GREY = (170, 172, 176)
LIGHT = (214, 216, 220)
GREEN = (58, 170, 60)
NAVY = (36, 44, 92)

img = Image.new("RGB", (W_MM * S, W_MM * S), WHITE)
d = ImageDraw.Draw(img)


def mm(*values):
    return [v * S for v in values]


def box(x0, y0, x1, y1, fill, r=0, outline=None, width=0):
    d.rounded_rectangle(mm(x0, y0, x1, y1), radius=r * S, fill=fill, outline=outline, width=int(width * S))


def text(x, y, value, size, fill, bold=False, anchor="mm"):
    font = ImageFont.truetype(BOLD if bold else FONT, int(size * S))
    d.text((x * S, y * S), value, font=font, fill=fill, anchor=anchor)


def line(points, fill, width):
    # Drawn 1.6x heavier than the print: the headset sees it from ~60 cm.
    d.line([p * S for xy in points for p in xy], fill=fill, width=int(width * 1.6 * S), joint="curve")


def circle(x, y, r, fill=None, outline=None, width=0):
    d.ellipse(mm(x - r, y - r, x + r, y + r), fill=fill, outline=outline, width=int(width * S))


# Soft housing shading: lighter centre, the moulding reads rounder in the headset.
for i in range(40):
    shade = tuple(int(c - (40 - i) * .35) for c in WHITE)
    box(i * .6, i * .6, W_MM - i * .6, H_MM - i * .6, shade, 30)

# Red panel wrapping the speaker, pictogram and step panel.
box(28, 42, 194, 222, RED, 14)

# Adult / child selector slot.
box(46, 51, 112, 77, LIGHT, 4, GREY, .6)
box(80, 55, 106, 73, WHITE, 3)
circle(87, 64, 3.2, GREY)
circle(95, 64, 3.2, GREY)
line([(54, 57), (54, 70)], INK, 1.4)          # adult figure
circle(54, 55.5, 1.6, INK)
line([(66, 61), (66, 69)], INK, 1.2)          # child figure
circle(66, 59.5, 1.3, INK)
text(56, 74.5, ">8", 3, INK)
text(98, 74.5, "(1-8)", 3, INK)

# Sensor window above the pictogram (the 3D lens sits on it).
box(118, 51, 142, 75, BLACK, 4)

# NaReT label in place of the manufacturer mark.
text(36, 94, "NaReT", 10, WHITE, True, "lm")
text(36, 103, "Trainings-AED", 4.2, WHITE, False, "lm")
text(36, 115, "Training device", 3.4, WHITE, False, "lm")
text(36, 119.5, "not for clinical use", 3.4, WHITE, False, "lm")

# Speaker grille.
d.ellipse(mm(26, 140, 70, 206), fill=WHITE)
for row in range(15):
    for col in range(9):
        cx, cy = 32 + col * 4.4 + (row % 2) * 2.2, 146 + row * 4.1
        if ((cx - 48) / 20) ** 2 + ((cy - 173) / 31) ** 2 < 1:
            circle(cx, cy, 1.05, GREY)

# Placement pictogram: supine adult from the rescuer's view, pads at the right
# clavicle and the left mid-axillary line, as on every adult electrode pack.
box(72, 82, 146, 168, WHITE, 3)
line([(98, 104), (95, 111), (82, 115), (77, 125), (76, 168)], INK, .9)     # right shoulder & arm
line([(118, 104), (121, 111), (134, 115), (139, 125), (140, 168)], INK, .9)
line([(84, 130), (86, 150), (90, 168)], INK, .9)                           # torso flanks
line([(132, 130), (130, 150), (126, 168)], INK, .9)
d.ellipse(mm(100, 86, 116, 105), outline=INK, width=int(.9 * S))           # head
line([(103, 95), (106, 95)], INK, .6)
line([(110, 95), (113, 95)], INK, .6)
line([(106.5, 100.5), (109.5, 100.5)], INK, .6)
line([(99, 124), (104, 126)], INK, .5)                                     # chest contour
line([(117, 124), (112, 126)], INK, .5)
line([(108, 130), (108, 150)], INK, .4)
box(87, 116, 99, 130, LIGHT, 1.5, INK, .5)                                 # pad 1
box(121, 142, 133, 156, LIGHT, 1.5, INK, .5)                               # pad 2
line([(93, 116), (100, 110), (140, 92), (146, 90)], INK, .6)               # lead 1
line([(133, 149), (146, 148)], INK, .6)                                    # lead 2

# Step panel: device name, then the two numbered steps with their leaders.
box(146, 82, 194, 168, BLACK, 5)
text(170, 96, "AED", 14, WHITE, True)
circle(168, 118, 7, None, GREEN, 1.1)
text(168, 118.4, "1", 9, GREEN, True)
line([(175, 118), (189, 118)], WHITE, .6)
circle(189.5, 118, 1.3, WHITE)
circle(158, 148, 7, None, WHITE, 1.1)
text(158, 148.4, "2", 9, WHITE, True)
line([(151, 148), (146, 148)], WHITE, .6)

# Two small pictograms: stand clear, compressions.
for x0 in (84, 124):
    box(x0, 176, x0 + 34, 212, WHITE, 3, GREY, .4)
line([(92, 206), (110, 206)], INK, .7)                                    # person lying
circle(98, 190, 2.2, None, INK, .6)                                        # clear: arms up
line([(98, 192.5), (98, 201)], INK, .7)
line([(98, 195), (93, 187)], INK, .7)
line([(98, 195), (103, 187)], INK, .7)
line([(131, 206), (151, 206)], INK, .7)                                    # compressions
line([(141, 184), (141, 202)], INK, 1.4)
line([(136, 195), (146, 195)], INK, .7)
line([(137, 199), (141, 203), (145, 199)], INK, .7)

# Info button print and status LED ring.
circle(180, 196, 8.5, LIGHT, GREY, .6)
text(180, 196.5, "i", 8, INK, True)
circle(188, 77, 2.8, (190, 200, 190))

# Right column: connector well, on/off, automatic shock indicator.
box(205, 50, 235, 80, LIGHT, 4)
text(220, 147, "ON/OFF", 4.6, INK, True)
circle(220, 176, 15, NAVY)
text(220, 171.5, "Automatic", 3.9, WHITE)
text(220, 179.5, "Shock", 5.4, WHITE, True)
text(128, 240, "SD Card", 3, (205, 207, 210))
# Status display under the shock indicator (the app renders into it; dark glass when off).
box(203, 197, 237, 233, (60, 64, 70), 3.5)
box(204.5, 198.5, 235.5, 231.5, (14, 16, 18), 2.5)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT, optimize=True)
print("NARET_AED_FACE", OUT)


# Electrode pad print: white foam, grey rim, placement pictogram, as on adult pads.
PAD = Path(OUT).with_name("aed_pad.png")
pad = Image.new("RGB", (120 * S // 2, 90 * S // 2), (242, 243, 244))
p = ImageDraw.Draw(pad)
k = S // 2
p.rounded_rectangle([2 * k, 2 * k, 118 * k, 88 * k], radius=14 * k, outline=(150, 154, 160), width=int(1.6 * k))
p.rounded_rectangle([10 * k, 10 * k, 110 * k, 80 * k], radius=10 * k, outline=(205, 208, 212), width=int(.8 * k))
cx, cy = 88, 45
p.ellipse([(cx - 6) * k, (cy - 26) * k, (cx + 6) * k, (cy - 14) * k], outline=(60, 60, 66), width=int(1.2 * k))
p.line([((cx - 16) * k, (cy - 8) * k), ((cx - 12) * k, (cy + 26) * k)], fill=(60, 60, 66), width=int(1.2 * k))
p.line([((cx + 16) * k, (cy - 8) * k), ((cx + 12) * k, (cy + 26) * k)], fill=(60, 60, 66), width=int(1.2 * k))
p.line([((cx - 16) * k, (cy - 8) * k), ((cx + 16) * k, (cy - 8) * k)], fill=(60, 60, 66), width=int(1.2 * k))
p.rectangle([(cx - 12) * k, (cy - 5) * k, (cx - 5) * k, (cy + 3) * k], fill=(214, 30, 45))
p.rectangle([(cx + 6) * k, (cy + 10) * k, (cx + 12) * k, (cy + 18) * k], fill=(214, 30, 45))
font = ImageFont.truetype(BOLD, int(7 * k))
p.text((16 * k, 20 * k), "ADULT", font=font, fill=(60, 60, 66))
p.text((16 * k, 32 * k), "> 8", font=ImageFont.truetype(FONT, int(6 * k)), fill=(90, 90, 96))
pad.save(PAD, optimize=True)
print("NARET_AED_PAD", PAD)
