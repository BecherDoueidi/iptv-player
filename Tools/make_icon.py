"""Regenerates the app icon.

The shipped icon is variant C, written to
App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png. It's kept as code rather
than only as a binary so the mark can be recoloured or resized later without redrawing
it by hand. The other two variants are the rejected candidates, kept for the same reason.

Everything is drawn at 4x and downsampled, which is what keeps the curves clean without
any antialiasing tricks. Requires Pillow; run from the repo root:

    python Tools/make_icon.py --install
"""
from PIL import Image, ImageDraw, ImageFilter
import os

S = 4096          # working size
OUT = 1024        # final icon size
# Renders land here; only the installed AppIcon.png is committed.
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "generated")
os.makedirs(OUTPUT_DIR, exist_ok=True)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def diagonal_gradient(c0, c1, size=S, steep=1.0):
    """Built small and upscaled — a per-pixel loop at 4096 would be needlessly slow."""
    n = 256
    g = Image.new("RGB", (n, n))
    px = g.load()
    for y in range(n):
        for x in range(n):
            t = (x / (n - 1) * steep + y / (n - 1)) / (1 + steep)
            px[x, y] = lerp(c0, c1, t)
    return g.resize((size, size), Image.LANCZOS)


def rounded_polygon(draw, points, radius, fill):
    """PIL has no rounded-corner polygon; stroking the outline with a curved joint
    and the same fill rounds the vertices."""
    draw.polygon(points, fill=fill)
    # Wrapping two points past the end, not one: `joint` only rounds *between*
    # segments, so closing back to points[0] alone leaves that first vertex square.
    draw.line(list(points) + [points[0], points[1]], fill=fill, width=radius * 2, joint="curve")


def play_triangle(cx, cy, size):
    """Optically centred: a triangle centred on its bounding box looks left-heavy."""
    h = size
    w = size * 0.87
    return [
        (cx - w * 0.42, cy - h / 2),
        (cx - w * 0.42, cy + h / 2),
        (cx + w * 0.58, cy),
    ]


def finish(img, name):
    icon = img.convert("RGB").resize((OUT, OUT), Image.LANCZOS)
    path = os.path.join(OUTPUT_DIR, name)
    icon.save(path, "PNG")
    return path


# ---------------------------------------------------------------- A: ring + play
def variant_a():
    img = diagonal_gradient((255, 45, 106), (109, 40, 217))
    d = ImageDraw.Draw(img)
    cx = cy = S / 2

    ring_r = S * 0.335
    d.ellipse([cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r],
              outline=(255, 255, 255), width=int(S * 0.045))

    rounded_polygon(d, play_triangle(cx, cy, S * 0.30), int(S * 0.022), (255, 255, 255))
    return finish(img, "icon_a_ring.png")


# ------------------------------------------------- B: broadcast arcs + play
def variant_b():
    img = diagonal_gradient((6, 22, 64), (0, 200, 255), steep=0.6)
    d = ImageDraw.Draw(img)
    cx, cy = S / 2, S * 0.53

    # Signal arcs sweeping out of the top-left, suggesting broadcast.
    for i, r in enumerate([0.30, 0.42, 0.54]):
        rr = S * r
        width = int(S * (0.040 - i * 0.007))
        alpha = 255 - i * 60
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        ld.arc([cx - rr, cy - rr, cx + rr, cy + rr], start=185, end=265,
               fill=(255, 255, 255, alpha), width=width)
        img = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")
        d = ImageDraw.Draw(img)

    rounded_polygon(d, play_triangle(cx + S * 0.03, cy, S * 0.34), int(S * 0.024), (255, 255, 255))
    return finish(img, "icon_b_broadcast.png")


# --------------------------------------------- C: neon play on near-black
def variant_c():
    img = Image.new("RGB", (S, S), (11, 11, 16))
    cx = cy = S / 2

    # Glow: the triangle drawn large and blurred under the sharp one.
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    rounded_polygon(gd, play_triangle(cx, cy, S * 0.46), int(S * 0.03), (255, 60, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.045))
    img = Image.blend(img, glow, 0.55)

    # The mark itself, filled with a gradient clipped to the triangle.
    grad = diagonal_gradient((255, 214, 0), (255, 45, 106))
    mask = Image.new("L", (S, S), 0)
    rounded_polygon(ImageDraw.Draw(mask), play_triangle(cx, cy, S * 0.44), int(S * 0.028), 255)
    img.paste(grad, (0, 0), mask)
    return finish(img, "icon_c_neon.png")


def contact_sheet(paths):
    """Shows each candidate at real home-screen size next to the full render — an icon
    that only works at 1024 is not an icon."""
    pad, big, small = 40, 300, 90
    sheet = Image.new("RGB", (pad + (big + pad) * len(paths), big + small + pad * 3), (245, 245, 247))
    for i, p in enumerate(paths):
        icon = Image.open(p)
        x = pad + i * (big + pad)
        sheet.paste(icon.resize((big, big), Image.LANCZOS), (x, pad))
        sheet.paste(icon.resize((small, small), Image.LANCZOS), (x + (big - small) // 2, pad * 2 + big))
    out = os.path.join(OUTPUT_DIR, "icon_options.png")
    sheet.save(out)
    return out


ICON_DESTINATION = os.path.join(
    "App", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png"
)


if __name__ == "__main__":
    import shutil
    import sys

    paths = [variant_a(), variant_b(), variant_c()]
    # Basenames, not full paths: this repo's own path isn't representable in the
    # Windows console codepage, and printing it raises UnicodeEncodeError.
    for rendered in paths + [contact_sheet(paths)]:
        print(os.path.basename(rendered))

    # iOS wants a single 1024x1024 with no alpha; `finish` already converts to RGB.
    if "--install" in sys.argv:
        shutil.copyfile(paths[2], ICON_DESTINATION)
        print("installed icon_c_neon.png -> AppIcon.png")
