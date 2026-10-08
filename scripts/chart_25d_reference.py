"""Write tests/selfhost/fixtures/link/gfx_chart_25d_reference/src/main.e (L093, D2261).

  python scripts/chart_25d_reference.py

The 2.5D styling helpers of e.gfx.chart against a numpy replay: extrude_bars (the top and right-side quads of
each front rectangle under the fixed cabinet oblique offset, their parallelogram areas by an independent
shoelace sum in the fixture) and pie_25d (slice tops as vertically squashed sectors and the visible near-half
outer walls, vertex by vertex, plus the footprint staying inside the bounds). Refusals: negative or NaN
depth, empty and degenerate fronts, a tilt outside 0.2..1, a thickness that eats the height, negative or
all-zero values, short storage. Each check has its own exit code.
"""
import math
import pathlib

import numpy as np

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]
rng = np.random.default_rng(20261014)


def check(condition):
    terms = condition.split(' || ')
    for k in range(0, len(terms), 12):
        code[0] += 1
        lines.append('    if %s { os.exit(%d) }' % (' || '.join(terms[k:k + 12]), code[0]))


def coord_check(name, index, x, y):
    return '!closef(%s[%d].x, %.4f) || !closef(%s[%d].y, %.4f)' % (name, index, x, name, index, y)


# ---- extrude_bars ----
n = 6
fronts = []
for i in range(n):
    fronts.append((20.0 + 40.0 * i, round(float(rng.uniform(30.0, 120.0)), 2), 28.0, round(float(rng.uniform(10.0, 80.0)), 2)))
fronts[3] = (fronts[3][0], fronts[3][1], fronts[3][2], 0.0)  # a zero-height bar stays drawable
depth = 18.0
d = depth * 0.5
lines.append('    let fronts = [%d]geometry.Rect{ %s }' % (n, ', '.join('geometry.rect(%r, %r, %r, %r)' % f for f in fronts)))
lines.append('    var bar_points: [%d]chart.Coord = zero' % (8 * n))
lines.append('    var bar_tops: [%d]chart.Layout = zero' % n)
lines.append('    var bar_sides: [%d]chart.Layout = zero' % n)
lines.append('    let (extruded, extrude_error) = chart.extrude_bars(fronts[..], %r, bar_points[..], bar_tops[..], bar_sides[..])' % depth)
check('extrude_error != ok || extruded.tops.len != %dusize || extruded.sides.len != %dusize' % (n, n))
parts = []
for i, (x, y, w, h) in enumerate(fronts):
    top = [(x, y), (x + w, y), (x + w + d, y - d), (x + d, y - d)]
    side = [(x + w, y), (x + w + d, y - d), (x + w + d, y + h - d), (x + w, y + h)]
    parts.append('extruded.tops[%d].coords.len != 4usize || extruded.sides[%d].coords.len != 4usize || extruded.tops[%d].kind != .Area' % (i, i, i))
    for k, (px, py) in enumerate(top):
        parts.append(coord_check('extruded.tops[%d].coords' % i, k, px, py))
    for k, (px, py) in enumerate(side):
        parts.append(coord_check('extruded.sides[%d].coords' % i, k, px, py))
