"""Write tests/selfhost/fixtures/link/gfx_chart_map_reference/src/main.e (L070, D2254).

  python scripts/chart_map_reference.py

Independent references for the maps of e.gfx.chart: the equirectangular and Mercator window
projections (the Mercator row as asinh(tan(latitude)), the closed form, where the code takes
log(tan(pi/4 + latitude/2))) on three windows including one centred on the antimeridian; area-scaled
proportional symbols (diameter 2 R sqrt(v / max), so circle area is proportional to the value);
choropleth normalisation, missing regions and ring winding from a shoelace sum of the projected
vertices; and the refusals of both layers and of the projection itself.
Every check has its own exit code.
"""
import math
import pathlib
import struct

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]


def f32(v):
    return struct.unpack('f', struct.pack('f', v))[0]


def check(condition):
    code[0] += 1
    lines.append('    if %s { os.exit(%d) }' % (condition, code[0]))


def num(v):
    return repr(float(v))


def merc(lat):
    return math.asinh(math.tan(math.radians(lat)))


def project(window, lon, lat):
    projection, center, half, south, north = window
    delta = lon - center
    if delta > 180.0:
        delta -= 360.0
    if delta < -180.0:
        delta += 360.0
    x = (delta + half) / (2.0 * half)
    if projection == 'Mercator':
        y = (merc(north) - merc(lat)) / (merc(north) - merc(south))
    else:
        y = (north - lat) / (north - south)
    return x, y


def window_text(name, window):
    projection, center, half, south, north = window
    lines.append('    let %s = geo.MapWindow { projection: .%s, center_lon: %sf64, half_lon_span: %sf64, south_lat: %sf64, north_lat: %sf64 }'
                 % (name, projection, num(center), num(half), num(south), num(north)))


WINDOWS = {
    'w_equi': ('Equirectangular', 0.0, 180.0, -60.0, 70.0),
    'w_seam': ('Equirectangular', 180.0, 30.0, -10.0, 20.0),
    'w_merc': ('Mercator', 10.0, 100.0, -70.0, 75.0),
}
POINTS = {
    'w_equi': [(-179.9, 69.9), (0.0, 0.0), (45.5, -59.9), (179.9, 10.0), (-90.0, 35.25), (12.3456, -12.3456), (-0.001, 69.999)],
    'w_seam': [(170.0, 5.0), (-170.0, -9.5), (180.0, 0.0), (-180.0, 19.0), (160.0, 10.0), (-160.0, 0.5), (179.5, 19.9)],
    'w_merc': [(10.0, 0.0), (-89.9, 74.9), (109.9, -69.9), (45.0, 45.0), (60.0, 60.0), (-30.0, -30.0), (10.0, 74.99)],
}
for name, window in WINDOWS.items():
    window_text(name, window)
# Closed-form Mercator against constants of the identity y = asinh(tan(lat)) at three latitudes.
lines.append('    let bounds = geometry.rect(20.0, 30.0, 200.0, 160.0)')
for name, window in WINDOWS.items():
    for k, (lon, lat) in enumerate(POINTS[name]):
        x, y = project(window, lon, lat)
        tag = '%s_%d' % (name, k)
        lines.append('    let (px_%s, py_%s, pe_%s) = geo.map_project(%sf64, %sf64, %s)' % (tag, tag, tag, num(lon), num(lat), name))
        check('pe_%s != ok || abs64(px_%s - %sf64) > 1e-12f64 || abs64(py_%s - %sf64) > 1e-12f64' % (tag, tag, num(x), tag, num(y)))

# ---- projection refusals ----
lines.append('    let nan = 0.0f64 / zero_f64()')
lines.append('    let infinity = 1.0f64 / zero_f64()')
refusals = [
    ('lon_high', 'geo.map_project(180.5f64, 0.0f64, w_equi)'),
    ('lon_low', 'geo.map_project(-180.5f64, 0.0f64, w_equi)'),
    ('lat_north', 'geo.map_project(0.0f64, 70.5f64, w_equi)'),
    ('lat_south', 'geo.map_project(0.0f64, -60.5f64, w_equi)'),
    ('beyond_span', 'geo.map_project(100.0f64, 0.0f64, w_seam)'),
    ('lon_nan', 'geo.map_project(nan, 0.0f64, w_equi)'),
    ('lat_nan', 'geo.map_project(0.0f64, nan, w_equi)'),
    ('lon_inf', 'geo.map_project(infinity, 0.0f64, w_equi)'),
    ('lat_inf', 'geo.map_project(0.0f64, 0.0f64 - infinity, w_equi)'),
]
for name, call in refusals:
    lines.append('    let (_rx_%s, _ry_%s, re_%s) = %s' % (name, name, name, call))
    check('re_%s != geo.Invalid' % name)
