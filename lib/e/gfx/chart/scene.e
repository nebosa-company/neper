// Draw the renderer-neutral chart marks into an existing scene display list.
use e.mem
use e.gpu
use e.gfx.chart
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.layout as text_layout
use e.text.shape

fn straight_channel(premultiplied: u32, alpha: u32) -> u8 {
    if alpha == 0u32 { ret 0u8 }
    let value = (premultiplied * 255u32 + alpha / 2u32) / alpha
    if value > 255u32 { ret 255u8 }
    ret u8(value)
}

// Rasterize a finished chart display list into caller-owned straight RGBA.
// Create any arena-backed output writer only after this returns.
fn rasterize(a: *mem.Arena, q: *gpu.Queue, output_target: *gpu.Target, canvas: scene.Target, renderer: *scene.Renderer, builder: *scene.Builder, width: u32, height: u32) -> (image.ConstImage, err) {
    if width == 0u32 || height == 0u32 { ret (zero, chart.Invalid) }
    let (_, size_error) = image.required_bytes(width, height, .Rgba8, usize(width) * 4usize)
    if size_error != ok { ret (zero, size_error) }
    let (compiled, compile_error) = scene.compile(renderer, scene.finish(builder))
    if compile_error != ok { ret (zero, compile_error) }
    defer let _ = scene.release_scene(renderer, compiled)
    let render_error = scene.render(renderer, compiled, canvas, geometry.Size { width: f32(width), height: f32(height) })
    if render_error != ok { ret (zero, render_error) }
    let (shown, shown_error) = gpu.presented(output_target)
    if shown_error != ok { ret (zero, shown_error) }
    if shown.width != width || shown.height != height { ret (zero, chart.Invalid) }
    let count = usize(width) * usize(height)
    let (pixels, pixels_error) = mem.alloc[u32](a, count)
    if pixels_error != ok { ret (zero, pixels_error) }
    let read_error = gpu.read_image(q, shown, pixels)
    if read_error != ok { ret (zero, read_error) }
    let (rgba, rgba_error) = mem.alloc[u8](a, count * 4usize)
    if rgba_error != ok { ret (zero, rgba_error) }
    var i = 0usize
    while i < count {
        let pixel = pixels[i]
        let alpha = (pixel >> 24u32) & 255u32
        rgba[4usize * i] = straight_channel(pixel & 255u32, alpha)
        rgba[4usize * i + 1usize] = straight_channel((pixel >> 8u32) & 255u32, alpha)
        rgba[4usize * i + 2usize] = straight_channel((pixel >> 16u32) & 255u32, alpha)
        rgba[4usize * i + 3usize] = u8(alpha)
        i += 1usize
    }
    let (view, view_error) = image.make_const(rgba, width, height, usize(width) * 4usize, .Rgba8, .Straight)
    ret (view, view_error)
}

