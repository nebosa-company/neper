// Streaming SVG adapter for the renderer-neutral chart layouts.
use e.bytes
use e.fmt.xml
use e.gfx.chart
use e.gfx.geometry
use e.gfx.paint
use e.io
use e.math
use e.mem
use e.str
use e.text.layout as text_layout

error Invalid

// A fill or stroke: a solid colour, or a gradient that `gradient` defined
// earlier in the document under this id.
type Ink = union enum u8 { Solid: paint.Color, Url: str }

// Numbers to 0.01 px (D2111): a hundredth of a pixel is below what any display
// shows, and full f32 digits made coordinates like 81.85714721679688 most of
// the file. Negative zero is written as 0.
// ponytail: fixed precision because the writer keeps no per-document state; a
// precision argument belongs here if anyone zooms an SVG past 100x.
fn number(w: *io.Writer, value: f32) -> err {
    if !chart.finite(value) { ret Invalid }
    var rounded = math.round[f64](f64(value) * 100.0f64) / 100.0f64
    if rounded == 0.0f64 { rounded = 0.0f64 }
    var scratch: [64]u8 = zero
    var arena = mem.arena_from(scratch[..])
    let (made, builder_error) = str.builder(&arena, 40usize)
    if builder_error != ok { ret builder_error }
    var built = made
    try str.push_f64(&built, rounded)
    ret io.write_all(w, str.done(&built))
}

fn unsigned(w: *io.Writer, value: usize) -> err {
    var scratch: [64]u8 = zero
    var arena = mem.arena_from(scratch[..])
    let (made, builder_error) = str.builder(&arena, 32usize)
    if builder_error != ok { ret builder_error }
    var built = made
    try str.push_usize(&built, value)
    ret io.write_all(w, str.done(&built))
}

fn text_ok(value: str) -> bool {
    var i = 0usize
    while i < value.len {
        let c = value[i]
        if c < 32u8 && c != 9u8 && c != 10u8 && c != 13u8 { ret false }
        i += 1usize
    }
    ret true
}

fn begin(w: *io.Writer, width: f32, height: f32, title: str, description: str) -> err {
    if !chart.finite(width) || !chart.finite(height) || width <= 0.0 || height <= 0.0 || title.len == 0usize || !text_ok(title) || !text_ok(description) { ret Invalid }
    try io.write_all(w, "<svg xmlns=\"http://www.w3.org/2000/svg\" role=\"img\" width=\"")
    try number(w, width)
    try io.write_all(w, "\" height=\"")
    try number(w, height)
    try io.write_all(w, "\" viewBox=\"0 0 ")
    try number(w, width)
    try io.write_all(w, " ")
    try number(w, height)
    try io.write_all(w, "\"><title>")
    try xml.write_escaped(w, title, false)
    try io.write_all(w, "</title><desc>")
    try xml.write_escaped(w, description, false)
    ret io.write_all(w, "</desc>\n")
}

fn finish(w: *io.Writer) -> err { ret io.write_all(w, "</svg>\n") }

fn clip_id_ok(id: str) -> bool {
    if id.len == 0usize { ret false }
    var i = 0usize
    while i < id.len {
        let c = id[i]
        let letter = (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8)
        if !letter && (i == 0usize || !((c >= 48u8 && c <= 57u8) || c == 45u8 || c == 95u8)) { ret false }
        i += 1usize
    }
    ret true
}

// Caller-owned ID must be unique within the SVG document. The group can wrap
// any existing mark or label output; end_clip closes it before outer labels.
fn begin_clip(w: *io.Writer, bounds: geometry.Rect, id: str) -> err {
    if !chart.valid_bounds(bounds) || !chart.finite(bounds.x + bounds.width) || !chart.finite(bounds.y + bounds.height) || !clip_id_ok(id) { ret Invalid }
    try io.write_all(w, "<defs><clipPath id=\"")
    try io.write_all(w, id)
    try io.write_all(w, "\"><rect x=\"")
    try number(w, bounds.x)
    try io.write_all(w, "\" y=\"")
    try number(w, bounds.y)
    try io.write_all(w, "\" width=\"")
    try number(w, bounds.width)
    try io.write_all(w, "\" height=\"")
    try number(w, bounds.height)
    try io.write_all(w, "\"/></clipPath></defs><g clip-path=\"url(#")
    try io.write_all(w, id)
    ret io.write_all(w, ")\">\n")
}

