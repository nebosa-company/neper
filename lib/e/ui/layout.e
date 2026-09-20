// A pure constraint solver: constraints go down, sizes come up, then the parent
// places its children. Every number in and out is finite and non-negative; a
// contradictory limit (a minimum above its maximum, a negative gap or child) is
// `Invalid`, and content that cannot fit a bounded limit even after shrinking is
// `Overflow`. An unbounded maximum is written as infinity (`mem.bitcast[f32]` of
// the IEEE pattern); flex factors and flexible tracks only ever share space a
// finite maximum bounds, so under an unbounded one they keep their desired size
// and the container grows to its content or its minimum.
//
// Flex: children sit along `axis` with `gap` between them. When the sum of
// desired sizes and gaps is under the bound, the shortfall goes to children in
// proportion to `flex` (none flexible: the container shrinks to content and
// `main` distributes the leftover); over the bound, every child shrinks in
// proportion to its desired size. Cross sizes are the desired one, or the
// container's under `Stretch`; `Baseline` places like `Start`, since a child
// carries no baseline here. Grid: cells are assigned in row-major order; a
// `Px` track is fixed, an `Auto` track is its widest child, a `Flex` track
// shares what a bounded limit leaves after the others and the gaps; every child
// fills its cell. More children than cells is `Overflow`.

use e.mem
use e.gfx.geometry

type Axis = enum u8 { Horizontal, Vertical }
type MainAlign = enum u8 { Start, End, Center, SpaceBetween, SpaceAround, SpaceEvenly }
type CrossAlign = enum u8 { Start, End, Center, Stretch, Baseline }
type Constraints = struct { min_width: f32, max_width: f32, min_height: f32, max_height: f32 }
type Flex = struct { axis: Axis, main: MainAlign, cross: CrossAlign, gap: f32 }
type GridTrack = union enum u8 { Px: f32, Flex: f32, Auto }
type Grid = struct { columns: []const GridTrack, rows: []const GridTrack, column_gap: f32, row_gap: f32 }
type Child = struct { desired: geometry.Size, flex: f32 }
type Result = struct { size: geometry.Size, children: []const geometry.Rect }
error Invalid
error Overflow

fn is_nan(v: f32) -> bool {
    ret v != v
}

fn bounded(v: f32) -> bool {
    ret v - v == 0.0
}

fn limits_ok(limits: Constraints) -> bool {
    if is_nan(limits.min_width) || is_nan(limits.max_width) || is_nan(limits.min_height) || is_nan(limits.max_height) { ret false }
    if !bounded(limits.min_width) || !bounded(limits.min_height) { ret false }
    if limits.min_width < 0.0 || limits.min_height < 0.0 { ret false }
    ret limits.max_width >= limits.min_width && limits.max_height >= limits.min_height
}

fn children_ok(children: []const Child) -> bool {
    var i = 0usize
    while i < children.len {
        let c = children[i]
        if !bounded(c.desired.width) || !bounded(c.desired.height) || !bounded(c.flex) { ret false }
        if c.desired.width < 0.0 || c.desired.height < 0.0 || c.flex < 0.0 { ret false }
        i += 1usize
    }
    ret true
}

fn clamp(v: f32, low: f32, high: f32) -> f32 {
    if v < low { ret low }
    if v > high { ret high }
    ret v
}

fn constrain(value: geometry.Size, limits: Constraints) -> geometry.Size {
    ret geometry.Size { width: clamp(value.width, limits.min_width, limits.max_width), height: clamp(value.height, limits.min_height, limits.max_height) }
}

