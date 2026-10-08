"""Write tests/selfhost/fixtures/link/gfx_chart_composition_reference/src/main.e (L073, D2257).

  python scripts/chart_composition_reference.py

The mekko, two-set Euler, three-set Venn and word-cloud layouts of e.gfx.chart against independent
numpy/scipy computations: every mekko cell's area fraction is value/grand total with column widths from
the category marginals (zero cells and a zero-total category included); the Euler circles' areas follow the
set sizes and their centre distance reproduces the overlap through scipy's root finder on the lens-area
formula (subset, identical, disjoint and empty-set cases too); the Venn circles are equal with the
equilateral spacing and the seven anchors sit in exactly their memberships; the word cloud's sizes,
stable descending order, exclusions, containment and non-overlap match a Python replay. Each check has
its own exit code.
"""
import math
import pathlib

import numpy as np
from scipy import optimize

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]
rng = np.random.default_rng(20261010)


def check(condition):
    code[0] += 1
    lines.append('    if %s { os.exit(%d) }' % (condition, code[0]))


def num(v):
    return repr(float(v))


def f32(v):
    return num(v) + 'f32'


def f64(v):
    return num(v) + 'f64'


# ---- mekko ----
cats, series = 6, 4
values = np.round(rng.uniform(0.5, 9.0, (cats, series)), 2)
values[1, 2] = 0.0
values[3, :] = 0.0
values[4, 0] = 0.0
values[4, 3] = 0.0
flat = values.reshape(-1)
lines.append('    let mekko_values = [%d]f32{ %s }' % (len(flat), ', '.join(f32(v) for v in flat)))
lines.append('    let mekko_bounds = geometry.rect(10.0, 20.0, 240.0, 160.0)')
lines.append('    var mekko_totals: [6]f64 = zero')
lines.append('    var mekko_bars: [24]geometry.Rect = zero')
lines.append('    var mekko_layers: [4]chart.Layout = zero')
lines.append('    let (mekko_made, mekko_error) = chart.mekko(mekko_values[..], 6usize, 4usize, mekko_bounds, mekko_totals[..], mekko_bars[..], mekko_layers[..])')
check('mekko_error != ok || mekko_made.len != 4usize')
grand = float(values.sum())
totals = values.sum(axis=1)
check(' || '.join('!close(mekko_totals[%d], %s, 1e-6)' % (i, f64(totals[i])) for i in range(cats)))
area = 240.0 * 160.0
cumulative = np.concatenate([[0.0], np.cumsum(totals)]) / grand
parts = []
for c in range(cats):
    for s in range(series):
        i = s * cats + c
        frac = values[c, s] / grand
        parts.append('!close32(mekko_bars[%d].width * mekko_bars[%d].height / %s, %s, 1e-5)' % (i, i, f32(area), f32(frac)))
check(' || '.join(parts))
parts = []
for c in range(cats):
    if totals[c] == 0:
        parts.append('mekko_bars[%d].width != 0.0' % c)
    else:
        parts.append('!close32(mekko_bars[%d].x, %s, 1e-4) || !close32(mekko_bars[%d].width, %s, 1e-4)' % (c, f32(10.0 + 240.0 * cumulative[c]), c, f32(240.0 * totals[c] / grand)))
check(' || '.join(parts))
# stacks: series 0 sits at the bottom, heights fill the column
parts = []
for c in range(cats):
    if totals[c] == 0:
        continue
    for s in range(series):
        i = s * cats + c
        bottom_frac = values[c, :s].sum() / totals[c]
        parts.append('!close32(mekko_bars[%d].y + mekko_bars[%d].height, %s, 1e-4)' % (i, i, f32(20.0 + 160.0 * (1.0 - bottom_frac))))
