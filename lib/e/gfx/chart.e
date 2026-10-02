// Declarative chart geometry. The first slice keeps data borrowed and emits
// renderer-neutral marks; scene, PNG and widget adapters can consume Layout.
//
// The contract is intentionally small: one numeric x/y mapping, one Cartesian
// bounds rectangle, and caller-owned output. More chart families compose on it.

use e.algo.stat
use e.gfx.geometry
use e.math
use e.math.special
use e.mem
use e.str

type Kind = enum u8 { Scatter, Line, Bar, Histogram, Step, Ecdf, Box, Density, Qq, Violin, Heatmap, Correlation, Area, Lollipop, ErrorBar, Band, Dumbbell, FrequencyPolygon, Rug, PointLine, Strip, Beeswarm, DotPlot, Waterfall }
type ScaleKind = enum u8 { Linear, Log10, Symlog }
type Scale = struct { kind: ScaleKind, reverse: bool, linthresh: f32 }
type Tick = struct { value: f32, fraction: f32 }
type Coord = struct { x: f32, y: f32 }
type LabelAlign = enum u8 { Left, Center, Right }
type Label = struct { text: str, anchor: Coord, align: LabelAlign }
type LegendItem = struct { swatch: geometry.Rect, label: Label }
type Segment = struct { from: Coord, to: Coord }
type Cell = struct { rect: geometry.Rect, value: f32 }
type Spec = struct { kind: Kind, bounds: geometry.Rect, x: []const f32, y: []const f32, baseline: f32, bar_width: f32, x_scale: Scale, y_scale: Scale }
type Layout = struct { kind: Kind, coords: []Coord, segments: []Segment, bars: []geometry.Rect, x_min: f32, x_max: f32, y_min: f32, y_max: f32 }
type MatrixLayout = struct { kind: Kind, cells: []Cell, columns: usize, rows: usize, value_min: f32, value_max: f32 }
error Invalid
error Empty
error TooLarge

fn spec(kind: Kind, bounds: geometry.Rect, x: []const f32, y: []const f32) -> Spec {
    let linear = Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    ret Spec { kind: kind, bounds: bounds, x: x, y: y, baseline: 0.0, bar_width: 0.0, x_scale: linear, y_scale: linear }
}

fn finite(v: f32) -> bool {
    ret v == v && v - v == 0.0
}

fn finite64(v: f64) -> bool {
    ret v == v && v - v == 0.0f64
}