fn flex(a: *mem.Arena, spec: Flex, limits: Constraints, children: []const Child) -> (Result, err) {
    if !limits_ok(limits) || !bounded(spec.gap) || spec.gap < 0.0 || !children_ok(children) { ret (zero, Invalid) }
    let horizontal = spec.axis == .Horizontal
    var main_min = limits.min_height
    var main_max = limits.max_height
    var cross_min = limits.min_width
    var cross_max = limits.max_width
    if horizontal {
        main_min = limits.min_width
        main_max = limits.max_width
        cross_min = limits.min_height
        cross_max = limits.max_height
    }
    let n = children.len
    let (rects, rects_error) = mem.alloc[geometry.Rect](a, n)
    if rects_error != ok { ret (zero, rects_error) }
    let (sizes, sizes_error) = mem.alloc[f32](a, n)
    if sizes_error != ok { ret (zero, sizes_error) }
    if n == 0usize {
        let empty = constrain(geometry.Size { width: 0.0, height: 0.0 }, limits)
        ret (Result { size: empty, children: rects }, ok)
    }
    var gaps: f32 = 0.0
    if n > 1usize { gaps = spec.gap * f32(n - 1usize) }
    var desired: f32 = 0.0
    var total_flex: f32 = 0.0
    var cross_desired: f32 = 0.0
    var i = 0usize
    while i < n {
        var m = children[i].desired.height
        var c = children[i].desired.width
        if horizontal {
            m = children[i].desired.width
            c = children[i].desired.height
        }
        sizes[i] = m
        desired += m
        total_flex += children[i].flex
        if c > cross_desired { cross_desired = c }
        i += 1usize
    }
    // The bound flexible children may grow to: the maximum, or the minimum under
    // an unbounded one; over it, everything shrinks in proportion.
    var bound = main_min
    if bounded(main_max) { bound = main_max }
    var used = desired + gaps
    if used > bound && bounded(main_max) {
        if gaps > bound { ret (zero, Overflow) }
        let room = bound - gaps
        i = 0usize
        while i < n {
            if desired > 0.0 { sizes[i] = sizes[i] * room / desired }
            i += 1usize
        }
        used = bound
    } else if used < bound && total_flex > 0.0 {
        let free = bound - used
        i = 0usize
        while i < n {
            sizes[i] += free * children[i].flex / total_flex
            i += 1usize
        }
        used = bound
    }
    var main_size = used
    if main_size < main_min { main_size = main_min }
    if bounded(main_max) && main_size > main_max { main_size = main_max }
    let cross_size = clamp(cross_desired, cross_min, cross_max)
    // Leftover along the main axis, placed by `main`.
    let leftover = main_size - used
    var pen: f32 = 0.0
    var between = spec.gap
    if leftover > 0.0 {
        if spec.main == .End {
            pen = leftover
        } else if spec.main == .Center {
            pen = leftover / 2.0
        } else if spec.main == .SpaceBetween && n > 1usize {
            between += leftover / f32(n - 1usize)
        } else if spec.main == .SpaceAround {
            pen = leftover / f32(n) / 2.0
            between += leftover / f32(n)
        } else if spec.main == .SpaceEvenly {
            pen = leftover / f32(n + 1usize)
            between += leftover / f32(n + 1usize)
        }
    }
    i = 0usize
    while i < n {
        var c = children[i].desired.width
        if horizontal { c = children[i].desired.height }
        if spec.cross == .Stretch { c = cross_size }
        if c > cross_size { c = cross_size }
        var offset: f32 = 0.0
        if spec.cross == .End { offset = cross_size - c } else if spec.cross == .Center { offset = (cross_size - c) / 2.0 }
        if horizontal {
            rects[i] = geometry.rect(pen, offset, sizes[i], c)
        } else {
            rects[i] = geometry.rect(offset, pen, c, sizes[i])
        }
        pen += sizes[i] + between
        i += 1usize
    }
    var size = geometry.Size { width: cross_size, height: main_size }
    if horizontal { size = geometry.Size { width: main_size, height: cross_size } }
    ret (Result { size: size, children: rects }, ok)
}

fn track_ok(t: GridTrack) -> bool {
    switch t {
    case .Px as v:
        ret bounded(v) && v >= 0.0
    case .Flex as v:
        ret bounded(v) && v >= 0.0
    case .Auto:
        ret true
    }
    ret false
}

