// The soft shadow of a round slider as GTK draws it (round 22, worker lb): `box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2)` on the knob of a
// switch or a scale. GTK's Cairo renderer blurs the shape's coverage with three box blurs (the SVG recipe for a Gaussian; a 4 px blur
// is a box of 3 px per pass), so the soft edge is not a Gaussian and not a few fitted rings: fitted on the library's own switch it
// is within 2 levels of every shadow pixel. The mask is the disc under `dy` px, 8 x 8 samples per device pixel, blurred in device
// pixels (the box grows with the render scale), and drawn one device pixel per rectangle, equal neighbours merged.

use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.math
use e.mem
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.winpx

error TooLarge

type Soft = struct { arena: *mem.Arena, radius: f32, dy: f32, alpha: f32, box: f32 }

fn soft_measure(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 0.0, height: 0.0 }
}

// One box-blur pass over `grid` (`n` x `n`, row stride `n`) along x (`across`) or y: each cell becomes the mean of the cells
// from `lo` to `hi` away (cells outside the grid count as 0). `tmp` is scratch of the same size.
fn pass(grid: []f32, tmp: []f32, n: usize, across: bool, lo: i32, hi: i32) {
    let width = f32(hi - lo + 1)
    var line: usize = 0usize
    while line < n {
        var at: usize = 0usize
        while at < n {
            var sum: f32 = 0.0
            var k: i32 = lo
            while k <= hi {
                let from = i32(at) + k
                if from >= 0 && from < i32(n) {
                    if across { sum += grid[line * n + usize(from)] } else { sum += grid[usize(from) * n + line] }
                }
                k += 1
            }
            if across { tmp[line * n + at] = sum / width } else { tmp[at * n + line] = sum / width }
            at += 1usize
        }
        line += 1usize
    }
    var i: usize = 0usize
    while i < n * n {
        grid[i] = tmp[i]
        i += 1usize
    }
}

// The three passes along one axis: odd `d` is three boxes of d; even is d, d and d + 1 with the first two half a pixel off.
fn blur_axis(grid: []f32, tmp: []f32, n: usize, across: bool, d: i32) {
    let h = d / 2
    if d % 2 == 1 {
        pass(grid, tmp, n, across, 0 - h, h)
        pass(grid, tmp, n, across, 0 - h, h)
        pass(grid, tmp, n, across, 0 - h, h)
    } else {
        pass(grid, tmp, n, across, 0 - h, h - 1)
        pass(grid, tmp, n, across, 1 - h, h)
        pass(grid, tmp, n, across, 0 - h, h)
    }
}

fn soft_paint(ctx: *void, b: *scene.Builder, area: geometry.Rect) -> err {
    let soft = mem.cast[*Soft](ctx)
    ret soft_disc(soft.arena, b, area, soft.radius, soft.dy, soft.alpha, soft.box)
}

