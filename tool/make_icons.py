#!/usr/bin/env python3
"""Build the launcher icons from the logo artwork.

A script rather than five exported PNGs, so re-cropping the logo or redrawing it
is one command instead of an afternoon in an image editor with a note about
which size went where.

Two sets are written, because Android needs both:

* **Legacy** `mipmap-*/ic_launcher.png` -- the whole square, used below API 26
  and as the fallback anywhere the adaptive one is not read.
* **Adaptive** `mipmap-anydpi-v26/ic_launcher.xml` plus a foreground layer --
  API 26 and up. The launcher masks this to whatever shape the phone uses
  (circle, squircle, teardrop) and may animate it, so the art sits inside the
  inner 66% safe zone with transparent margin around it. Art drawn to the edge
  of an adaptive foreground gets its edges cut off on a round mask.

Usage:  python3 tool/make_icons.py <source-image>
"""

import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"

# Android's five launcher densities, in px.
LEGACY = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# The adaptive foreground is a 108dp square of which only the middle 72dp is
# guaranteed visible. 0.66 keeps the drawing inside that.
SAFE_FRACTION = 0.66

# Adaptive foregrounds are authored at 108dp; these are that at each density.
ADAPTIVE = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

BACKGROUND = (255, 255, 255)


def trimmed(im):
    """The artwork with its surrounding white cropped away.

    The source is a drawing on a white field with uneven margins, and padding a
    square around the *uncropped* image inherits that unevenness -- the figure
    ends up off-centre in the icon. Cropping to the ink first means the padding
    added afterwards is symmetrical by construction.
    """
    grey = im.convert("L")
    # Not pure white: a JPEG of a white page is full of 250-254 pixels, and a
    # threshold of 255 would find no margin to trim at all.
    mask = grey.point(lambda v: 255 if v < 245 else 0)
    box = mask.getbbox()
    return im.crop(box) if box else im


def square(im, size, fill, fraction=1.0, transparent=False):
    """The artwork centred on a square canvas, scaled to `fraction` of it."""
    art = im.copy()
    target = int(size * fraction)
    art.thumbnail((target, target), Image.LANCZOS)

    mode = "RGBA" if transparent else "RGB"
    bg = (0, 0, 0, 0) if transparent else fill
    canvas = Image.new(mode, (size, size), bg)
    canvas.paste(
        art.convert(mode),
        ((size - art.width) // 2, (size - art.height) // 2),
        art.convert("RGBA") if transparent else None,
    )
    return canvas


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python3 tool/make_icons.py <source-image>")
    src = pathlib.Path(sys.argv[1])
    if not src.exists():
        sys.exit(f"no such file: {src}")

    art = trimmed(Image.open(src).convert("RGB"))
    print(f"source {Image.open(src).size} -> trimmed {art.size}")

    for density, px in LEGACY.items():
        out = RES / f"mipmap-{density}" / "ic_launcher.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        # 0.88, not 1.0: a legacy icon is drawn as-is with no mask, and art
        # touching the edge looks cramped against every other icon on the
        # screen, all of which have their own margin built in.
        square(art, px, BACKGROUND, fraction=0.88).save(out)
        print(f"  {out.relative_to(ROOT)}  {px}x{px}")

    for density, px in ADAPTIVE.items():
        out = RES / f"mipmap-{density}" / "ic_launcher_foreground.png"
        square(art, px, BACKGROUND, fraction=SAFE_FRACTION, transparent=True).save(out)
        print(f"  {out.relative_to(ROOT)}  {px}x{px} (adaptive foreground)")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )
    values = RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        "    <!-- The drawing is black ink with no fill of its own, so the icon\n"
        "         needs a field behind it or the launcher shows the ink floating\n"
        "         on whatever wallpaper happens to be there. -->\n"
        '    <color name="ic_launcher_background">#FFFFFFFF</color>\n'
        "</resources>\n"
    )
    print(f"  {(anydpi / 'ic_launcher.xml').relative_to(ROOT)}")
    print(f"  {(values / 'ic_launcher_background.xml').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
