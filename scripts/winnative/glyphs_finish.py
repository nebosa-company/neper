"""glyphs.exe output to the repository oracle: <tag>.outline.txt -> <tag>.outline.gz (one glyph per line), <tag>.<fg>-<bg>.bgra -> PNG.

python glyphs_finish.py <rawdir> <outdir>

Outline line (all integers, 26.6 pixels, y up, x from the pen): code adv a b c bbx bby orgx orgy ncont { npts { x y on } }
where the contour is H (on), then every L point on, every spline control point off and the last point of each spline record
on (GGO_NATIVE's B-spline convention); the closing point equal to the start is dropped. adv is gmCellIncX (the hinted whole-pixel advance); a, b, c the ABC widths.
GGO_NATIVE is the black-and-white hinted outline (ClearType quality changes nothing in it), so it checks the black-and-white machine and
the advance, not the ClearType outline; the pixels are the ClearType truth.
"""
import glob
import gzip
import os
import shutil
import struct
import sys
import winreg

import numpy as np
from PIL import Image


def outline(path, out):
    head = None
    glyphs = []
    cur = None
    for ln in open(path, encoding="latin-1").read().splitlines():
        t = ln.split()
        if t[0] == "FONT":
            head = " ".join(t[1:])
        elif t[0] == "G":
            cur = {"code": int(t[1]), "contours": [], "err": t[2] == "ERR"}
            if not cur["err"]:
                cur.update(adv=int(t[3]), bbx=int(t[6]), bby=int(t[7]), ox=int(t[9]), oy=int(t[10]))
            glyphs.append(cur)
        elif t[0] == "W":
            cur["abc"] = (int(t[2]), int(t[3]), int(t[4]))
        elif t[0] == "H":
            cur["contours"].append([("H", int(t[1]) >> 10, int(t[2]) >> 10)])
        else:
            cur["contours"][-1].append((t[0], int(t[1]) >> 10, int(t[2]) >> 10))
    with gzip.open(out, "wt", encoding="ascii", compresslevel=9) as f:
        f.write("font " + head + "\n")
        for g in glyphs:
            if g["err"]:
                continue
            body = []
            for c in g["contours"]:
                pts = []
                for i, (k, x, y) in enumerate(c):
                    on = 0 if k == "Q" else 1
                    pts.append((x, y, on))
                if len(pts) > 1 and pts[-1][:2] == pts[0][:2]:
                    pts.pop()
                body.append(" ".join([str(len(pts))] + ["%d %d %d" % p for p in pts]))
            a, b, cc = g["abc"]
            row = [g["code"], g["adv"], a, b, cc, g["bbx"], g["bby"], g["ox"], g["oy"], len(g["contours"])]
            f.write(" ".join(map(str, row)) + (" " + " ".join(body) if body else "") + "\n")


def bgra(path, out):
    d = open(path, "rb").read()
    w, h = struct.unpack("<ii", d[:8])
    a = np.frombuffer(d[24:], np.uint8).reshape(h, w, 4)
    Image.fromarray(a[:, :, 2::-1].copy(), "RGB").save(out, optimize=True)
    return struct.unpack("<6i", d[:24])


def main():
    raw, dst = sys.argv[1:3]
    os.makedirs(dst, exist_ok=True)
    for f in glob.glob(dst + "/*"):
        if not f.endswith(("README.md", "exact.txt")):
            os.remove(f)
    meta = []
    for p in sorted(glob.glob(raw + "/NProbe*.ttf")) + [raw + "/probe.json"]:
        if os.path.exists(p):
            shutil.copy(p, dst)
    for p in sorted(glob.glob(raw + "/*.outline.txt")):
        outline(p, os.path.join(dst, os.path.basename(p)[:-12] + ".outline.gz"))
    for p in sorted(glob.glob(raw + "/*.bgra")):
        b = os.path.basename(p)[:-5]
        hdr = bgra(p, os.path.join(dst, b + ".png"))
        meta.append("%s %s" % (b, " ".join(map(str, hdr))))
    open(os.path.join(dst, "atlases.txt"), "w").write("# name w h cellw cellh ascent(or steps) pad(or 16)\n" + "\n".join(meta) + "\n")
    s = open(raw + "/settings.txt", encoding="utf-16" if open(raw + "/settings.txt", "rb").read(2) in (b"\xff\xfe", b"\xfe\xff") else "ascii").read() if os.path.exists(raw + "/settings.txt") else ""
    reg = []
    key = "Control Panel\\Desktop"
    k = winreg.OpenKey(winreg.HKEY_CURRENT_USER, key)
    for n in ("FontSmoothing", "FontSmoothingType", "FontSmoothingGamma", "FontSmoothingOrientation", "FontSmoothingContrast"):
        try:
            reg.append("HKCU\\%s\\%s = %r" % (key, n, winreg.QueryValueEx(k, n)[0]))
        except OSError:
            reg.append("HKCU\\%s\\%s (not set)" % (key, n))
    open(os.path.join(dst, "settings.txt"), "w").write(s.replace("\r", "") + "\n".join(reg) + "\n")
    print("wrote", len(os.listdir(dst)), "files,", sum(os.path.getsize(os.path.join(dst, x)) for x in os.listdir(dst)) // 1024, "KB")


main()
