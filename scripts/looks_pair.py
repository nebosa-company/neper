"""usage: python -I looks_pair.py <sheet> <x0> <y0> <x1> <y1> <scale> [dir] -> D:/Temp/claude/looks11-g1/pair.png : ref over ours (and a diff strip)"""
import sys
import numpy as np
from PIL import Image
n = sys.argv[1]
x0, y0, x1, y1 = [int(v) for v in sys.argv[2:6]]
s = int(sys.argv[6])
d = sys.argv[7] if len(sys.argv) > 7 else "windows"
R = "D:/Temp/lanes/looks11-g1/docs/ui/looks/"
r = Image.open(R + "ref/windows/%s.png" % n).convert("RGB").crop((x0, y0, x1, y1))
o = Image.open(R + "%s/%s.png" % (d, n)).convert("RGB").crop((x0, y0, x1, y1))
df = np.abs(np.array(r).astype(int) - np.array(o).astype(int)).max(axis=2)
dm = Image.fromarray(np.where(df > 2, 255, 0).astype(np.uint8)).convert("RGB")
w, h = r.size
out = Image.new("RGB", (w * s, h * s * 3 + 8), (255, 0, 255))
for i, im in enumerate((r, o, dm)):
    out.paste(im.resize((w * s, h * s), Image.NEAREST), (0, i * (h * s + 4)))
out.save("D:/Temp/claude/looks11-g1/pair.png")
