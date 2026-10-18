"""Writes lib/e/ui/matglyph.e: the Material icons the Android look draws (outlines, filled), from SVG paths.
  python -I scripts/material/gen_glyphs.py        (from the repository root)
ICONS below are the Material Icons paths of scripts/material/gallery.html (the references) and the Material Symbols paths
Material Web itself draws in its chips (md-input-chip's remove icon, md-filter-chip's check)."""
import math
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# name: (viewBox x, y, size, path)
ICONS = {
    "notif": (0, 0, 24, "M12 22c1.1 0 2-.9 2-2h-4c0 1.1.89 2 2 2zm6-6v-5c0-3.07-1.64-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.63 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z"),
    "add": (0, 0, 24, "M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"),
    "close": (0, 0, 24, "M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"),
    "close_thin": (0, 96, 960, "m249 849-42-42 231-231-231-231 42-42 231 231 231-231 42 42-231 231 231 231-42 42-231-231-231 231Z"),
    "check_chip": (0, 0, 18, "M6.75012 12.1274L3.62262 8.99988L2.55762 10.0574L6.75012 14.2499L15.7501 5.24988L14.6926 4.19238L6.75012 12.1274Z"),
    "search": (0, 0, 24, "M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"),
    "menu": (0, 0, 24, "M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z"),
    "more": (0, 0, 24, "M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"),
    "edit": (0, 0, 24, "M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34a.9959.9959 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"),
    "down": (0, 0, 24, "M7 10l5 5 5-5z"),
    "up": (0, 0, 24, "M7 14l5-5 5 5z"),
    "prev": (0, 0, 24, "M15.41 7.41L14 6l-6 6 6 6 1.41-1.41L10.83 12z"),
    "next": (0, 0, 24, "M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"),
    "settings": (0, 0, 24, "M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"),
    "person": (0, 0, 24, "M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"),
}


def tokens(d):
    return re.findall(r"[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?", d)


def arc_to_cubics(x1, y1, rx, ry, phi, fa, fs, x2, y2):
    if rx == 0 or ry == 0:
        return [((x1, y1), (x2, y2), (x2, y2))]
    phi = math.radians(phi)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    rx, ry = abs(rx), abs(ry)
    lam = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    co = math.sqrt(max(0, num / den)) * (-1 if fa == fs else 1)
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx, cy = cp * cxp - sp * cyp + (x1 + x2) / 2, sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a
    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not fs and dt > 0:
        dt -= 2 * math.pi
    if fs and dt < 0:
        dt += 2 * math.pi
    n = max(1, int(math.ceil(abs(dt) / (math.pi / 2) - 1e-9)))
    out = []
    step = dt / n
    k = 4 / 3 * math.tan(step / 4)
    for i in range(n):
        a1, a2 = t1 + i * step, t1 + (i + 1) * step
        def pt(a, ddx=0, ddy=0):
            x, y = rx * math.cos(a), ry * math.sin(a)
            return (cp * x - sp * y + cx, sp * x + cp * y + cy)
        def dv(a):
            x, y = -rx * math.sin(a), ry * math.cos(a)
            return (cp * x - sp * y, sp * x + cp * y)
        p1, p2 = pt(a1), pt(a2)
        d1, d2 = dv(a1), dv(a2)
        out.append(((p1[0] + k * d1[0], p1[1] + k * d1[1]), (p2[0] - k * d2[0], p2[1] - k * d2[1]), p2))
    return out


def parse(d):
    t = tokens(d)
    i = 0
    cmd = None
    x = y = sx = sy = 0.0
    lastc = None
    ops = []

    def num():
        nonlocal i
        v = float(t[i]); i += 1; return v
    while i < len(t):
        if re.match(r"[A-Za-z]", t[i]):
            cmd = t[i]; i += 1
            if cmd in "Zz":
                ops.append(("Z",)); x, y = sx, sy; lastc = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            nx, ny = num(), num()
            if rel: nx, ny = x + nx, y + ny
            x, y = nx, ny; sx, sy = x, y
            ops.append(("M", x, y)); cmd = "l" if rel else "L"; lastc = None
        elif c == "L":
            nx, ny = num(), num()
            if rel: nx, ny = x + nx, y + ny
            x, y = nx, ny; ops.append(("L", x, y)); lastc = None
        elif c == "H":
            nx = num(); x = x + nx if rel else nx; ops.append(("L", x, y)); lastc = None
        elif c == "V":
            ny = num(); y = y + ny if rel else ny; ops.append(("L", x, y)); lastc = None
        elif c in "CS":
            if c == "C":
                a = [num() for _ in range(6)]
                if rel: a = [a[0] + x, a[1] + y, a[2] + x, a[3] + y, a[4] + x, a[5] + y]
                p1 = (a[0], a[1]); p2 = (a[2], a[3]); p3 = (a[4], a[5])
            else:
                a = [num() for _ in range(4)]
                if rel: a = [a[0] + x, a[1] + y, a[2] + x, a[3] + y]
                p1 = (2 * x - lastc[0], 2 * y - lastc[1]) if lastc else (x, y)
                p2 = (a[0], a[1]); p3 = (a[2], a[3])
            ops.append(("C", *p1, *p2, *p3)); lastc = p2; x, y = p3
        elif c == "A":
            rx, ry, phi, fa, fs, nx, ny = num(), num(), num(), int(num()), int(num()), num(), num()
            if rel: nx, ny = x + nx, y + ny
            for p1, p2, p3 in arc_to_cubics(x, y, rx, ry, phi, fa, fs, nx, ny):
                ops.append(("C", *p1, *p2, *p3))
            x, y = nx, ny; lastc = None
        else:
            raise SystemExit("unsupported " + c)
    return ops


def f(v):
    s = "%.5f" % v
    s = s.rstrip("0")
    if s.endswith("."): s += "0"
    return s


lines = ["// Generated by scripts/material/gen_glyphs.py: the Material icons of the Android look as filled outlines (do not edit).",
         "// Each function appends one icon's path to `b` in the box x, y, w, h.", "",
         "use e.gfx.geometry", ""]
for name, (vx, vy, vs, path) in ICONS.items():
    ops = parse(path)
    def X(v): return "x + w * %s" % f((v - vx) / vs)
    def Y(v): return "y + h * %s" % f((v - vy) / vs)
    lines.append("fn mat_%s(b: *geometry.PathBuilder, x: f32, y: f32, w: f32, h: f32) -> err {" % name)
    for o in ops:
        if o[0] == "M":
            lines.append("    try geometry.move_to(b, geometry.Point { x: %s, y: %s })" % (X(o[1]), Y(o[2])))
        elif o[0] == "L":
            lines.append("    try geometry.line_to(b, geometry.Point { x: %s, y: %s })" % (X(o[1]), Y(o[2])))
        elif o[0] == "C":
            lines.append("    try geometry.cubic_to(b, geometry.Point { x: %s, y: %s }, geometry.Point { x: %s, y: %s }, geometry.Point { x: %s, y: %s })" % (X(o[1]), Y(o[2]), X(o[3]), Y(o[4]), X(o[5]), Y(o[6])))
        else:
            lines.append("    try geometry.close_path(b)")
    lines.append("    ret ok")
    lines.append("}")
    lines.append("")
open(os.path.join(ROOT, "lib/e/ui/matglyph.e"), "w", newline="\n").write("\n".join(lines))
print(len(ICONS), "icons")