// The shadow of the disc of `radius` centred in `area`, `dy` px lower, `alpha` black at its strongest, the blur boxes `box` px wide.
fn soft_disc(arena: *mem.Arena, b: *scene.Builder, area: geometry.Rect, radius: f32, dy: f32, alpha: f32, box: f32) -> err {
    let soft = Soft { arena: arena, radius: radius, dy: dy, alpha: alpha, box: box }
    let scale = scene.builder_scale(b)
    var d = i32(soft.box * scale + 0.5)
    if d < 1 { d = 1 }
    let reach = 3 * (d / 2) + 2
    let margin = reach + i32(soft.dy * scale + 1.0)
    let side = area.width * scale
    // the grid: whole device pixels around the disc's box
    let gx0 = i32(math.floor[f32](area.x * scale)) - margin
    let gy0 = i32(math.floor[f32](area.y * scale)) - margin
    var n = usize(side + 1.0) + usize(2 * margin) + 1usize
    if n > 96usize { n = 96usize }
    let (grid, grid_error) = mem.alloc[f32](soft.arena, n * n)
    if grid_error != ok { ret grid_error }
    let (tmp, tmp_error) = mem.alloc[f32](soft.arena, n * n)
    if tmp_error != ok { ret tmp_error }
    let cx = area.x * scale + side * 0.5 - f32(gx0)
    let cy0 = area.y * scale + area.height * scale * 0.5 - f32(gy0)
    let cy = cy0 + soft.dy * scale
    let rr = soft.radius * scale
    var y: usize = 0usize
    while y < n {
        var x: usize = 0usize
        while x < n {
            var inside: i32 = 0
            var sy: i32 = 0
            while sy < 8 {
                var sx: i32 = 0
                while sx < 8 {
                    let px = f32(x) + (f32(sx) + 0.5) / 8.0 - cx
                    let py = f32(y) + (f32(sy) + 0.5) / 8.0 - cy
                    if px * px + py * py <= rr * rr { inside += 1 }
                    sx += 1
                }
                sy += 1
            }
            grid[y * n + x] = f32(inside) / 64.0
            x += 1usize
        }
        y += 1usize
    }
    blur_axis(grid, tmp, n, true, d)
    blur_axis(grid, tmp, n, false, d)
    // GTK clips an outset shadow to outside the box's own shape: the knob's antialiased edge pixels keep only what it leaves.
    y = 0usize
    while y < n {
        var x: usize = 0usize
        while x < n {
            var inside: i32 = 0
            var sy: i32 = 0
            while sy < 8 {
                var sx: i32 = 0
                while sx < 8 {
                    let px = f32(x) + (f32(sx) + 0.5) / 8.0 - cx
                    let py = f32(y) + (f32(sy) + 0.5) / 8.0 - cy0
                    if px * px + py * py <= rr * rr { inside += 1 }
                    sx += 1
                }
                sy += 1
            }
            grid[y * n + x] = grid[y * n + x] * (1.0 - f32(inside) / 64.0)
            x += 1usize
        }
        y += 1usize
    }
    // one rectangle per run of equal levels
    var row: usize = 0usize
    while row < n {
        var col: usize = 0usize
        while col < n {
            let level = u32(grid[row * n + col] * soft.alpha * 255.0 + 0.5)
            if level == 0u32 {
                col += 1usize
                continue
            }
            var run: usize = 1usize
            while col + run < n && u32(grid[row * n + col + run] * soft.alpha * 255.0 + 0.5) == level { run += 1usize }
            let x = f32(gx0 + i32(col)) / scale
            let yy = f32(gy0 + i32(row)) / scale
            try scene.push(b, scene.Command { FillRect: scene.FillRect { rect: geometry.Rect { x: x, y: yy, width: f32(run) / scale, height: 1.0 / scale }, brush: paint.Brush { Solid: paint.rgba(0.0, 0.0, 0.0, f32(level) / 255.0) } } })
            col += run
        }
        row += 1usize
    }
    ret ok
}

// An absolute node at (x, y) over a `side` x `side` slot (the knob's own box) that paints the shadow of the disc inscribed in it, `dy` px lower.
fn soft_node(a: *mem.Arena, x: f32, y: f32, side: f32, dy: f32, alpha: f32) -> (widget.Node, err) {
    let (softs, softs_error) = mem.alloc[Soft](a, 1usize)
    if softs_error != ok { ret (zero, TooLarge) }
    softs[0usize] = Soft { arena: a, radius: side * 0.5, dy: dy, alpha: alpha, box: 3.0 }
    var fill = style.defaults()
    fill.width = style.Length { Px: side }
    fill.height = style.Length { Px: side }
    fill.position = .Absolute
    fill.margin = style.EdgeLengths { left: style.Length { Px: x }, top: style.Length { Px: y }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    var none: []const widget.Node = zero
    ret (widget.Node { key: 0u64, kind: widget.Kind { Custom: widget.Custom { ctx: mem.cast[*void](&softs[0usize]), measure: soft_measure, paint: soft_paint, state: widget.bytes_of[Soft](&softs[0usize]) } }, style: fill, children: none }, ok)
}
