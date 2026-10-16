"""Round 13: prints the native light scroll bar arrows (ref/windows-native/light/*scroll*) as `gl.pixels` strings (RGB hex, row by row) for
control.windows_scroll_bar's disabled bar and pressed upper / left arrows: `python -I scripts/looks_bar_native.py`."""
import os
import numpy as np
from PIL import Image

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "ui", "looks", "ref", "windows-native", "light") + os.sep


def load(n):
    return np.array(Image.open(R + n + "@1x.png").convert("RGB")).astype(int)


def hexs(a):
    return "".join("%02X%02X%02X" % tuple(p) for p in a.reshape(-1, 3))


v, h = load("vscroll-disabled"), load("hscroll-disabled")
vp, hp = load("vscroll-pressed-arrow"), load("hscroll-pressed-arrow")
print("arrow_up_disabled 10x6", hexs(v[16:22, 24:34]))
print("arrow_down_disabled 10x6", hexs(v[169:175, 24:34]))
print("arrow_left_disabled 6x10", hexs(h[24:34, 21:27]))
print("arrow_right_disabled 6x10", hexs(h[24:34, 183:189]))
print("arrow_up_pressed 12x8 (x 22..33, rows 15..22)", hexs(vp[15:23, 22:34]))
print("arrow_left_pressed (x 20..27 rows 24..33)", hexs(hp[24:34, 20:28]))
