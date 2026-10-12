// Math typesetting over `e.text.shape` (L098): a LaTeX-math subset parsed and laid
// out in one pass into a flat list of positioned glyphs and rules in caller storage,
// for scene and SVG adapters. The model is TeX's: atoms of a class (ordinary,
// operator, binary, relation, open, close, punctuation, inner) with the inter-atom
// space table of the TeXbook, four styles (display, text, script, scriptscript) at
// 1, 1, 0.7 and 0.5 of the size, fractions, radicals with an optional index, super-
// and subscripts with the rule 18 shifts, big operators with limits in display
// style, `\left` `\right` delimiters grown to the content, and `matrix`, `pmatrix`,
// `bmatrix`, `Bmatrix`, `vmatrix` and `cases` environments.
//
// Coordinates are in the caller's size units, origin at the equation's left edge on
// its baseline, y growing downward: a glyph's `y` is its baseline, a rule's `y` its
// top edge. Glyph extents come from the font's `glyf` bounding boxes when it is a
// TrueType outline font (otherwise a character is taken as 0.7 em tall); the axis,
// rule thickness and the shift constants are TeX's cmsy values as fractions of the
// em, since a plain text font has no MATH table. ponytail: a font's own MATH
// constants, italic correction, extensible-glyph assembly and cramped styles are
// the upgrades; a delimiter or radical is the font's glyph scaled to the content.
//
// Input: source is UTF-8; `\` commands are those below; spaces are ignored. A
// command or environment this subset does not know is `Invalid`, as is an unbalanced
// brace; a character the font lacks is `MissingGlyph` unless `options.notdef`
// accepts its glyph 0; `items` too short is `TooSmall`; nesting past 24 is `TooDeep`.
//
// Commands: `\frac{}{}` `\sqrt{}` `\sqrt[n]{}` `\left` `\right` (with `.` as the
// empty delimiter) `\begin{env}` `\end{env}` with `&` and `\\` `\text{}` `\mathrm{}`
// `\sum` `\prod` `\int` `\lim` `\sin` `\cos` `\tan` `\log` `\ln` `\exp` `\min` `\max`,
// the Greek letters, `\pm` `\times` `\div` `\cdot` `\leq` `\geq` `\neq` `\approx`
// `\equiv` `\to` `\leftarrow` `\infty` `\partial` `\nabla` `\in` `\ldots` `\forall`
// `\exists`, the spaces `\,` `\:` `\;` `\quad` `\qquad` `\!`, and `\{` `\}`.

use e.mem
use e.text.shape
use e.text.unicode

type Kind = enum u8 { Glyph, Rule }
type Item = struct { kind: Kind, x: f32, y: f32, w: f32, h: f32, size: f32, glyph: u32, scalar: u32 }
type Equation = struct { items: []const Item, width: f32, ascent: f32, descent: f32 }
type Options = struct { font: shape.Font, size: f32, display: bool, notdef: bool }
error Invalid
error MissingGlyph
error TooSmall
error TooDeep

const NONE: usize = 18446744073709551615usize
const MAX_NEST: usize = 24usize
const CLASS_ORD: u8 = 0u8
const CLASS_OP: u8 = 1u8
const CLASS_BIN: u8 = 2u8
const CLASS_REL: u8 = 3u8
const CLASS_OPEN: u8 = 4u8
const CLASS_CLOSE: u8 = 5u8
const CLASS_PUNCT: u8 = 6u8
const CLASS_INNER: u8 = 7u8
const CLASS_SPACE: u8 = 8u8

// A laid-out piece: its items are `first..last` of the shared list, positioned
// relative to its own origin on the baseline.
type Atom = struct { class: u8, first: usize, last: usize, width: f32, height: f32, depth: f32, simple: bool, limits: bool }

type Ctx = struct {
    a: *mem.Arena,
    font: shape.Font,
    items: []Item,
    count: usize,
    src: str,
    pos: usize,
    size: f32,
    display: bool,
    notdef: bool,
    status: err,
    nest: usize,
    upem: f32,
    x_height: f32,
    head_at: usize,
    loca_at: usize,
    glyf_at: usize,
    maxp_at: usize,
}

fn maxf(x: f32, y: f32) -> f32 {
    if x > y { ret x }
    ret y
}

fn be16(d: []const u8, at: usize) -> u32 {
    if at + 2usize > d.len { ret 0u32 }
    ret (u32(d[at]) << 8u32) | u32(d[at + 1usize])
}

fn be16s(d: []const u8, at: usize) -> i32 {
    let v = i32(be16(d, at))
    if v >= 32768i32 { ret v - 65536i32 }
    ret v
}

fn be32(d: []const u8, at: usize) -> u32 {
    if at + 4usize > d.len { ret 0u32 }
    ret (u32(d[at]) << 24u32) | (u32(d[at + 1usize]) << 16u32) | (u32(d[at + 2usize]) << 8u32) | u32(d[at + 3usize])
}

fn find_table(d: []const u8, tag: u32) -> usize {
    let count = usize(be16(d, 4usize))
    var i = 0usize
    while i < count {
        let record = 12usize + 16usize * i
        if be32(d, record) == tag { ret usize(be32(d, record + 8usize)) }
        i += 1usize
    }
    ret NONE
}