for name, window in (('span_zero', ('Equirectangular', 0.0, 0.0, -10.0, 10.0)), ('span_wide', ('Equirectangular', 0.0, 181.0, -10.0, 10.0)),
                     ('center_high', ('Equirectangular', 181.0, 10.0, -10.0, 10.0)), ('flat', ('Equirectangular', 0.0, 10.0, 5.0, 5.0)),
                     ('inverted', ('Equirectangular', 0.0, 10.0, 10.0, -10.0)), ('south_pole', ('Equirectangular', 0.0, 10.0, -91.0, 10.0)),
                     ('merc_north', ('Mercator', 0.0, 10.0, -10.0, 85.5)), ('merc_south', ('Mercator', 0.0, 10.0, -85.5, 10.0))):
    window_text('bad_' + name, window)
    lines.append('    let (_wx_%s, _wy_%s, we_%s) = geo.map_project(0.0f64, 0.0f64, bad_%s)' % (name, name, name, name))
    check('we_%s != geo.Invalid' % name)

# ---- proportional symbols: circle area proportional to the value ----
values = [100.0, 25.0, 4.0, 1.0, 0.25, 0.0]
sites = [(-120.0, 50.0), (-60.0, 20.0), (0.0, 0.0), (30.0, -30.0), (90.0, 40.0), (150.0, 60.0)]
max_radius = 12.5
window = WINDOWS['w_equi']
site_lines = []
for k, (value, (lon, lat)) in enumerate(zip(values, sites)):
    site_lines.append('chart.MapSite { key: "S%d", lon: %sf64, lat: %sf64, value: %sf64, present: true }' % (k, num(lon), num(lat), num(value)))
lines.append('    let sites = [6]chart.MapSite{ %s }' % ', '.join(site_lines))
lines.append('    var circles: [6]geometry.Rect = zero')
lines.append('    let (symbols, symbols_error) = chart.proportional_symbol_map(sites[..], w_equi, bounds, %sf32, circles[..])' % num(max_radius))
check('symbols_error != ok || symbols.present_count != 6usize || symbols.maximum != 100.0f64')
expected = []
for (value, (lon, lat)) in zip(values, sites):
    x, y = project(window, lon, lat)
    px, py = 20.0 + 200.0 * f32(x), 30.0 + 160.0 * f32(y)
    d = 2.0 * max_radius * math.sqrt(value / 100.0) if value > 0 else 0.0
    expected.append((px, py, d))
for k, (px, py, d) in enumerate(expected):
    if d > 0:
        check('abs64(f64(circles[%dusize].width) - %sf64) > 1e-4f64 || abs64(f64(circles[%dusize].height) - %sf64) > 1e-4f64 || abs64(f64(circles[%dusize].x) + f64(circles[%dusize].width) * 0.5f64 - %sf64) > 1e-3f64 || abs64(f64(circles[%dusize].y) + f64(circles[%dusize].height) * 0.5f64 - %sf64) > 1e-3f64'
              % (k, num(d), k, num(d), k, k, num(px), k, k, num(py)))
    else:
        check('circles[%dusize].width != 0.0f32 || circles[%dusize].height != 0.0f32' % (k, k))