fn end_clip(w: *io.Writer) -> err { ret io.write_all(w, "</g>\n") }

fn append_map_region(w: *io.Writer, region: *const chart.MapRegionLayout, ink: paint.Color) -> err {
    if region.rings.len == 0usize || !paint.color_ok(ink) { ret Invalid }
    try io.write_all(w, "<path d=\"")
    var ring_index = 0usize
    while ring_index < region.rings.len {
        let ring = region.rings[ring_index]
        if ring.count < 3usize || ring.first > region.points.len || ring.count > region.points.len - ring.first { ret Invalid }
        if ring_index > 0usize { try io.write_all(w, " ") }
        try io.write_all(w, "M")
        var vertex_index = 0usize
        while vertex_index < ring.count {
            var index = ring.first + vertex_index
            if ring.reverse { index = ring.first + ring.count - 1usize - vertex_index }
            let point = region.points[index]
            if vertex_index > 0usize { try io.write_all(w, " L") }
            try number(w, point.x)
            try io.write_all(w, " ")
            try number(w, point.y)
            vertex_index += 1usize
        }
        try io.write_all(w, " Z")
        ring_index += 1usize
    }
    try io.write_all(w, "\" fill-rule=\"nonzero\"")
    try color(w, ink, false)
    ret io.write_all(w, "/>\n")
}

fn append_report_cells(w: *io.Writer, cells: []const chart.ReportCell, fills: []const paint.Color, bar_ink: paint.Color) -> err {
    if fills.len < 10usize || !paint.color_ok(bar_ink) { ret Invalid }
    var i = 0usize
    while i < 10usize {
        if !paint.color_ok(fills[i]) { ret Invalid }
        i += 1usize
    }
    i = 0usize
    while i < cells.len {
        let cell = cells[i]
        var index = chart.report_fill_index(cell.kind)
        if cell.kind == .Body {
            if !cell.present { index = 9usize } else if cell.source % 2usize == 1usize { index = 8usize }
        }
        try rect(w, cell.rect, fills[index], false)
        if cell.kind == .Body && cell.present && cell.bar.width > 0.0f32 && cell.bar.height > 0.0f32 {
            try rect(w, cell.bar, bar_ink, false)
        }
        i += 1usize
    }
    ret ok
}

fn rgb(w: *io.Writer, ink: paint.Color) -> err {
    // Match scene.channel_byte until the raster backend changes its output transfer.
    try io.write_all(w, "rgb(")
    try number(w, f32(u32(ink.red * 255.0 + 0.5)))
    try io.write_all(w, ",")
    try number(w, f32(u32(ink.green * 255.0 + 0.5)))
    try io.write_all(w, ",")
    try number(w, f32(u32(ink.blue * 255.0 + 0.5)))
    ret io.write_all(w, ")")
}

fn color(w: *io.Writer, ink: paint.Color, stroke: bool) -> err {
    if !paint.color_ok(ink) { ret Invalid }
    if stroke { try io.write_all(w, " stroke=\"") } else { try io.write_all(w, " fill=\"") }
    try rgb(w, ink)
    try io.write_all(w, "\"")
    // Opacity 1 is the SVG default, so only translucent ink names it.
    if ink.alpha == 1.0 { ret ok }
    if stroke { try io.write_all(w, " stroke-opacity=\"") } else { try io.write_all(w, " fill-opacity=\"") }
    try number(w, ink.alpha)
    ret io.write_all(w, "\"")
}

fn ink_ok(ink: Ink) -> bool {
    switch ink {
    case .Solid as solid:
        ret paint.color_ok(solid)
    case .Url as id:
        ret clip_id_ok(id)
    }
    ret false
}

fn ink_attr(w: *io.Writer, ink: Ink, stroke: bool) -> err {
    switch ink {
    case .Solid as solid:
        ret color(w, solid, stroke)
    case .Url as id:
        if !clip_id_ok(id) { ret Invalid }
        if stroke { try io.write_all(w, " stroke=\"url(#") } else { try io.write_all(w, " fill=\"url(#") }
        try io.write_all(w, id)
        ret io.write_all(w, ")\"")
    }
    ret Invalid
}

fn stops(w: *io.Writer, list: []const paint.Stop) -> err {
    var i = 0usize
    while i < list.len {
        try io.write_all(w, "<stop offset=\"")
        try number(w, list[i].offset)
        try io.write_all(w, "\" stop-color=\"")
        try rgb(w, list[i].color)
        try io.write_all(w, "\" stop-opacity=\"")
        try number(w, list[i].color.alpha)
        try io.write_all(w, "\"/>")
        i += 1usize
    }
    ret ok
}

