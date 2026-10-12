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

    try io.print("text math ok\n")
    ret ok
}
