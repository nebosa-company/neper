// `e.ui.ink` (L099): ink strokes captured from a pointer or pen stream, stored with
// their pressure and timestamps in caller storage, queried for bounds, length and hits,
// and replayed on their own clock. The canvas is two caller slices -- strokes and
// samples -- and counts; nothing allocates but `path_of`, which builds a polyline into
// the caller's arena for a `StrokePath`.
//
// Capture: `begin` opens a stroke at a point, `extend` adds samples (a sample closer
// than `min_distance` to the last stored one is dropped, so a slow pen does not fill
// the storage), `end` stores the final point and closes the stroke; `cancel` discards
// an open stroke. A sample's `pressure` is the caller's, clamped to 0..1: the
// `e.ui.input` pointer carries a position and buttons, so a pen host that reports
// force passes it here, and a mouse is 1. Times are milliseconds on the caller's
// clock and must not run backwards within a stroke.
//
// Replay: time zero is the first sample of the first stroke; `replay_counts` answers
// how many samples of every stroke have been drawn by `elapsed_ms`, `path_of` builds
// that prefix, and `duration` is the time of the last sample. Width follows pressure:
// `width_at` is the stroke's width times 0.25 at no pressure up to 1.0 at full.
//
// ponytail: a stroke is the raw polyline, no smoothing or curve fitting; a hit tests
// segments against a disc, so it is O(samples) per query.

use e.mem
use e.gfx.geometry

type Sample = struct { x: f32, y: f32, pressure: f32, time_ms: u32 }
type Stroke = struct { first: usize, count: usize, width: f32, color: u32 }
type Canvas = struct { strokes: []Stroke, samples: []Sample, stroke_count: usize, sample_count: usize, open: bool, min_distance: f32 }
error TooSmall
error Invalid

fn canvas(strokes: []Stroke, samples: []Sample, min_distance: f32) -> Canvas {
    ret Canvas { strokes: strokes, samples: samples, stroke_count: 0usize, sample_count: 0usize, open: false, min_distance: min_distance }
}

fn clamp_pressure(p: f32) -> f32 {
    if p < 0.0 { ret 0.0 }
    if p > 1.0 { ret 1.0 }
    ret p
}

fn is_number(v: f32) -> bool {
    ret v == v && v - v == 0.0
}

// Opens a stroke of `width` and `color` at (x, y).
fn begin(c: *Canvas, x: f32, y: f32, pressure: f32, time_ms: u32, width: f32, color: u32) -> err {
    if c.open || !is_number(x) || !is_number(y) || !is_number(pressure) || !is_number(width) || width < 0.0 { ret Invalid }
    if c.stroke_count >= c.strokes.len || c.sample_count >= c.samples.len { ret TooSmall }
    c.strokes[c.stroke_count] = Stroke { first: c.sample_count, count: 1usize, width: width, color: color }
    c.samples[c.sample_count] = Sample { x: x, y: y, pressure: clamp_pressure(pressure), time_ms: time_ms }
    c.sample_count += 1usize
    c.stroke_count += 1usize
    c.open = true
    ret ok
}

// Adds a sample to the open stroke. A sample nearer than `min_distance` to the last
// stored one is dropped (answered `ok`); storage that is full is `TooSmall`, and the
// stroke stays open so the caller can still `end` it.
fn extend(c: *Canvas, x: f32, y: f32, pressure: f32, time_ms: u32) -> err {
    if !c.open || !is_number(x) || !is_number(y) || !is_number(pressure) { ret Invalid }
    let s = c.strokes[c.stroke_count - 1usize]
    let last = c.samples[s.first + s.count - 1usize]
    if time_ms < last.time_ms { ret Invalid }
    let dx = x - last.x
    let dy = y - last.y
    if dx * dx + dy * dy < c.min_distance * c.min_distance { ret ok }
    if c.sample_count >= c.samples.len { ret TooSmall }
    c.samples[c.sample_count] = Sample { x: x, y: y, pressure: clamp_pressure(pressure), time_ms: time_ms }
    c.sample_count += 1usize
    c.strokes[c.stroke_count - 1usize].count += 1usize
    ret ok
}