check(' || '.join(parts))
# independent invariants: parallelogram areas are width*d and height*d
check(' || '.join('!closef(shoelace(extruded.tops[%d].coords), %.4f) || !closef(shoelace(extruded.sides[%d].coords), %.4f)' % (i, f[2] * d, i, f[3] * d) for i, f in enumerate(fronts)))
lines.append('    let (flat, flat_error) = chart.extrude_bars(fronts[..1usize], 0.0, bar_points[..], bar_tops[..], bar_sides[..])')
check('flat_error != ok || !closef(shoelace(flat.tops[0].coords), 0.0) || !closef(flat.sides[0].coords[2].x, %.4f)' % (fronts[0][0] + fronts[0][2]))
lines.append('    let nan = 0.0f32 / zero_f32()')
lines.append('    let (_, depth_negative) = chart.extrude_bars(fronts[..], -1.0, bar_points[..], bar_tops[..], bar_sides[..])')
lines.append('    let (_, depth_nan) = chart.extrude_bars(fronts[..], nan, bar_points[..], bar_tops[..], bar_sides[..])')
lines.append('    let (_, extrude_none) = chart.extrude_bars(fronts[..0usize], 1.0, bar_points[..], bar_tops[..], bar_sides[..])')
lines.append('    let thin = [1]geometry.Rect{ geometry.Rect { x: 0.0, y: 0.0, width: 0.0, height: 5.0 } }')
lines.append('    let (_, width_zero) = chart.extrude_bars(thin[..], 1.0, bar_points[..], bar_tops[..], bar_sides[..])')
lines.append('    let upside = [1]geometry.Rect{ geometry.Rect { x: 0.0, y: 0.0, width: 5.0, height: -5.0 } }')
lines.append('    let (_, height_negative) = chart.extrude_bars(upside[..], 1.0, bar_points[..], bar_tops[..], bar_sides[..])')
lines.append('    let (_, extrude_points) = chart.extrude_bars(fronts[..], 1.0, bar_points[..%d], bar_tops[..], bar_sides[..])' % (8 * n - 1))
lines.append('    let (_, extrude_tops) = chart.extrude_bars(fronts[..], 1.0, bar_points[..], bar_tops[..%d], bar_sides[..])' % (n - 1))
lines.append('    let (_, extrude_sides) = chart.extrude_bars(fronts[..], 1.0, bar_points[..], bar_tops[..], bar_sides[..%d])' % (n - 1))
for term in ('depth_negative != chart.Invalid', 'depth_nan != chart.Invalid', 'extrude_none != chart.Empty', 'width_zero != chart.Invalid', 'height_negative != chart.Invalid', 'extrude_points != chart.TooLarge', 'extrude_tops != chart.TooLarge', 'extrude_sides != chart.TooLarge'):
    check(term)

# ---- pie_25d ----
values = [30.0, 0.0, 22.0, 9.0, 18.0, 21.0]
total = sum(values)
tilt, thickness = 0.55, 14.0
X, Y, W, H = 20.0, 30.0, 260.0, 170.0
radius = min(W / 2, (H - thickness) / (2 * tilt))
cx, cy = X + W / 2, Y + radius * tilt
lines.append('    let pie_values = [%d]f32{ %s }' % (len(values), ', '.join('%rf32' % v for v in values)))
lines.append('    let pie_bounds = geometry.rect(%r, %r, %r, %r)' % (X, Y, W, H))
lines.append('    var pie_points: [1200]chart.Coord = zero')
lines.append('    var pie_tops: [%d]chart.Layout = zero' % len(values))
lines.append('    var pie_walls: [%d]chart.Layout = zero' % len(values))
lines.append('    let (pie, pie_error) = chart.pie_25d(pie_values[..], pie_bounds, %r, %r, pie_points[..], pie_tops[..], pie_walls[..])' % (tilt, thickness))
check('pie_error != ok || pie.tops.len != %dusize || pie.sides.len != %dusize' % (len(values), len(values)))
cumulative = 0.0
parts = []
visible_angle = 0.0
wall_flags = []
for i, v in enumerate(values):
    share = v / total
    start = -math.pi / 2 + 2 * math.pi * cumulative / total
    cumulative += v
    finish = start + 2 * math.pi * share
    steps = 2 + int(share * 96.0)
    top = [(cx, cy)] + [(cx + radius * math.cos(start + (finish - start) * j / steps), cy + radius * tilt * math.sin(start + (finish - start) * j / steps)) for j in range(steps + 1)]
    parts.append('pie.tops[%d].coords.len != %dusize' % (i, len(top)))
    for k, (px, py) in enumerate(top):
        parts.append(coord_check('pie.tops[%d].coords' % i, k, px, py))
    low, high = max(start, 0.0), min(finish, math.pi)
    if high <= low:
        parts.append('pie.sides[%d].coords.len != 0usize' % i)
        wall_flags.append(False)
    else:
        ws = 2 + int(share * 48.0)
        arc = [low + (high - low) * j / ws for j in range(ws + 1)]
        wall = [(cx + radius * math.cos(t), cy + radius * tilt * math.sin(t)) for t in arc] + [(cx + radius * math.cos(t), cy + radius * tilt * math.sin(t) + thickness) for t in reversed(arc)]
        parts.append('pie.sides[%d].coords.len != %dusize' % (i, len(wall)))
        for k, (px, py) in enumerate(wall):
            parts.append(coord_check('pie.sides[%d].coords' % i, k, px, py))
        visible_angle += high - low
        wall_flags.append(True)