# Area, not radius: the first circle covers 4, 16 and 64 times the area of the 25, 4 and 1 circles.
check('abs64(area_ratio(circles[0usize], circles[1usize]) - 4.0f64) > 1e-3f64 || abs64(area_ratio(circles[0usize], circles[2usize]) - 25.0f64) > 1e-2f64 || abs64(area_ratio(circles[0usize], circles[3usize]) - 100.0f64) > 1e-1f64')
# An absent site draws nothing and does not set the scale.
lines.append('    var absent = sites')
lines.append('    absent[0] = chart.MapSite { key: "S0", lon: -120.0f64, lat: 50.0f64, value: 1000.0f64, present: false }')
lines.append('    let (absent_map, absent_error) = chart.proportional_symbol_map(absent[..], w_equi, bounds, 12.5f32, circles[..])')
check('absent_error != ok || absent_map.present_count != 5usize || absent_map.maximum != 25.0f64 || circles[0usize].width != 0.0f32')
# Refusals of the symbol layer.
lines.append('    var bad_value = sites')
lines.append('    bad_value[1] = chart.MapSite { key: "S1", lon: -60.0f64, lat: 20.0f64, value: -1.0f64, present: true }')
lines.append('    let (_sa, e_negative) = chart.proportional_symbol_map(bad_value[..], w_equi, bounds, 12.5f32, circles[..])')
check('e_negative != chart.Invalid')
lines.append('    bad_value[1] = chart.MapSite { key: "S1", lon: -60.0f64, lat: 20.0f64, value: nan, present: true }')
lines.append('    let (_sb, e_value_nan) = chart.proportional_symbol_map(bad_value[..], w_equi, bounds, 12.5f32, circles[..])')
check('e_value_nan != chart.Invalid')
lines.append('    bad_value[1] = chart.MapSite { key: "", lon: -60.0f64, lat: 20.0f64, value: 1.0f64, present: true }')
lines.append('    let (_sc, e_key) = chart.proportional_symbol_map(bad_value[..], w_equi, bounds, 12.5f32, circles[..])')
check('e_key != chart.Invalid')
lines.append('    bad_value[1] = chart.MapSite { key: "S1", lon: -60.0f64, lat: 80.0f64, value: 1.0f64, present: true }')
lines.append('    let (_sd, e_outside) = chart.proportional_symbol_map(bad_value[..], w_equi, bounds, 12.5f32, circles[..])')
check('e_outside != chart.Invalid')
lines.append('    let (_se, e_radius_zero) = chart.proportional_symbol_map(sites[..], w_equi, bounds, 0.0f32, circles[..])')
check('e_radius_zero != chart.Invalid')
lines.append('    let (_sf, e_radius_nan) = chart.proportional_symbol_map(sites[..], w_equi, bounds, f32(nan), circles[..])')
check('e_radius_nan != chart.Invalid')
lines.append('    let (_sg, e_empty) = chart.proportional_symbol_map(sites[..0usize], w_equi, bounds, 12.5f32, circles[..])')
check('e_empty != chart.Invalid')
lines.append('    let (_sh, e_short) = chart.proportional_symbol_map(sites[..], w_equi, bounds, 12.5f32, circles[..5usize])')
check('e_short != chart.TooLarge')
lines.append('    let (_si, e_bounds) = chart.proportional_symbol_map(sites[..], w_equi, geometry.rect(0.0, 0.0, 0.0, 10.0), 12.5f32, circles[..])')
check('e_bounds != chart.Invalid')

# ---- choropleth: normalisation, missing regions, ring winding ----
def square(lon0, lat0, size, ccw=True):
    pts = [(lon0, lat0), (lon0 + size, lat0), (lon0 + size, lat0 + size), (lon0, lat0 + size)]
    return pts if ccw else list(reversed(pts))


regions = ['A', 'B', 'C', 'D', 'E']
rings = [
    # region index, hole, vertices
    (0, False, square(-100.0, 10.0, 20.0, True)),
    (0, True, square(-90.0, 20.0, 5.0, False)),          # a hole, wound the opposite way
    (1, False, square(-50.0, -20.0, 20.0, False)),       # an outer ring wound clockwise
    (1, True, square(-45.0, -15.0, 5.0, True)),
    (2, False, square(10.0, 30.0, 15.0, True)),
    (3, False, square(60.0, 0.0, 10.0, True)),
    (4, False, square(100.0, 40.0, 10.0, False)),
]
vertices = [v for (_, _, pts) in rings for v in pts]
lines.append('    let regions = [5]chart.MapRegion{ %s }' % ', '.join('chart.MapRegion { key: "%s" }' % r for r in regions))
ring_text = []
first = 0
for (owner, hole, pts) in rings:
    ring_text.append('chart.MapRing { region: %dusize, first: %dusize, count: %dusize, hole: %s }' % (owner, first, len(pts), 'true' if hole else 'false'))
    first += len(pts)