check(' || '.join(parts))
lines.append('    let mekko_bad = [4]f32{ 1.0, 2.0, -1.0, 4.0 }')
lines.append('    let (_, mekko_negative) = chart.mekko(mekko_bad[..], 2usize, 2usize, mekko_bounds, mekko_totals[..], mekko_bars[..], mekko_layers[..])')
lines.append('    let mekko_zero = [4]f32{ 0.0, 0.0, 0.0, 0.0 }')
lines.append('    let (_, mekko_none) = chart.mekko(mekko_zero[..], 2usize, 2usize, mekko_bounds, mekko_totals[..], mekko_bars[..], mekko_layers[..])')
lines.append('    let (_, mekko_short) = chart.mekko(mekko_values[..], 6usize, 4usize, mekko_bounds, mekko_totals[..5usize], mekko_bars[..], mekko_layers[..])')
lines.append('    let (_, mekko_empty) = chart.mekko(mekko_values[..0usize], 0usize, 4usize, mekko_bounds, mekko_totals[..], mekko_bars[..], mekko_layers[..])')
check('mekko_negative != chart.Invalid || mekko_none != chart.Empty || mekko_short != chart.TooLarge || mekko_empty != chart.Empty')


# ---- Euler, two sets ----
def lens(r1, r2, d):
    if d >= r1 + r2:
        return 0.0
    if d <= abs(r1 - r2):
        return math.pi * min(r1, r2) ** 2
    a = r1 * r1 * math.acos((d * d + r1 * r1 - r2 * r2) / (2 * d * r1))
    b = r2 * r2 * math.acos((d * d + r2 * r2 - r1 * r1) / (2 * d * r2))
    c = 0.5 * math.sqrt((-d + r1 + r2) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2))
    return a + b - c


lines.append('    let euler_bounds = geometry.rect(0.0, 0.0, 300.0, 200.0)')
lines.append('    var euler_circles: [2]geometry.Rect = zero')
lines.append('    var euler_layers: [2]chart.Layout = zero')
cases = [(10.0, 6.0, 2.0), (10.0, 10.0, 5.0), (7.0, 3.0, 3.0), (4.0, 9.0, 0.0), (5.0, 5.0, 5.0), (1.0, 20.0, 0.3), (12.0, 8.0, 7.9)]
for n, (a, b, o) in enumerate(cases):
    r1, r2 = math.sqrt(a / math.pi), math.sqrt(b / math.pi)
    if o == 0:
        d = r1 + r2 + min(r1, r2) * 0.18
    elif o >= min(a, b):
        d = 0.0
    else:
        d = optimize.brentq(lambda x: lens(r1, r2, x) - o, abs(r1 - r2), r1 + r2, xtol=1e-14)
    k_unit = d / r2  # centre distance in units of the second radius
    lines.append('    let (euler_%d, euler_%d_error) = chart.euler2(%s, %s, %s, euler_bounds, euler_circles[..], euler_layers[..])' % (n, n, f32(a), f32(b), f32(o)))
    check('euler_%d_error != ok || euler_%d.len != 2usize' % (n, n))
    # radii follow the set sizes; distance follows the overlap
    check('!close32((euler_circles[0].width * 0.5) / (euler_circles[1].width * 0.5), %s, 1e-5)' % f32(r1 / r2))
    check('!close32(circle_distance(euler_circles[0], euler_circles[1]) / (euler_circles[1].width * 0.5), %s, 1e-4)' % f32(k_unit))
    if 0 < o < min(a, b):
        check('!close(lens_area(euler_circles[0], euler_circles[1]) / (3.141592653589793f64 * f64(euler_circles[0].width) * f64(euler_circles[0].width) * 0.25f64), %s, 1e-4)' % f64(o / a))
lines.append('    let (_, euler_big) = chart.euler2(5.0, 6.0, 7.0, euler_bounds, euler_circles[..], euler_layers[..])')
lines.append('    let (_, euler_neg) = chart.euler2(5.0, 6.0, -1.0, euler_bounds, euler_circles[..], euler_layers[..])')
lines.append('    let (_, euler_none) = chart.euler2(0.0, 0.0, 0.0, euler_bounds, euler_circles[..], euler_layers[..])')
lines.append('    let (_, euler_room) = chart.euler2(5.0, 6.0, 1.0, euler_bounds, euler_circles[..1usize], euler_layers[..])')
check('euler_big != chart.Invalid || euler_neg != chart.Invalid || euler_none != chart.Empty || euler_room != chart.TooLarge')