// Defines a linear or radial gradient under a caller-unique id, in the brush's
// user space and padded past its ends, the way scene.brush_at samples it. A
// zero-length linear gradient is refused: the rasterizer paints it with the
// first stop, SVG with the last.
fn gradient(w: *io.Writer, id: str, brush: paint.Brush) -> err {
    if !clip_id_ok(id) || paint.validate(&brush) != ok { ret Invalid }
    switch brush {
    case .Solid as solid:
        ret Invalid
    case .Linear as linear:
        let finite_ends = chart.finite(linear.start.x) && chart.finite(linear.start.y) && chart.finite(linear.end.x) && chart.finite(linear.end.y)
        if !finite_ends || (linear.start.x == linear.end.x && linear.start.y == linear.end.y) { ret Invalid }
        try io.write_all(w, "<defs><linearGradient id=\"")
        try io.write_all(w, id)
        try io.write_all(w, "\" gradientUnits=\"userSpaceOnUse\" x1=\"")
        try number(w, linear.start.x)
        try io.write_all(w, "\" y1=\"")
        try number(w, linear.start.y)
        try io.write_all(w, "\" x2=\"")
        try number(w, linear.end.x)
        try io.write_all(w, "\" y2=\"")
        try number(w, linear.end.y)
        try io.write_all(w, "\">")
        try stops(w, linear.stops)
        ret io.write_all(w, "</linearGradient></defs>\n")
    case .Radial as radial:
        if !chart.finite(radial.center.x) || !chart.finite(radial.center.y) || !chart.finite(radial.radius) { ret Invalid }
        try io.write_all(w, "<defs><radialGradient id=\"")
        try io.write_all(w, id)
        try io.write_all(w, "\" gradientUnits=\"userSpaceOnUse\" cx=\"")
        try number(w, radial.center.x)
        try io.write_all(w, "\" cy=\"")
        try number(w, radial.center.y)
        try io.write_all(w, "\" r=\"")
        try number(w, radial.radius)
        try io.write_all(w, "\">")
        try stops(w, radial.stops)
        ret io.write_all(w, "</radialGradient></defs>\n")
    }
    ret Invalid
}

// The SVG side of chart_scene.append with any brush: a gradient is defined
// once under `id` and every mark refers to it; a solid brush ignores `id`.
fn append_brush(w: *io.Writer, marks: *const chart.Layout, brush: paint.Brush, id: str) -> err {
    switch brush {
    case .Solid as solid:
        ret append(w, marks, solid)
    case .Linear as linear:
        try gradient(w, id, brush)
    case .Radial as radial:
        try gradient(w, id, brush)
    }
    ret append_ink(w, marks, Ink { Url: id })
}

fn family_ok(family: str) -> bool {
    if family.len == 0usize || family.len > 64usize { ret false }
    var i = 0usize
    while i < family.len {
        let c = family[i]
        let letter = (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8)
        if !letter && !(c >= 48u8 && c <= 57u8) && c != 32u8 && c != 45u8 && c != 95u8 { ret false }
        i += 1usize
    }
    ret true
}

// Embeds a TrueType or OpenType font as a data URL, so labels written with
// append_labels_in render in the face the scene adapter registered rather
// than whatever sans-serif the viewer has. The whole file is embedded.
fn embed_font(w: *io.Writer, family: str, font: []const u8) -> err {
    if !family_ok(family) || font.len < 12usize { ret Invalid }
    let truetype = (font[0usize] == 0u8 && font[1usize] == 1u8 && font[2usize] == 0u8 && font[3usize] == 0u8) || str.starts_with(font[..4usize], "true")
    let opentype = str.starts_with(font[..4usize], "OTTO")
    if !truetype && !opentype { ret Invalid }
    try io.write_all(w, "<defs><style>@font-face{font-family:\"")
    try io.write_all(w, family)
    if opentype { try io.write_all(w, "\";src:url(data:font/otf;base64,") } else { try io.write_all(w, "\";src:url(data:font/ttf;base64,") }
    var encoder = bytes.base64_encoder(.Standard, true)
    var chunk: [1024]u8 = zero
    var pos = 0usize
    while pos < font.len {
        var end = pos + 765usize
        if end > font.len { end = font.len }
        let (written, encode_error) = bytes.base64_encoder_update(&encoder, chunk[..], font[pos..end])
        if encode_error != ok { ret encode_error }
        try io.write_all(w, chunk[..written])
        pos = end
    }
    let (tail, tail_error) = bytes.base64_encoder_finish(&encoder, chunk[..])
    if tail_error != ok { ret tail_error }
    try io.write_all(w, chunk[..tail])
    ret io.write_all(w, ")}</style></defs>\n")
}

