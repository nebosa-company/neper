// Declarative chart geometry. The first slice keeps data borrowed and emits
// renderer-neutral marks; scene, PNG and widget adapters can consume Layout.
//
// The contract is intentionally small: one numeric x/y mapping, one Cartesian
// bounds rectangle, and caller-owned output. More chart families compose on it.

use e.algo.stat
use e.gfx.geometry
use e.math.special

type Kind = enum u8 { Scatter, Line, Bar, Histogram, Step, Ecdf, Box, Density, Qq, Violin }
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
    if s.kind == .Histogram || s.kind == .Ecdf || s.kind == .Box || s.kind == .Density || s.kind == .Qq || s.kind == .Violin { ret (zero, Invalid) }
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
    if s.kind == .Bar && s.x.len > 1usize {
        let pad = f32((f64(x1) - f64(x0)) / f64(s.x.len - 1usize) / 2.0f64)
        let left = x0 - pad
        let right = x1 + pad
        if finite(left) && finite(right) {
            xmin = left
            xmax = right
        }
    }
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
    } else if s.kind == .Step {
        if s.x.len > 1usize && segments.len / 2usize < s.x.len - 1usize { ret (zero, TooLarge) }
        var i = 0usize
        while i + 1usize < s.x.len {
            if s.x[i + 1usize] < s.x[i] { ret (zero, Invalid) }
            let left = Coord {
                x: mapped(s.x[i], xmin, xmax, s.bounds.x, s.bounds.width),
                y: s.bounds.y + s.bounds.height - mapped(s.y[i], y0, y1, 0.0, s.bounds.height),
            }
            let right = Coord {
                x: mapped(s.x[i + 1usize], xmin, xmax, s.bounds.x, s.bounds.width),
                y: left.y,
            }
            let next = Coord {
                x: right.x,
                y: s.bounds.y + s.bounds.height - mapped(s.y[i + 1usize], y0, y1, 0.0, s.bounds.height),
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
