"""Write tests/selfhost/fixtures/link/gfx_chart_state_timeline_reference/src/main.e (L074, D2258).

  python scripts/chart_state_timeline_reference.py

A seeded 3-row, 4-state history over an epoch-millisecond domain (abutting equal states, abutting different
states, one-millisecond jitter, gaps) laid out by e.gfx.chart.state_timeline and compared with a Python
replay: the coalesced rectangle count, x and width from the f64 time mapping, row top and lane height, and
the state id of every rectangle. Refusals: out-of-order rows, overlaps, bad rows and states, spans outside
the domain, empty spans, short storage, a gap that eats the height. Each check has its own exit code.
"""
import pathlib

import numpy as np

root = pathlib.Path(__file__).resolve().parent.parent
lines = []
code = [0]
rng = np.random.default_rng(20261011)


def check(condition):
    code[0] += 1
    lines.append('    if %s { os.exit(%d) }' % (condition, code[0]))


BASE = 1700000000000
SPAN = 86400000  # one day
ROWS, STATES = 3, 4
W, H, X, Y, GAP = 600.0, 150.0, 20.0, 30.0, 6.0

spans = []
for row in range(ROWS):
    t = BASE + int(rng.integers(0, 3_000_000))
    for _ in range(int(rng.integers(5, 9))):
        end = t + int(rng.integers(600_000, 6_000_000))
        if end > BASE + SPAN:
            break
        spans.append((row, t, end, int(rng.integers(0, STATES))))
        mode = int(rng.integers(0, 3))
        if mode == 0:
            t = end                                          # abuts: merged when the state repeats
        elif mode == 1:
            t = end + 1                                      # one-millisecond jitter: never merged
        else:
            t = end + int(rng.integers(100_000, 2_000_000))  # a gap
# force one abutting equal-state pair in row 0, then keep every row ordered
first = [s for s in spans if s[0] == 0][0]
spans.insert(spans.index(first) + 1, (0, first[2], first[2] + 500_000, first[3]))
fixed, last_end = [], {}
for row, start, end, state in spans:
    if row in last_end and start < last_end[row]:
        shift = last_end[row] - start
        start, end = start + shift, end + shift
    if end > BASE + SPAN:
        continue
    fixed.append((row, start, end, state))
    last_end[row] = end
spans = fixed

lane = (H - GAP * (ROWS - 1)) / ROWS
rects, ids = [], []
for k, (row, start, end, state) in enumerate(spans):
    left = X + W * ((start - BASE) / SPAN)
    right = X + W * ((end - BASE) / SPAN)
    top = Y + row * (lane + GAP)
    if k > 0:
        prow, pstart, pend, pstate = spans[k - 1]
        if row == prow and state == pstate and start == pend:
            rects[-1][2] = right - rects[-1][0]
            continue
    rects.append([left, top, right - left, lane])
    ids.append(state)

n = len(spans)
lines.append('    let base = %s.0f64' % BASE)
lines.append('    let spans = [%d]chart.StateSpan{' % n)
for row, start, end, state in spans:
    lines.append('        chart.StateSpan { row: %dusize, start: base + %s.0f64, end: base + %s.0f64, state: %dusize },' % (row, start - BASE, end - BASE, state))
lines.append('    }')
lines.append('    let bounds = geometry.rect(%s, %s, %s, %s)' % (X, Y, W, H))
lines.append('    var rects: [%d]geometry.Rect = zero' % n)
lines.append('    var states: [%d]usize = zero' % n)
lines.append('    var storage: [%d]chart.Layout = zero' % n)
lines.append('    let domain_end = base + %s.0f64' % SPAN)
lines.append('    let (layers, layout_error) = chart.state_timeline(spans[..], 3usize, 4usize, base, domain_end, bounds, %s, rects[..], states[..], storage[..])' % GAP)
check('layout_error != ok || layers.len != %dusize' % len(rects))
check(' || '.join('!close(rects[%d].x, %.4f) || !close(rects[%d].width, %.4f)' % (i, r[0], i, r[2]) for i, r in enumerate(rects)))
check(' || '.join('!close(rects[%d].y, %.4f) || !close(rects[%d].height, %.4f)' % (i, r[1], i, r[3]) for i, r in enumerate(rects)))
check(' || '.join('states[%d] != %dusize' % (i, s) for i, s in enumerate(ids)))
check(' || '.join('layers[%d].bars.len != 1usize' % i for i in range(len(rects))))
# jitter and state changes must not merge; equal abutting states must
lines.append('    let jitter = [2]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base, end: base + 1000.0f64, state: 1usize }, chart.StateSpan { row: 0usize, start: base + 1001.0f64, end: base + 2000.0f64, state: 1usize } }')
lines.append('    let (jittered, jitter_error) = chart.state_timeline(jitter[..], 1usize, 2usize, base, domain_end, bounds, 0.0, rects[..], states[..], storage[..])')
lines.append('    let change = [2]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base, end: base + 1000.0f64, state: 0usize }, chart.StateSpan { row: 0usize, start: base + 1000.0f64, end: base + 2000.0f64, state: 1usize } }')
lines.append('    let (changed, change_error) = chart.state_timeline(change[..], 1usize, 2usize, base, domain_end, bounds, 0.0, rects[..], states[..], storage[..])')
lines.append('    let same = [2]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base, end: base + 1000.0f64, state: 1usize }, chart.StateSpan { row: 0usize, start: base + 1000.0f64, end: base + 2000.0f64, state: 1usize } }')
lines.append('    let (joined, join_error) = chart.state_timeline(same[..], 1usize, 2usize, base, domain_end, bounds, 0.0, rects[..], states[..], storage[..])')
check('jitter_error != ok || jittered.len != 2usize || change_error != ok || changed.len != 2usize || join_error != ok || joined.len != 1usize')


