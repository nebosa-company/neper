"""Write tests/selfhost/fixtures/link/gfx_chart_report_reference/src/main.e (L075, D2259).

  python scripts/chart_report_reference.py

The paginated-report compositions of e.gfx.chart against an independent numpy replay on seeded fact tables:
cross_tab_report (counts, marginals, grand total, display grid and cell rectangles), matrix_report (sums and
observed counts with missing facts and never-observed cells, group subtotals, row and column totals, the
grand total, header cells, and the data bars under the Row, Global and None scopes), in_cell_bars (one
shared maximum, inset), and sparkline (even spacing, min/max mapping to the box). Refusals: out-of-range
ids, a non-contiguous group list, a negative sum under a bar scope, a grid too small, short storage, bars
above the maximum. Each check has its own exit code.
"""
import pathlib

import numpy as np

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]
rng = np.random.default_rng(20261012)


def check(condition):
    # the parser nests left-associative operators, so keep each chain well under its 128-level limit
    terms = condition.split(' || ')
    for k in range(0, len(terms), 12):
        code[0] += 1
        lines.append('    if %s { os.exit(%d) }' % (' || '.join(terms[k:k + 12]), code[0]))


def usz(values):
    return ', '.join('%dusize' % v for v in values)


X, Y, W, H, HW = 12.0, 24.0, 420.0, 300.0, 90.0


def rect_for(row, column, rows_total, columns):
    body = (W - HW) / (columns + 1)
    rh = H / (rows_total + 2)
    x, w = X, HW
    if column > 0:
        x, w = X + HW + (column - 1) * body, body
    return (x + 0.5, Y + row * rh + 0.5, w - 1.0, rh - 1.0)


def rect_check(cell, r):
    return '!closef(%s.rect.x, %.4f) || !closef(%s.rect.y, %.4f) || !closef(%s.rect.width, %.4f) || !closef(%s.rect.height, %.4f)' % (cell, r[0], cell, r[1], cell, r[2], cell, r[3])


# ---- cross tab ----
rows, columns = 4, 3
n = 70
row_ids = rng.integers(0, rows, n)
col_ids = rng.integers(0, columns, n)
counts = np.zeros((rows, columns), dtype=int)
for r, c in zip(row_ids, col_ids):
    counts[r, c] += 1
lines.append('    let ct_rows = [%d]usize{ %s }' % (n, usz(row_ids)))
lines.append('    let ct_columns = [%d]usize{ %s }' % (n, usz(col_ids)))
lines.append('    var ct_counts: [12]u64 = zero')
lines.append('    var ct_row_totals: [4]u64 = zero')
lines.append('    var ct_column_totals: [3]u64 = zero')
lines.append('    var ct_cells: [30]chart.ReportCell = zero')
lines.append('    var ct_work = chart.CrossTabStorage { counts: ct_counts[..], row_totals: ct_row_totals[..], column_totals: ct_column_totals[..], cells: ct_cells[..] }')
lines.append('    let report_bounds = geometry.rect(%s, %s, %s, %s)' % (X, Y, W, H))
lines.append('    let (ct, ct_error) = chart.cross_tab_report(ct_rows[..], ct_columns[..], 4usize, 3usize, report_bounds, %s, &ct_work)' % HW)
check('ct_error != ok || ct.display_rows != 6usize || ct.display_columns != 5usize || ct.summary.total != %du64' % n)
parts = []
for r in range(rows):
    for c in range(columns):
        parts.append('ct_counts[%d] != %du64' % (r * columns + c, counts[r, c]))