// The vertical extent (ymin, ymax) of a glyph, in ems.
fn glyph_extent(c: *Ctx, id: u32) -> (f32, f32) {
    let d = c.font.data
    if c.glyf_at == NONE || c.loca_at == NONE || c.head_at == NONE || c.maxp_at == NONE || c.upem <= 0.0 { ret (0.0 - 0.2, 0.7) }
    if id >= be16(d, c.maxp_at + 4usize) { ret (0.0, 0.0) }
    var first = 0usize
    var second = 0usize
    if be16(d, c.head_at + 50usize) == 0u32 {
        first = usize(be16(d, c.loca_at + 2usize * usize(id))) * 2usize
        second = usize(be16(d, c.loca_at + 2usize * usize(id) + 2usize)) * 2usize
    } else {
        first = usize(be32(d, c.loca_at + 4usize * usize(id)))
        second = usize(be32(d, c.loca_at + 4usize * usize(id) + 4usize))
    }
    if second <= first { ret (0.0, 0.0) }
    let g = c.glyf_at + first
    ret (f32(be16s(d, g + 4usize)) / c.upem, f32(be16s(d, g + 8usize)) / c.upem)
}

fn style_scale(style: u32) -> f32 {
    if style >= 3u32 { ret 0.5 }
    if style == 2u32 { ret 0.7 }
    ret 1.0
}

fn script_style(style: u32) -> u32 {
    if style < 2u32 { ret 2u32 }
    ret 3u32
}

fn fraction_style(style: u32) -> u32 {
    if style >= 3u32 { ret 3u32 }
    ret style + 1u32
}

fn push_item(c: *Ctx, item: Item) {
    if c.status != ok { ret }
    if c.count >= c.items.len {
        c.status = TooSmall
        ret
    }
    c.items[c.count] = item
    c.count += 1usize
}

fn shift_range(c: *Ctx, first: usize, last: usize, dx: f32, dy: f32) {
    var i = first
    while i < last {
        c.items[i].x += dx
        c.items[i].y += dy
        i += 1usize
    }
}

fn byte_at(c: *Ctx, at: usize) -> u8 {
    if at >= c.src.len { ret 0u8 }
    ret c.src[at]
}

fn skip_space(c: *Ctx) {
    while c.pos < c.src.len && (c.src[c.pos] == 32u8 || c.src[c.pos] == 10u8 || c.src[c.pos] == 9u8 || c.src[c.pos] == 13u8) { c.pos += 1usize }
}

fn word_is(word: str, want: str) -> bool {
    if word.len != want.len { ret false }
    var i = 0usize
    while i < word.len {
        if word[i] != want[i] { ret false }
        i += 1usize
    }
    ret true
}

// Does the source continue with `\` and `word` at the cursor (not followed by a letter)?
fn at_command(c: *Ctx, word: str) -> bool {
    if byte_at(c, c.pos) != 92u8 { ret false }
    var i = 0usize
    while i < word.len {
        if byte_at(c, c.pos + 1usize + i) != word[i] { ret false }
        i += 1usize
    }
    let next = byte_at(c, c.pos + 1usize + word.len)
    ret !((next >= 97u8 && next <= 122u8) || (next >= 65u8 && next <= 90u8))
}

fn ends_row(c: *Ctx) -> bool {
    if c.pos >= c.src.len { ret true }
    let ch = c.src[c.pos]
    if ch == 125u8 || ch == 38u8 { ret true }
    if ch == 92u8 && byte_at(c, c.pos + 1usize) == 92u8 { ret true }
    ret at_command(c, "right") || at_command(c, "end")
}

fn fail(c: *Ctx, why: err) {
    if c.status == ok { c.status = why }
}

// One character as a positioned glyph of `size`; the atom's origin is its pen.
fn glyph_atom(c: *Ctx, scalar: u32, size: f32, class: u8) -> Atom {
    var out: Atom = zero
    out.class = class
    out.first = c.count
    out.last = c.count
    out.simple = true
    if c.status != ok { ret out }
    var buffer: [4]u8 = zero
    let n = unicode.write_utf8(scalar, buffer[0..], 0usize)
    let m = mem.mark(c.a)
    var o: shape.Options = zero
    let (run, shape_error) = shape.shape(c.a, c.font, buffer[..n], o)
    if shape_error != ok || run.glyphs.len == 0usize {
        mem.reset(c.a, m)
        fail(c, Invalid)
        ret out
    }
    let id = run.glyphs[0].id
    let advance = run.glyphs[0].advance_x * size
    mem.reset(c.a, m)
    if id == 0u32 && !c.notdef {
        fail(c, MissingGlyph)
        ret out
    }
    let (low, high) = glyph_extent(c, id)
    push_item(c, Item { kind: .Glyph, x: 0.0, y: 0.0, w: advance, h: 0.0, size: size, glyph: id, scalar: scalar })
    out.last = c.count
    out.width = advance
    out.height = maxf(high * size, 0.0)
    out.depth = maxf(0.0 - low * size, 0.0)
    ret out
}

// `text` shaped as one run (kerning and ligatures apply) in `size`.
fn text_atom(c: *Ctx, text: str, size: f32, class: u8) -> Atom {
    var out: Atom = zero
    out.class = class
    out.first = c.count
    out.last = c.count
    if c.status != ok { ret out }
    let m = mem.mark(c.a)
    var o: shape.Options = zero
    let (run, shape_error) = shape.shape(c.a, c.font, text, o)
    if shape_error != ok {
        mem.reset(c.a, m)
        fail(c, Invalid)
        ret out
    }
    var x: f32 = 0.0
    var top: f32 = 0.0
    var bottom: f32 = 0.0
    var i = 0usize
    while i < run.glyphs.len {
        let g = run.glyphs[i]
        if g.id == 0u32 && !c.notdef {
            mem.reset(c.a, m)
            fail(c, MissingGlyph)
            ret out
        }
        let (low, high) = glyph_extent(c, g.id)
        let (scalar, step) = unicode.read_utf8(text, g.cluster)
        push_item(c, Item { kind: .Glyph, x: x + g.offset_x * size, y: 0.0 - g.offset_y * size, w: g.advance_x * size, h: 0.0, size: size, glyph: g.id, scalar: scalar })
        x += g.advance_x * size
        top = maxf(top, high * size)
        bottom = maxf(bottom, 0.0 - low * size)
        i += 1usize
    }
    mem.reset(c.a, m)
    out.last = c.count
    out.width = x
    out.height = top
    out.depth = bottom
    ret out
}

