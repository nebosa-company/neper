// A chart inside an e.ui widget tree: `custom` gives a canvas (`control.canvas`
// or `control.framed_canvas`, D962) a measure and a paint that lay the chart
// out against whatever rectangle the canvas received, so the chart follows
// window and layout changes without the caller recomputing geometry. The View
// must outlive the widget tree that refers to it. Bump `revision` whenever its
// data or look changes: the runtime replays an unchanged custom's last paint
// (D917) and repaints only when those bytes differ.
//
// Wrapped in a `region(&view)`, the chart takes the pointer (D2114): the wheel
// zooms about the pointer, a drag pans, a double tap shows everything again, and
// hovering a point outlines it in `highlight` and names it in `hovered`.
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.ui.layout as ui_layout
use e.ui.widget

// `marks` and `plot` hold the most recent paint, for hit testing a pointer
// against what is on screen (`chart.hit_scatter`). `window` is the part of the
// whole plot on screen, as fractions of it from the top left, (0, 0, 1, 1) for
// all of it, and no side smaller than `min_window` (in (0, 1]). The marks are laid
// out over all the data and mapped through the window, so a zoom changes no
// scale: the caller's ticks move with the marks and those leaving the plot are
// not drawn.
// ponytail: one layer per view; several layers or a legend need a list of
// specs and brushes when a dashboard wants them. Zoom is on both axes and there
// are no keyboard equivalents yet.
type View = struct {
    arena: *mem.Arena,
    spec: chart.Spec,
    brush: paint.Brush,
    grid: paint.Brush,
    axis: paint.Brush,
    x_ticks: []const chart.Tick,
    y_ticks: []const chart.Tick,
    padding: f32,
    width: f32,
    height: f32,
    coords: []chart.Coord,
    segments: []chart.Segment,
    bars: []geometry.Rect,
    revision: u64,
    marks: chart.Layout,
    plot: geometry.Rect,
    window: geometry.Rect,
    min_window: f32,
    hover_radius: f32,
    hovered: usize,
    has_hovered: bool,
    highlight: paint.Brush,
    outline: [1]geometry.Rect,
    shown: []chart.Tick,
    pan_from: geometry.Rect,
}

// A view at the Canvas spec's chart defaults: 240 by 160 preferred, 16 of
// padding for the axes, outline-grey guides, all of the plot shown, zoom up to
// 64 times, points hovered within 8 and outlined in orange. The caller owns the
// mark storage, sized for its data as `chart.layout` needs, and the arena the
// scene adapter copies paths into.
fn view(a: *mem.Arena, spec: chart.Spec, brush: paint.Brush, coords: []chart.Coord, segments: []chart.Segment, bars: []geometry.Rect) -> View {
    let guide = paint.Brush { Solid: paint.rgba(0.80, 0.84, 0.89, 1.0) }
    let orange = paint.Brush { Solid: paint.rgba(0.89, 0.30, 0.13, 1.0) }
    ret View { arena: a, spec: spec, brush: brush, grid: guide, axis: guide, x_ticks: zero, y_ticks: zero, padding: 16.0, width: 240.0, height: 160.0, coords: coords, segments: segments, bars: bars, revision: 0u64, marks: zero, plot: zero, window: geometry.rect(0.0, 0.0, 1.0, 1.0), min_window: 1.0 / 64.0, hover_radius: 8.0, hovered: 0usize, has_hovered: false, highlight: orange, outline: zero, shown: zero, pan_from: zero }
}

fn clamp(value: f32, low: f32, high: f32) -> f32 {
    var v = value
    if v > high { v = high }
    if v < low { v = low }
    ret v
}

fn measure_view(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    let v = mem.cast[*View](ctx)
    ret geometry.Size { width: clamp(v.width, limits.min_width, limits.max_width), height: clamp(v.height, limits.min_height, limits.max_height) }
}

fn whole(w: geometry.Rect) -> bool {
    ret w.x == 0.0 && w.y == 0.0 && w.width == 1.0 && w.height == 1.0
}

fn through(c: chart.Coord, plot: geometry.Rect, w: geometry.Rect) -> chart.Coord {
    ret chart.Coord { x: plot.x + (c.x - plot.x - w.x * plot.width) / w.width, y: plot.y + (c.y - plot.y - w.y * plot.height) / w.height }
}

// The marks of the whole plot moved through the window, in place.
fn map_marks(marks: *chart.Layout, plot: geometry.Rect, w: geometry.Rect) {
    var i = 0usize
    while i < marks.coords.len {
        marks.coords[i] = through(marks.coords[i], plot, w)
        i += 1usize
    }
    i = 0usize
    while i < marks.segments.len {
        marks.segments[i] = chart.Segment { from: through(marks.segments[i].from, plot, w), to: through(marks.segments[i].to, plot, w) }
        i += 1usize
    }
    i = 0usize
    while i < marks.bars.len {
        let r = marks.bars[i]
        let corner = through(chart.Coord { x: r.x, y: r.y }, plot, w)
        marks.bars[i] = geometry.rect(corner.x, corner.y, r.width / w.width, r.height / w.height)
        i += 1usize
    }
}

