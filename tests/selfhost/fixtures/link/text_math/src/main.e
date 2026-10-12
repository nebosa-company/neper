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
    if eq_error != ok { ret 100i32 }
    if eq.items.len != 2usize { ret 101i32 }
    if !near(eq.width, 30.4600, 0.02) || !near(eq.ascent, 14.0000, 0.02) || !near(eq.descent, 0.0000, 0.02) { ret 102i32 }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119886u32, 1u32) { ret 104i32 }
    if !is_glyph(eq.items[1usize], 15.7200, 0.0000, 20.0000, 119909u32, 3u32) { ret 104i32 }
    ret 0i32
}

// superscript after an italic correction: x^2
fn check_model_1(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "x^2", options, items)
    if eq_error != ok { ret 105i32 }
    if eq.items.len != 2usize { ret 106i32 }
    if !near(eq.width, 25.1250, 0.02) || !near(eq.ascent, 18.7100, 0.02) || !near(eq.descent, (0.0 - 0.0000), 0.02) { ret 107i32 }
    if !is_glyph(eq.items[0usize], 0.0000, 0.0000, 20.0000, 119909u32, 3u32) { ret 109i32 }
    if !is_glyph(eq.items[1usize], 15.5400, (0.0 - 8.0000), 15.0000, 50u32, 35u32) { ret 109i32 }
    ret 0i32
}

// superscript in a cramped denominator: \frac{1}{x^2}
fn check_model_2(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\frac{1}{x^2}", options, items)
    if eq_error != ok { ret 110i32 }
    if eq.items.len != 4usize { ret 111i32 }
    if !near(eq.width, 23.4940, 0.02) || !near(eq.ascent, 19.5000, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret 112i32 }
    if !is_glyph(eq.items[0usize], 8.7095, (0.0 - 9.0000), 15.0000, 49u32, 34u32) { ret 114i32 }
    if !is_glyph(eq.items[1usize], 2.4000, 8.0000, 15.0000, 119909u32, 3u32) { ret 114i32 }
    if !is_glyph(eq.items[2usize], 14.0550, 3.5000, 11.0000, 50u32, 35u32) { ret 114i32 }
    if !is_rule(eq.items[3usize], 2.4000, (0.0 - 6.6000), 18.6940, 1.2000) { ret 113i32 }
    ret 0i32
}

// the same superscript in the numerator, not cramped: \frac{x^2}{1}
fn check_model_3(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\frac{x^2}{1}", options, items)
    if eq_error != ok { ret 115i32 }
    if eq.items.len != 4usize { ret 116i32 }
    if !near(eq.width, 23.4940, 0.02) || !near(eq.ascent, 22.8540, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret 117i32 }
    if !is_glyph(eq.items[0usize], 2.4000, (0.0 - 9.0000), 15.0000, 119909u32, 3u32) { ret 119i32 }
    if !is_glyph(eq.items[1usize], 14.0550, (0.0 - 15.0000), 11.0000, 50u32, 35u32) { ret 119i32 }
    if !is_glyph(eq.items[2usize], 8.7095, 8.0000, 15.0000, 49u32, 34u32) { ret 119i32 }
    if !is_rule(eq.items[3usize], 2.4000, (0.0 - 6.6000), 18.6940, 1.2000) { ret 118i32 }
    ret 0i32
}

// radical, natural sign: \sqrt{x}
fn check_model_4(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sqrt{x}", options, items)
    if eq_error != ok { ret 120i32 }
    if eq.items.len != 3usize { ret 121i32 }
    if !near(eq.width, 31.3400, 0.02) || !near(eq.ascent, 18.1000, 0.02) || !near(eq.descent, 2.2200, 0.02) { ret 122i32 }
    if !is_glyph(eq.items[0usize], 16.6000, 0.0000, 20.0000, 119909u32, 3u32) { ret 124i32 }
    if !is_glyph(eq.items[1usize], 0.0000, (0.0 - 1.6600), 20.0000, 8730u32, 59u32) { ret 124i32 }
    if !is_rule(eq.items[2usize], 16.6000, (0.0 - 16.5000), 14.7400, 1.1000) { ret 123i32 }
    ret 0i32
}

