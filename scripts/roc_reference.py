"""Write tests/selfhost/fixtures/link/gfx_chart_roc_reference/src/main.e (L096, D2264).

  python scripts/roc_reference.py

The ROC extensions against scikit-learn and numpy on one seeded 60-sample classifier with tied scores:
  * stat.binary_curve: every (tp, fp) point against sklearn.metrics.roc_curve(drop_intermediate=False);
  * roc_auc and average_precision against roc_auc_score and average_precision_score;
  * roc_partial_auc against a numpy interpolated trapezoid, and against sklearn's McClish-standardised
    roc_auc_score(max_fpr=...) after the standardisation is applied to the library's raw area;
  * youden_index against argmax(tpr - fpr) (the highest-score threshold on a tie);
  * decision_curve against the net-benefit formula in numpy;
  * binary_metric_curve (ROC, precision-recall, cumulative gain, lift) and roc_partial_region geometry,
    plus the invariant that the partial-region polygon's area is the raw partial AUC times the box area.
Refusals: one class, NaN scores, short storage, a cutoff outside (0, 1], thresholds not increasing or outside
(0, 1), scores outside [0, 1]. Each check has its own exit code.
"""
import math
import pathlib

import numpy as np
from sklearn.metrics import average_precision_score, roc_auc_score, roc_curve

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]
rng = np.random.default_rng(20261016)


def check(condition):
    terms = condition.split(' || ')
    for k in range(0, len(terms), 12):
        code[0] += 1
        lines.append('    if %s { os.exit(%d) }' % (' || '.join(terms[k:k + 12]), code[0]))


n = 60
labels = rng.random(n) < 0.38
scores = np.clip(np.where(labels, rng.normal(0.62, 0.22, n), rng.normal(0.38, 0.22, n)), 0.0, 1.0)
scores = np.round(scores, 2)
y = labels.astype(int)
P, N = int(y.sum()), int(n - y.sum())
assert P > 5 and N > 5
fpr, tpr, thr = roc_curve(y, scores, drop_intermediate=False)
tp = np.rint(tpr * P).astype(int)
fp = np.rint(fpr * N).astype(int)
m = len(tp)
auc = float(roc_auc_score(y, scores))
ap = float(average_precision_score(y, scores))
assert len(set(scores)) < n  # ties exist


def partial_raw(max_fpr):
    xs = [x for x in fpr if x < max_fpr] + [max_fpr]
    ys = list(tpr[: len(xs) - 1]) + [float(np.interp(max_fpr, fpr, tpr))]
    return float(np.trapezoid(ys, xs))


def mcclish(raw, max_fpr):
    return 0.5 * (1 + (raw - max_fpr * max_fpr / 2) / (max_fpr - max_fpr * max_fpr / 2))


lines.append('    let scores = [%d]f64{ %s }' % (n, ', '.join(repr(float(v)) + 'f64' for v in scores)))
lines.append('    let positive = [%d]bool{ %s }' % (n, ', '.join('true' if v else 'false' for v in labels)))
lines.append('    var order: [%d]usize = zero' % n)
lines.append('    var points: [%d]stat.BinaryPoint = zero' % (n + 1))
lines.append('    let (curve, curve_error) = stat.binary_curve(scores[..], positive[..], order[..], points[..])')
check('curve_error != ok || curve.positives != %dusize || curve.negatives != %dusize || curve.points.len != %dusize' % (P, N, m))
check(' || '.join('curve.points[%d].tp != %dusize || curve.points[%d].fp != %dusize' % (i, tp[i], i, fp[i]) for i in range(m)))
lines.append('    let (auc, auc_ok) = stat.roc_auc(&curve)')
lines.append('    let (ap, ap_ok) = stat.average_precision(&curve)')
check('!auc_ok || !ap_ok || !closed(auc, %r) || !closed(ap, %r)' % (auc, ap))
for cutoff in (0.1, 0.25, 0.4, 0.75, 1.0):
    raw = partial_raw(cutoff)
    if cutoff < 1.0:
        assert abs(mcclish(raw, cutoff) - roc_auc_score(y, scores, max_fpr=cutoff)) < 1e-9
    else:
        assert abs(raw - auc) < 1e-12
    name = 'pa_%d' % round(cutoff * 100)
    lines.append('    let (%s, %s_ok) = stat.roc_partial_auc(&curve, %rf64)' % (name, name, cutoff))
    check('!%s_ok || !closed(%s, %r)' % (name, name, raw))
    if cutoff < 1.0:
        check('!closed(0.5 * (1.0f64 + (%s - %r) / (%r)), %r)' % (name, cutoff * cutoff / 2, cutoff - cutoff * cutoff / 2, float(roc_auc_score(y, scores, max_fpr=cutoff))))
