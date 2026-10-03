// Streaming SVG adapter for the renderer-neutral chart layouts.
use e.fmt.xml
use e.gfx.chart
use e.gfx.geometry
use e.gfx.paint
use e.io
use e.mem
use e.str
use e.text.layout as text_layout

error Invalid

fn number(w: *io.Writer, value: f32) -> err {
    if !chart.finite(value) { ret Invalid }
    var scratch: [64]u8 = zero
    var arena = mem.arena_from(scratch[..])
    let (made, builder_error) = str.builder(&arena, 40usize)
    if builder_error != ok { ret builder_error }
    var built = made
    try str.push_f64(&built, f64(value))
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

fn color(w: *io.Writer, ink: paint.Color, stroke: bool) -> err {
    if !paint.color_ok(ink) { ret Invalid }
    // Match scene.channel_byte until the raster backend changes its output transfer.
    if stroke { try io.write_all(w, " stroke=\"rgb(") } else { try io.write_all(w, " fill=\"rgb(") }
    try number(w, f32(u32(ink.red * 255.0 + 0.5)))
    try io.write_all(w, ",")
    try number(w, f32(u32(ink.green * 255.0 + 0.5)))
    try io.write_all(w, ",")
    try number(w, f32(u32(ink.blue * 255.0 + 0.5)))
    try io.write_all(w, ")\"")
    if stroke { try io.write_all(w, " stroke-opacity=\"") } else { try io.write_all(w, " fill-opacity=\"") }
    try number(w, ink.alpha)
    ret io.write_all(w, "\"")
}

fn rect(w: *io.Writer, r: geometry.Rect, ink: paint.Color, outline: bool) -> err {
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
        try color(w, ink, true)
        try io.write_all(w, " stroke-width=\"2\"")
    } else {
        try color(w, ink, false)
    }
    ret io.write_all(w, "/>\n")
}

fn rule(w: *io.Writer, from: chart.Coord, to: chart.Coord, ink: paint.Color, width: f32) -> err {
    try io.write_all(w, "<line x1=\"")
    try number(w, from.x)
    try io.write_all(w, "\" y1=\"")
    try number(w, from.y)
    try io.write_all(w, "\" x2=\"")
    try number(w, to.x)
    try io.write_all(w, "\" y2=\"")
    try number(w, to.y)
    try io.write_all(w, "\"")
    try color(w, ink, true)
    try io.write_all(w, " stroke-width=\"")
    try number(w, width)
    ret io.write_all(w, "\" stroke-linecap=\"round\"/>\n")
}

fn line(w: *io.Writer, from: chart.Coord, to: chart.Coord, ink: paint.Color) -> err {
    ret rule(w, from, to, ink, 2.0)
}

fn path(w: *io.Writer, points: []const chart.Coord, ink: paint.Color, filled: bool) -> err {
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
    try color(w, ink, !filled)
    if !filled { try io.write_all(w, " stroke-width=\"2\" stroke-linejoin=\"round\"") }
    ret io.write_all(w, "/>\n")
}

fn dot(w: *io.Writer, p: chart.Coord, ink: paint.Color) -> err {
    ret rect(w, geometry.rect(p.x - 3.0, p.y - 3.0, 6.0, 6.0), ink, false)
}

fn append(w: *io.Writer, marks: *const chart.Layout, ink: paint.Color) -> err {
    if !paint.color_ok(ink) { ret Invalid }
    if marks.kind == .PointLine {
        var line_marks = *marks
        line_marks.kind = .Line
        try append(w, &line_marks, ink)
        var points = *marks
        points.kind = .Scatter
        ret append(w, &points, ink)
    }
    if marks.kind == .Scatter || marks.kind == .Strip || marks.kind == .Beeswarm || marks.kind == .DotPlot {
        var i = 0usize
        while i < marks.coords.len {
            try dot(w, marks.coords[i], ink)
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
            try io.write_all(w, " L")
            try number(w, marks.segments[i].to.x)
            try io.write_all(w, " ")
            try number(w, marks.segments[i].to.y)
            i += 1usize
        }
        try io.write_all(w, "\" fill=\"none\"")
        try color(w, ink, true)
        try io.write_all(w, " stroke-width=\"2\" stroke-linejoin=\"round\"/>\n")
    } else if marks.kind == .Area || marks.kind == .Violin || marks.kind == .Band {
        if marks.coords.len < 4usize { ret Invalid }
        try path(w, marks.coords, ink, true)
    } else if marks.kind == .Box || marks.kind == .Lollipop || marks.kind == .ErrorBar || marks.kind == .Qq || marks.kind == .Pp || marks.kind == .Dumbbell || marks.kind == .SlopeGraph || marks.kind == .Rug {
        var i = 0usize
        while i < marks.bars.len {
            if marks.bars[i].width > 0.0 && marks.bars[i].height > 0.0 { try rect(w, marks.bars[i], ink, true) }
            i += 1usize
        }
        i = 0usize
        while i < marks.segments.len {
            try line(w, marks.segments[i].from, marks.segments[i].to, ink)
            i += 1usize
        }
        i = 0usize
        while i < marks.coords.len {
            try dot(w, marks.coords[i], ink)
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
                try color(w, ink, false)
                try io.write_all(w, "/>\n")
            }
            i += 1usize
        }
    } else if marks.kind == .Bar || marks.kind == .Histogram || marks.kind == .Waterfall {
        var i = 0usize
        while i < marks.bars.len {
            if marks.bars[i].width > 0.0 && marks.bars[i].height > 0.0 { try rect(w, marks.bars[i], ink, false) }
            i += 1usize
        }
        if marks.kind == .Waterfall {
            i = 0usize
            while i < marks.segments.len {
                try line(w, marks.segments[i].from, marks.segments[i].to, ink)
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
    if !paint.color_ok(ink) || !chart.finite(size) || size <= 0.0 { ret Invalid }
    var i = 0usize
    while i < labels.len {
        let label = labels[i]
        if !chart.valid_label(&label) || !text_layout.valid_utf8(label.text) { ret Invalid }
        try io.write_all(w, "<text x=\"")
        try number(w, label.anchor.x)
        try io.write_all(w, "\" y=\"")
        try number(w, label.anchor.y)
        try io.write_all(w, "\" font-family=\"sans-serif\" font-size=\"")
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