// Stores the final point (replacing the last sample when storage is full) and closes.
fn end(c: *Canvas, x: f32, y: f32, pressure: f32, time_ms: u32) -> err {
    if !c.open || !is_number(x) || !is_number(y) || !is_number(pressure) { ret Invalid }
    let s = c.strokes[c.stroke_count - 1usize]
    let at = s.first + s.count - 1usize
    if time_ms < c.samples[at].time_ms { ret Invalid }
    let moved = x != c.samples[at].x || y != c.samples[at].y
    if moved {
        if c.sample_count < c.samples.len {
            c.samples[c.sample_count] = Sample { x: x, y: y, pressure: clamp_pressure(pressure), time_ms: time_ms }
            c.sample_count += 1usize
            c.strokes[c.stroke_count - 1usize].count += 1usize
        } else {
            c.samples[at] = Sample { x: x, y: y, pressure: clamp_pressure(pressure), time_ms: time_ms }
        }
    }
    c.open = false
    ret ok
}

// Discards the open stroke and its samples.
fn cancel(c: *Canvas) {
    if !c.open { ret }
    let s = c.strokes[c.stroke_count - 1usize]
    c.sample_count = s.first
    c.stroke_count -= 1usize
    c.open = false
}

fn clear(c: *Canvas) {
    c.stroke_count = 0usize
    c.sample_count = 0usize
    c.open = false
}

// Removes stroke `index`, closing the gap in both slices; later strokes keep their order.
fn erase(c: *Canvas, index: usize) -> err {
    if index >= c.stroke_count || (c.open && index + 1usize == c.stroke_count) { ret Invalid }
    let s = c.strokes[index]
    var i = s.first + s.count
    while i < c.sample_count {
        c.samples[i - s.count] = c.samples[i]
        i += 1usize
    }
    c.sample_count -= s.count
    var k = index + 1usize
    while k < c.stroke_count {
        c.strokes[k - 1usize] = c.strokes[k]
        c.strokes[k - 1usize].first -= s.count
        k += 1usize
    }
    c.stroke_count -= 1usize
    ret ok
}

fn samples_of(c: *const Canvas, index: usize) -> []const Sample {
    let s = c.strokes[index]
    ret c.samples[s.first..s.first + s.count]
}

// The stroke's width at its sample `k`: a quarter of the width with no pressure.
fn width_at(c: *const Canvas, index: usize, k: usize) -> f32 {
    let s = c.strokes[index]
    ret s.width * (0.25 + 0.75 * c.samples[s.first + k].pressure)
}

// The samples' hull grown by half the stroke's widest width.
fn bounds(c: *const Canvas, index: usize) -> geometry.Rect {
    let s = c.strokes[index]
    var x0 = c.samples[s.first].x
    var y0 = c.samples[s.first].y
    var x1 = x0
    var y1 = y0
    var k = 1usize
    while k < s.count {
        let p = c.samples[s.first + k]
        if p.x < x0 { x0 = p.x }
        if p.y < y0 { y0 = p.y }
        if p.x > x1 { x1 = p.x }
        if p.y > y1 { y1 = p.y }
        k += 1usize
    }
    let pad = s.width / 2.0
    ret geometry.rect(x0 - pad, y0 - pad, x1 - x0 + 2.0 * pad, y1 - y0 + 2.0 * pad)
}

// Every stroke's bounds united; an empty canvas is the zero rectangle.
fn extent(c: *const Canvas) -> geometry.Rect {
    if c.stroke_count == 0usize { ret geometry.rect(0.0, 0.0, 0.0, 0.0) }
    var r = bounds(c, 0usize)
    var i = 1usize
    while i < c.stroke_count {
        r = geometry.union_rect(r, bounds(c, i))
        i += 1usize
    }
    ret r
}

// The polyline's length.
fn length(c: *const Canvas, index: usize) -> f32 {
    let s = c.strokes[index]
    var total = 0.0f32
    var k = 1usize
    while k < s.count {
        let a = c.samples[s.first + k - 1usize]
        let b = c.samples[s.first + k]
        let dx = b.x - a.x
        let dy = b.y - a.y
        total += math_sqrt(dx * dx + dy * dy)
        k += 1usize
    }
    ret total
}

