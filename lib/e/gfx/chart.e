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
use e.text.layout as text_layout

type Kind = enum u8 { Scatter, Line, Bar, Histogram, Step, Ecdf, Box, Density, Qq, Violin, Heatmap, Correlation, Area, Lollipop, ErrorBar, Band, Dumbbell, FrequencyPolygon, Rug, PointLine, Strip, Beeswarm, DotPlot, Waterfall, Bubble, Pp, Mosaic }
type ScaleKind = enum u8 { Linear, Log10, Symlog }
type BinaryMetric = enum u8 { Roc, PrecisionRecall, CumulativeGain, Lift }
type Scale = struct { kind: ScaleKind, reverse: bool, linthresh: f32 }
type Tick = struct { value: f32, fraction: f32 }
type Coord = struct { x: f32, y: f32 }
type LabelAlign = enum u8 { Left, Center, Right }
type Label = struct { text: str, anchor: Coord, align: LabelAlign }
type LegendItem = struct { swatch: geometry.Rect, label: Label }
type Segment = struct { from: Coord, to: Coord }
type Cell = struct { rect: geometry.Rect, value: f32 }
type SunburstArc = struct { start: f64, end: f64, next: f64 }
type SankeyNode = struct { incoming: f64, outgoing: f64, in_used: f64, out_used: f64 }
type TargetStatus = struct { delta: f32, achieved: bool }
type CloudWord = struct { label: Label, size: f32, box: geometry.Rect }
type StateSpan = struct { row: usize, start: f64, end: f64, state: usize }
type CalendarDay = struct { offset: usize, value: f64 }
type TimelineEvent = struct { time: f64, row: usize }
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

// A sparkline is an evenly spaced Line with no guide contract.
fn sparkline(values: []const f32, bounds: geometry.Rect, x: []f32, segments: []Segment) -> (Layout, err) {
    if values.len < 2usize { ret (zero, Empty) }
    if x.len < values.len || segments.len < values.len - 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < values.len {
        x[i] = f32(i)
        i += 1usize
    }
    let plot = spec(.Line, bounds, x[..values.len], values)
    var unused_coords: [1]Coord = zero
    var unused_bars: [1]geometry.Rect = zero
    let (marks, marks_error) = layout(&plot, unused_coords[..0usize], segments, unused_bars[..0usize])
    ret (marks, marks_error)
}

// Four diagnostic curves from one tie-grouped classifier threshold sweep.
fn binary_metric_curve(c: *const stat.BinaryCurve, metric: BinaryMetric, bounds: geometry.Rect, x: []f32, y: []f32, segments: []Segment) -> (Layout, err) {
    let (_, valid) = stat.roc_auc(c)
    if !valid || !valid_bounds(bounds) { ret (zero, Invalid) }
    if x.len < c.points.len || y.len < c.points.len || segments.len + 1usize < c.points.len { ret (zero, TooLarge) }
    let total = c.positives + c.negatives
    let prevalence = f64(c.positives) / f64(total)
    var ymax = 1.0f32
    var i = 0usize
    while i < c.points.len {
        let p = c.points[i]
        let selected = p.tp + p.fp
        if metric == .Roc {
            x[i] = f32(f64(p.fp) / f64(c.negatives))
            y[i] = f32(f64(p.tp) / f64(c.positives))
        } else if metric == .PrecisionRecall {
            x[i] = f32(f64(p.tp) / f64(c.positives))
            y[i] = 1.0
            if selected > 0usize { y[i] = f32(f64(p.tp) / f64(selected)) }
        } else if metric == .CumulativeGain {
            x[i] = f32(f64(selected) / f64(total))
            y[i] = f32(f64(p.tp) / f64(c.positives))
        } else {
            x[i] = f32(f64(selected) / f64(total))
            y[i] = 1.0
            if selected > 0usize { y[i] = f32((f64(p.tp) / f64(selected)) / prevalence) }
        }
        if !finite(x[i]) || !finite(y[i]) { ret (zero, Invalid) }
        if y[i] > ymax { ymax = y[i] }
        i += 1usize
    }
    let x_limits = [2]f32{ 0.0, 1.0 }
    let y_limits = [2]f32{ 0.0, ymax }
    let plot = spec(.Line, bounds, x[..c.points.len], y[..c.points.len])
    var unused_coords: [1]Coord = zero
    var unused_bars: [1]geometry.Rect = zero
    let (marks, layout_error) = layout_with_limits(&plot, unused_coords[..0usize], segments, unused_bars[..0usize], x_limits[..], y_limits[..])
    ret (marks, layout_error)
}

// Fill the raw partial-AUC region on the full [0, 1] ROC axes.
fn roc_partial_region(c: *const stat.BinaryCurve, max_fpr: f32, bounds: geometry.Rect, points: []Coord) -> (Layout, err) {
    let (_, valid) = stat.roc_partial_auc(c, f64(max_fpr))
    if !valid || !valid_bounds(bounds) { ret (zero, Invalid) }
    if points.len < c.points.len + 2usize { ret (zero, TooLarge) }
    let bottom = bounds.y + bounds.height
    points[0usize] = Coord { x: bounds.x, y: bottom }
    var used = 1usize
    var i = 0usize
    while i < c.points.len {
        let p = c.points[i]
        let x = f32(f64(p.fp) / f64(c.negatives))
        let y = f32(f64(p.tp) / f64(c.positives))
        if x <= max_fpr {
            points[used] = Coord { x: bounds.x + bounds.width * x, y: bottom - bounds.height * y }
            used += 1usize
        } else {
            let before = c.points[i - 1usize]
            let x0 = f64(before.fp) / f64(c.negatives)
            let y0 = f64(before.tp) / f64(c.positives)
            let x1 = f64(p.fp) / f64(c.negatives)
            let y1 = f64(p.tp) / f64(c.positives)
            let y_stop = y0 + (y1 - y0) * (f64(max_fpr) - x0) / (x1 - x0)
            points[used] = Coord { x: bounds.x + bounds.width * max_fpr, y: bottom - bounds.height * f32(y_stop) }
            used += 1usize
            break
        }
        i += 1usize
    }
    points[used] = Coord { x: bounds.x + bounds.width * max_fpr, y: bottom }
    used += 1usize
    ret (Layout { kind: .Area, coords: points[..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }, ok)
}

// One bar per caller-supplied cell, all measured against the same maximum.
fn in_cell_bars(values: []const f32, maximum: f32, cells: []const geometry.Rect, inset: f32, bars: []geometry.Rect) -> (Layout, err) {
    if values.len == 0usize { ret (zero, Empty) }
    if cells.len != values.len || !finite(maximum) || maximum <= 0.0 || !finite(inset) || inset < 0.0 { ret (zero, Invalid) }
    if bars.len < values.len { ret (zero, TooLarge) }
    var i = 0usize
    while i < values.len {
        let cell = cells[i]
        if !valid_bounds(cell) || cell.width <= inset * 2.0 || cell.height <= inset * 2.0 || !finite(values[i]) || values[i] < 0.0 || values[i] > maximum { ret (zero, Invalid) }
        bars[i] = geometry.rect(cell.x + inset, cell.y + inset, (cell.width - 2.0 * inset) * (values[i] / maximum), cell.height - 2.0 * inset)
        i += 1usize
    }
    ret (Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[..values.len], x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: f32(values.len) }, ok)
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
    if s.kind == .Histogram || s.kind == .Ecdf || s.kind == .Box || s.kind == .Density || s.kind == .Qq || s.kind == .Violin || s.kind == .Heatmap || s.kind == .Correlation || s.kind == .ErrorBar || s.kind == .Band || s.kind == .Dumbbell || s.kind == .FrequencyPolygon || s.kind == .Rug || s.kind == .Strip || s.kind == .Beeswarm || s.kind == .DotPlot || s.kind == .Bubble { ret (zero, Invalid) }
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

// Size encodes circle area, not diameter. Zero-sized observations stay in the
// borrowed data but emit no visible mark; x/y use the ordinary scatter scales.
fn bubble(s: *const Spec, sizes: []const f32, max_radius: f32, coords: []Coord, circles: []geometry.Rect) -> (Layout, err) {
    if s.kind != .Bubble || sizes.len != s.x.len || sizes.len != s.y.len { ret (zero, Invalid) }
    if sizes.len == 0usize { ret (zero, Empty) }
    if !finite(max_radius) || max_radius <= 0.0 || !finite(max_radius * 2.0) { ret (zero, Invalid) }
    if circles.len < sizes.len { ret (zero, TooLarge) }
    var maximum = 0.0f32
    var i = 0usize
    while i < sizes.len {
        if !finite(sizes[i]) || sizes[i] < 0.0 { ret (zero, Invalid) }
        if sizes[i] > maximum { maximum = sizes[i] }
        i += 1usize
    }
    if maximum == 0.0 { ret (zero, Invalid) }
    var dots = *s
    dots.kind = .Scatter
    let (positions, positions_error) = layout(&dots, coords, zero, circles[..0usize])
    if positions_error != ok { ret (zero, positions_error) }
    i = 0usize
    while i < sizes.len {
        let radius = max_radius * f32(math.sqrt[f64](f64(sizes[i]) / f64(maximum)))
        let center = positions.coords[i]
        if !finite(center.x) || !finite(center.y) || !finite(center.x - radius) || !finite(center.y - radius) { ret (zero, Invalid) }
        circles[i] = geometry.rect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0)
        i += 1usize
    }
    ret (Layout { kind: .Bubble, coords: positions.coords, segments: zero, bars: circles[..sizes.len], x_min: positions.x_min, x_max: positions.x_max, y_min: positions.y_min, y_max: positions.y_max }, ok)
}

type PairedStats = struct { summary: stat.Regression, x_min: f32, x_max: f32, y_min: f32, y_max: f32 }

fn paired_stats(x: []const f32, y: []const f32) -> (PairedStats, err) {
    if x.len == 0usize { ret (zero, Empty) }
    if x.len != y.len { ret (zero, Invalid) }
    var result = PairedStats { summary: stat.regression(), x_min: x[0usize], x_max: x[0usize], y_min: y[0usize], y_max: y[0usize] }
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || !finite(y[i]) { ret (zero, Invalid) }
        stat.regression_add(&result.summary, f64(x[i]), f64(y[i]))
        if x[i] < result.x_min { result.x_min = x[i] }
        if x[i] > result.x_max { result.x_max = x[i] }
        if y[i] < result.y_min { result.y_min = y[i] }
        if y[i] > result.y_max { result.y_max = y[i] }
        i += 1usize
    }
    ret (result, ok)
}

// Ordinary least squares in data space. The returned domain includes fitted
// endpoints so a caller can map scatter marks with the same explicit limits.
fn regression_line(x: []const f32, y: []const f32, bounds: geometry.Rect, segments: []Segment) -> (Layout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    if segments.len == 0usize { ret (zero, TooLarge) }
    let (data, data_error) = paired_stats(x, y)
    if data_error != ok { ret (zero, data_error) }
    let (slope, has_slope) = stat.regression_slope(&data.summary)
    let (intercept, has_intercept) = stat.regression_intercept(&data.summary)
    if !has_slope || !has_intercept || !finite64(slope) || !finite64(intercept) { ret (zero, Invalid) }
    let first_y = f32(slope * f64(data.x_min) + intercept)
    let last_y = f32(slope * f64(data.x_max) + intercept)
    if !finite(first_y) || !finite(last_y) { ret (zero, Invalid) }
    var low = data.y_min
    var high = data.y_max
    if first_y < low { low = first_y }
    if last_y < low { low = last_y }
    if first_y > high { high = first_y }
    if last_y > high { high = last_y }
    if low == high {
        low -= 0.5
        high += 0.5
    }
    let line_x = [2]f32{ data.x_min, data.x_max }
    let line_y = [2]f32{ first_y, last_y }
    let y_limits = [2]f32{ low, high }
    var line_spec = spec(.Line, bounds, line_x[..], line_y[..])
    let (marks, marks_error) = layout_with_limits(&line_spec, zero, segments, zero, line_x[..], y_limits[..])
    ret (marks, marks_error)
}