check(' || '.join(parts))
check(' || '.join('ct_row_totals[%d] != %du64' % (r, counts[r].sum()) for r in range(rows)) + ' || ' + ' || '.join('ct_column_totals[%d] != %du64' % (c, counts[:, c].sum()) for c in range(columns)))
parts = []
for dr in range(rows + 2):
    for dc in range(columns + 2):
        i = dr * (columns + 2) + dc
        r = rect_for(dr, dc, rows, columns)
        parts.append(rect_check('ct.cells[%d]' % i, r))
        if 1 <= dr <= rows and 1 <= dc <= columns:
            parts.append('ct.cells[%d].kind != .Body || ct.cells[%d].value != %.1ff64' % (i, i, counts[dr - 1, dc - 1]))
        elif 1 <= dr <= rows and dc == columns + 1:
            parts.append('ct.cells[%d].kind != .RowTotal || ct.cells[%d].value != %.1ff64' % (i, i, counts[dr - 1].sum()))
        elif dr == rows + 1 and 1 <= dc <= columns:
            parts.append('ct.cells[%d].kind != .ColumnTotal || ct.cells[%d].value != %.1ff64' % (i, i, counts[:, dc - 1].sum()))
        elif dr == rows + 1 and dc == columns + 1:
            parts.append('ct.cells[%d].kind != .GrandTotal || ct.cells[%d].value != %.1ff64' % (i, i, counts.sum()))
        elif dr == 0:
            parts.append('ct.cells[%d].kind != %s' % (i, '.Corner' if dc == 0 else '.ColumnHeader'))
        elif dc == 0 and 1 <= dr <= rows:
            parts.append('ct.cells[%d].kind != .RowHeader' % i)
check(' || '.join(parts))
lines.append('    let ct_bad_ids = [2]usize{ 0usize, 4usize }')
lines.append('    let ct_zero_ids = [2]usize{ 0usize, 0usize }')
lines.append('    let (_, ct_range) = chart.cross_tab_report(ct_bad_ids[..], ct_zero_ids[..], 4usize, 3usize, report_bounds, %s, &ct_work)' % HW)
lines.append('    let (_, ct_narrow) = chart.cross_tab_report(ct_rows[..], ct_columns[..], 4usize, 3usize, report_bounds, 400.0, &ct_work)')
lines.append('    let (_, ct_tiny) = chart.cross_tab_report(ct_rows[..], ct_columns[..], 4usize, 3usize, geometry.rect(0.0, 0.0, 420.0, 40.0), %s, &ct_work)' % HW)
lines.append('    var ct_small_cells: [29]chart.ReportCell = zero')
lines.append('    var ct_small = chart.CrossTabStorage { counts: ct_counts[..], row_totals: ct_row_totals[..], column_totals: ct_column_totals[..], cells: ct_small_cells[..] }')
lines.append('    let (_, ct_room) = chart.cross_tab_report(ct_rows[..], ct_columns[..], 4usize, 3usize, report_bounds, %s, &ct_small)' % HW)
check('ct_range == ok')
check('ct_narrow != chart.Invalid')
check('ct_tiny != chart.Invalid')
check('ct_room != chart.TooLarge')

# ---- matrix report ----
M_ROWS, M_COLS = 5, 4
groups = [0, 0, 1, 1, 2]
G = 3
facts = 90
f_rows = rng.integers(0, M_ROWS, facts)
f_cols = rng.integers(0, M_COLS, facts)
f_vals = np.round(rng.uniform(1.0, 40.0, facts), 2)
f_present = rng.random(facts) > 0.2
# a never-observed column in row 3 and a zero-sum observed cell
mask = ~((f_rows == 3) & (f_cols == 1))
f_rows, f_cols, f_vals, f_present = f_rows[mask], f_cols[mask], f_vals[mask], f_present[mask]
f_vals[0], f_rows[0], f_cols[0], f_present[0] = 0.0, 4, 3, True
facts = len(f_rows)
sums = np.zeros((M_ROWS, M_COLS))
cnts = np.zeros((M_ROWS, M_COLS), dtype=int)
for r, c, v, p in zip(f_rows, f_cols, f_vals, f_present):
    if p:
        sums[r, c] += v
        cnts[r, c] += 1
