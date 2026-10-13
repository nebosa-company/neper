// `e.text.math` (L098): equations typeset over the repository's Montserrat font at
// size 20. The expected numbers come from scripts/gen_math_test.py, which reads the
// same font with fontTools and applies the TeXbook's rules as direct formulas: two
// ordinary atoms, a binary operator's medium space, a superscript's shift, a text and
// a display fraction, a radical, a 2x2 parenthesised matrix; then nesting (a fraction
// in a fraction takes the script styles), baseline alignment (a fraction beside
// letters keeps its bar on the axis), grown delimiters, display limits and the
// refusals. Each check exits with its own code.

use e.fs
use e.io
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gpu
use e.mem
use e.os
use e.text.shape
use e.text.math as math

fn near(x: f32, want: f32, eps: f32) -> bool {
    var d = x - want
    if d < 0.0 { d = 0.0 - d }
    ret d <= eps
}

fn rule_at(item: math.Item) -> bool {
    ret item.kind == .Rule
}

// @@GENERATED-BEGIN (scripts/gen_math_render_test.py) @@
fn math_font_path() -> str {
    ret "tests/selfhost/fixtures/link/text_math/assets/mathfont.ttf"
}

// A failed check: its code, after saying which check on stdout.
fn bad(code: i32, why: str) -> i32 {
    let said = io.print(why)
    ret code
}

fn is_glyph(item: math.Item, x: f32, y: f32, size: f32, scalar: u32, glyph: u32) -> bool {
    ret item.kind == .Glyph && near(item.x, x, 0.02) && near(item.y, y, 0.02) && near(item.size, size, 0.001) && item.scalar == scalar && item.glyph == glyph
}

fn is_rule(item: math.Item, x: f32, y: f32, w: f32, h: f32) -> bool {
    ret item.kind == .Rule && near(item.x, x, 0.02) && near(item.y, y, 0.02) && near(item.w, w, 0.02) && near(item.h, h, 0.02)
}

// Are two typesettings the same item for item, to the bit?
fn same_equation(left: math.Equation, right: math.Equation) -> bool {
    if left.items.len != right.items.len || left.width != right.width || left.ascent != right.ascent || left.descent != right.descent { ret false }
    var i = 0usize
    while i < left.items.len {
        let l = left.items[i]
        let r = right.items[i]
        if l.kind != r.kind || l.x != r.x || l.y != r.y || l.w != r.w || l.h != r.h || l.size != r.size || l.glyph != r.glyph || l.scalar != r.scalar { ret false }
        i += 1usize
    }
    ret true
}

// Presentation MathML typesets as the LaTeX it translates to, item for item.
fn check_pair(a: *mem.Arena, font: shape.Font, display: bool, mathml: str, latex: str, code: i32) -> i32 {
    let options = math.Options { font: font, size: 20.0, display: display, notdef: false }
    let (first, first_items_error) = mem.alloc[math.Item](a, 128usize)
    if first_items_error != ok { ret code }
    let (second, second_items_error) = mem.alloc[math.Item](a, 128usize)
    if second_items_error != ok { ret code }
    let (from_ml, ml_error) = math.typeset_mathml(a, mathml, options, first)
    if ml_error != ok { ret code }
    let (from_tex, tex_error) = math.typeset(a, latex, options, second)
    if tex_error != ok { ret code + 1i32 }
    if from_ml.items.len == 0usize || !same_equation(from_ml, from_tex) { ret code + 2i32 }
    ret 0i32
}

const DRAW_SIDE_W: usize = 96usize
const DRAW_SIDE_H: usize = 48usize

// `\frac{a}{b}+\sqrt{x}` drawn through the scene's CPU backend, 4 x 4 cell means against
// Pillow's 8x supersampled rendering of the same items.
fn check_draw(a: *mem.Arena, font: shape.Font, items: []math.Item) -> i32 {
    let options = math.Options { font: font, size: 22.0, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\frac{a}{b}+\\sqrt{x}", options, items)
    if eq_error != ok { ret 230i32 }
    let (text_layout, layout_error) = math.to_layout(a, eq, font)
    if layout_error != ok { ret 231i32 }
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok { ret 232i32 }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { ret 233i32 }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(DRAW_SIDE_W), u32(DRAW_SIDE_H), gpu.Format.Bgra8)
    if frames_error != ok { ret 234i32 }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { ret 235i32 }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok { ret 236i32 }
    var renderer = renderer_value
    if scene.register_font(&renderer, font) != ok { ret 237i32 }
    let (builder_value, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret 238i32 }
    var builder = builder_value
    let white = paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }
    let black = paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0 }
    if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 96.0, 48.0), brush: paint.Brush { Solid: white } } }) != ok { ret 239i32 }
    let origin = geometry.Point { x: 8.0, y: 30.0 }
    if scene.push(&builder, scene.Command { Text: scene.DrawText { layout: &text_layout, origin: origin, brush: paint.Brush { Solid: black } } }) != ok { ret 240i32 }
    var rules = 0usize
    var k = 0usize
    while k < eq.items.len {
        let item = eq.items[k]
        if item.kind == .Rule {
            rules += 1usize
            if scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(origin.x + item.x, origin.y + item.y, item.w, item.h), brush: paint.Brush { Solid: black } } }) != ok { ret 241i32 }
        }
        k += 1usize
    }
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok { ret 242i32 }
    if scene.render(&renderer, scene_id, canvas, geometry.Size { width: 96.0, height: 48.0 }) != ok { ret 243i32 }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { ret 244i32 }
    let (pixels, pixels_error) = mem.alloc[u32](a, DRAW_SIDE_W * DRAW_SIDE_H)
    if pixels_error != ok { ret 245i32 }
    if gpu.read_image(q, image, pixels) != ok { ret 246i32 }
    let want = "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\x7a\x71\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf3\x51\x22\xff\xff\xff\x9a\xc1\xff\xff\xff\xff\xff\x4f\x63\x73\x86\x93\xff\xff\xff\xff\xff\xff\xfe\xae\xb2\xff\xff\x9f\x16\x20\xcb\xff\xc5\xd6\xf3\x1a\xeb\x26\x25\xe7\xff\xff\xff\xff\xff\xff\xde\x7d\xc7\xed\xff\xff\x89\xb7\xff\xff\x72\x2e\xab\x5f\xf2\x2c\x1f\xe5\xff\xff\xff\xff\xff\xff\xe3\x2a\x68\xf6\xff\xff\xff\xff\xff\xff\xfe\x24\x3d\xb1\xc2\xab\xb2\xb5\xff\xff\xff\xff\xff\xff\xe3\x47\x5b\xd0\xff\xff\xff\xff\xff\xff\xff\x78\x0c\xf6\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf3\x9e\xa6\xfe\xff\xff\xff\xff\xff\xff\xff\xf1\xdf\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"
    var total = 0i64
    var worst = 0i32
    var cy = 0usize
    while cy < DRAW_SIDE_H / 4usize {
        var cx = 0usize
        while cx < DRAW_SIDE_W / 4usize {
            var sum = 0u32
            var y = 0usize
            while y < 4usize {
                var x = 0usize
                while x < 4usize {
                    sum += pixels[(cy * 4usize + y) * DRAW_SIDE_W + cx * 4usize + x] & 255u32
                    x += 1usize
                }
                y += 1usize
            }
            var diff = i32(sum / 16u32) - i32(want[cy * (DRAW_SIDE_W / 4usize) + cx])
            if diff < 0i32 { diff = 0i32 - diff }
            total += i64(diff)
            if diff > worst { worst = diff }
            cx += 1usize
        }
        cy += 1usize
    }
    let cells = (DRAW_SIDE_W / 4usize) * (DRAW_SIDE_H / 4usize)
    if f32(total) / f32(cells) > 3.0 { ret 247i32 }
    if worst > 70i32 { ret 248i32 }
    // A rule item is a rectangle and every other item is a glyph run of its own.
    if text_layout.lines.len != 1usize || text_layout.lines[0usize].runs.len + rules != eq.items.len { ret 249i32 }
    ret 0i32
}