fn rect(w: *io.Writer, r: geometry.Rect, ink: paint.Color, outline: bool) -> err {
    ret rect_ink(w, r, Ink { Solid: ink }, outline)
}

fn rect_ink(w: *io.Writer, r: geometry.Rect, ink: Ink, outline: bool) -> err {
    if !chart.finite(r.x) || !chart.finite(r.y) || !chart.finite(r.width) || !chart.finite(r.height) || r.width <= 0.0 || r.height <= 0.0 { ret Invalid }
    try io.write_all(w, "<rect x=\"")
    try number(w, r.x)
    try io.write_all(w, "\" y=\"")
    try number(w, r.y)
    try io.write_all(w, "\" width=\"")
    try number(w, r.width)
    try io.write_all(w, "\" height=\"")
    try number(w, r.height)
    try io.write_all(w, "\"")
    if outline {
        try io.write_all(w, " fill=\"none\"")
        try ink_attr(w, ink, true)
        try io.write_all(w, " stroke-width=\"2\"")
    } else {
        try ink_attr(w, ink, false)
    }
    ret io.write_all(w, "/>\n")
}

fn rule(w: *io.Writer, from: chart.Coord, to: chart.Coord, ink: paint.Color, width: f32) -> err {
    ret rule_ink(w, from, to, Ink { Solid: ink }, width)
}

fn rule_ink(w: *io.Writer, from: chart.Coord, to: chart.Coord, ink: Ink, width: f32) -> err {
    try io.write_all(w, "<line x1=\"")
    try number(w, from.x)
    try io.write_all(w, "\" y1=\"")
    try number(w, from.y)
    try io.write_all(w, "\" x2=\"")
    try number(w, to.x)
    try io.write_all(w, "\" y2=\"")
    try number(w, to.y)
    try io.write_all(w, "\"")
    try ink_attr(w, ink, true)
    try io.write_all(w, " stroke-width=\"")
    try number(w, width)
    ret io.write_all(w, "\" stroke-linecap=\"round\"/>\n")
}

fn line(w: *io.Writer, from: chart.Coord, to: chart.Coord, ink: paint.Color) -> err {
    ret rule(w, from, to, ink, 2.0)
}

fn path(w: *io.Writer, points: []const chart.Coord, ink: paint.Color, filled: bool) -> err {
    ret path_ink(w, points, Ink { Solid: ink }, filled)
}

fn path_ink(w: *io.Writer, points: []const chart.Coord, ink: Ink, filled: bool) -> err {
    if points.len == 0usize { ret ok }
    try io.write_all(w, "<path d=\"M")
    var i = 0usize
    while i < points.len {
        if i > 0usize { try io.write_all(w, " L") }
        try number(w, points[i].x)
        try io.write_all(w, " ")
        try number(w, points[i].y)
        i += 1usize
    }
    if filled { try io.write_all(w, " Z\"") } else { try io.write_all(w, "\" fill=\"none\"") }
    try ink_attr(w, ink, !filled)
    if !filled { try io.write_all(w, " stroke-width=\"2\" stroke-linejoin=\"round\"") }
    ret io.write_all(w, "/>\n")
}

fn dot(w: *io.Writer, p: chart.Coord, ink: paint.Color) -> err {
    ret rect(w, geometry.rect(p.x - 3.0, p.y - 3.0, 6.0, 6.0), ink, false)
}

fn dot_ink(w: *io.Writer, p: chart.Coord, ink: Ink) -> err {
    ret rect_ink(w, geometry.rect(p.x - 3.0, p.y - 3.0, 6.0, 6.0), ink, false)
}