lines.append('    let mx_rows = [%d]usize{ %s }' % (facts, usz(f_rows)))
lines.append('    let mx_columns = [%d]usize{ %s }' % (facts, usz(f_cols)))
lines.append('    let mx_values = [%d]f64{ %s }' % (facts, ', '.join(repr(float(v)) + 'f64' for v in f_vals)))
lines.append('    let mx_present = [%d]bool{ %s }' % (facts, ', '.join('true' if p else 'false' for p in f_present)))
lines.append('    let mx_groups = [%d]usize{ %s }' % (M_ROWS, usz(groups)))
lines.append('    var mx_aggregates: [%d]stat.ReportAggregate = zero' % (M_ROWS * M_COLS))
lines.append('    var mx_row_totals: [%d]stat.ReportAggregate = zero' % M_ROWS)
lines.append('    var mx_column_totals: [%d]stat.ReportAggregate = zero' % M_COLS)
lines.append('    var mx_group_aggregates: [%d]stat.ReportAggregate = zero' % (G * M_COLS))
lines.append('    var mx_group_totals: [%d]stat.ReportAggregate = zero' % G)
display_rows = M_ROWS + G + 2
display_cols = M_COLS + 2
lines.append('    var mx_cells: [%d]chart.ReportCell = zero' % (display_rows * display_cols))
lines.append('    var mx_work = chart.MatrixReportStorage { aggregates: mx_aggregates[..], row_totals: mx_row_totals[..], column_totals: mx_column_totals[..], group_aggregates: mx_group_aggregates[..], group_totals: mx_group_totals[..], cells: mx_cells[..] }')

row_sum = sums.sum(axis=1)
row_cnt = cnts.sum(axis=1)
col_sum = sums.sum(axis=0)
col_cnt = cnts.sum(axis=0)
grp_sum = np.array([sums[[i for i in range(M_ROWS) if groups[i] == g]].sum(axis=0) for g in range(G)])
grp_cnt = np.array([cnts[[i for i in range(M_ROWS) if groups[i] == g]].sum(axis=0) for g in range(G)])
grp_tot = grp_sum.sum(axis=1)
grp_tot_cnt = grp_cnt.sum(axis=1)

# display layout: header, then each leaf row, with a subtotal after the last row of a group, then totals
layout = [('header', None)]
for r in range(M_ROWS):
    layout.append(('row', r))
    if r == M_ROWS - 1 or groups[r + 1] != groups[r]:
        layout.append(('sub', groups[r]))
layout.append(('total', None))
assert len(layout) == display_rows

row_max = [max([sums[r, c] for c in range(M_COLS) if cnts[r, c] > 0] + [0.0]) for r in range(M_ROWS)]
global_max = max(sums[cnts > 0].max(), 0.0)

