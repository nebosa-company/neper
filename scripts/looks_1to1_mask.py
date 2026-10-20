"""Side by side crop of reference, ours and the difference mask: `python -I scripts/looks_1to1_mask.py <sheet> x0,y0,x1,y1 out.png [scale] [--ref windows-1to1]`
(coordinates in the reference sheet; ours is placed like looks_1to1_eval does). Red = more than 2 levels off."""
import os
import sys
import numpy as np
import cv2
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks_cells as lc  # noqa: E402
import looks_strict as ls  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith("--")]
ref_set = "windows-1to1"
if "--ref" in sys.argv:
    ref_set = sys.argv[sys.argv.index("--ref") + 1]
    args = [a for a in args if a != ref_set]
os.environ["LOOKS_REF"] = ref_set
sheet = args[0]
x0, y0, x1, y1 = [int(v) for v in args[1].split(",")]
scale = int(args[3]) if len(args) > 3 else 2
ref = np.array(Image.open(lc.refpath(sheet)).convert("RGB"))
ours = np.array(Image.open(os.environ.get("LOOKS_OURS", lc.ROOT + "windows") + "/%s.png" % sheet).convert("RGB"))
if ref.shape == ours.shape:
    o = ours
else:
    _, dx, dy = ls.place(ref, ours)
    o = ours[dy:dy + ref.shape[0], dx:dx + ref.shape[1]]
a = ref[y0:y1, x0:x1]
b = o[y0:y1, x0:x1]
d = np.abs(a.astype(int) - b.astype(int)).max(axis=2) > 2
m = np.where(d[..., None], np.array([255, 0, 0]), (b // 3 + 170)).astype(np.uint8)
im = np.vstack([a, b, m])[:, :, ::-1]
cv2.imwrite(args[2], cv2.resize(np.ascontiguousarray(im), None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST))
print(int(d.sum()), "px off in the box")