lines.append('    let rings = [%d]chart.MapRing{ %s }' % (len(rings), ', '.join(ring_text)))
lines.append('    let vertices = [%d]chart.MapVertex{ %s }' % (len(vertices), ', '.join('chart.MapVertex { lon: %sf64, lat: %sf64 }' % (num(v[0]), num(v[1])) for v in vertices)))
metrics = [('A', -5.0), ('B', 15.0), ('C', 5.0), ('Z', 1000.0)]   # D and E have no metric; Z names no region
lines.append('    let metrics = [4]chart.MapMetric{ %s }' % ', '.join('chart.MapMetric { key: "%s", value: %sf64 }' % (k, num(v)) for k, v in metrics))
lines.append('    var c_points: [%d]chart.Coord = zero' % len(vertices))
lines.append('    var c_rings: [%d]chart.MapProjectedRing = zero' % len(rings))
lines.append('    var c_regions: [5]chart.MapRegionLayout = zero')
lines.append('    var work = chart.ChoroplethStorage { points: c_points[..], rings: c_rings[..], regions: c_regions[..] }')
lines.append('    let (map, map_error) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], w_equi, bounds, &work)')
check('map_error != ok || map.regions.len != 5usize || !map.has_values || map.minimum != -5.0f64 || map.maximum != 15.0f64')
fractions = [0.0, 1.0, 0.5]
for k, f in enumerate(fractions):
    check('!map.regions[%dusize].has_value || abs64(f64(map.regions[%dusize].fraction) - %sf64) > 1e-6f64' % (k, k, num(f)))
check('map.regions[3usize].has_value || map.regions[4usize].has_value || map.regions[3usize].fraction != 0.0f32 || map.regions[4usize].fraction != 0.0f32')
# Winding: projected shoelace sum, outer rings one way, holes the other, whatever order the data came in.
want_reverse = []
ring_index = 0
for (owner, hole, pts) in rings:
    area = 0.0
    projected = []
    for (lon, lat) in pts:
        x, y = project(WINDOWS['w_equi'], lon, lat)
        projected.append((f32(20.0 + 200.0 * f32(x)), f32(30.0 + 160.0 * f32(y))))
    for i in range(len(projected)):
        ax, ay = projected[i]
        bx, by = projected[(i + 1) % len(projected)]
        area += ax * by - bx * ay
    reverse = area < 0.0
    if hole:
        reverse = area > 0.0
    want_reverse.append(reverse)
