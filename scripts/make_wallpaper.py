#!/usr/bin/env python3
# Resamples the wallpaper source to exactly the Pixel 9 Pro panel (1280 x 2856), once, offline, so the
# device never rescales a 3.6 MP image: a cover fit (scale until both sides are covered, crop the
# overflow around the centre) with a Lanczos filter, stored as 8-bit greyscale PNG (the lunar surface
# carries no colour worth four times the bytes; the shell's decoder draws R8 as grey).
# Usage: python scripts/make_wallpaper.py <source.jpg> [neperos/assets/wallpaper/neper-crater.png]
import os
import sys

from PIL import Image

WIDTH, HEIGHT = 1280, 2856

source = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "neperos", "assets", "wallpaper", "neper-crater.png")
image = Image.open(source).convert("L")
scale = max(WIDTH / image.width, HEIGHT / image.height)
resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
left = (resized.width - WIDTH) // 2
top = (resized.height - HEIGHT) // 2
cropped = resized.crop((left, top, left + WIDTH, top + HEIGHT))
assert cropped.size == (WIDTH, HEIGHT)
cropped.save(out, optimize=True)
print("wrote", out, os.path.getsize(out), "bytes", cropped.size)
