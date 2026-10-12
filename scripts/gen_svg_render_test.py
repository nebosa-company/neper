"""Writes tests/selfhost/fixtures/link/gfx_svg_render (L125, D2843).

Each case is an SVG document drawn by cairosvg at 64 x 64 on white and box-reduced to
16 x 16 RGB (4 x 4 cells); the fixture renders the same document through
`e.gfx.svg` -> `e.gfx.scene` -> the CPU backend, reduces it the same way and holds the
mean and the largest cell difference to a tolerance. The documents use what the
renderer now draws beyond shapes: linear and radial gradients (bounding-box and
user-space units, stop opacity, href-inherited stops, gradientTransform), `defs` and
`use`, units and percentages, and a clip path; plus two plain-shape documents so the
older renderer is measured against the same reference.

    python scripts/gen_svg_render_test.py
"""
import io
import os
import sys

import cairosvg
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIDE = 64
CELLS = 16

CASES = [
    ("linear gradient, bounding box",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="g"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient></defs><rect x="10" y="10" width="80" height="80" fill="url(#g)"/></svg>'),
    ("linear gradient, user space, three stops, stop opacity",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="100" y2="100"><stop offset="0" stop-color="#00aa00"/><stop offset="0.5" stop-color="#ffff00" stop-opacity="0.5"/><stop offset="1" stop-color="#8000ff"/></linearGradient></defs><rect width="100" height="100" fill="url(#g)"/></svg>'),
    ("radial gradient on a circle",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><radialGradient id="r" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#0000c0"/></radialGradient></defs><circle cx="50" cy="50" r="40" fill="url(#r)"/></svg>'),
    ("gradient stroke and href stops",
     '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 100"><defs><linearGradient id="base"><stop offset="0" stop-color="#ff8000"/><stop offset="1" stop-color="#0080ff"/></linearGradient><linearGradient id="g" xlink:href="#base" x1="0" y1="0" x2="0" y2="1"/></defs><rect x="20" y="20" width="60" height="60" fill="none" stroke="url(#g)" stroke-width="12"/></svg>'),
    ("gradientTransform",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="g" gradientTransform="rotate(90 0.5 0.5)"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#ffff00"/></linearGradient></defs><rect x="10" y="10" width="80" height="80" fill="url(#g)"/></svg>'),
    ("defs and use",
     '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 100"><defs><g id="tile"><rect width="20" height="20"/><circle cx="10" cy="10" r="4" fill="#ffffff"/></g></defs><use xlink:href="#tile" x="10" y="10" fill="#ff0000"/><use href="#tile" x="40" y="40" fill="#0000ff"/><use href="#tile" x="70" y="10" fill="#008000"/></svg>'),
    ("units and percentages",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><rect x="10%" y="10" width="50%" height="30" fill="#800080"/><rect x="1in" y="2cm" width="20mm" height="15pt" fill="#ff8000"/></svg>'),
    ("clip path",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><clipPath id="c"><rect x="25" y="25" width="50" height="50"/></clipPath></defs><circle cx="50" cy="50" r="45" fill="#ff0000" clip-path="url(#c)"/></svg>'),
    ("plain shapes and strokes",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="8" y="8" width="40" height="30" rx="6" fill="#336699"/><circle cx="70" cy="30" r="18" fill="none" stroke="#cc3300" stroke-width="5"/><polygon points="20,90 50,50 80,90" fill="#009966"/><path d="M10 60 Q 30 40 50 60 T 90 60" fill="none" stroke="#000000" stroke-width="3" stroke-linecap="round"/></svg>'),
    ("icon-like path with arcs",
     '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 2 a10 10 0 1 0 0.01 0 z M12 6 v6 l4 2" fill="none" stroke="#222222" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'),
]


def reference(svg):
    png = cairosvg.svg2png(bytestring=svg.encode("utf-8"), output_width=SIDE, output_height=SIDE, background_color="white")
    im = Image.open(io.BytesIO(png)).convert("RGB")
    cell = SIDE // CELLS
    out = bytearray()
    px = im.load()
    for cy in range(CELLS):
        for cx in range(CELLS):
            sums = [0, 0, 0]
            for y in range(cell):
                for x in range(cell):
                    p = px[cx * cell + x, cy * cell + y]
                    for k in range(3):
                        sums[k] += p[k]
            out.extend(s // (cell * cell) for s in sums)
    return bytes(out)


def neper_string(data):
    return "".join("\\x%02x" % b for b in data)


def neper_text(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    lines = []
    for index, (label, svg) in enumerate(CASES):
        ref = reference(svg)
        lines.append("    // %d: %s." % (index + 1, label))
        lines.append('    if !matches(a, "%s", "%s", %di32) { os.exit(%di32) }' % (neper_text(svg), neper_string(ref), index + 1, index + 1))
    body = "\n".join(lines)
    source = TEMPLATE.replace("@@CASES@@", body)
    path = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "gfx_svg_render", "src", "main.e")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(source)
    print("wrote %d cases -> %s" % (len(CASES), path))


TEMPLATE = r'''// `e.gfx.svg` against cairosvg (L125): each document is drawn at 64 x 64 on white
// through `e.gfx.scene` and the CPU backend, reduced to 16 x 16 RGB in 4 x 4 cells and
// compared with cairosvg's reduction (scripts/gen_svg_render_test.py wrote the
// vectors). The mean absolute channel difference must stay under 3 of 255 and no cell
// may differ by more than 56 on any channel (anti-aliasing of edges lives there).
// Gradients (box and user space, three stops, stop opacity, href stops,
// gradientTransform, on stroke), defs and use, units and percentages and a clip path
// are checked, with plain shapes and a stroked icon path for the older renderer.
// Each check exits with its own code.

use e.gfx.svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gpu
use e.mem
use e.os

const SIDE: usize = 64usize
const CELLS: usize = 16usize
const CELL: i32 = 56i32

fn mean_limit() -> f32 { ret 3.0 }

fn render(a: *mem.Arena, text: str) -> ([]u32, err) {
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok { ret (zero, open_error) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret (zero, queue_error) }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok { ret (zero, frames_error) }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { ret (zero, canvas_error) }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok { ret (zero, renderer_error) }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret (zero, builder_error) }
    var builder = builder_value
    try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 64.0, 64.0), brush: paint.Brush { Solid: paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 } } } })
    try svg.draw(a, &builder, text, geometry.rect(0.0, 0.0, 64.0, 64.0), paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0 })
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { ret (zero, compile_error) }
    try scene.render(&renderer, scene_id, canvas, geometry.Size { width: 64.0, height: 64.0 })
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { ret (zero, presented_error) }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { ret (zero, pixels_error) }
    if gpu.read_image(q, image, pixels) != ok { ret (zero, gpu.OutOfMemory) }
    ret (pixels, ok)
}

// The 4 x 4 cell mean of channel `shift` (16 red, 8 green, 0 blue) at cell (cx, cy).
fn cell_mean(pixels: []const u32, cx: usize, cy: usize, shift: u32) -> i32 {
    var sum = 0u32
    var y = 0usize
    while y < 4usize {
        var x = 0usize
        while x < 4usize {
            sum += (pixels[(cy * 4usize + y) * SIDE + cx * 4usize + x] >> shift) & 255u32
            x += 1usize
        }
        y += 1usize
    }
    ret i32(sum / 16u32)
}

// Does `text` draw to within tolerance of the reference cells? `code` is for the exit.
fn matches(a: *mem.Arena, text: str, want: str, code: i32) -> bool {
    let mark = mem.mark(a)
    let (pixels, pixels_error) = render(a, text)
    if pixels_error != ok { ret false }
    var total = 0i64
    var worst = 0i32
    var cy = 0usize
    while cy < CELLS {
        var cx = 0usize
        while cx < CELLS {
            var channel = 0usize
            while channel < 3usize {
                var shift = 16u32
                if channel == 1usize { shift = 8u32 }
                if channel == 2usize { shift = 0u32 }
                let got = cell_mean(pixels, cx, cy, shift)
                var diff = got - i32(want[(cy * CELLS + cx) * 3usize + channel])
                if diff < 0i32 { diff = 0i32 - diff }
                total += i64(diff)
                if diff > worst { worst = diff }
                channel += 1usize
            }
            cx += 1usize
        }
        cy += 1usize
    }
    mem.reset(a, mark)
    let mean_diff = f32(total) / f32(CELLS * CELLS * 3usize)
    ret mean_diff <= mean_limit() && worst <= CELL
}

fn main(a: *mem.Arena, args: []str) -> err {
@@CASES@@
    // A gradient naming nothing draws nothing, and an unknown use is skipped: the
    // document is still valid.
    let (blank, blank_error) = render(a, "<svg viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\" fill=\"url(#missing)\"/><use href=\"#nothing\"/></svg>")
    if blank_error != ok { os.exit(20i32) }
    if blank[32usize * SIDE + 32usize] != 4294967295u32 { os.exit(21i32) }
    // A use cycle is refused rather than recursed into.
    let (_, cycle_error) = render(a, "<svg viewBox=\"0 0 10 10\"><defs><g id=\"g\"><use href=\"#g\"/></g></defs><use href=\"#g\"/></svg>")
    if cycle_error != svg.TooComplex { os.exit(22i32) }
    ret ok
}
'''

if __name__ == "__main__":
    main()
