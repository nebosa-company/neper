// `e.gfx.scene` incremental redraw: a second frame that differs from the first only in two Text
// commands (inside a Save + Transform(scale) group, over a backdrop and rounded-rect cards that
// fully contain the text boxes) must repaint the cards under the damage box, not leave the backdrop
// colour there. The texts are hand-built layouts (no fonts); they differ in baseline.

use e.gfx.svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.gpu
use e.mem
use e.os

const SIDE: usize = 128usize
const BACKDROP: u32 = 4279506716u32
const CARD: u32 = 4294440432u32

fn solid(r: f32, g: f32, b: f32) -> paint.Brush {
    ret paint.Brush { Solid: paint.Color { red: r, green: g, blue: b, alpha: 1.0 } }
}

// A text whose layout is one empty line at `baseline`: it paints nothing, but its bounds are real.
fn text_at(a: *mem.Arena, x: f32, y: f32, baseline: f32) -> (scene.Command, err) {
    let (lines, lines_error) = mem.alloc[layout.Line](a, 1usize)
    if lines_error != ok { ret (zero, lines_error) }
    lines[0usize] = layout.Line { runs: zero, bounds: geometry.rect(0.0, 0.0, 8.0, 4.0), baseline: baseline, start: 0usize, end: 0usize }
    let (cells, cells_error) = mem.alloc[layout.Layout](a, 1usize)
    if cells_error != ok { ret (zero, cells_error) }
    cells[0usize] = layout.Layout { source: "", lines: lines, bounds: geometry.rect(0.0, 0.0, 8.0, 4.0) }
    let placed = &cells[0usize]
    ret (scene.Command { Text: scene.DrawText { layout: placed, origin: geometry.Point { x: x, y: y }, brush: solid(0.0, 0.0, 0.0) } }, ok)
}

fn card(a: *mem.Arena, b: *scene.Builder, x: f32, y: f32, w: f32, h: f32) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, 3.0, 3.0)
    if path_error != ok { ret path_error }
    try scene.push(b, scene.Command { FillPath: scene.FillPath { path: path, brush: solid(0.97, 0.96, 0.94) } })
    ret ok
}

// One frame: the same scene but for the two texts' baselines (`shift` moves both).
fn frame(a: *mem.Arena, r: *scene.Renderer, canvas: scene.Target, shift: f32) -> (scene.SceneId, err) {
    let (builder_value, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret (zero, builder_error) }
    var b = builder_value
    let save: scene.Command = .Save
    try scene.push(&b, save)
    try scene.push(&b, scene.Command { Transform: geometry.transform_scale(3.0, 3.0) })
    try scene.push(&b, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 42.0, 42.0), brush: solid(0.08, 0.09, 0.11) } })
    try card(a, &b, 1.0, 1.0, 40.0, 40.0)
    let (t0, e0) = text_at(a, 14.0, 10.0, 1.0 + shift)
    if e0 != ok { ret (zero, e0) }
    try scene.push(&b, t0)
    let (t1, e1) = text_at(a, 22.0, 28.0, 1.0 + shift)
    if e1 != ok { ret (zero, e1) }
    try scene.push(&b, t1)
    let restore: scene.Command = .Restore
    try scene.push(&b, restore)
    let (id, compile_error) = scene.compile(r, scene.finish(&b))
    ret (id, compile_error)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(1i32) }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok { os.exit(1i32) }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { os.exit(1i32) }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 2u32, 1u32)
    if renderer_error != ok { os.exit(1i32) }
    var renderer = renderer_value
    let size = geometry.Size { width: 128.0, height: 128.0 }
    let (first, first_error) = frame(a, &renderer, canvas, 0.0)
    if first_error != ok { os.exit(2i32) }
    if scene.render(&renderer, first, canvas, size) != ok { os.exit(2i32) }
    if scene.release_scene(&renderer, first) != ok { os.exit(2i32) }
    let (second, second_error) = frame(a, &renderer, canvas, 1.0)
    if second_error != ok { os.exit(3i32) }
    if scene.render(&renderer, second, canvas, size) != ok { os.exit(3i32) }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { os.exit(4i32) }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { os.exit(4i32) }
    if gpu.read_image(q, image, pixels) != ok { os.exit(4i32) }
    // Inside the first card (device 6..120 x 6..42) and under both text boxes' damage.
    if pixels[30usize * SIDE + 40usize] != CARD { os.exit(10i32) }
    if pixels[90usize * SIDE + 70usize] != CARD { os.exit(11i32) }
    // The margin outside every card keeps the backdrop.
    if pixels[2usize * SIDE + 2usize] != BACKDROP { os.exit(12i32) }
    ret ok
}