# ---- Venn, three sets ----
lines.append('    let venn_bounds = geometry.rect(0.0, 0.0, 240.0, 200.0)')
lines.append('    var venn_circles: [3]geometry.Rect = zero')
lines.append('    var venn_anchors: [7]chart.Coord = zero')
lines.append('    var venn_layers: [3]chart.Layout = zero')
lines.append('    let (venn_made, venn_error) = chart.venn3(venn_bounds, venn_circles[..], venn_anchors[..], venn_layers[..])')
check('venn_error != ok || venn_made.len != 3usize')
check('!close32(venn_circles[0].width, venn_circles[1].width, 1e-5) || !close32(venn_circles[1].width, venn_circles[2].width, 1e-5) || !close32(venn_circles[0].height, venn_circles[0].width, 1e-5)')
check('!close32(circle_distance(venn_circles[0], venn_circles[1]), 1.15 * venn_circles[0].width * 0.5, 1e-4) || !close32(circle_distance(venn_circles[0], venn_circles[2]), 1.15 * venn_circles[0].width * 0.5, 1e-4) || !close32(circle_distance(venn_circles[1], venn_circles[2]), 1.15 * venn_circles[0].width * 0.5, 1e-4)')
check('venn_circles[0].x < 0.0 || venn_circles[1].x < 0.0 || venn_circles[2].x + venn_circles[2].width > 240.0 || venn_circles[0].y < 0.0 || venn_circles[1].y + venn_circles[1].height > 200.0')
memberships = [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (1, 0, 1), (0, 1, 1), (1, 1, 1)]
for i, (a, b, c) in enumerate(memberships):
    check('inside(venn_circles[0], venn_anchors[%d]) != %s || inside(venn_circles[1], venn_anchors[%d]) != %s || inside(venn_circles[2], venn_anchors[%d]) != %s' % (i, 'true' if a else 'false', i, 'true' if b else 'false', i, 'true' if c else 'false'))
lines.append('    let (_, venn_room) = chart.venn3(venn_bounds, venn_circles[..], venn_anchors[..6usize], venn_layers[..])')
lines.append('    let (_, venn_flat) = chart.venn3(geometry.rect(0.0, 0.0, 0.0, 10.0), venn_circles[..], venn_anchors[..], venn_layers[..])')
check('venn_room != chart.TooLarge || venn_flat != chart.Invalid')