def span(r, s, e, st):
    return 'chart.StateSpan { row: %dusize, start: base + %s.0f64, end: base + %s.0f64, state: %dusize }' % (r, s, e, st)


bad = {
    'row_order': [span(1, 0, 10, 0), span(0, 20, 30, 0)],
    'overlap': [span(0, 0, 10, 0), span(0, 5, 20, 0)],
    'bad_row': [span(3, 0, 10, 0)],
    'bad_state': [span(0, 0, 10, 4)],
    'before': [span(0, -1, 10, 0)],
    'after': [span(0, 0, SPAN + 1, 0)],
    'empty_span': [span(0, 10, 10, 0)],
    'backwards': [span(0, 10, 5, 0)],
}
for name, items in bad.items():
    lines.append('    let bad_%s = [%d]chart.StateSpan{ %s }' % (name, len(items), ', '.join(items)))
    lines.append('    let (_, %s_error) = chart.state_timeline(bad_%s[..], 3usize, 4usize, base, domain_end, bounds, %s, rects[..], states[..], storage[..])' % (name, name, GAP))
check(' || '.join('%s_error != chart.Invalid' % k for k in bad))
lines.append('    let (_, none_error) = chart.state_timeline(spans[..0usize], 3usize, 4usize, base, domain_end, bounds, %s, rects[..], states[..], storage[..])' % GAP)
lines.append('    let (_, reversed_error) = chart.state_timeline(spans[..], 3usize, 4usize, domain_end, base, bounds, %s, rects[..], states[..], storage[..])' % GAP)
lines.append('    let (_, tall_gap_error) = chart.state_timeline(spans[..], 3usize, 4usize, base, domain_end, bounds, 80.0, rects[..], states[..], storage[..])')
lines.append('    let (_, short_rects_error) = chart.state_timeline(spans[..], 3usize, 4usize, base, domain_end, bounds, %s, rects[..%dusize], states[..], storage[..])' % (GAP, n - 1))
lines.append('    let (_, short_states_error) = chart.state_timeline(spans[..], 3usize, 4usize, base, domain_end, bounds, %s, rects[..], states[..%dusize], storage[..])' % (GAP, n - 1))
lines.append('    let (_, short_layers_error) = chart.state_timeline(spans[..], 3usize, 4usize, base, domain_end, bounds, %s, rects[..], states[..], storage[..%dusize])' % (GAP, n - 1))
check('none_error != chart.Empty || reversed_error != chart.Invalid || tall_gap_error != chart.Invalid || short_rects_error != chart.TooLarge || short_states_error != chart.TooLarge || short_layers_error != chart.TooLarge')

body = '\n'.join(lines)
source = '''// e.gfx.chart.state_timeline against a Python replay on a seeded epoch-millisecond history (L074, D2258;
// scripts/chart_state_timeline_reference.py writes this file): coalesced rectangle count and geometry from the
// f64 time mapping, lane tops and heights, state identity, one-millisecond jitter and state changes left
// unmerged, and every refusal. Every check has its own exit code.
use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem
use e.os

fn close(got: f32, want: f32) -> bool {
    let d = got - want
    ret d > -0.002 && d < 0.002
}

fn main(a: *mem.Arena, args: []str) -> err {
@@BODY@@
    try io.print("gfx chart state timeline reference ok\\n")
    os.exit(0)
    ret ok
}
'''.replace('@@BODY@@', body)
target = root / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'gfx_chart_state_timeline_reference' / 'src'
target.mkdir(parents=True, exist_ok=True)
(target / 'main.e').write_text(source, encoding='utf-8', newline='\n')
print('wrote', code[0], 'checks;', n, 'spans ->', len(rects), 'rects')