fn append(a: *mem.Arena, builder: *scene.Builder, marks: *const chart.Layout, brush: paint.Brush) -> err {
    if marks.kind == .PointLine {
        var line_marks = *marks
        line_marks.kind = .Line
        try append(a, builder, &line_marks, brush)
        var points = *marks
        points.kind = .Scatter
        ret append(a, builder, &points, brush)
    }
    if marks.kind == .Scatter || marks.kind == .Strip || marks.kind == .Beeswarm || marks.kind == .DotPlot {
        var i = 0usize
        while i < marks.coords.len {
            let p = marks.coords[i]
            try scene.push(builder, scene.Command { FillRect: scene.FillRect {
                rect: geometry.rect(p.x - 3.0, p.y - 3.0, 6.0, 6.0), brush: brush,
            } })
            i += 1usize
        }
    } else if marks.kind == .Line || marks.kind == .Step || marks.kind == .Ecdf || marks.kind == .Density || marks.kind == .FrequencyPolygon {
        if marks.segments.len == 0usize { ret ok }
        let (made, path_error) = geometry.path_builder(a, marks.segments.len + 1usize, marks.segments.len + 1usize)
        if path_error != ok { ret path_error }
        var path = made
        let first = marks.segments[0usize].from
        try geometry.move_to(&path, geometry.Point { x: first.x, y: first.y })
        var i = 0usize
        while i < marks.segments.len {
            let p = marks.segments[i].to
            try geometry.line_to(&path, geometry.Point { x: p.x, y: p.y })
            i += 1usize
        }
        try scene.push(builder, scene.Command { StrokePath: scene.StrokePath {
            path: geometry.finish(&path), brush: brush,
            stroke: paint.Stroke { width: 2.0, cap: .Round, join: .Round, miter_limit: 4.0 },
        } })
    } else if marks.kind == .Box || marks.kind == .Lollipop || marks.kind == .ErrorBar || marks.kind == .Dumbbell || marks.kind == .Rug {
        var i = 0usize
        while i < marks.bars.len {
            let r = marks.bars[i]
            if r.width > 0.0 && r.height > 0.0 {
                let (made, path_error) = geometry.path_builder(a, 5usize, 4usize)
                if path_error != ok { ret path_error }
                var path = made
                try geometry.move_to(&path, geometry.Point { x: r.x, y: r.y })
                try geometry.line_to(&path, geometry.Point { x: r.x + r.width, y: r.y })
                try geometry.line_to(&path, geometry.Point { x: r.x + r.width, y: r.y + r.height })
                try geometry.line_to(&path, geometry.Point { x: r.x, y: r.y + r.height })
                try geometry.close_path(&path)
                try scene.push(builder, scene.Command { StrokePath: scene.StrokePath {
                    path: geometry.finish(&path), brush: brush,
                    stroke: paint.Stroke { width: 2.0, cap: .Square, join: .Miter, miter_limit: 4.0 },
                } })
            }
            i += 1usize
        }
        i = 0usize
        while i < marks.segments.len {
            let (made, path_error) = geometry.path_builder(a, 2usize, 2usize)
            if path_error != ok { ret path_error }
            var path = made
            let from = marks.segments[i].from
            let to = marks.segments[i].to
            try geometry.move_to(&path, geometry.Point { x: from.x, y: from.y })
            try geometry.line_to(&path, geometry.Point { x: to.x, y: to.y })
            try scene.push(builder, scene.Command { StrokePath: scene.StrokePath {
                path: geometry.finish(&path), brush: brush,
                stroke: paint.Stroke { width: 2.0, cap: .Square, join: .Miter, miter_limit: 4.0 },
            } })
            i += 1usize
        }
        i = 0usize
        while i < marks.coords.len {
            let p = marks.coords[i]
            try scene.push(builder, scene.Command { FillRect: scene.FillRect {
                rect: geometry.rect(p.x - 3.0, p.y - 3.0, 6.0, 6.0), brush: brush,
            } })
            i += 1usize
        }
    } else if marks.kind == .Violin || marks.kind == .Area || marks.kind == .Band {
        if marks.coords.len < 4usize { ret chart.Invalid }
        let (made, path_error) = geometry.path_builder(a, marks.coords.len + 1usize, marks.coords.len)
        if path_error != ok { ret path_error }
        var path = made
        try geometry.move_to(&path, geometry.Point { x: marks.coords[0usize].x, y: marks.coords[0usize].y })
        var i = 1usize
        while i < marks.coords.len {
            try geometry.line_to(&path, geometry.Point { x: marks.coords[i].x, y: marks.coords[i].y })
            i += 1usize
        }
        try geometry.close_path(&path)
        try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&path), brush: brush } })
    } else if marks.kind == .Qq || marks.kind == .Pp {
        let line = chart.Layout { kind: .Line, coords: zero, segments: marks.segments, bars: zero, x_min: marks.x_min, x_max: marks.x_max, y_min: marks.y_min, y_max: marks.y_max }
        try append(a, builder, &line, brush)
        let dots = chart.Layout { kind: .Scatter, coords: marks.coords, segments: zero, bars: zero, x_min: marks.x_min, x_max: marks.x_max, y_min: marks.y_min, y_max: marks.y_max }
        try append(a, builder, &dots, brush)
    } else if marks.kind == .Bubble {
        var i = 0usize
        while i < marks.bars.len {
            let box = marks.bars[i]
            if box.width > 0.0 && box.height > 0.0 {
                let (made, path_error) = geometry.path_builder(a, 6usize, 13usize)
                if path_error != ok { ret path_error }
                var path = made
                let cx = box.x + box.width * 0.5
                let cy = box.y + box.height * 0.5
                let r = box.width * 0.5
                let k = r * 0.55228475
                try geometry.move_to(&path, geometry.Point { x: cx + r, y: cy })
                try geometry.cubic_to(&path, geometry.Point { x: cx + r, y: cy + k }, geometry.Point { x: cx + k, y: cy + r }, geometry.Point { x: cx, y: cy + r })
                try geometry.cubic_to(&path, geometry.Point { x: cx - k, y: cy + r }, geometry.Point { x: cx - r, y: cy + k }, geometry.Point { x: cx - r, y: cy })
                try geometry.cubic_to(&path, geometry.Point { x: cx - r, y: cy - k }, geometry.Point { x: cx - k, y: cy - r }, geometry.Point { x: cx, y: cy - r })
                try geometry.cubic_to(&path, geometry.Point { x: cx + k, y: cy - r }, geometry.Point { x: cx + r, y: cy - k }, geometry.Point { x: cx + r, y: cy })
                try geometry.close_path(&path)
                try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&path), brush: brush } })
            }
            i += 1usize
        }
    } else if marks.kind == .Bar || marks.kind == .Histogram || marks.kind == .Waterfall {
        var i = 0usize
        while i < marks.bars.len {
            if marks.bars[i].width > 0.0 && marks.bars[i].height > 0.0 {
                try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: marks.bars[i], brush: brush } })
            }
            i += 1usize
        }
        if marks.kind == .Waterfall {
            let links = chart.Layout { kind: .Rug, coords: zero, segments: marks.segments, bars: zero, x_min: marks.x_min, x_max: marks.x_max, y_min: marks.y_min, y_max: marks.y_max }
            try append(a, builder, &links, brush)
        }
    } else {
        ret chart.Invalid
    }
    ret ok
}

