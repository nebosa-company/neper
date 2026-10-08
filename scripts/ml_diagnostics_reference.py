"""Write tests/selfhost/fixtures/link/gfx_chart_ml_diagnostics_reference/src/main.e (L092, D2260).

  python scripts/ml_diagnostics_reference.py

The ML-diagnostics plots against independent numpy computations on seeded data:
  * ice_curves: instance-major prediction matrices swept over an uneven grid; every curve segment, the
    partial-dependence mean and the y domain, plain and centred (c-ICE);
  * ml.cluster.silhouette_samples against a numpy pairwise-distance silhouette (and scikit-learn's when it
    is installed), including a singleton cluster, plus silhouette_plot's ordering, bars and mean line;
  * missingness_map: tile values, per-column missing fractions, and the all-missing and none-missing tables.
Refusals: a non-increasing grid, a NaN prediction (an all-missing sweep), length and storage mismatches,
an empty cluster, out-of-range labels, a single cluster, a score outside [-1, 1]. Each check has its own
exit code.
"""
import pathlib

import numpy as np

try:
    from sklearn.metrics import silhouette_samples as sk_silhouette
except Exception:  # scikit-learn is optional
    sk_silhouette = None

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]
rng = np.random.default_rng(20261013)


def check(condition):
    # the parser nests left-associative operators, so keep each chain well under its 128-level limit
    terms = condition.split(' || ')
    for k in range(0, len(terms), 12):
        code[0] += 1
        lines.append('    if %s { os.exit(%d) }' % (' || '.join(terms[k:k + 12]), code[0]))


def f64s(values):
    return ', '.join(repr(float(v)) + 'f64' for v in np.asarray(values).reshape(-1))


def usz(values):
    return ', '.join('%dusize' % v for v in values)


X, Y, W, H = 14.0, 22.0, 300.0, 180.0

# ---- ICE / PDP ----
instances = 8
grid = np.array([0.0, 0.5, 1.5, 2.0, 3.5, 4.0, 6.0])
a = rng.uniform(0.5, 2.0, instances)
b = rng.uniform(-1.0, 1.0, instances)
c = rng.uniform(-3.0, 3.0, instances)
pred = np.round(a[:, None] * np.sin(grid[None, :]) + b[:, None] * grid[None, :] + c[:, None], 6)
G = len(grid)
lines.append('    let grid = [%d]f64{ %s }' % (G, f64s(grid)))
lines.append('    let predictions = [%d]f64{ %s }' % (instances * G, f64s(pred)))
lines.append('    let ice_bounds = geometry.rect(%r, %r, %r, %r)' % (X, Y, W, H))
lines.append('    var ice_means: [%d]f64 = zero' % G)
lines.append('    var ice_curves: [%d]chart.Segment = zero' % (instances * (G - 1)))
lines.append('    var ice_mean_segments: [%d]chart.Segment = zero' % (G - 1))
for name, center in (('plain', False), ('centered', True)):
    shown = pred - pred[:, :1] if center else pred
    mean = shown.mean(axis=0)
    lo, hi = shown.min(), shown.max()
    lines.append('    let (ice_%s, ice_%s_error) = chart.ice_curves(predictions[..], %dusize, grid[..], %s, ice_bounds, ice_means[..], ice_curves[..], ice_mean_segments[..])' % (name, name, instances, 'true' if center else 'false'))
    check('ice_%s_error != ok || ice_%s.curves.segments.len != %dusize || ice_%s.mean.segments.len != %dusize' % (name, name, instances * (G - 1), name, G - 1))
    check(' || '.join('!close(ice_means[%d], %r)' % (j, float(mean[j])) for j in range(G)))
    check('!closef(ice_%s.y_min, %r) || !closef(ice_%s.y_max, %r) || !closef(ice_%s.curves.x_min, 0.0) || !closef(ice_%s.curves.x_max, 6.0)' % (name, float(lo), name, float(hi), name, name))
    span = grid[-1] - grid[0]

    def mx(v):
        return X + W * (v - grid[0]) / span

    def my(v):
        return Y + H - H * (v - lo) / (hi - lo)

    parts = []
    for i in range(instances):
        for j in range(G - 1):
            s = 'ice_curves[%d]' % (i * (G - 1) + j)
            parts.append('!closef(%s.from.x, %.4f) || !closef(%s.to.x, %.4f) || !closef(%s.from.y, %.4f) || !closef(%s.to.y, %.4f)' % (s, mx(grid[j]), s, mx(grid[j + 1]), s, my(shown[i, j]), s, my(shown[i, j + 1])))
    check(' || '.join(parts))
    check(' || '.join('!closef(ice_mean_segments[%d].from.y, %.4f) || !closef(ice_mean_segments[%d].to.y, %.4f)' % (j, my(mean[j]), j, my(mean[j + 1])) for j in range(G - 1)))
