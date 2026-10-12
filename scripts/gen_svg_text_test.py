"""Writes tests/selfhost/fixtures/link/gfx_svg_text (L125, D3701).

`<text>` in e.gfx.svg is set through e.text.layout over a real font (Jost, the
repository's OFL face) and drawn by the scene's CPU backend. The oracle is Pillow's
FreeType rasterizer over the same font file: each document's text is drawn by Pillow at
8x on a white 8*96 x 8*48 canvas at the positions the SVG rules give (x, y baseline,
text-anchor from the advance width Pillow reports, whitespace folded, entities decoded,
a transform folded into the size and origin), box-reduced to 24 x 12 cells of 4 x 4 pixels.
The fixture renders the SVG, reduces it the same way, and holds the mean and the worst
cell difference to a tolerance.

    python scripts/gen_svg_text_test.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "neperos", "assets", "fonts", "jost-regular.ttf")
W, H, SS = 96, 48, 8
CW, CH = W // 4, H // 4

HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 48">'


def t(x, y, size, text, fill=(0, 0, 0), alpha=1.0, anchor="start", scale=1.0, dx=0.0, dy=0.0):
    return dict(x=x, y=y, size=size, text=text, fill=fill, alpha=alpha, anchor=anchor, scale=scale, dx=dx, dy=dy)


# (label, svg, [text draws])
CASES = [
    ("one run at a baseline",
     HEAD + '<text x="6" y="30" font-size="22" fill="#000000">Hello</text></svg>',
     [t(6, 30, 22, "Hello")]),
    ("text-anchor middle and fill colour",
     HEAD + '<text x="48" y="32" font-size="20" fill="#0000ff" text-anchor="middle">Jost Sans</text></svg>',
     [t(48, 32, 20, "Jost Sans", fill=(0, 0, 255), anchor="middle")]),
    ("text-anchor end with fill-opacity",
     HEAD + '<text x="90" y="28" font-size="18" fill="#c00000" fill-opacity="0.5" text-anchor="end">End</text></svg>',
     [t(90, 28, 18, "End", fill=(192, 0, 0), alpha=0.5, anchor="end")]),
    ("whitespace folded and entities decoded",
     HEAD + '<text x="4" y="30" font-size="16">  Two   words  &amp; &lt;b&gt;  </text></svg>',
     [t(4, 30, 16, "Two words & <b>")]),
    ("tspans with their own positions start new chunks",
     HEAD + '<text x="4" y="18" font-size="14">Top<tspan x="30" y="40">Low</tspan></text></svg>',
     [t(4, 18, 14, "Top"), t(30, 40, 14, "Low")]),
    ("a transform scales the size and moves the origin",
     HEAD + '<g transform="translate(10 4) scale(2)"><text x="2" y="15" font-size="10" fill="#007000">Mx</text></g></svg>',
     [t(10 + 2 * 2, 4 + 2 * 15, 10, "Mx", fill=(0, 112, 0), scale=2.0)]),
    ("a style sheet with a child combinator sets size and colour",
     HEAD + '<style>g > text{font-size:18px;fill:#800080}</style><g><text x="8" y="30">Rule</text></g><text x="8" y="44" font-size="8">plain</text></svg>',
     [t(8, 30, 18, "Rule", fill=(128, 0, 128)), t(8, 44, 8, "plain")]),
]


def reference(draws):
    im = Image.new("RGB", (W * SS, H * SS), (255, 255, 255))
    d = ImageDraw.Draw(im)
    for c in draws:
        size = c["size"] * c["scale"]
        font = ImageFont.truetype(FONT, int(round(size * SS)), layout_engine=ImageFont.Layout.RAQM)
        width = font.getlength(c["text"]) / SS
        x = c["x"]
        if c["anchor"] == "middle":
            x -= width / 2
        elif c["anchor"] == "end":
            x -= width
        col = tuple(int(round(255 * (1 - c["alpha"]) + ch * c["alpha"])) for ch in c["fill"])
        d.text((x * SS, c["y"] * SS), c["text"], font=font, fill=col, anchor="ls")
    small = im.resize((W, H), Image.BOX)
    out = bytearray()
    px = small.load()
    for cy in range(CH):
        for cx in range(CW):
            sums = [0, 0, 0]
            for y in range(4):
                for x in range(4):
                    p = px[cx * 4 + x, cy * 4 + y]
                    for k in range(3):
                        sums[k] += p[k]
            out.extend(s // 16 for s in sums)
    return bytes(out)


def neper_string(data):
    return "".join("\\x%02x" % b for b in data)


def neper_text(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    lines = []
    for index, (label, svg, draws) in enumerate(CASES):
        lines.append("    // %d: %s." % (index + 1, label))
        lines.append('    if !matches(a, device, font, "%s", "%s", %di32) { os.exit(%di32) }' % (neper_text(svg), neper_string(reference(draws)), index + 1, index + 1))
    source = TEMPLATE.replace("@@CASES@@", "\n".join(lines))
    path = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "gfx_svg_text", "src", "main.e")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(source)
    print("wrote %d cases -> %s" % (len(CASES), path))


TEMPLATE = r'''// `e.gfx.svg` text (L125, D3701): `<text>` set through `e.text.layout` over the
// repository's Jost face and drawn by the scene's CPU backend, at 96 x 48 on white,
// reduced to 24 x 12 cells of 4 x 4 pixels and compared with Pillow's FreeType rendering
// of the same string at 8x (scripts/gen_svg_text_test.py wrote the vectors): one run,
// text-anchor middle and end, fill colour and opacity, folded whitespace and decoded
// entities, tspans that start chunks, a transform on the group, and a style sheet rule
// with a child combinator. The mean absolute channel difference must stay under 1 of
// 255 (measured: at most 0.42) and no cell may differ by more than 30 (measured: at most
// 15). Each check exits with its own code.

use e.fs
use e.gfx.svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gpu
use e.mem
use e.os
use e.text.shape

const SIDE_W: usize = 96usize
const SIDE_H: usize = 48usize
const CELLS_X: usize = 24usize
const CELLS_Y: usize = 12usize

fn mean_limit() -> f32 { ret 1.0 }

fn render(a: *mem.Arena, device: *gpu.Device, font: shape.Font, text: str) -> ([]u32, err) {
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret (zero, queue_error) }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE_W), u32(SIDE_H), gpu.Format.Bgra8)
    if frames_error != ok { ret (zero, frames_error) }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { ret (zero, canvas_error) }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok { ret (zero, renderer_error) }
    var renderer = renderer_value
    try scene.register_font(&renderer, font)
    let (builder_value, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret (zero, builder_error) }
    var builder = builder_value
    try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 96.0, 48.0), brush: paint.Brush { Solid: paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 } } } })
    try svg.draw_with_font(a, &builder, text, geometry.rect(0.0, 0.0, 96.0, 48.0), paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0 }, font)
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { ret (zero, compile_error) }
    try scene.render(&renderer, scene_id, canvas, geometry.Size { width: 96.0, height: 48.0 })
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { ret (zero, presented_error) }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE_W * SIDE_H)
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
            sum += (pixels[(cy * 4usize + y) * SIDE_W + cx * 4usize + x] >> shift) & 255u32
            x += 1usize
        }
        y += 1usize
    }
    ret i32(sum / 16u32)
}

fn matches(a: *mem.Arena, device: *gpu.Device, font: shape.Font, text: str, want: str, code: i32) -> bool {
    let mark = mem.mark(a)
    let (pixels, pixels_error) = render(a, device, font, text)
    if pixels_error != ok { ret false }
    var total = 0i64
    var worst = 0i32
    var cy = 0usize
    while cy < CELLS_Y {
        var cx = 0usize
        while cx < CELLS_X {
            var channel = 0usize
            while channel < 3usize {
                var shift = 16u32
                if channel == 1usize { shift = 8u32 }
                if channel == 2usize { shift = 0u32 }
                var diff = cell_mean(pixels, cx, cy, shift) - i32(want[(cy * CELLS_X + cx) * 3usize + channel])
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
    let mean_diff = f32(total) / f32(CELLS_X * CELLS_Y * 3usize)
    ret mean_diff <= mean_limit() && worst <= 30i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (font_bytes, font_error) = fs.read_file(a, "neperos/assets/fonts/jost-regular.ttf", 1048576usize)
    if font_error != ok { os.exit(70i32) }
    let font = shape.Font { id: 1u32, data: font_bytes, face_index: 0u32 }
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok { os.exit(80i32) }
@@CASES@@
    // Without a font `<text>` draws nothing, and the document is still valid.
    let (no_font, no_font_error) = render_plain(a, device)
    if no_font_error != ok { os.exit(90i32) }
    if no_font[24usize * SIDE_W + 20usize] != 4294967295u32 { os.exit(91i32) }
    ret ok
}

fn render_plain(a: *mem.Arena, device: *gpu.Device) -> ([]u32, err) {
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret (zero, queue_error) }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE_W), u32(SIDE_H), gpu.Format.Bgra8)
    if frames_error != ok { ret (zero, frames_error) }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { ret (zero, canvas_error) }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok { ret (zero, renderer_error) }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret (zero, builder_error) }
    var builder = builder_value
    try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 96.0, 48.0), brush: paint.Brush { Solid: paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 } } } })
    try svg.draw(a, &builder, "<svg viewBox=\"0 0 96 48\"><text x=\"10\" y=\"30\" font-size=\"30\">Hello</text></svg>", geometry.rect(0.0, 0.0, 96.0, 48.0), paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0 })
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { ret (zero, compile_error) }
    try scene.render(&renderer, scene_id, canvas, geometry.Size { width: 96.0, height: 48.0 })
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { ret (zero, presented_error) }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE_W * SIDE_H)
    if pixels_error != ok { ret (zero, pixels_error) }
    if gpu.read_image(q, image, pixels) != ok { ret (zero, gpu.OutOfMemory) }
    ret (pixels, ok)
}
'''

if __name__ == "__main__":
    main()