// Matrix palettes are supplied by the caller. Correlation uses a neutral
// midpoint at zero; ordinary heatmaps interpolate directly from low to high.
fn append_matrix(builder: *scene.Builder, marks: *const chart.MatrixLayout, low: paint.Color, middle: paint.Color, high: paint.Color) -> err {
    if marks.kind != .Heatmap && marks.kind != .Correlation && marks.kind != .Mosaic { ret chart.Invalid }
    if marks.columns == 0usize || marks.rows == 0usize || marks.cells.len == 0usize || (marks.cells.len - 1usize) / marks.columns >= marks.rows { ret chart.Invalid }
    var i = 0usize
    while i < marks.cells.len {
        let cell = marks.cells[i]
        if cell.value != cell.value || cell.value - cell.value != 0.0 || cell.rect.width <= 0.0 || cell.rect.height <= 0.0 { ret chart.Invalid }
        var color = middle
        if marks.kind == .Correlation || marks.kind == .Mosaic {
            let value = cell.value / marks.value_max
            if value < 0.0 { color = paint.mix(low, middle, value + 1.0) }
            if value > 0.0 { color = paint.mix(middle, high, value) }
        } else if marks.value_max > marks.value_min {
            color = paint.mix(low, high, (cell.value - marks.value_min) / (marks.value_max - marks.value_min))
        }
        try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: cell.rect, brush: paint.Brush { Solid: color } } })
        i += 1usize
    }
    ret ok
}

// Tick values remain metadata for a text adapter; this scene pass draws the
// grid, axis rules and small ticks at their normalized positions.
fn append_guides(builder: *scene.Builder, bounds: geometry.Rect, x_ticks: []const chart.Tick, y_ticks: []const chart.Tick, grid: paint.Brush, axis: paint.Brush) -> err {
    if !chart.valid_bounds(bounds) { ret chart.Invalid }
    var i = 0usize
    while i < x_ticks.len {
        let t = x_ticks[i].fraction
        if !(t >= 0.0 && t <= 1.0) { ret chart.Invalid }
        let x = bounds.x + bounds.width * t
        try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(x, bounds.y, 1.0, bounds.height), brush: grid } })
        try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(x, bounds.y + bounds.height, 1.0, 5.0), brush: axis } })
        i += 1usize
    }
    i = 0usize
    while i < y_ticks.len {
        let t = y_ticks[i].fraction
        if !(t >= 0.0 && t <= 1.0) { ret chart.Invalid }
        let y = bounds.y + bounds.height * (1.0 - t)
        try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(bounds.x, y, bounds.width, 1.0), brush: grid } })
        try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(bounds.x - 5.0, y, 5.0, 1.0), brush: axis } })
        i += 1usize
    }
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(bounds.x, bounds.y, 1.0, bounds.height), brush: axis } })
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(bounds.x, bounds.y + bounds.height, bounds.width, 1.0), brush: axis } })
    ret ok
}

// The caller registers `font` with the renderer before replaying the scene.
// Layout objects live in the caller's arena, alongside the display list.
fn append_labels(a: *mem.Arena, builder: *scene.Builder, labels: []const chart.Label, font: shape.Font, size: f32, brush: paint.Brush) -> err {
    if !chart.finite(size) || size <= 0.0 { ret chart.Invalid }
    try shape.validate_font(font)
    let fonts = [1]text_layout.FontChoice{ text_layout.FontChoice { font: font, size: size } }
    let style = text_layout.Style { fonts: fonts[..], language: "", line_height: 0.0 }
    let options = text_layout.Options { width: 0.0, max_lines: 1u32, align: .Start, wrap: .None, ellipsis: "", notdef: true }
    var i = 0usize
    while i < labels.len {
        let label = labels[i]
        if !chart.valid_label(&label) || !text_layout.valid_utf8(label.text) { ret chart.Invalid }
        let (laid, layout_error) = text_layout.layout(a, label.text, style, options)
        if layout_error != ok { ret layout_error }
        if laid.lines.len != 1usize { ret chart.Invalid }
        let (held, allocation_error) = mem.alloc[text_layout.Layout](a, 1usize)
        if allocation_error != ok { ret allocation_error }
        held[0usize] = laid
        var x = label.anchor.x
        if label.align == .Center { x -= laid.bounds.width / 2.0 }
        if label.align == .Right { x -= laid.bounds.width }
        try scene.push(builder, scene.Command { Text: scene.DrawText {
            layout: &held[0usize], origin: geometry.Point { x: x, y: label.anchor.y - laid.lines[0usize].baseline }, brush: brush,
        } })
        i += 1usize
    }
    ret ok
}