// radical, first variant tall enough: \sqrt{x^2}
fn check_model_5(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sqrt{x^2}", options, items)
    if eq_error != ok { ret 125i32 }
    if eq.items.len != 4usize { ret 126i32 }
    if !near(eq.width, 34.2250, 0.02) || !near(eq.ascent, 20.8100, 0.02) || !near(eq.descent, (0.0 - 0.0000), 0.02) { ret 127i32 }
    if !is_glyph(eq.items[0usize], 9.1000, 0.0000, 20.0000, 119909u32, 3u32) { ret 129i32 }
    if !is_glyph(eq.items[1usize], 24.6400, (0.0 - 6.0000), 15.0000, 50u32, 35u32) { ret 129i32 }
    if !is_glyph(eq.items[2usize], 0.0000, (0.0 - 4.0900), 20.0000, 8730u32, 57u32) { ret 129i32 }
    if !is_rule(eq.items[3usize], 9.1000, (0.0 - 19.2100), 25.1250, 1.1000) { ret 128i32 }
    ret 0i32
}

// radical with an index: \sqrt[3]{x}
fn check_model_6(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sqrt[3]{x}", options, items)
    if eq_error != ok { ret 130i32 }
    if eq.items.len != 4usize { ret 131i32 }
    if !near(eq.width, 31.9730, 0.02) || !near(eq.ascent, 18.1000, 0.02) || !near(eq.descent, 2.2200, 0.02) { ret 132i32 }
    if !is_glyph(eq.items[0usize], 2.0000, (0.0 - 9.0750), 11.0000, 51u32, 36u32) { ret 134i32 }
    if !is_glyph(eq.items[1usize], 17.2330, 0.0000, 20.0000, 119909u32, 3u32) { ret 134i32 }
    if !is_glyph(eq.items[2usize], 0.6330, (0.0 - 1.6600), 20.0000, 8730u32, 59u32) { ret 134i32 }
    if !is_rule(eq.items[3usize], 17.2330, (0.0 - 16.5000), 14.7400, 1.1000) { ret 133i32 }
    ret 0i32
}

// radical over a fraction, taller variant: \sqrt{\frac{a}{b}}
fn check_model_7(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sqrt{\\frac{a}{b}}", options, items)
    if eq_error != ok { ret 135i32 }
    if eq.items.len != 5usize { ret 136i32 }
    if !near(eq.width, 25.6900, 0.02) || !near(eq.ascent, 23.6000, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret 137i32 }
    if !is_glyph(eq.items[0usize], 11.5000, (0.0 - 9.0000), 15.0000, 119886u32, 1u32) { ret 139i32 }
    if !is_glyph(eq.items[1usize], 11.6275, 8.0000, 15.0000, 119887u32, 2u32) { ret 139i32 }
    if !is_rule(eq.items[2usize], 11.5000, (0.0 - 6.6000), 11.7900, 1.2000) { ret 138i32 }
    if !is_glyph(eq.items[3usize], 0.0000, (0.0 - 6.8800), 20.0000, 8730u32, 57u32) { ret 139i32 }
    if !is_rule(eq.items[4usize], 9.1000, (0.0 - 22.0000), 16.5900, 1.1000) { ret 138i32 }
    ret 0i32
}

// parenthesis assembly: \left(\frac{a}{b}\right)
fn check_model_8(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\left(\\frac{a}{b}\\right)", options, items)
    if eq_error != ok { ret 140i32 }
    if eq.items.len != 8usize { ret 141i32 }
    if !near(eq.width, 39.2565, 0.02) || !near(eq.ascent, 19.5000, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret 142i32 }
    if !is_glyph(eq.items[0usize], 14.5800, (0.0 - 9.0000), 15.0000, 119886u32, 1u32) { ret 144i32 }
    if !is_glyph(eq.items[1usize], 14.7075, 8.0000, 15.0000, 119887u32, 2u32) { ret 144i32 }
    if !is_rule(eq.items[2usize], 14.5800, (0.0 - 6.6000), 11.7900, 1.2000) { ret 143i32 }
    if !is_glyph(eq.items[3usize], 3.2600, 4.1600, 20.0000, 40u32, 45u32) { ret 144i32 }
    if !is_glyph(eq.items[4usize], 0.0000, 3.2867, 20.0000, 40u32, 56u32) { ret 144i32 }
    if !is_glyph(eq.items[5usize], 0.0000, (0.0 - 4.2467), 20.0000, 40u32, 56u32) { ret 144i32 }
    if !is_glyph(eq.items[6usize], 3.2600, (0.0 - 14.9800), 20.0000, 40u32, 44u32) { ret 144i32 }
    if !is_glyph(eq.items[7usize], 28.7700, 1.7868, 28.4188, 41u32, 48u32) { ret 144i32 }
    ret 0i32
}

