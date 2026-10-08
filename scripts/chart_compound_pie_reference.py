"""Write tests/selfhost/fixtures/link/gfx_chart_compound_pie_reference/src/main.e (L094, D2262).

  python scripts/chart_compound_pie_reference.py

Pie-of-pie and bar-of-pie of e.gfx.chart against a numpy replay: every sector vertex of the main pie (the
tail folded into one Other slice turned to face the breakout) and of the breakout pie, the stacked breakout
bar, the two connectors, and the invariants a replay does not share: polygon areas against the analytic
chord-sector area and proportional to the values, the Other total equal to the breakout's own total, the
breakout bar contiguous top to bottom, and small_tail_count's contiguous tail. Refusals: tail outside 2..n-1,
negative values, an all-zero tail, short storage, bad bounds, bad shares. Each check has its own exit code.
"""
import math
import pathlib

import numpy as np

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]


def check(condition):
    terms = condition.split(' || ')
    for k in range(0, len(terms), 12):
        code[0] += 1
        lines.append('    if %s { os.exit(%d) }' % (' || '.join(terms[k:k + 12]), code[0]))


def coord_check(name, index, x, y):
    return '!closef(%s[%d].x, %.4f) || !closef(%s[%d].y, %.4f)' % (name, index, x, name, index, y)


values = [27.0, 21.0, 17.0, 12.0, 9.0, 6.5, 4.5, 3.0]
n = len(values)
tail = 3
X, Y, W, H = 10.0, 30.0, 340.0, 170.0
total = sum(values)
other = sum(values[-tail:])
f = other / total
turn = math.pi * f
r1 = min(W * 0.25, H / 2)
r2 = r1 * 0.7
cy = Y + H / 2
c1 = X + r1
c2 = X + W - r2


def sector(cx, cy_, r, start, finish, share):
    steps = 2 + int(share * 96.0)
    pts = [(cx, cy_)]
    for j in range(steps + 1):
        a = start + (finish - start) * j / steps
        pts.append((cx + r * math.cos(a), cy_ + r * math.sin(a)))
    return pts, steps


def chord_area(r, start, finish, steps):
    # polygon centre + arc points: sum of `steps` triangles of area r^2 sin(d/steps) / 2
    return 0.5 * r * r * steps * math.sin((finish - start) / steps)


lines.append('    let values = [%d]f32{ %s }' % (n, ', '.join('%rf32' % v for v in values)))
lines.append('    let bounds = geometry.rect(%r, %r, %r, %r)' % (X, Y, W, H))
lines.append('    var points: [2000]chart.Coord = zero')
lines.append('    var main_layers: [%d]chart.Layout = zero' % n)
lines.append('    var breakout: [%d]chart.Layout = zero' % n)
lines.append('    var bars: [%d]geometry.Rect = zero' % n)
lines.append('    var links: [2]chart.Segment = zero')

main_values = values[:-tail] + [other]
mains = []
cum = 0.0
for v in main_values:
    start = turn + 2 * math.pi * cum / total
    cum += v
    finish = start + 2 * math.pi * v / total
    mains.append((sector(c1, cy, r1, start, finish, v / total), start, finish, v))

# ---- pie-of-pie ----
lines.append('    let (pie_pie, pie_pie_error) = chart.compound_pie(values[..], %dusize, .Pie, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..])' % tail)
check('pie_pie_error != ok || pie_pie.main.len != %dusize || pie_pie.breakout.len != %dusize || pie_pie.bars.len != 0usize' % (len(main_values), tail))
check('!closed(pie_pie.other_total, %r) || !closed(pie_pie.main_total, %r)' % (other, total - other))
parts = []
for i, ((pts, steps), start, finish, v) in enumerate(mains):
    parts.append('pie_pie.main[%d].coords.len != %dusize || pie_pie.main[%d].kind != .Area' % (i, len(pts), i))
    for k, (px, py) in enumerate(pts):
        parts.append(coord_check('pie_pie.main[%d].coords' % i, k, px, py))
check(' || '.join(parts))
# areas: analytic chord-sector area, and proportional to the value
parts = []
areas = [chord_area(r1, s, fi, st) for (pts, st), s, fi, v in mains]
for i, ((pts, st), s, fi, v) in enumerate(mains):
    parts.append('!closef(shoelace(pie_pie.main[%d].coords), %.4f)' % (i, areas[i]))
    parts.append('!closef(shoelace(pie_pie.main[%d].coords) / area_sum(pie_pie.main), %.6f)' % (i, v / total))
check(' || '.join(parts))
# the Other slice faces the breakout: its two radii sit symmetrically about the +x axis
check('!closef(pie_pie.main[%d].coords[1].y - %r, %r) || !closef(%r - pie_pie.main[%d].coords[pie_pie.main[%d].coords.len - 1].y, %r)' % (len(main_values) - 1, cy, -r1 * math.sin(turn), cy, len(main_values) - 1, len(main_values) - 1, -r1 * math.sin(turn)))
# breakout pie
bpts = []
cum = 0.0
for i in range(tail):
    v = values[n - tail + i]
    start = -0.5 * math.pi + 2 * math.pi * cum / other
    cum += v
    finish = start + 2 * math.pi * v / other
    bpts.append((sector(c2, cy, r2, start, finish, v / other), start, finish, v))