// A square root by Newton's method (the module takes no `e.math` dependency).
fn math_sqrt(v: f32) -> f32 {
    if v <= 0.0 { ret 0.0 }
    var x = v
    if x < 1.0 { x = 1.0 }
    var i = 0usize
    while i < 24usize {
        x = 0.5 * (x + v / x)
        i += 1usize
    }
    ret x
}

// The time of the last sample after the first stroke's first, in milliseconds.
fn duration(c: *const Canvas) -> u32 {
    if c.stroke_count == 0usize { ret 0u32 }
    let origin = c.samples[c.strokes[0usize].first].time_ms
    var last = origin
    var i = 0usize
    while i < c.stroke_count {
        let s = c.strokes[i]
        let t = c.samples[s.first + s.count - 1usize].time_ms
        if t > last { last = t }
        i += 1usize
    }
    ret last - origin
}

// For each stroke, how many samples are drawn by `elapsed_ms` of replay time;
// `counts.len` must be at least the stroke count.
fn replay_counts(c: *const Canvas, elapsed_ms: u32, counts: []usize) -> err {
    if counts.len < c.stroke_count { ret TooSmall }
    if c.stroke_count == 0usize { ret ok }
    let origin = c.samples[c.strokes[0usize].first].time_ms
    var i = 0usize
    while i < c.stroke_count {
        let s = c.strokes[i]
        var n = 0usize
        while n < s.count {
            let t = c.samples[s.first + n].time_ms
            if t < origin || t - origin > elapsed_ms { break }
            n += 1usize
        }
        counts[i] = n
        i += 1usize
    }
    ret ok
}

// The first `count` samples of a stroke as a polyline path (a lone sample is a
// zero-length segment, so a round cap draws a dot).
fn path_of(a: *mem.Arena, c: *const Canvas, index: usize, count: usize) -> (geometry.Path, err) {
    let s = c.strokes[index]
    var n = count
    if n > s.count { n = s.count }
    if n == 0usize { ret (zero, Invalid) }
    let (pb, pb_error) = geometry.path_builder(a, n + 1usize, n + 1usize)
    if pb_error != ok { ret (zero, TooSmall) }
    var b = pb
    let first = c.samples[s.first]
    if geometry.move_to(&b, geometry.Point { x: first.x, y: first.y }) != ok { ret (zero, TooSmall) }
    if n == 1usize {
        if geometry.line_to(&b, geometry.Point { x: first.x, y: first.y }) != ok { ret (zero, TooSmall) }
    }
    var k = 1usize
    while k < n {
        let p = c.samples[s.first + k]
        if geometry.line_to(&b, geometry.Point { x: p.x, y: p.y }) != ok { ret (zero, TooSmall) }
        k += 1usize
    }
    ret (geometry.finish(&b), ok)
}

fn segment_distance_squared(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32) -> f32 {
    let dx = bx - ax
    let dy = by - ay
    let length_squared = dx * dx + dy * dy
    var t = 0.0f32
    if length_squared > 0.0 { t = ((px - ax) * dx + (py - ay) * dy) / length_squared }
    if t < 0.0 { t = 0.0 }
    if t > 1.0 { t = 1.0 }
    let cx = ax + t * dx - px
    let cy = ay + t * dy - py
    ret cx * cx + cy * cy
}

// The topmost (latest) stroke passing within `radius` of `p`, widths included.
fn hit(c: *const Canvas, p: geometry.Point, radius: f32) -> (usize, bool) {
    var i = c.stroke_count
    while i > 0usize {
        i -= 1usize
        let s = c.strokes[i]
        let reach = radius + s.width / 2.0
        var k = 0usize
        while k < s.count {
            let a = c.samples[s.first + k]
            var b = a
            if k + 1usize < s.count { b = c.samples[s.first + k + 1usize] }
            if segment_distance_squared(p.x, p.y, a.x, a.y, b.x, b.y) <= reach * reach { ret (i, true) }
            k += 1usize
        }
    }
    ret (0usize, false)
}
