"""Turns the pairs capture_textonly.mjs writes into the text masks text_cmp.py reads.

  python -I scripts/material/textmask.py [TMPDIR]        (default D:/Temp/textonly; from the repository root)

For each <scheme>/<cell>@1x-settled.png with its @1x-textonly.png twin in TMPDIR, writes
docs/ui/looks/ref/material/<scheme>/<cell>@1x-textmask.png: 255 where the text (and nothing else) changes a channel by more than 2
levels, 0 elsewhere. Both pictures are taken after the cell's transitions have settled, so a hover elevation or a ripple that was still
moving in the reference picture does not count as text.
"""
import glob
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF = os.path.join(ROOT, "docs/ui/looks/ref/material")


def main():
    tmp = sys.argv[1] if len(sys.argv) > 1 else "D:/Temp/textonly"
    n = 0
    for scheme in ("light", "dark"):
        for settled in sorted(glob.glob(os.path.join(tmp, scheme, "*@1x-settled.png"))):
            twin = settled.replace("-settled", "-textonly")
            if not os.path.exists(twin):
                continue
            a = np.array(Image.open(settled).convert("RGB")).astype(int)
            b = np.array(Image.open(twin).convert("RGB")).astype(int)
            mask = (np.abs(a - b).max(axis=2) > 2).astype(np.uint8) * 255
            name = os.path.basename(settled).replace("-settled", "-textmask")
            out = os.path.join(REF, scheme, name)
            Image.fromarray(mask, "L").save(out, optimize=True)
            n += 1
    print("masks", n)


if __name__ == "__main__":
    main()