j = tpr - fpr
best = int(np.argmax(j[1:]) + 1)
lines.append('    let (youden_at, youden_value, youden_ok) = stat.youden_index(&curve)')
check('!youden_ok || youden_at != %dusize || !closed(youden_value, %r)' % (best, float(j[best])))
check('curve.points[youden_at].tp != %dusize || curve.points[youden_at].fp != %dusize' % (tp[best], fp[best]))
# the Youden threshold sits at a score present in the data, the highest one reaching that J
assert thr[best] in set(scores)

# decision curve
thresholds = [0.1, 0.2, 0.3, 0.45, 0.6, 0.75, 0.9]
nb, nb_all = [], []
for t in thresholds:
    pred = scores >= t
    tpc = int(np.sum(pred & labels))
    fpc = int(np.sum(pred & ~labels))
    w = t / (1 - t)
    nb.append((tpc - fpc * w) / n)
    nb_all.append((P - N * w) / n)
lines.append('    let thresholds = [%d]f64{ %s }' % (len(thresholds), ', '.join(repr(t) + 'f64' for t in thresholds)))
lines.append('    var model_benefit: [%d]f64 = zero' % len(thresholds))
lines.append('    var all_benefit: [%d]f64 = zero' % len(thresholds))
lines.append('    let decision_error = stat.decision_curve(scores[..], positive[..], thresholds[..], model_benefit[..], all_benefit[..])')
check('decision_error != ok')
check(' || '.join('!closed(model_benefit[%d], %r) || !closed(all_benefit[%d], %r)' % (i, nb[i], i, nb_all[i]) for i in range(len(thresholds))))

# chart geometry
lines.append('    let bounds = geometry.rect(14.0, 22.0, 300.0, 170.0)')
lines.append('    var gx: [%d]f32 = zero' % m)
lines.append('    var gy: [%d]f32 = zero' % m)
lines.append('    var gseg: [%d]chart.Segment = zero' % (m - 1))
X, Y, W, H = 14.0, 22.0, 300.0, 170.0
total = n
prev = P / n
metrics = {}
for name, enum in (('roc', 'Roc'), ('pr', 'PrecisionRecall'), ('gain', 'CumulativeGain'), ('lift', 'Lift')):
    xs, ys = [], []
    for i in range(m):
        sel = tp[i] + fp[i]
        if enum == 'Roc':
            xs.append(fp[i] / N)
            ys.append(tp[i] / P)
        elif enum == 'PrecisionRecall':
            xs.append(tp[i] / P)
            ys.append(1.0 if sel == 0 else tp[i] / sel)
        elif enum == 'CumulativeGain':
            xs.append(sel / total)
            ys.append(tp[i] / P)
        else:
            xs.append(sel / total)
            ys.append(1.0 if sel == 0 else (tp[i] / sel) / prev)
    ymax = max(1.0, max(ys))
    metrics[name] = (xs, ys, ymax)
    lines.append('    let (%s_layout, %s_error) = chart.binary_metric_curve(&curve, .%s, bounds, gx[..], gy[..], gseg[..])' % (name, name, enum))
    check('%s_error != ok || %s_layout.segments.len != %dusize' % (name, name, m - 1))
    check('!closef(%s_layout.y_max, %r) || !closef(%s_layout.x_min, 0.0) || !closef(%s_layout.x_max, 1.0)' % (name, ymax, name, name))
    parts = []
    for i in range(m - 1):
        parts.append('!closef(%s_layout.segments[%d].from.x, %.4f) || !closef(%s_layout.segments[%d].from.y, %.4f) || !closef(%s_layout.segments[%d].to.x, %.4f) || !closef(%s_layout.segments[%d].to.y, %.4f)' % (
            name, i, X + W * xs[i], name, i, Y + H - H * ys[i] / ymax, name, i, X + W * xs[i + 1], name, i, Y + H - H * ys[i + 1] / ymax))
    check(' || '.join(parts))
    # the lift of the whole sample is one and the gain at full selection is one
    if enum in ('CumulativeGain', 'Lift'):
        last = ys[-1]
        check('!closef(gy[%d], %r)' % (m - 1, float(last)))