// OLS mean-confidence or new-observation prediction ribbon. `critical` is
// the caller's two-sided Student-t quantile with count-2 degrees of freedom.
// Both layers share a domain that includes the observations and ribbon.
fn regression_interval(x: []const f32, y: []const f32, bounds: geometry.Rect, critical: f32, prediction: bool, outline: []Coord, fit: []Segment) -> (Layout, Layout, err) {
    if !valid_bounds(bounds) || !finite(critical) || critical <= 0.0 { ret (zero, zero, Invalid) }
    if outline.len < 4usize || outline.len % 2usize != 0usize || fit.len == 0usize { ret (zero, zero, TooLarge) }
    let (data, data_error) = paired_stats(x, y)
    if data_error != ok { ret (zero, zero, data_error) }
    let s = data.summary
    if s.count < 3u64 || s.m2_x <= 0.0f64 || data.x_min == data.x_max { ret (zero, zero, Invalid) }
    let slope = s.cov / s.m2_x
    let intercept = s.mean_y - slope * s.mean_x
    let residual = s.m2_y - slope * s.cov
    if !finite64(slope) || !finite64(intercept) || !finite64(residual) || residual < -0.0000000001f64 * (1.0f64 + s.m2_y) { ret (zero, zero, Invalid) }
    var nonnegative = residual
    if nonnegative < 0.0f64 { nonnegative = 0.0f64 }
    let sigma = math.sqrt[f64](nonnegative / f64(s.count - 2u64))
    let base = 1.0f64 / f64(s.count)
    var ymin = data.y_min
    var ymax = data.y_max
    let samples = outline.len / 2usize
    var i = 0usize
    while i < samples {
        let value_x = f64(data.x_min) + (f64(data.x_max) - f64(data.x_min)) * f64(i) / f64(samples - 1usize)
        let offset = value_x - s.mean_x
        var leverage = base + offset * offset / s.m2_x
        if prediction { leverage += 1.0f64 }
        let estimate = slope * value_x + intercept
        let half_width = f64(critical) * sigma * math.sqrt[f64](leverage)
        let lower = f32(estimate - half_width)
        let upper = f32(estimate + half_width)
        let position = f32(value_x)
        if !finite(lower) || !finite(upper) || !finite(position) { ret (zero, zero, Invalid) }
        outline[i] = Coord { x: position, y: upper }
        outline[2usize * samples - 1usize - i] = Coord { x: position, y: lower }
        if lower < ymin { ymin = lower }
        if upper > ymax { ymax = upper }
        i += 1usize
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    if !finite(ymin) || !finite(ymax) { ret (zero, zero, Invalid) }
    i = 0usize
    while i < outline.len {
        outline[i] = Coord { x: mapped(outline[i].x, data.x_min, data.x_max, bounds.x, bounds.width), y: bounds.y + bounds.height - mapped(outline[i].y, ymin, ymax, 0.0, bounds.height) }
        i += 1usize
    }
    let first = f32(slope * f64(data.x_min) + intercept)
    let last = f32(slope * f64(data.x_max) + intercept)
    if !finite(first) || !finite(last) { ret (zero, zero, Invalid) }
    fit[0usize] = Segment { from: Coord { x: bounds.x, y: bounds.y + bounds.height - mapped(first, ymin, ymax, 0.0, bounds.height) }, to: Coord { x: bounds.x + bounds.width, y: bounds.y + bounds.height - mapped(last, ymin, ymax, 0.0, bounds.height) } }
    let ribbon = Layout { kind: .Band, coords: outline, segments: zero, bars: zero, x_min: data.x_min, x_max: data.x_max, y_min: ymin, y_max: ymax }
    let line = Layout { kind: .Line, coords: zero, segments: fit[..1usize], bars: zero, x_min: data.x_min, x_max: data.x_max, y_min: ymin, y_max: ymax }
    ret (ribbon, line, ok)
}

// Covariance contour at a caller-selected Mahalanobis radius. A 95% contour
// for bivariate normal data uses radius sqrt(chi-square(2, .95)) ~= 2.4477.
fn covariance_ellipse(x: []const f32, y: []const f32, bounds: geometry.Rect, radius: f32, segments: []Segment) -> (Layout, err) {
    if !valid_bounds(bounds) || !finite(radius) || radius <= 0.0 { ret (zero, Invalid) }
    if segments.len < 8usize { ret (zero, TooLarge) }
    let (data, data_error) = paired_stats(x, y)
    if data_error != ok { ret (zero, data_error) }
    if data.summary.count < 3u64 { ret (zero, Invalid) }
    let denominator = f64(data.summary.count - 1u64)
    let variance_x = data.summary.m2_x / denominator
    let variance_y = data.summary.m2_y / denominator
    let covariance = data.summary.cov / denominator
    if !finite64(variance_x) || !finite64(variance_y) || !finite64(covariance) || variance_x <= 0.0f64 || variance_y <= 0.0f64 { ret (zero, Invalid) }
    let spread_x = math.sqrt[f64](variance_x)
    let tilt = covariance / spread_x
    let remainder = variance_y - tilt * tilt
    if !finite64(remainder) || remainder <= 0.0f64 { ret (zero, Invalid) }
    let spread_y = math.sqrt[f64](remainder)
    let reach_x = f64(radius) * spread_x
    let reach_y = f64(radius) * math.sqrt[f64](variance_y)
    var xmin = data.x_min
    var xmax = data.x_max
    var ymin = data.y_min
    var ymax = data.y_max
    let left = f32(data.summary.mean_x - reach_x)
    let right = f32(data.summary.mean_x + reach_x)
    let bottom = f32(data.summary.mean_y - reach_y)
    let top = f32(data.summary.mean_y + reach_y)
    if !finite(left) || !finite(right) || !finite(bottom) || !finite(top) { ret (zero, Invalid) }
    if left < xmin { xmin = left }
    if right > xmax { xmax = right }
    if bottom < ymin { ymin = bottom }
    if top > ymax { ymax = top }
    let dx = f64(xmax) - f64(xmin)
    let dy = f64(ymax) - f64(ymin)
    if dx <= 0.0f64 || dy <= 0.0f64 { ret (zero, Invalid) }
    let first_data_x = data.summary.mean_x + f64(radius) * spread_x
    let first_data_y = data.summary.mean_y + f64(radius) * tilt
    let first = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * (first_data_x - f64(xmin)) / dx), y: f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (first_data_y - f64(ymin)) / dy)) }
    if !finite(first.x) || !finite(first.y) { ret (zero, Invalid) }
    var previous = first
    var i = 0usize
    while i < segments.len {
        var next = first
        if i + 1usize < segments.len {
            let angle = 6.283185307179586f64 * f64(i + 1usize) / f64(segments.len)
            let cosine = math.cos[f64](angle)
            let sine = math.sin[f64](angle)
            let value_x = data.summary.mean_x + f64(radius) * spread_x * cosine
            let value_y = data.summary.mean_y + f64(radius) * (tilt * cosine + spread_y * sine)
            next = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * (value_x - f64(xmin)) / dx), y: f32(f64(bounds.y) + f64(bounds.height) * (1.0f64 - (value_y - f64(ymin)) / dy)) }
            if !finite(next.x) || !finite(next.y) { ret (zero, Invalid) }
        }
        segments[i] = Segment { from: previous, to: next }
        previous = next
        i += 1usize
    }
    ret (Layout { kind: .Line, coords: zero, segments: segments, bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
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

// Centered stacked areas share one y scale and one caller-owned polygon per series.
// Values are sample-major: every x position carries all series in input order.
// ponytail: silhouette centering is stable; add wiggle offsets if trend-heavy data needs them.
fn streamgraph(x: []const f32, values: []const f32, series: usize, bounds: geometry.Rect, totals: []f64, cumulative: []f64, outline: []Coord, layers: []Layout) -> ([]Layout, err) {
    if x.len < 2usize || series == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || values.len / x.len != series || values.len % x.len != 0usize { ret (zero, Invalid) }
    if totals.len < x.len || cumulative.len < x.len || outline.len / x.len / 2usize < series || layers.len < series { ret (zero, TooLarge) }
    var max_total = 0.0f64
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || (i > 0usize && x[i] <= x[i - 1usize]) { ret (zero, Invalid) }
        var total = 0.0f64
        var j = 0usize
        while j < series {
            let value = values[i * series + j]
            if !finite(value) || value < 0.0 { ret (zero, Invalid) }
            total += f64(value)
            j += 1usize
        }
        if !finite(f32(total)) { ret (zero, Invalid) }
        totals[i] = total
        if total > max_total { max_total = total }
        i += 1usize
    }
    if max_total <= 0.0f64 { ret (zero, Empty) }
    i = 0usize
    while i < x.len {
        cumulative[i] = (max_total - totals[i]) * 0.5f64
        i += 1usize
    }
    var layer = 0usize
    while layer < series {
        let first = layer * 2usize * x.len
        i = 0usize
        while i < x.len {
            let lower = cumulative[i]
            let upper = lower + f64(values[i * series + layer])
            let px = bounds.x + bounds.width * f32((f64(x[i]) - f64(x[0usize])) / (f64(x[x.len - 1usize]) - f64(x[0usize])))
            let top = bounds.y + bounds.height * (1.0 - f32(upper / max_total))
            let bottom = bounds.y + bounds.height * (1.0 - f32(lower / max_total))
            if !finite(px) || !finite(top) || !finite(bottom) { ret (zero, Invalid) }
            outline[first + i] = Coord { x: px, y: top }
            outline[first + 2usize * x.len - 1usize - i] = Coord { x: px, y: bottom }
            cumulative[i] = upper
            i += 1usize
        }
        layers[layer] = Layout { kind: .Area, coords: outline[first..first + 2usize * x.len], segments: zero, bars: zero, x_min: x[0usize], x_max: x[x.len - 1usize], y_min: 0.0, y_max: f32(max_total) }
        layer += 1usize
    }
    ret (layers[..series], ok)
}

// Equal-height rank bands over increasing x positions. Values are sample-major;
// higher values rank first, and ties keep the original series order.
// ponytail: O(samples * series^2) comparisons; sort per sample if large series counts matter.
fn ribbon_rank(x: []const f32, values: []const f32, series: usize, bounds: geometry.Rect, gap: f32, outline: []Coord, layers: []Layout) -> ([]Layout, err) {
    if x.len < 2usize || series == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(gap) || gap < 0.0 || values.len / x.len != series || values.len % x.len != 0usize { ret (zero, Invalid) }
    if outline.len / x.len / 2usize < series || layers.len < series { ret (zero, TooLarge) }
    let total_gap = gap * f32(series - 1usize)
    if !finite(total_gap) || total_gap >= bounds.height { ret (zero, Invalid) }
    let band_height = (bounds.height - total_gap) / f32(series)
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || (i > 0usize && x[i] <= x[i - 1usize]) { ret (zero, Invalid) }
        var j = 0usize
        while j < series {
            if !finite(values[i * series + j]) { ret (zero, Invalid) }
            j += 1usize
        }
        i += 1usize
    }
    var layer = 0usize
    while layer < series {
        let first = layer * 2usize * x.len
        i = 0usize
        while i < x.len {
            let value = values[i * series + layer]
            var rank = 0usize
            var other = 0usize
            while other < series {
                let candidate = values[i * series + other]
                if candidate > value || (candidate == value && other < layer) { rank += 1usize }
                other += 1usize
            }
            let px = bounds.x + bounds.width * f32((f64(x[i]) - f64(x[0usize])) / (f64(x[x.len - 1usize]) - f64(x[0usize])))
            let top = bounds.y + f32(rank) * (band_height + gap)
            let bottom = top + band_height
            if !finite(px) || !finite(top) || !finite(bottom) { ret (zero, Invalid) }
            outline[first + i] = Coord { x: px, y: top }
            outline[first + 2usize * x.len - 1usize - i] = Coord { x: px, y: bottom }
            i += 1usize
        }
        layers[layer] = Layout { kind: .Area, coords: outline[first..first + 2usize * x.len], segments: zero, bars: zero, x_min: x[0usize], x_max: x[x.len - 1usize], y_min: 0.0, y_max: f32(series) }
        layer += 1usize
    }
    ret (layers[..series], ok)
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

// Horizontal study intervals, center estimates and one reference rule.
fn forest_plot(estimate: []const f32, lower: []const f32, upper: []const f32, reference: f32, scale: Scale, bounds: geometry.Rect, points: []Coord, intervals: []Segment, reference_rule: []Segment) -> (Layout, Layout, err) {
    if estimate.len == 0usize { ret (zero, zero, Empty) }
    if lower.len != estimate.len || upper.len != estimate.len || !valid_bounds(bounds) || !finite(reference) { ret (zero, zero, Invalid) }
    if points.len < estimate.len || intervals.len < estimate.len || reference_rule.len == 0usize { ret (zero, zero, TooLarge) }
    var xmin = reference
    var xmax = reference
    var i = 0usize
    while i < estimate.len {
        if !finite(estimate[i]) || !finite(lower[i]) || !finite(upper[i]) || lower[i] > estimate[i] || estimate[i] > upper[i] { ret (zero, zero, Invalid) }
        if lower[i] < xmin { xmin = lower[i] }
        if upper[i] > xmax { xmax = upper[i] }
        i += 1usize
    }
    if xmin == xmax {
        if scale.kind == .Log10 {
            if xmin <= 0.0 { ret (zero, zero, Invalid) }
            xmin *= 0.5
            xmax *= 2.0
        } else {
            xmin -= 0.5
            xmax += 0.5
        }
    }
    if !valid_scale(scale, xmin, xmax) { ret (zero, zero, Invalid) }
    i = 0usize
    while i < estimate.len {
        let y = bounds.y + bounds.height * (f32(i) + 0.5) / f32(estimate.len)
        let left = bounds.x + bounds.width * fraction(lower[i], xmin, xmax, scale)
        let middle = bounds.x + bounds.width * fraction(estimate[i], xmin, xmax, scale)
        let right = bounds.x + bounds.width * fraction(upper[i], xmin, xmax, scale)
        if !finite(y) || !finite(left) || !finite(middle) || !finite(right) { ret (zero, zero, Invalid) }
        points[i] = Coord { x: middle, y: y }
        intervals[i] = Segment { from: Coord { x: left, y: y }, to: Coord { x: right, y: y } }
        i += 1usize
    }
    let reference_x = bounds.x + bounds.width * fraction(reference, xmin, xmax, scale)
    reference_rule[0usize] = Segment { from: Coord { x: reference_x, y: bounds.y }, to: Coord { x: reference_x, y: bounds.y + bounds.height } }
    let studies = Layout { kind: .Dumbbell, coords: points[..estimate.len], segments: intervals[..estimate.len], bars: zero, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: f32(estimate.len) }
    let rule = Layout { kind: .Rug, coords: zero, segments: reference_rule[..1usize], bars: zero, x_min: xmin, x_max: xmax, y_min: 0.0, y_max: f32(estimate.len) }
    ret (studies, rule, ok)
}

// Means and differences are chart scratch; agreement limits come from e.algo.stat.
fn bland_altman(left: []const f64, right: []const f64, critical: f64, bounds: geometry.Rect, means: []f32, differences: []f32, points: []Coord, rules: []Segment) -> (Layout, Layout, err) {
    if left.len < 2usize { ret (zero, zero, Empty) }
    if right.len != left.len || !valid_bounds(bounds) { ret (zero, zero, Invalid) }
    if means.len < left.len || differences.len < left.len || points.len < left.len || rules.len < 3usize { ret (zero, zero, TooLarge) }
    let (agreement, defined) = stat.agreement_limits(left, right, critical)
    if !defined || !finite(f32(agreement.lower)) || !finite(f32(agreement.bias)) || !finite(f32(agreement.upper)) { ret (zero, zero, Invalid) }
    var ymin = f32(agreement.lower)
    var ymax = f32(agreement.upper)
    var i = 0usize
    while i < left.len {
        means[i] = f32(left[i] * 0.5f64 + right[i] * 0.5f64)
        differences[i] = f32(left[i] - right[i])
        if !finite(means[i]) || !finite(differences[i]) { ret (zero, zero, Invalid) }
        if differences[i] < ymin { ymin = differences[i] }
        if differences[i] > ymax { ymax = differences[i] }
        i += 1usize
    }
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    let y_limits = [2]f32{ ymin, ymax }
    let plot = spec(.Scatter, bounds, means[..left.len], differences[..left.len])
    var unused_segments: [1]Segment = zero
    var unused_bars: [1]geometry.Rect = zero
    let (dots, dots_error) = layout_with_limits(&plot, points, unused_segments[..0usize], unused_bars[..0usize], means[..0usize], y_limits[..])
    if dots_error != ok { ret (zero, zero, dots_error) }
    let levels = [3]f32{ f32(agreement.lower), f32(agreement.bias), f32(agreement.upper) }
    i = 0usize
    while i < 3usize {
        let y = y_position(&plot, levels[i], ymin, ymax)
        rules[i] = Segment { from: Coord { x: bounds.x, y: y }, to: Coord { x: bounds.x + bounds.width, y: y } }
        i += 1usize
    }
    let guides = Layout { kind: .Rug, coords: zero, segments: rules[..3usize], bars: zero, x_min: dots.x_min, x_max: dots.x_max, y_min: ymin, y_max: ymax }
    ret (dots, guides, ok)
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

// Signed delta is actual minus target; callers choose whether higher is better.
fn target_status(actual: f32, target_value: f32, higher_is_better: bool) -> (TargetStatus, err) {
    if !finite(actual) || !finite(target_value) { ret (zero, Invalid) }
    let delta = actual - target_value
    if !finite(delta) { ret (zero, Invalid) }
    var achieved = actual >= target_value
    if !higher_is_better { achieved = actual <= target_value }
    ret (TargetStatus { delta: delta, achieved: achieved }, ok)
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

// Category-centred columns and a line share x while retaining independent
// vertical domains. The caller owns category positions and both mark layers.
fn combo_bar_line(columns: []const f32, line: []const f32, bounds: geometry.Rect, category_x: []f32, bars: []geometry.Rect, points: []Coord, segments: []Segment, layers: []Layout) -> ([]Layout, err) {
    if columns.len == 0usize { ret (zero, Empty) }
    if columns.len != line.len || !valid_bounds(bounds) { ret (zero, Invalid) }
    if category_x.len < columns.len || bars.len < columns.len || points.len < line.len || (line.len > 1usize && segments.len < line.len - 1usize) || layers.len < 2usize { ret (zero, TooLarge) }
    // ponytail: f32 centres need distinct integers; wider categories need a non-f32 axis.
    if columns.len >= 16777216usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < columns.len {
        category_x[i] = f32(i) + 0.5
        i += 1usize
    }
    let limits = [2]f32{ 0.0, f32(columns.len) }
    var column_spec = spec(.Bar, bounds, category_x[..columns.len], columns)
    let (column_layer, column_error) = layout_with_limits(&column_spec, zero, zero, bars, limits[..], zero)
    if column_error != ok { ret (zero, column_error) }
    var line_spec = spec(.PointLine, bounds, category_x[..line.len], line)
    let (line_layer, line_error) = layout_with_limits(&line_spec, points, segments, zero, limits[..], zero)
    if line_error != ok { ret (zero, line_error) }
    layers[0usize] = column_layer
    layers[1usize] = line_layer
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

// Half-ring gauge: background, measured value and target rule, in paint order.
// The ring fits a semicircle inside bounds; the caller owns all three marks.
fn gauge(value: f32, target_value: f32, maximum: f32, bounds: geometry.Rect, hole: f32, points: []Coord, target_line: []Segment, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) || !finite(value) || !finite(target_value) || !finite(maximum) || maximum <= 0.0 || value < 0.0 || value > maximum || target_value < 0.0 || target_value > maximum || !finite(hole) || hole < 0.0 || hole >= 1.0 { ret (zero, Invalid) }
    if points.len < 196usize || target_line.len == 0usize || layers.len < 3usize { ret (zero, TooLarge) }
    var radius = f64(bounds.width) * 0.5f64
    if f64(bounds.height) < radius { radius = f64(bounds.height) }
    if radius <= 0.0f64 { ret (zero, Invalid) }
    let inner = radius * f64(hole)
    let cx = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let cy = f64(bounds.y) + f64(bounds.height)
    let pi = 3.141592653589793f64
    let fractions = [2]f64{ 1.0f64, f64(value) / f64(maximum) }
    var layer = 0usize
    while layer < 2usize {
        let first = layer * 98usize
        var j = 0usize
        while j <= 48usize {
            let angle = pi + pi * fractions[layer] * f64(j) / 48.0f64
            points[first + j] = Coord { x: f32(cx + radius * math.cos[f64](angle)), y: f32(cy + radius * math.sin[f64](angle)) }
            let reverse = pi + pi * fractions[layer] * f64(48usize - j) / 48.0f64
            points[first + 49usize + j] = Coord { x: f32(cx + inner * math.cos[f64](reverse)), y: f32(cy + inner * math.sin[f64](reverse)) }
            if !finite(points[first + j].x) || !finite(points[first + j].y) || !finite(points[first + 49usize + j].x) || !finite(points[first + 49usize + j].y) { ret (zero, Invalid) }
            j += 1usize
        }
        layers[layer] = Layout { kind: .Area, coords: points[first..first + 98usize], segments: zero, bars: zero, x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: 1.0 }
        layer += 1usize
    }
    let angle = pi + pi * f64(target_value) / f64(maximum)
    let start = Coord { x: f32(cx + inner * 0.85f64 * math.cos[f64](angle)), y: f32(cy + inner * 0.85f64 * math.sin[f64](angle)) }
    let end = Coord { x: f32(cx + radius * math.cos[f64](angle)), y: f32(cy + radius * math.sin[f64](angle)) }
    if !finite(start.x) || !finite(start.y) || !finite(end.x) || !finite(end.y) { ret (zero, Invalid) }
    target_line[0usize] = Segment { from: start, to: end }
    layers[2usize] = Layout { kind: .Rug, coords: zero, segments: target_line[..1usize], bars: zero, x_min: 0.0, x_max: maximum, y_min: 0.0, y_max: 1.0 }
    ret (layers[..3usize], ok)
}

// Text metrics are font-size-normalized widths and heights measured by the
// caller. Larger weights get larger type; exact excluded tokens are omitted.
// ponytail: deterministic spiral placement scans prior boxes; use a spatial index
// and a better packing search when clouds of hundreds of tokens are needed.
fn word_cloud(words: []const str, weights: []const f32, unit_widths: []const f32, unit_heights: []const f32, baseline_unit: f32, excluded: []const str, bounds: geometry.Rect, min_size: f32, max_size: f32, gap: f32, order: []usize, marks: []CloudWord) -> ([]CloudWord, err) {
    if words.len == 0usize { ret (zero, Empty) }
    if weights.len != words.len || unit_widths.len != words.len || unit_heights.len != words.len || !valid_bounds(bounds) || !finite(baseline_unit) || baseline_unit <= 0.0 || !finite(min_size) || !finite(max_size) || min_size <= 0.0 || max_size < min_size || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if order.len < words.len || marks.len < words.len { ret (zero, TooLarge) }
    var active = 0usize
    var maximum = 0.0f32
    var i = 0usize
    while i < words.len {
        if words[i].len == 0usize || !text_layout.valid_utf8(words[i]) || !finite(weights[i]) || weights[i] < 0.0 || !finite(unit_widths[i]) || unit_widths[i] <= 0.0 || !finite(unit_heights[i]) || unit_heights[i] <= 0.0 { ret (zero, Invalid) }
        var prior = 0usize
        while prior < i {
            if str.eq(words[prior], words[i]) { ret (zero, Invalid) }
            prior += 1usize
        }
        var skip = weights[i] == 0.0
        var j = 0usize
        while j < excluded.len {
            if str.eq(words[i], excluded[j]) { skip = true }
            j += 1usize
        }
        if !skip {
            order[active] = i
            active += 1usize
            if weights[i] > maximum { maximum = weights[i] }
        }
        i += 1usize
    }
    if active == 0usize { ret (zero, Empty) }
    i = 1usize
    while i < active {
        let selected = order[i]
        var j = i
        while j > 0usize && weights[order[j - 1usize]] < weights[selected] {
            order[j] = order[j - 1usize]
            j -= 1usize
        }
        order[j] = selected
        i += 1usize
    }
    let center_x = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let center_y = f64(bounds.y) + f64(bounds.height) * 0.5f64
    var used = 0usize
    while used < active {
        let index = order[used]
        var size = max_size * f32(math.sqrt[f64](f64(weights[index]) / f64(maximum)))
        if size < min_size { size = min_size }
        let width = unit_widths[index] * size
        let height = unit_heights[index] * size
        if !finite(size) || !finite(width) || !finite(height) || width <= 0.0 || height <= 0.0 || width > bounds.width || height > bounds.height { ret (zero, TooLarge) }
        var placed = false
        var attempt = 0usize
        while attempt < 4096usize && !placed {
            let angle = f64(attempt) * 2.399963229728653f64
            let radius = 3.0f64 * math.sqrt[f64](f64(attempt))
            let x = f32(center_x + radius * math.cos[f64](angle) - f64(width) * 0.5f64)
            let y = f32(center_y + radius * math.sin[f64](angle) - f64(height) * 0.5f64)
            if finite(x) && finite(y) && x >= bounds.x && y >= bounds.y && x + width <= bounds.x + bounds.width && y + height <= bounds.y + bounds.height {
                var free = true
                var prior = 0usize
                while prior < used {
                    let box = marks[prior].box
                    if x < box.x + box.width + gap && x + width + gap > box.x && y < box.y + box.height + gap && y + height + gap > box.y { free = false }
                    prior += 1usize
                }
                if free {
                    let box = geometry.rect(x, y, width, height)
                    let anchor = Coord { x: x, y: y + baseline_unit * size }
                    if !finite(anchor.y) { ret (zero, Invalid) }
                    marks[used] = CloudWord { label: Label { text: words[index], anchor: anchor, align: .Left }, size: size, box: box }
                    placed = true
                }
            }
            attempt += 1usize
        }
        if !placed { ret (zero, TooLarge) }
        used += 1usize
    }
    ret (marks[..active], ok)
}

// Ordered half-open spans map to categorical rows. Uncovered time remains blank.
// ponytail: coalescing uses exact shared endpoints; normalize jittery clocks upstream.
fn state_timeline(spans: []const StateSpan, rows: usize, states: usize, domain_start: f64, domain_end: f64, bounds: geometry.Rect, row_gap: f32, rects: []geometry.Rect, state_ids: []usize, layers: []Layout) -> ([]Layout, err) {
    if spans.len == 0usize || rows == 0usize || states == 0usize { ret (zero, Empty) }
    if !finite64(domain_start) || !finite64(domain_end) || domain_end <= domain_start || !valid_bounds(bounds) || !finite(row_gap) || row_gap < 0.0 { ret (zero, Invalid) }
    if rects.len < spans.len || state_ids.len < spans.len || layers.len < spans.len { ret (zero, TooLarge) }
    let total_gap = row_gap * f32(rows - 1usize)
    if !finite(total_gap) || total_gap >= bounds.height { ret (zero, Invalid) }
    let lane_height = (bounds.height - total_gap) / f32(rows)
    if !finite(lane_height) || lane_height <= 0.0 { ret (zero, Invalid) }
    var used = 0usize
    var i = 0usize
    while i < spans.len {
        let span = spans[i]
        if span.row >= rows || span.state >= states || !finite64(span.start) || !finite64(span.end) || span.start < domain_start || span.end > domain_end || span.end <= span.start { ret (zero, Invalid) }
        if i > 0usize {
            let before = spans[i - 1usize]
            if span.row < before.row || (span.row == before.row && span.start < before.end) { ret (zero, Invalid) }
        }
        let left = bounds.x + bounds.width * f32((span.start - domain_start) / (domain_end - domain_start))
        let right = bounds.x + bounds.width * f32((span.end - domain_start) / (domain_end - domain_start))
        let top = bounds.y + f32(span.row) * (lane_height + row_gap)
        if !finite(left) || !finite(right) || !finite(top) || right <= left { ret (zero, Invalid) }
        var merged = false
        if i > 0usize {
            let before = spans[i - 1usize]
            if span.row == before.row && span.state == before.state && span.start == before.end {
                rects[used - 1usize].width = right - rects[used - 1usize].x
                merged = true
            }
        }
        if !merged {
            rects[used] = geometry.rect(left, top, right - left, lane_height)
            state_ids[used] = span.state
            layers[used] = Layout { kind: .Bar, coords: zero, segments: zero, bars: rects[used..used + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: f32(rows) }
            used += 1usize
        }
        i += 1usize
    }
    ret (layers[..used], ok)
}

// Discrete events become lane-centered lollipop marks on an f64 time domain.
fn event_timeline(events: []const TimelineEvent, rows: usize, domain_start: f64, domain_end: f64, bounds: geometry.Rect, points: []Coord, stems: []Segment) -> (Layout, err) {
    if events.len == 0usize { ret (zero, Empty) }
    if rows == 0usize || !finite64(domain_start) || !finite64(domain_end) || domain_end <= domain_start || !valid_bounds(bounds) { ret (zero, Invalid) }
    if points.len < events.len || stems.len < events.len { ret (zero, TooLarge) }
    let lane = bounds.height / f32(rows)
    if !finite(lane) || lane <= 0.0 { ret (zero, Invalid) }
    var i = 0usize
    while i < events.len {
        let e = events[i]
        if e.row >= rows || !finite64(e.time) || e.time < domain_start || e.time > domain_end || (i > 0usize && e.time < events[i - 1usize].time) { ret (zero, Invalid) }
        let x = bounds.x + bounds.width * f32((e.time - domain_start) / (domain_end - domain_start))
        let y = bounds.y + (f32(e.row) + 0.5) * lane
        if !finite(x) || !finite(y) { ret (zero, Invalid) }
        points[i] = Coord { x: x, y: y }
        stems[i] = Segment { from: Coord { x: x, y: y + lane * 0.28 }, to: points[i] }
        i += 1usize
    }
    ret (Layout { kind: .Lollipop, coords: points[..events.len], segments: stems[..events.len], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: f32(rows) }, ok)
}

fn chord_point(center: Coord, radius: f64, angle: f64) -> Coord {
    ret Coord { x: center.x + f32(radius * math.cos[f64](angle)), y: center.y + f32(radius * math.sin[f64](angle)) }
}

fn chord_curve(from: Coord, to: Coord, center: Coord, t: f32) -> Coord {
    let back = 1.0 - t
    ret Coord { x: back * back * from.x + 2.0 * back * t * center.x + t * t * to.x, y: back * back * from.y + 2.0 * back * t * center.y + t * t * to.y }
}

// Row-major directed weights: each row owns a group arc; opposite cells form
// one possibly tapered ribbon. Ribbons paint before the outer group rings.
// ponytail: fixed-step curves; add adaptive tessellation for zoomed exports.
fn chord(values: []const f32, groups: usize, bounds: geometry.Rect, hole: f32, gap: f32, steps: usize, totals: []f64, arcs: []SunburstArc, subarcs: []SunburstArc, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if groups == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(hole) || hole <= 0.0 || hole >= 1.0 || !finite(gap) || gap < 0.0 || steps < 2usize || values.len / groups != groups || values.len % groups != 0usize { ret (zero, Invalid) }
    let pairs = groups * (groups + 1usize) / 2usize
    if totals.len < groups || arcs.len < groups || subarcs.len < values.len || layers.len < pairs + groups || points.len < 2usize || steps > (points.len - 2usize) / 4usize { ret (zero, TooLarge) }
    let turn = 6.283185307179586f64
    let available = turn - f64(gap) * f64(groups)
    if available <= 0.0f64 { ret (zero, Invalid) }
    var total = 0.0f64
    var i = 0usize
    while i < groups {
        var row = 0.0f64
        var j = 0usize
        while j < groups {
            let value = values[i * groups + j]
            if !finite(value) || value < 0.0 { ret (zero, Invalid) }
            row += f64(value)
            j += 1usize
        }
        if !finite(f32(row)) { ret (zero, Invalid) }
        totals[i] = row
        total += row
        i += 1usize
    }
    if !finite(f32(total)) || total <= 0.0f64 { ret (zero, Invalid) }
    var radius = f64(bounds.width) * 0.5f64
    if bounds.height < bounds.width { radius = f64(bounds.height) * 0.5f64 }
    let inner = radius * f64(hole)
    let center = Coord { x: f32(f64(bounds.x) + f64(bounds.width) * 0.5f64), y: f32(f64(bounds.y) + f64(bounds.height) * 0.5f64) }
    if !finite(center.x) || !finite(center.y) || !finite(f32(radius)) || !finite(f32(inner)) || inner <= 0.0f64 || inner >= radius { ret (zero, Invalid) }
    var angle = -1.5707963267948966f64 + f64(gap) * 0.5f64
    i = 0usize
    while i < groups {
        let end = angle + available * totals[i] / total
        arcs[i] = SunburstArc { start: angle, end: end, next: angle }
        var cursor = angle
        var j = 0usize
        while j < groups {
            var subend = cursor
            if totals[i] > 0.0f64 { subend += (end - angle) * f64(values[i * groups + j]) / totals[i] }
            subarcs[i * groups + j] = SunburstArc { start: cursor, end: subend, next: cursor }
            cursor = subend
            j += 1usize
        }
        angle = end + f64(gap)
        i += 1usize
    }
    var needed = 0usize
    i = 0usize
    while i < groups {
        var j = i
        while j < groups {
            if values[i * groups + j] > 0.0 || values[j * groups + i] > 0.0 {
                var count = 4usize * steps + 2usize
                if i == j { count = 2usize * steps + 1usize }
                if count > points.len - needed { ret (zero, TooLarge) }
                needed += count
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < groups {
        if totals[i] > 0.0f64 {
            let count = 2usize * (steps + 1usize)
            if count > points.len - needed { ret (zero, TooLarge) }
            needed += count
        }
        i += 1usize
    }
    var used = 0usize
    var layer = 0usize
    i = 0usize
    while i < groups {
        var j = i
        while j < groups {
            if values[i * groups + j] == 0.0 && values[j * groups + i] == 0.0 {
                layers[layer] = Layout { kind: .Bar, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
            } else {
                let source = subarcs[i * groups + j]
                let destination = subarcs[j * groups + i]
                let first = used
                var k = 0usize
                while k <= steps {
                    let a = source.start + (source.end - source.start) * f64(k) / f64(steps)
                    points[used] = chord_point(center, inner, a)
                    used += 1usize
                    k += 1usize
                }
                let source_end = points[used - 1usize]
                let source_start = points[first]
                var target_start = source_start
                if i != j { target_start = chord_point(center, inner, destination.start) }
                k = 1usize
                while k <= steps {
                    points[used] = chord_curve(source_end, target_start, center, f32(k) / f32(steps))
                    used += 1usize
                    k += 1usize
                }
                if i != j {
                    k = 0usize
                    while k <= steps {
                        let a = destination.start + (destination.end - destination.start) * f64(k) / f64(steps)
                        points[used] = chord_point(center, inner, a)
                        used += 1usize
                        k += 1usize
                    }
                    let target_end = points[used - 1usize]
                    k = 1usize
                    while k <= steps {
                        points[used] = chord_curve(target_end, source_start, center, f32(k) / f32(steps))
                        used += 1usize
                        k += 1usize
                    }
                }
                layers[layer] = Layout { kind: .Area, coords: points[first..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
            }
            layer += 1usize
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < groups {
        if totals[i] == 0.0f64 {
            layers[layer] = Layout { kind: .Bar, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        } else {
            let first = used
            var k = 0usize
            while k <= steps {
                let a = arcs[i].start + (arcs[i].end - arcs[i].start) * f64(k) / f64(steps)
                points[used] = chord_point(center, radius, a)
                used += 1usize
                k += 1usize
            }
            k = 0usize
            while k <= steps {
                let a = arcs[i].end - (arcs[i].end - arcs[i].start) * f64(k) / f64(steps)
                points[used] = chord_point(center, inner, a)
                used += 1usize
                k += 1usize
            }
            layers[layer] = Layout { kind: .Area, coords: points[first..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        }
        layer += 1usize
        i += 1usize
    }
    i = 0usize
    while i < used {
        if !finite(points[i].x) || !finite(points[i].y) { ret (zero, Invalid) }
        i += 1usize
    }
    ret (layers[..layer], ok)
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

// Parent indices precede children; root 0 names itself and only leaves carry
// weights. Reused by rectangular and radial hierarchy layouts.
fn hierarchy_totals(parents: []const usize, weights: []const f32, totals: []f64) -> err {
    if parents.len == 0usize { ret Empty }
    if parents.len != weights.len || parents[0usize] != 0usize { ret Invalid }
    if totals.len < parents.len { ret TooLarge }
    var i = 0usize
    while i < parents.len {
        if (i > 0usize && parents[i] >= i) || !finite(weights[i]) || weights[i] < 0.0 { ret Invalid }
        if i > 0usize && weights[parents[i]] != 0.0 { ret Invalid }
        totals[i] = f64(weights[i])
        i += 1usize
    }
    i = parents.len
    while i > 1usize {
        i -= 1usize
        totals[parents[i]] += totals[i]
        if !finite64(totals[parents[i]]) { ret Invalid }
    }
    if !(totals[0usize] > 0.0f64) { ret Invalid }
    ret ok
}

// Every node gets a rectangle, while only leaves get a Bar layer.
fn treemap(parents: []const usize, weights: []const f32, bounds: geometry.Rect, totals: []f64, rects: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    let total_error = hierarchy_totals(parents, weights, totals)
    if total_error != ok { ret (zero, total_error) }
    if rects.len < parents.len || layers.len < parents.len { ret (zero, TooLarge) }
    rects[0usize] = bounds
    var i = 0usize
    while i < parents.len {
        var children = 0usize
        var j = 1usize
        while j < parents.len {
            if parents[j] == i { children += 1usize }
            j += 1usize
        }
        if children > 0usize {
            let parent = rects[i]
            let across = parent.width >= parent.height
            var cumulative = 0.0f64
            var placed = 0usize
            // ponytail: sibling scans are O(n^2) and long strips are possible;
            // use caller-scratch squarification if very large trees need it.
            j = 1usize
            while j < parents.len {
                if parents[j] == i {
                    placed += 1usize
                    var start = 0.0f64
                    var finish = 0.0f64
                    if totals[i] > 0.0f64 {
                        start = cumulative / totals[i]
                        cumulative += totals[j]
                        finish = cumulative / totals[i]
                    }
                    if placed == children { finish = 1.0f64 }
                    if across {
                        let left = parent.x + parent.width * f32(start)
                        let right = parent.x + parent.width * f32(finish)
                        if !finite(left) || !finite(right) || right < left { ret (zero, Invalid) }
                        rects[j] = geometry.rect(left, parent.y, right - left, parent.height)
                    } else {
                        let top = parent.y + parent.height * f32(start)
                        let bottom = parent.y + parent.height * f32(finish)
                        if !finite(top) || !finite(bottom) || bottom < top { ret (zero, Invalid) }
                        rects[j] = geometry.rect(parent.x, top, parent.width, bottom - top)
                    }
                }
                j += 1usize
            }
            layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        } else {
            layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: rects[i..i + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        }
        i += 1usize
    }
    ret (layers[..parents.len], ok)
}

// Depth occupies horizontal bands; each sibling keeps its subtree's width.
// Shallow leaves extend to the bottom of the panel.
fn icicle(parents: []const usize, weights: []const f32, bounds: geometry.Rect, totals: []f64, depths: []usize, rects: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    let total_error = hierarchy_totals(parents, weights, totals)
    if total_error != ok { ret (zero, total_error) }
    if depths.len < parents.len || rects.len < parents.len || layers.len < parents.len { ret (zero, TooLarge) }
    depths[0usize] = 0usize
    var max_depth = 0usize
    var i = 1usize
    while i < parents.len {
        depths[i] = depths[parents[i]] + 1usize
        if depths[i] > max_depth { max_depth = depths[i] }
        i += 1usize
    }
    let row_height = bounds.height / f32(max_depth + 1usize)
    if !finite(row_height) || row_height <= 0.0 { ret (zero, Invalid) }
    rects[0usize] = geometry.rect(bounds.x, bounds.y, bounds.width, row_height)
    i = 1usize
    while i < parents.len {
        let parent = parents[i]
        var before = 0.0f64
        var j = 1usize
        // ponytail: preceding-sibling scans are O(n^2); use caller-owned
        // per-parent cursors only if large hierarchies need linear layout.
        while j < i {
            if parents[j] == parent { before += totals[j] }
            j += 1usize
        }
        var left = rects[parent].x
        var right = left
        if totals[parent] > 0.0f64 {
            left += rects[parent].width * f32(before / totals[parent])
            right = rects[parent].x + rects[parent].width * f32((before + totals[i]) / totals[parent])
        }
        let top = bounds.y + f32(depths[i]) * row_height
        var bottom = top + row_height
        if weights[i] > 0.0 { bottom = bounds.y + bounds.height }
        if !finite(left) || !finite(right) || !finite(top) || !finite(bottom) || right < left || bottom < top { ret (zero, Invalid) }
        rects[i] = geometry.rect(left, top, right - left, bottom - top)
        i += 1usize
    }
    if weights[0usize] > 0.0 { rects[0usize] = bounds }
    i = 0usize
    while i < parents.len {
        var bars: []geometry.Rect = zero
        if totals[i] > 0.0f64 { bars = rects[i..i + 1usize] }
        layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..parents.len], ok)
}

// Siblings occupy disjoint circles inside their parent; area ratios match
// subtree totals. Each sibling group uses one deterministic ring.
fn circle_pack(parents: []const usize, weights: []const f32, bounds: geometry.Rect, padding: f32, totals: []f64, circles: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) || !finite(padding) || padding < 0.0 || padding >= 1.0 { ret (zero, Invalid) }
    let total_error = hierarchy_totals(parents, weights, totals)
    if total_error != ok { ret (zero, total_error) }
    if circles.len < parents.len || layers.len < parents.len { ret (zero, TooLarge) }
    var root_radius = f64(bounds.width) * 0.5f64
    if bounds.height < bounds.width { root_radius = f64(bounds.height) * 0.5f64 }
    let root_x = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let root_y = f64(bounds.y) + f64(bounds.height) * 0.5f64
    if !finite(f32(root_x - root_radius)) || !finite(f32(root_y - root_radius)) || !finite(f32(root_radius * 2.0f64)) { ret (zero, Invalid) }
    circles[0usize] = geometry.rect(f32(root_x - root_radius), f32(root_y - root_radius), f32(root_radius * 2.0f64), f32(root_radius * 2.0f64))
    var i = 0usize
    while i < parents.len {
        var count = 0usize
        var maximum = 0.0f64
        var j = i + 1usize
        while j < parents.len {
            if parents[j] == i {
                count += 1usize
                if totals[j] > maximum { maximum = totals[j] }
            }
            j += 1usize
        }
        if count > 0usize {
            let parent = circles[i]
            let center_x = f64(parent.x) + f64(parent.width) * 0.5f64
            let center_y = f64(parent.y) + f64(parent.height) * 0.5f64
            let parent_radius = f64(parent.width) * 0.5f64
            let orbit = parent_radius * f64(1.0 - padding) * 0.5f64
            var rank = 0usize
            // ponytail: sibling scans are O(n^2) and ring packing wastes space
            // for large groups; use caller-scratch tangent packing if density matters.
            j = i + 1usize
            while j < parents.len {
                if parents[j] == i {
                    var angle = 0.0f64
                    var radius = 0.0f64
                    if count == 1usize {
                        radius = parent_radius * f64(1.0 - padding)
                    } else {
                        angle = 6.283185307179586f64 * f64(rank) / f64(count)
                        if maximum > 0.0f64 { radius = orbit * math.sin[f64](3.141592653589793f64 / f64(count)) * math.sqrt[f64](totals[j] / maximum) }
                    }
                    var x = center_x
                    var y = center_y
                    if count > 1usize {
                        x += orbit * math.cos[f64](angle)
                        y += orbit * math.sin[f64](angle)
                    }
                    let left = f32(x - radius)
                    let top = f32(y - radius)
                    let diameter = f32(radius * 2.0f64)
                    if !finite(left) || !finite(top) || !finite(diameter) || (totals[j] > 0.0f64 && diameter <= 0.0) { ret (zero, Invalid) }
                    circles[j] = geometry.rect(left, top, diameter, diameter)
                    rank += 1usize
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < parents.len {
        var bars: []geometry.Rect = zero
        if totals[i] > 0.0f64 { bars = circles[i..i + 1usize] }
        layers[i] = Layout { kind: .Bubble, coords: zero, segments: zero, bars: bars, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..parents.len], ok)
}

// Exact two-circle overlap in the same area units as r1 and r2.
fn circle_overlap_area(r1: f64, r2: f64, distance: f64) -> f64 {
    let pi = 3.141592653589793f64
    if distance >= r1 + r2 { ret 0.0f64 }
    var difference = r1 - r2
    if difference < 0.0f64 { difference = 0.0f64 - difference }
    if distance <= difference {
        var smaller = r1
        if r2 < smaller { smaller = r2 }
        ret pi * smaller * smaller
    }
    var first = (distance * distance + r1 * r1 - r2 * r2) / (2.0f64 * distance * r1)
    var second = (distance * distance + r2 * r2 - r1 * r1) / (2.0f64 * distance * r2)
    if first < -1.0f64 { first = -1.0f64 }
    if first > 1.0f64 { first = 1.0f64 }
    if second < -1.0f64 { second = -1.0f64 }
    if second > 1.0f64 { second = 1.0f64 }
    var root = (0.0f64 - distance + r1 + r2) * (distance + r1 - r2) * (distance - r1 + r2) * (distance + r1 + r2)
    if root < 0.0f64 { root = 0.0f64 }
    ret r1 * r1 * math.acos[f64](first) + r2 * r2 * math.acos[f64](second) - 0.5f64 * math.sqrt[f64](root)
}

// Two-set area-proportional Euler diagram. A full subset is concentric;
// disjoint sets get a small visual gap. The caller owns both circle marks.
fn euler2(first: f32, second: f32, overlap: f32, bounds: geometry.Rect, circles: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) || !finite(first) || !finite(second) || !finite(overlap) || first < 0.0 || second < 0.0 || overlap < 0.0 || overlap > first || overlap > second { ret (zero, Invalid) }
    if circles.len < 2usize || layers.len < 2usize { ret (zero, TooLarge) }
    if first == 0.0 && second == 0.0 { ret (zero, Empty) }
    let pi = 3.141592653589793f64
    let r1 = math.sqrt[f64](f64(first) / pi)
    let r2 = math.sqrt[f64](f64(second) / pi)
    var distance = 0.0f64
    if overlap == 0.0 {
        var smaller = r1
        if r2 < smaller { smaller = r2 }
        distance = r1 + r2 + smaller * 0.18f64
    } else {
        var smaller = first
        if second < smaller { smaller = second }
        if overlap < smaller {
            var low = r1 - r2
            if low < 0.0f64 { low = 0.0f64 - low }
            var high = r1 + r2
            var step = 0usize
            while step < 56usize {
                let middle = (low + high) * 0.5f64
                if circle_overlap_area(r1, r2, middle) > f64(overlap) { low = middle } else { high = middle }
                step += 1usize
            }
            distance = (low + high) * 0.5f64
        }
    }
    var left = 0.0f64 - r1
    if distance - r2 < left { left = distance - r2 }
    var right = r1
    if distance + r2 > right { right = distance + r2 }
    var tall = r1
    if r2 > tall { tall = r2 }
    var scale = f64(bounds.width) / (right - left)
    let vertical = f64(bounds.height) / (2.0f64 * tall)
    if vertical < scale { scale = vertical }
    scale *= 0.92f64
    let cx1 = f64(bounds.x) + (f64(bounds.width) - (right - left) * scale) * 0.5f64 - left * scale
    let cx2 = cx1 + distance * scale
    let cy = f64(bounds.y) + f64(bounds.height) * 0.5f64
    let radii = [2]f64{ r1 * scale, r2 * scale }
    let centers = [2]f64{ cx1, cx2 }
    var i = 0usize
    while i < 2usize {
        let x = f32(centers[i] - radii[i])
        let y = f32(cy - radii[i])
        let diameter = f32(2.0f64 * radii[i])
        if !finite(x) || !finite(y) || !finite(diameter) || (radii[i] > 0.0f64 && diameter <= 0.0) { ret (zero, Invalid) }
        circles[i] = geometry.rect(x, y, diameter, diameter)
        var bars: []geometry.Rect = zero
        if diameter > 0.0 { bars = circles[i..i + 1usize] }
        layers[i] = Layout { kind: .Bubble, coords: zero, segments: zero, bars: bars, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..2usize], ok)
}

// Nominal three-set Venn: all seven memberships have nonempty regions.
// Anchor order is A, B, C, AB, AC, BC, ABC; no area claims are made.
// ponytail: fixed circles cannot encode seven arbitrary region areas; add a fitted-region solver only when those areas are required.
fn venn3(bounds: geometry.Rect, circles: []geometry.Rect, anchors: []Coord, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) { ret (zero, Invalid) }
    if circles.len < 3usize || anchors.len < 7usize || layers.len < 3usize { ret (zero, TooLarge) }
    var radius = f64(bounds.width) / 3.15f64
    let vertical = f64(bounds.height) / 2.995929214352104f64
    if vertical < radius { radius = vertical }
    radius *= 0.92f64
    let distance = radius * 1.15f64
    let dy = distance * 0.2886751345948129f64
    let cx = f64(bounds.x) + f64(bounds.width) * 0.5f64
    let cy = f64(bounds.y) + f64(bounds.height) * 0.5f64
    let xs = [3]f64{ cx, cx - distance * 0.5f64, cx + distance * 0.5f64 }
    let ys = [3]f64{ cy - 2.0f64 * dy, cy + dy, cy + dy }
    var i = 0usize
    while i < 3usize {
        let x = f32(xs[i] - radius)
        let y = f32(ys[i] - radius)
        let diameter = f32(2.0f64 * radius)
        if !finite(x) || !finite(y) || !finite(diameter) || diameter <= 0.0 { ret (zero, Invalid) }
        circles[i] = geometry.rect(x, y, diameter, diameter)
        layers[i] = Layout { kind: .Bubble, coords: zero, segments: zero, bars: circles[i..i + 1usize], x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    anchors[0usize] = Coord { x: f32(xs[0usize]), y: f32(ys[0usize] - radius * 0.5f64) }
    anchors[1usize] = Coord { x: f32(xs[1usize] - radius * 0.45f64), y: f32(ys[1usize] + radius * 0.3f64) }
    anchors[2usize] = Coord { x: f32(xs[2usize] + radius * 0.45f64), y: f32(ys[2usize] + radius * 0.3f64) }
    anchors[3usize] = Coord { x: f32((xs[0usize] + xs[1usize]) * 0.5f64 - radius * 0.18f64), y: f32((ys[0usize] + ys[1usize]) * 0.5f64) }
    anchors[4usize] = Coord { x: f32((xs[0usize] + xs[2usize]) * 0.5f64 + radius * 0.18f64), y: f32((ys[0usize] + ys[2usize]) * 0.5f64) }
    anchors[5usize] = Coord { x: f32(cx), y: f32(cy + dy + radius * 0.23f64) }
    anchors[6usize] = Coord { x: f32(cx), y: f32(cy) }
    i = 0usize
    while i < 7usize {
        if !finite(anchors[i].x) || !finite(anchors[i].y) { ret (zero, Invalid) }
        i += 1usize
    }
    ret (layers[..3usize], ok)
}

// Nodes are ordered within zero-based columns; links go strictly forward.
// Link layers precede node layers so painted nodes cover ribbon endpoints.
// ponytail: fixed input order can cross ribbons; add barycentric ordering only
// when the caller can supply identity-preserving reorder scratch.
fn sankey(node_columns: []const usize, columns: usize, sources: []const usize, targets: []const usize, values: []const f32, bounds: geometry.Rect, node_width: f32, node_gap: f32, steps: usize, nodes: []SankeyNode, rects: []geometry.Rect, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if node_columns.len == 0usize || sources.len == 0usize { ret (zero, Empty) }
    if columns < 2usize || sources.len != targets.len || sources.len != values.len || !valid_bounds(bounds) || !finite(node_width) || !finite(node_gap) || node_width <= 0.0 || node_gap < 0.0 || steps < 2usize || steps > 64usize { ret (zero, Invalid) }
    if node_columns.len > nodes.len || node_columns.len > rects.len || sources.len > layers.len || node_columns.len > layers.len - sources.len || sources.len > points.len / (2usize * (steps + 1usize)) { ret (zero, TooLarge) }
    let column_width = (bounds.width - node_width) / f32(columns - 1usize)
    if !finite(column_width) || column_width <= node_width { ret (zero, Invalid) }
    var i = 0usize
    while i < node_columns.len {
        if node_columns[i] >= columns { ret (zero, Invalid) }
        nodes[i] = SankeyNode { incoming: 0.0f64, outgoing: 0.0f64, in_used: 0.0f64, out_used: 0.0f64 }
        i += 1usize
    }
    i = 0usize
    while i < sources.len {
        let from = sources[i]
        let to = targets[i]
        if from >= node_columns.len || to >= node_columns.len || node_columns[from] >= node_columns[to] || !finite(values[i]) || values[i] < 0.0 { ret (zero, Invalid) }
        nodes[from].outgoing += f64(values[i])
        nodes[to].incoming += f64(values[i])
        if !finite64(nodes[from].outgoing) || !finite64(nodes[to].incoming) { ret (zero, Invalid) }
        i += 1usize
    }
    var scale = 0.0f64
    var column = 0usize
    while column < columns {
        var count = 0usize
        var total = 0.0f64
        i = 0usize
        while i < node_columns.len {
            if node_columns[i] == column {
                count += 1usize
                var flow = nodes[i].incoming
                if nodes[i].outgoing > flow { flow = nodes[i].outgoing }
                total += flow
            }
            i += 1usize
        }
        if count == 0usize || !finite64(total) || total <= 0.0f64 { ret (zero, Invalid) }
        let available = f64(bounds.height) - f64(node_gap) * f64(count - 1usize)
        if !finite64(available) || available <= 0.0f64 { ret (zero, Invalid) }
        let candidate = available / total
        if !finite64(candidate) || candidate <= 0.0f64 { ret (zero, Invalid) }
        if column == 0usize || candidate < scale { scale = candidate }
        column += 1usize
    }
    column = 0usize
    while column < columns {
        var count = 0usize
        var total = 0.0f64
        i = 0usize
        while i < node_columns.len {
            if node_columns[i] == column {
                count += 1usize
                var flow = nodes[i].incoming
                if nodes[i].outgoing > flow { flow = nodes[i].outgoing }
                total += flow
            }
            i += 1usize
        }
        let used = total * scale + f64(node_gap) * f64(count - 1usize)
        var cursor = f64(bounds.y) + (f64(bounds.height) - used) * 0.5f64
        let x = bounds.x + column_width * f32(column)
        i = 0usize
        while i < node_columns.len {
            if node_columns[i] == column {
                var flow = nodes[i].incoming
                if nodes[i].outgoing > flow { flow = nodes[i].outgoing }
                let height = f32(flow * scale)
                if !finite(x) || !finite(f32(cursor)) || !finite(height) || (flow > 0.0f64 && height <= 0.0) { ret (zero, Invalid) }
                rects[i] = geometry.rect(x, f32(cursor), node_width, height)
                cursor += f64(height) + f64(node_gap)
            }
            i += 1usize
        }
        column += 1usize
    }
    var used_points = 0usize
    i = 0usize
    while i < sources.len {
        let from = sources[i]
        let to = targets[i]
        let value = f64(values[i])
        if value == 0.0f64 {
            layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        } else {
            let x0 = rects[from].x + node_width
            let x1 = rects[to].x
            let top0 = rects[from].y + f32(nodes[from].out_used * scale)
            let top1 = rects[to].y + f32(nodes[to].in_used * scale)
            let thickness = f32(value * scale)
            if !finite(x0) || !finite(x1) || !finite(top0) || !finite(top1) || !finite(thickness) || thickness <= 0.0 { ret (zero, Invalid) }
            let first = used_points
            var j = 0usize
            while j <= steps {
                let t = f32(j) / f32(steps)
                let eased = t * t * (3.0 - 2.0 * t)
                points[used_points] = Coord { x: x0 + (x1 - x0) * t, y: top0 + (top1 - top0) * eased }
                used_points += 1usize
                j += 1usize
            }
            j = 0usize
            while j <= steps {
                let t = 1.0 - f32(j) / f32(steps)
                let eased = t * t * (3.0 - 2.0 * t)
                points[used_points] = Coord { x: x0 + (x1 - x0) * t, y: top0 + thickness + (top1 - top0) * eased }
                used_points += 1usize
                j += 1usize
            }
            layers[i] = Layout { kind: .Area, coords: points[first..used_points], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        }
        nodes[from].out_used += value
        nodes[to].in_used += value
        i += 1usize
    }
    i = 0usize
    while i < node_columns.len {
        var bars: []geometry.Rect = zero
        if rects[i].height > 0.0 { bars = rects[i..i + 1usize] }
        layers[sources.len + i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        i += 1usize
    }
    ret (layers[..sources.len + node_columns.len], ok)
}

// An alluvial diagram conserves each interior stratum across adjacent stages.
// Each input link remains a separate caller-colourable ribbon.
// ponytail: keep caller order; add crossing reduction only when real charts need it.
fn alluvial(node_columns: []const usize, columns: usize, sources: []const usize, targets: []const usize, values: []const f32, bounds: geometry.Rect, node_width: f32, node_gap: f32, steps: usize, nodes: []SankeyNode, rects: []geometry.Rect, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if node_columns.len == 0usize || sources.len == 0usize { ret (zero, Empty) }
    if columns < 2usize || sources.len != targets.len || sources.len != values.len { ret (zero, Invalid) }
    var i = 0usize
    while i < sources.len {
        let from = sources[i]
        let to = targets[i]
        if from >= node_columns.len || to >= node_columns.len || node_columns[from] >= columns || node_columns[to] >= columns || node_columns[from] + 1usize != node_columns[to] { ret (zero, Invalid) }
        i += 1usize
    }
    let (marks, layout_error) = sankey(node_columns, columns, sources, targets, values, bounds, node_width, node_gap, steps, nodes, rects, points, layers)
    if layout_error != ok { ret (zero, layout_error) }
    i = 0usize
    while i < node_columns.len {
        if node_columns[i] > 0usize && node_columns[i] + 1usize < columns {
            var difference = nodes[i].incoming - nodes[i].outgoing
            if difference < 0.0f64 { difference = 0.0f64 - difference }
            var size = nodes[i].incoming
            if nodes[i].outgoing > size { size = nodes[i].outgoing }
            if difference > size * 0.000001f64 { ret (zero, Invalid) }
        }
        i += 1usize
    }
    ret (marks, ok)
}

// Root occupies the innermost ring, each generation the next. A leaf extends
// through any remaining rings; zero-total nodes return empty Bar layers.
fn sunburst(parents: []const usize, weights: []const f32, bounds: geometry.Rect, hole: f32, totals: []f64, depths: []usize, arcs: []SunburstArc, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) || !finite(hole) || hole < 0.0 || hole >= 1.0 { ret (zero, Invalid) }
    let total_error = hierarchy_totals(parents, weights, totals)
    if total_error != ok { ret (zero, total_error) }
    if depths.len < parents.len || arcs.len < parents.len || layers.len < parents.len { ret (zero, TooLarge) }
    let turn = 6.283185307179586f64
    let top = -1.5707963267948966f64
    depths[0usize] = 0usize
    arcs[0usize] = SunburstArc { start: top, end: top + turn, next: top }
    var max_depth = 0usize
    var i = 1usize
    while i < parents.len {
        let parent = parents[i]
        depths[i] = depths[parent] + 1usize
        if depths[i] > max_depth { max_depth = depths[i] }
        let start = arcs[parent].next
        var end = start
        if totals[parent] > 0.0f64 { end += (arcs[parent].end - arcs[parent].start) * totals[i] / totals[parent] }
        if !finite64(end) { ret (zero, Invalid) }
        arcs[parent].next = end
        arcs[i] = SunburstArc { start: start, end: end, next: start }
        i += 1usize
    }
    var radius = bounds.width * 0.5
    if bounds.height < bounds.width { radius = bounds.height * 0.5 }
    let inner = radius * hole
    let ring_width = (radius - inner) / f32(max_depth + 1usize)
    let cx = bounds.x + bounds.width * 0.5
    let cy = bounds.y + bounds.height * 0.5
    if !finite(radius) || !finite(inner) || !finite(ring_width) || ring_width <= 0.0 || !finite(cx) || !finite(cy) { ret (zero, Invalid) }
    var needed = 0usize
    i = 0usize
    while i < parents.len {
        if totals[i] > 0.0f64 {
            let steps = 2usize + usize((arcs[i].end - arcs[i].start) / turn * 96.0f64)
            let count = 2usize * (steps + 1usize)
            if needed > points.len || count > points.len - needed { ret (zero, TooLarge) }
            needed += count
        }
        i += 1usize
    }
    var used = 0usize
    i = 0usize
    while i < parents.len {
        if totals[i] == 0.0f64 {
            layers[i] = Layout { kind: .Bar, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        } else {
            let fraction_of_turn = (arcs[i].end - arcs[i].start) / turn
            let steps = 2usize + usize(fraction_of_turn * 96.0f64)
            let low = inner + f32(depths[i]) * ring_width
            var high = low + ring_width
            if weights[i] > 0.0 { high = radius }
            let first = used
            var j = 0usize
            while j <= steps {
                let angle = arcs[i].start + (arcs[i].end - arcs[i].start) * f64(j) / f64(steps)
                let x = cx + high * f32(math.cos[f64](angle))
                let y = cy + high * f32(math.sin[f64](angle))
                if !finite(x) || !finite(y) { ret (zero, Invalid) }
                points[used] = Coord { x: x, y: y }
                used += 1usize
                j += 1usize
            }
            j = 0usize
            while j <= steps {
                let angle = arcs[i].end - (arcs[i].end - arcs[i].start) * f64(j) / f64(steps)
                let x = cx + low * f32(math.cos[f64](angle))
                let y = cy + low * f32(math.sin[f64](angle))
                if !finite(x) || !finite(y) { ret (zero, Invalid) }
                points[used] = Coord { x: x, y: y }
                used += 1usize
                j += 1usize
            }
            layers[i] = Layout { kind: .Area, coords: points[first..used], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
        }
        i += 1usize
    }
    ret (layers[..parents.len], ok)
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

// Numeric x positions may be irregular; the smallest interval controls mark
// width while half an interval pads the first and last marks into the panel.
fn ohlc_domain(x: []const f32, opens: []const f32, highs: []const f32, lows: []const f32, closes: []const f32) -> (f32, f32, f32, f32, f32, err) {
    if x.len == 0usize { ret (0.0, 0.0, 0.0, 0.0, 0.0, Empty) }
    if opens.len != x.len || highs.len != x.len || lows.len != x.len || closes.len != x.len { ret (0.0, 0.0, 0.0, 0.0, 0.0, Invalid) }
    var ymin = lows[0usize]
    var ymax = highs[0usize]
    var step = 1.0f32
    if x.len > 1usize { step = x[1usize] - x[0usize] }
    var i = 0usize
    while i < x.len {
        if !finite(x[i]) || !finite(opens[i]) || !finite(highs[i]) || !finite(lows[i]) || !finite(closes[i]) || lows[i] > opens[i] || lows[i] > closes[i] || highs[i] < opens[i] || highs[i] < closes[i] { ret (0.0, 0.0, 0.0, 0.0, 0.0, Invalid) }
        if i > 0usize {
            let gap = x[i] - x[i - 1usize]
            if !finite(gap) || gap <= 0.0 { ret (0.0, 0.0, 0.0, 0.0, 0.0, Invalid) }
            if gap < step { step = gap }
        }
        if lows[i] < ymin { ymin = lows[i] }
        if highs[i] > ymax { ymax = highs[i] }
        i += 1usize
    }
    let xmin = x[0usize] - step * 0.5
    let xmax = x[x.len - 1usize] + step * 0.5
    if ymin == ymax {
        ymin -= 0.5
        ymax += 0.5
    }
    if !finite(xmin) || !finite(xmax) || !(xmax > xmin) || !finite(ymin) || !finite(ymax) || !(ymax > ymin) { ret (0.0, 0.0, 0.0, 0.0, 0.0, Invalid) }
    ret (xmin, xmax, ymin, ymax, step, ok)
}

fn price_y(value: f32, ymin: f32, ymax: f32, bounds: geometry.Rect) -> f32 {
    ret bounds.y + bounds.height * (1.0 - (value - ymin) / (ymax - ymin))
}

// Wicks, rising bodies and falling bodies are separate borrowed-colour layers.
// Zero-height (doji) bodies get a horizontal stroke instead of disappearing.
fn candlestick(x: []const f32, opens: []const f32, highs: []const f32, lows: []const f32, closes: []const f32, bounds: geometry.Rect, body_fraction: f32, wicks: []Segment, rising: []geometry.Rect, falling: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if !valid_bounds(bounds) || !finite(body_fraction) || body_fraction <= 0.0 || body_fraction >= 1.0 { ret (zero, Invalid) }
    let (xmin, xmax, ymin, ymax, step, domain_error) = ohlc_domain(x, opens, highs, lows, closes)
    if domain_error != ok { ret (zero, domain_error) }
    if wicks.len / 2usize < x.len || rising.len < x.len || falling.len < x.len || layers.len < 3usize { ret (zero, TooLarge) }
    let width = bounds.width * step / (xmax - xmin) * body_fraction
    if !finite(width) || width <= 0.0 { ret (zero, Invalid) }
    var up = 0usize
    var down = 0usize
    var strokes = 0usize
    var i = 0usize
    while i < x.len {
        let center = mapped(x[i], xmin, xmax, bounds.x, bounds.width)
        let high_y = price_y(highs[i], ymin, ymax, bounds)
        let low_y = price_y(lows[i], ymin, ymax, bounds)
        let open_y = price_y(opens[i], ymin, ymax, bounds)
        let close_y = price_y(closes[i], ymin, ymax, bounds)
        if !finite(center) || !finite(high_y) || !finite(low_y) || !finite(open_y) || !finite(close_y) { ret (zero, Invalid) }
        wicks[strokes] = Segment { from: Coord { x: center, y: high_y }, to: Coord { x: center, y: low_y } }
        strokes += 1usize
        if opens[i] == closes[i] {
            wicks[strokes] = Segment { from: Coord { x: center - width * 0.5, y: open_y }, to: Coord { x: center + width * 0.5, y: open_y } }
            strokes += 1usize
        } else if closes[i] > opens[i] {
            rising[up] = geometry.rect(center - width * 0.5, close_y, width, open_y - close_y)
            up += 1usize
        } else {
            falling[down] = geometry.rect(center - width * 0.5, open_y, width, close_y - open_y)
            down += 1usize
        }
        i += 1usize
    }
    layers[0usize] = Layout { kind: .Rug, coords: zero, segments: wicks[..strokes], bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }
    layers[1usize] = Layout { kind: .Bar, coords: zero, segments: zero, bars: rising[..up], x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }
    layers[2usize] = Layout { kind: .Bar, coords: zero, segments: zero, bars: falling[..down], x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }
    ret (layers[..3usize], ok)
}

// One stem plus left-open and right-close ticks per observation.
fn ohlc(x: []const f32, opens: []const f32, highs: []const f32, lows: []const f32, closes: []const f32, bounds: geometry.Rect, tick_fraction: f32, lines: []Segment) -> (Layout, err) {
    if !valid_bounds(bounds) || !finite(tick_fraction) || tick_fraction <= 0.0 || tick_fraction >= 1.0 { ret (zero, Invalid) }
    let (xmin, xmax, ymin, ymax, step, domain_error) = ohlc_domain(x, opens, highs, lows, closes)
    if domain_error != ok { ret (zero, domain_error) }
    if lines.len / 3usize < x.len { ret (zero, TooLarge) }
    let half = bounds.width * step / (xmax - xmin) * tick_fraction * 0.5
    if !finite(half) || half <= 0.0 { ret (zero, Invalid) }
    var i = 0usize
    while i < x.len {
        let center = mapped(x[i], xmin, xmax, bounds.x, bounds.width)
        let high_y = price_y(highs[i], ymin, ymax, bounds)
        let low_y = price_y(lows[i], ymin, ymax, bounds)
        let open_y = price_y(opens[i], ymin, ymax, bounds)
        let close_y = price_y(closes[i], ymin, ymax, bounds)
        if !finite(center) || !finite(high_y) || !finite(low_y) || !finite(open_y) || !finite(close_y) { ret (zero, Invalid) }
        let first = 3usize * i
        lines[first] = Segment { from: Coord { x: center, y: high_y }, to: Coord { x: center, y: low_y } }
        lines[first + 1usize] = Segment { from: Coord { x: center - half, y: open_y }, to: Coord { x: center, y: open_y } }
        lines[first + 2usize] = Segment { from: Coord { x: center, y: close_y }, to: Coord { x: center + half, y: close_y } }
        i += 1usize
    }
    ret (Layout { kind: .Rug, coords: zero, segments: lines[..3usize * x.len], bars: zero, x_min: xmin, x_max: xmax, y_min: ymin, y_max: ymax }, ok)
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

// Variable-width columns make each cell area proportional to its value.
// Input is category-major; output is series-major for caller-selected colours.
fn mekko(values: []const f32, categories: usize, series: usize, bounds: geometry.Rect, totals: []f64, bars: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if categories == 0usize || series == 0usize { ret (zero, Empty) }
    if !bar_grid_ok(values, categories, series, bounds) { ret (zero, Invalid) }
    if totals.len < categories || bars.len < values.len || layers.len < series { ret (zero, TooLarge) }
    var grand = 0.0f64
    var category = 0usize
    while category < categories {
        var total = 0.0f64
        var column = 0usize
        while column < series {
            let value = values[category * series + column]
            if !finite(value) || value < 0.0 { ret (zero, Invalid) }
            total += f64(value)
            column += 1usize
        }
        if !finite(f32(total)) { ret (zero, Invalid) }
        totals[category] = total
        grand += total
        category += 1usize
    }
    if !finite(f32(grand)) { ret (zero, Invalid) }
    if grand <= 0.0f64 { ret (zero, Empty) }
    var cumulative = 0.0f64
    category = 0usize
    while category < categories {
        let left = bounds.x + bounds.width * f32(cumulative / grand)
        cumulative += totals[category]
        let right = bounds.x + bounds.width * f32(cumulative / grand)
        var stacked = 0.0f64
        var column = 0usize
        while column < series {
            let value = f64(values[category * series + column])
            var top = bounds.y + bounds.height
            var bottom = top
            if totals[category] > 0.0f64 {
                bottom = bounds.y + bounds.height * (1.0 - f32(stacked / totals[category]))
                stacked += value
                top = bounds.y + bounds.height * (1.0 - f32(stacked / totals[category]))
            }
            if !finite(left) || !finite(right) || !finite(top) || !finite(bottom) || (totals[category] > 0.0f64 && right <= left) || (value > 0.0f64 && bottom <= top) { ret (zero, Invalid) }
            bars[column * categories + category] = geometry.rect(left, top, right - left, bottom - top)
            column += 1usize
        }
        category += 1usize
    }
    let made = bar_layers(categories, series, bars, layers, 0.0, 1.0)
    var i = 0usize
    while i < made.len {
        layers[i].x_max = 1.0
        i += 1usize
    }
    ret (made, ok)
}

// Contingency-table mosaic: tile area follows count, colour follows Pearson
// residual from independence. Input is column-major; zero cells emit no tile.
fn mosaic(counts: []const f64, columns: usize, bounds: geometry.Rect, gutter: f32, column_totals: []f64, row_totals: []f64, cells: []Cell) -> (MatrixLayout, err) {
    if counts.len == 0usize { ret (zero, Empty) }
    if columns == 0usize || counts.len % columns != 0usize || !valid_bounds(bounds) || !finite(gutter) || gutter < 0.0 { ret (zero, Invalid) }
    let rows = counts.len / columns
    if column_totals.len < columns || row_totals.len < rows || cells.len < counts.len { ret (zero, TooLarge) }
    var row = 0usize
    while row < rows {
        row_totals[row] = 0.0f64
        row += 1usize
    }
    var grand = 0.0f64
    var column = 0usize
    while column < columns {
        var total = 0.0f64
        row = 0usize
        while row < rows {
            let value = counts[column * rows + row]
            if !finite64(value) || value < 0.0f64 { ret (zero, Invalid) }
            total += value
            row_totals[row] += value
            row += 1usize
        }
        if !finite64(total) { ret (zero, Invalid) }
        column_totals[column] = total
        grand += total
        column += 1usize
    }
    if !finite64(grand) { ret (zero, Invalid) }
    if grand <= 0.0f64 { ret (zero, Empty) }
    var cumulative = 0.0f64
    var used = 0usize
    var maximum = 0.0f32
    column = 0usize
    while column < columns {
        let left = bounds.x + bounds.width * f32(cumulative / grand)
        cumulative += column_totals[column]
        let right = bounds.x + bounds.width * f32(cumulative / grand)
        var stacked = 0.0f64
        row = 0usize
        while row < rows {
            let value = counts[column * rows + row]
            if value > 0.0f64 {
                let bottom = bounds.y + bounds.height * f32(1.0f64 - stacked / column_totals[column])
                stacked += value
                let top = bounds.y + bounds.height * f32(1.0f64 - stacked / column_totals[column])
                let expected = (column_totals[column] / grand) * row_totals[row]
                if expected <= 0.0f64 { ret (zero, Invalid) }
                let residual = f32((value - expected) / math.sqrt[f64](expected))
                let width = right - left - gutter
                let height = bottom - top - gutter
                if !finite(residual) || !finite(left) || !finite(top) || !finite(width) || !finite(height) || width <= 0.0 || height <= 0.0 { ret (zero, Invalid) }
                cells[used] = Cell { rect: geometry.rect(left + gutter / 2.0, top + gutter / 2.0, width, height), value: residual }
                var magnitude = residual
                if magnitude < 0.0 { magnitude = -magnitude }
                if magnitude > maximum { maximum = magnitude }
                used += 1usize
            }
            row += 1usize
        }
        column += 1usize
    }
    if maximum == 0.0 { maximum = 1.0 }
    ret (MatrixLayout { kind: .Mosaic, cells: cells[..used], columns: columns, rows: rows, value_min: -maximum, value_max: maximum }, ok)
}

// Two nonnegative age series diverge from a shared central label gutter.
// Input rows run from youngest (bottom) to oldest (top).
fn population_pyramid(left: []const f32, right: []const f32, bounds: geometry.Rect, gutter: f32, row_gap: f32, bars: []geometry.Rect, layers: []Layout) -> ([]Layout, err) {
    if left.len == 0usize { ret (zero, Empty) }
    if left.len != right.len || !valid_bounds(bounds) || !finite(gutter) || !finite(row_gap) || gutter < 0.0 || gutter >= bounds.width || row_gap < 0.0 { ret (zero, Invalid) }
    if left.len > bars.len / 2usize || layers.len < 2usize { ret (zero, TooLarge) }
    let slot = bounds.height / f32(left.len)
    let half = (bounds.width - gutter) * 0.5
    if !finite(slot) || !finite(half) || slot <= row_gap || half <= 0.0 { ret (zero, Invalid) }
    var maximum = 0.0f32
    var i = 0usize
    while i < left.len {
        if !finite(left[i]) || !finite(right[i]) || left[i] < 0.0 || right[i] < 0.0 { ret (zero, Invalid) }
        if left[i] > maximum { maximum = left[i] }
        if right[i] > maximum { maximum = right[i] }
        i += 1usize
    }
    if maximum <= 0.0 { ret (zero, Invalid) }
    let center = bounds.x + bounds.width * 0.5
    if !finite(center) { ret (zero, Invalid) }
    i = 0usize
    while i < left.len {
        let left_width = half * f32(f64(left[i]) / f64(maximum))
        let right_width = half * f32(f64(right[i]) / f64(maximum))
        let y = bounds.y + bounds.height - slot * f32(i + 1usize) + row_gap * 0.5
        if !finite(left_width) || !finite(right_width) || !finite(y) || !finite(center - gutter * 0.5 - left_width) { ret (zero, Invalid) }
        bars[i] = geometry.rect(center - gutter * 0.5 - left_width, y, left_width, slot - row_gap)
        bars[left.len + i] = geometry.rect(center + gutter * 0.5, y, right_width, slot - row_gap)
        i += 1usize
    }
    layers[0usize] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[..left.len], x_min: 0.0 - maximum, x_max: maximum, y_min: 0.0, y_max: f32(left.len) }
    layers[1usize] = Layout { kind: .Bar, coords: zero, segments: zero, bars: bars[left.len..left.len * 2usize], x_min: 0.0 - maximum, x_max: maximum, y_min: 0.0, y_max: f32(left.len) }
    ret (layers[..2usize], ok)
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

// Nested R7 letter-value ranges; depth is explicit and each tail must retain
// at least one observation. Points beyond the outer range are tail observations.
fn boxen_plot(sorted: []const f64, bounds: geometry.Rect, depth: usize, tails: []Coord, median_line: []Segment, boxes: []geometry.Rect) -> (Layout, err) {
    if sorted.len < 4usize { ret (zero, Empty) }
    if depth == 0usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    if boxes.len < depth || median_line.len < 1usize { ret (zero, TooLarge) }
    var i = 0usize
    while i < sorted.len {
        if !finite(f32(sorted[i])) || (i > 0usize && sorted[i] < sorted[i - 1usize]) { ret (zero, Invalid) }
        i += 1usize
    }
    var lo = sorted[0usize]
    var hi = sorted[sorted.len - 1usize]
    if lo == hi {
        lo -= 0.5f64
        hi += 0.5f64
    }
    let cx = bounds.x + bounds.width / 2.0
    var probability = 0.25f64
    var outer_low = lo
    var outer_high = hi
    i = 0usize
    while i < depth {
        if probability * f64(sorted.len) < 1.0f64 { ret (zero, Invalid) }
        let (low, low_ok) = stat.quantile(sorted, probability, .R7)
        let (high, high_ok) = stat.quantile(sorted, 1.0f64 - probability, .R7)
        if !low_ok || !high_ok { ret (zero, Invalid) }
        let width = bounds.width * 0.72 * f32(depth - i) / f32(depth)
        let top = box_y(high, lo, hi, bounds)
        boxes[i] = geometry.rect(cx - width / 2.0, top, width, box_y(low, lo, hi, bounds) - top)
        outer_low = low
        outer_high = high
        probability *= 0.5f64
        i += 1usize
    }
    let (middle, middle_ok) = stat.quantile(sorted, 0.5f64, .R7)
    if !middle_ok { ret (zero, Invalid) }
    let median_y = box_y(middle, lo, hi, bounds)
    median_line[0usize] = Segment { from: Coord { x: boxes[0usize].x, y: median_y }, to: Coord { x: boxes[0usize].x + boxes[0usize].width, y: median_y } }
    var used = 0usize
    i = 0usize
    while i < sorted.len {
        if sorted[i] < outer_low || sorted[i] > outer_high {
            if used >= tails.len { ret (zero, TooLarge) }
            tails[used] = Coord { x: cx, y: box_y(sorted[i], lo, hi, bounds) }
            used += 1usize
        }
        i += 1usize
    }
    ret (Layout { kind: .Box, coords: tails[..used], segments: median_line[..1usize], bars: boxes[..depth], x_min: 0.0, x_max: 1.0, y_min: f32(lo), y_max: f32(hi) }, ok)
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

// Groups are concatenated in `values` and drawn top-to-bottom on one KDE x
// domain. `overlap` is ridge height in row spacings; heights share one density
// scale, so unlike per-ridge normalization they retain cross-group magnitude.
fn ridgeline(values: []const f64, lengths: []const usize, bounds: geometry.Rect, bandwidth: f64, overlap: f32, grid: []f64, estimates: []f64, bandwidths: []f64, outline: []Coord, layers: []Layout) -> ([]Layout, err) {
    if values.len == 0usize || lengths.len == 0usize { ret (zero, Empty) }
    if !valid_bounds(bounds) || !finite(overlap) || overlap <= 0.0 || bandwidth < 0.0f64 || !finite64(bandwidth) { ret (zero, Invalid) }
    if grid.len < 2usize || estimates.len / grid.len < lengths.len || outline.len / (grid.len + 2usize) < lengths.len || bandwidths.len < lengths.len || layers.len < lengths.len { ret (zero, TooLarge) }
    var lo = values[0usize]
    var hi = lo
    var offset = 0usize
    var max_bandwidth = 0.0f64
    var group = 0usize
    while group < lengths.len {
        let count = lengths[group]
        if count == 0usize || count > values.len - offset { ret (zero, Invalid) }
        var i = offset
        while i < offset + count {
            if !finite(f32(values[i])) { ret (zero, Invalid) }
            if values[i] < lo { lo = values[i] }
            if values[i] > hi { hi = values[i] }
            i += 1usize
        }
        var bw = bandwidth
        if bw == 0.0f64 {
            let (chosen, defined) = stat.kde_bandwidth(values[offset..offset + count], .Scott)
            if !defined { ret (zero, Invalid) }
            bw = chosen
        }
        if !(bw > 0.0f64) || !finite(f32(bw)) { ret (zero, Invalid) }
        bandwidths[group] = bw
        if bw > max_bandwidth { max_bandwidth = bw }
        offset += count
        group += 1usize
    }
    if offset != values.len { ret (zero, Invalid) }
    lo -= 3.0f64 * max_bandwidth
    hi += 3.0f64 * max_bandwidth
    if !finite(f32(lo)) || !finite(f32(hi)) || !(hi > lo) { ret (zero, Invalid) }
    var i = 0usize
    while i < grid.len {
        grid[i] = lo + (hi - lo) * f64(i) / f64(grid.len - 1usize)
        i += 1usize
    }
    var peak = 0.0f64
    offset = 0usize
    group = 0usize
    while group < lengths.len {
        let first = group * grid.len
        let kde_error = stat.kde(values[offset..offset + lengths[group]], bandwidths[group], grid, estimates[first..first + grid.len])
        if kde_error != ok { ret (zero, kde_error) }
        i = first
        while i < first + grid.len {
            if estimates[i] > peak { peak = estimates[i] }
            i += 1usize
        }
        offset += lengths[group]
        group += 1usize
    }
    if !(peak > 0.0f64) || !finite(f32(peak)) { ret (zero, Invalid) }
    let spacing = bounds.height / (f32(lengths.len - 1usize) + overlap)
    let height = spacing * overlap
    if !finite(spacing) || !finite(height) || spacing <= 0.0 || height <= 0.0 { ret (zero, Invalid) }
    group = 0usize
    while group < lengths.len {
        let baseline = bounds.y + height + spacing * f32(group)
        if !finite(baseline) { ret (zero, Invalid) }
        let first = group * (grid.len + 2usize)
        outline[first] = Coord { x: bounds.x, y: baseline }
        i = 0usize
        while i < grid.len {
            let x = bounds.x + bounds.width * f32(i) / f32(grid.len - 1usize)
            let y = baseline - height * f32(estimates[group * grid.len + i] / peak)
            if !finite(x) || !finite(y) { ret (zero, Invalid) }
            outline[first + i + 1usize] = Coord { x: x, y: y }
            i += 1usize
        }
        outline[first + grid.len + 1usize] = Coord { x: bounds.x + bounds.width, y: baseline }
        layers[group] = Layout { kind: .Area, coords: outline[first..first + grid.len + 2usize], segments: zero, bars: zero, x_min: f32(lo), x_max: f32(hi), y_min: 0.0, y_max: f32(lengths.len) }
        group += 1usize
    }
    ret (layers[..lengths.len], ok)
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

// Compare the empirical plotting positions with a caller-specified normal CDF.
fn pp_normal(sorted: []const f64, mean: f64, deviation: f64, bounds: geometry.Rect, points: []Coord, reference: []Segment) -> (Layout, err) {
    if sorted.len < 2usize { ret (zero, Empty) }
    if points.len < sorted.len || reference.len < 1usize { ret (zero, TooLarge) }
    if !valid_bounds(bounds) || !finite64(mean) || !finite64(deviation) || deviation <= 0.0f64 { ret (zero, Invalid) }
    var i = 0usize
    while i < sorted.len {
        if !finite64(sorted[i]) || (i > 0usize && sorted[i] < sorted[i - 1usize]) { ret (zero, Invalid) }
        let z = (sorted[i] - mean) / deviation
        if !finite64(z) { ret (zero, Invalid) }
        let theoretical = special.normal_cdf(z)
        let empirical = (f64(i) + 0.5f64) / f64(sorted.len)
        points[i] = Coord {
            x: bounds.x + bounds.width * f32(theoretical),
            y: bounds.y + bounds.height * f32(1.0f64 - empirical),
        }
        i += 1usize
    }
    reference[0usize] = Segment {
        from: Coord { x: bounds.x, y: bounds.y + bounds.height },
        to: Coord { x: bounds.x + bounds.width, y: bounds.y },
    }
    ret (Layout { kind: .Pp, coords: points[..sorted.len], segments: reference[..1usize], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }, ok)
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

// Monday is row zero. Missing offsets emit no tile, preserving a visible gap.
fn calendar_heatmap(days: []const CalendarDay, day_count: usize, first_weekday: usize, bounds: geometry.Rect, gap: f32, cells: []Cell) -> (MatrixLayout, err) {
    if days.len == 0usize { ret (zero, Empty) }
    if day_count == 0usize || day_count > 366usize || first_weekday >= 7usize || !valid_bounds(bounds) || !finite(gap) || gap < 0.0 { ret (zero, Invalid) }
    if cells.len < days.len { ret (zero, TooLarge) }
    let columns = (first_weekday + day_count + 6usize) / 7usize
    var lo = days[0usize].value
    var hi = lo
    var i = 0usize
    while i < days.len {
        let d = days[i]
        if d.offset >= day_count || (i > 0usize && d.offset <= days[i - 1usize].offset) || !finite64(d.value) || !finite(f32(d.value)) { ret (zero, Invalid) }
        if d.value < lo { lo = d.value }
        if d.value > hi { hi = d.value }
        let slot = first_weekday + d.offset
        let tile = cell_rect(bounds, slot / 7usize, slot % 7usize, columns, 7usize)
        if tile.width <= gap || tile.height <= gap { ret (zero, Invalid) }
        cells[i] = Cell { rect: geometry.rect(tile.x + gap * 0.5, tile.y + gap * 0.5, tile.width - gap, tile.height - gap), value: f32(d.value) }
        i += 1usize
    }
    if !finite(f32(hi - lo)) { ret (zero, Invalid) }
    ret (MatrixLayout { kind: .Heatmap, cells: cells[..days.len], columns: columns, rows: 7usize, value_min: f32(lo), value_max: f32(hi) }, ok)
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

// Each row crosses one independently normalized vertical axis per column.
fn parallel_coordinates(observations: []const f64, columns: usize, bounds: geometry.Rect, minimums: []f64, maximums: []f64, lines: []Segment, axes: []Segment) -> (Layout, Layout, err) {
    if observations.len == 0usize { ret (zero, zero, Empty) }
    if columns < 2usize || observations.len % columns != 0usize || !valid_bounds(bounds) { ret (zero, zero, Invalid) }
    let rows = observations.len / columns
    if minimums.len < columns || maximums.len < columns || axes.len < columns || lines.len / (columns - 1usize) < rows { ret (zero, zero, TooLarge) }
    var i = 0usize
    while i < observations.len {
        if !finite64(observations[i]) { ret (zero, zero, Invalid) }
        i += 1usize
    }
    var column = 0usize
    while column < columns {
        minimums[column] = observations[column]
        maximums[column] = observations[column]
        i = 1usize
        while i < rows {
            let value = observations[i * columns + column]
            if value < minimums[column] { minimums[column] = value }
            if value > maximums[column] { maximums[column] = value }
            i += 1usize
        }
        if !finite64(maximums[column] - minimums[column]) { ret (zero, zero, Invalid) }
        let x = bounds.x + bounds.width * f32(column) / f32(columns - 1usize)
        axes[column] = Segment { from: Coord { x: x, y: bounds.y }, to: Coord { x: x, y: bounds.y + bounds.height } }
        column += 1usize
    }
    var row = 0usize
    while row < rows {
        column = 0usize
        while column + 1usize < columns {
            var first = 0.5f64
            var second = 0.5f64
            if maximums[column] > minimums[column] { first = (observations[row * columns + column] - minimums[column]) / (maximums[column] - minimums[column]) }
            if maximums[column + 1usize] > minimums[column + 1usize] { second = (observations[row * columns + column + 1usize] - minimums[column + 1usize]) / (maximums[column + 1usize] - minimums[column + 1usize]) }
            if !finite64(first) || !finite64(second) { ret (zero, zero, Invalid) }
            let left = bounds.x + bounds.width * f32(column) / f32(columns - 1usize)
            let right = bounds.x + bounds.width * f32(column + 1usize) / f32(columns - 1usize)
            lines[row * (columns - 1usize) + column] = Segment {
                from: Coord { x: left, y: bounds.y + bounds.height * (1.0 - f32(first)) },
                to: Coord { x: right, y: bounds.y + bounds.height * (1.0 - f32(second)) },
            }
            column += 1usize
        }
        row += 1usize
    }
    let data = Layout { kind: .Rug, coords: zero, segments: lines[..rows * (columns - 1usize)], bars: zero, x_min: 0.0, x_max: f32(columns - 1usize), y_min: 0.0, y_max: 1.0 }
    let guides = Layout { kind: .Rug, coords: zero, segments: axes[..columns], bars: zero, x_min: 0.0, x_max: f32(columns - 1usize), y_min: 0.0, y_max: 1.0 }
    ret (data, guides, ok)
}

// Off-diagonal cells plot every variable pair; callers label the blank diagonal.
// Inputs are row-major and each variable keeps one range across its panels.
fn scatterplot_matrix(observations: []const f64, columns: usize, bounds: geometry.Rect, gap: f32, minimums: []f64, maximums: []f64, panels: []geometry.Rect, points: []Coord, layers: []Layout) -> ([]Layout, err) {
    if observations.len == 0usize { ret (zero, Empty) }
    if columns < 2usize || observations.len % columns != 0usize || !valid_bounds(bounds) { ret (zero, Invalid) }
    let rows = observations.len / columns
    if minimums.len < columns || maximums.len < columns || panels.len / columns < columns || layers.len / columns < columns { ret (zero, TooLarge) }
    let count = columns * columns
    if points.len / (count - columns) < rows { ret (zero, TooLarge) }
    let (_, panel_error) = facet_grid(bounds, columns, count, gap, panels)
    if panel_error != ok { ret (zero, panel_error) }
    var column = 0usize
    while column < columns {
        minimums[column] = observations[column]
        maximums[column] = observations[column]
        var row = 0usize
        while row < rows {
            let value = observations[row * columns + column]
            if !finite64(value) || !finite(f32(value)) { ret (zero, Invalid) }
            if value < minimums[column] { minimums[column] = value }
            if value > maximums[column] { maximums[column] = value }
            row += 1usize
        }
        if !finite64(maximums[column] - minimums[column]) { ret (zero, Invalid) }
        column += 1usize
    }
    var used = 0usize
    var panel = 0usize
    while panel < count {
        let x_column = panel % columns
        let y_column = panel / columns
        let first = used
        if x_column != y_column {
            var row = 0usize
            while row < rows {
                var x = 0.5f64
                var y = 0.5f64
                if maximums[x_column] > minimums[x_column] { x = (observations[row * columns + x_column] - minimums[x_column]) / (maximums[x_column] - minimums[x_column]) }
                if maximums[y_column] > minimums[y_column] { y = (observations[row * columns + y_column] - minimums[y_column]) / (maximums[y_column] - minimums[y_column]) }
                if !finite64(x) || !finite64(y) { ret (zero, Invalid) }
                points[used] = Coord {
                    x: panels[panel].x + panels[panel].width * f32(x),
                    y: panels[panel].y + panels[panel].height * f32(1.0f64 - y),
                }
                used += 1usize
                row += 1usize
            }
        }
        layers[panel] = Layout { kind: .Scatter, coords: points[first..used], segments: zero, bars: zero, x_min: f32(minimums[x_column]), x_max: f32(maximums[x_column]), y_min: f32(minimums[y_column]), y_max: f32(maximums[y_column]) }
        panel += 1usize
    }
    ret (layers[..count], ok)
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
