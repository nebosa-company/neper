// Declarative chart geometry. The first slice keeps data borrowed and emits
// renderer-neutral marks; scene, PNG and widget adapters can consume Layout.
//
// The contract is intentionally small: one numeric x/y mapping, one Cartesian
// bounds rectangle, and caller-owned output. More chart families compose on it.

use e.gfx.geometry

type Kind = enum u8 { Scatter, Line, Bar }
type Coord = struct { x: f32, y: f32 }
type Segment = struct { from: Coord, to: Coord }
type Spec = struct { kind: Kind, bounds: geometry.Rect, x: []const f32, y: []const f32, baseline: f32, bar_width: f32 }
type Layout = struct { kind: Kind, coords: []Coord, segments: []Segment, bars: []geometry.Rect, x_min: f32, x_max: f32, y_min: f32, y_max: f32 }
error Invalid
error Empty
error TooLarge

fn spec(kind: Kind, bounds: geometry.Rect, x: []const f32, y: []const f32) -> Spec {
    ret Spec { kind: kind, bounds: bounds, x: x, y: y, baseline: 0.0, bar_width: 0.0 }
}

fn finite(v: f32) -> bool {
    ret v == v && v - v == 0.0
}

fn extent(values: []const f32) -> (f32, f32, err) {
    if values.len == 0usize { ret (0.0, 0.0, Empty) }
    if !finite(values[0usize]) { ret (0.0, 0.0, Invalid) }
    var lo = values[0usize]
    var hi = lo
    var i = 1usize
    while i < values.len {
        if !finite(values[i]) { ret (0.0, 0.0, Invalid) }
        if values[i] < lo { lo = values[i] }
        if values[i] > hi { hi = values[i] }
        i += 1usize
    }
    ret (lo, hi, ok)
}

fn mapped(value: f32, lo: f32, hi: f32, start: f32, size: f32) -> f32 {
    ret start + (value - lo) / (hi - lo) * size
}

// Produces marks in screen coordinates. Y is inverted because graphics bounds
// use a top-left origin; the returned domain remains in data coordinates.
fn layout(s: *const Spec, coords: []Coord, segments: []Segment, bars: []geometry.Rect) -> (Layout, err) {
    if s.x.len == 0usize { ret (zero, Empty) }
    if s.x.len != s.y.len || s.bounds.width <= 0.0 || s.bounds.height <= 0.0 { ret (zero, Invalid) }
    if !finite(s.bounds.x) || !finite(s.bounds.y) || !finite(s.bounds.width) || !finite(s.bounds.height) { ret (zero, Invalid) }
    let (x0, x1, x_error) = extent(s.x)
    if x_error != ok { ret (zero, x_error) }
    let (raw_y0, raw_y1, y_error) = extent(s.y)
    if y_error != ok { ret (zero, y_error) }
    var y0 = raw_y0
    var y1 = raw_y1
    if s.kind == .Bar {
        if !finite(s.baseline) { ret (zero, Invalid) }
        if s.baseline < y0 { y0 = s.baseline }
        if s.baseline > y1 { y1 = s.baseline }
    }
    var xmin = x0
    var xmax = x1
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
    }
    if y0 == y1 {
        y0 -= 0.5
        y1 += 0.5
    }

    var coord_count = 0usize
    var segment_count = 0usize
    var bar_count = 0usize
    if s.kind == .Scatter {
        if coords.len < s.x.len { ret (zero, TooLarge) }
        while coord_count < s.x.len {
            coords[coord_count] = Coord {
                x: mapped(s.x[coord_count], xmin, xmax, s.bounds.x, s.bounds.width),
                y: s.bounds.y + s.bounds.height - mapped(s.y[coord_count], y0, y1, 0.0, s.bounds.height),
            }
            coord_count += 1usize
        }
    } else if s.kind == .Line {
        if segments.len + 1usize < s.x.len { ret (zero, TooLarge) }
        if s.x.len > 1usize {
            while segment_count + 1usize < s.x.len {
                let from = Coord {
                    x: mapped(s.x[segment_count], xmin, xmax, s.bounds.x, s.bounds.width),
                    y: s.bounds.y + s.bounds.height - mapped(s.y[segment_count], y0, y1, 0.0, s.bounds.height),
                }
                let next = segment_count + 1usize
                let to = Coord {
                    x: mapped(s.x[next], xmin, xmax, s.bounds.x, s.bounds.width),
                    y: s.bounds.y + s.bounds.height - mapped(s.y[next], y0, y1, 0.0, s.bounds.height),
                }
                segments[segment_count] = Segment { from: from, to: to }
                segment_count += 1usize
            }
        }
    } else {
        if bars.len < s.x.len { ret (zero, TooLarge) }
        var width = s.bar_width
        if width <= 0.0 { width = s.bounds.width / f32(i64(s.x.len)) * 0.8 }
        if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
        while bar_count < s.x.len {
            let cx = mapped(s.x[bar_count], xmin, xmax, s.bounds.x, s.bounds.width)
            var top_value = s.baseline
            if s.y[bar_count] > top_value { top_value = s.y[bar_count] }
            var bottom_value = s.baseline
            if s.y[bar_count] < bottom_value { bottom_value = s.y[bar_count] }
            let top = s.bounds.y + s.bounds.height - mapped(top_value, y0, y1, 0.0, s.bounds.height)
            let bottom = s.bounds.y + s.bounds.height - mapped(bottom_value, y0, y1, 0.0, s.bounds.height)
            bars[bar_count] = geometry.rect(cx - width / 2.0, top, width, bottom - top)
            bar_count += 1usize
        }
    }
    ret (Layout { kind: s.kind, coords: coords[..coord_count], segments: segments[..segment_count], bars: bars[..bar_count], x_min: xmin, x_max: xmax, y_min: y0, y_max: y1 }, ok)
}
