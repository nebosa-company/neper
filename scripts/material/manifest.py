"""Writes docs/ui/looks/ref/material/manifest.csv from the captured PNGs: python -I scripts/material/manifest.py"""
import os
import re

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REF = os.path.join(ROOT, "docs/ui/looks/ref/material")
CROP = 16
CONTROL = [
    ("icon-button", "button_icon"), ("button", "button"), ("fab", "fab"), ("checkbox", "checkbox"), ("radio", "radio"), ("switch", "switch"),
    ("text-field", "text_edit"), ("select", "combo_box"), ("chip", "chips"), ("slider", "slider"), ("progress", "progress_bar"), ("tabs", "page_control"),
    ("menu", "popup_menu"), ("list-item", "list_box"), ("dialog", "dialog"), ("snackbar", "snackbar"), ("tooltip", "hint"),
    ("navigation-bar", "navigation_bar"), ("app-bar", "app_bar"), ("search-bar", "search_bar"), ("badge", "badge"), ("date-picker", "date_picker"),
]
rows = []
for scheme in ("light", "dark"):
    d = os.path.join(REF, scheme)
    for f in sorted(os.listdir(d)):
        m = re.match(r"(.+)@1x\.png$", f)
        if not m or m.group(1).endswith("-notext"):
            continue
        n = m.group(1)
        im = Image.open(os.path.join(d, f))
        ctl = next((c for p, c in CONTROL if n.startswith(p)), n)
        rows.append("%s,%s,%s,%s/%s@1x.png,%s/%s@2x.png,%d,%d,margin=%d" % (scheme, ctl, n, scheme, n, scheme, n, im.width - 2 * CROP, im.height - 2 * CROP, CROP))
with open(os.path.join(REF, "manifest.csv"), "w") as f:
    f.write("scheme,neper_control,name,png_1x,png_2x,w_1x,h_1x,note\n" + "\n".join(rows) + "\n")
print(len(rows), "cells")