for scope in ('None', 'Row', 'Global'):
    var = 'mx_' + scope.lower()
    lines.append('    let (%s, %s_error) = chart.matrix_report(mx_rows[..], mx_columns[..], mx_values[..], mx_present[..], mx_groups[..], %dusize, %dusize, report_bounds, %s, .%s, &mx_work)' % (var, var, M_ROWS, M_COLS, HW, scope))
    check('%s_error != ok || %s.display_rows != %dusize || %s.display_columns != %dusize || %s.group_count != %dusize' % (var, var, display_rows, var, display_cols, var, G))
    if scope == 'None':
        check('%s.grand.count != %dusize || !close(%s.grand.sum, %r)' % (var, int(cnts.sum()), var, float(sums.sum())))
        # aggregates and totals in caller storage
        parts = []
        for r in range(M_ROWS):
            for c in range(M_COLS):
                parts.append('!close(mx_aggregates[%d].sum, %r) || mx_aggregates[%d].count != %dusize' % (r * M_COLS + c, float(sums[r, c]), r * M_COLS + c, cnts[r, c]))
        check(' || '.join(parts))
        check(' || '.join('!close(mx_row_totals[%d].sum, %r) || mx_row_totals[%d].count != %dusize' % (r, float(row_sum[r]), r, row_cnt[r]) for r in range(M_ROWS)) + ' || ' + ' || '.join('!close(mx_column_totals[%d].sum, %r) || mx_column_totals[%d].count != %dusize' % (c, float(col_sum[c]), c, col_cnt[c]) for c in range(M_COLS)))
        check(' || '.join('!close(mx_group_totals[%d].sum, %r) || mx_group_totals[%d].count != %dusize' % (g, float(grp_tot[g]), g, grp_tot_cnt[g]) for g in range(G)))
    parts = []
    for dr, (kind, idx) in enumerate(layout):
        for dc in range(display_cols):
            i = dr * display_cols + dc
            cell = '%s.cells[%d]' % (var, i)
            parts.append(rect_check(cell, rect_for(dr, dc, M_ROWS + G, M_COLS)))
            if kind == 'header':
                parts.append('%s.kind != %s || %s.present' % (cell, '.Corner' if dc == 0 else '.ColumnHeader', cell))
            elif kind == 'row':
                if dc == 0:
                    parts.append('%s.kind != .RowHeader || %s.source != %dusize' % (cell, cell, idx))
                elif dc == display_cols - 1:
                    parts.append('%s.kind != .RowTotal || !close(%s.value, %r) || %s.present != %s' % (cell, cell, float(row_sum[idx]), cell, 'true' if row_cnt[idx] > 0 else 'false'))
                else:
                    c = dc - 1
                    present = cnts[idx, c] > 0
                    parts.append('%s.kind != .Body || !close(%s.value, %r) || %s.present != %s' % (cell, cell, float(sums[idx, c]), cell, 'true' if present else 'false'))
                    r_ = rect_for(dr, dc, M_ROWS + G, M_COLS)
                    denominator = {'None': 0.0, 'Row': row_max[idx], 'Global': global_max}[scope]
                    if present and sums[idx, c] > 0 and denominator > 0:
                        bar = (r_[0] + 3.0, r_[1] + r_[3] * 0.65, (r_[2] - 6.0) * (sums[idx, c] / denominator), r_[3] * 0.22)
                        parts.append('!closef(%s.bar.x, %.4f) || !closef(%s.bar.y, %.4f) || !closef(%s.bar.width, %.4f) || !closef(%s.bar.height, %.4f)' % (cell, bar[0], cell, bar[1], cell, bar[2], cell, bar[3]))
                    else:
                        parts.append('%s.bar.width != 0.0 || %s.bar.height != 0.0' % (cell, cell))
            elif kind == 'sub':
                if dc == 0:
                    parts.append('%s.kind != .GroupSubtotal' % cell)
                elif dc == display_cols - 1:
                    parts.append('%s.kind != .GroupSubtotal || !close(%s.value, %r) || %s.source != %dusize' % (cell, cell, float(grp_tot[idx]), cell, idx))
                else:
                    parts.append('%s.kind != .GroupSubtotal || !close(%s.value, %r) || %s.present != %s' % (cell, cell, float(grp_sum[idx, dc - 1]), cell, 'true' if grp_cnt[idx, dc - 1] > 0 else 'false'))
            else:
                if dc == display_cols - 1:
                    parts.append('%s.kind != .GrandTotal || !close(%s.value, %r)' % (cell, cell, float(sums.sum())))
                elif dc > 0:
                    parts.append('%s.kind != .ColumnTotal || !close(%s.value, %r)' % (cell, cell, float(col_sum[dc - 1])))
    # split into chunks so one expression stays small
    for k in range(0, len(parts), 40):
        check(' || '.join(parts[k:k + 40]))