// The ticks still on the plot through the window's `low` and `span` on their
// axis, into `out`. A y tick's fraction runs up from the bottom, the window's down.
fn shown_ticks(ticks: []const chart.Tick, low: f32, span: f32, upward: bool, out: []chart.Tick) -> []chart.Tick {
    var n = 0usize
    var i = 0usize
    while i < ticks.len {
        var f = ticks[i].fraction
        if upward { f = 1.0 - f }
        f = (f - low) / span
        if upward { f = 1.0 - f }
        if f >= 0.0 && f <= 1.0 {
            out[n] = chart.Tick { value: ticks[i].value, fraction: f }
            n += 1usize
        }
        i += 1usize
    }
    ret out[..n]
}

// A canvas smaller than its padding paints nothing rather than inverted marks.
fn paint_view(ctx: *void, builder: *scene.Builder, area: geometry.Rect) -> err {
    let v = mem.cast[*View](ctx)
    let plot = geometry.rect(area.x + v.padding, area.y + v.padding, area.width - 2.0 * v.padding, area.height - 2.0 * v.padding)
    if !(plot.width > 0.0) || !(plot.height > 0.0) {
        let no_marks: chart.Layout = zero
        let no_plot: geometry.Rect = zero
        v.marks = no_marks
        v.plot = no_plot
        ret ok
    }
    var spec = v.spec
    spec.bounds = plot
    let (laid, layout_error) = chart.layout(&spec, v.coords, v.segments, v.bars)
    if layout_error != ok { ret layout_error }
    var marks = laid
    let zoomed = !whole(v.window)
    var x_ticks = v.x_ticks
    var y_ticks = v.y_ticks
    if zoomed {
        map_marks(&marks, plot, v.window)
        let need = v.x_ticks.len + v.y_ticks.len
        if v.shown.len < need {
            let (room, room_error) = mem.alloc[chart.Tick](v.arena, need)
            if room_error != ok { ret room_error }
            v.shown = room
        }
        x_ticks = shown_ticks(v.x_ticks, v.window.x, v.window.width, false, v.shown[..v.x_ticks.len])
        y_ticks = shown_ticks(v.y_ticks, v.window.y, v.window.height, true, v.shown[v.x_ticks.len..need])
    }
    if v.x_ticks.len > 0usize || v.y_ticks.len > 0usize { try chart_scene.append_guides(builder, plot, x_ticks, y_ticks, v.grid, v.axis) }
    if zoomed { try chart_scene.begin_clip(builder, plot) }
    try chart_scene.append(v.arena, builder, &marks, v.brush)
    if v.has_hovered && v.hovered < marks.coords.len {
        var points = marks
        points.kind = .Scatter
        let (outline, outline_error) = chart.selected_point_outline(&points, v.hovered, 2.0, v.outline[..])
        if outline_error != ok { ret outline_error }
        try chart_scene.append(v.arena, builder, &outline, v.highlight)
    }
    if zoomed { try chart_scene.end_clip(builder) }
    v.marks = marks
    v.plot = plot
    ret ok
}

fn custom(v: *View) -> widget.Custom {
    ret widget.Custom { ctx: mem.cast[*void](v), measure: measure_view, paint: paint_view, state: widget.bytes_of[u64](&v.revision) }
}

// The window kept on the plot and no side under `min_window`; a change repaints.
fn set_window(v: *View, w: geometry.Rect) {
    let width = clamp(w.width, v.min_window, 1.0)
    let height = clamp(w.height, v.min_window, 1.0)
    let next = geometry.rect(clamp(w.x, 0.0, 1.0 - width), clamp(w.y, 0.0, 1.0 - height), width, height)
    if next.x == v.window.x && next.y == v.window.y && next.width == v.window.width && next.height == v.window.height { ret }
    v.window = next
    v.revision += 1u64
}

// The window scaled by `factor` (above 1 zooms in) keeping the point under the
// pointer where it is.
fn zoom_about(v: *View, p: geometry.Point, factor: f32) {
    let u = clamp((p.x - v.plot.x) / v.plot.width, 0.0, 1.0)
    let t = clamp((p.y - v.plot.y) / v.plot.height, 0.0, 1.0)
    let w = v.window
    let width = clamp(w.width / factor, v.min_window, 1.0)
    let height = clamp(w.height / factor, v.min_window, 1.0)
    set_window(v, geometry.rect(w.x + u * (w.width - width), w.y + t * (w.height - height), width, height))
}

