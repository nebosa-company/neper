#!/usr/bin/env python3
"""Write tests/selfhost/fixtures/link/algo_magnetic/src/main.e: WMM2025 evaluated by e.algo.magnetic.field at a dozen
places and dates against pygeomag (NOAA's model), and e.algo.magnetic.heading against orientations built with
rotation matrices (a known yaw, pitch and roll, the field of a known place and gravity). Set NEPER_PYLIB to a
directory holding pygeomag and numpy."""
import math
import os
import sys
from pathlib import Path

sys.path.insert(0, os.environ.get("NEPER_PYLIB", "D:/Temp/claude/pylib"))
from pygeomag import GeoMag  # noqa: E402

geo = GeoMag(coefficients_file="wmm/WMM_2025.COF")

places = [
    (47.6, -122.3, 0.05, 2026.78), (59.9, 10.7, 0.02, 2027.5), (30.0, 31.2, 0.0, 2025.0), (-33.9, 151.2, 0.0, 2029.0),
    (64.1, -21.9, 0.0, 2026.0), (-0.2, -78.5, 2.8, 2028.25), (35.7, 139.7, 0.04, 2026.9), (-33.9, 18.4, 0.0, 2025.5),
    (19.1, 72.9, 0.0, 2027.0), (-22.9, -43.2, 0.0, 2029.9), (61.2, -149.9, 0.0, 2026.5), (-60.0, -60.0, 0.0, 2025.0),
    (0.0, 0.0, 0.0, 2027.0), (89.0, 45.0, 0.0, 2026.0),
]
lines = []
code = [0]
for lat, lon, alt, year in places:
    r = geo.calculate(glat=lat, glon=lon, alt=alt, time=year)
    code[0] += 1
    lines.append(
        '    if !close_field(%r, %r, %r, %r, %.6f, %.6f, %.3f, %.3f, %.3f, %.3f, %.3f) { os.exit(%d) }'
        % (lat, lon, alt, year, r.d, r.i, r.h, r.f, r.x, r.y, r.z, code[0]))


def matmul_vec(m, v):
    return [sum(m[i][j] * v[j] for j in range(3)) for i in range(3)]


def rotation(yaw, pitch, roll):
    y, p, r = map(math.radians, (yaw, pitch, roll))
    rz = [[math.cos(y), math.sin(y), 0], [-math.sin(y), math.cos(y), 0], [0, 0, 1]]
    ry = [[math.cos(p), 0, -math.sin(p)], [0, 1, 0], [math.sin(p), 0, math.cos(p)]]
    rx = [[1, 0, 0], [0, math.cos(r), math.sin(r)], [0, -math.sin(r), math.cos(r)]]
    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mul(rx, mul(ry, rz))


# A field with declination (east of north) 14 degrees, inclination 66, total 52000 nT.
total, incl, decl = 52000.0, 66.0, 14.0
h = total * math.cos(math.radians(incl))
field_ned = [h * math.cos(math.radians(decl)), h * math.sin(math.radians(decl)), total * math.sin(math.radians(incl))]
for yaw, pitch, roll in ((30, 0, 0), (200, 20, -15), (310, -35, 40), (0.5, 5, 5), (90, 60, 10), (181, -10, 80)):
    # Heading is the yaw relative to MAGNETIC north, so the declination is removed from the field first.
    mag_ned = [math.hypot(*field_ned[:2]), 0.0, field_ned[2]]
    body = rotation(yaw, pitch, roll)
    m = matmul_vec(body, mag_ned)
    g = matmul_vec(body, [0, 0, 9.81])
    code[0] += 1
    lines.append('    if !close_heading(%.4f, %.4f, %.4f, %.5f, %.5f, %.5f, %.4f) { os.exit(%d) }' % (m[0], m[1], m[2], g[0], g[1], g[2], yaw, code[0]))

# Hard-iron: a sphere of radius 40 around (12, -7, 3) sampled on a few directions.
pts = []
for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1), (0.6, 0.6, 0.5)):
    pts.append((12 + 40 * dx, -7 + 40 * dy, 3 + 40 * dz))
xs = ", ".join("%.3ff64" % p[0] for p in pts)
ys = ", ".join("%.3ff64" % p[1] for p in pts)
zs = ", ".join("%.3ff64" % p[2] for p in pts)
code[0] += 1
lines.append('    let hx: [%d]f64 = [%d]f64{ %s }\n    let hy: [%d]f64 = [%d]f64{ %s }\n    let hz: [%d]f64 = [%d]f64{ %s }\n'
             '    let (ox, oy, oz) = mag.calibrate_hard_iron(hx[0usize..%dusize], hy[0usize..%dusize], hz[0usize..%dusize], %dusize)\n'
             '    if !near(ox, 12.0f64, 0.001f64) || !near(oy, -7.0f64, 0.001f64) || !near(oz, 3.0f64, 0.001f64) { os.exit(%d) }'
             % (len(pts), len(pts), xs, len(pts), len(pts), ys, len(pts), len(pts), zs, len(pts), len(pts), len(pts), len(pts), code[0]))

head = '''// `e.algo.magnetic`: WMM2025 at fourteen places and dates against pygeomag (declination and inclination to a
// hundredth of a degree, intensities to 2 nT), and the tilt-compensated heading against orientations built from
// rotation matrices. Every check has its own exit code.
use e.os
use e.algo.magnetic as mag

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= tolerance
}

fn close_field(lat: f64, lon: f64, alt: f64, year: f64, d: f64, i: f64, h: f64, f: f64, x: f64, y: f64, z: f64) -> bool {
    let r = mag.field(lat, lon, alt, year)
    return_check(r, d, i, h, f, x, y, z)
}
'''
open(Path(__file__).with_name("gen_magnetic_head.e.txt"), "r", encoding="utf-8").close() if False else None
body = "\n".join(lines)
out = '''// `e.algo.magnetic`: WMM2025 at fourteen places and dates against pygeomag (declination and inclination to 0.02
// degrees, intensities to 3 nT), and the tilt-compensated heading against orientations built from rotation
// matrices. Every check has its own exit code.
use e.os
use e.algo.magnetic as mag

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= tolerance
}

fn close_field(lat: f64, lon: f64, alt: f64, year: f64, d: f64, i: f64, h: f64, f: f64, x: f64, y: f64, z: f64) -> bool {
    let r = mag.field(lat, lon, alt, year)
    ret near(r.declination, d, 0.02f64) && near(r.inclination, i, 0.02f64) && near(r.horizontal, h, 3.0f64) && near(r.total, f, 3.0f64) && near(r.north, x, 3.0f64) && near(r.east, y, 3.0f64) && near(r.down, z, 3.0f64)
}

// The heading is the yaw: compared on the circle.
fn close_heading(mx: f64, my: f64, mz: f64, ax: f64, ay: f64, az: f64, yaw: f64) -> bool {
    let got = mag.heading(mx, my, mz, ax, ay, az)
    var d = got - yaw
    while d > 180.0f64 { d = d - 360.0f64 }
    while d < 0.0f64 - 180.0f64 { d = d + 360.0f64 }
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.05f64
}

fn main(args: []str) -> err {
''' + body.replace('e.os', 'e.os') + '''
    ret ok
}
'''
# main takes the arena like the other fixtures.
out = out.replace("fn main(args: []str) -> err {", "fn main(a: *mem.Arena, args: []str) -> err {").replace("use e.os\n", "use e.os\nuse e.mem\n", 1)
dest = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/algo_magnetic/src/main.e"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(out, encoding="utf-8", newline="\n")
print(dest, code[0], "checks")
