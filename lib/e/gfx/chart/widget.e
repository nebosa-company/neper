// A chart inside an e.ui widget tree: `custom` gives a canvas (`control.canvas`
// or `control.framed_canvas`, D962) a measure and a paint that lay the chart
// out against whatever rectangle the canvas received, so the chart follows
// window and layout changes without the caller recomputing geometry. The View
// must outlive the widget tree that refers to it. Bump `revision` whenever its
// data or look changes: the runtime replays an unchanged custom's last paint
// (D917) and repaints only when those bytes differ.
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.ui.layout as ui_layout
use e.ui.widget

// `marks` and `plot` hold the most recent paint, for hit testing a pointer
// against what is on screen (`chart.hit_scatter`).
// ponytail: one layer per view; several layers or a legend need a list of
// specs and brushes when a dashboard wants them.
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
}

// A view at the Canvas spec's chart defaults: 240 by 160 preferred, 16 of
// padding for the axes, outline-grey guides. The caller owns the mark storage,
// sized for its data as `chart.layout` needs, and the arena the scene adapter
// copies paths into.
fn view(a: *mem.Arena, spec: chart.Spec, brush: paint.Brush, coords: []chart.Coord, segments: []chart.Segment, bars: []geometry.Rect) -> View {
    let guide = paint.Brush { Solid: paint.rgba(0.80, 0.84, 0.89, 1.0) }
    ret View { arena: a, spec: spec, brush: brush, grid: guide, axis: guide, x_ticks: zero, y_ticks: zero, padding: 16.0, width: 240.0, height: 160.0, coords: coords, segments: segments, bars: bars, revision: 0u64, marks: zero, plot: zero }
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
    let (marks, layout_error) = chart.layout(&spec, v.coords, v.segments, v.bars)
    if layout_error != ok { ret layout_error }
    if v.x_ticks.len > 0usize || v.y_ticks.len > 0usize { try chart_scene.append_guides(builder, plot, v.x_ticks, v.y_ticks, v.grid, v.axis) }
    try chart_scene.append(v.arena, builder, &marks, v.brush)
    v.marks = marks
    v.plot = plot
    ret ok
}

fn custom(v: *View) -> widget.Custom {
    ret widget.Custom { ctx: mem.cast[*void](v), measure: measure_view, paint: paint_view, state: widget.bytes_of[u64](&v.revision) }
}