// Standalone SVGs can select points by click or keyboard focus without script.
// Fragment targets are mark indices; data-row-id retains original source rows.
fn append_selectable_scatter(w: *io.Writer, marks: *const chart.Layout, row_ids: []const usize, descriptions: []const str, ink: paint.Color, selected_ink: paint.Color, id_prefix: str) -> err {
    if marks.kind != .Scatter || (row_ids.len != 0usize && row_ids.len != marks.coords.len) || descriptions.len != marks.coords.len || !paint.color_ok(ink) || !paint.color_ok(selected_ink) || !clip_id_ok(id_prefix) { ret Invalid }
    var i = 0usize
    while i < marks.coords.len {
        let point = marks.coords[i]
        if !chart.finite(point.x - 12.0) || !chart.finite(point.x + 12.0) || !chart.finite(point.y - 12.0) || !chart.finite(point.y + 12.0) || !text_ok(descriptions[i]) || !text_layout.valid_utf8(descriptions[i]) { ret Invalid }
        i += 1usize
    }
    try io.write_all(w, "<style>a:target .np-selection-halo,a:focus .np-selection-halo{visibility:visible}</style>\n")
    i = 0usize
    while i < marks.coords.len {
        let point = marks.coords[i]
        try io.write_all(w, "<a id=\"")
        try io.write_all(w, id_prefix)
        try io.write_all(w, "-")
        try unsigned(w, i)
        try io.write_all(w, "\" href=\"#")
        try io.write_all(w, id_prefix)
        try io.write_all(w, "-")
        try unsigned(w, i)
        try io.write_all(w, "\" tabindex=\"0\" data-row-id=\"")
        var source_row = i
        if row_ids.len > 0usize { source_row = row_ids[i] }
        try unsigned(w, source_row)
        try io.write_all(w, "\"><title>")
        try xml.write_escaped(w, descriptions[i], false)
        try io.write_all(w, "</title><rect x=\"")
        try number(w, point.x - 12.0)
        try io.write_all(w, "\" y=\"")
        try number(w, point.y - 12.0)
        try io.write_all(w, "\" width=\"24\" height=\"24\" fill=\"transparent\"/>")
        try dot(w, point, ink)
        try io.write_all(w, "<rect class=\"np-selection-halo\" x=\"")
        try number(w, point.x - 8.0)
        try io.write_all(w, "\" y=\"")
        try number(w, point.y - 8.0)
        try io.write_all(w, "\" width=\"16\" height=\"16\" fill=\"none\"")
        try color(w, selected_ink, true)
        try io.write_all(w, " stroke-width=\"2\" visibility=\"hidden\"/></a>\n")
        i += 1usize
    }
    ret ok
}

fn append(w: *io.Writer, marks: *const chart.Layout, ink: paint.Color) -> err {
    if !paint.color_ok(ink) { ret Invalid }
    ret append_ink(w, marks, Ink { Solid: ink })
}