// The nearest painted point within `hover_radius` that is on the plot, if any.
fn hover_at(v: *View, p: geometry.Point) -> err {
    var found = false
    var index = 0usize
    if v.marks.coords.len > 0usize && geometry.contains(v.plot, p) {
        var points = v.marks
        points.kind = .Scatter
        let (hit, has_hit, hit_error) = chart.hit_scatter(&points, zero, chart.Coord { x: p.x, y: p.y }, v.hover_radius)
        if hit_error != ok { ret hit_error }
        if has_hit {
            let c = points.coords[hit.mark_index]
            found = geometry.contains(v.plot, geometry.Point { x: c.x, y: c.y })
            index = hit.mark_index
        }
    }
    if found != v.has_hovered || (found && index != v.hovered) {
        v.has_hovered = found
        v.hovered = index
        v.revision += 1u64
    }
    ret ok
}

fn gesture_view(ctx: *void, g: widget.Gesture) -> err {
    let v = mem.cast[*View](ctx)
    if !(v.plot.width > 0.0) || !(v.plot.height > 0.0) { ret ok }
    switch g {
    case .Wheel as w:
        // A notch away zooms in by a tenth, as the zoom view does (D844).
        if w.notches > 0.0 { zoom_about(v, w.position, 1.1) }
        if w.notches < 0.0 { zoom_about(v, w.position, 1.0 / 1.1) }
    case .DragStart as p:
        v.pan_from = v.window
    case .DragMove as d:
        // From the press, not the last move: the content follows the pointer.
        let f = v.pan_from
        set_window(v, geometry.rect(f.x - (d.position.x - d.start.x) / v.plot.width * f.width, f.y - (d.position.y - d.start.y) / v.plot.height * f.height, f.width, f.height))
    case .DoubleTap as p:
        set_window(v, geometry.rect(0.0, 0.0, 1.0, 1.0))
    case .Hover as p:
        ret hover_at(v, p)
    case .HoverEnd:
        if v.has_hovered {
            v.has_hovered = false
            v.revision += 1u64
        }
    default:
        ret ok
    }
    ret ok
}

// The region that gives the chart the pointer: tap (for the double tap), drag,
// hover and wheel. Wrap the canvas in it: `widget.region(key, region(&v), style, canvas)`.
fn region(v: *View) -> widget.Region {
    ret widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](v), invoke: gesture_view }, gestures: widget.GESTURE_TAP | widget.GESTURE_DRAG | widget.GESTURE_HOVER | widget.GESTURE_WHEEL, enabled: true, focusable: false }
}

// A 3-D chart's camera, turned by dragging over the canvas wrapped in
// `orbit_region` (D2116): the scene follows the pointer at `degrees_per_pixel`
// from where the press found it, the elevation stays within `low`..`high`, and a
// double tap returns to `home`. The caller's custom lays the chart out with
// `camera` and takes `revision` as its state.
type Orbit = struct { camera: chart.Camera3d, home: chart.Camera3d, from: chart.Camera3d, revision: u64, low: f64, high: f64, degrees_per_pixel: f64 }

// Half a degree a pixel, elevation 5..85 so surfaces stay drawable.
fn orbit(camera: chart.Camera3d) -> Orbit {
    ret Orbit { camera: camera, home: camera, from: camera, revision: 0u64, low: 5.0f64, high: 85.0f64, degrees_per_pixel: 0.5f64 }
}

fn set_camera(o: *Orbit, camera: chart.Camera3d) {
    if camera.azimuth_degrees == o.camera.azimuth_degrees && camera.elevation_degrees == o.camera.elevation_degrees && camera.distance == o.camera.distance { ret }
    o.camera = camera
    o.revision += 1u64
}

fn gesture_orbit(ctx: *void, g: widget.Gesture) -> err {
    let o = mem.cast[*Orbit](ctx)
    switch g {
    case .DragStart as p:
        o.from = o.camera
    case .DragMove as d:
        // Right turns the front of the scene right, down tips its top toward the viewer.
        let dx = f64(d.position.x - d.start.x) * o.degrees_per_pixel
        let dy = f64(d.position.y - d.start.y) * o.degrees_per_pixel
        let (turned, orbit_error) = chart.orbit(o.from, 0.0f64 - dx, dy, o.low, o.high)
        if orbit_error != ok { ret orbit_error }
        set_camera(o, turned)
    case .DoubleTap as p:
        set_camera(o, o.home)
    default:
        ret ok
    }
    ret ok
}

fn orbit_region(o: *Orbit) -> widget.Region {
    ret widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](o), invoke: gesture_orbit }, gestures: widget.GESTURE_TAP | widget.GESTURE_DRAG, enabled: true, focusable: false }
}
