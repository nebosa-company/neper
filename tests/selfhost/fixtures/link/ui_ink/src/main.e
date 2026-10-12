// `e.ui.ink` (L099): three strokes fed through a pen pointer stream built from
// `e.ui.input` events (down, moves, up), then their bounds, length, widths by
// pressure, replay counts, duration and hits compared with the numbers
// scripts/gen_ink_test.py computes from the same formulas in doubles; capture
// decimation by `min_distance`, cancel, erase and its compaction, capacity refusal
// with a full sample table, and the state errors. Each check exits with its own code.

use e.gfx.geometry
use e.io
use e.mem
use e.os
use e.ui.input
use e.ui.ink as ink

fn near(x: f32, want: f32, eps: f32) -> bool {
    var d = x - want
    if d < 0.0 { d = 0.0 - d }
    ret d <= eps
}

// Sample i of stroke A, B or C (the generator's formulas).
fn sine_x(i: usize) -> f32 { ret 5.0 * f32(i) }
fn sine_y(i: usize) -> f32 {
    var s = 0.0f64
    // sin by its series is enough for 0.3 * i up to 11.7: reduce by 2 pi first.
    var t = 0.3f64 * f64(i)
    while t > 6.283185307179586f64 { t -= 6.283185307179586f64 }
    if t > 3.141592653589793f64 { t -= 6.283185307179586f64 }
    var term = t
    var n = 1.0f64
    s = t
    var k = 0usize
    while k < 12usize {
        term = 0.0f64 - term * t * t / ((n + 1.0f64) * (n + 2.0f64))
        s += term
        n += 2.0f64
        k += 1usize
    }
    ret f32(50.0f64 + 20.0f64 * s)
}

// The pen stream of stroke A as events: down, 38 moves, up.
fn pen(position: geometry.Point, buttons: u32) -> input.Pointer {
    ret input.Pointer { window: zero, device: 1u32, pointer: 1u32, kind: .Pen, position: position, buttons: buttons, changed: .Primary }
}

// One pointer event into the canvas: a pen down opens a stroke, a move extends it, an
// up closes it. The pressure and time come from the caller (the event has neither).
fn apply(c: *ink.Canvas, event: input.Event, pressure: f32, time: u32) -> err {
    switch event {
    case .PointerDown as e:
        ret ink.begin(c, e.position.x, e.position.y, pressure, time, 4.0, 4278190335u32)
    case .PointerMove as e:
        ret ink.extend(c, e.position.x, e.position.y, pressure, time)
    case .PointerUp as e:
        ret ink.end(c, e.position.x, e.position.y, pressure, time)
    default:
        ret ink.Invalid
    }
    ret ink.Invalid
}

fn feed_a(c: *ink.Canvas) -> err {
    var i = 0usize
    while i < 40usize {
        let p = geometry.Point { x: sine_x(i), y: sine_y(i) }
        let pressure = 0.2f32 + 0.6f32 * f32(i) / 39.0f32
        let time = 1000u32 + u32(10usize * i)
        if i == 0usize {
            try apply(c, input.Event { PointerDown: pen(p, 1u32) }, pressure, time)
        } else if i == 39usize {
            try apply(c, input.Event { PointerUp: pen(p, 0u32) }, pressure, time)
        } else {
            try apply(c, input.Event { PointerMove: pen(p, 1u32) }, pressure, time)
        }
        i += 1usize
    }
    ret ok
}

fn feed_b(c: *ink.Canvas) -> err {
    try ink.begin(c, 0.0, 0.0, 0.0, 2000u32, 6.0, 4278255360u32)
    var i = 1usize
    while i < 10usize {
        try ink.extend(c, 10.0 * f32(i), 6.0 * f32(i), f32(i) / 10.0, 2000u32 + u32(50usize * i))
        i += 1usize
    }
    ret ink.end(c, 100.0, 60.0, 1.0, 2500u32)
}

