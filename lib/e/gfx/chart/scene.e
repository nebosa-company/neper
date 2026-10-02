// Draw the renderer-neutral chart marks into an existing scene display list.
use e.mem
use e.gfx.chart
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene

fn append(a: *mem.Arena, builder: *scene.Builder, marks: *const chart.Layout, brush: paint.Brush) -> err {
    if marks.kind == .Scatter {
        var i = 0usize
        while i < marks.coords.len {
            let p = marks.coords[i]
            try scene.push(builder, scene.Command { FillRect: scene.FillRect {
                rect: geometry.rect(p.x - 3.0, p.y - 3.0, 6.0, 6.0), brush: brush,
            } })
            i += 1usize
        }
    } else if marks.kind == .Line || marks.kind == .Step || marks.kind == .Ecdf {
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
    } else if marks.kind == .Bar || marks.kind == .Histogram {
        var i = 0usize
        while i < marks.bars.len {
            if marks.bars[i].width > 0.0 && marks.bars[i].height > 0.0 {
                try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: marks.bars[i], brush: brush } })
            }
            i += 1usize
        }
    } else {
        ret chart.Invalid
    }
    ret ok
}
