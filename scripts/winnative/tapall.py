"""Reads the ClearType-hinted points of every glyph of the oracle fonts and sizes through tap fonts (see tapfont.py) and writes
docs/ui/looks/ref/windows-native/glyphs/<tag>.hinted.gz (format in tapread.py).

python tapall.py [tag-substring ...]

Needs glyphs.exe from glyphs.ps1 (D:\\Temp\\claude\\winnative) and the fonts in C:\\Windows\\Fonts. About 25 seconds per font and size; no window is
shown. Each atlas of a tap font is 3200 x 3360 pixels, written to a scratch folder and thrown away.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "docs", "ui", "looks", "ref", "windows-native", "glyphs")
BIN = r"D:\Temp\claude\winnative"
WORK = os.path.join(BIN, "tap")
FONTS = {  # tag prefix -> (font file, weight, sizes)
    "Segoe_UI-400": ("segoeui.ttf", 400, (11, 12, 13, 14, 15, 16, 18, 24)),
    "Segoe_UI-700": ("segoeuib.ttf", 700, (11, 12, 13, 14, 15, 16, 18, 24)),
    "Tahoma-400": ("tahoma.ttf", 400, (11, 12, 13, 14, 16, 21)),
    "Tahoma-700": ("tahomabd.ttf", 700, (11, 12, 13, 14, 16, 21)),
}


def run(cmd, env=None):
    e = dict(os.environ)
    e.update(env or {})
    subprocess.run(cmd, check=True, env=e, stdout=subprocess.DEVNULL)


def one(tag, fontfile, weight, ppem):
    os.makedirs(WORK, exist_ok=True)
    family = "NTap" + tag.replace("-", "").replace("_", "")
    ttf = os.path.join(WORK, "%s%d.ttf" % (family, ppem))
    run([sys.executable, os.path.join(HERE, "tapfont.py"), os.path.join(r"C:\Windows\Fonts", fontfile), ttf, family, str(ppem)])
    atlases = []
    for mode in (1, 2):
        scratch = os.path.join(WORK, "out%d" % mode)
        os.makedirs(scratch, exist_ok=True)
        run([os.path.join(BIN, "glyphs.exe"), scratch, family, str(weight), str(ppem), "5"],
            {"GLYPHS_READER": str(mode), "GLYPHS_FONT": ttf, "GLYPHS_CELL": "200,210,110", "GLYPHS_NOOUTLINE": "1"})
        atlases.append(os.path.join(scratch, "%s-%d-%d-q5.000000-FFFFFF.bgra" % (family, weight, ppem)))
    out = os.path.join(OUT, "%s-%d-q5.hinted.gz" % (tag, ppem))
    run([sys.executable, os.path.join(HERE, "tapread.py"), os.path.join(r"C:\Windows\Fonts", fontfile), atlases[0], atlases[1], out])
    for a in atlases:
        os.remove(a)


def main():
    want = sys.argv[1:]
    for tag, (fontfile, weight, sizes) in FONTS.items():
        for ppem in sizes:
            if want and not any(w in "%s-%d" % (tag, ppem) for w in want):
                continue
            one(tag, fontfile, weight, ppem)


if __name__ == "__main__":
    main()
