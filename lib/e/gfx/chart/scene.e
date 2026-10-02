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
    } else if marks.kind == .Line || marks.kind == .Step || marks.kind == .Ecdf || marks.kind == .Density {
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
    } else if marks.kind == .Box {
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
    } else if marks.kind == .Violin {
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
    } else if marks.kind == .Qq {
        let line = chart.Layout { kind: .Line, coords: zero, segments: marks.segments, bars: zero, x_min: marks.x_min, x_max: marks.x_max, y_min: marks.y_min, y_max: marks.y_max }
        try append(a, builder, &line, brush)
        let dots = chart.Layout { kind: .Scatter, coords: marks.coords, segments: zero, bars: zero, x_min: marks.x_min, x_max: marks.x_max, y_min: marks.y_min, y_max: marks.y_max }
        try append(a, builder, &dots, brush)
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