parts = []
for i, ((pts, st), s, fi, v) in enumerate(bpts):
    parts.append('pie_pie.breakout[%d].coords.len != %dusize' % (i, len(pts)))
    for k, (px, py) in enumerate(pts):
        parts.append(coord_check('pie_pie.breakout[%d].coords' % i, k, px, py))
    parts.append('!closef(shoelace(pie_pie.breakout[%d].coords) / area_sum(pie_pie.breakout), %.6f)' % (i, v / other))
check(' || '.join(parts))
top = (c2, cy - r2)
bottom = (c2, cy + r2)
check('!closef(links[0].from.x, %.4f) || !closef(links[0].from.y, %.4f) || !closef(links[0].to.x, %.4f) || !closef(links[0].to.y, %.4f)' % (c1 + r1 * math.cos(-turn), cy + r1 * math.sin(-turn), top[0], top[1]))
check('!closef(links[1].from.x, %.4f) || !closef(links[1].from.y, %.4f) || !closef(links[1].to.x, %.4f) || !closef(links[1].to.y, %.4f)' % (c1 + r1 * math.cos(turn), cy + r1 * math.sin(turn), bottom[0], bottom[1]))
check('!same(links[0].from.x, links[1].from.x) || !same(links[0].from.y - %rf32, %rf32 - links[1].from.y)' % (cy, cy))
check('pie_pie.connectors.segments.len != 2usize')
# the breakout is smaller than the main pie and to its right
check('breakout_left(pie_pie.breakout) < main_right(pie_pie.main)')

# ---- bar-of-pie ----
lines.append('    let (bar_pie, bar_pie_error) = chart.compound_pie(values[..], %dusize, .Bar, bounds, points[..], main_layers[..], breakout[..], bars[..], links[..])' % tail)
check('bar_pie_error != ok || bar_pie.main.len != %dusize || bar_pie.bars.len != %dusize || bar_pie.breakout.len != 0usize' % (len(main_values), tail))
bar_w = r2 * 0.9
left = c2 - bar_w / 2
parts = []
cum = 0.0
for i in range(tail):
    v = values[n - tail + i]
    y0 = cy - r2 + 2 * r2 * cum / other
    cum += v
    y1 = cy - r2 + 2 * r2 * cum / other
    parts.append('!closef(bar_pie.bars[%d].x, %.4f) || !closef(bar_pie.bars[%d].width, %.4f) || !closef(bar_pie.bars[%d].y, %.4f) || !closef(bar_pie.bars[%d].height, %.4f)' % (i, left, i, bar_w, i, y0, i, y1 - y0))
check(' || '.join(parts))
check(' || '.join('!same(bar_pie.bars[%d].y + bar_pie.bars[%d].height, bar_pie.bars[%d].y)' % (i, i, i + 1) for i in range(tail - 1)) + ' || !closef(bar_pie.bars[0].y, %.4f) || !closef(bar_pie.bars[%d].y + bar_pie.bars[%d].height, %.4f)' % (cy - r2, tail - 1, tail - 1, cy + r2))
check('!closef(links[0].to.x, %.4f) || !closef(links[0].to.y, %.4f) || !closef(links[1].to.x, %.4f) || !closef(links[1].to.y, %.4f)' % (left, cy - r2, left, cy + r2))
check('!closed(bar_pie.other_total, %r)' % other)
# the main pie is the same in both modes
check(' || '.join('!same(bar_pie.main[%d].coords[%d].x, pie_pie.main[%d].coords[%d].x)' % (i, 1, i, 1) for i in range(len(main_values))))

# ---- small_tail_count ----
small = [30.0, 25.0, 20.0, 10.0, 6.0, 5.0, 4.0]
lines.append('    let small = [%d]f32{ %s }' % (len(small), ', '.join('%rf32' % v for v in small)))
lines.append('    let (small_three, small_error) = chart.small_tail_count(small[..], 0.07)')
lines.append('    let (small_all, small_all_error) = chart.small_tail_count(small[..], 0.5)')
lines.append('    let (small_none, small_none_error) = chart.small_tail_count(small[..], 0.04)')
lines.append('    let gap = [5]f32{ 40.0, 2.0, 30.0, 3.0, 25.0 }')
lines.append('    let (small_gap, small_gap_error) = chart.small_tail_count(gap[..], 0.05)')
check('small_error != ok || small_three != 3usize || small_all_error != ok || small_all != 7usize || small_none_error != ok || small_none != 0usize || small_gap_error != ok || small_gap != 0usize')
lines.append('    let gap_tail = [5]f32{ 40.0, 2.0, 30.0, 25.0, 3.0 }')
lines.append('    let (small_tail, small_tail_error) = chart.small_tail_count(gap_tail[..], 0.05)')
check('small_tail_error != ok || small_tail != 1usize')
lines.append('    let nan = 0.0f32 / zero_f32()')
lines.append('    let (_, share_zero) = chart.small_tail_count(small[..], 0.0)')
lines.append('    let (_, share_big) = chart.small_tail_count(small[..], 1.5)')
lines.append('    let (_, share_nan) = chart.small_tail_count(small[..], nan)')
lines.append('    let (_, small_empty) = chart.small_tail_count(small[..0usize], 0.1)')
lines.append('    let negative = [2]f32{ 3.0, -1.0 }')
lines.append('    let (_, small_negative) = chart.small_tail_count(negative[..], 0.1)')
lines.append('    let zeros = [2]f32{ 0.0, 0.0 }')
lines.append('    let (_, small_zero) = chart.small_tail_count(zeros[..], 0.1)')
for term in ('share_zero != chart.Invalid', 'share_big != chart.Invalid', 'share_nan != chart.Invalid', 'small_empty != chart.Empty', 'small_negative != chart.Invalid', 'small_zero != chart.Invalid'):
    check(term)