// two italic letters: ax
fn check_model_0(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "ax", options, items)
    if eq_error != ok { ret bad(100i32, "check 100 (ax): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(100i32, "check 100 (ax): item count\n") }
    if !near(eq.width, 30.4600, 0.02) || !near(eq.ascent, 14.0000, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(100i32, "check 100 (ax): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(100i32, "check 100 (ax): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 15.7200, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(100i32, "check 100 (ax): glyph 1\n") }
    ret 0i32
}

// superscript after an italic correction: x^2
fn check_model_1(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "x^2", options, items)
    if eq_error != ok { ret bad(101i32, "check 101 (x^2): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(101i32, "check 101 (x^2): item count\n") }
    if !near(eq.width, 23.9250, 0.02) || !near(eq.ascent, 18.7100, 0.02) || !near(eq.descent, (0.0 - 0.0000), 0.02) { ret bad(101i32, "check 101 (x^2): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(101i32, "check 101 (x^2): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 14.3400, (0.0 - 8.0000), 15.0000, 50u32, 35u32) { ret bad(101i32, "check 101 (x^2): glyph 1\n") }
    ret 0i32
}

// superscript in a cramped denominator: \frac{1}{x^2}
fn check_model_2(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\frac{1}{x^2}", options, items)
    if eq_error != ok { ret bad(102i32, "check 102 (\\frac{1}{x^2}): typeset refused\n") }
    if eq.items.len != 4usize { ret bad(102i32, "check 102 (\\frac{1}{x^2}): item count\n") }
    if !near(eq.width, 22.5940, 0.02) || !near(eq.ascent, 19.5000, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret bad(102i32, "check 102 (\\frac{1}{x^2}): extent\n") }
    if !is_glyph(eq.items[0usize], 8.2595, (0.0 - 9.0000), 15.0000, 49u32, 34u32) { ret bad(102i32, "check 102 (\\frac{1}{x^2}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 2.4000, 8.0000, 15.0000, 119909u32, 3u32) { ret bad(102i32, "check 102 (\\frac{1}{x^2}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 13.1550, 3.5000, 11.0000, 50u32, 35u32) { ret bad(102i32, "check 102 (\\frac{1}{x^2}): glyph 2\n") }
    if !is_rule(eq.items[3usize], 2.4000, (0.0 - 6.6000), 17.7940, 1.2000) { ret bad(102i32, "check 102 (\\frac{1}{x^2}): rule 3\n") }
    ret 0i32
}

// the same superscript in the numerator, not cramped: \frac{x^2}{1}
fn check_model_3(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\frac{x^2}{1}", options, items)
    if eq_error != ok { ret bad(103i32, "check 103 (\\frac{x^2}{1}): typeset refused\n") }
    if eq.items.len != 4usize { ret bad(103i32, "check 103 (\\frac{x^2}{1}): item count\n") }
    if !near(eq.width, 22.5940, 0.02) || !near(eq.ascent, 22.8540, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret bad(103i32, "check 103 (\\frac{x^2}{1}): extent\n") }
    if !is_glyph(eq.items[0usize], 2.4000, (0.0 - 9.0000), 15.0000, 119909u32, 3u32) { ret bad(103i32, "check 103 (\\frac{x^2}{1}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 13.1550, (0.0 - 15.0000), 11.0000, 50u32, 35u32) { ret bad(103i32, "check 103 (\\frac{x^2}{1}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 8.2595, 8.0000, 15.0000, 49u32, 34u32) { ret bad(103i32, "check 103 (\\frac{x^2}{1}): glyph 2\n") }
    if !is_rule(eq.items[3usize], 2.4000, (0.0 - 6.6000), 17.7940, 1.2000) { ret bad(103i32, "check 103 (\\frac{x^2}{1}): rule 3\n") }
    ret 0i32
}

// radical, natural sign: \sqrt{x}
fn check_model_4(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sqrt{x}", options, items)
    if eq_error != ok { ret bad(104i32, "check 104 (\\sqrt{x}): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(104i32, "check 104 (\\sqrt{x}): item count\n") }
    if !near(eq.width, 31.3400, 0.02) || !near(eq.ascent, 18.1000, 0.02) || !near(eq.descent, 2.2200, 0.02) { ret bad(104i32, "check 104 (\\sqrt{x}): extent\n") }
    if !is_glyph(eq.items[0usize], 16.6000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(104i32, "check 104 (\\sqrt{x}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 0.0000, (0.0 - 1.6600), 20.0000, 8730u32, 62u32) { ret bad(104i32, "check 104 (\\sqrt{x}): glyph 1\n") }
    if !is_rule(eq.items[2usize], 16.6000, (0.0 - 16.5000), 14.7400, 1.1000) { ret bad(104i32, "check 104 (\\sqrt{x}): rule 2\n") }
    ret 0i32
}

// radical, first variant tall enough: \sqrt{x^2}
fn check_model_5(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sqrt{x^2}", options, items)
    if eq_error != ok { ret bad(105i32, "check 105 (\\sqrt{x^2}): typeset refused\n") }
    if eq.items.len != 4usize { ret bad(105i32, "check 105 (\\sqrt{x^2}): item count\n") }
    if !near(eq.width, 33.0250, 0.02) || !near(eq.ascent, 20.8100, 0.02) || !near(eq.descent, (0.0 - 0.0000), 0.02) { ret bad(105i32, "check 105 (\\sqrt{x^2}): extent\n") }
    if !is_glyph(eq.items[0usize], 9.1000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(105i32, "check 105 (\\sqrt{x^2}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 23.4400, (0.0 - 6.0000), 15.0000, 50u32, 35u32) { ret bad(105i32, "check 105 (\\sqrt{x^2}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 0.0000, (0.0 - 4.0900), 20.0000, 8730u32, 60u32) { ret bad(105i32, "check 105 (\\sqrt{x^2}): glyph 2\n") }
    if !is_rule(eq.items[3usize], 9.1000, (0.0 - 19.2100), 23.9250, 1.1000) { ret bad(105i32, "check 105 (\\sqrt{x^2}): rule 3\n") }
    ret 0i32
}

// radical with an index: \sqrt[3]{x}
fn check_model_6(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sqrt[3]{x}", options, items)
    if eq_error != ok { ret bad(106i32, "check 106 (\\sqrt[3]{x}): typeset refused\n") }
    if eq.items.len != 4usize { ret bad(106i32, "check 106 (\\sqrt[3]{x}): item count\n") }
    if !near(eq.width, 31.9730, 0.02) || !near(eq.ascent, 18.1000, 0.02) || !near(eq.descent, 2.2200, 0.02) { ret bad(106i32, "check 106 (\\sqrt[3]{x}): extent\n") }
    if !is_glyph(eq.items[0usize], 2.0000, (0.0 - 9.0750), 11.0000, 51u32, 36u32) { ret bad(106i32, "check 106 (\\sqrt[3]{x}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 17.2330, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(106i32, "check 106 (\\sqrt[3]{x}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 0.6330, (0.0 - 1.6600), 20.0000, 8730u32, 62u32) { ret bad(106i32, "check 106 (\\sqrt[3]{x}): glyph 2\n") }
    if !is_rule(eq.items[3usize], 17.2330, (0.0 - 16.5000), 14.7400, 1.1000) { ret bad(106i32, "check 106 (\\sqrt[3]{x}): rule 3\n") }
    ret 0i32
}

// radical over a fraction, taller variant: \sqrt{\frac{a}{b}}
fn check_model_7(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sqrt{\\frac{a}{b}}", options, items)
    if eq_error != ok { ret bad(107i32, "check 107 (\\sqrt{\\frac{a}{b}}): typeset refused\n") }
    if eq.items.len != 5usize { ret bad(107i32, "check 107 (\\sqrt{\\frac{a}{b}}): item count\n") }
    if !near(eq.width, 25.6900, 0.02) || !near(eq.ascent, 23.6000, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret bad(107i32, "check 107 (\\sqrt{\\frac{a}{b}}): extent\n") }
    if !is_glyph(eq.items[0usize], 11.5000, (0.0 - 9.0000), 15.0000, 119886u32, 1u32) { ret bad(107i32, "check 107 (\\sqrt{\\frac{a}{b}}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 11.6275, 8.0000, 15.0000, 119887u32, 2u32) { ret bad(107i32, "check 107 (\\sqrt{\\frac{a}{b}}): glyph 1\n") }
    if !is_rule(eq.items[2usize], 11.5000, (0.0 - 6.6000), 11.7900, 1.2000) { ret bad(107i32, "check 107 (\\sqrt{\\frac{a}{b}}): rule 2\n") }
    if !is_glyph(eq.items[3usize], 0.0000, (0.0 - 6.8800), 20.0000, 8730u32, 60u32) { ret bad(107i32, "check 107 (\\sqrt{\\frac{a}{b}}): glyph 3\n") }
    if !is_rule(eq.items[4usize], 9.1000, (0.0 - 22.0000), 16.5900, 1.1000) { ret bad(107i32, "check 107 (\\sqrt{\\frac{a}{b}}): rule 4\n") }
    ret 0i32
}

// parenthesis assembly: \left(\frac{a}{b}\right)
fn check_model_8(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\left(\\frac{a}{b}\\right)", options, items)
    if eq_error != ok { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): typeset refused\n") }
    if eq.items.len != 8usize { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): item count\n") }
    if !near(eq.width, 39.2565, 0.02) || !near(eq.ascent, 19.5000, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): extent\n") }
    if !is_glyph(eq.items[0usize], 14.5800, (0.0 - 9.0000), 15.0000, 119886u32, 1u32) { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 14.7075, 8.0000, 15.0000, 119887u32, 2u32) { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): glyph 1\n") }
    if !is_rule(eq.items[2usize], 14.5800, (0.0 - 6.6000), 11.7900, 1.2000) { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): rule 2\n") }
    if !is_glyph(eq.items[3usize], 3.2600, 4.1600, 20.0000, 40u32, 45u32) { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 0.0000, 3.2867, 20.0000, 40u32, 57u32) { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 0.0000, (0.0 - 4.2467), 20.0000, 40u32, 57u32) { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 3.2600, (0.0 - 14.9800), 20.0000, 40u32, 44u32) { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): glyph 6\n") }
    if !is_glyph(eq.items[7usize], 28.7700, 1.7868, 28.4188, 41u32, 49u32) { ret bad(108i32, "check 108 (\\left(\\frac{a}{b}\\right)): glyph 7\n") }
    ret 0i32
}

// parenthesis assembly, tall: \left(\frac{\frac{a}{b}}{\frac{a}{b}}\right)
fn check_model_9(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)", options, items)
    if eq_error != ok { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): typeset refused\n") }
    if eq.items.len != 15usize { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): item count\n") }
    if !near(eq.width, 45.7423, 0.02) || !near(eq.ascent, 28.0500, 0.02) || !near(eq.descent, 16.0500, 0.02) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): extent\n") }
    if !is_glyph(eq.items[0usize], 16.3800, (0.0 - 20.3500), 11.0000, 119886u32, 1u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 16.4735, (0.0 - 7.6000), 11.0000, 119887u32, 2u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 1\n") }
    if !is_rule(eq.items[2usize], 16.3800, (0.0 - 18.5500), 8.6460, 0.9000) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): rule 2\n") }
    if !is_glyph(eq.items[3usize], 16.3800, 3.3000, 11.0000, 119886u32, 1u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 16.4735, 16.0500, 11.0000, 119887u32, 2u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 4\n") }
    if !is_rule(eq.items[5usize], 16.3800, 5.1000, 8.6460, 0.9000) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): rule 5\n") }
    if !is_rule(eq.items[6usize], 14.5800, (0.0 - 6.6000), 12.2460, 1.2000) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): rule 6\n") }
    if !is_glyph(eq.items[7usize], 3.2600, 11.8075, 20.0000, 40u32, 45u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 7\n") }
    if !is_glyph(eq.items[8usize], 0.0000, 12.1517, 20.0000, 40u32, 57u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 8\n") }
    if !is_glyph(eq.items[9usize], 0.0000, 5.8358, 20.0000, 40u32, 57u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 9\n") }
    if !is_glyph(eq.items[10usize], 0.0000, (0.0 - 0.4800), 20.0000, 40u32, 57u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 10\n") }
    if !is_glyph(eq.items[11usize], 0.0000, (0.0 - 6.7958), 20.0000, 40u32, 57u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 11\n") }
    if !is_glyph(eq.items[12usize], 0.0000, (0.0 - 13.1117), 20.0000, 40u32, 57u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 12\n") }
    if !is_glyph(eq.items[13usize], 3.2600, (0.0 - 22.6275), 20.0000, 40u32, 44u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 13\n") }
    if !is_glyph(eq.items[14usize], 29.2260, 6.2641, 44.7596, 41u32, 49u32) { ret bad(109i32, "check 109 (\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)): glyph 14\n") }
    ret 0i32
}

// display operator with limits: \sum_{a}^{b}
fn check_model_10(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sum_{a}^{b}", options, items)
    if eq_error != ok { ret bad(110i32, "check 110 (\\sum_{a}^{b}): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(110i32, "check 110 (\\sum_{a}^{b}): item count\n") }
    if !near(eq.width, 22.7852, 0.02) || !near(eq.ascent, 33.5000, 0.02) || !near(eq.descent, 22.3000, 0.02) { ret bad(110i32, "check 110 (\\sum_{a}^{b}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 2.4899, 33.5570, 8721u32, 61u32) { ret bad(110i32, "check 110 (\\sum_{a}^{b}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 5.4976, 22.3000, 15.0000, 119886u32, 1u32) { ret bad(110i32, "check 110 (\\sum_{a}^{b}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 5.6251, (0.0 - 23.0000), 15.0000, 119887u32, 2u32) { ret bad(110i32, "check 110 (\\sum_{a}^{b}): glyph 2\n") }
    ret 0i32
}

// text fraction: \frac{a}{b}
fn check_model_11(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\frac{a}{b}", options, items)
    if eq_error != ok { ret bad(111i32, "check 111 (\\frac{a}{b}): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(111i32, "check 111 (\\frac{a}{b}): item count\n") }
    if !near(eq.width, 16.5900, 0.02) || !near(eq.ascent, 19.5000, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret bad(111i32, "check 111 (\\frac{a}{b}): extent\n") }
    if !is_glyph(eq.items[0usize], 2.4000, (0.0 - 9.0000), 15.0000, 119886u32, 1u32) { ret bad(111i32, "check 111 (\\frac{a}{b}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 2.5275, 8.0000, 15.0000, 119887u32, 2u32) { ret bad(111i32, "check 111 (\\frac{a}{b}): glyph 1\n") }
    if !is_rule(eq.items[2usize], 2.4000, (0.0 - 6.6000), 11.7900, 1.2000) { ret bad(111i32, "check 111 (\\frac{a}{b}): rule 2\n") }
    ret 0i32
}

// display fraction: \frac{a}{b}
fn check_model_12(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\frac{a}{b}", options, items)
    if eq_error != ok { ret bad(112i32, "check 112 (\\frac{a}{b}): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(112i32, "check 112 (\\frac{a}{b}): item count\n") }
    if !near(eq.width, 20.5200, 0.02) || !near(eq.ascent, 28.0000, 0.02) || !near(eq.descent, 14.4000, 0.02) { ret bad(112i32, "check 112 (\\frac{a}{b}): extent\n") }
    if !is_glyph(eq.items[0usize], 2.4000, (0.0 - 14.0000), 20.0000, 119886u32, 1u32) { ret bad(112i32, "check 112 (\\frac{a}{b}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 2.5700, 14.4000, 20.0000, 119887u32, 2u32) { ret bad(112i32, "check 112 (\\frac{a}{b}): glyph 1\n") }
    if !is_rule(eq.items[2usize], 2.4000, (0.0 - 6.6000), 15.7200, 1.2000) { ret bad(112i32, "check 112 (\\frac{a}{b}): rule 2\n") }
    ret 0i32
}

// display radical: \sqrt{x}
fn check_model_13(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sqrt{x}", options, items)
    if eq_error != ok { ret bad(113i32, "check 113 (\\sqrt{x}): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(113i32, "check 113 (\\sqrt{x}): item count\n") }
    if !near(eq.width, 31.3400, 0.02) || !near(eq.ascent, 18.9000, 0.02) || !near(eq.descent, 1.4200, 0.02) { ret bad(113i32, "check 113 (\\sqrt{x}): extent\n") }
    if !is_glyph(eq.items[0usize], 16.6000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(113i32, "check 113 (\\sqrt{x}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 0.0000, (0.0 - 2.4600), 20.0000, 8730u32, 62u32) { ret bad(113i32, "check 113 (\\sqrt{x}): glyph 1\n") }
    if !is_rule(eq.items[2usize], 16.6000, (0.0 - 17.3000), 14.7400, 1.1000) { ret bad(113i32, "check 113 (\\sqrt{x}): rule 2\n") }
    ret 0i32
}

// bold letters: \mathbf{ax}
fn check_model_14(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\mathbf{ax}", options, items)
    if eq_error != ok { ret bad(114i32, "check 114 (\\mathbf{ax}): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(114i32, "check 114 (\\mathbf{ax}): item count\n") }
    if !near(eq.width, 24.9000, 0.02) || !near(eq.ascent, 11.0200, 0.02) || !near(eq.descent, 0.1800, 0.02) { ret bad(114i32, "check 114 (\\mathbf{ax}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119834u32, 7u32) { ret bad(114i32, "check 114 (\\mathbf{ax}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 12.0600, 0.0000, 20.0000, 119857u32, 9u32) { ret bad(114i32, "check 114 (\\mathbf{ax}): glyph 1\n") }
    ret 0i32
}

// script capitals, B from Letterlike Symbols: \mathcal{AB}
fn check_model_15(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\mathcal{AB}", options, items)
    if eq_error != ok { ret bad(115i32, "check 115 (\\mathcal{AB}): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(115i32, "check 115 (\\mathcal{AB}): item count\n") }
    if !near(eq.width, 19.9400, 0.02) || !near(eq.ascent, 16.0800, 0.02) || !near(eq.descent, 4.0600, 0.02) { ret bad(115i32, "check 115 (\\mathcal{AB}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119964u32, 15u32) { ret bad(115i32, "check 115 (\\mathcal{AB}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 6.4000, 0.0000, 20.0000, 8492u32, 17u32) { ret bad(115i32, "check 115 (\\mathcal{AB}): glyph 1\n") }
    ret 0i32
}

// double-struck and fraktur holes: \mathbb{RC}\mathfrak{AC}
fn check_model_16(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\mathbb{RC}\\mathfrak{AC}", options, items)
    if eq_error != ok { ret bad(116i32, "check 116 (\\mathbb{RC}\\mathfrak{AC}): typeset refused\n") }
    if eq.items.len != 4usize { ret bad(116i32, "check 116 (\\mathbb{RC}\\mathfrak{AC}): item count\n") }
    if !near(eq.width, 49.9800, 0.02) || !near(eq.ascent, 11.0200, 0.02) || !near(eq.descent, 3.8800, 0.02) { ret bad(116i32, "check 116 (\\mathbb{RC}\\mathfrak{AC}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 8477u32, 21u32) { ret bad(116i32, "check 116 (\\mathbb{RC}\\mathfrak{AC}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 13.3200, 0.0000, 20.0000, 8450u32, 22u32) { ret bad(116i32, "check 116 (\\mathbb{RC}\\mathfrak{AC}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 27.2200, 0.0000, 20.0000, 120068u32, 23u32) { ret bad(116i32, "check 116 (\\mathbb{RC}\\mathfrak{AC}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 41.1200, 0.0000, 20.0000, 8493u32, 24u32) { ret bad(116i32, "check 116 (\\mathbb{RC}\\mathfrak{AC}): glyph 3\n") }
    ret 0i32
}

// sans, mono, bold italic, digits and a Greek letter: \mathsf{a}\mathtt{a}\boldsymbol{a}\mathbf{1}\mathtt{2}\mathbf{\alpha}
fn check_model_17(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\mathsf{a}\\mathtt{a}\\boldsymbol{a}\\mathbf{1}\\mathtt{2}\\mathbf{\\alpha}", options, items)
    if eq_error != ok { ret bad(117i32, "check 117 (\\mathsf{a}\\mathtt{a}\\boldsymbol{a}\\mathbf{1}\\mathtt{2}\\mathbf{\\alpha}): typeset refused\n") }
    if eq.items.len != 6usize { ret bad(117i32, "check 117 (\\mathsf{a}\\mathtt{a}\\boldsymbol{a}\\mathbf{1}\\mathtt{2}\\mathbf{\\alpha}): item count\n") }
    if !near(eq.width, 71.5000, 0.02) || !near(eq.ascent, 16.0800, 0.02) || !near(eq.descent, 0.1800, 0.02) { ret bad(117i32, "check 117 (\\mathsf{a}\\mathtt{a}\\boldsymbol{a}\\mathbf{1}\\mathtt{2}\\mathbf{\\alpha}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 120250u32, 25u32) { ret bad(117i32, "check 117 (\\mathsf{a}\\mathtt{a}\\boldsymbol{a}\\mathbf{1}\\mathtt{2}\\mathbf{\\alpha}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 10.9400, 0.0000, 20.0000, 120458u32, 26u32) { ret bad(117i32, "check 117 (\\mathsf{a}\\mathtt{a}\\boldsymbol{a}\\mathbf{1}\\mathtt{2}\\mathbf{\\alpha}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 19.8800, 0.0000, 20.0000, 119938u32, 27u32) { ret bad(117i32, "check 117 (\\mathsf{a}\\mathtt{a}\\boldsymbol{a}\\mathbf{1}\\mathtt{2}\\mathbf{\\alpha}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 33.7200, 0.0000, 20.0000, 120783u32, 13u32) { ret bad(117i32, "check 117 (\\mathsf{a}\\mathtt{a}\\boldsymbol{a}\\mathbf{1}\\mathtt{2}\\mathbf{\\alpha}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 39.9800, 0.0000, 20.0000, 120824u32, 29u32) { ret bad(117i32, "check 117 (\\mathsf{a}\\mathtt{a}\\boldsymbol{a}\\mathbf{1}\\mathtt{2}\\mathbf{\\alpha}): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 59.1000, 0.0000, 20.0000, 120514u32, 28u32) { ret bad(117i32, "check 117 (\\mathsf{a}\\mathtt{a}\\boldsymbol{a}\\mathbf{1}\\mathtt{2}\\mathbf{\\alpha}): glyph 5\n") }
    ret 0i32
}

// a letter the alphabet's block lacks stays itself: \mathbf{c}
fn check_model_18(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\mathbf{c}", options, items)
    if eq_error != ok { ret bad(118i32, "check 118 (\\mathbf{c}): typeset refused\n") }
    if eq.items.len != 1usize { ret bad(118i32, "check 118 (\\mathbf{c}): item count\n") }
    if !near(eq.width, 12.0600, 0.02) || !near(eq.ascent, 11.0200, 0.02) || !near(eq.descent, 0.1800, 0.02) { ret bad(118i32, "check 118 (\\mathbf{c}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 99u32, 7u32) { ret bad(118i32, "check 118 (\\mathbf{c}): glyph 0\n") }
    ret 0i32
}

// hat over a letter with an attachment point: \hat{x}
fn check_model_19(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\hat{x}", options, items)
    if eq_error != ok { ret bad(119i32, "check 119 (\\hat{x}): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(119i32, "check 119 (\\hat{x}): item count\n") }
    if !near(eq.width, 14.7400, 0.02) || !near(eq.ascent, 15.2000, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(119i32, "check 119 (\\hat{x}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(119i32, "check 119 (\\hat{x}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 3.6000, (0.0 - 4.0000), 20.0000, 770u32, 59u32) { ret bad(119i32, "check 119 (\\hat{x}): glyph 1\n") }
    ret 0i32
}

// tilde over a letter with an attachment point: \tilde{a}
fn check_model_20(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\tilde{a}", options, items)
    if eq_error != ok { ret bad(120i32, "check 120 (\\tilde{a}): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(120i32, "check 120 (\\tilde{a}): item count\n") }
    if !near(eq.width, 15.7200, 0.02) || !near(eq.ascent, 14.0000, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(120i32, "check 120 (\\tilde{a}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(120i32, "check 120 (\\tilde{a}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 0.8000, (0.0 - 4.0000), 20.0000, 771u32, 58u32) { ret bad(120i32, "check 120 (\\tilde{a}): glyph 1\n") }
    ret 0i32
}

// bar over a letter with none, and a script after it: \bar{y}^{2}
fn check_model_21(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\bar{y}^{2}", options, items)
    if eq_error != ok { ret bad(121i32, "check 121 (\\bar{y}^{2}): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(121i32, "check 121 (\\bar{y}^{2}): item count\n") }
    if !near(eq.width, 23.4450, 0.02) || !near(eq.ascent, 19.4600, 0.02) || !near(eq.descent, (0.0 - 0.0000), 0.02) { ret bad(121i32, "check 121 (\\bar{y}^{2}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119910u32, 4u32) { ret bad(121i32, "check 121 (\\bar{y}^{2}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 1.9300, (0.0 - 4.0000), 20.0000, 772u32, 47u32) { ret bad(121i32, "check 121 (\\bar{y}^{2}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 13.8600, (0.0 - 8.7500), 15.0000, 50u32, 35u32) { ret bad(121i32, "check 121 (\\bar{y}^{2}): glyph 2\n") }
    ret 0i32
}

// dot over a row: \dot{ab}
fn check_model_22(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\dot{ab}", options, items)
    if eq_error != ok { ret bad(122i32, "check 122 (\\dot{ab}): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(122i32, "check 122 (\\dot{ab}): item count\n") }
    if !near(eq.width, 31.1000, 0.02) || !near(eq.ascent, 14.0000, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(122i32, "check 122 (\\dot{ab}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(122i32, "check 122 (\\dot{ab}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 15.7200, 0.0000, 20.0000, 119887u32, 2u32) { ret bad(122i32, "check 122 (\\dot{ab}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 12.7200, (0.0 - 4.0000), 20.0000, 775u32, 44u32) { ret bad(122i32, "check 122 (\\dot{ab}): glyph 2\n") }
    ret 0i32
}

// vector arrow: \vec{x}
fn check_model_23(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\vec{x}", options, items)
    if eq_error != ok { ret bad(123i32, "check 123 (\\vec{x}): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(123i32, "check 123 (\\vec{x}): item count\n") }
    if !near(eq.width, 14.7400, 0.02) || !near(eq.ascent, 14.0000, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(123i32, "check 123 (\\vec{x}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(123i32, "check 123 (\\vec{x}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 4.7200, (0.0 - 4.0000), 20.0000, 8407u32, 46u32) { ret bad(123i32, "check 123 (\\vec{x}): glyph 1\n") }
    ret 0i32
}

// wide hat takes the widest variant: \widehat{xax}
fn check_model_24(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\widehat{xax}", options, items)
    if eq_error != ok { ret bad(124i32, "check 124 (\\widehat{xax}): typeset refused\n") }
    if eq.items.len != 4usize { ret bad(124i32, "check 124 (\\widehat{xax}): item count\n") }
    if !near(eq.width, 45.2000, 0.02) || !near(eq.ascent, 14.9800, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(124i32, "check 124 (\\widehat{xax}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(124i32, "check 124 (\\widehat{xax}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 14.7400, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(124i32, "check 124 (\\widehat{xax}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 30.4600, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(124i32, "check 124 (\\widehat{xax}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 16.5100, (0.0 - 4.0000), 20.0000, 770u32, 57u32) { ret bad(124i32, "check 124 (\\widehat{xax}): glyph 3\n") }
    ret 0i32
}

// wide hat takes the first variant that reaches: \widehat{x}
fn check_model_25(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\widehat{x}", options, items)
    if eq_error != ok { ret bad(125i32, "check 125 (\\widehat{x}): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(125i32, "check 125 (\\widehat{x}): item count\n") }
    if !near(eq.width, 14.7400, 0.02) || !near(eq.ascent, 14.9800, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(125i32, "check 125 (\\widehat{x}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(125i32, "check 125 (\\widehat{x}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 2.5100, (0.0 - 4.0000), 20.0000, 770u32, 57u32) { ret bad(125i32, "check 125 (\\widehat{x}): glyph 1\n") }
    ret 0i32
}

// wide tilde: \widetilde{ab}
fn check_model_26(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\widetilde{ab}", options, items)
    if eq_error != ok { ret bad(126i32, "check 126 (\\widetilde{ab}): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(126i32, "check 126 (\\widetilde{ab}): item count\n") }
    if !near(eq.width, 31.1000, 0.02) || !near(eq.ascent, 15.7600, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(126i32, "check 126 (\\widetilde{ab}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(126i32, "check 126 (\\widetilde{ab}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 15.7200, 0.0000, 20.0000, 119887u32, 2u32) { ret bad(126i32, "check 126 (\\widetilde{ab}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 9.4600, (0.0 - 4.0000), 20.0000, 771u32, 55u32) { ret bad(126i32, "check 126 (\\widetilde{ab}): glyph 2\n") }
    ret 0i32
}

// overline: \overline{x}
fn check_model_27(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\overline{x}", options, items)
    if eq_error != ok { ret bad(127i32, "check 127 (\\overline{x}): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(127i32, "check 127 (\\overline{x}): item count\n") }
    if !near(eq.width, 14.7400, 0.02) || !near(eq.ascent, 17.6000, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(127i32, "check 127 (\\overline{x}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(127i32, "check 127 (\\overline{x}): glyph 0\n") }
    if !is_rule(eq.items[1usize], 0.0000, (0.0 - 16.8000), 14.7400, 1.0000) { ret bad(127i32, "check 127 (\\overline{x}): rule 1\n") }
    ret 0i32
}

// underline: \underline{ab}
fn check_model_28(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\underline{ab}", options, items)
    if eq_error != ok { ret bad(128i32, "check 128 (\\underline{ab}): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(128i32, "check 128 (\\underline{ab}): item count\n") }
    if !near(eq.width, 31.1000, 0.02) || !near(eq.ascent, 14.0000, 0.02) || !near(eq.descent, 3.1000, 0.02) { ret bad(128i32, "check 128 (\\underline{ab}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(128i32, "check 128 (\\underline{ab}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 15.7200, 0.0000, 20.0000, 119887u32, 2u32) { ret bad(128i32, "check 128 (\\underline{ab}): glyph 1\n") }
    if !is_rule(eq.items[2usize], 0.0000, 1.6000, 31.1000, 0.9000) { ret bad(128i32, "check 128 (\\underline{ab}): rule 2\n") }
    ret 0i32
}

// overbrace assembled from parts: \overbrace{xaxaxa}
fn check_model_29(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\overbrace{xaxaxa}", options, items)
    if eq_error != ok { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): typeset refused\n") }
    if eq.items.len != 15usize { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): item count\n") }
    if !near(eq.width, 91.3800, 0.02) || !near(eq.ascent, 34.9200, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 14.7400, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 30.4600, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 45.2000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 60.9200, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 75.6600, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 0.0000, (0.0 - 20.0800), 20.0000, 9182u32, 48u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 6\n") }
    if !is_glyph(eq.items[7usize], 6.3000, (0.0 - 20.0800), 20.0000, 9182u32, 57u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 7\n") }
    if !is_glyph(eq.items[8usize], 17.4000, (0.0 - 20.0800), 20.0000, 9182u32, 57u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 8\n") }
    if !is_glyph(eq.items[9usize], 28.5000, (0.0 - 20.0800), 20.0000, 9182u32, 57u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 9\n") }
    if !is_glyph(eq.items[10usize], 39.6000, (0.0 - 20.0800), 20.0000, 9182u32, 57u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 10\n") }
    if !is_glyph(eq.items[11usize], 50.7000, (0.0 - 20.0800), 20.0000, 9182u32, 57u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 11\n") }
    if !is_glyph(eq.items[12usize], 61.8000, (0.0 - 20.0800), 20.0000, 9182u32, 57u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 12\n") }
    if !is_glyph(eq.items[13usize], 72.9000, (0.0 - 20.0800), 20.0000, 9182u32, 57u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 13\n") }
    if !is_glyph(eq.items[14usize], 84.0000, (0.0 - 20.0800), 20.0000, 9182u32, 49u32) { ret bad(129i32, "check 129 (\\overbrace{xaxaxa}): glyph 14\n") }
    ret 0i32
}

// overbrace with a label placed as an upper limit: \overbrace{ab}^{x}
fn check_model_30(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\overbrace{ab}^{x}", options, items)
    if eq_error != ok { ret bad(130i32, "check 130 (\\overbrace{ab}^{x}): typeset refused\n") }
    if eq.items.len != 7usize { ret bad(130i32, "check 130 (\\overbrace{ab}^{x}): item count\n") }
    if !near(eq.width, 33.1200, 0.02) || !near(eq.ascent, 47.4200, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(130i32, "check 130 (\\overbrace{ab}^{x}): extent\n") }
    if !is_glyph(eq.items[0usize], 1.0100, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(130i32, "check 130 (\\overbrace{ab}^{x}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 16.7300, 0.0000, 20.0000, 119887u32, 2u32) { ret bad(130i32, "check 130 (\\overbrace{ab}^{x}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 0.0000, (0.0 - 20.0800), 20.0000, 9182u32, 48u32) { ret bad(130i32, "check 130 (\\overbrace{ab}^{x}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 5.3800, (0.0 - 20.0800), 20.0000, 9182u32, 57u32) { ret bad(130i32, "check 130 (\\overbrace{ab}^{x}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 15.5600, (0.0 - 20.0800), 20.0000, 9182u32, 57u32) { ret bad(130i32, "check 130 (\\overbrace{ab}^{x}): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 25.7400, (0.0 - 20.0800), 20.0000, 9182u32, 49u32) { ret bad(130i32, "check 130 (\\overbrace{ab}^{x}): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 11.0325, (0.0 - 36.9200), 15.0000, 119909u32, 3u32) { ret bad(130i32, "check 130 (\\overbrace{ab}^{x}): glyph 6\n") }
    ret 0i32
}

// underbrace with a label placed as a lower limit: \underbrace{ab}_{x}
fn check_model_31(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\underbrace{ab}_{x}", options, items)
    if eq_error != ok { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): typeset refused\n") }
    if eq.items.len != 8usize { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): item count\n") }
    if !near(eq.width, 31.1000, 0.02) || !near(eq.ascent, 14.0000, 0.02) || !near(eq.descent, 33.2200, 0.02) { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 15.7200, 0.0000, 20.0000, 119887u32, 2u32) { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 0.0000, 16.0400, 20.0000, 9183u32, 52u32) { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 5.8450, 16.0400, 20.0000, 9183u32, 46u32) { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 11.6700, 16.0400, 20.0000, 9183u32, 46u32) { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 17.4950, 16.0400, 20.0000, 9183u32, 46u32) { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 23.3200, 16.0400, 20.0000, 9183u32, 53u32) { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): glyph 6\n") }
    if !is_glyph(eq.items[7usize], 10.0225, 33.2200, 15.0000, 119909u32, 3u32) { ret bad(131i32, "check 131 (\\underbrace{ab}_{x}): glyph 7\n") }
    ret 0i32
}

// superscript kerned by the base's top right and the script's bottom left: x^y
fn check_model_32(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "x^y", options, items)
    if eq_error != ok { ret bad(132i32, "check 132 (x^y): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(132i32, "check 132 (x^y): item count\n") }
    if !near(eq.width, 25.4850, 0.02) || !near(eq.ascent, 18.5000, 0.02) || !near(eq.descent, (0.0 - 0.0000), 0.02) { ret bad(132i32, "check 132 (x^y): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(132i32, "check 132 (x^y): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 14.4900, (0.0 - 8.0000), 15.0000, 119910u32, 4u32) { ret bad(132i32, "check 132 (x^y): glyph 1\n") }
    ret 0i32
}

// superscript on a base with only a top right table: a^b
fn check_model_33(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "a^b", options, items)
    if eq_error != ok { ret bad(133i32, "check 133 (a^b): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(133i32, "check 133 (a^b): item count\n") }
    if !near(eq.width, 28.3550, 0.02) || !near(eq.ascent, 18.5000, 0.02) || !near(eq.descent, (0.0 - 0.0000), 0.02) { ret bad(133i32, "check 133 (a^b): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(133i32, "check 133 (a^b): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 16.2200, (0.0 - 8.0000), 15.0000, 119887u32, 2u32) { ret bad(133i32, "check 133 (a^b): glyph 1\n") }
    ret 0i32
}

// subscript kerned by the base's bottom right and the script's top left: x_y
fn check_model_34(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "x_y", options, items)
    if eq_error != ok { ret bad(134i32, "check 134 (x_y): typeset refused\n") }
    if eq.items.len != 2usize { ret bad(134i32, "check 134 (x_y): item count\n") }
    if !near(eq.width, 24.5850, 0.02) || !near(eq.ascent, 14.0000, 0.02) || !near(eq.descent, 3.6000, 0.02) { ret bad(134i32, "check 134 (x_y): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(134i32, "check 134 (x_y): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 13.5900, 3.6000, 15.0000, 119910u32, 4u32) { ret bad(134i32, "check 134 (x_y): glyph 1\n") }
    ret 0i32
}

// both scripts, display style: x^y_y
fn check_model_35(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "x^y_y", options, items)
    if eq_error != ok { ret bad(135i32, "check 135 (x^y_y): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(135i32, "check 135 (x^y_y): item count\n") }
    if !near(eq.width, 25.4850, 0.02) || !near(eq.ascent, 18.5000, 0.02) || !near(eq.descent, 6.5000, 0.02) { ret bad(135i32, "check 135 (x^y_y): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(135i32, "check 135 (x^y_y): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 14.4900, (0.0 - 8.0000), 15.0000, 119910u32, 4u32) { ret bad(135i32, "check 135 (x^y_y): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 13.7400, 6.5000, 15.0000, 119910u32, 4u32) { ret bad(135i32, "check 135 (x^y_y): glyph 2\n") }
    ret 0i32
}

// align, two rows: \begin{align}a&=b\\cc&=d\end{align}
fn check_model_36(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\begin{align}a&=b\\\\cc&=d\\end{align}", options, items)
    if eq_error != ok { ret bad(136i32, "check 136 (\\begin{align}a&=b\\\\cc&=d\\end{align}): typeset refused\n") }
    if eq.items.len != 7usize { ret bad(136i32, "check 136 (\\begin{align}a&=b\\\\cc&=d\\end{align}): item count\n") }
    if !near(eq.width, 55.8156, 0.02) || !near(eq.ascent, 29.0000, 0.02) || !near(eq.descent, 19.0000, 0.02) { ret bad(136i32, "check 136 (\\begin{align}a&=b\\\\cc&=d\\end{align}): extent\n") }
    if !is_glyph(eq.items[0usize], 11.5600, (0.0 - 12.2000), 20.0000, 97u32, 588u32) { ret bad(136i32, "check 136 (\\begin{align}a&=b\\\\cc&=d\\end{align}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 24.1200, (0.0 - 12.2000), 20.0000, 61u32, 2397u32) { ret bad(136i32, "check 136 (\\begin{align}a&=b\\\\cc&=d\\end{align}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 41.8556, (0.0 - 12.2000), 20.0000, 98u32, 625u32) { ret bad(136i32, "check 136 (\\begin{align}a&=b\\\\cc&=d\\end{align}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 0.0000, 11.8000, 20.0000, 99u32, 634u32) { ret bad(136i32, "check 136 (\\begin{align}a&=b\\\\cc&=d\\end{align}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 12.0600, 11.8000, 20.0000, 99u32, 634u32) { ret bad(136i32, "check 136 (\\begin{align}a&=b\\\\cc&=d\\end{align}): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 24.1200, 11.8000, 20.0000, 61u32, 2397u32) { ret bad(136i32, "check 136 (\\begin{align}a&=b\\\\cc&=d\\end{align}): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 41.8556, 11.8000, 20.0000, 100u32, 646u32) { ret bad(136i32, "check 136 (\\begin{align}a&=b\\\\cc&=d\\end{align}): glyph 6\n") }
    ret 0i32
}

// a run of glyphs as a base: its last glyph's top right corner kerns the superscript: {ax}^y
fn check_model_37(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "{ax}^y", options, items)
    if eq_error != ok { ret bad(137i32, "check 137 ({ax}^y): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(137i32, "check 137 ({ax}^y): item count\n") }
    if !near(eq.width, 40.4050, 0.02) || !near(eq.ascent, 19.2500, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(137i32, "check 137 ({ax}^y): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(137i32, "check 137 ({ax}^y): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 15.7200, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(137i32, "check 137 ({ax}^y): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 29.4100, (0.0 - 8.7500), 15.0000, 119910u32, 4u32) { ret bad(137i32, "check 137 ({ax}^y): glyph 2\n") }
    ret 0i32
}

// a run of glyphs as a base: its last glyph's bottom right corner kerns the subscript: {ax}_y
fn check_model_38(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "{ax}_y", options, items)
    if eq_error != ok { ret bad(138i32, "check 138 ({ax}_y): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(138i32, "check 138 ({ax}_y): item count\n") }
    if !near(eq.width, 40.3050, 0.02) || !near(eq.ascent, 14.0000, 0.02) || !near(eq.descent, 3.6000, 0.02) { ret bad(138i32, "check 138 ({ax}_y): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(138i32, "check 138 ({ax}_y): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 15.7200, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(138i32, "check 138 ({ax}_y): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 29.3100, 3.6000, 15.0000, 119910u32, 4u32) { ret bad(138i32, "check 138 ({ax}_y): glyph 2\n") }
    ret 0i32
}

// a fraction as a base is not kerned: {\frac{a}{x}}^y
fn check_model_39(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "{\\frac{a}{x}}^y", options, items)
    if eq_error != ok { ret bad(139i32, "check 139 ({\\frac{a}{x}}^y): typeset refused\n") }
    if eq.items.len != 4usize { ret bad(139i32, "check 139 ({\\frac{a}{x}}^y): item count\n") }
    if !near(eq.width, 27.5850, 0.02) || !near(eq.ascent, 24.7500, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret bad(139i32, "check 139 ({\\frac{a}{x}}^y): extent\n") }
    if !is_glyph(eq.items[0usize], 2.4000, (0.0 - 9.0000), 15.0000, 119886u32, 1u32) { ret bad(139i32, "check 139 ({\\frac{a}{x}}^y): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 2.7675, 8.0000, 15.0000, 119909u32, 3u32) { ret bad(139i32, "check 139 ({\\frac{a}{x}}^y): glyph 1\n") }
    if !is_rule(eq.items[2usize], 2.4000, (0.0 - 6.6000), 11.7900, 1.2000) { ret bad(139i32, "check 139 ({\\frac{a}{x}}^y): rule 2\n") }
    if !is_glyph(eq.items[3usize], 16.5900, (0.0 - 14.2500), 15.0000, 119910u32, 4u32) { ret bad(139i32, "check 139 ({\\frac{a}{x}}^y): glyph 3\n") }
    ret 0i32
}

// \substack as a lower limit: \sum_{\substack{a\\b}}
fn check_model_40(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sum_{\\substack{a\\\\b}}", options, items)
    if eq_error != ok { ret bad(140i32, "check 140 (\\sum_{\\substack{a\\\\b}}): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(140i32, "check 140 (\\sum_{\\substack{a\\\\b}}): item count\n") }
    if !near(eq.width, 22.7852, 0.02) || !near(eq.ascent, 21.0000, 0.02) || !near(eq.descent, 47.8000, 0.02) { ret bad(140i32, "check 140 (\\sum_{\\substack{a\\\\b}}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 2.4899, 33.5570, 8721u32, 61u32) { ret bad(140i32, "check 140 (\\sum_{\\substack{a\\\\b}}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 5.4976, 24.4000, 15.0000, 119886u32, 1u32) { ret bad(140i32, "check 140 (\\sum_{\\substack{a\\\\b}}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 5.6251, 42.4000, 15.0000, 119887u32, 2u32) { ret bad(140i32, "check 140 (\\sum_{\\substack{a\\\\b}}): glyph 2\n") }
    ret 0i32
}

// \substack of three rows, the widest centring the others: \sum_{\substack{ax\\b\\y}}
fn check_model_41(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sum_{\\substack{ax\\\\b\\\\y}}", options, items)
    if eq_error != ok { ret bad(141i32, "check 141 (\\sum_{\\substack{ax\\\\b\\\\y}}): typeset refused\n") }
    if eq.items.len != 5usize { ret bad(141i32, "check 141 (\\sum_{\\substack{ax\\\\b\\\\y}}): item count\n") }
    if !near(eq.width, 22.8450, 0.02) || !near(eq.ascent, 21.0000, 0.02) || !near(eq.descent, 65.8000, 0.02) { ret bad(141i32, "check 141 (\\sum_{\\substack{ax\\\\b\\\\y}}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0299, 2.4899, 33.5570, 8721u32, 61u32) { ret bad(141i32, "check 141 (\\sum_{\\substack{ax\\\\b\\\\y}}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 0.0000, 24.4000, 15.0000, 119886u32, 1u32) { ret bad(141i32, "check 141 (\\sum_{\\substack{ax\\\\b\\\\y}}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 11.7900, 24.4000, 15.0000, 119909u32, 3u32) { ret bad(141i32, "check 141 (\\sum_{\\substack{ax\\\\b\\\\y}}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 5.6550, 42.4000, 15.0000, 119887u32, 2u32) { ret bad(141i32, "check 141 (\\sum_{\\substack{ax\\\\b\\\\y}}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 6.2250, 60.4000, 15.0000, 119910u32, 4u32) { ret bad(141i32, "check 141 (\\sum_{\\substack{ax\\\\b\\\\y}}): glyph 4\n") }
    ret 0i32
}

// \bigl and \bigr, 1.2 em: \bigl(x\bigr)
fn check_model_42(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\bigl(x\\bigr)", options, items)
    if eq_error != ok { ret bad(142i32, "check 142 (\\bigl(x\\bigr)): typeset refused\n") }
    if eq.items.len != 6usize { ret bad(142i32, "check 142 (\\bigl(x\\bigr)): item count\n") }
    if !near(eq.width, 36.3815, 0.02) || !near(eq.ascent, 18.0000, 0.02) || !near(eq.descent, 6.0000, 0.02) { ret bad(142i32, "check 142 (\\bigl(x\\bigr)): extent\n") }
    if !is_glyph(eq.items[0usize], 3.2600, 2.8600, 20.0000, 40u32, 45u32) { ret bad(142i32, "check 142 (\\bigl(x\\bigr)): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 0.0000, 2.8533, 20.0000, 40u32, 57u32) { ret bad(142i32, "check 142 (\\bigl(x\\bigr)): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 0.0000, (0.0 - 3.8133), 20.0000, 40u32, 57u32) { ret bad(142i32, "check 142 (\\bigl(x\\bigr)): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 3.2600, (0.0 - 13.6800), 20.0000, 40u32, 44u32) { ret bad(142i32, "check 142 (\\bigl(x\\bigr)): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 12.1800, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(142i32, "check 142 (\\bigl(x\\bigr)): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 26.9200, 1.0256, 25.6410, 41u32, 49u32) { ret bad(142i32, "check 142 (\\bigl(x\\bigr)): glyph 5\n") }
    ret 0i32
}

// \Bigl and \Bigr, 1.8 em: \Bigl(x\Bigr)
fn check_model_43(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\Bigl(x\\Bigr)", options, items)
    if eq_error != ok { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): typeset refused\n") }
    if eq.items.len != 8usize { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): item count\n") }
    if !near(eq.width, 41.1123, 0.02) || !near(eq.ascent, 24.0000, 0.02) || !near(eq.descent, 12.0000, 0.02) { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): extent\n") }
    if !is_glyph(eq.items[0usize], 3.2600, 8.8600, 20.0000, 40u32, 45u32) { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 0.0000, 9.1200, 20.0000, 40u32, 57u32) { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 0.0000, 2.7200, 20.0000, 40u32, 57u32) { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 0.0000, (0.0 - 3.6800), 20.0000, 40u32, 57u32) { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 0.0000, (0.0 - 10.0800), 20.0000, 40u32, 57u32) { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 3.2600, (0.0 - 19.6800), 20.0000, 40u32, 44u32) { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 12.1800, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): glyph 6\n") }
    if !is_glyph(eq.items[7usize], 26.9200, 4.5385, 38.4615, 41u32, 49u32) { ret bad(143i32, "check 143 (\\Bigl(x\\Bigr)): glyph 7\n") }
    ret 0i32
}

// \biggl and \biggr, 2.4 em: \biggl(x\biggr)
fn check_model_44(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\biggl(x\\biggr)", options, items)
    if eq_error != ok { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): typeset refused\n") }
    if eq.items.len != 9usize { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): item count\n") }
    if !near(eq.width, 45.8431, 0.02) || !near(eq.ascent, 30.0000, 0.02) || !near(eq.descent, 18.0000, 0.02) { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): extent\n") }
    if !is_glyph(eq.items[0usize], 3.2600, 14.8600, 20.0000, 40u32, 45u32) { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 0.0000, 14.1867, 20.0000, 40u32, 57u32) { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 0.0000, 6.8533, 20.0000, 40u32, 57u32) { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 0.0000, (0.0 - 0.4800), 20.0000, 40u32, 57u32) { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 0.0000, (0.0 - 7.8133), 20.0000, 40u32, 57u32) { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 0.0000, (0.0 - 15.1467), 20.0000, 40u32, 57u32) { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 3.2600, (0.0 - 25.6800), 20.0000, 40u32, 44u32) { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): glyph 6\n") }
    if !is_glyph(eq.items[7usize], 12.1800, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): glyph 7\n") }
    if !is_glyph(eq.items[8usize], 26.9200, 8.0513, 51.2821, 41u32, 49u32) { ret bad(144i32, "check 144 (\\biggl(x\\biggr)): glyph 8\n") }
    ret 0i32
}

// \Biggl and \Biggr, 3 em: \Biggl(x\Biggr)
fn check_model_45(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\Biggl(x\\Biggr)", options, items)
    if eq_error != ok { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): typeset refused\n") }
    if eq.items.len != 11usize { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): item count\n") }
    if !near(eq.width, 50.5738, 0.02) || !near(eq.ascent, 36.0000, 0.02) || !near(eq.descent, 24.0000, 0.02) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): extent\n") }
    if !is_glyph(eq.items[0usize], 3.2600, 20.8600, 20.0000, 40u32, 45u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 0.0000, 20.5200, 20.0000, 40u32, 57u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 0.0000, 13.5200, 20.0000, 40u32, 57u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 0.0000, 6.5200, 20.0000, 40u32, 57u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 0.0000, (0.0 - 0.4800), 20.0000, 40u32, 57u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 0.0000, (0.0 - 7.4800), 20.0000, 40u32, 57u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 0.0000, (0.0 - 14.4800), 20.0000, 40u32, 57u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 6\n") }
    if !is_glyph(eq.items[7usize], 0.0000, (0.0 - 21.4800), 20.0000, 40u32, 57u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 7\n") }
    if !is_glyph(eq.items[8usize], 3.2600, (0.0 - 31.6800), 20.0000, 40u32, 44u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 8\n") }
    if !is_glyph(eq.items[9usize], 12.1800, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 9\n") }
    if !is_glyph(eq.items[10usize], 26.9200, 11.5641, 64.1026, 41u32, 49u32) { ret bad(145i32, "check 145 (\\Biggl(x\\Biggr)): glyph 10\n") }
    ret 0i32
}

// \big alone is an ordinary atom, in a script style it keeps its size: x^{\big(}
fn check_model_46(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "x^{\\big(}", options, items)
    if eq_error != ok { ret bad(146i32, "check 146 (x^{\\big(}): typeset refused\n") }
    if eq.items.len != 5usize { ret bad(146i32, "check 146 (x^{\\big(}): item count\n") }
    if !near(eq.width, 27.7200, 0.02) || !near(eq.ascent, 26.4000, 0.02) || !near(eq.descent, (0.0 - 0.0000), 0.02) { ret bad(146i32, "check 146 (x^{\\big(}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(146i32, "check 146 (x^{\\big(}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 18.2000, (0.0 - 5.5400), 20.0000, 40u32, 45u32) { ret bad(146i32, "check 146 (x^{\\big(}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 14.9400, (0.0 - 5.5467), 20.0000, 40u32, 57u32) { ret bad(146i32, "check 146 (x^{\\big(}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 14.9400, (0.0 - 12.2133), 20.0000, 40u32, 57u32) { ret bad(146i32, "check 146 (x^{\\big(}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 18.2000, (0.0 - 22.0800), 20.0000, 40u32, 44u32) { ret bad(146i32, "check 146 (x^{\\big(}): glyph 4\n") }
    ret 0i32
}

// a tag follows the equation by an em: x^2\tag{1}
fn check_model_47(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "x^2\\tag{1}", options, items)
    if eq_error != ok { ret bad(147i32, "check 147 (x^2\\tag{1}): typeset refused\n") }
    if eq.items.len != 5usize { ret bad(147i32, "check 147 (x^2\\tag{1}): item count\n") }
    if !near(eq.width, 66.7850, 0.02) || !near(eq.ascent, 18.7100, 0.02) || !near(eq.descent, 3.8800, 0.02) { ret bad(147i32, "check 147 (x^2\\tag{1}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(147i32, "check 147 (x^2\\tag{1}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 14.3400, (0.0 - 8.0000), 15.0000, 50u32, 35u32) { ret bad(147i32, "check 147 (x^2\\tag{1}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 43.9250, 0.0000, 20.0000, 40u32, 48u32) { ret bad(147i32, "check 147 (x^2\\tag{1}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 51.3050, 0.0000, 20.0000, 49u32, 34u32) { ret bad(147i32, "check 147 (x^2\\tag{1}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 59.4050, 0.0000, 20.0000, 41u32, 49u32) { ret bad(147i32, "check 147 (x^2\\tag{1}): glyph 4\n") }
    ret 0i32
}

// a tag flush right, the equation centred when it clears the number by an em: a+b\tag{1}
fn check_model_48(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset_numbered(a, "a+b\\tag{1}", options, 200.0000, items)
    if eq_error != ok { ret bad(148i32, "check 148 (a+b\\tag{1}): typeset refused\n") }
    if eq.items.len != 6usize { ret bad(148i32, "check 148 (a+b\\tag{1}): item count\n") }
    if !near(eq.width, 200.0000, 0.02) || !near(eq.ascent, 14.8400, 0.02) || !near(eq.descent, 3.8800, 0.02) { ret bad(148i32, "check 148 (a+b\\tag{1}): extent\n") }
    if !is_glyph(eq.items[0usize], 73.9156, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(148i32, "check 148 (a+b\\tag{1}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 94.0800, 0.0000, 20.0000, 43u32, 55u32) { ret bad(148i32, "check 148 (a+b\\tag{1}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 110.7044, 0.0000, 20.0000, 119887u32, 2u32) { ret bad(148i32, "check 148 (a+b\\tag{1}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 177.1400, 0.0000, 20.0000, 40u32, 48u32) { ret bad(148i32, "check 148 (a+b\\tag{1}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 184.5200, 0.0000, 20.0000, 49u32, 34u32) { ret bad(148i32, "check 148 (a+b\\tag{1}): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 192.6200, 0.0000, 20.0000, 41u32, 49u32) { ret bad(148i32, "check 148 (a+b\\tag{1}): glyph 5\n") }
    ret 0i32
}

// an equation too near its number moves left: a+b\tag{12}
fn check_model_49(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset_numbered(a, "a+b\\tag{12}", options, 120.0000, items)
    if eq_error != ok { ret bad(149i32, "check 149 (a+b\\tag{12}): typeset refused\n") }
    if eq.items.len != 7usize { ret bad(149i32, "check 149 (a+b\\tag{12}): item count\n") }
    if !near(eq.width, 120.0000, 0.02) || !near(eq.ascent, 14.8400, 0.02) || !near(eq.descent, 3.8800, 0.02) { ret bad(149i32, "check 149 (a+b\\tag{12}): extent\n") }
    if !is_glyph(eq.items[0usize], 12.9911, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(149i32, "check 149 (a+b\\tag{12}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 33.1556, 0.0000, 20.0000, 43u32, 55u32) { ret bad(149i32, "check 149 (a+b\\tag{12}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 49.7800, 0.0000, 20.0000, 119887u32, 2u32) { ret bad(149i32, "check 149 (a+b\\tag{12}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 85.1600, 0.0000, 20.0000, 40u32, 48u32) { ret bad(149i32, "check 149 (a+b\\tag{12}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 92.5400, 0.0000, 20.0000, 49u32, 34u32) { ret bad(149i32, "check 149 (a+b\\tag{12}): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 100.6400, 0.0000, 20.0000, 50u32, 35u32) { ret bad(149i32, "check 149 (a+b\\tag{12}): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 112.6200, 0.0000, 20.0000, 41u32, 49u32) { ret bad(149i32, "check 149 (a+b\\tag{12}): glyph 6\n") }
    ret 0i32
}

// a long equation is pushed left of its number, the line grows when there is no room: a+b+x+a\tag{12}
fn check_model_50(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset_numbered(a, "a+b+x+a\\tag{12}", options, 100.0000, items)
    if eq_error != ok { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): typeset refused\n") }
    if eq.items.len != 11usize { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): item count\n") }
    if !near(eq.width, 179.6067, 0.02) || !near(eq.ascent, 14.8400, 0.02) || !near(eq.descent, 3.8800, 0.02) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 20.1644, 0.0000, 20.0000, 43u32, 55u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 36.7889, 0.0000, 20.0000, 119887u32, 2u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 56.6133, 0.0000, 20.0000, 43u32, 55u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 73.2378, 0.0000, 20.0000, 119909u32, 3u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 92.4222, 0.0000, 20.0000, 43u32, 55u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 109.0467, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 6\n") }
    if !is_glyph(eq.items[7usize], 144.7667, 0.0000, 20.0000, 40u32, 48u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 7\n") }
    if !is_glyph(eq.items[8usize], 152.1467, 0.0000, 20.0000, 49u32, 34u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 8\n") }
    if !is_glyph(eq.items[9usize], 160.2467, 0.0000, 20.0000, 50u32, 35u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 9\n") }
    if !is_glyph(eq.items[10usize], 172.2267, 0.0000, 20.0000, 41u32, 49u32) { ret bad(150i32, "check 150 (a+b+x+a\\tag{12}): glyph 10\n") }
    ret 0i32
}

// a starred tag has no parentheses: a=b\tag*{ok}
fn check_model_51(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "a=b\\tag*{ok}", options, items)
    if eq_error != ok { ret bad(151i32, "check 151 (a=b\\tag*{ok}): typeset refused\n") }
    if eq.items.len != 5usize { ret bad(151i32, "check 151 (a=b\\tag*{ok}): item count\n") }
    if !near(eq.width, 101.2511, 0.02) || !near(eq.ascent, 14.8400, 0.02) || !near(eq.descent, 0.1800, 0.02) { ret bad(151i32, "check 151 (a=b\\tag*{ok}): extent\n") }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(151i32, "check 151 (a=b\\tag*{ok}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 21.2756, 0.0000, 20.0000, 61u32, 57u32) { ret bad(151i32, "check 151 (a=b\\tag*{ok}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 39.0111, 0.0000, 20.0000, 119887u32, 2u32) { ret bad(151i32, "check 151 (a=b\\tag*{ok}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 74.3911, 0.0000, 20.0000, 111u32, 21u32) { ret bad(151i32, "check 151 (a=b\\tag*{ok}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 87.7111, 0.0000, 20.0000, 107u32, 17u32) { ret bad(151i32, "check 151 (a=b\\tag*{ok}): glyph 4\n") }
    ret 0i32
}

// without a tag the equation is centred in the line: a+b
fn check_model_52(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset_numbered(a, "a+b", options, 90.0000, items)
    if eq_error != ok { ret bad(152i32, "check 152 (a+b): typeset refused\n") }
    if eq.items.len != 3usize { ret bad(152i32, "check 152 (a+b): item count\n") }
    if !near(eq.width, 90.0000, 0.02) || !near(eq.ascent, 14.0000, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret bad(152i32, "check 152 (a+b): extent\n") }
    if !is_glyph(eq.items[0usize], 18.9156, 0.0000, 20.0000, 119886u32, 1u32) { ret bad(152i32, "check 152 (a+b): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 39.0800, 0.0000, 20.0000, 43u32, 55u32) { ret bad(152i32, "check 152 (a+b): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 55.7044, 0.0000, 20.0000, 119887u32, 2u32) { ret bad(152i32, "check 152 (a+b): glyph 2\n") }
    ret 0i32
}

// align rows are numbered in a right column: \begin{align}a&=b\tag{1}\\cc&=d\tag{2}\end{align}
fn check_model_53(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}", options, items)
    if eq_error != ok { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): typeset refused\n") }
    if eq.items.len != 13usize { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): item count\n") }
    if !near(eq.width, 102.5556, 0.02) || !near(eq.ascent, 29.0000, 0.02) || !near(eq.descent, 19.0000, 0.02) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): extent\n") }
    if !is_glyph(eq.items[0usize], 11.5600, (0.0 - 12.2000), 20.0000, 97u32, 588u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 0\n") }
    if !is_glyph(eq.items[1usize], 24.1200, (0.0 - 12.2000), 20.0000, 61u32, 2397u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 1\n") }
    if !is_glyph(eq.items[2usize], 41.8556, (0.0 - 12.2000), 20.0000, 98u32, 625u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 2\n") }
    if !is_glyph(eq.items[3usize], 0.0000, 11.8000, 20.0000, 99u32, 634u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 3\n") }
    if !is_glyph(eq.items[4usize], 12.0600, 11.8000, 20.0000, 99u32, 634u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 4\n") }
    if !is_glyph(eq.items[5usize], 24.1200, 11.8000, 20.0000, 61u32, 2397u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 5\n") }
    if !is_glyph(eq.items[6usize], 41.8556, 11.8000, 20.0000, 100u32, 646u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 6\n") }
    if !is_glyph(eq.items[7usize], 79.6956, (0.0 - 12.2000), 20.0000, 40u32, 2286u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 7\n") }
    if !is_glyph(eq.items[8usize], 87.0756, (0.0 - 12.2000), 20.0000, 49u32, 2118u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 8\n") }
    if !is_glyph(eq.items[9usize], 95.1756, (0.0 - 12.2000), 20.0000, 41u32, 2287u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 9\n") }
    if !is_glyph(eq.items[10usize], 75.8156, 11.8000, 20.0000, 40u32, 2286u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 10\n") }
    if !is_glyph(eq.items[11usize], 83.1956, 11.8000, 20.0000, 50u32, 2119u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 11\n") }
    if !is_glyph(eq.items[12usize], 95.1756, 11.8000, 20.0000, 41u32, 2287u32) { ret bad(153i32, "check 153 (\\begin{align}a&=b\\tag{1}\\\\cc&=d\\tag{2}\\end{align}): glyph 12\n") }
    ret 0i32
}

fn check_extra(a: *mem.Arena, items: []math.Item, plain: shape.Font, math_font: shape.Font) -> i32 {
    var failed = 0i32
    failed = check_model_0(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_1(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_2(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_3(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_4(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_5(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_6(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_7(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_8(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_9(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_10(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_11(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_12(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_13(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_14(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_15(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_16(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_17(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_18(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_19(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_20(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_21(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_22(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_23(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_24(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_25(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_26(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_27(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_28(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_29(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_30(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_31(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_32(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_33(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_34(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_35(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_36(a, items, plain)
    if failed != 0i32 { ret failed }
    failed = check_model_37(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_38(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_39(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_40(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_41(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_42(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_43(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_44(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_45(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_46(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_47(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_48(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_49(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_50(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_51(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_52(a, items, math_font)
    if failed != 0i32 { ret failed }
    failed = check_model_53(a, items, plain)
    if failed != 0i32 { ret failed }
    // MathML: sum of letters.
    failed = check_pair(a, math_font, false, "<math><mrow><mi>a</mi><mo>+</mo><mi>x</mi></mrow></math>", "a+x", 160i32)
    if failed != 0i32 { ret failed }
    // MathML: superscript.
    failed = check_pair(a, math_font, false, "<math><msup><mi>x</mi><mn>2</mn></msup></math>", "x^2", 163i32)
    if failed != 0i32 { ret failed }
    // MathML: subscript and superscript.
    failed = check_pair(a, math_font, false, "<math><msubsup><mi>x</mi><mn>1</mn><mn>2</mn></msubsup></math>", "x_1^2", 166i32)
    if failed != 0i32 { ret failed }
    // MathML: fraction.
    failed = check_pair(a, math_font, false, "<math><mfrac><mi>a</mi><mi>b</mi></mfrac></math>", "\\frac{a}{b}", 169i32)
    if failed != 0i32 { ret failed }
    // MathML: fraction of rows.
    failed = check_pair(a, math_font, false, "<math><mfrac><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow><mn>12</mn></mfrac></math>", "\\frac{a+b}{12}", 172i32)
    if failed != 0i32 { ret failed }
    // MathML: square root.
    failed = check_pair(a, math_font, false, "<math><msqrt><mi>x</mi></msqrt></math>", "\\sqrt{x}", 175i32)
    if failed != 0i32 { ret failed }
    // MathML: root with an index.
    failed = check_pair(a, math_font, false, "<math><mroot><mi>x</mi><mn>3</mn></mroot></math>", "\\sqrt[3]{x}", 178i32)
    if failed != 0i32 { ret failed }
    // MathML: fenced list.
    failed = check_pair(a, math_font, false, "<math><mfenced open=\"(\" close=\")\"><mi>a</mi><mi>b</mi></mfenced></math>", "\\left(a,b\\right)", 181i32)
    if failed != 0i32 { ret failed }
    // MathML: summation with limits.
    failed = check_pair(a, math_font, true, "<math><munderover><mo>&#x2211;</mo><mi>a</mi><mi>b</mi></munderover></math>", "\\sum_{a}^{b}", 184i32)
    if failed != 0i32 { ret failed }
    // MathML: table.
    failed = check_pair(a, math_font, false, "<math><mtable><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>x</mi></mtd><mtd><mi>y</mi></mtd></mtr></mtable></math>", "\\begin{matrix}a&b\\\\x&y\\end{matrix}", 187i32)
    if failed != 0i32 { ret failed }
    // MathML: function name and entity.
    failed = check_pair(a, math_font, false, "<math><mi>sin</mi><mo>&#x2061;</mo><mi>x</mi><mo>&#x2212;</mo><mn>1</mn></math>", "\\sin x-1", 190i32)
    if failed != 0i32 { ret failed }
    // MathML: text.
    failed = check_pair(a, math_font, false, "<math><mtext>if</mtext><mi>x</mi></math>", "\\text{if}x", 193i32)
    if failed != 0i32 { ret failed }
    // MathML: accented mover.
    failed = check_pair(a, math_font, false, "<math><mover accent=\"true\"><mi>x</mi><mo>^</mo></mover></math>", "\\overaccent{^}{x}", 196i32)
    if failed != 0i32 { ret failed }
    // MathML: accent from the operator without the attribute.
    failed = check_pair(a, math_font, false, "<math><mover><mi>x</mi><mo>&#x303;</mo></mover></math>", "\\overaccent{̃}{x}", 199i32)
    if failed != 0i32 { ret failed }
    // MathML: under accent.
    failed = check_pair(a, math_font, false, "<math><munder accentunder=\"true\"><mrow><mi>a</mi><mi>b</mi></mrow><mo>~</mo></munder></math>", "\\underaccent{~}{ab}", 202i32)
    if failed != 0i32 { ret failed }
    // MathML: over brace.
    failed = check_pair(a, math_font, false, "<math><mover><mrow><mi>a</mi><mi>b</mi></mrow><mo>&#x23DE;</mo></mover></math>", "\\overbrace{ab}", 205i32)
    if failed != 0i32 { ret failed }
    // MathML: under brace.
    failed = check_pair(a, math_font, false, "<math><munder><mrow><mi>a</mi><mi>b</mi></mrow><mo>&#x23DF;</mo></munder></math>", "\\underbrace{ab}", 208i32)
    if failed != 0i32 { ret failed }
    // MathML: a letter over is a script, not an accent.
    failed = check_pair(a, math_font, false, "<math><mover><mi>x</mi><mi>y</mi></mover></math>", "x^y", 211i32)
    if failed != 0i32 { ret failed }
    // MathML that is not well formed or not in the subset is refused.
    let (_, refused_0) = math.typeset_mathml(a, "<math><mi>a</mi>", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)
    if refused_0 != math.Invalid { ret 214i32 }
    let (_, refused_1) = math.typeset_mathml(a, "<math><mfoo/></math>", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)
    if refused_1 != math.Invalid { ret 215i32 }
    let (_, refused_2) = math.typeset_mathml(a, "<math><mi>a</mi></mrow>", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)
    if refused_2 != math.Invalid { ret 216i32 }
    let (_, refused_3) = math.typeset_mathml(a, "<math><mo>&bogus;</mo></math>", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)
    if refused_3 != math.Invalid { ret 217i32 }
    let (_, refused_4) = math.typeset_mathml(a, "<math><mi>a</mi></math>trailing", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)
    if refused_4 != math.Invalid { ret 218i32 }
    // The scene draws the equation.
    failed = check_draw(a, plain, items)
    if failed != 0i32 { ret failed }
    ret 0i32
}
// @@GENERATED-END @@

fn main(a: *mem.Arena, args: []str) -> err {
    let (font_bytes, font_error) = fs.read_file(a, "docs/video/neper-capabilities/fonts/Montserrat-ExtraBold.ttf", 1048576usize)
    if font_error != ok { os.exit(1) }
    let font = shape.Font { id: 1u32, data: font_bytes, face_index: 0u32 }
    let (items, items_error) = mem.alloc[math.Item](a, 128usize)
    if items_error != ok { os.exit(2) }
    let text = math.Options { font: font, size: 20.0, display: false, notdef: false }
    let display = math.Options { font: font, size: 20.0, display: true, notdef: false }

    // 1: "ab".
    let (ab, ab_error) = math.typeset(a, "ab", text, items)
    if ab_error != ok || ab.items.len != 2usize { os.exit(10) }
    if !near(ab.width, 26.46, 0.01) || !near(ab.ascent, 14.84, 0.01) || !near(ab.descent, 0.18, 0.01) { os.exit(11) }
    if !near(ab.items[1usize].x, 12.56, 0.01) || ab.items[0usize].scalar != 97u32 || ab.items[1usize].scalar != 98u32 { os.exit(12) }

    // 2: "a+b": medium space of 4/18 em around the binary operator.
    let (sum, sum_error) = math.typeset(a, "a+b", text, items)
    if sum_error != ok || sum.items.len != 3usize { os.exit(13) }
    if !near(sum.width, 47.5289, 0.01) || !near(sum.items[1usize].x, 17.0044, 0.01) || !near(sum.items[2usize].x, 33.6289, 0.01) { os.exit(14) }
    if sum.items[1usize].glyph != 2393u32 { os.exit(15) }

    // 3: "x^2".
    let (sup, sup_error) = math.typeset(a, "x^2", text, items)
    if sup_error != ok || sup.items.len != 2usize { os.exit(16) }
    if !near(sup.items[1usize].x, 12.38, 0.01) || !near(sup.items[1usize].y, 0.0 - 7.26, 0.01) || !near(sup.items[1usize].size, 14.0, 0.001) { os.exit(17) }
    if !near(sup.width, 21.766, 0.01) || !near(sup.ascent, 17.256, 0.01) { os.exit(18) }

    // 4: a text-style fraction.
    let (fraction, fraction_error) = math.typeset(a, "\\frac{1}{2}", text, items)
    if fraction_error != ok || fraction.items.len != 3usize { os.exit(19) }
    if !near(fraction.items[0usize].y, 0.0 - 7.88, 0.01) || !near(fraction.items[1usize].y, 6.9, 0.01) { os.exit(20) }
    if !near(fraction.items[0usize].x, 3.758, 0.01) || !near(fraction.items[1usize].x, 2.4, 0.01) { os.exit(21) }
    let bar = fraction.items[2usize]
    if !rule_at(bar) || !near(bar.y, 0.0 - 5.4, 0.01) || !near(bar.w, 8.386, 0.01) || !near(bar.h, 0.8, 0.001) { os.exit(22) }
    if !near(fraction.width, 13.186, 0.01) || !near(fraction.ascent, 17.68, 0.01) { os.exit(23) }

    // 5: the display fraction: larger shifts, children at full size.
    let (wide, wide_error) = math.typeset(a, "\\frac{1}{2}", display, items)
    if wide_error != ok { os.exit(24) }
    if !near(wide.items[0usize].y, 0.0 - 13.54, 0.01) || !near(wide.items[1usize].y, 13.72, 0.01) || !near(wide.items[0usize].size, 20.0, 0.001) { os.exit(25) }
    if !near(wide.ascent, 27.54, 0.01) { os.exit(26) }

    // 6: a radical: sign, then the radicand under a bar.
    let (root, root_error) = math.typeset(a, "\\sqrt{x}", text, items)
    if root_error != ok || root.items.len != 3usize { os.exit(27) }
    if !near(root.items[0usize].x, 16.6, 0.01) || root.items[1usize].scalar != 8730u32 || !near(root.items[1usize].size, 20.0, 0.001) { os.exit(28) }
    let overbar = root.items[2usize]
    if !rule_at(overbar) || !near(overbar.x, 16.6, 0.01) || !near(overbar.y, 0.0 - 12.64, 0.01) || !near(overbar.h, 0.8, 0.001) { os.exit(29) }
    if !near(root.ascent, 12.64, 0.01) { os.exit(30) }

    // 7: a parenthesised 2x2 matrix.
    let (matrix, matrix_error) = math.typeset(a, "\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}", text, items)
    if matrix_error != ok || matrix.items.len != 6usize { os.exit(31) }
    if !near(matrix.ascent, 29.0, 0.01) || !near(matrix.descent, 19.0, 0.01) { os.exit(32) }
    if !near(matrix.items[0usize].y, 0.0 - 12.2, 0.01) || !near(matrix.items[2usize].y, 11.8, 0.01) { os.exit(33) }
    let left_fence = matrix.items[4usize]
    let right_fence = matrix.items[5usize]
    if left_fence.scalar != 40u32 || right_fence.scalar != 41u32 || left_fence.size <= 40.0 { os.exit(34) }
    // Cells of one column share a centre; the column is a em from the next.
    if !near(matrix.items[1usize].x - matrix.items[0usize].x, 33.07 - 1.98, 0.01) { os.exit(35) }

    // 8: nesting. In text style the outer numerator is script, the inner fraction's
    // parts scriptscript; the radical's index is scriptscript too.
    let (nested, nested_error) = math.typeset(a, "\\frac{\\frac{a}{b}}{c}", text, items)
    if nested_error != ok { os.exit(36) }
    if !near(nested.items[0usize].size, 10.0, 0.001) || !near(nested.items[1usize].size, 10.0, 0.001) { os.exit(37) }
    if !near(nested.items[3usize].size, 14.0, 0.001) { os.exit(38) }
    let (indexed, indexed_error) = math.typeset(a, "\\sqrt[3]{x+1}", text, items)
    if indexed_error != ok || !near(indexed.items[0usize].size, 10.0, 0.001) { os.exit(39) }

    // 9: baseline alignment. A fraction between letters leaves the letters on the
    // baseline and puts its bar on the math axis (0.25 em plus half the rule).
    let (aligned, aligned_error) = math.typeset(a, "a\\frac{1}{2}b", text, items)
    if aligned_error != ok || aligned.items.len != 5usize { os.exit(40) }
    if aligned.items[0usize].y != 0.0 || aligned.items[4usize].y != 0.0 { os.exit(41) }
    if !rule_at(aligned.items[3usize]) || !near(aligned.items[3usize].y, 0.0 - 5.4, 0.01) { os.exit(42) }

    // 10: \left( \right) grows with a fraction; the delimiters are centred on the axis.
    let (fenced, fenced_error) = math.typeset(a, "\\left(\\frac{a}{b}\\right)", text, items)
    if fenced_error != ok { os.exit(43) }
    if fenced.items[3usize].scalar != 40u32 || fenced.items[3usize].size <= 22.0 { os.exit(44) }
    if fenced.items[3usize].x != 0.0 { os.exit(45) }

    // 11: display limits: the operator is larger, the limits sit above and below it
    // centred on its width; as a text-style script they would sit beside it.
    let (limits, limits_error) = math.typeset(a, "\\sum_{i}^{n}", display, items)
    if limits_error != ok || limits.items.len != 3usize { os.exit(46) }
    if !near(limits.items[0usize].size, 28.0, 0.001) || limits.items[0usize].scalar != 8721u32 { os.exit(47) }
    if limits.items[1usize].y <= 0.0 || limits.items[2usize].y >= 0.0 { os.exit(48) }
    if !near(limits.items[2usize].x + limits.items[2usize].w / 2.0, limits.items[0usize].x + limits.items[0usize].w / 2.0, 0.05) { os.exit(49) }
    let (beside, beside_error) = math.typeset(a, "\\sum_{i}^{n}", text, items)
    if beside_error != ok || !near(beside.items[1usize].x, beside.items[0usize].w, 0.05) { os.exit(50) }

    // 12: refusals.
    let (_, brace_error) = math.typeset(a, "{a", text, items)
    if brace_error != math.Invalid { os.exit(51) }
    let (_, close_error) = math.typeset(a, "a}", text, items)
    if close_error != math.Invalid { os.exit(52) }
    let (_, unknown_error) = math.typeset(a, "\\foo", text, items)
    if unknown_error != math.Invalid { os.exit(53) }
    let (_, missing_error) = math.typeset(a, "\\alpha", text, items)
    if missing_error != math.MissingGlyph { os.exit(54) }
    let lenient = math.Options { font: font, size: 20.0, display: false, notdef: true }
    let (alpha, alpha_error) = math.typeset(a, "\\alpha", lenient, items)
    if alpha_error != ok || alpha.items.len != 1usize || alpha.items[0usize].glyph != 0u32 { os.exit(55) }
    let (_, small_error) = math.typeset(a, "abc", text, items[..2usize])
    if small_error != math.TooSmall { os.exit(56) }
    let (_, deep_error) = math.typeset(a, "{{{{{{{{{{{{{{{{{{{{{{{{{{{{a}}}}}}}}}}}}}}}}}}}}}}}}}}}}", text, items)
    if deep_error != math.TooDeep { os.exit(57) }
    let (_, environment_error) = math.typeset(a, "\\begin{foo}a\\end{foo}", text, items)
    if environment_error != math.Invalid { os.exit(58) }
    let (_, mismatch_error) = math.typeset(a, "\\begin{matrix}a\\end{pmatrix}", text, items)
    if mismatch_error != math.Invalid { os.exit(59) }
    let (_, twice_error) = math.typeset(a, "x^1^2", text, items)
    if twice_error != math.Invalid { os.exit(60) }
    let (_, empty_error) = math.typeset(a, "", text, items)
    if empty_error != math.Invalid { os.exit(61) }
    let flat = math.Options { font: font, size: 0.0, display: false, notdef: false }
    let (_, size_error) = math.typeset(a, "a", flat, items)
    if size_error != math.Invalid { os.exit(62) }
    let broken = shape.Font { id: 2u32, data: font_bytes[..16usize], face_index: 0u32 }
    let (_, font_refused) = math.typeset(a, "a", math.Options { font: broken, size: 20.0, display: false, notdef: false }, items)
    if font_refused != math.Invalid { os.exit(63) }

    // The MATH-table, cramped-style, assembly, align, MathML and drawing checks, whose
    // numbers scripts/gen_math_render_test.py computes from a separate model.
    let (math_bytes, math_font_error) = fs.read_file(a, math_font_path(), 1048576usize)
    if math_font_error != ok { os.exit(64) }
    let math_font = shape.Font { id: 3u32, data: math_bytes, face_index: 0u32 }
    let extra = check_extra(a, items, font, math_font)
    if extra != 0i32 { os.exit(extra) }

    try io.print("text math ok\n")
    ret ok
}