# ---- word cloud ----
names = ['alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel', 'india', 'juliet', 'kilo', 'lima', 'mike', 'november']
weights = [int(w) for w in rng.integers(2, 100, len(names))]
weights[3] = weights[6]  # a tie, resolved by input order
weights[9] = 0           # zero weight: omitted
excluded = ['hotel', 'mike']
unit_w = [round(float(x), 2) for x in rng.uniform(2.5, 5.5, len(names))]
unit_h = [1.0] * len(names)
base = 0.8
min_size, max_size, gap = 9.0, 36.0, 2.0
W, H = 640.0, 420.0
lines.append('    let cloud_words = [%d]str{ %s }' % (len(names), ', '.join('"%s"' % n for n in names)))
lines.append('    let cloud_weights = [%d]f32{ %s }' % (len(names), ', '.join(f32(w) for w in weights)))
lines.append('    let cloud_widths = [%d]f32{ %s }' % (len(names), ', '.join(f32(w) for w in unit_w)))
lines.append('    let cloud_heights = [%d]f32{ %s }' % (len(names), ', '.join(f32(h) for h in unit_h)))
lines.append('    let cloud_excluded = [2]str{ %s }' % ', '.join('"%s"' % n for n in excluded))
lines.append('    let cloud_bounds = geometry.rect(0.0, 0.0, %s, %s)' % (f32(W), f32(H)))
lines.append('    var cloud_order: [%d]usize = zero' % len(names))
lines.append('    var cloud_storage: [%d]chart.CloudWord = zero' % len(names))
lines.append('    let (cloud, cloud_error) = chart.word_cloud(cloud_words[..], cloud_weights[..], cloud_widths[..], cloud_heights[..], %s, cloud_excluded[..], cloud_bounds, %s, %s, %s, cloud_order[..], cloud_storage[..])' % (f32(base), f32(min_size), f32(max_size), f32(gap)))
active = [i for i in range(len(names)) if weights[i] > 0 and names[i] not in excluded]
ordered = sorted(active, key=lambda i: -weights[i])  # Python's sort is stable
wmax = max(weights[i] for i in active)
check('cloud_error != ok || cloud.len != %dusize' % len(active))
check(' || '.join('!str.eq(cloud[%d].label.text, "%s")' % (k, names[i]) for k, i in enumerate(ordered)))
sizes = [max(min_size, max_size * math.sqrt(weights[i] / wmax)) for i in ordered]
check(' || '.join('!close32(cloud[%d].size, %s, 1e-5)' % (k, f32(sizes[k])) for k in range(len(ordered))))
check(' || '.join('!close32(cloud[%d].box.width, %s, 1e-5) || !close32(cloud[%d].box.height, %s, 1e-5)' % (k, f32(unit_w[i] * sizes[k]), k, f32(unit_h[i] * sizes[k])) for k, i in enumerate(ordered)))
check(' || '.join('!close32(cloud[%d].label.anchor.y - cloud[%d].box.y, %s, 1e-4) || !close32(cloud[%d].label.anchor.x, cloud[%d].box.x, 1e-6)' % (k, k, f32(base * sizes[k]), k, k) for k in range(len(ordered))))
check('!cloud_contained(cloud, cloud_bounds)')
check('cloud_overlaps(cloud, %s)' % f32(gap))
check('cloud_has(cloud, "hotel") || cloud_has(cloud, "mike") || cloud_has(cloud, "juliet")')
# the largest weight sits nearest the centre of the bounds
check('!close32(cloud[0].box.x + cloud[0].box.width * 0.5, %s, 1e-4) || !close32(cloud[0].box.y + cloud[0].box.height * 0.5, %s, 1e-4)' % (f32(W / 2), f32(H / 2)))
lines.append('    let dup_words = [2]str{ "same", "same" }')
lines.append('    let dup_weights = [2]f32{ 1.0, 2.0 }')
lines.append('    let dup_sizes = [2]f32{ 3.0, 3.0 }')
lines.append('    let (_, cloud_dup) = chart.word_cloud(dup_words[..], dup_weights[..], dup_sizes[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])')
lines.append('    let neg_weights = [2]f32{ 1.0, -2.0 }')
lines.append('    let two_words = [2]str{ "one", "two" }')
lines.append('    let (_, cloud_neg) = chart.word_cloud(two_words[..], neg_weights[..], dup_sizes[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])')
lines.append('    let (_, cloud_len) = chart.word_cloud(two_words[..], dup_weights[..1usize], dup_sizes[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])')
lines.append('    let (_, cloud_range) = chart.word_cloud(two_words[..], dup_weights[..], dup_sizes[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 40.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])')
lines.append('    let (_, cloud_none) = chart.word_cloud(cloud_words[..0usize], cloud_weights[..0usize], cloud_widths[..0usize], cloud_heights[..0usize], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])')
lines.append('    let all_out = [2]str{ "one", "two" }')
lines.append('    let (_, cloud_all) = chart.word_cloud(two_words[..], dup_weights[..], dup_sizes[..], dup_sizes[..], 0.8, all_out[..], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])')
lines.append('    let (_, cloud_room) = chart.word_cloud(two_words[..], dup_weights[..], dup_sizes[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..1usize], cloud_storage[..])')
lines.append('    let wide = [2]f32{ 30.0, 3.0 }')
lines.append('    let (_, cloud_wide) = chart.word_cloud(two_words[..], dup_weights[..], wide[..], dup_sizes[..], 0.8, cloud_excluded[..0usize], cloud_bounds, 9.0, 36.0, 2.0, cloud_order[..], cloud_storage[..])')
check('cloud_dup != chart.Invalid || cloud_neg != chart.Invalid || cloud_len != chart.Invalid || cloud_range != chart.Invalid || cloud_none != chart.Empty || cloud_all != chart.Empty || cloud_room != chart.TooLarge || cloud_wide != chart.TooLarge')