# a centred curve starts at zero, so the mean does too; the plain mean passes through the spread
lines.append('    let (ice_c, ice_c_error) = chart.ice_curves(predictions[..], %dusize, grid[..], true, ice_bounds, ice_means[..], ice_curves[..], ice_mean_segments[..])' % instances)
check('ice_c_error != ok || !close(ice_means[0], 0.0)')
# a flat sweep still gets a drawable domain
lines.append('    let flat = [%d]f64{ %s }' % (2 * G, f64s(np.full(2 * G, 3.0))))
lines.append('    let (ice_flat, ice_flat_error) = chart.ice_curves(flat[..], 2usize, grid[..], false, ice_bounds, ice_means[..], ice_curves[..], ice_mean_segments[..])')
check('ice_flat_error != ok || !closef(ice_flat.y_min, 2.5) || !closef(ice_flat.y_max, 3.5) || !closef(ice_flat.mean.segments[0].from.y, %.4f)' % (Y + H / 2))
lines.append('    let nan = 0.0f64 / zero_f64()')
lines.append('    var nan_predictions = predictions')
lines.append('    nan_predictions[10usize] = nan')
lines.append('    let (_, ice_nan) = chart.ice_curves(nan_predictions[..], %dusize, grid[..], false, ice_bounds, ice_means[..], ice_curves[..], ice_mean_segments[..])' % instances)
lines.append('    var all_nan: [%d]f64 = zero' % (instances * G))
lines.append('    var fill = 0usize')
lines.append('    while fill < %d {' % (instances * G))
lines.append('        all_nan[fill] = nan')
lines.append('        fill += 1usize')
lines.append('    }')
lines.append('    let (_, ice_all_missing) = chart.ice_curves(all_nan[..], %dusize, grid[..], false, ice_bounds, ice_means[..], ice_curves[..], ice_mean_segments[..])' % instances)
lines.append('    let descending = [%d]f64{ %s }' % (G, f64s(grid[::-1])))
lines.append('    let (_, ice_order) = chart.ice_curves(predictions[..], %dusize, descending[..], false, ice_bounds, ice_means[..], ice_curves[..], ice_mean_segments[..])' % instances)
lines.append('    let (_, ice_shape) = chart.ice_curves(predictions[..%dusize], %dusize, grid[..], false, ice_bounds, ice_means[..], ice_curves[..], ice_mean_segments[..])' % (instances * G - 1, instances))
lines.append('    let (_, ice_one_point) = chart.ice_curves(predictions[..1usize], 1usize, grid[..1usize], false, ice_bounds, ice_means[..], ice_curves[..], ice_mean_segments[..])')
lines.append('    let (_, ice_none) = chart.ice_curves(predictions[..0usize], 0usize, grid[..], false, ice_bounds, ice_means[..], ice_curves[..], ice_mean_segments[..])')
lines.append('    let (_, ice_room) = chart.ice_curves(predictions[..], %dusize, grid[..], false, ice_bounds, ice_means[..], ice_curves[..%dusize], ice_mean_segments[..])' % (instances, instances * (G - 1) - 1))
lines.append('    let (_, ice_mean_room) = chart.ice_curves(predictions[..], %dusize, grid[..], false, ice_bounds, ice_means[..], ice_curves[..], ice_mean_segments[..%dusize])' % (instances, G - 2))
lines.append('    let (_, ice_box) = chart.ice_curves(predictions[..], %dusize, grid[..], false, geometry.rect(0.0, 0.0, 0.0, 10.0), ice_means[..], ice_curves[..], ice_mean_segments[..])' % instances)
for term in ('ice_nan != chart.Invalid', 'ice_all_missing != chart.Invalid', 'ice_order != chart.Invalid', 'ice_shape != chart.Invalid', 'ice_one_point != chart.Invalid', 'ice_none != chart.Empty', 'ice_room != chart.TooLarge', 'ice_mean_room != chart.TooLarge', 'ice_box != chart.Invalid'):
    check(term)