# partial region: replay the library's loop literally
def region(max_fpr):
    pts = [(X, Y + H)]
    for i in range(m):
        x, yv = fp[i] / N, tp[i] / P
        if x <= max_fpr:
            pts.append((X + W * x, Y + H - H * yv))
        else:
            x0, y0 = fp[i - 1] / N, tp[i - 1] / P
            y_stop = y0 + (yv - y0) * (max_fpr - x0) / (x - x0)
            pts.append((X + W * max_fpr, Y + H - H * y_stop))
            break
    pts.append((X + W * max_fpr, Y + H))
    return pts


def shoelace(pts):
    s = 0.0
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        s += a[0] * b[1] - b[0] * a[1]
    return float(abs(s) / 2)


lines.append('    var region_points: [%d]chart.Coord = zero' % (m + 2))
for cutoff in (0.2, 0.5, 1.0):
    pts = region(cutoff)
    name = 'region_%d' % round(cutoff * 100)
    lines.append('    let (%s, %s_error) = chart.roc_partial_region(&curve, %rf32, bounds, region_points[..])' % (name, name, cutoff))
    check('%s_error != ok || %s.coords.len != %dusize' % (name, name, len(pts)))
    check(' || '.join('!closef(%s.coords[%d].x, %.4f) || !closef(%s.coords[%d].y, %.4f)' % (name, i, p[0], name, i, p[1]) for i, p in enumerate(pts)))
    # the polygon's area is the raw partial AUC times the box area, by an independent shoelace sum
    area = shoelace(pts)
    assert abs(area / (W * H) - partial_raw(cutoff)) < 1e-6 or cutoff == 1.0 and abs(area / (W * H) - auc) < 1e-6
    check('!closef(shoelace(%s.coords) / %r, %r)' % (name, W * H, area / (W * H)))