// parenthesis assembly, tall: \left(\frac{\frac{a}{b}}{\frac{a}{b}}\right)
fn check_model_9(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\left(\\frac{\\frac{a}{b}}{\\frac{a}{b}}\\right)", options, items)
    if eq_error != ok { ret 145i32 }
    if eq.items.len != 15usize { ret 146i32 }
    if !near(eq.width, 45.7423, 0.02) || !near(eq.ascent, 28.0500, 0.02) || !near(eq.descent, 16.0500, 0.02) { ret 147i32 }
    if !is_glyph(eq.items[0usize], 16.3800, (0.0 - 20.3500), 11.0000, 119886u32, 1u32) { ret 149i32 }
    if !is_glyph(eq.items[1usize], 16.4735, (0.0 - 7.6000), 11.0000, 119887u32, 2u32) { ret 149i32 }
    if !is_rule(eq.items[2usize], 16.3800, (0.0 - 18.5500), 8.6460, 0.9000) { ret 148i32 }
    if !is_glyph(eq.items[3usize], 16.3800, 3.3000, 11.0000, 119886u32, 1u32) { ret 149i32 }
    if !is_glyph(eq.items[4usize], 16.4735, 16.0500, 11.0000, 119887u32, 2u32) { ret 149i32 }
    if !is_rule(eq.items[5usize], 16.3800, 5.1000, 8.6460, 0.9000) { ret 148i32 }
    if !is_rule(eq.items[6usize], 14.5800, (0.0 - 6.6000), 12.2460, 1.2000) { ret 148i32 }
    if !is_glyph(eq.items[7usize], 3.2600, 11.8075, 20.0000, 40u32, 45u32) { ret 149i32 }
    if !is_glyph(eq.items[8usize], 0.0000, 12.1517, 20.0000, 40u32, 56u32) { ret 149i32 }
    if !is_glyph(eq.items[9usize], 0.0000, 5.8358, 20.0000, 40u32, 56u32) { ret 149i32 }
    if !is_glyph(eq.items[10usize], 0.0000, (0.0 - 0.4800), 20.0000, 40u32, 56u32) { ret 149i32 }
    if !is_glyph(eq.items[11usize], 0.0000, (0.0 - 6.7958), 20.0000, 40u32, 56u32) { ret 149i32 }
    if !is_glyph(eq.items[12usize], 0.0000, (0.0 - 13.1117), 20.0000, 40u32, 56u32) { ret 149i32 }
    if !is_glyph(eq.items[13usize], 3.2600, (0.0 - 22.6275), 20.0000, 40u32, 44u32) { ret 149i32 }
    if !is_glyph(eq.items[14usize], 29.2260, 6.2641, 44.7596, 41u32, 48u32) { ret 149i32 }
    ret 0i32
}

// display operator with limits: \sum_{a}^{b}
fn check_model_10(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sum_{a}^{b}", options, items)
    if eq_error != ok { ret 150i32 }
    if eq.items.len != 3usize { ret 151i32 }
    if !near(eq.width, 22.7852, 0.02) || !near(eq.ascent, 33.5000, 0.02) || !near(eq.descent, 22.3000, 0.02) { ret 152i32 }
    if !is_glyph(eq.items[0usize], 0.0000, 2.4899, 33.5570, 8721u32, 58u32) { ret 154i32 }
    if !is_glyph(eq.items[1usize], 5.4976, 22.3000, 15.0000, 119886u32, 1u32) { ret 154i32 }
    if !is_glyph(eq.items[2usize], 5.6251, (0.0 - 23.0000), 15.0000, 119887u32, 2u32) { ret 154i32 }
    ret 0i32
}