# ---- silhouette ----
centres = np.array([[0.0, 0.0], [6.0, 1.0], [2.0, 7.0]])
pts = np.concatenate([rng.normal(centres[i], 1.1, (10, 2)) for i in range(3)] + [[[9.0, 9.0]]])
pts = np.round(pts, 4)
labels = np.array([0] * 10 + [1] * 10 + [2] * 10 + [3])
labels[3], labels[14] = 1, 0  # two points sit in the wrong cluster: negative silhouettes
n, k = len(pts), 4
dist = np.sqrt(((pts[:, None, :] - pts[None, :, :]) ** 2).sum(axis=2))
scores = np.zeros(n)
for i in range(n):
    own = labels == labels[i]
    if own.sum() == 1:
        continue
    a_i = dist[i, own & (np.arange(n) != i)].mean()
    b_i = min(dist[i, labels == j].mean() for j in range(k) if j != labels[i])
    top = max(a_i, b_i)
    scores[i] = (b_i - a_i) / top if top > 0 else 0.0
if sk_silhouette is not None:
    assert np.allclose(scores, sk_silhouette(pts, labels), atol=1e-12), 'numpy and scikit-learn silhouettes disagree'
assert scores.min() < 0 and scores[-1] == 0.0
lines.append('    let sil_points = [%d]f64{ %s }' % (n * 2, f64s(pts)))
lines.append('    let sil_labels = [%d]usize{ %s }' % (n, usz(labels)))
lines.append('    var sil_scores: [%d]f64 = zero' % n)
lines.append('    let (sil_mean, sil_error) = cluster.silhouette_samples(sil_points[..], %dusize, 2usize, sil_labels[..], 4usize, sil_scores[..])' % n)
check('sil_error != ok || !close(sil_mean, %r)' % float(scores.mean()))
check(' || '.join('!close1e12(sil_scores[%d], %r)' % (i, float(scores[i])) for i in range(n)))
check('sil_scores[%d] != 0.0f64 || sil_scores[3] >= 0.0f64 || sil_scores[14] >= 0.0f64' % (n - 1))
lines.append('    let sil_bounds = geometry.rect(%r, %r, %r, %r)' % (X, Y, W, H))
lines.append('    var sil_order: [%d]usize = zero' % n)
lines.append('    var sil_bars: [%d]geometry.Rect = zero' % n)
lines.append('    var sil_mean_line: [1]chart.Segment = zero')
lines.append('    let (sil_plot, sil_plot_error) = chart.silhouette_plot(sil_scores[..], sil_labels[..], 4usize, sil_bounds, sil_order[..], sil_bars[..], sil_mean_line[..])')
order = []
for cl in range(k):
    members = [i for i in range(n) if labels[i] == cl]
    order += sorted(members, key=lambda i: -scores[i])  # stable
rows = n + k - 1
rh = H / rows
zx = X + W / 2
check('sil_plot_error != ok || sil_plot.bars.len != %dusize' % n)
check(' || '.join('sil_order[%d] != %dusize' % (i, o) for i, o in enumerate(order)))
parts = []
row = 0
for bidx, sample in enumerate(order):
    if bidx > 0 and labels[order[bidx - 1]] != labels[sample]:
        row += 1
    edge = zx + W / 2 * scores[sample]
    left, right = min(edge, zx), max(edge, zx)
    parts.append('!closef(sil_bars[%d].x, %.4f) || !closef(sil_bars[%d].width, %.4f) || !closef(sil_bars[%d].y, %.4f) || !closef(sil_bars[%d].height, %.4f)' % (bidx, left, bidx, right - left, bidx, Y + row * rh, bidx, rh))
    row += 1