# ---- matrix refusals ----
lines.append('    let mx_gap_groups = [%d]usize{ 0usize, 0usize, 2usize, 2usize, 2usize }' % M_ROWS)
lines.append('    let (_, mx_gap) = chart.matrix_report(mx_rows[..], mx_columns[..], mx_values[..], mx_present[..], mx_gap_groups[..], %dusize, %dusize, report_bounds, %s, .None, &mx_work)' % (M_ROWS, M_COLS, HW))
lines.append('    let mx_back_groups = [%d]usize{ 0usize, 1usize, 0usize, 1usize, 1usize }' % M_ROWS)
lines.append('    let (_, mx_back) = chart.matrix_report(mx_rows[..], mx_columns[..], mx_values[..], mx_present[..], mx_back_groups[..], %dusize, %dusize, report_bounds, %s, .None, &mx_work)' % (M_ROWS, M_COLS, HW))
lines.append('    let mx_first_groups = [%d]usize{ 1usize, 1usize, 1usize, 1usize, 1usize }' % M_ROWS)
lines.append('    let (_, mx_first) = chart.matrix_report(mx_rows[..], mx_columns[..], mx_values[..], mx_present[..], mx_first_groups[..], %dusize, %dusize, report_bounds, %s, .None, &mx_work)' % (M_ROWS, M_COLS, HW))
lines.append('    let mx_negative = [2]f64{ -3.0, 4.0 }')
lines.append('    let mx_two_rows = [2]usize{ 0usize, 1usize }')
lines.append('    let mx_two_columns = [2]usize{ 0usize, 1usize }')
lines.append('    let mx_two_present = [2]bool{ true, true }')
lines.append('    let mx_two_groups = [2]usize{ 0usize, 0usize }')
lines.append('    let (_, mx_neg_row) = chart.matrix_report(mx_two_rows[..], mx_two_columns[..], mx_negative[..], mx_two_present[..], mx_two_groups[..], 2usize, 2usize, report_bounds, %s, .Row, &mx_work)' % HW)
lines.append('    let (_, mx_neg_none) = chart.matrix_report(mx_two_rows[..], mx_two_columns[..], mx_negative[..], mx_two_present[..], mx_two_groups[..], 2usize, 2usize, report_bounds, %s, .None, &mx_work)' % HW)
lines.append('    let mx_out_rows = [2]usize{ 0usize, 9usize }')
lines.append('    let (_, mx_range) = chart.matrix_report(mx_out_rows[..], mx_two_columns[..], mx_negative[..], mx_two_present[..], mx_two_groups[..], 2usize, 2usize, report_bounds, %s, .None, &mx_work)' % HW)
lines.append('    let (_, mx_empty) = chart.matrix_report(mx_rows[..], mx_columns[..], mx_values[..], mx_present[..], mx_groups[..0usize], 0usize, %dusize, report_bounds, %s, .None, &mx_work)' % (M_COLS, HW))
lines.append('    var mx_tiny_cells: [%d]chart.ReportCell = zero' % (display_rows * display_cols - 1))
lines.append('    var mx_tiny = chart.MatrixReportStorage { aggregates: mx_aggregates[..], row_totals: mx_row_totals[..], column_totals: mx_column_totals[..], group_aggregates: mx_group_aggregates[..], group_totals: mx_group_totals[..], cells: mx_tiny_cells[..] }')
lines.append('    let (_, mx_room) = chart.matrix_report(mx_rows[..], mx_columns[..], mx_values[..], mx_present[..], mx_groups[..], %dusize, %dusize, report_bounds, %s, .None, &mx_tiny)' % (M_ROWS, M_COLS, HW))
for term in ('mx_gap != chart.Invalid', 'mx_back != chart.Invalid', 'mx_first != chart.Invalid', 'mx_neg_row != chart.Invalid', 'mx_neg_none != ok', 'mx_range == ok', 'mx_empty != chart.Invalid', 'mx_room != chart.TooLarge'):
    check(term)