// text fraction: \frac{a}{b}
fn check_model_11(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: false, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\frac{a}{b}", options, items)
    if eq_error != ok { ret 155i32 }
    if eq.items.len != 3usize { ret 156i32 }
    if !near(eq.width, 16.5900, 0.02) || !near(eq.ascent, 19.5000, 0.02) || !near(eq.descent, 8.0000, 0.02) { ret 157i32 }
    if !is_glyph(eq.items[0usize], 2.4000, (0.0 - 9.0000), 15.0000, 119886u32, 1u32) { ret 159i32 }
    if !is_glyph(eq.items[1usize], 2.5275, 8.0000, 15.0000, 119887u32, 2u32) { ret 159i32 }
    if !is_rule(eq.items[2usize], 2.4000, (0.0 - 6.6000), 11.7900, 1.2000) { ret 158i32 }
    ret 0i32
}

// display fraction: \frac{a}{b}
fn check_model_12(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\frac{a}{b}", options, items)
    if eq_error != ok { ret 160i32 }
    if eq.items.len != 3usize { ret 161i32 }
    if !near(eq.width, 20.5200, 0.02) || !near(eq.ascent, 28.0000, 0.02) || !near(eq.descent, 14.4000, 0.02) { ret 162i32 }
    if !is_glyph(eq.items[0usize], 2.4000, (0.0 - 14.0000), 20.0000, 119886u32, 1u32) { ret 164i32 }
    if !is_glyph(eq.items[1usize], 2.5700, 14.4000, 20.0000, 119887u32, 2u32) { ret 164i32 }
    if !is_rule(eq.items[2usize], 2.4000, (0.0 - 6.6000), 15.7200, 1.2000) { ret 163i32 }
    ret 0i32
}

// display radical: \sqrt{x}
fn check_model_13(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\sqrt{x}", options, items)
    if eq_error != ok { ret 165i32 }
    if eq.items.len != 3usize { ret 166i32 }
    if !near(eq.width, 31.3400, 0.02) || !near(eq.ascent, 18.9000, 0.02) || !near(eq.descent, 1.4200, 0.02) { ret 167i32 }
    if !is_glyph(eq.items[0usize], 16.6000, 0.0000, 20.0000, 119909u32, 3u32) { ret 169i32 }
    if !is_glyph(eq.items[1usize], 0.0000, (0.0 - 2.4600), 20.0000, 8730u32, 59u32) { ret 169i32 }
    if !is_rule(eq.items[2usize], 16.6000, (0.0 - 17.3000), 14.7400, 1.1000) { ret 168i32 }
    ret 0i32
}