fn char_class(scalar: u32) -> u8 {
    if scalar == 43u32 || scalar == 8722u32 || scalar == 42u32 { ret CLASS_BIN }
    if scalar == 61u32 || scalar == 60u32 || scalar == 62u32 || scalar == 58u32 { ret CLASS_REL }
    if scalar == 40u32 || scalar == 91u32 { ret CLASS_OPEN }
    if scalar == 41u32 || scalar == 93u32 || scalar == 33u32 || scalar == 63u32 { ret CLASS_CLOSE }
    if scalar == 44u32 || scalar == 59u32 { ret CLASS_PUNCT }
    ret CLASS_ORD
}

fn greek_names() -> str {
    ret "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega"
}

// The scalar of a lowercase Greek name, or 0.
fn greek_scalar(word: str) -> u32 {
    let names = greek_names()
    var index = 0u32
    var start = 0usize
    var i = 0usize
    while i <= names.len {
        if i == names.len || names[i] == 32u8 {
            if word_is(word, names[start..i]) {
                var scalar = 945u32 + index
                if index >= 17u32 { scalar += 1u32 }
                ret scalar
            }
            index += 1u32
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u32
}

fn upper_greek(word: str) -> u32 {
    if word_is(word, "Gamma") { ret 915u32 }
    if word_is(word, "Delta") { ret 916u32 }
    if word_is(word, "Theta") { ret 920u32 }
    if word_is(word, "Lambda") { ret 923u32 }
    if word_is(word, "Xi") { ret 926u32 }
    if word_is(word, "Pi") { ret 928u32 }
    if word_is(word, "Sigma") { ret 931u32 }
    if word_is(word, "Phi") { ret 934u32 }
    if word_is(word, "Psi") { ret 936u32 }
    if word_is(word, "Omega") { ret 937u32 }
    ret 0u32
}

// (scalar, class) of a symbol command, scalar 0 when it is not one.
fn symbol_of(word: str) -> (u32, u8) {
    let g = greek_scalar(word)
    if g != 0u32 { ret (g, CLASS_ORD) }
    let u = upper_greek(word)
    if u != 0u32 { ret (u, CLASS_ORD) }
    if word_is(word, "pm") { ret (177u32, CLASS_BIN) }
    if word_is(word, "times") { ret (215u32, CLASS_BIN) }
    if word_is(word, "div") { ret (247u32, CLASS_BIN) }
    if word_is(word, "cdot") { ret (8901u32, CLASS_BIN) }
    if word_is(word, "cup") { ret (8746u32, CLASS_BIN) }
    if word_is(word, "cap") { ret (8745u32, CLASS_BIN) }
    if word_is(word, "leq") || word_is(word, "le") { ret (8804u32, CLASS_REL) }
    if word_is(word, "geq") || word_is(word, "ge") { ret (8805u32, CLASS_REL) }
    if word_is(word, "neq") || word_is(word, "ne") { ret (8800u32, CLASS_REL) }
    if word_is(word, "approx") { ret (8776u32, CLASS_REL) }
    if word_is(word, "equiv") { ret (8801u32, CLASS_REL) }
    if word_is(word, "to") || word_is(word, "rightarrow") { ret (8594u32, CLASS_REL) }
    if word_is(word, "leftarrow") { ret (8592u32, CLASS_REL) }
    if word_is(word, "in") { ret (8712u32, CLASS_REL) }
    if word_is(word, "infty") { ret (8734u32, CLASS_ORD) }
    if word_is(word, "partial") { ret (8706u32, CLASS_ORD) }
    if word_is(word, "nabla") { ret (8711u32, CLASS_ORD) }
    if word_is(word, "forall") { ret (8704u32, CLASS_ORD) }
    if word_is(word, "exists") { ret (8707u32, CLASS_ORD) }
    if word_is(word, "ldots") { ret (8230u32, CLASS_INNER) }
    ret (0u32, CLASS_ORD)
}

fn is_operator_name(word: str) -> bool {
    ret word_is(word, "sin") || word_is(word, "cos") || word_is(word, "tan") || word_is(word, "log") || word_is(word, "ln") || word_is(word, "exp") || word_is(word, "min") || word_is(word, "max") || word_is(word, "lim")
}

fn spacing_table() -> str {
    ret "01bc000a110c000abb00b00bcc00c00c0000000001bc000aaa0aaaaaa1bca0aa"
}

// Space between classes `left` and `right` in 18ths of an em.
fn spacing(left: u8, right: u8, script: bool) -> f32 {
    let table = spacing_table()
    let code = table[usize(left) * 8usize + usize(right)]
    if code == 48u8 { ret 0.0 }
    if code == 49u8 { ret 3.0 }
    if code == 50u8 { ret 4.0 }
    if code == 51u8 { ret 5.0 }
    if script { ret 0.0 }
    if code == 97u8 { ret 3.0 }
    if code == 98u8 { ret 4.0 }
    if code == 99u8 { ret 5.0 }
    ret 0.0
}

fn command_word(c: *Ctx) -> str {
    // The cursor is just after the backslash.
    let start = c.pos
    if c.pos < c.src.len {
        let ch = c.src[c.pos]
        if !((ch >= 97u8 && ch <= 122u8) || (ch >= 65u8 && ch <= 90u8)) {
            c.pos += 1usize
            ret c.src[start..c.pos]
        }
    }
    while c.pos < c.src.len && ((c.src[c.pos] >= 97u8 && c.src[c.pos] <= 122u8) || (c.src[c.pos] >= 65u8 && c.src[c.pos] <= 90u8)) { c.pos += 1usize }
    ret c.src[start..c.pos]
}

fn expect_byte(c: *Ctx, want: u8) {
    skip_space(c)
    if byte_at(c, c.pos) == want {
        c.pos += 1usize
        ret
    }
    fail(c, Invalid)
}

fn as_atom(b: Atom, class: u8) -> Atom {
    var out = b
    out.class = class
    out.simple = false
    out.limits = false
    ret out
}

// --- Rows, atoms and scripts.

fn parse_row(c: *Ctx, style: u32) -> Atom {
    var out: Atom = zero
    out.first = c.count
    out.last = c.count
    if c.nest >= MAX_NEST {
        fail(c, TooDeep)
        ret out
    }
    c.nest += 1usize
    let m = mem.mark(c.a)
    let (atoms, atoms_error) = mem.alloc[Atom](c.a, c.src.len - c.pos + 2usize)
    if atoms_error != ok {
        fail(c, Invalid)
        c.nest -= 1usize
        ret out
    }
    var n = 0usize
    while c.status == ok {
        skip_space(c)
        if ends_row(c) { break }
        let atom = parse_atom(c, style)
        if c.status != ok { break }
        atoms[n] = atom
        n += 1usize
    }
    // A binary atom with nothing to its left, or after another operator, is ordinary;
    // one with nothing right of it or before a relation, close or punctuation too.
    var i = 0usize
    while i < n {
        if atoms[i].class == CLASS_BIN {
            var before = CLASS_OPEN
            var j = i
            while j > 0usize {
                j -= 1usize
                if atoms[j].class != CLASS_SPACE {
                    before = atoms[j].class
                    break
                }
            }
            var after = CLASS_CLOSE
            j = i + 1usize
            while j < n {
                if atoms[j].class != CLASS_SPACE {
                    after = atoms[j].class
                    break
                }
                j += 1usize
            }
            if i == 0usize || before == CLASS_BIN || before == CLASS_OP || before == CLASS_REL || before == CLASS_OPEN || before == CLASS_PUNCT || after == CLASS_REL || after == CLASS_CLOSE || after == CLASS_PUNCT || j >= n {
                atoms[i].class = CLASS_ORD
            }
        }
        i += 1usize
    }
    let em18 = c.size * style_scale(style) / 18.0
    var x: f32 = 0.0
    var previous = CLASS_SPACE
    i = 0usize
    while i < n {
        if atoms[i].class != CLASS_SPACE {
            if previous != CLASS_SPACE { x += spacing(previous, atoms[i].class, style >= 2u32) * em18 }
            previous = atoms[i].class
        } else {
            previous = CLASS_SPACE
        }
        shift_range(c, atoms[i].first, atoms[i].last, x, 0.0)
        x += atoms[i].width
        out.height = maxf(out.height, atoms[i].height)
        out.depth = maxf(out.depth, atoms[i].depth)
        i += 1usize
    }
    out.last = c.count
    out.width = x
    out.class = CLASS_ORD
    mem.reset(c.a, m)
    c.nest -= 1usize
    ret out
}

// A group `{...}` or one token, the argument of a command or script.
fn parse_argument(c: *Ctx, style: u32) -> Atom {
    skip_space(c)
    if byte_at(c, c.pos) == 123u8 {
        c.pos += 1usize
        let row = parse_row(c, style)
        expect_byte(c, 125u8)
        ret row
    }
    ret parse_nucleus(c, style)
}

fn parse_atom(c: *Ctx, style: u32) -> Atom {
    var nucleus = parse_nucleus(c, style)
    if c.status != ok || nucleus.class == CLASS_SPACE { ret nucleus }
    skip_space(c)
    var has_sup = false
    var has_sub = false
    var sup: Atom = zero
    var sub: Atom = zero
    let sstyle = script_style(style)
    while c.status == ok && (byte_at(c, c.pos) == 94u8 || byte_at(c, c.pos) == 95u8) {
        let up = byte_at(c, c.pos) == 94u8
        c.pos += 1usize
        if up && has_sup { fail(c, Invalid) }
        if !up && has_sub { fail(c, Invalid) }
        let arg = parse_argument(c, sstyle)
        if up {
            sup = arg
            has_sup = true
        } else {
            sub = arg
            has_sub = true
        }
        skip_space(c)
    }
    if c.status != ok || (!has_sup && !has_sub) { ret nucleus }
    let s = c.size * style_scale(style)
    let ss = c.size * style_scale(sstyle)
    let display = c.display && style == 0u32
    // Limits over and under a big operator in display style.
    if nucleus.limits && display {
        var width = nucleus.width
        if has_sup { width = maxf(width, sup.width) }
        if has_sub { width = maxf(width, sub.width) }
        shift_range(c, nucleus.first, nucleus.last, (width - nucleus.width) / 2.0, 0.0)
        var height = nucleus.height
        var depth = nucleus.depth
        let gap = 0.12 * s
        if has_sup {
            let up_shift = nucleus.height + gap + sup.depth
            shift_range(c, sup.first, sup.last, (width - sup.width) / 2.0, 0.0 - up_shift)
            height = up_shift + sup.height
        }
        if has_sub {
            let down_shift = nucleus.depth + gap + sub.height
            shift_range(c, sub.first, sub.last, (width - sub.width) / 2.0, down_shift)
            depth = down_shift + sub.depth
        }
        var out = nucleus
        out.last = c.count
        out.width = width
        out.height = height
        out.depth = depth
        out.simple = false
        out.limits = false
        ret out
    }
    var up_shift: f32 = 0.0
    var down_shift: f32 = 0.0
    if !nucleus.simple {
        up_shift = nucleus.height - 0.386 * ss
        down_shift = nucleus.depth + 0.05 * ss
    }
    var sup_min = 0.363 * s
    if display { sup_min = 0.413 * s }
    let x_height = c.x_height * s
    if has_sup {
        up_shift = maxf(up_shift, sup_min)
        up_shift = maxf(up_shift, sup.depth + 0.25 * x_height)
    }
    if has_sub && !has_sup {
        down_shift = maxf(down_shift, 0.15 * s)
        down_shift = maxf(down_shift, sub.height - 0.8 * x_height)
    }
    if has_sub && has_sup {
        down_shift = maxf(down_shift, 0.247 * s)
        let theta = 0.04 * s
        let gap = (up_shift - sup.depth) - (sub.height - down_shift)
        if gap < 4.0 * theta {
            down_shift += 4.0 * theta - gap
            let psi = 0.8 * x_height - (up_shift - sup.depth)
            if psi > 0.0 {
                up_shift += psi
                down_shift -= psi
            }
        }
    }
    var width = nucleus.width
    var height = nucleus.height
    var depth = nucleus.depth
    let script_space = 0.05 * s
    if has_sup {
        shift_range(c, sup.first, sup.last, nucleus.width, 0.0 - up_shift)
        width = maxf(width, nucleus.width + sup.width + script_space)
        height = maxf(height, up_shift + sup.height)
        depth = maxf(depth, sup.depth - up_shift)
    }
    if has_sub {
        shift_range(c, sub.first, sub.last, nucleus.width, down_shift)
        width = maxf(width, nucleus.width + sub.width + script_space)
        depth = maxf(depth, down_shift + sub.depth)
        height = maxf(height, sub.height - down_shift)
    }
    var out = nucleus
    out.last = c.count
    out.width = width
    out.height = height
    out.depth = depth
    out.simple = false
    out.limits = false
    ret out
}

// The delimiter glyph `scalar` grown so its ink spans `span_h`, centred on the
// axis; an empty atom for scalar 0.
fn delimiter(c: *Ctx, scalar: u32, span_h: f32, size: f32, class: u8) -> Atom {
    if scalar == 0u32 {
        var empty: Atom = zero
        empty.class = class
        empty.first = c.count
        empty.last = c.count
        ret empty
    }
    var probe = glyph_atom(c, scalar, size, class)
    if c.status != ok { ret probe }
    let ink = probe.height + probe.depth
    var k: f32 = 1.0
    if ink > 0.0 && span_h > ink { k = span_h / ink }
    if k == 1.0 {
        // Centre on the axis at the natural size.
        let lift = 0.25 * size - (probe.height - probe.depth) / 2.0
        shift_range(c, probe.first, probe.last, 0.0, 0.0 - lift)
        probe.height += lift
        probe.depth -= lift
        ret probe
    }
    // Replace the natural glyph with the scaled one.
    c.count = probe.first
    let scaled = glyph_atom(c, scalar, size * k, class)
    let lift = 0.25 * size - (scaled.height - scaled.depth) / 2.0
    shift_range(c, scaled.first, scaled.last, 0.0, 0.0 - lift)
    var out = scaled
    out.height += lift
    out.depth -= lift
    ret out
}

fn push_rule(c: *Ctx, x: f32, top: f32, w: f32, h: f32) {
    push_item(c, Item { kind: .Rule, x: x, y: top, w: w, h: h, size: 0.0, glyph: 0u32, scalar: 0u32 })
}

fn delimiter_scalar(c: *Ctx) -> u32 {
    skip_space(c)
    let ch = byte_at(c, c.pos)
    if ch == 46u8 {
        c.pos += 1usize
        ret 0u32
    }
    if ch == 92u8 {
        c.pos += 1usize
        let word = command_word(c)
        if word_is(word, "{") { ret 123u32 }
        if word_is(word, "}") { ret 125u32 }
        if word_is(word, "|") { ret 8214u32 }
        fail(c, Invalid)
        ret 0u32
    }
    if ch == 0u8 {
        fail(c, Invalid)
        ret 0u32
    }
    let (scalar, step) = unicode.read_utf8(c.src, c.pos)
    c.pos += step
    ret scalar
}

// Wraps the content `body` (already at its origin) in delimiters grown to it.
fn fence(c: *Ctx, body: Atom, left: u32, right: u32, style: u32) -> Atom {
    let s = c.size * style_scale(style)
    let axis = 0.25 * s
    var delta = maxf(body.height - axis, body.depth + axis)
    var span_h = 2.0 * delta * 0.95
    if span_h < 1.2 * s { span_h = 1.2 * s }
    let first = body.first
    // Delimiters go after the body in the list; move the body right of the left one.
    let l = delimiter(c, left, span_h, s, CLASS_OPEN)
    shift_range(c, body.first, body.last, l.width, 0.0)
    let r = delimiter(c, right, span_h, s, CLASS_CLOSE)
    shift_range(c, r.first, r.last, l.width + body.width, 0.0)
    var out: Atom = zero
    out.class = CLASS_INNER
    out.first = first
    out.last = c.count
    out.width = l.width + body.width + r.width
    out.height = maxf(body.height, maxf(l.height, r.height))
    out.depth = maxf(body.depth, maxf(l.depth, r.depth))
    ret out
}

fn lay_fraction(c: *Ctx, style: u32) -> Atom {
    let child = fraction_style(style)
    let numerator = parse_argument(c, child)
    let denominator = parse_argument(c, child)
    var out: Atom = zero
    out.class = CLASS_INNER
    out.first = numerator.first
    if c.status != ok { ret out }
    let s = c.size * style_scale(style)
    let display = c.display && style == 0u32
    let theta = 0.04 * s
    let axis = 0.25 * s
    var up = 0.394 * s
    var down = 0.345 * s
    var clearance = theta
    if display {
        up = 0.677 * s
        down = 0.686 * s
        clearance = 3.0 * theta
    }
    if (up - numerator.depth) - (axis + theta / 2.0) < clearance { up += clearance - ((up - numerator.depth) - (axis + theta / 2.0)) }
    if (axis - theta / 2.0) - (denominator.height - down) < clearance { down += clearance - ((axis - theta / 2.0) - (denominator.height - down)) }
    let side = 0.12 * s
    let width = maxf(numerator.width, denominator.width)
    shift_range(c, numerator.first, numerator.last, side + (width - numerator.width) / 2.0, 0.0 - up)
    shift_range(c, denominator.first, denominator.last, side + (width - denominator.width) / 2.0, down)
    push_rule(c, side, 0.0 - (axis + theta / 2.0), width, theta)
    out.last = c.count
    out.width = width + 2.0 * side
    out.height = up + numerator.height
    out.depth = down + denominator.depth
    ret out
}

fn lay_radical(c: *Ctx, style: u32) -> Atom {
    var out: Atom = zero
    out.class = CLASS_ORD
    out.first = c.count
    skip_space(c)
    // Optional index.
    var index: Atom = zero
    var has_index = false
    if byte_at(c, c.pos) == 91u8 {
        c.pos += 1usize
        let first = c.count
        index = parse_row_until_bracket(c, 3u32)
        has_index = true
        out.first = first
    }
    let body = parse_argument(c, style)
    if c.status != ok { ret out }
    let s = c.size * style_scale(style)
    let theta = 0.04 * s
    var clearance = theta + theta / 4.0
    if c.display && style == 0u32 { clearance = theta + c.x_height * s / 4.0 }
    let need = body.height + body.depth + clearance + theta
    // The radical sign, grown to `need`.
    let probe = glyph_atom(c, 8730u32, s, CLASS_ORD)
    if c.status != ok { ret out }
    let ink = probe.height + probe.depth
    var k: f32 = 1.0
    if ink > 0.0 && need > ink { k = need / ink }
    c.count = probe.first
    let sign = glyph_atom(c, 8730u32, s * k, CLASS_ORD)
    if c.status != ok { ret out }
    // Sit the sign's bottom at the body's bottom plus the clearance's share.
    let top_of_bar = body.height + clearance + theta
    shift_range(c, sign.first, sign.last, 0.0, 0.0 - (top_of_bar - sign.height))
    var sign_x: f32 = 0.0
    var index_width: f32 = 0.0
    if has_index {
        index_width = index.width
        let overlap = 5.0 / 18.0 * s
        sign_x = maxf(index_width - overlap, 0.0)
        let raise = 0.6 * (top_of_bar + body.depth) - body.depth
        shift_range(c, index.first, index.last, 0.0, 0.0 - raise)
    }
    shift_range(c, sign.first, sign.last, sign_x, 0.0)
    shift_range(c, body.first, body.last, sign_x + sign.width, 0.0)
    push_rule(c, sign_x + sign.width, 0.0 - top_of_bar, body.width, theta)
    out.last = c.count
    out.width = sign_x + sign.width + body.width
    out.height = top_of_bar
    out.depth = maxf(body.depth, sign.depth - (top_of_bar - sign.height))
    if has_index { out.height = maxf(out.height, 0.6 * (top_of_bar + body.depth) - body.depth + index.height) }
    ret out
}

// The index of a radical: a row up to the closing bracket, in scriptscript style.
fn parse_row_until_bracket(c: *Ctx, style: u32) -> Atom {
    var out: Atom = zero
    out.first = c.count
    out.last = c.count
    var x: f32 = 0.0
    while c.status == ok {
        skip_space(c)
        if c.pos >= c.src.len {
            fail(c, Invalid)
            break
        }
        if c.src[c.pos] == 93u8 {
            c.pos += 1usize
            break
        }
        let atom = parse_atom(c, style)
        if c.status != ok { break }
        shift_range(c, atom.first, atom.last, x, 0.0)
        x += atom.width
        out.height = maxf(out.height, atom.height)
        out.depth = maxf(out.depth, atom.depth)
    }
    out.last = c.count
    out.width = x
    ret out
}

type Cell = struct { atom: Atom, row: usize, col: usize }

fn lay_environment(c: *Ctx, style: u32) -> Atom {
    var out: Atom = zero
    out.class = CLASS_INNER
    out.first = c.count
    expect_byte(c, 123u8)
    let name_start = c.pos
    while c.pos < c.src.len && c.src[c.pos] != 125u8 { c.pos += 1usize }
    let name = c.src[name_start..c.pos]
    expect_byte(c, 125u8)
    if c.status != ok { ret out }
    var left = 0u32
    var right = 0u32
    var left_align = false
    if word_is(name, "pmatrix") {
        left = 40u32
        right = 41u32
    } else if word_is(name, "bmatrix") {
        left = 91u32
        right = 93u32
    } else if word_is(name, "Bmatrix") {
        left = 123u32
        right = 125u32
    } else if word_is(name, "vmatrix") {
        left = 124u32
        right = 124u32
    } else if word_is(name, "cases") {
        left = 123u32
        left_align = true
    } else if !word_is(name, "matrix") {
        fail(c, Invalid)
        ret out
    }
    if c.nest >= MAX_NEST {
        fail(c, TooDeep)
        ret out
    }
    c.nest += 1usize
    let m = mem.mark(c.a)
    let (cells, cells_error) = mem.alloc[Cell](c.a, c.src.len - c.pos + 2usize)
    if cells_error != ok {
        fail(c, Invalid)
        c.nest -= 1usize
        ret out
    }
    var n = 0usize
    var row = 0usize
    var col = 0usize
    var columns = 0usize
    let cell_style = 1u32
    while c.status == ok {
        let cell = parse_row(c, cell_style)
        if c.status != ok { break }
        cells[n] = Cell { atom: cell, row: row, col: col }
        n += 1usize
        if col + 1usize > columns { columns = col + 1usize }
        skip_space(c)
        if byte_at(c, c.pos) == 38u8 {
            c.pos += 1usize
            col += 1usize
        } else if byte_at(c, c.pos) == 92u8 && byte_at(c, c.pos + 1usize) == 92u8 {
            c.pos += 2usize
            row += 1usize
            col = 0usize
            skip_space(c)
            // A trailing row separator before \end adds no row.
            if at_command(c, "end") { break }
        } else if at_command(c, "end") {
            break
        } else {
            fail(c, Invalid)
        }
    }
    if c.status == ok {
        c.pos += 4usize
        expect_byte(c, 123u8)
        let end_start = c.pos
        while c.pos < c.src.len && c.src[c.pos] != 125u8 { c.pos += 1usize }
        if !word_is(c.src[end_start..c.pos], name) { fail(c, Invalid) }
        expect_byte(c, 125u8)
    }
    if c.status != ok {
        mem.reset(c.a, m)
        c.nest -= 1usize
        ret out
    }
    var rows = 0usize
    var i = 0usize
    while i < n {
        if cells[i].row + 1usize > rows { rows = cells[i].row + 1usize }
        i += 1usize
    }
    let (col_w, col_error) = mem.alloc[f32](c.a, columns + 1usize)
    let (row_h, row_h_error) = mem.alloc[f32](c.a, rows + 1usize)
    let (row_d, row_d_error) = mem.alloc[f32](c.a, rows + 1usize)
    if col_error != ok || row_h_error != ok || row_d_error != ok {
        mem.reset(c.a, m)
        c.nest -= 1usize
        fail(c, Invalid)
        ret out
    }
    let s = c.size * style_scale(style)
    i = 0usize
    while i < columns {
        col_w[i] = 0.0
        i += 1usize
    }
    i = 0usize
    while i < rows {
        // The strut of a row: 0.7 and 0.3 of a 1.2 em baseline skip.
        row_h[i] = 0.84 * s
        row_d[i] = 0.36 * s
        i += 1usize
    }
    i = 0usize
    while i < n {
        col_w[cells[i].col] = maxf(col_w[cells[i].col], cells[i].atom.width)
        row_h[cells[i].row] = maxf(row_h[cells[i].row], cells[i].atom.height)
        row_d[cells[i].row] = maxf(row_d[cells[i].row], cells[i].atom.depth)
        i += 1usize
    }
    var total_h: f32 = 0.0
    i = 0usize
    while i < rows {
        total_h += row_h[i] + row_d[i]
        i += 1usize
    }
    var total_w: f32 = 0.0
    i = 0usize
    while i < columns {
        total_w += col_w[i]
        i += 1usize
    }
    if columns > 1usize { total_w += s * f32(columns - 1usize) }
    let top = 0.25 * s + total_h / 2.0
    i = 0usize
    while i < n {
        var x: f32 = 0.0
        var j = 0usize
        while j < cells[i].col {
            x += col_w[j] + s
            j += 1usize
        }
        if !left_align { x += (col_w[cells[i].col] - cells[i].atom.width) / 2.0 }
        var above = top
        j = 0usize
        while j < cells[i].row {
            above -= row_h[j] + row_d[j]
            j += 1usize
        }
        above -= row_h[cells[i].row]
        shift_range(c, cells[i].atom.first, cells[i].atom.last, x, 0.0 - above)
        i += 1usize
    }
    var body: Atom = zero
    body.first = out.first
    body.last = c.count
    body.width = total_w
    body.height = top
    body.depth = total_h - top
    mem.reset(c.a, m)
    c.nest -= 1usize
    if left == 0u32 && right == 0u32 { ret as_atom(body, CLASS_INNER) }
    // Delimiters wrap the whole block, grown to its height.
    let wrapped = fence(c, body, left, right, style)
    ret wrapped
}

fn lay_text(c: *Ctx, style: u32) -> Atom {
    expect_byte(c, 123u8)
    let start = c.pos
    while c.pos < c.src.len && c.src[c.pos] != 125u8 { c.pos += 1usize }
    let raw = c.src[start..c.pos]
    expect_byte(c, 125u8)
    if c.status != ok {
        var empty: Atom = zero
        ret empty
    }
    var out = text_atom(c, raw, c.size * style_scale(style), CLASS_ORD)
    out.simple = false
    ret out
}

fn space_atom(c: *Ctx, em18: f32, style: u32) -> Atom {
    var out: Atom = zero
    out.class = CLASS_SPACE
    out.first = c.count
    out.last = c.count
    out.width = em18 * c.size * style_scale(style) / 18.0
    ret out
}

fn parse_nucleus(c: *Ctx, style: u32) -> Atom {
    skip_space(c)
    var out: Atom = zero
    out.first = c.count
    out.last = c.count
    if c.pos >= c.src.len {
        fail(c, Invalid)
        ret out
    }
    let s = c.size * style_scale(style)
    let ch = c.src[c.pos]
    if ch == 123u8 {
        c.pos += 1usize
        let row = parse_row(c, style)
        expect_byte(c, 125u8)
        ret as_atom(row, CLASS_ORD)
    }
    if ch == 125u8 || ch == 38u8 || ch == 94u8 || ch == 95u8 {
        fail(c, Invalid)
        ret out
    }
    if ch != 92u8 {
        let (scalar, step) = unicode.read_utf8(c.src, c.pos)
        c.pos += step
        var mapped = scalar
        if scalar == 45u32 { mapped = 8722u32 }
        ret glyph_atom(c, mapped, s, char_class(mapped))
    }
    c.pos += 1usize
    let word = command_word(c)
    if word.len == 0usize {
        fail(c, Invalid)
        ret out
    }
    if word_is(word, "frac") { ret lay_fraction(c, style) }
    if word_is(word, "sqrt") { ret lay_radical(c, style) }
    if word_is(word, "text") || word_is(word, "mathrm") { ret lay_text(c, style) }
    if word_is(word, "begin") { ret lay_environment(c, style) }
    if word_is(word, "left") {
        let left = delimiter_scalar(c)
        if c.nest >= MAX_NEST {
            fail(c, TooDeep)
            ret out
        }
        c.nest += 1usize
        let body = parse_row(c, style)
        c.nest -= 1usize
        if c.status != ok { ret out }
        if !at_command(c, "right") {
            fail(c, Invalid)
            ret out
        }
        c.pos += 6usize
        let right = delimiter_scalar(c)
        if c.status != ok { ret out }
        ret fence(c, body, left, right, style)
    }
    if word_is(word, ",") { ret space_atom(c, 3.0, style) }
    if word_is(word, ":") { ret space_atom(c, 4.0, style) }
    if word_is(word, ";") { ret space_atom(c, 5.0, style) }
    if word_is(word, "quad") { ret space_atom(c, 18.0, style) }
    if word_is(word, "qquad") { ret space_atom(c, 36.0, style) }
    if word_is(word, "!") {
        var back = space_atom(c, 3.0, style)
        back.width = 0.0 - back.width
        ret back
    }
    if word_is(word, "{") { ret glyph_atom(c, 123u32, s, CLASS_OPEN) }
    if word_is(word, "}") { ret glyph_atom(c, 125u32, s, CLASS_CLOSE) }
    if word_is(word, "|") { ret glyph_atom(c, 8214u32, s, CLASS_ORD) }
    if word_is(word, "%") || word_is(word, "#") || word_is(word, "&") || word_is(word, "_") || word_is(word, "$") {
        ret glyph_atom(c, u32(word[0]), s, CLASS_ORD)
    }
    if word_is(word, "sum") || word_is(word, "prod") || word_is(word, "int") {
        var scalar = 8721u32
        if word_is(word, "prod") { scalar = 8719u32 }
        if word_is(word, "int") { scalar = 8747u32 }
        var size = s
        if c.display && style == 0u32 { size = s * 1.4 }
        var op = glyph_atom(c, scalar, size, CLASS_OP)
        if c.status != ok { ret op }
        // Centre the operator on the axis.
        let lift = 0.25 * s - (op.height - op.depth) / 2.0
        shift_range(c, op.first, op.last, 0.0, 0.0 - lift)
        op.height += lift
        op.depth -= lift
        op.limits = !word_is(word, "int")
        op.simple = false
        ret op
    }
    if is_operator_name(word) {
        var op = text_atom(c, word, s, CLASS_OP)
        op.limits = word_is(word, "lim") || word_is(word, "min") || word_is(word, "max")
        op.simple = false
        ret op
    }
    let (scalar, class) = symbol_of(word)
    if scalar != 0u32 { ret glyph_atom(c, scalar, s, class) }
    fail(c, Invalid)
    ret out
}

fn font_ready(c: *Ctx) -> bool {
    if shape.validate_font(c.font) != ok { ret false }
    let d = c.font.data
    c.head_at = find_table(d, 1751474532u32)
    c.maxp_at = find_table(d, 1835104368u32)
    c.loca_at = find_table(d, 1819239265u32)
    c.glyf_at = find_table(d, 1735162214u32)
    if c.head_at == NONE { ret false }
    c.upem = f32(be16(d, c.head_at + 18usize))
    ret c.upem > 0.0
}

// Typesets `source` at `options.size` into `items`.
fn typeset(a: *mem.Arena, source: str, options: Options, items: []Item) -> (Equation, err) {
    if options.size <= 0.0 || source.len == 0usize { ret (zero, Invalid) }
    var c: Ctx = zero
    c.a = a
    c.font = options.font
    c.items = items
    c.src = source
    c.size = options.size
    c.display = options.display
    c.notdef = options.notdef
    c.status = ok
    if !font_ready(&c) { ret (zero, Invalid) }
    // The x-height from the font's own "x".
    c.x_height = 0.5
    let m = mem.mark(a)
    var o: shape.Options = zero
    let (probe, probe_error) = shape.shape(a, options.font, "x", o)
    if probe_error == ok && probe.glyphs.len > 0usize {
        let (low, high) = glyph_extent(&c, probe.glyphs[0].id)
        if high > 0.0 { c.x_height = high }
    }
    mem.reset(a, m)
    var style = 1u32
    if options.display { style = 0u32 }
    let row = parse_row(&c, style)
    if c.status == ok && c.pos < c.src.len { c.status = Invalid }
    if c.status != ok { ret (zero, c.status) }
    var eq: Equation = zero
    eq.items = items[..c.count]
    eq.width = row.width
    eq.ascent = row.height
    eq.descent = row.depth
    ret (eq, ok)
}