// Resolves one axis of tracks: fixed, then the widest child of each auto track,
// then the flexible ones over what a bounded limit leaves.
fn resolve_tracks(tracks: []const GridTrack, sizes: []f32, gap: f32, min: f32, max: f32, children: []const Child, columns: usize, by_column: bool) -> err {
    var fixed: f32 = 0.0
    var total_flex: f32 = 0.0
    var t = 0usize
    while t < tracks.len {
        if !track_ok(tracks[t]) { ret Invalid }
        sizes[t] = 0.0
        switch tracks[t] {
        case .Px as v:
            sizes[t] = v
        case .Flex as v:
            total_flex += v
        case .Auto:
            var widest: f32 = 0.0
            var i = 0usize
            while i < children.len {
                var index = i / columns
                var extent = children[i].desired.height
                if by_column {
                    index = i % columns
                    extent = children[i].desired.width
                }
                if index == t && extent > widest { widest = extent }
                i += 1usize
            }
            sizes[t] = widest
        }
        fixed += sizes[t]
        t += 1usize
    }
    var gaps: f32 = 0.0
    if tracks.len > 1usize { gaps = gap * f32(tracks.len - 1usize) }
    var bound = min
    if bounded(max) { bound = max }
    var free = bound - fixed - gaps
    if free < 0.0 { free = 0.0 }
    t = 0usize
    while t < tracks.len {
        switch tracks[t] {
        case .Flex as v:
            // ponytail: a flexible track under an unbounded limit and no minimum is
            // zero; sizing it to its content is the upgrade.
            if total_flex > 0.0 { sizes[t] = free * v / total_flex }
        case .Px as v:
            sizes[t] = v
        case .Auto:
            sizes[t] = sizes[t]
        }
        t += 1usize
    }
    ret ok
}

fn grid(a: *mem.Arena, spec: Grid, limits: Constraints, children: []const Child) -> (Result, err) {
    if !limits_ok(limits) || !children_ok(children) { ret (zero, Invalid) }
    if !bounded(spec.column_gap) || !bounded(spec.row_gap) || spec.column_gap < 0.0 || spec.row_gap < 0.0 { ret (zero, Invalid) }
    if spec.columns.len == 0usize || spec.rows.len == 0usize { ret (zero, Invalid) }
    if children.len > spec.columns.len * spec.rows.len { ret (zero, Overflow) }
    let (widths, widths_error) = mem.alloc[f32](a, spec.columns.len)
    if widths_error != ok { ret (zero, widths_error) }
    let (heights, heights_error) = mem.alloc[f32](a, spec.rows.len)
    if heights_error != ok { ret (zero, heights_error) }
    let columns_error = resolve_tracks(spec.columns, widths, spec.column_gap, limits.min_width, limits.max_width, children, spec.columns.len, true)
    if columns_error != ok { ret (zero, columns_error) }
    let rows_error = resolve_tracks(spec.rows, heights, spec.row_gap, limits.min_height, limits.max_height, children, spec.columns.len, false)
    if rows_error != ok { ret (zero, rows_error) }
    var width: f32 = 0.0
    var t = 0usize
    while t < widths.len {
        width += widths[t]
        if t + 1usize < widths.len { width += spec.column_gap }
        t += 1usize
    }
    var height: f32 = 0.0
    t = 0usize
    while t < heights.len {
        height += heights[t]
        if t + 1usize < heights.len { height += spec.row_gap }
        t += 1usize
    }
    if width > limits.max_width || height > limits.max_height { ret (zero, Overflow) }
    if width < limits.min_width { width = limits.min_width }
    if height < limits.min_height { height = limits.min_height }
    let (rects, rects_error) = mem.alloc[geometry.Rect](a, children.len)
    if rects_error != ok { ret (zero, rects_error) }
    var i = 0usize
    while i < children.len {
        let column = i % spec.columns.len
        let row = i / spec.columns.len
        var x: f32 = 0.0
        var c = 0usize
        while c < column {
            x += widths[c] + spec.column_gap
            c += 1usize
        }
        var y: f32 = 0.0
        var r = 0usize
        while r < row {
            y += heights[r] + spec.row_gap
            r += 1usize
        }
        rects[i] = geometry.rect(x, y, widths[column], heights[row])
        i += 1usize
    }
    ret (Result { size: geometry.Size { width: width, height: height }, children: rects }, ok)
}