// align, two rows: \begin{align}a&=b\\cc&=d\end{align}
fn check_model_14(a: *mem.Arena, items: []math.Item, font: shape.Font) -> i32 {
    let options = math.Options { font: font, size: 20.0000, display: true, notdef: false }
    let (eq, eq_error) = math.typeset(a, "\\begin{align}a&=b\\\\cc&=d\\end{align}", options, items)
    if eq_error != ok { ret 170i32 }
    if eq.items.len != 7usize { ret 171i32 }
    if !near(eq.width, 55.8156, 0.02) || !near(eq.ascent, 29.0000, 0.02) || !near(eq.descent, 19.0000, 0.02) { ret 172i32 }
    if !is_glyph(eq.items[0usize], 11.5600, (0.0 - 12.2000), 20.0000, 97u32, 588u32) { ret 174i32 }
    if !is_glyph(eq.items[1usize], 24.1200, (0.0 - 12.2000), 20.0000, 61u32, 2397u32) { ret 174i32 }
    if !is_glyph(eq.items[2usize], 41.8556, (0.0 - 12.2000), 20.0000, 98u32, 625u32) { ret 174i32 }
    if !is_glyph(eq.items[3usize], 0.0000, 11.8000, 20.0000, 99u32, 634u32) { ret 174i32 }
    if !is_glyph(eq.items[4usize], 12.0600, 11.8000, 20.0000, 99u32, 634u32) { ret 174i32 }
    if !is_glyph(eq.items[5usize], 24.1200, 11.8000, 20.0000, 61u32, 2397u32) { ret 174i32 }
    if !is_glyph(eq.items[6usize], 41.8556, 11.8000, 20.0000, 100u32, 646u32) { ret 174i32 }
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
    failed = check_model_14(a, items, plain)
    if failed != 0i32 { ret failed }
    // MathML: sum of letters.
    failed = check_pair(a, math_font, false, "<math><mrow><mi>a</mi><mo>+</mo><mi>x</mi></mrow></math>", "a+x", 180i32)
    if failed != 0i32 { ret failed }
    // MathML: superscript.
    failed = check_pair(a, math_font, false, "<math><msup><mi>x</mi><mn>2</mn></msup></math>", "x^2", 183i32)
    if failed != 0i32 { ret failed }
    // MathML: subscript and superscript.
    failed = check_pair(a, math_font, false, "<math><msubsup><mi>x</mi><mn>1</mn><mn>2</mn></msubsup></math>", "x_1^2", 186i32)
    if failed != 0i32 { ret failed }
    // MathML: fraction.
    failed = check_pair(a, math_font, false, "<math><mfrac><mi>a</mi><mi>b</mi></mfrac></math>", "\\frac{a}{b}", 189i32)
    if failed != 0i32 { ret failed }
    // MathML: fraction of rows.
    failed = check_pair(a, math_font, false, "<math><mfrac><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow><mn>12</mn></mfrac></math>", "\\frac{a+b}{12}", 192i32)
    if failed != 0i32 { ret failed }
    // MathML: square root.
    failed = check_pair(a, math_font, false, "<math><msqrt><mi>x</mi></msqrt></math>", "\\sqrt{x}", 195i32)
    if failed != 0i32 { ret failed }
    // MathML: root with an index.
    failed = check_pair(a, math_font, false, "<math><mroot><mi>x</mi><mn>3</mn></mroot></math>", "\\sqrt[3]{x}", 198i32)
    if failed != 0i32 { ret failed }
    // MathML: fenced list.
    failed = check_pair(a, math_font, false, "<math><mfenced open=\"(\" close=\")\"><mi>a</mi><mi>b</mi></mfenced></math>", "\\left(a,b\\right)", 201i32)
    if failed != 0i32 { ret failed }
    // MathML: summation with limits.
    failed = check_pair(a, math_font, true, "<math><munderover><mo>&#x2211;</mo><mi>a</mi><mi>b</mi></munderover></math>", "\\sum_{a}^{b}", 204i32)
    if failed != 0i32 { ret failed }
    // MathML: table.
    failed = check_pair(a, math_font, false, "<math><mtable><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>x</mi></mtd><mtd><mi>y</mi></mtd></mtr></mtable></math>", "\\begin{matrix}a&b\\\\x&y\\end{matrix}", 207i32)
    if failed != 0i32 { ret failed }
    // MathML: function name and entity.
    failed = check_pair(a, math_font, false, "<math><mi>sin</mi><mo>&#x2061;</mo><mi>x</mi><mo>&#x2212;</mo><mn>1</mn></math>", "\\sin x-1", 210i32)
    if failed != 0i32 { ret failed }
    // MathML: text.
    failed = check_pair(a, math_font, false, "<math><mtext>if</mtext><mi>x</mi></math>", "\\text{if}x", 213i32)
    if failed != 0i32 { ret failed }
    // MathML that is not well formed or not in the subset is refused.
    let (_, refused_0) = math.typeset_mathml(a, "<math><mi>a</mi>", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)
    if refused_0 != math.Invalid { ret 216i32 }
    let (_, refused_1) = math.typeset_mathml(a, "<math><mfoo/></math>", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)
    if refused_1 != math.Invalid { ret 217i32 }
    let (_, refused_2) = math.typeset_mathml(a, "<math><mi>a</mi></mrow>", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)
    if refused_2 != math.Invalid { ret 218i32 }
    let (_, refused_3) = math.typeset_mathml(a, "<math><mo>&bogus;</mo></math>", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)
    if refused_3 != math.Invalid { ret 219i32 }
    let (_, refused_4) = math.typeset_mathml(a, "<math><mi>a</mi></math>trailing", math.Options { font: math_font, size: 20.0, display: false, notdef: false }, items)
    if refused_4 != math.Invalid { ret 220i32 }
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