# ---- refusals ----
def compound(label, vals, tail_, kind, b='bounds', m='main_layers[..]', br='breakout[..]', ba='bars[..]', lk='links[..]', pt='points[..]'):
    lines.append('    let (_, %s) = chart.compound_pie(%s, %s, .%s, %s, %s, %s, %s, %s, %s)' % (label, vals, tail_, kind, b, pt, m, br, ba, lk))


compound('tail_one', 'values[..]', '1usize', 'Pie')
compound('tail_zero', 'values[..]', '0usize', 'Pie')
compound('tail_all', 'values[..]', '%dusize' % n, 'Pie')
compound('compound_none', 'values[..0usize]', '3usize', 'Pie')
compound('compound_bounds', 'values[..]', '3usize', 'Pie', b='geometry.Rect { x: 0.0, y: 0.0, width: 0.0, height: 10.0 }')
lines.append('    let cn = [4]f32{ 5.0, 4.0, -1.0, 2.0 }')
compound('compound_negative', 'cn[..]', '2usize', 'Pie')
lines.append('    let tail_zeros = [4]f32{ 5.0, 4.0, 0.0, 0.0 }')
compound('compound_zero_tail', 'tail_zeros[..]', '2usize', 'Pie')
compound('main_short', 'values[..]', '3usize', 'Pie', m='main_layers[..5usize]')
compound('breakout_short', 'values[..]', '3usize', 'Pie', br='breakout[..2usize]')
compound('bars_short', 'values[..]', '3usize', 'Bar', ba='bars[..2usize]')
compound('links_short', 'values[..]', '3usize', 'Pie', lk='links[..1usize]')
compound('points_short', 'values[..]', '3usize', 'Pie', pt='points[..100usize]')
check('tail_one != chart.Invalid || tail_zero != chart.Invalid || tail_all != chart.Invalid || compound_none != chart.Empty || compound_bounds != chart.Invalid || compound_negative != chart.Invalid || compound_zero_tail != chart.Invalid')
check('main_short != chart.TooLarge || breakout_short != chart.TooLarge || bars_short != chart.TooLarge || links_short != chart.TooLarge || points_short != chart.TooLarge')

body = '\n'.join(lines)
source = '''// Pie-of-pie and bar-of-pie of e.gfx.chart against a numpy replay (L094, D2262;
// scripts/chart_compound_pie_reference.py writes this file): the main pie with its tail folded into one Other
// slice facing the breakout, the breakout pie or stacked bar, the connectors, polygon areas against the
// analytic chord-sector area and proportional to the values, small_tail_count, and every refusal. Every check
// has its own exit code.
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

fn same(a: f32, b: f32) -> bool { ret abs64(f64(a) - f64(b)) <= 0.0006f64 }

fn closed(got: f64, want: f64) -> bool { ret abs64(got - want) <= 1e-9f64 * (1.0f64 + abs64(want)) }

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

fn area_sum(layers: []chart.Layout) -> f32 {
    var total = 0.0f32
    var i = 0usize
    while i < layers.len {
        total += shoelace(layers[i].coords)
        i += 1usize
    }
    ret total
}

fn breakout_left(layers: []chart.Layout) -> f32 {
    var left = layers[0usize].coords[0usize].x
    var i = 0usize
    while i < layers.len {
        var j = 0usize
        while j < layers[i].coords.len {
            if layers[i].coords[j].x < left { left = layers[i].coords[j].x }
            j += 1usize
        }
        i += 1usize
    }
    ret left
}

fn main_right(layers: []chart.Layout) -> f32 {
    var right = layers[0usize].coords[0usize].x
    var i = 0usize
    while i < layers.len {
        var j = 0usize
        while j < layers[i].coords.len {
            if layers[i].coords[j].x > right { right = layers[i].coords[j].x }
            j += 1usize
        }
        i += 1usize
    }
    ret right
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("gfx chart compound pie reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_compound_pie_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote', code[0], 'checks')
