"""Write tests/selfhost/fixtures/link/gfx_chart_3d_reference/src/main.e (L069, D2253).

  python scripts/chart_3d_reference.py

Independent references for the 3-D charts of e.gfx.chart: the perspective projection and the fitted
viewport (re-derived here from the documented formulas, with the single-precision rounding the layouts
use), the depth-sorted order of a scatter cloud, the product-Gaussian density of density_surface3d
(a direct double sum), and the two-dimensional bin counts of histogram3d with out-of-range points
dropped -- plus the refusals: non-finite data, degenerate domains, bandwidths and cameras out of range,
and every caller-storage array one element too short. Every check has its own exit code.
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


def farr(name, values):
    lines.append('    let %s = [%d]f64{ %s }' % (name, len(values), ', '.join(repr(float(v)) + 'f64' for v in values)))


def project(cam, x, y, z):
    az, el, dist = cam
    a, e = math.radians(az), math.radians(el)
    # The layouts convert degrees with the constant pi/180 to 17 digits, as the product below does.
    a = az * 0.017453292519943295
    e = el * 0.017453292519943295
    sa, ca, se, ce = math.sin(a), math.cos(a), math.sin(e), math.cos(e)
    right = -sa * x + ca * y
    up = -se * ca * x - se * sa * y + ce * z
    depth = ce * ca * x + ce * sa * y + se * z
    factor = dist / (dist - depth)
    return f32(right * factor), f32(up * factor), depth


def viewport(cam, bounds):
    bx, by, bw, bh = bounds
    raws = []
    for i in range(8):
        nx = 1.0 if i % 2 else -1.0
        ny = 1.0 if (i // 2) % 2 else -1.0
        nz = 1.0 if i >= 4 else -1.0
        raws.append(project(cam, nx, ny, nz)[:2])
    u_lo = min(r[0] for r in raws)
    u_hi = max(r[0] for r in raws)
    v_lo = min(r[1] for r in raws)
    v_hi = max(r[1] for r in raws)
    scale = min(bw / (1.12 * (u_hi - u_lo)), bh / (1.12 * (v_hi - v_lo)))
    uc = u_lo + (u_hi - u_lo) * 0.5
    vc = v_lo + (v_hi - v_lo) * 0.5
    xc = bx + bw * 0.5
    yc = by + bh * 0.5
    return (lambda nx, ny, nz: _view(cam, nx, ny, nz, uc, vc, xc, yc, scale)), raws, (uc, vc, xc, yc, scale)


def _view(cam, nx, ny, nz, uc, vc, xc, yc, scale):
    u, v, depth = project(cam, nx, ny, nz)
    return f32(xc + (u - uc) * scale), f32(yc - (v - vc) * scale), depth


BOUNDS = (20.0, 25.0, 240.0, 130.0)
CAMERAS = [(42.0, 30.0, 4.5), (-120.0, 15.0, 3.0), (200.0, -40.0, 6.0)]

# ---- the cube frame under three cameras, read back through a 2x2 wireframe ----
lines.append('    let bounds = geometry.rect(%.1f, %.1f, %.1f, %.1f)' % BOUNDS)
lines.append('    let flat = [4]f64{ 0.0f64, 1.0f64, 1.0f64, 0.0f64 }')
for index, cam in enumerate(CAMERAS):
    view, raws, parameters = viewport(cam, BOUNDS)
    expected = []
    for i in range(8):
        nx = 1.0 if i % 2 else -1.0
        ny = 1.0 if (i // 2) % 2 else -1.0
        nz = 1.0 if i >= 4 else -1.0
        x, y, d = view(nx, ny, nz)
        expected += [x, y]
    farr('corners%d' % index, expected)
    lines.append('    let camera%d = chart.Camera3d { azimuth_degrees: %.1ff64, elevation_degrees: %.1ff64, distance: %.1ff64 }' % ((index,) + cam))
    lines.append('    let (frame%d, frame_error%d) = chart.wireframe3d(flat[..], 2usize, camera%d, bounds, &surface_storage)' % (index, index, index))
    check('frame_error%d != ok' % index)
    check('!corners_match(frame%d.corners, corners%d[..])' % (index, index))

# ---- a scatter cloud: projected points and the far-to-near order ----
cloud = [(-3.0, 1.0, 0.5), (2.5, -1.5, 2.0), (0.0, 0.0, -1.0), (4.0, 3.0, 1.0), (-1.0, -2.0, 3.0), (1.0, 2.0, -2.0)]
xs = [p[0] for p in cloud]
ys = [p[1] for p in cloud]
zs = [p[2] for p in cloud]
cam = CAMERAS[0]
view, raws, parameters = viewport(cam, BOUNDS)
span = [max(c) - min(c) for c in (xs, ys, zs)]
lo = [min(c) for c in (xs, ys, zs)]
projected = []
depths = []
for p in cloud:
    n = [2.0 * (p[k] - lo[k]) / span[k] - 1.0 for k in range(3)]
    x, y, d = view(*n)
    projected += [x, y]
    depths.append(d)
order = sorted(range(len(cloud)), key=lambda i: (depths[i], i))
farr('cloud_x', xs)
farr('cloud_y', ys)
farr('cloud_z', zs)
farr('cloud_points', projected)
farr('cloud_depths', depths)
lines.append('    let cloud_order = [6]usize{ %s }' % ', '.join('%dusize' % i for i in order))
lines.append('    let (cloud, cloud_error) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &scatter_storage)')
check('cloud_error != ok || cloud.points.len != 6usize')
check('!points_match(cloud.points, cloud_points[..])')
check('!depths_match(cloud.depths, cloud_depths[..])')
check('!same_order(cloud.order, cloud_order[..])')
check('cloud.x_min != %sf64 || cloud.x_max != %sf64 || cloud.z_min != %sf64 || cloud.z_max != %sf64' % tuple(repr(float(v)) for v in (lo[0], lo[0] + span[0], lo[2], lo[2] + span[2])))

# ---- the product-Gaussian density against a direct double sum ----
sample = [(-0.6, 0.2), (0.1, -0.5), (0.3, 0.4), (0.7, 0.7), (-0.2, -0.1)]
bw = (0.3, 0.4)
gx = [-1.0 + 2.0 * i / 4 for i in range(5)]
gy = [1.0 - 2.0 * i / 3 for i in range(4)]
density = []
for yy in gy:
    for xx in gx:
        s = 0.0
        for (sx, sy) in sample:
            dx = (xx - sx) / bw[0]
            dy = (yy - sy) / bw[1]
            s += math.exp(-0.5 * (dx * dx + dy * dy))
        density.append(s / (len(sample) * 2.0 * math.pi * bw[0] * bw[1]))
farr('sample_x', [p[0] for p in sample])
farr('sample_y', [p[1] for p in sample])
farr('density_want', density)
lines.append('    var grid_x: [5]f64 = zero')
lines.append('    var grid_y: [4]f64 = zero')
lines.append('    var density: [20]f64 = zero')
lines.append('    let (surface, surface_error) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, %.1ff64, %.1ff64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)' % bw)
check('surface_error != ok || surface.columns != 5usize || surface.rows != 4usize')
check('!close_all(density[..], density_want[..], 1e-12f64)')
check('surface.value_min != density_min(density[..]) || surface.value_max != density_max(density[..])')
farr('grid_x_want', gx)
farr('grid_y_want', gy)
check('!close_all(grid_x[..], grid_x_want[..], 1e-15f64) || !close_all(grid_y[..], grid_y_want[..], 1e-15f64)')

# ---- the histogram: bin counts, maxima in the last bin, the top row first ----
hx = [-0.9, -0.5, -0.1, 0.3, 0.6, 1.0, 0.99, -1.0, 0.2, 0.25]
hy = [-0.8, 0.1, 0.4, -0.3, 0.7, 1.0, 0.0, -1.0, -0.95, -0.9]
columns, rows = 4, 3
counts = [0] * (columns * rows)
for (px, py) in zip(hx, hy):
    column = columns - 1 if px >= 1.0 else min(int(math.floor((px + 1.0) / 2.0 * columns)), columns - 1)
    row = rows - 1 if py <= -1.0 else min(int(math.floor((1.0 - py) / 2.0 * rows)), rows - 1)
    counts[row * columns + column] += 1
lines.append('    let hist_x = [%d]f32{ %s }' % (len(hx), ', '.join('%.3f' % v for v in hx)))
lines.append('    let hist_y = [%d]f32{ %s }' % (len(hy), ', '.join('%.3f' % v for v in hy)))
lines.append('    let hist_want = [%d]u64{ %s }' % (len(counts), ', '.join('%du64' % c for c in counts)))
lines.append('    let (hist, hist_error) = chart.histogram3d(hist_x[..], hist_y[..], -1.0, 1.0, -1.0, 1.0, %dusize, %dusize, camera0, bounds, &hist_storage)' % (columns, rows))
check('hist_error != ok || hist.total_count != %du64 || hist.max_count != %du64' % (len(hx), max(counts)))
check('!counts_match(hist.counts, hist_want[..])')
# A point outside the domain is a refusal, never a dropped or clamped count.
lines.append('    var out_x = hist_x')
lines.append('    out_x[6] = 1.4')
lines.append('    let (_ho, e_hist_outside) = chart.histogram3d(out_x[..], hist_y[..], -1.0, 1.0, -1.0, 1.0, %dusize, %dusize, camera0, bounds, &hist_storage)' % (columns, rows))
check('e_hist_outside != chart.Invalid')

# ---- refusals ----
lines.append('    let nan = 0.0f64 / zero_f64()')
lines.append('    let infinity = 1.0f64 / zero_f64()')
lines.append('    var bad_x = cloud_x')
lines.append('    bad_x[2] = nan')
lines.append('    let (_p0, e_nan_x) = chart.scatter3d(bad_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &scatter_storage)')
check('e_nan_x != chart.Invalid')
lines.append('    var bad_y = cloud_y')
lines.append('    bad_y[4] = infinity')
lines.append('    let (_p1, e_inf_y) = chart.scatter3d(cloud_x[..], bad_y[..], cloud_z[..], camera0, bounds, &scatter_storage)')
check('e_inf_y != chart.Invalid')
lines.append('    var bad_z = cloud_z')
lines.append('    bad_z[0] = -infinity')
lines.append('    let (_p2, e_inf_z) = chart.scatter3d(cloud_x[..], cloud_y[..], bad_z[..], camera0, bounds, &scatter_storage)')
check('e_inf_z != chart.Invalid')
lines.append('    let (_p3, e_len) = chart.scatter3d(cloud_x[..5usize], cloud_y[..], cloud_z[..], camera0, bounds, &scatter_storage)')
check('e_len != chart.Invalid')
lines.append('    let (_p4, e_empty) = chart.scatter3d(cloud_x[..0usize], cloud_y[..0usize], cloud_z[..0usize], camera0, bounds, &scatter_storage)')
check('e_empty != chart.Invalid')
for name, camera in (('az_high', '361.0f64, 30.0f64, 4.5f64'), ('az_low', '-361.0f64, 30.0f64, 4.5f64'), ('el_high', '42.0f64, 91.0f64, 4.5f64'),
                     ('el_low', '42.0f64, -91.0f64, 4.5f64'), ('near', '42.0f64, 30.0f64, 2.99f64'), ('nan_camera', '42.0f64, 30.0f64, nan')):
    az, el, di = camera.split(', ')
    lines.append('    let bad_%s = chart.Camera3d { azimuth_degrees: %s, elevation_degrees: %s, distance: %s }' % (name, az, el, di))
    lines.append('    let (_c_%s, e_%s) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], bad_%s, bounds, &scatter_storage)' % (name, name, name))
    check('e_%s != chart.Invalid' % name)
lines.append('    let (_b0, e_bounds0) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, geometry.rect(20.0, 25.0, 0.0, 130.0), &scatter_storage)')
check('e_bounds0 != chart.Invalid')
lines.append('    let (_b1, e_bounds1) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, geometry.rect(20.0, 25.0, 240.0, -5.0), &scatter_storage)')
check('e_bounds1 != chart.Invalid')
# The histogram's elevation must show the tops, and its range must be a range.
lines.append('    let flat_camera = chart.Camera3d { azimuth_degrees: 42.0f64, elevation_degrees: 0.0f64, distance: 4.5f64 }')
lines.append('    let (_h0, e_hist_flat) = chart.histogram3d(hist_x[..], hist_y[..], -1.0, 1.0, -1.0, 1.0, 4usize, 3usize, flat_camera, bounds, &hist_storage)')
check('e_hist_flat != chart.Invalid')
lines.append('    let (_h1, e_hist_zero) = chart.histogram3d(hist_x[..], hist_y[..], -1.0, 1.0, -1.0, 1.0, 0usize, 3usize, camera0, bounds, &hist_storage)')
check('e_hist_zero != chart.Invalid')
lines.append('    let (_h2, e_hist_range) = chart.histogram3d(hist_x[..], hist_y[..], 1.0, -1.0, -1.0, 1.0, 4usize, 3usize, camera0, bounds, &hist_storage)')
check('e_hist_range == ok')
lines.append('    var bad_hist = hist_x')
lines.append('    bad_hist[3] = f32(nan)')
lines.append('    let (_h3, e_hist_nan) = chart.histogram3d(bad_hist[..], hist_y[..], -1.0, 1.0, -1.0, 1.0, 4usize, 3usize, camera0, bounds, &hist_storage)')
check('e_hist_nan == ok')
# The density's domain, bandwidths and grid.
for name, args in (('domain_x', '-1.0f64, -1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64'), ('domain_y', '-1.0f64, 1.0f64, 1.0f64, 1.0f64, 0.3f64, 0.4f64'),
                   ('bw_zero', '-1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.0f64, 0.4f64'), ('bw_negative', '-1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, -0.4f64'),
                   ('bw_nan', '-1.0f64, 1.0f64, -1.0f64, 1.0f64, nan, 0.4f64'), ('narrow', '0.0f64, 0.5f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64')):
    lines.append('    let (_d_%s, e_density_%s) = chart.density_surface3d(sample_x[..], sample_y[..], %s, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)' % (name, name, args))
    check('e_density_%s != chart.Invalid' % name)
lines.append('    var bad_sample = sample_x')
lines.append('    bad_sample[1] = nan')
lines.append('    let (_d6, e_density_nan) = chart.density_surface3d(bad_sample[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)')
check('e_density_nan != chart.Invalid')
lines.append('    var tiny_grid_x: [1]f64 = zero')
lines.append('    let (_d7, e_density_grid) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, tiny_grid_x[..], grid_y[..], density[..], &surface_storage)')
check('e_density_grid != chart.Invalid')
lines.append('    let (_d8, e_density_short) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..19usize], &surface_storage)')
check('e_density_short != chart.TooLarge')
lines.append('    let (_d9, e_density_empty) = chart.density_surface3d(sample_x[..0usize], sample_y[..0usize], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)')
check('e_density_empty != chart.Empty')
# Caller storage: each array of each layout one element too short is a refusal, not a trap.
scatter_fields = [('points', 6), ('depths', 6), ('order', 6), ('bubbles', 6), ('corners', 8), ('edges', 12)]
for field, need in scatter_fields:
    parts = []
    for f, n in scatter_fields:
        parts.append('%s: s_%s[..%dusize]' % (f, f, n - 1 if f == field else n))
    lines.append('    var short_scatter_%s = chart.Scatter3dStorage { %s }' % (field, ', '.join(parts)))
    lines.append('    let (_s_%s, e_short_%s) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &short_scatter_%s)' % (field, field, field))
    check('e_short_%s != chart.TooLarge' % field)

body = '\n'.join(lines)
source = '''// The 3-D charts of e.gfx.chart against independent references (L069, D2253;
// scripts/chart_3d_reference.py writes this file): the cube frame under three cameras, a scatter cloud's
// projected points, depths and far-to-near order, the product-Gaussian density against a direct double sum,
// the bin counts of the 3-D histogram with out-of-range points dropped, and the refusals -- non-finite data,
// degenerate domains and bounds, out-of-range cameras and bandwidths, and each caller-storage array one
// element short. Every check has its own exit code.
use e.gfx.chart
use e.gfx.geometry
use e.math
use e.mem
use e.os

fn zero_f64() -> f64 {
    ret 0.0f64
}

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn corners_match(got: []const chart.Coord, want: []const f64) -> bool {
    if got.len != 8usize || want.len != 16usize { ret false }
    var i = 0usize
    while i < 8usize {
        if abs64(f64(got[i].x) - want[2usize * i]) > 0.002f64 || abs64(f64(got[i].y) - want[2usize * i + 1usize]) > 0.002f64 { ret false }
        i += 1usize
    }
    ret true
}

fn points_match(got: []const chart.Coord, want: []const f64) -> bool {
    if got.len * 2usize != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if abs64(f64(got[i].x) - want[2usize * i]) > 0.002f64 || abs64(f64(got[i].y) - want[2usize * i + 1usize]) > 0.002f64 { ret false }
        i += 1usize
    }
    ret true
}

fn depths_match(got: []const f64, want: []const f64) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if abs64(got[i] - want[i]) > 1e-12f64 { ret false }
        i += 1usize
    }
    ret true
}

fn same_order(got: []const usize, want: []const usize) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if got[i] != want[i] { ret false }
        i += 1usize
    }
    ret true
}

fn counts_match(got: []const u64, want: []const u64) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if got[i] != want[i] { ret false }
        i += 1usize
    }
    ret true
}

fn close_all(got: []const f64, want: []const f64, tolerance: f64) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if abs64(got[i] - want[i]) > tolerance * (1.0f64 + abs64(want[i])) { ret false }
        i += 1usize
    }
    ret true
}

fn density_min(values: []const f64) -> f64 {
    var m = values[0usize]
    var i = 1usize
    while i < values.len {
        if values[i] < m { m = values[i] }
        i += 1usize
    }
    ret m
}

fn density_max(values: []const f64) -> f64 {
    var m = values[0usize]
    var i = 1usize
    while i < values.len {
        if values[i] > m { m = values[i] }
        i += 1usize
    }
    ret m
}

fn main(a: *mem.Arena, args: []str) -> err {
    var s_points: [6]chart.Coord = zero
    var s_depths: [6]f64 = zero
    var s_order: [6]usize = zero
    var s_bubbles: [6]geometry.Rect = zero
    var s_corners: [8]chart.Coord = zero
    var s_edges: [12]chart.Segment = zero
    var scatter_storage = chart.Scatter3dStorage { points: s_points[..], depths: s_depths[..], order: s_order[..], bubbles: s_bubbles[..], corners: s_corners[..], edges: s_edges[..] }
    var u_points: [20]chart.Coord = zero
    var u_depths: [20]f64 = zero
    var u_face_vertices: [48]chart.Coord = zero
    var u_faces: [12]chart.Layout = zero
    var u_face_depths: [12]f64 = zero
    var u_face_values: [12]f64 = zero
    var u_order: [12]usize = zero
    var u_wires: [64]chart.Segment = zero
    var u_corners: [8]chart.Coord = zero
    var u_edges: [12]chart.Segment = zero
    var surface_storage = chart.Surface3dStorage { points: u_points[..], depths: u_depths[..], face_vertices: u_face_vertices[..], faces: u_faces[..], face_depths: u_face_depths[..], face_values: u_face_values[..], order: u_order[..], wires: u_wires[..], corners: u_corners[..], edges: u_edges[..] }
    var h_counts: [12]u64 = zero
    var h_cells: [12]chart.Cell = zero
    var h_vertices: [144]chart.Coord = zero
    var h_faces: [36]chart.Layout = zero
    var h_depths: [36]f64 = zero
    var h_order: [36]usize = zero
    var h_kinds: [36]chart.Histogram3dFace = zero
    var h_corners: [8]chart.Coord = zero
    var h_edges: [12]chart.Segment = zero
    var hist_storage = chart.Histogram3dStorage { counts: h_counts[..], cells: h_cells[..], vertices: h_vertices[..], faces: h_faces[..], depths: h_depths[..], order: h_order[..], face_kinds: h_kinds[..], corners: h_corners[..], edges: h_edges[..] }
@@BODY@@
    let (written, write_error) = os.write(os.stdout(), "gfx chart 3d reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_3d_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote gfx_chart_3d_reference with', code[0], 'checks')