fn append_ink(w: *io.Writer, marks: *const chart.Layout, ink: Ink) -> err {
    if !ink_ok(ink) { ret Invalid }
    if marks.kind == .PointLine {
        var line_marks = *marks
        line_marks.kind = .Line
        try append_ink(w, &line_marks, ink)
        var points = *marks
        points.kind = .Scatter
        ret append_ink(w, &points, ink)
    }
    if marks.kind == .Scatter || marks.kind == .Strip || marks.kind == .Beeswarm || marks.kind == .DotPlot {
        var i = 0usize
        while i < marks.coords.len {
            try dot_ink(w, marks.coords[i], ink)
            i += 1usize
        }
    } else if marks.kind == .Line || marks.kind == .Step || marks.kind == .Ecdf || marks.kind == .Density || marks.kind == .FrequencyPolygon {
        if marks.segments.len == 0usize { ret ok }
        try io.write_all(w, "<path d=\"M")
        try number(w, marks.segments[0usize].from.x)
        try io.write_all(w, " ")
        try number(w, marks.segments[0usize].from.y)
        var i = 0usize
        while i < marks.segments.len {
            // A segment that does not start where the last one ended is a gap.
            let start = marks.segments[i].from
            if i > 0usize && (start.x != marks.segments[i - 1usize].to.x || start.y != marks.segments[i - 1usize].to.y) {
                try io.write_all(w, " M")
                try number(w, start.x)
                try io.write_all(w, " ")
                try number(w, start.y)
            }
            try io.write_all(w, " L")
            try number(w, marks.segments[i].to.x)
            try io.write_all(w, " ")
            try number(w, marks.segments[i].to.y)
            i += 1usize
        }
        try io.write_all(w, "\" fill=\"none\"")
        try ink_attr(w, ink, true)
        try io.write_all(w, " stroke-width=\"2\" stroke-linejoin=\"round\"/>\n")
    } else if marks.kind == .Area || marks.kind == .Violin || marks.kind == .Band {
        if marks.coords.len < 4usize { ret Invalid }
        try path_ink(w, marks.coords, ink, true)
    } else if marks.kind == .Box || marks.kind == .Lollipop || marks.kind == .ErrorBar || marks.kind == .Qq || marks.kind == .Pp || marks.kind == .Dumbbell || marks.kind == .SlopeGraph || marks.kind == .Rug {
        var i = 0usize
        while i < marks.bars.len {
            if marks.bars[i].width > 0.0 && marks.bars[i].height > 0.0 { try rect_ink(w, marks.bars[i], ink, true) }
            i += 1usize
        }
        i = 0usize
        while i < marks.segments.len {
            try rule_ink(w, marks.segments[i].from, marks.segments[i].to, ink, 2.0)
            i += 1usize
        }
        i = 0usize
        while i < marks.coords.len {
            try dot_ink(w, marks.coords[i], ink)
            i += 1usize
        }
    } else if marks.kind == .Bubble {
        var i = 0usize
        while i < marks.bars.len {
            let box = marks.bars[i]
            if box.width > 0.0 && box.height > 0.0 {
                try io.write_all(w, "<circle cx=\"")
                try number(w, box.x + box.width * 0.5)
                try io.write_all(w, "\" cy=\"")
                try number(w, box.y + box.height * 0.5)
                try io.write_all(w, "\" r=\"")
                try number(w, box.width * 0.5)
                try io.write_all(w, "\"")
                try ink_attr(w, ink, false)
                try io.write_all(w, "/>\n")
            }
            i += 1usize
        }
    } else if marks.kind == .Bar || marks.kind == .Histogram || marks.kind == .Waterfall {
        var i = 0usize
        while i < marks.bars.len {
            if marks.bars[i].width > 0.0 && marks.bars[i].height > 0.0 { try rect_ink(w, marks.bars[i], ink, false) }
            i += 1usize
        }
        if marks.kind == .Waterfall {
            i = 0usize
            while i < marks.segments.len {
                try rule_ink(w, marks.segments[i].from, marks.segments[i].to, ink, 2.0)
                i += 1usize
            }
        }
    } else {
        ret Invalid
    }
    ret ok
}

// Keep every polygon of one band in one SVG path, matching the scene fill.
fn append_filled_contour(w: *io.Writer, layers: []const chart.Layout, band_ids: []const usize, colors: []const paint.Color) -> err {
    if layers.len != band_ids.len || colors.len == 0usize { ret Invalid }
    var i = 0usize
    while i < layers.len {
        if layers[i].kind != .Area || layers[i].coords.len < 4usize || band_ids[i] >= colors.len { ret Invalid }
        i += 1usize
    }
    var color_index = 0usize
    while color_index < colors.len {
        if !paint.color_ok(colors[color_index]) { ret Invalid }
        var started = false
        i = 0usize
        while i < layers.len {
            if band_ids[i] == color_index {
                if !started {
                    try io.write_all(w, "<path d=\"")
                    started = true
                } else {
                    try io.write_all(w, " ")
                }
                try io.write_all(w, "M")
                var j = 0usize
                while j < layers[i].coords.len {
                    if j > 0usize { try io.write_all(w, " L") }
                    try number(w, layers[i].coords[j].x)
                    try io.write_all(w, " ")
                    try number(w, layers[i].coords[j].y)
                    j += 1usize
                }
                try io.write_all(w, " Z")
            }
            i += 1usize
        }
        if started {
            try io.write_all(w, "\"")
            try color(w, colors[color_index], false)
            try io.write_all(w, "/>\n")
        }
        color_index += 1usize
    }
    ret ok
}