# refusals
lines.append('    let one_class = [%d]bool{ %s }' % (n, ', '.join('true' for _ in range(n))))
lines.append('    let (_, one_class_error) = stat.binary_curve(scores[..], one_class[..], order[..], points[..])')
lines.append('    let nan = 0.0f64 / zero_f64()')
lines.append('    var nan_scores = scores')
lines.append('    nan_scores[7usize] = nan')
lines.append('    let (_, nan_error) = stat.binary_curve(nan_scores[..], positive[..], order[..], points[..])')
lines.append('    let (_, short_labels) = stat.binary_curve(scores[..], positive[..%dusize], order[..], points[..])' % (n - 1))
lines.append('    let (_, short_order) = stat.binary_curve(scores[..], positive[..], order[..%dusize], points[..])' % (n - 1))
lines.append('    let (_, short_points) = stat.binary_curve(scores[..], positive[..], order[..], points[..%dusize])' % m)
lines.append('    let (_, none_error) = stat.binary_curve(scores[..0usize], positive[..0usize], order[..], points[..])')
check('one_class_error != stat.Invalid || nan_error != stat.Invalid || short_labels != stat.Invalid || short_order != stat.TooSmall || short_points != stat.TooSmall || none_error != stat.Invalid')
lines.append('    let (_, cut_zero_ok) = stat.roc_partial_auc(&curve, 0.0f64)')
lines.append('    let (_, cut_big_ok) = stat.roc_partial_auc(&curve, 1.01f64)')
lines.append('    let (_, cut_nan_ok) = stat.roc_partial_auc(&curve, nan)')
check('cut_zero_ok || cut_big_ok || cut_nan_ok')
lines.append('    let (_, region_zero) = chart.roc_partial_region(&curve, 0.0f32, bounds, region_points[..])')
lines.append('    let (_, region_big) = chart.roc_partial_region(&curve, 1.5f32, bounds, region_points[..])')
lines.append('    let (_, region_room) = chart.roc_partial_region(&curve, 0.5f32, bounds, region_points[..%dusize])' % (m - 1))
lines.append('    let (_, region_bounds) = chart.roc_partial_region(&curve, 0.5f32, geometry.Rect { x: 0.0, y: 0.0, width: 0.0, height: 5.0 }, region_points[..])')
check('region_zero != chart.Invalid || region_big != chart.Invalid || region_room != chart.TooLarge || region_bounds != chart.Invalid')
lines.append('    let (_, metric_room_x) = chart.binary_metric_curve(&curve, .Roc, bounds, gx[..%dusize], gy[..], gseg[..])' % (m - 1))
lines.append('    let (_, metric_room_y) = chart.binary_metric_curve(&curve, .Lift, bounds, gx[..], gy[..%dusize], gseg[..])' % (m - 1))
lines.append('    let (_, metric_room_s) = chart.binary_metric_curve(&curve, .PrecisionRecall, bounds, gx[..], gy[..], gseg[..%dusize])' % (m - 3))
lines.append('    let (_, metric_bounds) = chart.binary_metric_curve(&curve, .Roc, geometry.Rect { x: 0.0, y: 0.0, width: -1.0, height: 5.0 }, gx[..], gy[..], gseg[..])')
check('metric_room_x != chart.TooLarge || metric_room_y != chart.TooLarge || metric_room_s != chart.TooLarge || metric_bounds != chart.Invalid')
lines.append('    let bad_thr_order = [3]f64{ 0.5, 0.3, 0.7 }')
lines.append('    let bad_thr_zero = [3]f64{ 0.0, 0.3, 0.7 }')
lines.append('    let bad_thr_one = [3]f64{ 0.3, 0.7, 1.0 }')
lines.append('    let bad_thr_dup = [3]f64{ 0.3, 0.3, 0.7 }')
lines.append('    let out_scores = [3]f64{ 0.2, 1.4, 0.6 }')
lines.append('    let out_labels = [3]bool{ true, false, true }')
lines.append('    let ok_thr = [2]f64{ 0.3, 0.6 }')
lines.append('    let d_order = stat.decision_curve(scores[..], positive[..], bad_thr_order[..], model_benefit[..], all_benefit[..])')
lines.append('    let d_zero = stat.decision_curve(scores[..], positive[..], bad_thr_zero[..], model_benefit[..], all_benefit[..])')
lines.append('    let d_one = stat.decision_curve(scores[..], positive[..], bad_thr_one[..], model_benefit[..], all_benefit[..])')
lines.append('    let d_dup = stat.decision_curve(scores[..], positive[..], bad_thr_dup[..], model_benefit[..], all_benefit[..])')
lines.append('    let d_scores = stat.decision_curve(out_scores[..], out_labels[..], ok_thr[..], model_benefit[..], all_benefit[..])')
lines.append('    let d_short = stat.decision_curve(scores[..], positive[..], thresholds[..], model_benefit[..3usize], all_benefit[..])')
lines.append('    let d_none = stat.decision_curve(scores[..0usize], positive[..0usize], thresholds[..], model_benefit[..], all_benefit[..])')
lines.append('    let d_shape = stat.decision_curve(scores[..], positive[..%dusize], thresholds[..], model_benefit[..], all_benefit[..])' % (n - 1))
check('d_order != stat.Invalid || d_zero != stat.Invalid || d_one != stat.Invalid || d_dup != stat.Invalid || d_scores != stat.Invalid || d_short != stat.TooSmall || d_none != stat.Invalid || d_shape != stat.Invalid')

import re

# numpy scalars print as np.float64(x); the generated Neper wants the bare number
body = re.sub(r'np\.float64\(([^)]*)\)', r'\1', '\n'.join(line for line in lines if line))
source = '''// The ROC extensions against scikit-learn and numpy on one seeded 60-sample classifier with tied scores
// (L096, D2264; scripts/roc_reference.py writes this file): the threshold sweep, AUC, average precision,
// raw and McClish-standardised partial AUC, the Youden point, net-benefit decision curves, the four metric
// curves and the partial-region polygon (its area is the raw partial AUC times the box), and every refusal.
// Every check has its own exit code.
use e.algo.stat
use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem
use e.os

fn zero_f64() -> f64 { ret 0.0f64 }

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn closed(got: f64, want: f64) -> bool {
    ret abs64(got - want) <= 1e-9f64 * (1.0f64 + abs64(want))
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

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("gfx chart roc reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_roc_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote', code[0], 'checks; AUC %.4f AP %.4f, %d curve points, P=%d N=%d' % (auc, ap, m, P, N))
