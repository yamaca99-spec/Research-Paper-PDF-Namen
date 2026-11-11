#!/usr/bin/env python3
"""Draws the app icon (Resources/AppIcon.icns). Requires Pillow: pip install pillow"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 2048  # drawn at 2x, scaled down to 1024 for smooth edges


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def rounded_mask(size, box, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def main(out_path):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Background tile (Apple icon grid: 824/1024 body with soft shadow).
    margin = int(S * 100 / 1024)
    box = (margin, margin, S - margin, S - margin)
    radius = int(S * 185 / 1024)

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (box[0], box[1] + 24, box[2], box[3] + 24), radius=radius, fill=(0, 0, 0, 110)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    img.alpha_composite(shadow)

    top, bottom = (79, 70, 229), (14, 165, 233)
    gradient = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(gradient)
    for y in range(S):
        t = y / (S - 1)
        gd.line([(0, y), (S, y)], fill=lerp(top, bottom, t) + (255,))
    img.paste(gradient, (0, 0), rounded_mask((S, S), box, radius))

    d = ImageDraw.Draw(img)

    # Paper sheet with folded corner.
    px0, py0, px1, py1 = int(S * 0.29), int(S * 0.20), int(S * 0.69), int(S * 0.76)
    fold = int(S * 0.11)
    paper_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(paper_shadow).polygon(
        [(px0, py0 + 20), (px1 - fold, py0 + 20), (px1, py0 + fold + 20), (px1, py1 + 20), (px0, py1 + 20)],
        fill=(0, 0, 0, 90),
    )
    paper_shadow = paper_shadow.filter(ImageFilter.GaussianBlur(22))
    img.alpha_composite(paper_shadow)
    d = ImageDraw.Draw(img)
    d.polygon([(px0, py0), (px1 - fold, py0), (px1, py0 + fold), (px1, py1), (px0, py1)], fill=(255, 255, 255, 255))
    d.polygon([(px1 - fold, py0), (px1 - fold, py0 + fold), (px1, py0 + fold)], fill=(203, 213, 225, 255))

    # Title bar and text lines.
    lx0 = px0 + int(S * 0.05)
    d.rounded_rectangle((lx0, py0 + int(S * 0.08), px1 - fold - int(S * 0.02), py0 + int(S * 0.115)),
                        radius=18, fill=(49, 46, 129, 255))
    d.rounded_rectangle((lx0, py0 + int(S * 0.145), px1 - int(S * 0.12), py0 + int(S * 0.17)),
                        radius=14, fill=(99, 102, 241, 255))
    y = py0 + int(S * 0.23)
    for width in (0.30, 0.27, 0.30, 0.22, 0.28):
        d.rounded_rectangle((lx0, y, lx0 + int(S * width), y + int(S * 0.018)), radius=10, fill=(203, 213, 225, 255))
        y += int(S * 0.048)

    # Pencil crossing the lower right corner.
    cx, cy = S * 0.64, S * 0.66
    angle = math.radians(-45)
    length, width = S * 0.42, S * 0.085

    def rot(x, yv):
        return (cx + x * math.cos(angle) - yv * math.sin(angle), cy + x * math.sin(angle) + yv * math.cos(angle))

    half = width / 2
    body_start, body_end = -length * 0.35, length * 0.45
    tip = -length * 0.55
    pencil_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(pencil_shadow).polygon(
        [(p[0] + 14, p[1] + 22) for p in [rot(tip, 0), rot(body_start, -half), rot(body_end, -half),
                                          rot(body_end, half), rot(body_start, half)]],
        fill=(0, 0, 0, 100),
    )
    pencil_shadow = pencil_shadow.filter(ImageFilter.GaussianBlur(18))
    img.alpha_composite(pencil_shadow)
    d = ImageDraw.Draw(img)
    d.polygon([rot(body_start, -half), rot(body_end - width * 0.6, -half),
               rot(body_end - width * 0.6, half), rot(body_start, half)], fill=(251, 191, 36, 255))
    d.polygon([rot(body_start, -half), rot(body_end - width * 0.6, -half),
               rot(body_end - width * 0.6, 0), rot(body_start, 0)], fill=(253, 224, 71, 255))
    d.polygon([rot(body_end - width * 0.6, -half), rot(body_end - width * 0.25, -half),
               rot(body_end - width * 0.25, half), rot(body_end - width * 0.6, half)], fill=(148, 163, 184, 255))
    d.polygon([rot(body_end - width * 0.25, -half), rot(body_end, -half),
               rot(body_end, half), rot(body_end - width * 0.25, half)], fill=(244, 114, 182, 255))
    d.polygon([rot(tip, 0), rot(body_start, -half), rot(body_start, half)], fill=(254, 243, 199, 255))
    lead = tip + (body_start - tip) * 0.35
    d.polygon([rot(tip, 0), rot(lead, -half * 0.35), rot(lead, half * 0.35)], fill=(30, 41, 59, 255))

    icon = img.resize((1024, 1024), Image.LANCZOS)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    icon.save(out_path, format="ICNS")
    icon.save(os.path.splitext(out_path)[0] + ".png")
    print("wrote", out_path)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "Resources", "AppIcon.icns"))