fn valid_bounds(bounds: geometry.Rect) -> bool {
    ret finite(bounds.x) && finite(bounds.y) && finite(bounds.width) && finite(bounds.height) && bounds.width > 0.0 && bounds.height > 0.0
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

fn valid_scale(scale: Scale, lo: f32, hi: f32) -> bool {
    if !finite(lo) || !finite(hi) || !(hi > lo) { ret false }
    if scale.kind == .Log10 { ret lo > 0.0 }
    if scale.kind == .Symlog { ret finite(scale.linthresh) && scale.linthresh > 0.0 }
    ret true
}

fn transformed(value: f32, scale: Scale) -> f64 {
    if scale.kind == .Log10 { ret math.log10[f64](f64(value)) }
    if scale.kind == .Symlog {
        let unit = f64(value) / f64(scale.linthresh)
        if unit < 0.0f64 { ret 0.0f64 - math.log10[f64](1.0f64 - unit) }
        ret math.log10[f64](1.0f64 + unit)
    }
    ret f64(value)
}

fn fraction(value: f32, lo: f32, hi: f32, scale: Scale) -> f32 {
    let t = f32((transformed(value, scale) - transformed(lo, scale)) / (transformed(hi, scale) - transformed(lo, scale)))
    if scale.reverse { ret 1.0 - t }
    ret t
}

fn x_position(s: *const Spec, value: f32, lo: f32, hi: f32) -> f32 {
    ret s.bounds.x + s.bounds.width * fraction(value, lo, hi, s.x_scale)
}

fn y_position(s: *const Spec, value: f32, lo: f32, hi: f32) -> f32 {
    ret s.bounds.y + s.bounds.height * (1.0 - fraction(value, lo, hi, s.y_scale))
}

// Even breaks in transformed space, with data values and normalized positions
// returned to the caller for grid, label and interaction adapters.
fn ticks(scale: Scale, lo: f32, hi: f32, out: []Tick) -> ([]Tick, err) {
    if out.len < 2usize { ret (zero, TooLarge) }
    if !valid_scale(scale, lo, hi) { ret (zero, Invalid) }
    let first = transformed(lo, scale)
    let span = transformed(hi, scale) - first
    var i = 0usize
    while i < out.len {
        let t = f64(i) / f64(out.len - 1usize)
        let transformed_value = first + span * t
        var value = transformed_value
        if scale.kind == .Log10 {
            value = math.pow[f64](10.0f64, transformed_value)
        } else if scale.kind == .Symlog {
            if transformed_value < 0.0f64 {
                value = f64(scale.linthresh) * (1.0f64 - math.pow[f64](10.0f64, 0.0f64 - transformed_value))
            } else {
                value = f64(scale.linthresh) * (math.pow[f64](10.0f64, transformed_value) - 1.0f64)
            }
        }
        var position = f32(t)
        if scale.reverse { position = 1.0 - position }
        out[i] = Tick { value: f32(value), fraction: position }
        i += 1usize
    }
    out[0usize].value = lo
    out[out.len - 1usize].value = hi
    ret (out, ok)
}

// Prefer human-scale linear breaks and 1/2/5 decades on log axes. Symlog
// retains equal transformed-space positions until a symmetric break policy exists.
fn nice_ticks(scale: Scale, lo: f32, hi: f32, wanted: usize, out: []Tick) -> ([]Tick, err) {
    if wanted < 2usize { ret (zero, Invalid) }
    if out.len < wanted { ret (zero, TooLarge) }
    if !valid_scale(scale, lo, hi) { ret (zero, Invalid) }
    if scale.kind == .Symlog {
        let (made, tick_error) = ticks(scale, lo, hi, out[..wanted])
        ret (made, tick_error)
    }
    var count = 0usize
    if scale.kind == .Linear {
        let raw = (f64(hi) - f64(lo)) / f64(wanted - 1usize)
        let unit = math.pow[f64](10.0f64, math.floor[f64](math.log10[f64](raw)))
        let ratio = raw / unit
        var factor = 10.0f64
        if ratio <= 1.0f64 {
            factor = 1.0f64
        } else if ratio <= 2.0f64 {
            factor = 2.0f64
        } else if ratio <= 5.0f64 {
            factor = 5.0f64
        }
        let step = factor * unit
        var value = math.ceil[f64](f64(lo) / step) * step
        var attempts = 0usize
        while value <= f64(hi) + step * 0.000000001f64 && attempts < wanted + 2usize {
            let rounded = f32(value)
            if count < wanted && rounded >= lo && rounded <= hi && (count == 0usize || rounded > out[count - 1usize].value) {
                var at = fraction(rounded, lo, hi, scale)
                if at < 0.0 { at = 0.0 }
                if at > 1.0 { at = 1.0 }
                out[count] = Tick { value: rounded, fraction: at }
                count += 1usize
            }
            value += step
            attempts += 1usize
        }
    } else {
        let multipliers = [3]f64{ 1.0f64, 2.0f64, 5.0f64 }
        var candidates: [256]f32 = zero
        var candidate_count = 0usize
        var exponent = math.floor[f64](math.log10[f64](f64(lo)))
        let last = math.ceil[f64](math.log10[f64](f64(hi)))
        while exponent <= last {
            let unit = math.pow[f64](10.0f64, exponent)
            var m = 0usize
            while m < multipliers.len {
                let raw = multipliers[m] * unit
                if raw >= f64(lo) && raw <= f64(hi) {
                    let rounded = f32(raw)
                    if rounded >= lo && rounded <= hi && (candidate_count == 0usize || rounded > candidates[candidate_count - 1usize]) {
                        if candidate_count >= candidates.len { ret (zero, TooLarge) }
                        candidates[candidate_count] = rounded
                        candidate_count += 1usize
                    }
                }
                m += 1usize
            }
            exponent += 1.0f64
        }
        if candidate_count >= 2usize {
            count = candidate_count
            if count > wanted { count = wanted }
            var i = 0usize
            while i < count {
                let index = (i * (candidate_count - 1usize) + (count - 1usize) / 2usize) / (count - 1usize)
                let value = candidates[index]
                var at = fraction(value, lo, hi, scale)
                if at < 0.0 { at = 0.0 }
                if at > 1.0 { at = 1.0 }
                out[i] = Tick { value: value, fraction: at }
                i += 1usize
            }
        }
    }
    if count < 2usize {
        let (fallback, fallback_error) = ticks(scale, lo, hi, out[..2usize])
        ret (fallback, fallback_error)
    }
    ret (out[..count], ok)
}

// Text slices point into caller-owned storage, which must outlive the labels.
fn format_ticks(values: []const Tick, out: []str, storage: []u8) -> ([]str, err) {
    if out.len < values.len { ret (zero, TooLarge) }
    var used = 0usize
    var i = 0usize
    while i < values.len {
        if !finite(values[i].value) { ret (zero, Invalid) }
        if used == storage.len { ret (zero, TooLarge) }
        var arena = mem.arena_from(storage[used..])
        let (made, builder_error) = str.builder(&arena, 0usize)
        if builder_error != ok { ret (zero, builder_error) }
        var builder = made
        var value = values[i].value
        if value == 0.0 { value = 0.0 }
        try str.push_f32(&builder, value)
        let label = str.done(&builder)
        out[i] = label
        used += label.len
        i += 1usize
    }
    ret (out[..values.len], ok)
}

fn valid_label(label: *const Label) -> bool {
    if label.text.len == 0usize || !finite(label.anchor.x) || !finite(label.anchor.y) { ret false }
    var i = 0usize
    while i < label.text.len {
        if label.text[i] < 32u8 || label.text[i] == 127u8 { ret false }
        i += 1usize
    }
    ret true
}

// Caller supplies text (and therefore formatting); this only positions it.
// Anchors are text baselines, not bounding-box corners.
fn guide_labels(bounds: geometry.Rect, x_ticks: []const Tick, x_text: []const str, y_ticks: []const Tick, y_text: []const str, size: f32, out: []Label) -> ([]Label, err) {
    if !valid_bounds(bounds) || !finite(size) || size <= 0.0 || x_ticks.len != x_text.len || y_ticks.len != y_text.len { ret (zero, Invalid) }
    if out.len < x_ticks.len || out.len - x_ticks.len < y_ticks.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < x_ticks.len {
        let position = x_ticks[i].fraction
        if !finite(position) || position < 0.0 || position > 1.0 { ret (zero, Invalid) }
        let label = Label { text: x_text[i], anchor: Coord { x: bounds.x + bounds.width * position, y: bounds.y + bounds.height + size + 6.0 }, align: .Center }
        if !valid_label(&label) { ret (zero, Invalid) }
        out[i] = label
        i += 1usize
    }
    i = 0usize
    while i < y_ticks.len {
        let position = y_ticks[i].fraction
        if !finite(position) || position < 0.0 || position > 1.0 { ret (zero, Invalid) }
        let label = Label { text: y_text[i], anchor: Coord { x: bounds.x - 9.0, y: bounds.y + bounds.height * (1.0 - position) + size * 0.35 }, align: .Right }
        if !valid_label(&label) { ret (zero, Invalid) }
        out[x_ticks.len + i] = label
        i += 1usize
    }
    ret (out[..x_ticks.len + y_ticks.len], ok)
}

// Category centers use the same guide-label contract as numeric tick marks.
fn category_ticks(count: usize, out: []Tick) -> ([]Tick, err) {
    if count == 0usize { ret (zero, Empty) }
    if out.len < count { ret (zero, TooLarge) }
    var i = 0usize
    while i < count {
        out[i] = Tick { value: f32(i), fraction: f32((f64(i) + 0.5f64) / f64(count)) }
        i += 1usize
    }
    ret (out[..count], ok)
}

// Palette stays with the caller; each swatch and label shares its series index.
fn legend_items(names: []const str, origin: Coord, swatch: f32, row_height: f32, out: []LegendItem) -> ([]LegendItem, err) {
    if !finite(origin.x) || !finite(origin.y) || !finite(swatch) || !finite(row_height) || swatch <= 0.0 || row_height < swatch { ret (zero, Invalid) }
    if out.len < names.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < names.len {
        let y = origin.y + f32(i) * row_height
        let label = Label { text: names[i], anchor: Coord { x: origin.x + swatch + 6.0, y: y + swatch }, align: .Left }
        if !finite(y) || !valid_label(&label) { ret (zero, Invalid) }
        out[i] = LegendItem { swatch: geometry.rect(origin.x, y, swatch, swatch), label: label }
        i += 1usize
    }
    ret (out[..names.len], ok)
}

// Produces marks in screen coordinates. Y is inverted because graphics bounds
// use a top-left origin; the returned domain remains in data coordinates.
fn layout(s: *const Spec, coords: []Coord, segments: []Segment, bars: []geometry.Rect) -> (Layout, err) {
    let (marks, marks_error) = layout_with_limits(s, coords, segments, bars, s.x[..0usize], s.y[..0usize])
    ret (marks, marks_error)
}

// Empty limits use each series' own domain; two values fix the domain so
// multiple facet panels can share x, y, or both without copying their columns.
fn layout_with_limits(s: *const Spec, coords: []Coord, segments: []Segment, bars: []geometry.Rect, x_limits: []const f32, y_limits: []const f32) -> (Layout, err) {
    if s.kind == .PointLine {
        if coords.len < s.x.len || (s.x.len > 1usize && segments.len < s.x.len - 1usize) { ret (zero, TooLarge) }
        var points_spec = *s
        points_spec.kind = .Scatter
        let (points, points_error) = layout_with_limits(&points_spec, coords, segments, bars, x_limits, y_limits)
        if points_error != ok { ret (zero, points_error) }
        var line_spec = *s
        line_spec.kind = .Line
        let (line, line_error) = layout_with_limits(&line_spec, coords, segments, bars, x_limits, y_limits)
        if line_error != ok { ret (zero, line_error) }
        ret (Layout { kind: .PointLine, coords: points.coords, segments: line.segments, bars: zero, x_min: points.x_min, x_max: points.x_max, y_min: points.y_min, y_max: points.y_max }, ok)
    }
    if s.kind == .Histogram || s.kind == .Ecdf || s.kind == .Box || s.kind == .Density || s.kind == .Qq || s.kind == .Violin || s.kind == .Heatmap || s.kind == .Correlation || s.kind == .ErrorBar || s.kind == .Band || s.kind == .Dumbbell || s.kind == .FrequencyPolygon || s.kind == .Rug || s.kind == .Strip || s.kind == .Beeswarm || s.kind == .DotPlot { ret (zero, Invalid) }
    if s.x.len == 0usize { ret (zero, Empty) }
    if s.x.len != s.y.len || s.bounds.width <= 0.0 || s.bounds.height <= 0.0 { ret (zero, Invalid) }
    if (x_limits.len != 0usize && x_limits.len != 2usize) || (y_limits.len != 0usize && y_limits.len != 2usize) { ret (zero, Invalid) }
    if !finite(s.bounds.x) || !finite(s.bounds.y) || !finite(s.bounds.width) || !finite(s.bounds.height) { ret (zero, Invalid) }
    let (x0, x1, x_error) = extent(s.x)
    if x_error != ok { ret (zero, x_error) }
    let (raw_y0, raw_y1, y_error) = extent(s.y)
    if y_error != ok { ret (zero, y_error) }
    var y0 = raw_y0
    var y1 = raw_y1
    if s.kind == .Bar || s.kind == .Area || s.kind == .Lollipop {
        if !finite(s.baseline) { ret (zero, Invalid) }
        if s.baseline < y0 { y0 = s.baseline }
        if s.baseline > y1 { y1 = s.baseline }
    }
    var xmin = x0
    var xmax = x1
    if s.kind == .Bar && s.x_scale.kind == .Linear && s.x.len > 1usize && x_limits.len == 0usize {
        let pad = f32((f64(x1) - f64(x0)) / f64(s.x.len - 1usize) / 2.0f64)
        let left = x0 - pad
        let right = x1 + pad
        if finite(left) && finite(right) {
            xmin = left
            xmax = right
        }
    }
    if x_limits.len == 2usize {
        if !valid_scale(s.x_scale, x_limits[0usize], x_limits[1usize]) || x_limits[0usize] > x0 || x_limits[1usize] < x1 { ret (zero, Invalid) }
        xmin = x_limits[0usize]
        xmax = x_limits[1usize]
    }
    if y_limits.len == 2usize {
        if !valid_scale(s.y_scale, y_limits[0usize], y_limits[1usize]) || y_limits[0usize] > y0 || y_limits[1usize] < y1 { ret (zero, Invalid) }
        y0 = y_limits[0usize]
        y1 = y_limits[1usize]
    }
    if xmin == xmax {
        if s.x_scale.kind == .Log10 {
            if !(xmin > 0.0) { ret (zero, Invalid) }
            xmin = x0 / 2.0
            xmax = x0 * 2.0
            if !(xmin > 0.0) { xmin = x0 }
            if !finite(xmax) { xmax = x0 }
        } else {
            xmin -= 0.5
            xmax += 0.5
        }
    }
    if y0 == y1 {
        if s.y_scale.kind == .Log10 {
            if !(y0 > 0.0) { ret (zero, Invalid) }
            let constant = y0
            y0 = constant / 2.0
            y1 = constant * 2.0
            if !(y0 > 0.0) { y0 = constant }
            if !finite(y1) { y1 = constant }
        } else {
            y0 -= 0.5
            y1 += 0.5
        }
    }
    if !valid_scale(s.x_scale, xmin, xmax) || !valid_scale(s.y_scale, y0, y1) { ret (zero, Invalid) }

    var coord_count = 0usize
    var segment_count = 0usize
    var bar_count = 0usize
    if s.kind == .Scatter {
        if coords.len < s.x.len { ret (zero, TooLarge) }
        while coord_count < s.x.len {
            coords[coord_count] = Coord {
                x: x_position(s, s.x[coord_count], xmin, xmax),
                y: y_position(s, s.y[coord_count], y0, y1),
            }
            coord_count += 1usize
        }
    } else if s.kind == .Line {
        if segments.len + 1usize < s.x.len { ret (zero, TooLarge) }
        if s.x.len > 1usize {
            while segment_count + 1usize < s.x.len {
                let from = Coord {
                    x: x_position(s, s.x[segment_count], xmin, xmax),
                    y: y_position(s, s.y[segment_count], y0, y1),
                }
                let next = segment_count + 1usize
                let to = Coord {
                    x: x_position(s, s.x[next], xmin, xmax),
                    y: y_position(s, s.y[next], y0, y1),
                }
                segments[segment_count] = Segment { from: from, to: to }
                segment_count += 1usize
            }
        }
    } else if s.kind == .Area {
        if s.x.len < 2usize { ret (zero, Empty) }
        if coords.len / 2usize < s.x.len { ret (zero, TooLarge) }
        let baseline_y = y_position(s, s.baseline, y0, y1)
        var i = 0usize
        while i < s.x.len {
            if i > 0usize && s.x[i] < s.x[i - 1usize] { ret (zero, Invalid) }
            let x = x_position(s, s.x[i], xmin, xmax)
            coords[i] = Coord { x: x, y: y_position(s, s.y[i], y0, y1) }
            coords[2usize * s.x.len - 1usize - i] = Coord { x: x, y: baseline_y }
            i += 1usize
        }
        coord_count = 2usize * s.x.len
    } else if s.kind == .Lollipop {
        if coords.len < s.x.len || segments.len < s.x.len { ret (zero, TooLarge) }
        let baseline_y = y_position(s, s.baseline, y0, y1)
        while coord_count < s.x.len {
            let p = Coord { x: x_position(s, s.x[coord_count], xmin, xmax), y: y_position(s, s.y[coord_count], y0, y1) }
            coords[coord_count] = p
            segments[coord_count] = Segment { from: Coord { x: p.x, y: baseline_y }, to: p }
            coord_count += 1usize
        }
        segment_count = s.x.len
    } else if s.kind == .Step {
        if s.x.len > 1usize && segments.len / 2usize < s.x.len - 1usize { ret (zero, TooLarge) }
        var i = 0usize
        while i + 1usize < s.x.len {
            if s.x[i + 1usize] < s.x[i] { ret (zero, Invalid) }
            let left = Coord {
                x: x_position(s, s.x[i], xmin, xmax),
                y: y_position(s, s.y[i], y0, y1),
            }
            let right = Coord {
                x: x_position(s, s.x[i + 1usize], xmin, xmax),
                y: left.y,
            }
            let next = Coord {
                x: right.x,
                y: y_position(s, s.y[i + 1usize], y0, y1),
            }
            segments[segment_count] = Segment { from: left, to: right }
            segments[segment_count + 1usize] = Segment { from: right, to: next }
            segment_count += 2usize
            i += 1usize
        }
    } else {
        if bars.len < s.x.len { ret (zero, TooLarge) }
        var width = s.bar_width
        if width <= 0.0 { width = s.bounds.width / f32(i64(s.x.len)) * 0.8 }
        if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
        while bar_count < s.x.len {
            let cx = x_position(s, s.x[bar_count], xmin, xmax)
            var top_value = s.baseline
            if s.y[bar_count] > top_value { top_value = s.y[bar_count] }
            var bottom_value = s.baseline
            if s.y[bar_count] < bottom_value { bottom_value = s.y[bar_count] }
            var top = y_position(s, top_value, y0, y1)
            var bottom = y_position(s, bottom_value, y0, y1)
            if top > bottom {
                let old = top
                top = bottom
                bottom = old
            }
            bars[bar_count] = geometry.rect(cx - width / 2.0, top, width, bottom - top)
            bar_count += 1usize
        }
    }
    ret (Layout { kind: s.kind, coords: coords[..coord_count], segments: segments[..segment_count], bars: bars[..bar_count], x_min: xmin, x_max: xmax, y_min: y0, y_max: y1 }, ok)
}

// Vertical intervals with a point estimate and two caps per observation.
// Lower/upper values must enclose each estimate; all output is caller-owned.
fn error_bars(x: []const f32, center: []const f32, lower: []const f32, upper: []const f32, bounds: geometry.Rect, points: []Coord, lines: []Segment) -> (Layout, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if center.len != x.len || lower.len != x.len || upper.len != x.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if points.len < x.len || lines.len / 3usize < x.len { ret (zero, TooLarge) }
    let (raw_xmin, raw_xmax, x_error) = extent(x)
    if x_error != ok { ret (zero, x_error) }
    var ymin = lower[0usize]
    var ymax = upper[0usize]
    var i = 0usize
    while i < x.len {
        if !finite(center[i]) || !finite(lower[i]) || !finite(upper[i]) || lower[i] > center[i] || center[i] > upper[i] { ret (zero, Invalid) }
        if lower[i] < ymin { ymin = lower[i] }
        if upper[i] > ymax { ymax = upper[i] }
        i += 1usize
    }
    var xmin = raw_xmin
    var xmax = raw_xmax
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    i = 0usize
    while i < x.len {
        let px = mapped(x[i], xmin, xmax, bounds.x, bounds.width)
        let top = bounds.y + bounds.height - mapped(upper[i], ymin, ymax, 0.0, bounds.height)
        let bottom = bounds.y + bounds.height - mapped(lower[i], ymin, ymax, 0.0, bounds.height)
        let middle = bounds.y + bounds.height - mapped(center[i], ymin, ymax, 0.0, bounds.height)
        points[i] = Coord { x: px, y: middle }
        lines[3usize * i] = Segment { from: Coord { x: px, y: top }, to: Coord { x: px, y: bottom } }
        lines[3usize * i + 1usize] = Segment { from: Coord { x: px - 5.0, y: top }, to: Coord { x: px + 5.0, y: top } }
        lines[3usize * i + 2usize] = Segment { from: Coord { x: px - 5.0, y: bottom }, to: Coord { x: px + 5.0, y: bottom } }
        i += 1usize
    }
    ret (Layout { kind: .ErrorBar, coords: points[..x.len], segments: lines[..3usize * x.len], bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
}

// A closed ribbon between lower and upper series. Ordered x and contained
// intervals are required; the polygon remains in caller-provided storage.
fn band(x: []const f32, lower: []const f32, upper: []const f32, bounds: geometry.Rect, outline: []Coord) -> (Layout, err) {
    if x.len < 2usize { ret (zero, Empty) }
    if lower.len != x.len || upper.len != x.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if outline.len / 2usize < x.len { ret (zero, TooLarge) }
    let (xmin, xmax, x_error) = extent(x)
    if x_error != ok { ret (zero, x_error) }
    if xmin == xmax { ret (zero, Invalid) }
    var ymin = lower[0usize]
    var ymax = upper[0usize]
    var i = 0usize
    while i < x.len {
        if (i > 0usize && x[i] < x[i - 1usize]) || !finite(lower[i]) || !finite(upper[i]) || lower[i] > upper[i] { ret (zero, Invalid) }
        if lower[i] < ymin { ymin = lower[i] }
        if upper[i] > ymax { ymax = upper[i] }
        i += 1usize
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    if !finite(ymin) || !finite(ymax) { ret (zero, Invalid) }
    i = 0usize
    while i < x.len {
        let px = mapped(x[i], xmin, xmax, bounds.x, bounds.width)
        outline[i] = Coord { x: px, y: bounds.y + bounds.height - mapped(upper[i], ymin, ymax, 0.0, bounds.height) }
        outline[2usize * x.len - 1usize - i] = Coord { x: px, y: bounds.y + bounds.height - mapped(lower[i], ymin, ymax, 0.0, bounds.height) }
        i += 1usize
    }
    ret (Layout { kind: .Band, coords: outline[..2usize * x.len], segments: zero, bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
}

// Horizontal intervals with a dot at each endpoint; `position` is the
// numeric vertical axis, so repeated positions naturally overlay.
fn dumbbell(position: []const f32, lower: []const f32, upper: []const f32, bounds: geometry.Rect, points: []Coord, lines: []Segment) -> (Layout, err) {
    if position.len == 0usize { ret (zero, Empty) }
    if lower.len != position.len || upper.len != position.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if points.len / 2usize < position.len || lines.len < position.len { ret (zero, TooLarge) }
    let (raw_ymin, raw_ymax, y_error) = extent(position)
    if y_error != ok { ret (zero, y_error) }
    var xmin = lower[0usize]
    var xmax = upper[0usize]
    var i = 0usize
    while i < position.len {
        if !finite(lower[i]) || !finite(upper[i]) || lower[i] > upper[i] { ret (zero, Invalid) }
        if lower[i] < xmin { xmin = lower[i] }
        if upper[i] > xmax { xmax = upper[i] }
        i += 1usize
    }
    var ymin = raw_ymin
    var ymax = raw_ymax
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    if !finite(xmin) || !finite(xmax) || !finite(ymin) || !finite(ymax) { ret (zero, Invalid) }
    i = 0usize
    while i < position.len {
        let py = bounds.y + bounds.height - mapped(position[i], ymin, ymax, 0.0, bounds.height)
        let left = Coord { x: mapped(lower[i], xmin, xmax, bounds.x, bounds.width), y: py }
        let right = Coord { x: mapped(upper[i], xmin, xmax, bounds.x, bounds.width), y: py }
        points[2usize * i] = left
        points[2usize * i + 1usize] = right
        lines[i] = Segment { from: left, to: right }
        i += 1usize
    }
    ret (Layout { kind: .Dumbbell, coords: points[..2usize * position.len], segments: lines[..position.len], bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
}

fn bar_grid_ok(values: []const f32, categories: usize, series: usize, bounds: geometry.Rect) -> bool {
    ret valid_bounds(bounds) && values.len / categories == series && values.len % categories == 0usize && finite(f32(categories))
}

// Series-major output lets each caller-owned layer be painted with its own
// colour by the existing Bar adapter; input observations are category-major.
fn bar_layers(categories: usize, series: usize, bars: []geometry.Rect, layers: []Layout, ymin: f32, ymax: f32) -> []Layout {
    var i = 0usize
    while i < series {
        let first = i * categories
        layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[first..first + categories], x_min: 0.0, x_max: f32(categories), y_min: ymin, y_max: ymax }
        i += 1usize
    }
    ret layers[..series]
}

// The first value is an absolute starting total; later values are signed
// changes. The final bar is the resulting total, with level connectors.
fn waterfall(values: []const f32, bounds: geometry.Rect, bars: []geometry.Rect, connectors: []Segment) -> (Layout, err) {
    if values.len < 2usize { ret (zero, Empty) }
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    if bars.len <= values.len || connectors.len < values.len { ret (zero, TooLarge) }
    var low = 0.0f64
    var high = 0.0f64
    var total = 0.0f64
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) { ret (zero, Invalid) }
        let before = total
        if i == 0usize { total = f64(values[i]) } else { total += f64(values[i]) }
        if !finite(f32(total)) { ret (zero, Invalid) }
        if before < low { low = before }
        if before > high { high = before }
        if total < low { low = total }
        if total > high { high = total }
        i += 1usize
    }
    var ymin = f32(low)
    var ymax = f32(high)
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    let count = values.len + 1usize
    let cell = bounds.width / f32(count)
    let width = cell * 0.72
    if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
    let offset = (cell - width) * 0.5
    total = 0.0f64
    i = 0usize
    while i < count {
        let before = total
        if i < values.len {
            if i == 0usize { total = f64(values[i]) } else { total += f64(values[i]) }
        }
        var from = f32(before)
        if i == 0usize || i == values.len { from = 0.0 }
        let y0 = bounds.y + bounds.height - mapped(from, ymin, ymax, 0.0, bounds.height)
        let y1 = bounds.y + bounds.height - mapped(f32(total), ymin, ymax, 0.0, bounds.height)
        var top = y0
        var bottom = y1
        if top > bottom {
            top = y1
            bottom = y0
        }
        let x = bounds.x + cell * f32(i) + offset
        bars[i] = geometry.rect(x, top, width, bottom - top)
        if i < values.len {
            let level = bounds.y + bounds.height - mapped(f32(total), ymin, ymax, 0.0, bounds.height)
            connectors[i] = Segment { from: Coord { x: x + width, y: level }, to: Coord { x: x + cell, y: level } }
        }
        i += 1usize
    }
    ret (Layout { kind: .Waterfall, coords: zero, segments: connectors[..values.len], bars: bars[..count], x_min: 0.0, x_max: f32(count), y_min: ymin, y_max: ymax }, ok)
}

// Qualitative ranges paint widest to narrowest, then actual and target.
// The caller chooses one brush per layer; no new painter is needed.
fn bullet(actual: f32, target_value: f32, ranges: []const f32, bounds: geometry.Rect, bars: []geometry.Rect, target_line: []Segment, layers: []Layout) -> ([]Layout, err) {
    if ranges.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(actual) || !finite(target_value) { ret (zero, Invalid) }
    if bars.len <= ranges.len || target_line.len == 0usize || layers.len < 2usize || layers.len - 2usize < ranges.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < ranges.len {
        if !finite(ranges[i]) || ranges[i] <= 0.0 || (i > 0usize && ranges[i] <= ranges[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    let maximum = ranges[ranges.len - 1usize]
    if actual < 0.0 || actual > maximum || target_value < 0.0 || target_value > maximum { ret (zero, Invalid) }
    i = 0usize
    while i < ranges.len {
        let endpoint = ranges[ranges.len - 1usize - i]
        bars[i] = geometry.rect(bounds.x, bounds.y, bounds.width * (endpoint / maximum), bounds.height)
        layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[i..i + 1usize], x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    bars[i] = geometry.rect(bounds.x, bounds.y + bounds.height * 0.325, bounds.width * (actual / maximum), bounds.height * 0.35)
    layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[i..i + 1usize], x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: 1.0 }
    let x = bounds.x + bounds.width * (target_value / maximum)
    target_line[0usize] = Segment { from: Coord { x: x, y: bounds.y }, to: Coord { x: x, y: bounds.y + bounds.height } }
    layers[i + 1usize] = Layout { kind: .Rug, coords: zero, segments: target_line[..1usize], bars: zero, x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: 1.0 }
    ret (layers[..ranges.len + 2usize], ok)
}

// Descending frequency bars and a cumulative fraction line share category
// centres. `order` maps rendered positions back to the borrowed input.
fn pareto(values: []const f32, bounds: geometry.Rect, order: []usize, bars: []geometry.Rect, points: []Coord, lines: []Segment, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    if order.len < values.len || bars.len < values.len || points.len < values.len || (values.len > 1usize && lines.len < values.len - 1usize) || layers.len < 2usize { ret (zero, TooLarge) }
    var total = 0.0f64
    var maximum = 0.0f32
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) || values[i] < 0.0 { ret (zero, Invalid) }
        total += f64(values[i])
        if values[i] > maximum { maximum = values[i] }
        order[i] = i
        i += 1usize
    }
    if total <= 0.0f64 { ret (zero, Invalid) }
    // ponytail: insertion sort is quadratic; use caller-scratch mergesort for very wide category sets.
    i = 1usize
    while i < values.len {
        let selected = order[i]
        var j = i
        while j > 0usize && values[order[j - 1usize]] < values[selected] {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = selected
        i += 1usize
    }
    let cell = bounds.width / f32(values.len)
    let width = cell * 0.8
    if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
    var cumulative = 0.0f64
    i = 0usize
    while i < values.len {
        let value = values[order[i]]
        cumulative += f64(value)
        let x = bounds.x + cell * f32(i)
        let height = bounds.height * (value / maximum)
        bars[i] = geometry.rect(x + cell * 0.1, bounds.y + bounds.height - height, width, height)
        points[i] = Coord { x: x + cell * 0.5, y: bounds.y + bounds.height * (1.0 - f32(cumulative / total)) }
        if i > 0usize { lines[i - 1usize] = Segment { from: points[i - 1usize], to: points[i] } }
        i += 1usize
    }
    layers[0usize] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[..values.len], x_min: 0.0, x_max: f32(values.len), y_min: 0.0, y_max: maximum }
    layers[1usize] = Layout { kind: .PointLine, coords: points[..values.len], segments: lines[..values.len - 1usize], bars: zero, x_min: 0.0, x_max: f32(values.len), y_min: 0.0, y_max: 1.0 }
    ret (layers[..2usize], ok)
}

// Each slice is a filled polygon; hole=0 gives a pie, 0<hole<1 a donut.
// A fixed full-circle tessellation keeps the painter and SVG paths identical.
fn pie(values: []const f32, bounds: geometry.Rect, hole: f32, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(hole) || hole < 0.0 || hole >= 1.0 { ret (zero, Invalid) }
    if layers.len < values.len { ret (zero, TooLarge) }
    var total = 0.0f64
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) || values[i] < 0.0 { ret (zero, Invalid) }
        total += f64(values[i])
        i += 1usize
    }
    if total <= 0.0f64 { ret (zero, Invalid) }
    var needed = 0usize
    i = 0usize
    while i < values.len {
        let steps = 2usize + usize(f64(values[i]) / total * 96.0f64)
        let count = 2usize * (steps + 1usize)
        if needed > points.len || count > points.len - needed { ret (zero, TooLarge) }
        needed += count
        i += 1usize
    }
    var radius = f64(bounds.width) * 0.5f64
    if bounds.height < bounds.width { radius = f64(bounds.height) * 0.5f64 }
    let inner = radius * f64(hole)
    let center_x = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let center_y = f64(bounds.y) + f64(bounds.height) * 0.5f64
    if !finite(f32(center_x)) || !finite(f32(center_y)) { ret (zero, Invalid) }
    var used = 0usize
    var cumulative = 0.0f64
    i = 0usize
    while i < values.len {
        let fraction_of_total = f64(values[i]) / total
        let start = -1.5707963267948966f64 + 6.283185307179586f64 * cumulative / total
        cumulative += f64(values[i])
        let finish = start + 6.283185307179586f64 * fraction_of_total
        let steps = 2usize + usize(fraction_of_total * 96.0f64)
        let first = used
        var j = 0usize
        while j <= steps {
            let angle = start + (finish - start) * f64(j) / f64(steps)
            points[used] = Coord { x: f32(center_x + radius * math.cos[f64](angle)), y: f32(center_y + radius * math.sin[f64](angle)) }
            used += 1usize
            j += 1usize
        }
        j = 0usize
        while j <= steps {
            let angle = finish - (finish - start) * f64(j) / f64(steps)
            points[used] = Coord { x: f32(center_x + inner * math.cos[f64](angle)), y: f32(center_y + inner * math.sin[f64](angle)) }
            used += 1usize
            j += 1usize
        }
        layers[i] = Layout { kind: .Area, coords: points[first..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..values.len], ok)
}

// Ordered categories occupy a fixed grid, rounded at cumulative boundaries.
fn waffle(values: []const f32, bounds: geometry.Rect, columns: usize, rows: usize, gap: f32, bars: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || columns == 0usize || rows == 0usize || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if columns > bars.len / rows || layers.len < values.len { ret (zero, TooLarge) }
    let count = columns * rows
    let width = bounds.width / f32(columns)
    let height = bounds.height / f32(rows)
    if !finite(width) || !finite(height) || gap >= width || gap >= height { ret (zero, Invalid) }
    var total = 0.0f64
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) || values[i] < 0.0 { ret (zero, Invalid) }
        total += f64(values[i])
        i += 1usize
    }
    if total <= 0.0f64 { ret (zero, Invalid) }
    var cumulative = 0.0f64
    var used = 0usize
    i = 0usize
    while i < values.len {
        cumulative += f64(values[i])
        var end_cell = count
        if i + 1usize < values.len {
            // ponytail: ordered cumulative rounding can bias a category by one cell;
            // use caller-scratch largest remainders if per-category fairness matters.
            end_cell = usize(cumulative / total * f64(count) + 0.5f64)
            if end_cell > count { end_cell = count }
        }
        let first = used
        while used < end_cell {
            let column = used % columns
            let row = used / columns
            bars[used] = geometry.rect(bounds.x + width * f32(column) + gap * 0.5,
                bounds.y + bounds.height - height * f32(row + 1usize) + gap * 0.5,
                width - gap, height - gap)
            used += 1usize
        }
        layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[first..used], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..values.len], ok)
}

// A stage funnel tapers each segment to the next nonincreasing value.
fn funnel(values: []const f32, bounds: geometry.Rect, gap: f32, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if values.len > points.len / 4usize || layers.len < values.len { ret (zero, TooLarge) }
    if !finite(values[0usize]) || values[0usize] <= 0.0 { ret (zero, Invalid) }
    let slot = bounds.height / f32(values.len)
    if !finite(slot) || gap >= slot { ret (zero, Invalid) }
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) || values[i] < 0.0 || (i > 0usize && values[i] > values[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    i = 0usize
    while i < values.len {
        var lower = values[i]
        if i + 1usize < values.len { lower = values[i + 1usize] }
        let top_width = bounds.width * (values[i] / values[0usize])
        let bottom_width = bounds.width * (lower / values[0usize])
        let center = bounds.x + bounds.width * 0.5
        let top = bounds.y + slot * f32(i)
        let bottom = top + slot - gap
        let first = 4usize * i
        points[first] = Coord { x: center - top_width * 0.5, y: top }
        points[first + 1usize] = Coord { x: center + top_width * 0.5, y: top }
        points[first + 2usize] = Coord { x: center + bottom_width * 0.5, y: bottom }
        points[first + 3usize] = Coord { x: center - bottom_width * 0.5, y: bottom }
        layers[i] = Layout { kind: .Area, coords: points[first..first + 4usize], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..values.len], ok)
}

fn grouped_bars(values: []const f32, categories: usize, series: usize, bounds: geometry.Rect, bars: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if categories == 0usize || series == 0usize { ret (zero, Invalid) }
    if !bar_grid_ok(values, categories, series, bounds) { ret (zero, Invalid) }
    if bars.len < values.len || layers.len < series { ret (zero, TooLarge) }
    var ymin = 0.0f32
    var ymax = 0.0f32
    var i = 0usize
    while i < values.len {
        if !finite(values[i]) { ret (zero, Invalid) }
        if values[i] < ymin { ymin = values[i] }
        if values[i] > ymax { ymax = values[i] }
        i += 1usize
    }
    if ymin == ymax {
        ymin = -0.5
        ymax = 0.5
    }
    let cell = bounds.width / f32(categories)
    let width = cell * 0.8 / f32(series)
    if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
    var category = 0usize
    while category < categories {
        var column = 0usize
        while column < series {
            let value = values[category * series + column]
            let baseline_y = bounds.y + bounds.height - mapped(0.0, ymin, ymax, 0.0, bounds.height)
            let value_y = bounds.y + bounds.height - mapped(value, ymin, ymax, 0.0, bounds.height)
            var top = baseline_y
            var bottom = value_y
            if top > bottom {
                let old = top
                top = bottom
                bottom = old
            }
            bars[column * categories + category] = geometry.rect(bounds.x + cell * f32(category) + cell * 0.1 + width * f32(column), top, width, bottom - top)
            column += 1usize
        }
        category += 1usize
    }
    ret (bar_layers(categories, series, bars, layers, ymin, ymax), ok)
}

// Positive and negative values stack away from zero independently. With
// normalize=true, every category must have a positive total and no negatives.
fn stacked_bars(values: []const f32, categories: usize, series: usize, bounds: geometry.Rect, normalize: bool, bars: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if categories == 0usize || series == 0usize { ret (zero, Invalid) }
    if !bar_grid_ok(values, categories, series, bounds) { ret (zero, Invalid) }
    if bars.len < values.len || layers.len < series { ret (zero, TooLarge) }
    var ymin = 0.0f64
    var ymax = 0.0f64
    var category = 0usize
    while category < categories {
        var positive = 0.0f64
        var negative = 0.0f64
        var column = 0usize
        while column < series {
            let value = values[category * series + column]
            if !finite(value) || (normalize && value < 0.0) { ret (zero, Invalid) }
            if value >= 0.0 { positive += f64(value) } else { negative += f64(value) }
            column += 1usize
        }
        if !finite(f32(positive)) || !finite(f32(negative)) || (normalize && positive <= 0.0f64) { ret (zero, Invalid) }
        if negative < ymin { ymin = negative }
        if positive > ymax { ymax = positive }
        category += 1usize
    }
    if normalize {
        ymin = 0.0f64
        ymax = 1.0f64
    }
    if ymin == ymax {
        ymin = -0.5f64
        ymax = 0.5f64
    }
    let low = f32(ymin)
    let high = f32(ymax)
    let cell = bounds.width / f32(categories)
    let width = cell * 0.8
    if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
    category = 0usize
    while category < categories {
        var total = 1.0f64
        if normalize {
            total = 0.0f64
            var s = 0usize
            while s < series {
                total += f64(values[category * series + s])
                s += 1usize
            }
        }
        var positive = 0.0f64
        var negative = 0.0f64
        var column = 0usize
        while column < series {
            let value = f64(values[category * series + column]) / total
            var from = positive
            if value >= 0.0f64 {
                positive += value
            } else {
                from = negative
                negative += value
            }
            var to = positive
            if value < 0.0f64 { to = negative }
            let from_y = bounds.y + bounds.height - mapped(f32(from), low, high, 0.0, bounds.height)
            let to_y = bounds.y + bounds.height - mapped(f32(to), low, high, 0.0, bounds.height)
            var top = from_y
            var bottom = to_y
            if top > bottom {
                let old = top
                top = bottom
                bottom = old
            }
            bars[column * categories + category] = geometry.rect(bounds.x + cell * f32(category) + cell * 0.1, top, width, bottom - top)
            column += 1usize
        }
        category += 1usize
    }
    ret (bar_layers(categories, series, bars, layers, low, high), ok)
}

// Equal-width bins, left-closed/right-open except the last bin (which includes
// the maximum). Counts and rectangles are caller-owned; bars touch edge to edge.
fn histogram(values: []const f32, bounds: geometry.Rect, counts: []u64, bars: []geometry.Rect) -> (Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if counts.len == 0usize || counts.len != bars.len { ret (zero, Invalid) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    let (raw_min, raw_max, range_error) = extent(values)
    if range_error != ok { ret (zero, range_error) }
    var xmin = raw_min
    var xmax = raw_max
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
        if xmin == xmax {
            if xmin > 0.0 { xmin *= 0.5 } else { xmax *= 0.5 }
        }
    }
    var i = 0usize
    while i < counts.len {
        counts[i] = 0u64
        i += 1usize
    }
    if raw_min == raw_max {
        counts[counts.len / 2usize] = u64(values.len)
    } else {
        let span = f64(xmax) - f64(xmin)
        i = 0usize
        while i < values.len {
            var bin = counts.len - 1usize
            if values[i] < xmax {
                bin = usize((f64(values[i]) - f64(xmin)) / span * f64(counts.len))
                if bin >= counts.len { bin = counts.len - 1usize }
            }
            counts[bin] += 1u64
            i += 1usize
        }
    }
    var tallest = 0u64
    i = 0usize
    while i < counts.len {
        if counts[i] > tallest { tallest = counts[i] }
        i += 1usize
    }
    let bar_width = bounds.width / f32(counts.len)
    i = 0usize
    while i < counts.len {
        let height = bounds.height * f32(counts[i]) / f32(tallest)
        bars[i] = geometry.rect(bounds.x + f32(i) * bar_width, bounds.y + bounds.height - height, bar_width, height)
        i += 1usize
    }
    ret (Layout { kind: .Histogram, coords: zero, segments: zero, bars: bars, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: f32(tallest) }, ok)
}

// Connect each histogram bin center, closing at zero at the outer bin edges.
fn frequency_polygon(values: []const f32, bounds: geometry.Rect, counts: []u64, bins: []geometry.Rect, segments: []Segment) -> (Layout, err) {
    let (hist, hist_error) = histogram(values, bounds, counts, bins)
    if hist_error != ok { ret (zero, hist_error) }
    if segments.len <= bins.len { ret (zero, TooLarge) }
    let baseline = bounds.y + bounds.height
    var previous = Coord { x: bounds.x, y: baseline }
    var i = 0usize
    while i < bins.len {
        let center = Coord { x: bins[i].x + bins[i].width * 0.5, y: bins[i].y }
        segments[i] = Segment { from: previous, to: center }
        previous = center
        i += 1usize
    }
    segments[i] = Segment { from: previous, to: Coord { x: bounds.x + bounds.width, y: baseline } }
    ret (Layout { kind: .FrequencyPolygon, coords: zero, segments: segments[..i + 1usize], bars: zero, x_min: hist.x_min, x_max: hist.x_max, y_min: hist.y_min, y_max: hist.y_max }, ok)
}

// Each observation is a short independent mark along the bottom x axis.
fn rug(values: []const f32, bounds: geometry.Rect, height: f32, segments: []Segment) -> (Layout, err) {
    if !valid_bounds(bounds) || !finite(height) || height <= 0.0 || height > bounds.height { ret (zero, Invalid) }
    if segments.len < values.len { ret (zero, TooLarge) }
    let (raw_min, raw_max, range_error) = extent(values)
    if range_error != ok { ret (zero, range_error) }
    var xmin = raw_min
    var xmax = raw_max
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
        if xmin == xmax {
            if xmin > 0.0 { xmin *= 0.5 } else { xmax *= 0.5 }
        }
    }
    var i = 0usize
    while i < values.len {
        let x = mapped(values[i], xmin, xmax, bounds.x, bounds.width)
        segments[i] = Segment { from: Coord { x: x, y: bounds.y + bounds.height }, to: Coord { x: x, y: bounds.y + bounds.height - height } }
        i += 1usize
    }
    ret (Layout { kind: .Rug, coords: zero, segments: segments[..values.len], bars: zero, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: 1.0 }, ok)
}

// Show every observation at its numeric x value with repeatable vertical jitter.
fn strip(values: []const f32, bounds: geometry.Rect, spread: f32, coords: []Coord) -> (Layout, err) {
    if !valid_bounds(bounds) || !finite(spread) || spread < 0.0 || spread > bounds.height * 0.5 { ret (zero, Invalid) }
    if coords.len < values.len { ret (zero, TooLarge) }
    let (raw_min, raw_max, range_error) = extent(values)
    if range_error != ok { ret (zero, range_error) }
    var xmin = raw_min
    var xmax = raw_max
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
        if xmin == xmax {
            if xmin > 0.0 { xmin *= 0.5 } else { xmax *= 0.5 }
        }
    }
    var i = 0usize
    while i < values.len {
        // ponytail: eleven jitter offsets repeat; use beeswarm packing when overlap matters.
        let slot = ((i % 11usize) * 7usize) % 11usize
        coords[i] = Coord { x: mapped(values[i], xmin, xmax, bounds.x, bounds.width), y: bounds.y + bounds.height * 0.5 + (f32(slot) - 5.0) * spread / 5.0 }
        i += 1usize
    }
    ret (Layout { kind: .Strip, coords: coords[..values.len], segments: zero, bars: zero, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: 1.0 }, ok)
}

// Keep exact numeric x positions while packing square marks into free y lanes.
fn beeswarm(values: []const f32, bounds: geometry.Rect, spacing: f32, coords: []Coord) -> (Layout, err) {
    if !valid_bounds(bounds) || bounds.height < 6.0 || !finite(spacing) || spacing < 6.0 { ret (zero, Invalid) }
    let (base, base_error) = strip(values, bounds, 0.0, coords)
    if base_error != ok { ret (zero, base_error) }
    let center = bounds.y + bounds.height * 0.5
    var i = 0usize
    while i < values.len {
        var placed = false
        var slot = 0usize
        // ponytail: cubic worst-case packing suits small plots; index x lanes for large clouds.
        while slot <= i && !placed {
            let distance = f32((slot + 1usize) / 2usize) * spacing
            if distance > bounds.height * 0.5 - 3.0 { ret (zero, TooLarge) }
            var y = center - distance
            if slot % 2usize == 1usize { y = center + distance }
            var blocked = false
            var j = 0usize
            while j < i && !blocked {
                let dx = coords[i].x - coords[j].x
                let dy = y - coords[j].y
                if dx > -6.0 && dx < 6.0 && dy > -6.0 && dy < 6.0 { blocked = true }
                j += 1usize
            }
            if !blocked {
                coords[i].y = y
                placed = true
            }
            slot += 1usize
        }
        if !placed { ret (zero, TooLarge) }
        i += 1usize
    }
    var marks = base
    marks.kind = .Beeswarm
    ret (marks, ok)
}

// Histogram counts become one dot per observation, stacked in each bin.
fn dot_plot(values: []const f32, bounds: geometry.Rect, spacing: f32, counts: []u64, bins: []geometry.Rect, coords: []Coord) -> (Layout, err) {
    if !finite(spacing) || spacing < 6.0 { ret (zero, Invalid) }
    if coords.len < values.len { ret (zero, TooLarge) }
    let (hist, hist_error) = histogram(values, bounds, counts, bins)
    if hist_error != ok { ret (zero, hist_error) }
    if (hist.y_max - 1.0) * spacing + 6.0 > bounds.height { ret (zero, TooLarge) }
    var used = 0usize
    var bin = 0usize
    while bin < bins.len {
        let x = bins[bin].x + bins[bin].width * 0.5
        var row = 0u64
        while row < counts[bin] {
            coords[used] = Coord { x: x, y: bounds.y + bounds.height - 3.0 - f32(row) * spacing }
            used += 1usize
            row += 1u64
        }
        bin += 1usize
    }
    ret (Layout { kind: .DotPlot, coords: coords[..used], segments: zero, bars: zero, x_min: hist.x_min, x_max: hist.x_max, y_min: 0.0, y_max: 1.0 }, ok)
}

// Empirical CDF of an ascending sample. Each observation raises the step by
// 1/n; repeated values produce coincident rises at the same x coordinate.
fn ecdf(sorted: []const f32, bounds: geometry.Rect, segments: []Segment) -> (Layout, err) {
    if sorted.len == 0usize { ret (zero, Empty) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    if segments.len < sorted.len || segments.len - sorted.len < sorted.len - 1usize { ret (zero, TooLarge) }
    let (raw_min, raw_max, range_error) = extent(sorted)
    if range_error != ok { ret (zero, range_error) }
    var xmin = raw_min
    var xmax = raw_max
    if xmin == xmax {
        xmin -= 0.5
        xmax += 0.5
        if xmin == xmax {
            if xmin > 0.0 { xmin *= 0.5 } else { xmax *= 0.5 }
        }
    }
    var count = 0usize
    var i = 0usize
    while i < sorted.len {
        if i > 0usize && sorted[i] < sorted[i - 1usize] { ret (zero, Invalid) }
        let x = mapped(sorted[i], xmin, xmax, bounds.x, bounds.width)
        let previous_y = bounds.y + bounds.height * (1.0 - f32(i) / f32(sorted.len))
        let next_y = bounds.y + bounds.height * (1.0 - f32(i + 1usize) / f32(sorted.len))
        if i > 0usize {
            let old_x = mapped(sorted[i - 1usize], xmin, xmax, bounds.x, bounds.width)
            segments[count] = Segment { from: Coord { x: old_x, y: previous_y }, to: Coord { x: x, y: previous_y } }
            count += 1usize
        }
        segments[count] = Segment { from: Coord { x: x, y: previous_y }, to: Coord { x: x, y: next_y } }
        count += 1usize
        i += 1usize
    }
    ret (Layout { kind: .Ecdf, coords: zero, segments: segments[..count], bars: zero, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: 1.0 }, ok)
}

fn box_y(value: f64, lo: f64, hi: f64, bounds: geometry.Rect) -> f32 {
    ret bounds.y + bounds.height * f32(1.0f64 - (value - lo) / (hi - lo))
}

// One vertical Tukey box: R7 quartiles, whiskers at the most extreme sample
// within 1.5 IQR, and caller-owned coordinates for values beyond the fences.
fn box_plot(sorted: []const f64, bounds: geometry.Rect, outliers: []Coord, lines: []Segment, boxes: []geometry.Rect) -> (Layout, err) {
    if sorted.len == 0usize { ret (zero, Empty) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    if lines.len < 5usize || boxes.len < 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < sorted.len {
        if !finite(f32(sorted[i])) || (i > 0usize && sorted[i] < sorted[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    let (q1, first_ok) = stat.quantile(sorted, 0.25f64, .R7)
    let (median, middle_ok) = stat.quantile(sorted, 0.5f64, .R7)
    let (q3, third_ok) = stat.quantile(sorted, 0.75f64, .R7)
    if !first_ok || !middle_ok || !third_ok { ret (zero, Invalid) }
    let spread = q3 - q1
    let lower_fence = q1 - 1.5f64 * spread
    let upper_fence = q3 + 1.5f64 * spread
    var lower = sorted[0usize]
    var upper = sorted[sorted.len - 1usize]
    var outlier_count = 0usize
    i = 0usize
    while i < sorted.len {
        if sorted[i] < lower_fence || sorted[i] > upper_fence {
            outlier_count += 1usize
        } else {
            if sorted[i] < lower || lower < lower_fence { lower = sorted[i] }
            if sorted[i] > upper || upper > upper_fence { upper = sorted[i] }
        }
        i += 1usize
    }
    if outliers.len < outlier_count { ret (zero, TooLarge) }
    var lo = sorted[0usize]
    var hi = sorted[sorted.len - 1usize]
    if lo == hi {
        lo -= 0.5f64
        hi += 0.5f64
    }
    let cx = bounds.x + bounds.width / 2.0
    let width = bounds.width * 0.36
    let cap = width * 0.5
    let low_y = box_y(lower, lo, hi, bounds)
    let q1_y = box_y(q1, lo, hi, bounds)
    let mid_y = box_y(median, lo, hi, bounds)
    let q3_y = box_y(q3, lo, hi, bounds)
    let high_y = box_y(upper, lo, hi, bounds)
    boxes[0usize] = geometry.rect(cx - width / 2.0, q3_y, width, q1_y - q3_y)
    lines[0usize] = Segment { from: Coord { x: cx, y: q1_y }, to: Coord { x: cx, y: low_y } }
    lines[1usize] = Segment { from: Coord { x: cx, y: q3_y }, to: Coord { x: cx, y: high_y } }
    lines[2usize] = Segment { from: Coord { x: cx - cap / 2.0, y: low_y }, to: Coord { x: cx + cap / 2.0, y: low_y } }
    lines[3usize] = Segment { from: Coord { x: cx - cap / 2.0, y: high_y }, to: Coord { x: cx + cap / 2.0, y: high_y } }
    lines[4usize] = Segment { from: Coord { x: cx - width / 2.0, y: mid_y }, to: Coord { x: cx + width / 2.0, y: mid_y } }
    var placed = 0usize
    i = 0usize
    while i < sorted.len {
        if sorted[i] < lower_fence || sorted[i] > upper_fence {
            outliers[placed] = Coord { x: cx, y: box_y(sorted[i], lo, hi, bounds) }
            placed += 1usize
        }
        i += 1usize
    }
    ret (Layout { kind: .Box, coords: outliers[..placed], segments: lines[..5usize], bars: boxes[..1usize], x_min: 0.0, x_max: 1.0, y_min: f32(lo), y_max: f32(hi) }, ok)
}

// Shared Gaussian estimate for density and violin marks. The caller owns both
// arrays; zero bandwidth selects Scott's rule.
fn kde_grid(values: []const f64, bandwidth: f64, grid: []f64, estimates: []f64) -> (f64, f64, f64, err) {
    if values.len == 0usize { ret (0.0f64, 0.0f64, 0.0f64, Empty) }
    if grid.len < 2usize || estimates.len < grid.len { ret (0.0f64, 0.0f64, 0.0f64, TooLarge) }
    var lo = values[0usize]
    var hi = lo
    var i = 0usize
    while i < values.len {
        if !finite(f32(values[i])) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
        if values[i] < lo { lo = values[i] }
        if values[i] > hi { hi = values[i] }
        i += 1usize
    }
    var bw = bandwidth
    if bw == 0.0f64 {
        let (chosen, has_bandwidth) = stat.kde_bandwidth(values, .Scott)
        if !has_bandwidth { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
        bw = chosen
    }
    if !(bw > 0.0f64) || !finite(f32(bw)) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    lo -= 3.0f64 * bw
    hi += 3.0f64 * bw
    if !finite(f32(lo)) || !finite(f32(hi)) || !(hi > lo) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    i = 0usize
    while i < grid.len {
        grid[i] = lo + (hi - lo) * f64(i) / f64(grid.len - 1usize)
        i += 1usize
    }
    let density_error = stat.kde(values, bw, grid, estimates)
    if density_error != ok { ret (0.0f64, 0.0f64, 0.0f64, density_error) }
    var peak = 0.0f64
    i = 0usize
    while i < grid.len {
        if estimates[i] > peak { peak = estimates[i] }
        i += 1usize
    }
    if !(peak > 0.0f64) || !finite(f32(peak)) { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    ret (lo, hi, peak, ok)
}

// Gaussian KDE on an equally spaced caller-owned grid. Zero bandwidth selects
// Scott's rule; a positive bandwidth is an explicit caller calibration.
fn density(values: []const f64, bounds: geometry.Rect, bandwidth: f64, grid: []f64, estimates: []f64, segments: []Segment) -> (Layout, err) {
    if grid.len < 2usize || segments.len < grid.len - 1usize { ret (zero, TooLarge) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    let (lo, hi, peak, grid_error) = kde_grid(values, bandwidth, grid, estimates)
    if grid_error != ok { ret (zero, grid_error) }
    var i = 0usize
    while i + 1usize < grid.len {
        segments[i] = Segment {
            from: Coord { x: bounds.x + bounds.width * f32(i) / f32(grid.len - 1usize), y: bounds.y + bounds.height * f32(1.0f64 - estimates[i] / peak) },
            to: Coord { x: bounds.x + bounds.width * f32(i + 1usize) / f32(grid.len - 1usize), y: bounds.y + bounds.height * f32(1.0f64 - estimates[i + 1usize] / peak) },
        }
        i += 1usize
    }
    ret (Layout { kind: .Density, coords: zero, segments: segments[..grid.len - 1usize], bars: zero, x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(peak) }, ok)
}

// The same estimate mirrored around the panel center. `outline` holds the
// closed shape's left side bottom-to-top and right side top-to-bottom.
fn violin(values: []const f64, bounds: geometry.Rect, bandwidth: f64, grid: []f64, estimates: []f64, outline: []Coord) -> (Layout, err) {
    if grid.len < 2usize || outline.len / 2usize < grid.len { ret (zero, TooLarge) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    let (lo, hi, peak, grid_error) = kde_grid(values, bandwidth, grid, estimates)
    if grid_error != ok { ret (zero, grid_error) }
    let center = bounds.x + bounds.width / 2.0
    let half = bounds.width * 0.35
    var i = 0usize
    while i < grid.len {
        let y = bounds.y + bounds.height * f32(1.0f64 - (grid[i] - lo) / (hi - lo))
        let side = half * f32(estimates[i] / peak)
        outline[i] = Coord { x: center - side, y: y }
        outline[2usize * grid.len - 1usize - i] = Coord { x: center + side, y: y }
        i += 1usize
    }
    ret (Layout { kind: .Violin, coords: outline[..2usize * grid.len], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: f32(lo), y_max: f32(hi) }, ok)
}

// Normal Q-Q positions use (i + 1/2) / n. The reference joins the sample's
// R7 quartiles against the theoretical normal quartiles.
fn qq_normal(sorted: []const f64, bounds: geometry.Rect, points: []Coord, reference: []Segment) -> (Layout, err) {
    if sorted.len < 2usize { ret (zero, Empty) }
    if points.len < sorted.len || reference.len < 1usize { ret (zero, TooLarge) }
    if !finite(bounds.x) || !finite(bounds.y) || !finite(bounds.width) || !finite(bounds.height) || bounds.width <= 0.0 || bounds.height <= 0.0 { ret (zero, Invalid) }
    var i = 0usize
    while i < sorted.len {
        if !finite(f32(sorted[i])) || (i > 0usize && sorted[i] < sorted[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    var ymin = f32(sorted[0usize])
    var ymax = f32(sorted[sorted.len - 1usize])
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
        if ymin == ymax {
            if ymin > 0.0 { ymin *= 0.5 } else { ymax *= 0.5 }
        }
    }
    let n = f64(sorted.len)
    let xmin = f32(special.normal_quantile(0.5f64 / n))
    let xmax = f32(special.normal_quantile((n - 0.5f64) / n))
    i = 0usize
    while i < sorted.len {
        let theoretical = f32(special.normal_quantile((f64(i) + 0.5f64) / n))
        points[i] = Coord {
            x: mapped(theoretical, xmin, xmax, bounds.x, bounds.width),
            y: bounds.y + bounds.height - mapped(f32(sorted[i]), ymin, ymax, 0.0, bounds.height),
        }
        i += 1usize
    }
    let (q1, first_ok) = stat.quantile(sorted, 0.25f64, .R7)
    let (q3, third_ok) = stat.quantile(sorted, 0.75f64, .R7)
    if !first_ok || !third_ok { ret (zero, Invalid) }
    let theory_q1 = f32(special.normal_quantile(0.25f64))
    let theory_q3 = f32(special.normal_quantile(0.75f64))
    reference[0usize] = Segment {
        from: Coord { x: mapped(theory_q1, xmin, xmax, bounds.x, bounds.width), y: bounds.y + bounds.height - mapped(f32(q1), ymin, ymax, 0.0, bounds.height) },
        to: Coord { x: mapped(theory_q3, xmin, xmax, bounds.x, bounds.width), y: bounds.y + bounds.height - mapped(f32(q3), ymin, ymax, 0.0, bounds.height) },
    }
    ret (Layout { kind: .Qq, coords: points[..sorted.len], segments: reference[..1usize], bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
}

fn cell_rect(bounds: geometry.Rect, column: usize, row: usize, columns: usize, rows: usize) -> geometry.Rect {
    let x0 = bounds.x + bounds.width * f32(column) / f32(columns)
    let x1 = bounds.x + bounds.width * f32(column + 1usize) / f32(columns)
    let y0 = bounds.y + bounds.height * f32(row) / f32(rows)
    let y1 = bounds.y + bounds.height * f32(row + 1usize) / f32(rows)
    ret geometry.rect(x0, y0, x1 - x0, y1 - y0)
}

// Row-major values become caller-owned tiles; the renderer owns palette choice.
fn heatmap(values: []const f64, columns: usize, bounds: geometry.Rect, cells: []Cell) -> (MatrixLayout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if columns == 0usize || values.len % columns != 0usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    if cells.len < values.len { ret (zero, TooLarge) }
    let rows = values.len / columns
    var lo = values[0usize]
    var hi = lo
    var i = 0usize
    while i < values.len {
        if !finite64(values[i]) || !finite(f32(values[i])) { ret (zero, Invalid) }
        if values[i] < lo { lo = values[i] }
        if values[i] > hi { hi = values[i] }
        i += 1usize
    }
    i = 0usize
    while i < values.len {
        cells[i] = Cell { rect: cell_rect(bounds, i % columns, i / columns, columns, rows), value: f32(values[i]) }
        i += 1usize
    }
    ret (MatrixLayout { kind: .Heatmap, cells: cells[..values.len], columns: columns, rows: rows, value_min: f32(lo), value_max: f32(hi) }, ok)
}

// Observations are row-major. Pearson's r comes from e.algo.stat; two scratch
// columns and the output cells belong to the caller. Constant columns refuse.
fn correlation_matrix(observations: []const f64, columns: usize, bounds: geometry.Rect, x: []f64, y: []f64, cells: []Cell) -> (MatrixLayout, err) {
    if observations.len == 0usize { ret (zero, Empty) }
    if columns == 0usize || observations.len % columns != 0usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    let rows = observations.len / columns
    if rows < 2usize { ret (zero, Invalid) }
    if cells.len / columns < columns || x.len < rows || y.len < rows { ret (zero, TooLarge) }
    var i = 0usize
    while i < observations.len {
        if !finite64(observations[i]) { ret (zero, Invalid) }
        i += 1usize
    }
    var row = 0usize
    while row < columns {
        var column = 0usize
        while column < columns {
            i = 0usize
            while i < rows {
                x[i] = observations[i * columns + column]
                y[i] = observations[i * columns + row]
                i += 1usize
            }
            let (coefficient, defined) = stat.correlation_pearson(x[..rows], y[..rows])
            if !defined || !finite(f32(coefficient)) { ret (zero, Invalid) }
            var value = f32(coefficient)
            if value < -1.0 { value = -1.0 }
            if value > 1.0 { value = 1.0 }
            cells[row * columns + column] = Cell { rect: cell_rect(bounds, column, row, columns, columns), value: value }
            column += 1usize
        }
        row += 1usize
    }
    ret (MatrixLayout { kind: .Correlation, cells: cells[..columns * columns], columns: columns, rows: columns, value_min: -1.0, value_max: 1.0 }, ok)
}

// Row-major equal panels for a later facet mapping stage. All panels use the
// same outer bounds; callers choose shared or independent data scales.
fn facet_grid(bounds: geometry.Rect, columns: usize, count: usize, gap: f32, panels: []geometry.Rect) -> ([]geometry.Rect, err) {
    if columns == 0usize || count == 0usize || !valid_bounds(bounds) || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if panels.len < count { ret (zero, TooLarge) }
    var rows = count / columns
    if count % columns != 0usize { rows += 1usize }
    let width = (bounds.width - gap * f32(columns - 1usize)) / f32(columns)
    let height = (bounds.height - gap * f32(rows - 1usize)) / f32(rows)
    if !(width > 0.0) || !(height > 0.0) { ret (zero, Invalid) }
    var i = 0usize
    while i < count {
        panels[i] = geometry.rect(bounds.x + f32(i % columns) * (width + gap), bounds.y + f32(i / columns) * (height + gap), width, height)
        i += 1usize
    }
    ret (panels[..count], ok)
}