body = '\n'.join(lines)
source = '''// The mekko, Euler, Venn and word-cloud layouts of e.gfx.chart against independent numpy and scipy
// computations (L073, D2257; scripts/chart_composition_reference.py writes this file): cell areas as value
// over grand total, circle areas and the overlap-solving centre distance, Venn spacing and region membership,
// and the cloud's sizes, order, exclusions, containment and spacing. Every check has its own exit code.
use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem
use e.os
use e.str

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn close(got: f64, want: f64, tolerance: f64) -> bool {
    ret abs64(got - want) <= tolerance * (1.0f64 + abs64(want))
}

fn close32(got: f32, want: f32, tolerance: f64) -> bool {
    ret close(f64(got), f64(want), tolerance)
}

fn circle_distance(a: geometry.Rect, b: geometry.Rect) -> f32 {
    let dx = f64(a.x + a.width * 0.5) - f64(b.x + b.width * 0.5)
    let dy = f64(a.y + a.height * 0.5) - f64(b.y + b.height * 0.5)
    ret f32(math_sqrt(dx * dx + dy * dy))
}

fn math_sqrt(v: f64) -> f64 {
    if v <= 0.0f64 { ret 0.0f64 }
    var x = v
    var i = 0usize
    while i < 80usize {
        x = 0.5f64 * (x + v / x)
        i += 1usize
    }
    ret x
}

fn inside(circle: geometry.Rect, p: chart.Coord) -> bool {
    let r = f64(circle.width) * 0.5f64
    let dx = f64(p.x) - (f64(circle.x) + r)
    let dy = f64(p.y) - (f64(circle.y) + r)
    ret dx * dx + dy * dy < r * r
}

// Lens area by numerical integration over x, so it shares no formula with the library.
fn lens_area(a: geometry.Rect, b: geometry.Rect) -> f64 {
    let ra = f64(a.width) * 0.5f64
    let rb = f64(b.width) * 0.5f64
    let ax = f64(a.x) + ra
    let ay = f64(a.y) + ra
    let bx = f64(b.x) + rb
    let by = f64(b.y) + rb
    var left = ax - ra
    if bx - rb > left { left = bx - rb }
    var right = ax + ra
    if bx + rb < right { right = bx + rb }
    if right <= left { ret 0.0f64 }
    let steps = 20000usize
    let h = (right - left) / f64(steps)
    var area = 0.0f64
    var i = 0usize
    while i < steps {
        let x = left + (f64(i) + 0.5f64) * h
        let ua = ra * ra - (x - ax) * (x - ax)
        let ub = rb * rb - (x - bx) * (x - bx)
        if ua > 0.0f64 && ub > 0.0f64 {
            let sa = math_sqrt(ua)
            let sb = math_sqrt(ub)
            var low = ay - sa
            if by - sb > low { low = by - sb }
            var high = ay + sa
            if by + sb < high { high = by + sb }
            if high > low { area += (high - low) * h }
        }
        i += 1usize
    }
    ret area
}

fn cloud_contained(cloud: []chart.CloudWord, bounds: geometry.Rect) -> bool {
    var i = 0usize
    while i < cloud.len {
        let b = cloud[i].box
        if b.x < bounds.x || b.y < bounds.y || b.x + b.width > bounds.x + bounds.width || b.y + b.height > bounds.y + bounds.height { ret false }
        i += 1usize
    }
    ret true
}

fn cloud_overlaps(cloud: []chart.CloudWord, gap: f32) -> bool {
    var i = 0usize
    while i < cloud.len {
        var j = 0usize
        while j < i {
            let a = cloud[i].box
            let b = cloud[j].box
            if a.x < b.x + b.width + gap && a.x + a.width + gap > b.x && a.y < b.y + b.height + gap && a.y + a.height + gap > b.y { ret true }
            j += 1usize
        }
        i += 1usize
    }
    ret false
}

fn cloud_has(cloud: []chart.CloudWord, text: str) -> bool {
    var i = 0usize
    while i < cloud.len {
        if str.eq(cloud[i].label.text, text) { ret true }
        i += 1usize
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("gfx chart composition reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_composition_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote gfx_chart_composition_reference with', code[0], 'checks')