fn feed_c(c: *ink.Canvas) -> err {
    try ink.begin(c, 30.0, 30.0, 1.0, 3000u32, 8.0, 4294901760u32)
    ret ink.end(c, 30.0, 30.0, 1.0, 3000u32)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var strokes: [8]ink.Stroke = zero
    var samples: [128]ink.Sample = zero
    var canvas = ink.canvas(strokes[0..], samples[0..], 0.0)
    if feed_a(&canvas) != ok || feed_b(&canvas) != ok || feed_c(&canvas) != ok { os.exit(1) }
    if canvas.stroke_count != 3usize || canvas.sample_count != 40usize + 11usize + 1usize || canvas.open { os.exit(2) }

    // Bounds: the hull grown by half the width.
    let ba = ink.bounds(&canvas, 0usize)
    if !near(ba.x, 0.0 - 2.0, 0.01) || !near(ba.y, 28.0767, 0.01) || !near(ba.width, 199.0, 0.01) || !near(ba.height, 43.8942, 0.01) { os.exit(3) }
    let bb = ink.bounds(&canvas, 1usize)
    if !near(bb.x, 0.0 - 3.0, 0.01) || !near(bb.y, 0.0 - 3.0, 0.01) || !near(bb.width, 106.0, 0.01) || !near(bb.height, 66.0, 0.01) { os.exit(4) }
    let bc = ink.bounds(&canvas, 2usize)
    if !near(bc.x, 26.0, 0.01) || !near(bc.width, 8.0, 0.01) { os.exit(5) }
    let whole = ink.extent(&canvas)
    if !near(whole.x, 0.0 - 3.0, 0.01) || !near(whole.y, 0.0 - 3.0, 0.01) || !near(whole.width, 200.0, 0.01) || !near(whole.height, 74.9709, 0.02) { os.exit(6) }

    // Lengths and pressure-driven widths.
    if !near(ink.length(&canvas, 0usize), 250.1109, 0.05) || !near(ink.length(&canvas, 1usize), 116.619, 0.02) || ink.length(&canvas, 2usize) != 0.0 { os.exit(7) }
    if !near(ink.width_at(&canvas, 0usize, 0usize), 1.6, 0.001) || !near(ink.width_at(&canvas, 0usize, 39usize), 3.4, 0.001) || !near(ink.width_at(&canvas, 1usize, 5usize), 3.75, 0.001) { os.exit(8) }

    // Replay on the stroke clock: time zero is A's first sample.
    var counts: [8]usize = zero
    if ink.duration(&canvas) != 2000u32 { os.exit(9) }
    if ink.replay_counts(&canvas, 0u32, counts[0..]) != ok || counts[0] != 1usize || counts[1] != 0usize || counts[2] != 0usize { os.exit(10) }
    if ink.replay_counts(&canvas, 105u32, counts[0..]) != ok || counts[0] != 11usize || counts[1] != 0usize { os.exit(11) }
    if ink.replay_counts(&canvas, 389u32, counts[0..]) != ok || counts[0] != 39usize { os.exit(12) }
    if ink.replay_counts(&canvas, 1000u32, counts[0..]) != ok || counts[0] != 40usize || counts[1] != 1usize || counts[2] != 0usize { os.exit(13) }
    if ink.replay_counts(&canvas, 2000u32, counts[0..]) != ok || counts[1] != 11usize || counts[2] != 1usize { os.exit(14) }
    if ink.replay_counts(&canvas, 5u32, counts[..2usize]) != ink.TooSmall { os.exit(15) }

    // Hits: topmost within the radius plus half the width.
    let (h_b, has_b) = ink.hit(&canvas, geometry.Point { x: 50.0, y: 30.0 }, 2.0)
    if !has_b || h_b != 1usize { os.exit(16) }
    let (h_c, has_c) = ink.hit(&canvas, geometry.Point { x: 30.0, y: 30.0 }, 0.0)
    if !has_c || h_c != 2usize { os.exit(17) }
    let (_, has_none) = ink.hit(&canvas, geometry.Point { x: 190.0, y: 190.0 }, 5.0)
    if has_none { os.exit(18) }
    let (_, has_gap) = ink.hit(&canvas, geometry.Point { x: 40.0, y: 50.0 }, 0.0)
    if has_gap { os.exit(19) }

    // A path of the first eleven samples: a move and ten lines.
    var arena_bytes: [8192]u8 = zero
    var local = mem.arena_from(arena_bytes[0..])
    let (path, path_error) = ink.path_of(&local, &canvas, 0usize, 11usize)
    if path_error != ok || path.points.len != 11usize || path.verbs.len != 11usize { os.exit(20) }
    let (dot, dot_error) = ink.path_of(&local, &canvas, 2usize, 1usize)
    if dot_error != ok || dot.points.len != 2usize { os.exit(21) }

    // Erase B: C and the samples move down, bounds follow.
    if ink.erase(&canvas, 1usize) != ok { os.exit(22) }
    if canvas.stroke_count != 2usize || canvas.sample_count != 41usize || canvas.strokes[1usize].first != 40usize { os.exit(23) }
    if !near(ink.bounds(&canvas, 1usize).x, 26.0, 0.01) { os.exit(24) }
    if ink.erase(&canvas, 5usize) != ink.Invalid { os.exit(25) }

    // Capture decimation: min_distance 8, 12 and 30 keep 21, 18 and 9 of A's samples.
    var thin = ink.canvas(strokes[0..], samples[0..], 8.0)
    if feed_a(&thin) != ok || thin.sample_count != 21usize { os.exit(26) }
    ink.clear(&thin)
    thin.min_distance = 12.0
    if feed_a(&thin) != ok || thin.sample_count != 18usize { os.exit(27) }
    ink.clear(&thin)
    thin.min_distance = 30.0
    if feed_a(&thin) != ok || thin.sample_count != 9usize { os.exit(28) }
    // The end point is stored whatever the distance.
    let tail = ink.samples_of(&thin, 0usize)
    if tail[tail.len - 1usize].x != 195.0 { os.exit(29) }

    // State errors, cancel and capacity.
    ink.clear(&canvas)
    if ink.extend(&canvas, 1.0, 1.0, 1.0, 5u32) != ink.Invalid { os.exit(30) }
    if ink.end(&canvas, 1.0, 1.0, 1.0, 5u32) != ink.Invalid { os.exit(31) }
    if ink.begin(&canvas, 1.0, 1.0, 1.0, 100u32, 2.0, 0u32) != ok { os.exit(32) }
    if ink.begin(&canvas, 2.0, 2.0, 1.0, 101u32, 2.0, 0u32) != ink.Invalid { os.exit(33) }
    if ink.extend(&canvas, 5.0, 5.0, 1.0, 50u32) != ink.Invalid { os.exit(34) }
    if ink.extend(&canvas, 5.0, 5.0, 3.0, 120u32) != ok || canvas.samples[1usize].pressure != 1.0 { os.exit(35) }
    ink.cancel(&canvas)
    if canvas.stroke_count != 0usize || canvas.sample_count != 0usize || canvas.open { os.exit(36) }
    var tiny_strokes: [2]ink.Stroke = zero
    var tiny_samples: [3]ink.Sample = zero
    var tiny = ink.canvas(tiny_strokes[0..], tiny_samples[0..], 0.0)
    if ink.begin(&tiny, 0.0, 0.0, 1.0, 0u32, 1.0, 0u32) != ok { os.exit(37) }
    if ink.extend(&tiny, 1.0, 0.0, 1.0, 1u32) != ok || ink.extend(&tiny, 2.0, 0.0, 1.0, 2u32) != ok { os.exit(38) }
    if ink.extend(&tiny, 3.0, 0.0, 1.0, 3u32) != ink.TooSmall { os.exit(39) }
    // end() with the table full replaces the last sample rather than failing.
    if ink.end(&tiny, 9.0, 0.0, 1.0, 4u32) != ok || tiny.samples[2usize].x != 9.0 || tiny.sample_count != 3usize { os.exit(40) }
    if ink.begin(&tiny, 0.0, 0.0, 1.0, 5u32, 1.0, 0u32) != ink.TooSmall { os.exit(41) }
    if ink.begin(&tiny, 0.0 / 0.0, 0.0, 1.0, 5u32, 1.0, 0u32) != ink.Invalid { os.exit(42) }

    try io.print("ui ink ok\n")
    ret ok
}
