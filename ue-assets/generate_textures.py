"""Generate ping marker textures for the Omega Strikers custom ping mod.

All textures are 512x512 RGBA PNGs with transparent backgrounds,
designed for use as UE5 decal materials.
"""

from PIL import Image, ImageDraw, ImageFont
import math
import os

SIZE = 512
CENTER = SIZE // 2
OUT_DIR = os.path.join(os.path.dirname(__file__), "textures")


def new_canvas():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def draw_circle(draw, cx, cy, r, fill=None, outline=None, width=1):
    draw.ellipse(
        [cx - r, cy - r, cx + r, cy + r],
        fill=fill,
        outline=outline,
        width=width,
    )


def draw_ring(draw, cx, cy, r_outer, r_inner, color):
    draw_circle(draw, cx, cy, r_outer, fill=color)
    draw_circle(draw, cx, cy, r_inner, fill=(0, 0, 0, 0))


def ping_generic():
    """White circle with inner ring — general-purpose ping."""
    img = new_canvas()
    draw = ImageDraw.Draw(img)
    white = (255, 255, 255, 230)
    white_soft = (255, 255, 255, 80)

    draw_circle(draw, CENTER, CENTER, 200, fill=white_soft)
    draw_circle(draw, CENTER, CENTER, 200, outline=white, width=8)
    draw_circle(draw, CENTER, CENTER, 140, outline=white, width=4)

    draw.line([(CENTER, CENTER - 30), (CENTER, CENTER + 30)], fill=white, width=6)
    draw.line([(CENTER - 30, CENTER), (CENTER + 30, CENTER)], fill=white, width=6)

    img.save(os.path.join(OUT_DIR, "ping_generic.png"))
    print("  ping_generic.png")


def ping_danger():
    """Red diamond with exclamation — danger/enemy ping."""
    img = new_canvas()
    draw = ImageDraw.Draw(img)
    red = (255, 50, 50, 240)
    red_soft = (255, 50, 50, 60)
    dark = (180, 20, 20, 255)

    diamond = [
        (CENTER, CENTER - 200),
        (CENTER + 160, CENTER),
        (CENTER, CENTER + 200),
        (CENTER - 160, CENTER),
    ]
    draw.polygon(diamond, fill=red_soft, outline=red, width=6)

    inner = [
        (CENTER, CENTER - 140),
        (CENTER + 112, CENTER),
        (CENTER, CENTER + 140),
        (CENTER - 112, CENTER),
    ]
    draw.polygon(inner, outline=dark, width=3)

    draw.line([(CENTER, CENTER - 90), (CENTER, CENTER + 30)], fill=red, width=12)
    draw_circle(draw, CENTER, CENTER + 70, 8, fill=red)

    img.save(os.path.join(OUT_DIR, "ping_danger.png"))
    print("  ping_danger.png")


def ping_assist():
    """Cyan crosshair/target — assist/focus ping."""
    img = new_canvas()
    draw = ImageDraw.Draw(img)
    cyan = (0, 220, 255, 240)
    cyan_soft = (0, 220, 255, 50)

    draw_circle(draw, CENTER, CENTER, 190, fill=cyan_soft)
    draw_circle(draw, CENTER, CENTER, 190, outline=cyan, width=6)
    draw_circle(draw, CENTER, CENTER, 120, outline=cyan, width=4)
    draw_circle(draw, CENTER, CENTER, 50, outline=cyan, width=4)

    gap = 60
    length = 200
    w = 5
    draw.line([(CENTER, CENTER - length), (CENTER, CENTER - gap)], fill=cyan, width=w)
    draw.line([(CENTER, CENTER + gap), (CENTER, CENTER + length)], fill=cyan, width=w)
    draw.line([(CENTER - length, CENTER), (CENTER - gap, CENTER)], fill=cyan, width=w)
    draw.line([(CENTER + gap, CENTER), (CENTER + length, CENTER)], fill=cyan, width=w)

    img.save(os.path.join(OUT_DIR, "ping_assist.png"))
    print("  ping_assist.png")


def ping_omw():
    """Green chevron/arrow — on my way ping."""
    img = new_canvas()
    draw = ImageDraw.Draw(img)
    green = (50, 255, 100, 240)
    green_soft = (50, 255, 100, 60)

    draw_circle(draw, CENTER, CENTER, 190, fill=green_soft)
    draw_circle(draw, CENTER, CENTER, 190, outline=green, width=5)

    arrow = [
        (CENTER, CENTER - 130),
        (CENTER + 100, CENTER + 30),
        (CENTER + 50, CENTER + 30),
        (CENTER + 50, CENTER + 130),
        (CENTER - 50, CENTER + 130),
        (CENTER - 50, CENTER + 30),
        (CENTER - 100, CENTER + 30),
    ]
    draw.polygon(arrow, fill=green, outline=(30, 200, 70, 255), width=3)

    img.save(os.path.join(OUT_DIR, "ping_omw.png"))
    print("  ping_omw.png")


def ping_retreat():
    """Yellow warning triangle — retreat/back off ping."""
    img = new_canvas()
    draw = ImageDraw.Draw(img)
    yellow = (255, 220, 40, 240)
    yellow_soft = (255, 220, 40, 60)
    dark_yellow = (200, 170, 20, 255)

    tri_h = int(190 * math.sqrt(3))
    tri = [
        (CENTER, CENTER - 180),
        (CENTER + 190, CENTER + tri_h // 2 - 80),
        (CENTER - 190, CENTER + tri_h // 2 - 80),
    ]
    draw.polygon(tri, fill=yellow_soft, outline=yellow, width=7)

    inner_s = 0.7
    inner_tri = [
        (CENTER, CENTER - int(180 * inner_s)),
        (CENTER + int(190 * inner_s), CENTER + int((tri_h // 2 - 80) * inner_s)),
        (CENTER - int(190 * inner_s), CENTER + int((tri_h // 2 - 80) * inner_s)),
    ]
    draw.polygon(inner_tri, outline=dark_yellow, width=3)

    draw.line([(CENTER, CENTER - 80), (CENTER, CENTER + 20)], fill=yellow, width=10)
    draw_circle(draw, CENTER, CENTER + 55, 7, fill=yellow)

    img.save(os.path.join(OUT_DIR, "ping_retreat.png"))
    print("  ping_retreat.png")


def ping_awaken():
    """Purple starburst — awakening ready ping."""
    img = new_canvas()
    draw = ImageDraw.Draw(img)
    purple = (180, 80, 255, 240)
    purple_soft = (180, 80, 255, 50)
    bright = (220, 140, 255, 255)

    draw_circle(draw, CENTER, CENTER, 190, fill=purple_soft)

    points = 8
    r_outer = 185
    r_inner = 100
    star = []
    for i in range(points * 2):
        angle = math.pi / 2 + (math.pi * i / points)
        r = r_outer if i % 2 == 0 else r_inner
        x = CENTER + r * math.cos(angle)
        y = CENTER - r * math.sin(angle)
        star.append((x, y))
    draw.polygon(star, fill=purple, outline=bright, width=4)

    draw_circle(draw, CENTER, CENTER, 40, fill=bright)
    draw_circle(draw, CENTER, CENTER, 25, fill=(255, 255, 255, 200))

    img.save(os.path.join(OUT_DIR, "ping_awaken.png"))
    print("  ping_awaken.png")


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Generating ping textures...")
    ping_generic()
    ping_danger()
    ping_assist()
    ping_omw()
    ping_retreat()
    ping_awaken()
    print(f"Done — {len(os.listdir(OUT_DIR))} textures in {OUT_DIR}")