# ---- in-cell bars ----
cell_count = 7
cells = []
for i in range(cell_count):
    cells.append((10.0 + 40.0 * (i % 3), 20.0 + 18.0 * (i // 3), 36.0, 14.0))
vals = np.round(rng.uniform(0.0, 50.0, cell_count), 2)
vals[2] = 0.0
vals[5] = 50.0
inset = 2.0
lines.append('    let bar_values = [%d]f32{ %s }' % (cell_count, ', '.join('%rf32' % float(v) for v in vals)))
lines.append('    let bar_cells = [%d]geometry.Rect{ %s }' % (cell_count, ', '.join('geometry.rect(%r, %r, %r, %r)' % c for c in cells)))
lines.append('    var bar_storage: [%d]geometry.Rect = zero' % cell_count)
lines.append('    let (cell_bars, cell_bars_error) = chart.in_cell_bars(bar_values[..], 50.0, bar_cells[..], %r, bar_storage[..])' % inset)
check('cell_bars_error != ok || cell_bars.bars.len != %dusize' % cell_count)
parts = []
for i, (cx, cy, cw, ch) in enumerate(cells):
    parts.append('!closef(bar_storage[%d].x, %.4f) || !closef(bar_storage[%d].y, %.4f) || !closef(bar_storage[%d].width, %.4f) || !closef(bar_storage[%d].height, %.4f)' % (i, cx + inset, i, cy + inset, i, (cw - 2 * inset) * vals[i] / 50.0, i, ch - 2 * inset))
check(' || '.join(parts))
lines.append('    let over = [1]f32{ 51.0 }')
lines.append('    let one_cell = [1]geometry.Rect{ geometry.rect(0.0, 0.0, 30.0, 10.0) }')
lines.append('    let (_, bar_over) = chart.in_cell_bars(over[..], 50.0, one_cell[..], 1.0, bar_storage[..])')
lines.append('    let under = [1]f32{ -1.0 }')
lines.append('    let (_, bar_under) = chart.in_cell_bars(under[..], 50.0, one_cell[..], 1.0, bar_storage[..])')
lines.append('    let (_, bar_count) = chart.in_cell_bars(bar_values[..], 50.0, bar_cells[..3usize], 1.0, bar_storage[..])')
lines.append('    let (_, bar_max) = chart.in_cell_bars(bar_values[..], 0.0, bar_cells[..], 1.0, bar_storage[..])')
lines.append('    let (_, bar_fat) = chart.in_cell_bars(bar_values[..], 50.0, bar_cells[..], 8.0, bar_storage[..])')
lines.append('    let (_, bar_none) = chart.in_cell_bars(bar_values[..0usize], 50.0, bar_cells[..0usize], 1.0, bar_storage[..])')
lines.append('    let (_, bar_room) = chart.in_cell_bars(bar_values[..], 50.0, bar_cells[..], 1.0, bar_storage[..3usize])')
check('bar_over != chart.Invalid || bar_under != chart.Invalid || bar_count != chart.Invalid || bar_max != chart.Invalid || bar_fat != chart.Invalid || bar_none != chart.Empty || bar_room != chart.TooLarge')

# ---- sparkline ----
spark = np.round(rng.uniform(-5.0, 20.0, 12), 2)
lines.append('    let spark_values = [12]f32{ %s }' % ', '.join('%rf32' % float(v) for v in spark))
lines.append('    let spark_bounds = geometry.rect(5.0, 8.0, 110.0, 22.0)')
lines.append('    var spark_x: [12]f32 = zero')
lines.append('    var spark_segments: [11]chart.Segment = zero')
lines.append('    let (spark, spark_error) = chart.sparkline(spark_values[..], spark_bounds, spark_x[..], spark_segments[..])')
check('spark_error != ok || spark.segments.len != 11usize')
lo, hi = spark.min(), spark.max()
parts = []
for i in range(11):
    parts.append('!closef(spark.segments[%d].from.x, %.4f) || !closef(spark.segments[%d].to.x, %.4f)' % (i, 5.0 + 110.0 * i / 11, i, 5.0 + 110.0 * (i + 1) / 11))
    parts.append('!closef(spark.segments[%d].from.y, %.4f) || !closef(spark.segments[%d].to.y, %.4f)' % (i, 8.0 + 22.0 * (1 - (spark[i] - lo) / (hi - lo)), i, 8.0 + 22.0 * (1 - (spark[i + 1] - lo) / (hi - lo))))
check(' || '.join(parts))
lines.append('    let (_, spark_short) = chart.sparkline(spark_values[..1usize], spark_bounds, spark_x[..], spark_segments[..])')
lines.append('    let (_, spark_room) = chart.sparkline(spark_values[..], spark_bounds, spark_x[..], spark_segments[..10usize])')
check('spark_short != chart.Empty || spark_room != chart.TooLarge')

body = '\n'.join(lines)
source = '''// The paginated-report compositions of e.gfx.chart against an independent numpy replay on seeded fact
// tables (L075, D2259; scripts/chart_report_reference.py writes this file): cross-tab counts and marginals,
// matrix sums with missing facts, group subtotals, totals and Row/Global/None data-bar scopes, in-cell bars
// on one shared maximum, sparklines, and every refusal. Every check has its own exit code.
use e.algo.stat
use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem
use e.os

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn close(got: f64, want: f64) -> bool {
    ret abs64(got - want) <= 0.0005f64 * (1.0f64 + abs64(want))
}

fn closef(got: f32, want: f64) -> bool { ret close(f64(got), want) }

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("gfx chart report reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_report_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote gfx_chart_report_reference with', code[0], 'checks')