check(' || '.join(parts))
mean_x = zx + W / 2 * scores.mean()
check('!closef(sil_mean_line[0].from.x, %.4f) || !closef(sil_mean_line[0].to.x, %.4f) || !closef(sil_mean_line[0].from.y, %r) || !closef(sil_mean_line[0].to.y, %r)' % (mean_x, mean_x, Y, Y + H))
# the plot is blocked by cluster: a bar's top never precedes the previous cluster's bottom
check('sil_plot.y_max != %d.0f32 || sil_plot.x_min != -1.0f32 || sil_plot.x_max != 1.0f32' % rows)
lines.append('    let (_, sil_one) = cluster.silhouette_samples(sil_points[..], %dusize, 2usize, sil_labels[..], 1usize, sil_scores[..])' % n)
lines.append('    let (_, sil_empty) = cluster.silhouette_samples(sil_points[..], %dusize, 2usize, sil_labels[..], 5usize, sil_scores[..])' % n)
lines.append('    var sil_big = sil_labels')
lines.append('    sil_big[0usize] = 9usize')
lines.append('    let (_, sil_range) = cluster.silhouette_samples(sil_points[..], %dusize, 2usize, sil_big[..], 4usize, sil_scores[..])' % n)
lines.append('    let (_, sil_small) = cluster.silhouette_samples(sil_points[..], %dusize, 2usize, sil_labels[..], 4usize, sil_scores[..%dusize])' % (n, n - 1))
lines.append('    let (_, sil_shape) = cluster.silhouette_samples(sil_points[..%dusize], %dusize, 2usize, sil_labels[..], 4usize, sil_scores[..])' % (n * 2 - 1, n))
lines.append('    let (_, sil_alone) = cluster.silhouette_samples(sil_points[..2usize], 1usize, 2usize, sil_labels[..1usize], 2usize, sil_scores[..])')
for term in ('sil_one != cluster.Invalid', 'sil_empty != cluster.Invalid', 'sil_range != cluster.Invalid', 'sil_small != cluster.TooSmall', 'sil_shape != cluster.Invalid', 'sil_alone != cluster.Invalid'):
    check(term)
lines.append('    var bad_scores = sil_scores')
lines.append('    bad_scores[2usize] = 1.5')
lines.append('    let (_, plot_range) = chart.silhouette_plot(bad_scores[..], sil_labels[..], 4usize, sil_bounds, sil_order[..], sil_bars[..], sil_mean_line[..])')
lines.append('    let (_, plot_empty) = chart.silhouette_plot(sil_scores[..], sil_labels[..], 5usize, sil_bounds, sil_order[..], sil_bars[..], sil_mean_line[..])')
lines.append('    let (_, plot_one) = chart.silhouette_plot(sil_scores[..], sil_labels[..], 1usize, sil_bounds, sil_order[..], sil_bars[..], sil_mean_line[..])')
lines.append('    let (_, plot_none) = chart.silhouette_plot(sil_scores[..0usize], sil_labels[..0usize], 4usize, sil_bounds, sil_order[..], sil_bars[..], sil_mean_line[..])')
lines.append('    let (_, plot_room) = chart.silhouette_plot(sil_scores[..], sil_labels[..], 4usize, sil_bounds, sil_order[..], sil_bars[..%dusize], sil_mean_line[..])' % (n - 1))
lines.append('    let (_, plot_labels) = chart.silhouette_plot(sil_scores[..], sil_labels[..%dusize], 4usize, sil_bounds, sil_order[..], sil_bars[..], sil_mean_line[..])' % (n - 1))
for term in ('plot_range != chart.Invalid', 'plot_empty != chart.Invalid', 'plot_one != chart.Invalid', 'plot_none != chart.Empty', 'plot_room != chart.TooLarge', 'plot_labels != chart.Invalid'):
    check(term)