fn append_matrix(w: *io.Writer, marks: *const chart.MatrixLayout, low: paint.Color, middle: paint.Color, high: paint.Color) -> err {
    if marks.kind != .Heatmap && marks.kind != .Correlation && marks.kind != .Mosaic && marks.kind != .Association { ret Invalid }
    if marks.columns == 0usize || marks.rows == 0usize || (marks.cells.len == 0usize && marks.kind != .Association) { ret Invalid }
    if marks.cells.len > 0usize && (marks.cells.len - 1usize) / marks.columns >= marks.rows { ret Invalid }
    if !paint.color_ok(low) || !paint.color_ok(middle) || !paint.color_ok(high) { ret Invalid }
    var i = 0usize
    while i < marks.cells.len {
        let cell = marks.cells[i]
        if !chart.finite(cell.value) { ret Invalid }
        var ink = middle
        if marks.kind == .Correlation || marks.kind == .Mosaic || marks.kind == .Association {
            let value = cell.value / marks.value_max
            if value < 0.0 { ink = paint.mix(low, middle, value + 1.0) }
            if value > 0.0 { ink = paint.mix(middle, high, value) }
        } else if marks.value_max > marks.value_min {
            ink = paint.mix(low, high, (cell.value - marks.value_min) / (marks.value_max - marks.value_min))
        }
        try rect(w, cell.rect, ink, false)
        i += 1usize
    }
    ret ok
}

fn append_guides(w: *io.Writer, bounds: geometry.Rect, x_ticks: []const chart.Tick, y_ticks: []const chart.Tick, grid: paint.Color, axis: paint.Color) -> err {
    if !chart.valid_bounds(bounds) || !paint.color_ok(grid) || !paint.color_ok(axis) { ret Invalid }
    var i = 0usize
    while i < x_ticks.len {
        let t = x_ticks[i].fraction
        if !(t >= 0.0 && t <= 1.0) { ret Invalid }
        let x = bounds.x + bounds.width * t
        try rule(w, chart.Coord { x: x, y: bounds.y }, chart.Coord { x: x, y: bounds.y + bounds.height }, grid, 1.0)
        try rule(w, chart.Coord { x: x, y: bounds.y + bounds.height }, chart.Coord { x: x, y: bounds.y + bounds.height + 5.0 }, axis, 1.0)
        i += 1usize
    }
    i = 0usize
    while i < y_ticks.len {
        let t = y_ticks[i].fraction
        if !(t >= 0.0 && t <= 1.0) { ret Invalid }
        let y = bounds.y + bounds.height * (1.0 - t)
        try rule(w, chart.Coord { x: bounds.x, y: y }, chart.Coord { x: bounds.x + bounds.width, y: y }, grid, 1.0)
        try rule(w, chart.Coord { x: bounds.x - 5.0, y: y }, chart.Coord { x: bounds.x, y: y }, axis, 1.0)
        i += 1usize
    }
    try rule(w, chart.Coord { x: bounds.x, y: bounds.y }, chart.Coord { x: bounds.x, y: bounds.y + bounds.height }, axis, 1.0)
    ret rule(w, chart.Coord { x: bounds.x, y: bounds.y + bounds.height }, chart.Coord { x: bounds.x + bounds.width, y: bounds.y + bounds.height }, axis, 1.0)
}

fn append_labels(w: *io.Writer, labels: []const chart.Label, ink: paint.Color, size: f32) -> err {
    ret append_labels_in(w, labels, ink, size, "")
}

// Labels in a family from embed_font, falling back to sans-serif; an empty
// family writes plain sans-serif.
fn append_labels_in(w: *io.Writer, labels: []const chart.Label, ink: paint.Color, size: f32, family: str) -> err {
    if !paint.color_ok(ink) || !chart.finite(size) || size <= 0.0 || (family.len > 0usize && !family_ok(family)) { ret Invalid }
    var i = 0usize
    while i < labels.len {
        let label = labels[i]
        if !chart.valid_label(&label) || !text_layout.valid_utf8(label.text) { ret Invalid }
        try io.write_all(w, "<text x=\"")
        try number(w, label.anchor.x)
        try io.write_all(w, "\" y=\"")
        try number(w, label.anchor.y)
        try io.write_all(w, "\" font-family=\"")
        if family.len > 0usize {
            try io.write_all(w, "'")
            try io.write_all(w, family)
            try io.write_all(w, "', ")
        }
        try io.write_all(w, "sans-serif\" font-size=\"")
        try number(w, size)
        try io.write_all(w, "\" text-anchor=\"")
        if label.align == .Center {
            try io.write_all(w, "middle")
        } else if label.align == .Right {
            try io.write_all(w, "end")
        } else {
            try io.write_all(w, "start")
        }
        try io.write_all(w, "\"")
        try color(w, ink, false)
        try io.write_all(w, ">")
        try xml.write_escaped(w, label.text, false)
        try io.write_all(w, "</text>\n")
        i += 1usize
    }
    ret ok
}