lines.append('    let want_reverse = [%d]bool{ %s }' % (len(rings), ', '.join('true' if r else 'false' for r in want_reverse)))
lines.append('    var winding_ok = true')
lines.append('    var wi = 0usize')
lines.append('    while wi < %dusize {' % len(rings))
lines.append('        if work.rings[wi].reverse != want_reverse[wi] { winding_ok = false }')
lines.append('        wi += 1usize')
lines.append('    }')
check('!winding_ok')
# With every metric equal the fraction is the middle, never a division by zero.
lines.append('    let equal_metrics = [2]chart.MapMetric{ chart.MapMetric { key: "A", value: 7.0f64 }, chart.MapMetric { key: "B", value: 7.0f64 } }')
lines.append('    let (equal_map, equal_error) = chart.choropleth(regions[..], rings[..], vertices[..], equal_metrics[..], w_equi, bounds, &work)')
check('equal_error != ok || equal_map.regions[0usize].fraction != 0.5f32 || equal_map.regions[1usize].fraction != 0.5f32')
# No metrics at all: no values, every region unfilled.
lines.append('    let (none_map, none_error) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..0usize], w_equi, bounds, &work)')
check('none_error != ok || none_map.has_values || none_map.regions[0usize].has_value')
# Refusals of the choropleth.
lines.append('    let dup_regions = [5]chart.MapRegion{ chart.MapRegion { key: "A" }, chart.MapRegion { key: "A" }, chart.MapRegion { key: "C" }, chart.MapRegion { key: "D" }, chart.MapRegion { key: "E" } }')
lines.append('    let (_ca, e_dup_region) = chart.choropleth(dup_regions[..], rings[..], vertices[..], metrics[..], w_equi, bounds, &work)')
check('e_dup_region != chart.Invalid')
lines.append('    let blank_regions = [5]chart.MapRegion{ chart.MapRegion { key: "" }, chart.MapRegion { key: "B" }, chart.MapRegion { key: "C" }, chart.MapRegion { key: "D" }, chart.MapRegion { key: "E" } }')
lines.append('    let (_cb, e_blank_region) = chart.choropleth(blank_regions[..], rings[..], vertices[..], metrics[..], w_equi, bounds, &work)')
check('e_blank_region != chart.Invalid')
lines.append('    let nan_metrics = [1]chart.MapMetric{ chart.MapMetric { key: "A", value: nan } }')
lines.append('    let (_cc, e_nan_metric) = chart.choropleth(regions[..], rings[..], vertices[..], nan_metrics[..], w_equi, bounds, &work)')
check('e_nan_metric != chart.Invalid')
lines.append('    let dup_metrics = [2]chart.MapMetric{ chart.MapMetric { key: "A", value: 1.0f64 }, chart.MapMetric { key: "A", value: 2.0f64 } }')
lines.append('    let (_cd, e_dup_metric) = chart.choropleth(regions[..], rings[..], vertices[..], dup_metrics[..], w_equi, bounds, &work)')
check('e_dup_metric != chart.Invalid')
lines.append('    let hole_first = [1]chart.MapRing{ chart.MapRing { region: 0usize, first: 0usize, count: 4usize, hole: true } }')
lines.append('    let (_ce, e_hole_first) = chart.choropleth(regions[..1usize], hole_first[..], vertices[..4usize], metrics[..], w_equi, bounds, &work)')
check('e_hole_first != chart.Invalid')
lines.append('    let tiny_ring = [1]chart.MapRing{ chart.MapRing { region: 0usize, first: 0usize, count: 2usize, hole: false } }')
lines.append('    let (_cf, e_tiny_ring) = chart.choropleth(regions[..1usize], tiny_ring[..], vertices[..2usize], metrics[..], w_equi, bounds, &work)')
check('e_tiny_ring != chart.Invalid')
lines.append('    let flat_vertices = [4]chart.MapVertex{ chart.MapVertex { lon: 0.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 5.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 10.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 15.0f64, lat: 0.0f64 } }')
lines.append('    let flat_ring = [1]chart.MapRing{ chart.MapRing { region: 0usize, first: 0usize, count: 4usize, hole: false } }')
lines.append('    let (_cg, e_flat_ring) = chart.choropleth(regions[..1usize], flat_ring[..], flat_vertices[..], metrics[..], w_equi, bounds, &work)')
check('e_flat_ring != chart.Invalid')
lines.append('    let outside = [4]chart.MapVertex{ chart.MapVertex { lon: 0.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 5.0f64, lat: 0.0f64 }, chart.MapVertex { lon: 5.0f64, lat: 90.0f64 }, chart.MapVertex { lon: 0.0f64, lat: 5.0f64 } }')
lines.append('    let (_ch, e_outside_window) = chart.choropleth(regions[..1usize], flat_ring[..], outside[..], metrics[..], w_equi, bounds, &work)')
check('e_outside_window != chart.Invalid')
lines.append('    let (_ci, e_few_rings) = chart.choropleth(regions[..], rings[..4usize], vertices[..], metrics[..], w_equi, bounds, &work)')
check('e_few_rings != chart.Invalid')
lines.append('    let (_cj, e_no_regions) = chart.choropleth(regions[..0usize], rings[..], vertices[..], metrics[..], w_equi, bounds, &work)')
check('e_no_regions != chart.Invalid')
lines.append('    let (_ck, e_bad_bounds) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], w_equi, geometry.rect(0.0, 0.0, -1.0, 10.0), &work)')
check('e_bad_bounds != chart.Invalid')
for field, count in (('points', len(vertices) - 1), ('rings', len(rings) - 1), ('regions', 4)):
    lines.append('    var short_%s = work' % field)
    lines.append('    short_%s.%s = %s[..%dusize]' % (field, field, {'points': 'c_points', 'rings': 'c_rings', 'regions': 'c_regions'}[field], count))
    lines.append('    let (_cs_%s, e_short_%s) = chart.choropleth(regions[..], rings[..], vertices[..], metrics[..], w_equi, bounds, &short_%s)' % (field, field, field))
    check('e_short_%s != chart.TooLarge' % field)

body = '\n'.join(lines)
source = '''// The maps of e.gfx.chart against independent references (L070, D2254;
// scripts/chart_map_reference.py writes this file): the equirectangular and Mercator projections on three
// windows, one centred on the antimeridian; area-scaled proportional symbols; choropleth normalisation,
// missing regions and ring winding from a shoelace sum; and the refusals of the projection and of both
// layers, with each storage array one element short. Every check has its own exit code.
use e.algo.geo
use e.gfx.chart
use e.gfx.geometry
use e.mem
use e.os

fn zero_f64() -> f64 {
    ret 0.0f64
}

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn area_ratio(big: geometry.Rect, small: geometry.Rect) -> f64 {
    ret (f64(big.width) * f64(big.height)) / (f64(small.width) * f64(small.height))
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    let (written, write_error) = os.write(os.stdout(), "gfx chart map reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_map_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote gfx_chart_map_reference with', code[0], 'checks')