# ---- missingness map ----
R, C = 7, 5
present = rng.random((R, C)) > 0.3
present[:, 2] = True      # a complete column
present[:, 4] = False     # an empty column
present[0, 0] = False
lines.append('    let miss_present = [%d]bool{ %s }' % (R * C, ', '.join('true' if v else 'false' for v in present.reshape(-1))))
lines.append('    var miss_cells: [%d]chart.Cell = zero' % (R * C))
lines.append('    var miss_columns: [%d]f64 = zero' % C)
lines.append('    let miss_bounds = geometry.rect(%r, %r, %r, %r)' % (X, Y, W, H))
lines.append('    let (miss, miss_error) = chart.missingness_map(miss_present[..], %dusize, %dusize, miss_bounds, miss_cells[..], miss_columns[..])' % (R, C))
check('miss_error != ok || miss.rows != %dusize || miss.columns != %dusize || miss.cells.len != %dusize || !closef(miss.value_min, 0.0) || !closef(miss.value_max, 1.0)' % (R, C, R * C))
check(' || '.join('!close(miss_columns[%d], %r)' % (j, float((~present[:, j]).mean())) for j in range(C)))
check(' || '.join('!closef(miss_cells[%d].value, %r)' % (i, 0.0 if present.reshape(-1)[i] else 1.0) for i in range(R * C)))
parts = []
for i in range(R * C):
    col, row = i % C, i // C
    parts.append('miss_cells[%d].rect.x < %.4f || miss_cells[%d].rect.x + miss_cells[%d].rect.width > %.4f || miss_cells[%d].rect.y < %.4f || miss_cells[%d].rect.y + miss_cells[%d].rect.height > %.4f' % (i, X + W * col / C - 0.001, i, i, X + W * (col + 1) / C + 0.001, i, Y + H * row / R - 0.001, i, i, Y + H * (row + 1) / R + 0.001))
check(' || '.join(parts))
lines.append('    var all_missing: [6]bool = zero')
lines.append('    let (miss_all, miss_all_error) = chart.missingness_map(all_missing[..], 2usize, 3usize, miss_bounds, miss_cells[..], miss_columns[..])')
check('miss_all_error != ok || !closef(miss_all.value_min, 1.0) || !closef(miss_all.value_max, 1.0) || !close(miss_columns[0], 1.0) || !close(miss_columns[2], 1.0)')
lines.append('    let none_missing = [6]bool{ true, true, true, true, true, true }')
lines.append('    let (miss_none, miss_none_error) = chart.missingness_map(none_missing[..], 2usize, 3usize, miss_bounds, miss_cells[..], miss_columns[..])')
check('miss_none_error != ok || !closef(miss_none.value_min, 0.0) || !closef(miss_none.value_max, 0.0) || !close(miss_columns[1], 0.0)')
lines.append('    let (_, miss_shape) = chart.missingness_map(miss_present[..], %dusize, %dusize, miss_bounds, miss_cells[..], miss_columns[..])' % (R, C + 1))
lines.append('    let (_, miss_none_rows) = chart.missingness_map(miss_present[..0usize], 0usize, %dusize, miss_bounds, miss_cells[..], miss_columns[..])' % C)
lines.append('    let (_, miss_room) = chart.missingness_map(miss_present[..], %dusize, %dusize, miss_bounds, miss_cells[..%dusize], miss_columns[..])' % (R, C, R * C - 1))
lines.append('    let (_, miss_col_room) = chart.missingness_map(miss_present[..], %dusize, %dusize, miss_bounds, miss_cells[..], miss_columns[..%dusize])' % (R, C, C - 1))
lines.append('    let (_, miss_box) = chart.missingness_map(miss_present[..], %dusize, %dusize, geometry.rect(0.0, 0.0, -1.0, 5.0), miss_cells[..], miss_columns[..])' % (R, C))
for term in ('miss_shape != chart.Invalid', 'miss_none_rows != chart.Empty', 'miss_room != chart.TooLarge', 'miss_col_room != chart.TooLarge', 'miss_box != chart.Invalid'):
    check(term)

body = '\n'.join(lines)
source = '''// The ML-diagnostics plots against independent numpy computations on seeded data (L092, D2260;
// scripts/ml_diagnostics_reference.py writes this file): ICE curves and their partial-dependence mean (plain
// and centred), per-sample silhouettes and their bar layout, and the missingness map. Every check has its own
// exit code.
use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem
use e.ml.cluster as cluster
use e.os

fn zero_f64() -> f64 { ret 0.0f64 }

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn close(got: f64, want: f64) -> bool {
    ret abs64(got - want) <= 1e-9f64 * (1.0f64 + abs64(want))
}

fn close1e12(got: f64, want: f64) -> bool {
    ret abs64(got - want) <= 1e-12f64 * (1.0f64 + abs64(want))
}

fn closef(got: f32, want: f64) -> bool {
    ret abs64(f64(got) - want) <= 0.0006f64 * (1.0f64 + abs64(want))
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("gfx chart ml diagnostics reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_ml_diagnostics_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote', code[0], 'checks; sklearn cross-check', 'on' if sk_silhouette else 'off')