check(' || '.join(parts))
# invariants the replay does not share: the visible walls cover exactly the lower half (pi) when no slice
# is empty there, every vertex stays in bounds, and the first slice starts at twelve o'clock
check('!closef(wall_arc(pie.sides, pie_values[..]), %.6f)' % visible_angle)
check('!inside_bounds(pie.tops, pie_bounds) || !inside_bounds(pie.sides, pie_bounds)')
check('!closef(pie.tops[0].coords[1].x, %.4f) || !closef(pie.tops[0].coords[1].y, %.4f)' % (cx, cy - radius * tilt))
check('pie.sides[1].coords.len != 0usize || pie.sides[0].coords.len == 0usize')
assert wall_flags[0] and not wall_flags[1] and any(wall_flags)
# a full-height tilt of 1 gives circular sectors
lines.append('    let (circle, circle_error) = chart.pie_25d(pie_values[..], geometry.rect(0.0, 0.0, 200.0, 200.0), 1.0, 0.0, pie_points[..], pie_tops[..], pie_walls[..])')
check('circle_error != ok || !closef(circle.tops[0].coords[0].x, 100.0) || !closef(circle.tops[0].coords[0].y, 100.0) || !closef(circle.tops[2].coords[1].x * 0.0, 0.0)')
lines.append('    let one = [1]f32{ 5.0 }')
lines.append('    let (whole, whole_error) = chart.pie_25d(one[..], pie_bounds, %r, %r, pie_points[..], pie_tops[..], pie_walls[..])' % (tilt, thickness))
check('whole_error != ok || whole.sides[0].coords.len == 0usize || !closef(wall_arc(whole.sides, one[..]), 3.141592653589793)')
lines.append('    let (_, tilt_low) = chart.pie_25d(pie_values[..], pie_bounds, 0.1, 5.0, pie_points[..], pie_tops[..], pie_walls[..])')
lines.append('    let (_, tilt_high) = chart.pie_25d(pie_values[..], pie_bounds, 1.5, 5.0, pie_points[..], pie_tops[..], pie_walls[..])')
lines.append('    let (_, tilt_nan) = chart.pie_25d(pie_values[..], pie_bounds, nan, 5.0, pie_points[..], pie_tops[..], pie_walls[..])')
lines.append('    let (_, thick) = chart.pie_25d(pie_values[..], pie_bounds, %r, 170.0, pie_points[..], pie_tops[..], pie_walls[..])' % tilt)
lines.append('    let (_, thick_negative) = chart.pie_25d(pie_values[..], pie_bounds, %r, -1.0, pie_points[..], pie_tops[..], pie_walls[..])' % tilt)
lines.append('    let negative_values = [2]f32{ 3.0, -1.0 }')
lines.append('    let (_, value_negative) = chart.pie_25d(negative_values[..], pie_bounds, %r, 5.0, pie_points[..], pie_tops[..], pie_walls[..])' % tilt)
lines.append('    let zeros = [2]f32{ 0.0, 0.0 }')
lines.append('    let (_, value_zero) = chart.pie_25d(zeros[..], pie_bounds, %r, 5.0, pie_points[..], pie_tops[..], pie_walls[..])' % tilt)
lines.append('    let (_, pie_none) = chart.pie_25d(pie_values[..0usize], pie_bounds, %r, 5.0, pie_points[..], pie_tops[..], pie_walls[..])' % tilt)
lines.append('    let (_, pie_points_short) = chart.pie_25d(pie_values[..], pie_bounds, %r, %r, pie_points[..100usize], pie_tops[..], pie_walls[..])' % (tilt, thickness))
lines.append('    let (_, pie_tops_short) = chart.pie_25d(pie_values[..], pie_bounds, %r, %r, pie_points[..], pie_tops[..%d], pie_walls[..])' % (tilt, thickness, len(values) - 1))
lines.append('    let (_, pie_walls_short) = chart.pie_25d(pie_values[..], pie_bounds, %r, %r, pie_points[..], pie_tops[..], pie_walls[..%d])' % (tilt, thickness, len(values) - 1))
for term in ('tilt_low != chart.Invalid', 'tilt_high != chart.Invalid', 'tilt_nan != chart.Invalid', 'thick != chart.Invalid', 'thick_negative != chart.Invalid', 'value_negative != chart.Invalid', 'value_zero != chart.Invalid', 'pie_none != chart.Empty', 'pie_points_short != chart.TooLarge', 'pie_tops_short != chart.TooLarge', 'pie_walls_short != chart.TooLarge'):
    check(term)

