// e.gfx.chart.state_timeline against a Python replay on a seeded epoch-millisecond history (L074, D2258;
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
    let base = 1700000000000.0f64
    let spans = [22]chart.StateSpan{
        chart.StateSpan { row: 0usize, start: base + 2026409.0f64, end: base + 5273717.0f64, state: 0usize },
        chart.StateSpan { row: 0usize, start: base + 5273717.0f64, end: base + 5773717.0f64, state: 0usize },
        chart.StateSpan { row: 0usize, start: base + 5982853.0f64, end: base + 8669194.0f64, state: 2usize },
        chart.StateSpan { row: 0usize, start: base + 8669195.0f64, end: base + 11654124.0f64, state: 1usize },
        chart.StateSpan { row: 0usize, start: base + 11654124.0f64, end: base + 14751421.0f64, state: 3usize },
        chart.StateSpan { row: 0usize, start: base + 14751422.0f64, end: base + 19767723.0f64, state: 2usize },
        chart.StateSpan { row: 0usize, start: base + 20380231.0f64, end: base + 24460690.0f64, state: 2usize },
        chart.StateSpan { row: 1usize, start: base + 2415522.0f64, end: base + 3530908.0f64, state: 3usize },
        chart.StateSpan { row: 1usize, start: base + 3530908.0f64, end: base + 8298021.0f64, state: 1usize },
        chart.StateSpan { row: 1usize, start: base + 8298022.0f64, end: base + 11743941.0f64, state: 2usize },
        chart.StateSpan { row: 1usize, start: base + 11743941.0f64, end: base + 15887891.0f64, state: 3usize },
        chart.StateSpan { row: 1usize, start: base + 16010996.0f64, end: base + 18041483.0f64, state: 2usize },
        chart.StateSpan { row: 1usize, start: base + 18041483.0f64, end: base + 19602657.0f64, state: 2usize },
        chart.StateSpan { row: 1usize, start: base + 19602657.0f64, end: base + 23850107.0f64, state: 2usize },
        chart.StateSpan { row: 2usize, start: base + 893236.0f64, end: base + 6273778.0f64, state: 0usize },
        chart.StateSpan { row: 2usize, start: base + 7290696.0f64, end: base + 11389230.0f64, state: 1usize },
        chart.StateSpan { row: 2usize, start: base + 11389230.0f64, end: base + 17163220.0f64, state: 1usize },
        chart.StateSpan { row: 2usize, start: base + 19135319.0f64, end: base + 21778058.0f64, state: 1usize },
        chart.StateSpan { row: 2usize, start: base + 21778059.0f64, end: base + 25527084.0f64, state: 0usize },
        chart.StateSpan { row: 2usize, start: base + 25527084.0f64, end: base + 31358803.0f64, state: 1usize },
        chart.StateSpan { row: 2usize, start: base + 31358804.0f64, end: base + 35824625.0f64, state: 2usize },
        chart.StateSpan { row: 2usize, start: base + 35824626.0f64, end: base + 41619936.0f64, state: 2usize },
    }
    let bounds = geometry.rect(20.0, 30.0, 600.0, 150.0)
    var rects: [22]geometry.Rect = zero
    var states: [22]usize = zero
    var storage: [22]chart.Layout = zero
    let domain_end = base + 86400000.0f64
    let (layers, layout_error) = chart.state_timeline(spans[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..])
    if layout_error != ok || layers.len != 18usize { os.exit(1) }
    if !close(rects[0].x, 34.0723) || !close(rects[0].width, 26.0230) || !close(rects[1].x, 61.5476) || !close(rects[1].width, 18.6551) || !close(rects[2].x, 80.2027) || !close(rects[2].width, 20.7287) || !close(rects[3].x, 100.9314) || !close(rects[3].width, 21.5090) || !close(rects[4].x, 122.4404) || !close(rects[4].width, 34.8354) || !close(rects[5].x, 161.5294) || !close(rects[5].width, 28.3365) || !close(rects[6].x, 36.7745) || !close(rects[6].width, 7.7457) || !close(rects[7].x, 44.5202) || !close(rects[7].width, 33.1050) || !close(rects[8].x, 77.6252) || !close(rects[8].width, 23.9300) || !close(rects[9].x, 101.5551) || !close(rects[9].width, 28.7774) || !close(rects[10].x, 131.1875) || !close(rects[10].width, 54.4383) || !close(rects[11].x, 26.2030) || !close(rects[11].width, 37.3649) || !close(rects[12].x, 70.6298) || !close(rects[12].width, 68.5592) || !close(rects[13].x, 152.8842) || !close(rects[13].width, 18.3524) || !close(rects[14].x, 171.2365) || !close(rects[14].width, 26.0349) || !close(rects[15].x, 197.2714) || !close(rects[15].width, 40.4980) || !close(rects[16].x, 237.7695) || !close(rects[16].width, 31.0126) || !close(rects[17].x, 268.7821) || !close(rects[17].width, 40.2452) { os.exit(2) }
    if !close(rects[0].y, 30.0000) || !close(rects[0].height, 46.0000) || !close(rects[1].y, 30.0000) || !close(rects[1].height, 46.0000) || !close(rects[2].y, 30.0000) || !close(rects[2].height, 46.0000) || !close(rects[3].y, 30.0000) || !close(rects[3].height, 46.0000) || !close(rects[4].y, 30.0000) || !close(rects[4].height, 46.0000) || !close(rects[5].y, 30.0000) || !close(rects[5].height, 46.0000) || !close(rects[6].y, 82.0000) || !close(rects[6].height, 46.0000) || !close(rects[7].y, 82.0000) || !close(rects[7].height, 46.0000) || !close(rects[8].y, 82.0000) || !close(rects[8].height, 46.0000) || !close(rects[9].y, 82.0000) || !close(rects[9].height, 46.0000) || !close(rects[10].y, 82.0000) || !close(rects[10].height, 46.0000) || !close(rects[11].y, 134.0000) || !close(rects[11].height, 46.0000) || !close(rects[12].y, 134.0000) || !close(rects[12].height, 46.0000) || !close(rects[13].y, 134.0000) || !close(rects[13].height, 46.0000) || !close(rects[14].y, 134.0000) || !close(rects[14].height, 46.0000) || !close(rects[15].y, 134.0000) || !close(rects[15].height, 46.0000) || !close(rects[16].y, 134.0000) || !close(rects[16].height, 46.0000) || !close(rects[17].y, 134.0000) || !close(rects[17].height, 46.0000) { os.exit(3) }
    if states[0] != 0usize || states[1] != 2usize || states[2] != 1usize || states[3] != 3usize || states[4] != 2usize || states[5] != 2usize || states[6] != 3usize || states[7] != 1usize || states[8] != 2usize || states[9] != 3usize || states[10] != 2usize || states[11] != 0usize || states[12] != 1usize || states[13] != 1usize || states[14] != 0usize || states[15] != 1usize || states[16] != 2usize || states[17] != 2usize { os.exit(4) }
    if layers[0].bars.len != 1usize || layers[1].bars.len != 1usize || layers[2].bars.len != 1usize || layers[3].bars.len != 1usize || layers[4].bars.len != 1usize || layers[5].bars.len != 1usize || layers[6].bars.len != 1usize || layers[7].bars.len != 1usize || layers[8].bars.len != 1usize || layers[9].bars.len != 1usize || layers[10].bars.len != 1usize || layers[11].bars.len != 1usize || layers[12].bars.len != 1usize || layers[13].bars.len != 1usize || layers[14].bars.len != 1usize || layers[15].bars.len != 1usize || layers[16].bars.len != 1usize || layers[17].bars.len != 1usize { os.exit(5) }
    let jitter = [2]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base, end: base + 1000.0f64, state: 1usize }, chart.StateSpan { row: 0usize, start: base + 1001.0f64, end: base + 2000.0f64, state: 1usize } }
    let (jittered, jitter_error) = chart.state_timeline(jitter[..], 1usize, 2usize, base, domain_end, bounds, 0.0, rects[..], states[..], storage[..])
    let change = [2]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base, end: base + 1000.0f64, state: 0usize }, chart.StateSpan { row: 0usize, start: base + 1000.0f64, end: base + 2000.0f64, state: 1usize } }
    let (changed, change_error) = chart.state_timeline(change[..], 1usize, 2usize, base, domain_end, bounds, 0.0, rects[..], states[..], storage[..])
    let same = [2]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base, end: base + 1000.0f64, state: 1usize }, chart.StateSpan { row: 0usize, start: base + 1000.0f64, end: base + 2000.0f64, state: 1usize } }
    let (joined, join_error) = chart.state_timeline(same[..], 1usize, 2usize, base, domain_end, bounds, 0.0, rects[..], states[..], storage[..])
    if jitter_error != ok || jittered.len != 2usize || change_error != ok || changed.len != 2usize || join_error != ok || joined.len != 1usize { os.exit(6) }
    let bad_row_order = [2]chart.StateSpan{ chart.StateSpan { row: 1usize, start: base + 0.0f64, end: base + 10.0f64, state: 0usize }, chart.StateSpan { row: 0usize, start: base + 20.0f64, end: base + 30.0f64, state: 0usize } }
    let (_, row_order_error) = chart.state_timeline(bad_row_order[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..])
    let bad_overlap = [2]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base + 0.0f64, end: base + 10.0f64, state: 0usize }, chart.StateSpan { row: 0usize, start: base + 5.0f64, end: base + 20.0f64, state: 0usize } }
    let (_, overlap_error) = chart.state_timeline(bad_overlap[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..])
    let bad_bad_row = [1]chart.StateSpan{ chart.StateSpan { row: 3usize, start: base + 0.0f64, end: base + 10.0f64, state: 0usize } }
    let (_, bad_row_error) = chart.state_timeline(bad_bad_row[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..])
    let bad_bad_state = [1]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base + 0.0f64, end: base + 10.0f64, state: 4usize } }
    let (_, bad_state_error) = chart.state_timeline(bad_bad_state[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..])
    let bad_before = [1]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base + -1.0f64, end: base + 10.0f64, state: 0usize } }
    let (_, before_error) = chart.state_timeline(bad_before[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..])
    let bad_after = [1]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base + 0.0f64, end: base + 86400001.0f64, state: 0usize } }
    let (_, after_error) = chart.state_timeline(bad_after[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..])
    let bad_empty_span = [1]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base + 10.0f64, end: base + 10.0f64, state: 0usize } }
    let (_, empty_span_error) = chart.state_timeline(bad_empty_span[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..])
    let bad_backwards = [1]chart.StateSpan{ chart.StateSpan { row: 0usize, start: base + 10.0f64, end: base + 5.0f64, state: 0usize } }
    let (_, backwards_error) = chart.state_timeline(bad_backwards[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..])
    if row_order_error != chart.Invalid || overlap_error != chart.Invalid || bad_row_error != chart.Invalid || bad_state_error != chart.Invalid || before_error != chart.Invalid || after_error != chart.Invalid || empty_span_error != chart.Invalid || backwards_error != chart.Invalid { os.exit(7) }
    let (_, none_error) = chart.state_timeline(spans[..0usize], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..])
    let (_, reversed_error) = chart.state_timeline(spans[..], 3usize, 4usize, domain_end, base, bounds, 6.0, rects[..], states[..], storage[..])
    let (_, tall_gap_error) = chart.state_timeline(spans[..], 3usize, 4usize, base, domain_end, bounds, 80.0, rects[..], states[..], storage[..])
    let (_, short_rects_error) = chart.state_timeline(spans[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..21usize], states[..], storage[..])
    let (_, short_states_error) = chart.state_timeline(spans[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..21usize], storage[..])
    let (_, short_layers_error) = chart.state_timeline(spans[..], 3usize, 4usize, base, domain_end, bounds, 6.0, rects[..], states[..], storage[..21usize])
    if none_error != chart.Empty || reversed_error != chart.Invalid || tall_gap_error != chart.Invalid || short_rects_error != chart.TooLarge || short_states_error != chart.TooLarge || short_layers_error != chart.TooLarge { os.exit(8) }
    try io.print("gfx chart state timeline reference ok\n")
    os.exit(0)
    ret ok
}