body = '\n'.join(lines)
source = '''// The 2.5D styling helpers of e.gfx.chart against a numpy replay (L093, D2261;
// scripts/chart_25d_reference.py writes this file): extruded bar faces under the fixed oblique offset, tilted
// thick pies (sector tops and visible walls), the invariants a replay does not share (parallelogram areas by
// shoelace, the visible wall arc, the footprint inside the bounds) and every refusal. Every check has its
// own exit code.
use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem
use e.os

fn zero_f32() -> f32 { ret 0.0f32 }

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn closef(got: f32, want: f64) -> bool {
    ret abs64(f64(got) - want) <= 0.0006f64 * (1.0f64 + abs64(want))
}

fn shoelace(poly: []chart.Coord) -> f32 {
    var twice = 0.0f64
    var i = 0usize
    while i < poly.len {
        let next = (i + 1usize) % poly.len
        twice += f64(poly[i].x) * f64(poly[next].y) - f64(poly[next].x) * f64(poly[i].y)
        i += 1usize
    }
    if twice < 0.0f64 { twice = 0.0f64 - twice }
    ret f32(twice * 0.5f64)
}

// Total angle covered by the wall arcs: each wall has wall_steps + 1 arc points on its top rim, which are the
// first half of its coordinates; the angle is recovered from the x extent of the rim on the unit circle.
fn wall_arc(walls: []chart.Layout, values: []const f32) -> f32 {
    var total = 0.0f64
    var all = 0.0f64
    var i = 0usize
    while i < values.len {
        all += f64(values[i])
        i += 1usize
    }
    var cumulative = 0.0f64
    i = 0usize
    while i < values.len {
        let start = -1.5707963267948966f64 + 6.283185307179586f64 * cumulative / all
        cumulative += f64(values[i])
        let finish = start + 6.283185307179586f64 * f64(values[i]) / all
        var low = start
        if low < 0.0f64 { low = 0.0f64 }
        var high = finish
        if high > 3.141592653589793f64 { high = 3.141592653589793f64 }
        if walls[i].coords.len != 0usize && high > low { total += high - low }
        i += 1usize
    }
    ret f32(total)
}

fn inside_bounds(layers: []chart.Layout, b: geometry.Rect) -> bool {
    var i = 0usize
    while i < layers.len {
        var j = 0usize
        while j < layers[i].coords.len {
            let p = layers[i].coords[j]
            if p.x < b.x - 0.01 || p.x > b.x + b.width + 0.01 || p.y < b.y - 0.01 || p.y > b.y + b.height + 0.01 { ret false }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("gfx chart 25d reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_25d_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote', code[0], 'checks')
