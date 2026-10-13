// Math typesetting over `e.text.shape` (L098): a LaTeX-math subset, or presentation
// MathML, parsed and laid out in one pass into a flat list of positioned glyphs and
// rules in caller storage, for scene and SVG adapters. The model is TeX's: atoms of a
// class (ordinary, operator, binary, relation, open, close, punctuation, inner) with
// the inter-atom space table of the TeXbook, four styles (display, text, script,
// scriptscript) each with a cramped form, fractions, radicals with an optional index,
// super- and subscripts with the rule 18 shifts, big operators with limits in display
// style, `\left` `\right` delimiters grown to the content, and `matrix`, `pmatrix`,
// `bmatrix`, `Bmatrix`, `vmatrix`, `cases`, `align`, `aligned` and `gather`
// environments.
//
// Coordinates are in the caller's size units, origin at the equation's left edge on
// its baseline, y growing downward: a glyph's `y` is its baseline, a rule's `y` its
// top edge. Glyph extents come from the font's `glyf` bounding boxes when it is a
// TrueType outline font (otherwise a character is taken as 0.7 em tall).
//
// A font with an OpenType MATH table is laid out by that table (L098, D3101): the
// MathConstants (axis, rule thickness, fraction and script shifts and gaps, radical
// parameters, script scale-down percentages), the italic corrections of
// MathGlyphInfo, and MathVariants for delimiters, radical signs and display
// operators -- the first variant tall enough, else an assembly of parts with the
// extenders repeated and the connectors overlapped. A font without one gets TeX's
// cmsy values as fractions of the em and a glyph scaled to the content. When the
// font carries the Mathematical Alphanumeric block, Latin and lower-case Greek
// letters in a formula take its italic forms; otherwise they stay as written.
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
//
// `typeset_mathml` reads presentation MathML (`mrow` `mi` `mn` `mo` `mtext` `msup`
// `msub` `msubsup` `munder` `mover` `munderover` `mfrac` `msqrt` `mroot` `mfenced`
// `mtable` `mtr` `mtd` `mstyle` `mspace`) by translating it to the LaTeX subset
// above and laying that out, so the two inputs share every rule. `munder` and `mover`
// are laid out as a subscript and a superscript (limits on a big operator in display
// style) unless the second child is an `mo` of one accent or brace character (and
// `accent`/`accentunder` is not "false"): that is `\overaccent{c}{base}`,
// `\underaccent{c}{base}` or `\overbrace`, `\underbrace`, set as wide as the base.
//
// Also (L098, D3702): the alphabets `\mathbf` `\mathbfit` `\boldsymbol` `\mathcal`
// `\mathscr` `\mathfrak` `\mathbb` `\mathsf` `\mathtt` `\mathit` (Mathematical
// Alphanumeric Symbols, the Letterlike holes included, when the font has the glyph; a
// letter it lacks stays as written); accents `\hat` `\check` `\tilde` `\acute` `\grave`
// `\dot` `\ddot` `\breve` `\bar` `\vec` `\mathring` (combining forms, centred by the two
// MathTopAccentAttachment points, else half the advance, and raised by the base's
// height over AccentBaseHeight), `\widehat` `\widetilde` (a horizontal variant or
// assembly as wide as the base), `\overline` `\underline` (the Overbar and Underbar
// constants), `\overbrace` `\underbrace` (U+23DE and U+23DF stretched to the body, a
// StretchStack gap away, an operator with limits so `^` and `_` set a label beyond);
// and MathKernInfo cut-ins between a one-glyph base and a one-glyph script.
//
// Also (L098, D4505): `\substack{a\\b}` (rows centred, one 1.2 em skip of the style apart, the block
// on the axis); `\big` `\Big` `\bigg` `\Bigg` and their `l`, `r`, `m` forms (a delimiter 1.2, 1.8, 2.4
// and 3 em of the equation's size tall in any style, centred on the axis; open, close, relation or
// ordinary); `\tag{n}` and `\tag*{n}` (`typeset_numbered`: the equation centred in a line of the
// given width, its number flush right and an em clear of it, the line growing when there is no
// room; an `align` or `gather` row's tag is set in a right-aligned column an em past the table); and
// MathKernInfo kerning of a base that is a run of glyphs on one baseline by its last glyph, at that
// glyph's own height and depth (a fraction or any other structure as a base is not kerned).
//
// `to_layout` turns the glyph items into an `e.text.layout.Layout` of one run per
// glyph, which `e.gfx.scene` draws as a `DrawText`; the rule items are rectangles the
// caller fills.

use e.mem
use e.str
use e.gfx.geometry
use e.text.layout
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
const STYLE_CRAMPED: u32 = 4u32

// A laid-out piece: its items are `first..last` of the shared list, positioned
// relative to its own origin on the baseline.
type Atom = struct { class: u8, first: usize, last: usize, width: f32, height: f32, depth: f32, simple: bool, limits: bool, stretch: bool }

// Layout constants in ems of the size: TeX's cmsy and cmex values, or the font's MATH
// table's when it has one.
type Consts = struct {
    axis: f32,
    rule: f32,
    script: f32,
    scriptscript: f32,
    num_display: f32,
    num_text: f32,
    den_display: f32,
    den_text: f32,
    num_gap: f32,
    num_gap_display: f32,
    den_gap: f32,
    den_gap_display: f32,
    sup_display: f32,
    sup_text: f32,
    sup_cramped: f32,
    sub_only: f32,
    sub_both: f32,
    sub_top_max: f32,
    sup_bottom_min: f32,
    sup_max_with_sub: f32,
    sub_sup_gap: f32,
    sup_drop: f32,
    sub_drop: f32,
    script_space: f32,
    upper_gap: f32,
    lower_gap: f32,
    rad_rule: f32,
    rad_gap: f32,
    rad_gap_display: f32,
    rad_extra: f32,
    rad_before: f32,
    rad_after: f32,
    rad_raise: f32,
    delim_min: f32,
    op_min: f32,
    accent_base: f32,
    over_gap: f32,
    over_rule: f32,
    over_extra: f32,
    under_gap: f32,
    under_rule: f32,
    under_extra: f32,
    stretch_above: f32,
    stretch_below: f32,
}

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
    hhea_at: usize,
    hmtx_at: usize,
    math_at: usize,
    consts_at: usize,
    info_at: usize,
    variants_at: usize,
    alphabet: u8,
    tag_at: usize,
    tag_len: usize,
    tag_star: bool,
    k: Consts,
}

fn maxf(x: f32, y: f32) -> f32 {
    if x > y { ret x }
    ret y
}

fn minf(x: f32, y: f32) -> f32 {
    if x < y { ret x }
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

// The horizontal advance of a glyph in ems, from `hmtx`.
fn glyph_advance(c: *Ctx, id: u32) -> f32 {
    if c.hhea_at == NONE || c.hmtx_at == NONE || c.upem <= 0.0 { ret 0.5 }
    let d = c.font.data
    let metrics = usize(be16(d, c.hhea_at + 34usize))
    if metrics == 0usize { ret 0.5 }
    var index = usize(id)
    if index >= metrics { index = metrics - 1usize }
    ret f32(be16(d, c.hmtx_at + 4usize * index)) / c.upem
}

// --- Styles: 0 display, 1 text, 2 script, 3 scriptscript, plus STYLE_CRAMPED.

fn style_base(style: u32) -> u32 {
    ret style & 3u32
}

fn style_cramped(style: u32) -> bool {
    ret style & STYLE_CRAMPED != 0u32
}

fn style_scale(c: *Ctx, style: u32) -> f32 {
    let base = style & 3u32
    if base >= 3u32 { ret c.k.scriptscript }
    if base == 2u32 { ret c.k.script }
    ret 1.0
}

// The style of a script: script or scriptscript, cramped as its parent is.
fn script_style(style: u32) -> u32 {
    var base = 3u32
    if style & 3u32 < 2u32 { base = 2u32 }
    ret base | (style & STYLE_CRAMPED)
}

fn fraction_style(style: u32) -> u32 {
    var base = 3u32
    if style & 3u32 < 3u32 { base = (style & 3u32) + 1u32 }
    ret base | (style & STYLE_CRAMPED)
}

// --- Constants.

// TeX's values; `xh` is the font's x-height in ems.
fn default_consts(xh: f32) -> Consts {
    var k: Consts = zero
    k.axis = 0.25
    k.rule = 0.04
    k.script = 0.7
    k.scriptscript = 0.5
    k.num_display = 0.677
    k.num_text = 0.394
    k.den_display = 0.686
    k.den_text = 0.345
    k.num_gap = 0.04
    k.num_gap_display = 0.12
    k.den_gap = 0.04
    k.den_gap_display = 0.12
    k.sup_display = 0.413
    k.sup_text = 0.363
    k.sup_cramped = 0.289
    k.sub_only = 0.15
    k.sub_both = 0.247
    k.sub_top_max = 0.8 * xh
    k.sup_bottom_min = 0.25 * xh
    k.sup_max_with_sub = 0.8 * xh
    k.sub_sup_gap = 0.16
    k.sup_drop = 0.386
    k.sub_drop = 0.05
    k.script_space = 0.05
    k.upper_gap = 0.12
    k.lower_gap = 0.12
    k.rad_rule = 0.04
    k.rad_gap = 0.05
    k.rad_gap_display = 0.04 + 0.25 * xh
    k.rad_extra = 0.0
    k.rad_before = 0.0
    k.rad_after = 0.0 - 5.0 / 18.0
    k.rad_raise = 0.6
    k.delim_min = 1.2
    k.op_min = 0.0
    // TeX's rule 9 and 12: an overline sits 3 rule thicknesses above the body under one thickness
    // of rule and one of extra height; an accent is designed for the x-height.
    k.accent_base = xh
    k.over_gap = 0.12
    k.over_rule = 0.04
    k.over_extra = 0.04
    k.under_gap = 0.12
    k.under_rule = 0.04
    k.under_extra = 0.04
    k.stretch_above = 0.12
    k.stretch_below = 0.12
    ret k
}

// A MathValueRecord of the MathConstants table, in ems; `index` counts the records
// from `mathLeading` (0) on.
fn math_value(c: *Ctx, index: usize) -> f32 {
    ret f32(be16s(c.font.data, c.consts_at + 8usize + 4usize * index)) / c.upem
}

// Reads the MATH table's constants over TeX's defaults and finds its info and
// variants; a table of another major version, or one cut short, is ignored.
fn load_math(c: *Ctx) {
    c.k = default_consts(c.x_height)
    let d = c.font.data
    c.math_at = find_table(d, 1296127048u32)
    c.consts_at = NONE
    c.info_at = NONE
    c.variants_at = NONE
    if c.math_at == NONE || be16(d, c.math_at) != 1u32 { ret }
    let consts = usize(be16(d, c.math_at + 4usize))
    let info = usize(be16(d, c.math_at + 6usize))
    let variants = usize(be16(d, c.math_at + 8usize))
    if consts == 0usize || c.math_at + consts + 8usize + 4usize * 51usize + 2usize > d.len { ret }
    c.consts_at = c.math_at + consts
    if info != 0usize { c.info_at = c.math_at + info }
    if variants != 0usize { c.variants_at = c.math_at + variants }
    var k = c.k
    let up = f32(be16s(d, c.consts_at)) / 100.0
    let up2 = f32(be16s(d, c.consts_at + 2usize)) / 100.0
    if up > 0.0 { k.script = up }
    if up2 > 0.0 { k.scriptscript = up2 }
    k.delim_min = f32(be16(d, c.consts_at + 4usize)) / c.upem
    k.op_min = f32(be16(d, c.consts_at + 6usize)) / c.upem
    k.axis = math_value(c, 1usize)
    k.accent_base = math_value(c, 2usize)
    k.stretch_above = math_value(c, 26usize)
    k.stretch_below = math_value(c, 27usize)
    k.over_gap = math_value(c, 39usize)
    k.over_rule = math_value(c, 40usize)
    k.over_extra = math_value(c, 41usize)
    k.under_gap = math_value(c, 42usize)
    k.under_rule = math_value(c, 43usize)
    k.under_extra = math_value(c, 44usize)
    k.sub_only = math_value(c, 4usize)
    k.sub_both = k.sub_only
    k.sub_top_max = math_value(c, 5usize)
    k.sub_drop = math_value(c, 6usize)
    k.sup_display = math_value(c, 7usize)
    k.sup_text = k.sup_display
    k.sup_cramped = math_value(c, 8usize)
    k.sup_bottom_min = math_value(c, 9usize)
    k.sup_drop = math_value(c, 10usize)
    k.sub_sup_gap = math_value(c, 11usize)
    k.sup_max_with_sub = math_value(c, 12usize)
    k.script_space = math_value(c, 13usize)
    k.upper_gap = math_value(c, 14usize)
    k.lower_gap = math_value(c, 16usize)
    k.num_text = math_value(c, 28usize)
    k.num_display = math_value(c, 29usize)
    k.den_text = math_value(c, 30usize)
    k.den_display = math_value(c, 31usize)
    k.num_gap = math_value(c, 32usize)
    k.num_gap_display = math_value(c, 33usize)
    k.rule = math_value(c, 34usize)
    k.den_gap = math_value(c, 35usize)
    k.den_gap_display = math_value(c, 36usize)
    k.rad_gap = math_value(c, 45usize)
    k.rad_gap_display = math_value(c, 46usize)
    k.rad_rule = math_value(c, 47usize)
    k.rad_extra = math_value(c, 48usize)
    k.rad_before = math_value(c, 49usize)
    k.rad_after = math_value(c, 50usize)
    k.rad_raise = f32(be16s(d, c.consts_at + 8usize + 4usize * 51usize)) / 100.0
    c.k = k
}

// The position of `gid` in a Coverage table at `at`, or NONE.
fn coverage_pos(d: []const u8, at: usize, gid: u32) -> usize {
    let format = be16(d, at)
    let count = usize(be16(d, at + 2usize))
    var i = 0usize
    if format == 1u32 {
        while i < count {
            if be16(d, at + 4usize + 2usize * i) == gid { ret i }
            i += 1usize
        }
        ret NONE
    }
    if format == 2u32 {
        while i < count {
            let record = at + 4usize + 6usize * i
            let first = be16(d, record)
            let last = be16(d, record + 2usize)
            if gid >= first && gid <= last { ret usize(be16(d, record + 4usize)) + usize(gid - first) }
            i += 1usize
        }
    }
    ret NONE
}

// The italic correction of a glyph in ems, from MathGlyphInfo; 0 when it has none.
fn italic_correction(c: *Ctx, gid: u32) -> f32 {
    if c.info_at == NONE { ret 0.0 }
    let d = c.font.data
    let table = usize(be16(d, c.info_at))
    if table == 0usize { ret 0.0 }
    let at = c.info_at + table
    let cov = usize(be16(d, at))
    if cov == 0usize { ret 0.0 }
    let index = coverage_pos(d, at + cov, gid)
    if index == NONE || index >= usize(be16(d, at + 2usize)) { ret 0.0 }
    ret f32(be16s(d, at + 4usize + 4usize * index)) / c.upem
}

// The vertical GlyphConstruction table of a glyph, or NONE.
fn construction_of(c: *Ctx, gid: u32) -> usize {
    if c.variants_at == NONE || gid == 0u32 { ret NONE }
    let d = c.font.data
    let cov = usize(be16(d, c.variants_at + 2usize))
    if cov == 0usize { ret NONE }
    let index = coverage_pos(d, c.variants_at + cov, gid)
    if index == NONE || index >= usize(be16(d, c.variants_at + 6usize)) { ret NONE }
    let offset = usize(be16(d, c.variants_at + 10usize + 2usize * index))
    if offset == 0usize { ret NONE }
    ret c.variants_at + offset
}

// The horizontal GlyphConstruction table of a glyph, or NONE.
fn construction_h(c: *Ctx, gid: u32) -> usize {
    if c.variants_at == NONE || gid == 0u32 { ret NONE }
    let d = c.font.data
    let cov = usize(be16(d, c.variants_at + 4usize))
    if cov == 0usize { ret NONE }
    let index = coverage_pos(d, c.variants_at + cov, gid)
    let vertical = usize(be16(d, c.variants_at + 6usize))
    if index == NONE || index >= usize(be16(d, c.variants_at + 8usize)) { ret NONE }
    let offset = usize(be16(d, c.variants_at + 10usize + 2usize * vertical + 2usize * index))
    if offset == 0usize { ret NONE }
    ret c.variants_at + offset
}

// The top accent attachment point of a glyph in layout units (MathGlyphInfo), false when the
// glyph has none.
fn top_attach(c: *Ctx, gid: u32, size: f32) -> (f32, bool) {
    if c.info_at == NONE { ret (0.0, false) }
    let d = c.font.data
    let table = usize(be16(d, c.info_at + 2usize))
    if table == 0usize { ret (0.0, false) }
    let at = c.info_at + table
    let cov = usize(be16(d, at))
    if cov == 0usize { ret (0.0, false) }
    let index = coverage_pos(d, at + cov, gid)
    if index == NONE || index >= usize(be16(d, at + 2usize)) { ret (0.0, false) }
    ret (f32(be16s(d, at + 4usize + 4usize * index)) / c.upem * size, true)
}

// The cut-in kern of a glyph's corner (0 top right, 1 top left, 2 bottom right, 3 bottom left)
// at `height` above its baseline, in layout units of a glyph set at `size`: MathKernInfo's step
// function, the first record whose correction height is above `height`, else the last.
fn kern_at(c: *Ctx, gid: u32, corner: usize, height: f32, size: f32) -> f32 {
    if c.info_at == NONE || size <= 0.0 { ret 0.0 }
    let d = c.font.data
    let offset = usize(be16(d, c.info_at + 6usize))
    if offset == 0usize { ret 0.0 }
    let info = c.info_at + offset
    let cov = usize(be16(d, info))
    if cov == 0usize { ret 0.0 }
    let index = coverage_pos(d, info + cov, gid)
    if index == NONE || index >= usize(be16(d, info + 2usize)) { ret 0.0 }
    let table_offset = usize(be16(d, info + 4usize + 8usize * index + 2usize * corner))
    if table_offset == 0usize { ret 0.0 }
    let table = info + table_offset
    let count = usize(be16(d, table))
    let units = height / size * c.upem
    var i = 0usize
    while i < count && units >= f32(be16s(d, table + 2usize + 4usize * i)) { i += 1usize }
    ret f32(be16s(d, table + 2usize + 4usize * count + 4usize * i)) / c.upem * size
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

// The glyph a scalar shapes to alone, 0 when the font lacks it.
fn scalar_gid(c: *Ctx, scalar: u32) -> u32 {
    var buffer: [4]u8 = zero
    let n = unicode.write_utf8(scalar, buffer[0..], 0usize)
    let m = mem.mark(c.a)
    var o: shape.Options = zero
    let (run, shape_error) = shape.shape(c.a, c.font, buffer[..n], o)
    var id = 0u32
    if shape_error == ok && run.glyphs.len > 0usize { id = run.glyphs[0].id }
    mem.reset(c.a, m)
    ret id
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

// A glyph named by id (a MATH variant or part) as one positioned item.
fn id_atom(c: *Ctx, id: u32, scalar: u32, size: f32, class: u8) -> Atom {
    var out: Atom = zero
    out.class = class
    out.first = c.count
    out.last = c.count
    if c.status != ok { ret out }
    let advance = glyph_advance(c, id) * size
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

// The Mathematical Alphanumeric italic form of a Latin or lower-case Greek letter when
// the font has a glyph for it, else the scalar itself.
fn math_italic(c: *Ctx, scalar: u32) -> u32 {
    var want = 0u32
    if scalar >= 97u32 && scalar <= 122u32 {
        want = 119886u32 + (scalar - 97u32)
        if scalar == 104u32 { want = 8462u32 }
    } else if scalar >= 65u32 && scalar <= 90u32 {
        want = 119860u32 + (scalar - 65u32)
    } else if scalar >= 945u32 && scalar <= 969u32 {
        want = 120572u32 + (scalar - 945u32)
    }
    if want == 0u32 || scalar_gid(c, want) == 0u32 { ret scalar }
    ret want
}

// The alphabets `\mathbf` and friends select (Mathematical Alphanumeric Symbols).
const ALPHA_ITALIC: u8 = 0u8
const ALPHA_BOLD: u8 = 1u8
const ALPHA_BOLD_ITALIC: u8 = 2u8
const ALPHA_SCRIPT: u8 = 3u8
const ALPHA_FRAKTUR: u8 = 4u8
const ALPHA_DOUBLE: u8 = 5u8
const ALPHA_SANS: u8 = 6u8
const ALPHA_MONO: u8 = 7u8
const ALPHA_UPRIGHT: u8 = 8u8

// The scalar of `letter` ('A'..'Z' index 0..25, or 26..51 for 'a'..'z') in a block that starts at
// `upper_base`, with the Letterlike Symbols block's holes patched where Unicode puts them.
fn letter_in(alphabet: u8, index: u32) -> u32 {
    if alphabet == ALPHA_SCRIPT {
        // B E F H I L M R, e g o live in Letterlike Symbols.
        if index == 1u32 { ret 8492u32 }
        if index == 4u32 { ret 8496u32 }
        if index == 5u32 { ret 8497u32 }
        if index == 7u32 { ret 8459u32 }
        if index == 8u32 { ret 8464u32 }
        if index == 11u32 { ret 8466u32 }
        if index == 12u32 { ret 8499u32 }
        if index == 17u32 { ret 8475u32 }
        if index == 30u32 { ret 8495u32 }
        if index == 32u32 { ret 8458u32 }
        if index == 40u32 { ret 8500u32 }
        ret 119964u32 + index
    }
    if alphabet == ALPHA_FRAKTUR {
        if index == 2u32 { ret 8493u32 }
        if index == 7u32 { ret 8460u32 }
        if index == 8u32 { ret 8465u32 }
        if index == 17u32 { ret 8476u32 }
        if index == 25u32 { ret 8488u32 }
        ret 120068u32 + index
    }
    if alphabet == ALPHA_DOUBLE {
        if index == 2u32 { ret 8450u32 }
        if index == 7u32 { ret 8461u32 }
        if index == 13u32 { ret 8469u32 }
        if index == 15u32 { ret 8473u32 }
        if index == 16u32 { ret 8474u32 }
        if index == 17u32 { ret 8477u32 }
        if index == 25u32 { ret 8484u32 }
        ret 120120u32 + index
    }
    if alphabet == ALPHA_BOLD { ret 119808u32 + index }
    if alphabet == ALPHA_BOLD_ITALIC { ret 119912u32 + index }
    if alphabet == ALPHA_SANS { ret 120224u32 + index }
    if alphabet == ALPHA_MONO { ret 120432u32 + index }
    ret 0u32
}

// `scalar` in the alphabet `\mathbf`, `\mathcal`, `\mathbb`, `\mathfrak`, `\mathsf`, `\mathtt` or
// `\boldsymbol` selected, when the font has a glyph for the result; otherwise the scalar itself.
// Bold and bold italic also take the Greek letters and the sans, mono and double-struck faces the
// digits, as Unicode has them. `\mathit` (and no command) is `math_italic`.
fn alphabet_scalar(c: *Ctx, scalar: u32) -> u32 {
    if c.alphabet == ALPHA_ITALIC { ret math_italic(c, scalar) }
    if c.alphabet == ALPHA_UPRIGHT { ret scalar }
    var want = 0u32
    if scalar >= 65u32 && scalar <= 90u32 {
        want = letter_in(c.alphabet, scalar - 65u32)
    } else if scalar >= 97u32 && scalar <= 122u32 {
        want = letter_in(c.alphabet, scalar - 97u32 + 26u32)
    } else if scalar >= 48u32 && scalar <= 57u32 {
        var base = 0u32
        if c.alphabet == ALPHA_BOLD || c.alphabet == ALPHA_BOLD_ITALIC { base = 120782u32 }
        if c.alphabet == ALPHA_DOUBLE { base = 120792u32 }
        if c.alphabet == ALPHA_SANS { base = 120802u32 }
        if c.alphabet == ALPHA_MONO { base = 120822u32 }
        if base != 0u32 { want = base + (scalar - 48u32) }
    } else if scalar >= 945u32 && scalar <= 969u32 {
        if c.alphabet == ALPHA_BOLD { want = 120514u32 + (scalar - 945u32) }
        if c.alphabet == ALPHA_BOLD_ITALIC { want = 120630u32 + (scalar - 945u32) }
    }
    if want == 0u32 || scalar_gid(c, want) == 0u32 { ret scalar }
    ret want
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
    out.stretch = false
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
    let em18 = c.size * style_scale(c, style) / 18.0
    var x: f32 = 0.0
    var previous = CLASS_SPACE
    i = 0usize
    while i < n {
        if atoms[i].class != CLASS_SPACE {
            if previous != CLASS_SPACE { x += spacing(previous, atoms[i].class, style_base(style) >= 2u32) * em18 }
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

// Two or more glyphs, all one size on one baseline: a run of letters, which scripts kern against its last.
fn glyph_run(c: *Ctx, a: Atom) -> bool {
    if a.last < a.first + 2usize { ret false }
    let size = c.items[a.last - 1usize].size
    var i = a.first
    while i < a.last {
        let it = c.items[i]
        if it.kind != .Glyph || it.y != 0.0 || it.size != size { ret false }
        i += 1usize
    }
    ret true
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
        // A subscript is set cramped; a superscript keeps the style's own cramping.
        var arg_style = sstyle
        if !up { arg_style = sstyle | STYLE_CRAMPED }
        let arg = parse_argument(c, arg_style)
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
    let s = c.size * style_scale(c, style)
    let ss = c.size * style_scale(c, sstyle)
    let display = c.display && style_base(style) == 0u32
    // Limits over and under a big operator in display style.
    if nucleus.limits && (display || nucleus.stretch) {
        var width = nucleus.width
        if has_sup { width = maxf(width, sup.width) }
        if has_sub { width = maxf(width, sub.width) }
        shift_range(c, nucleus.first, nucleus.last, (width - nucleus.width) / 2.0, 0.0)
        var height = nucleus.height
        var depth = nucleus.depth
        if has_sup {
            let up_shift = nucleus.height + c.k.upper_gap * s + sup.depth
            shift_range(c, sup.first, sup.last, (width - sup.width) / 2.0, 0.0 - up_shift)
            height = up_shift + sup.height
        }
        if has_sub {
            let down_shift = nucleus.depth + c.k.lower_gap * s + sub.height
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
        out.stretch = false
        ret out
    }
    var up_shift: f32 = 0.0
    var down_shift: f32 = 0.0
    if !nucleus.simple {
        up_shift = nucleus.height - c.k.sup_drop * ss
        down_shift = nucleus.depth + c.k.sub_drop * ss
    }
    var sup_min = c.k.sup_text * s
    if display { sup_min = c.k.sup_display * s }
    if style_cramped(style) { sup_min = c.k.sup_cramped * s }
    if has_sup {
        up_shift = maxf(up_shift, sup_min)
        up_shift = maxf(up_shift, sup.depth + c.k.sup_bottom_min * s)
    }
    if has_sub && !has_sup {
        down_shift = maxf(down_shift, c.k.sub_only * s)
        down_shift = maxf(down_shift, sub.height - c.k.sub_top_max * s)
    }
    if has_sub && has_sup {
        down_shift = maxf(down_shift, c.k.sub_both * s)
        let gap = (up_shift - sup.depth) - (sub.height - down_shift)
        let want = c.k.sub_sup_gap * s
        if gap < want {
            down_shift += want - gap
            let psi = c.k.sup_max_with_sub * s - (up_shift - sup.depth)
            if psi > 0.0 {
                up_shift += psi
                down_shift -= psi
            }
        }
    }
    // A single glyph with an italic correction pushes its superscript right of the slant.
    var correction: f32 = 0.0
    if has_sup && nucleus.simple && nucleus.last > nucleus.first {
        let last_item = c.items[nucleus.last - 1usize]
        if last_item.kind == .Glyph { correction = italic_correction(c, last_item.glyph) * last_item.size }
    }
    // MathKernInfo: a single-glyph base and a single-glyph script cut into each other's corners. The
    // base's corner is read at the height of the script's near edge above the base's baseline, the
    // script's corner at the height of the base's near edge above the script's baseline.
    var sup_kern: f32 = 0.0
    var sub_kern: f32 = 0.0
    // D4505: a base that is a run of glyphs on one baseline (`{ab}`, `\mathrm{ab}`) is kerned as its last
    // glyph alone: that glyph's corners at its own height and depth.
    var base_index = NONE
    var base_height = nucleus.height
    var base_depth = nucleus.depth
    if nucleus.simple && nucleus.last == nucleus.first + 1usize && c.items[nucleus.first].kind == .Glyph {
        base_index = nucleus.first
    } else if glyph_run(c, nucleus) {
        base_index = nucleus.last - 1usize
        let (run_low, run_high) = glyph_extent(c, c.items[base_index].glyph)
        base_height = maxf(run_high * c.items[base_index].size, 0.0)
        base_depth = maxf(0.0 - run_low * c.items[base_index].size, 0.0)
    }
    if base_index != NONE {
        let base_item = c.items[base_index]
        if has_sup {
            sup_kern = kern_at(c, base_item.glyph, 0usize, up_shift - sup.depth, base_item.size)
            if sup.simple && sup.last == sup.first + 1usize && c.items[sup.first].kind == .Glyph {
                let script_item = c.items[sup.first]
                sup_kern += kern_at(c, script_item.glyph, 3usize, base_height - up_shift, script_item.size)
            }
        }
        if has_sub {
            sub_kern = kern_at(c, base_item.glyph, 2usize, sub.height - down_shift, base_item.size)
            if sub.simple && sub.last == sub.first + 1usize && c.items[sub.first].kind == .Glyph {
                let script_item = c.items[sub.first]
                sub_kern += kern_at(c, script_item.glyph, 1usize, down_shift - base_depth, script_item.size)
            }
        }
    }
    var width = nucleus.width
    var height = nucleus.height
    var depth = nucleus.depth
    let script_space = c.k.script_space * s
    if has_sup {
        shift_range(c, sup.first, sup.last, nucleus.width + correction + sup_kern, 0.0 - up_shift)
        width = maxf(width, nucleus.width + correction + sup_kern + sup.width + script_space)
        height = maxf(height, up_shift + sup.height)
        depth = maxf(depth, sup.depth - up_shift)
    }
    if has_sub {
        shift_range(c, sub.first, sub.last, nucleus.width + sub_kern, down_shift)
        width = maxf(width, nucleus.width + sub_kern + sub.width + script_space)
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
    out.stretch = false
    ret out
}

// The glyph `scalar` with its ink at least `need` tall: the natural glyph when it is,
// else the font's own variant or assembly (MATH table), else the natural glyph scaled.
// The ink's baseline is the atom's: for an assembly the bottom part sits on it.
fn grown(c: *Ctx, scalar: u32, need: f32, size: f32, class: u8) -> Atom {
    var probe = glyph_atom(c, scalar, size, class)
    if c.status != ok { ret probe }
    let ink = probe.height + probe.depth
    if !(need > ink) || !(ink > 0.0) { ret probe }
    let d = c.font.data
    let cons = construction_of(c, c.items[probe.first].glyph)
    if cons != NONE {
        c.count = probe.first
        let variants = usize(be16(d, cons + 2usize))
        var v = 0usize
        while v < variants {
            let record = cons + 4usize + 4usize * v
            if f32(be16(d, record + 2usize)) / c.upem * size >= need {
                var picked = id_atom(c, be16(d, record), scalar, size, class)
                picked.simple = false
                ret picked
            }
            v += 1usize
        }
        let assembly = usize(be16(d, cons))
        if assembly != 0usize {
            let at = cons + assembly
            let parts = usize(be16(d, at + 4usize))
            let first_part = at + 6usize
            let min_overlap = f32(be16(d, c.variants_at)) / c.upem * size
            var fixed: f32 = 0.0
            var repeated: f32 = 0.0
            var extenders = 0usize
            var p = 0usize
            while p < parts {
                let advance = f32(be16(d, first_part + 10usize * p + 6usize)) / c.upem * size
                if be16(d, first_part + 10usize * p + 8usize) & 1u32 != 0u32 {
                    repeated += advance
                    extenders += 1usize
                } else {
                    fixed += advance
                }
                p += 1usize
            }
            if parts > 0usize && (extenders > 0usize || fixed > 0.0) {
                var reps = 1usize
                var total = fixed + repeated - f32(parts - 1usize) * min_overlap
                while extenders > 0usize && total < need && reps < 64usize {
                    reps += 1usize
                    total = fixed + repeated * f32(reps) - f32(parts - extenders + extenders * reps - 1usize) * min_overlap
                }
                let joints = parts - extenders + extenders * reps - 1usize
                var extra: f32 = 0.0
                if joints > 0usize && total > need { extra = (total - need) / f32(joints) }
                let out_first = c.count
                var width: f32 = 0.0
                var bottom: f32 = 0.0
                var previous_end: f32 = 0.0
                var placed = 0usize
                var q = 0usize
                while q < parts {
                    var times = 1usize
                    let is_extender = be16(d, first_part + 10usize * q + 8usize) & 1u32 != 0u32
                    if is_extender { times = reps }
                    var t = 0usize
                    while t < times {
                        let part_id = be16(d, first_part + 10usize * q)
                        let advance = f32(be16(d, first_part + 10usize * q + 6usize)) / c.upem * size
                        let start_connector = f32(be16(d, first_part + 10usize * q + 2usize)) / c.upem * size
                        var overlap = min_overlap
                        if placed > 0usize {
                            // Overlap more than the minimum only as far as both connectors reach.
                            overlap = min_overlap + minf(extra, maxf(minf(previous_end, start_connector) - min_overlap, 0.0))
                            bottom = bottom - overlap
                        }
                        let (low, high) = glyph_extent(c, part_id)
                        let piece = id_atom(c, part_id, scalar, size, class)
                        if c.status != ok { ret piece }
                        // The part's box bottom sits at `bottom` above the assembly's base.
                        let lift = bottom - low * size
                        c.items[piece.first].y = 0.0 - lift
                        width = maxf(width, piece.width)
                        bottom = bottom + advance
                        previous_end = f32(be16(d, first_part + 10usize * q + 4usize)) / c.upem * size
                        placed += 1usize
                        t += 1usize
                    }
                    q += 1usize
                }
                // Centre the parts horizontally on the widest.
                var r = out_first
                while r < c.count {
                    c.items[r].x = (width - c.items[r].w) / 2.0
                    r += 1usize
                }
                var out: Atom = zero
                out.class = class
                out.first = out_first
                out.last = c.count
                out.width = width
                out.height = bottom
                out.depth = 0.0
                ret out
            }
        }
        if variants > 0usize {
            let record = cons + 4usize + 4usize * (variants - 1usize)
            var biggest = id_atom(c, be16(d, record), scalar, size, class)
            biggest.simple = false
            ret biggest
        }
        // No variant at all: the scaled natural glyph below.
        probe = glyph_atom(c, scalar, size, class)
    }
    let k = need / ink
    c.count = probe.first
    ret glyph_atom(c, scalar, size * k, class)
}

// The glyph `scalar` at least `need` wide: itself when its advance is, else the font's first
// horizontal variant whose declared advance reaches it, else an assembly of left-to-right parts
// (extenders repeated until the overlapped total reaches `need`, then overlapped further as far as
// the joined connectors allow), else the widest variant, else the glyph as it is. Every piece sits on
// the atom's baseline; the atom's width is the advance (the assembly's total).
fn grown_h(c: *Ctx, scalar: u32, need: f32, size: f32, class: u8) -> Atom {
    let probe = glyph_atom(c, scalar, size, class)
    if c.status != ok { ret probe }
    if !(need > probe.width) { ret probe }
    let d = c.font.data
    let cons = construction_h(c, c.items[probe.first].glyph)
    if cons == NONE { ret probe }
    let variants = usize(be16(d, cons + 2usize))
    var v = 0usize
    while v < variants {
        let record = cons + 4usize + 4usize * v
        if f32(be16(d, record + 2usize)) / c.upem * size >= need {
            c.count = probe.first
            var picked = id_atom(c, be16(d, record), scalar, size, class)
            picked.simple = false
            ret picked
        }
        v += 1usize
    }
    let assembly = usize(be16(d, cons))
    if assembly != 0usize {
        let at = cons + assembly
        let parts = usize(be16(d, at + 4usize))
        let first_part = at + 6usize
        let min_overlap = f32(be16(d, c.variants_at)) / c.upem * size
        var fixed: f32 = 0.0
        var repeated: f32 = 0.0
        var extenders = 0usize
        var p = 0usize
        while p < parts {
            let advance = f32(be16(d, first_part + 10usize * p + 6usize)) / c.upem * size
            if be16(d, first_part + 10usize * p + 8usize) & 1u32 != 0u32 {
                repeated += advance
                extenders += 1usize
            } else {
                fixed += advance
            }
            p += 1usize
        }
        if parts > 0usize && (extenders > 0usize || fixed > 0.0) {
            var reps = 1usize
            var total = fixed + repeated - f32(parts - 1usize) * min_overlap
            while extenders > 0usize && total < need && reps < 64usize {
                reps += 1usize
                total = fixed + repeated * f32(reps) - f32(parts - extenders + extenders * reps - 1usize) * min_overlap
            }
            let joints = parts - extenders + extenders * reps - 1usize
            var extra: f32 = 0.0
            if joints > 0usize && total > need { extra = (total - need) / f32(joints) }
            c.count = probe.first
            let out_first = c.count
            var pen: f32 = 0.0
            var previous_end: f32 = 0.0
            var placed = 0usize
            var top: f32 = 0.0
            var bottom: f32 = 0.0
            var q = 0usize
            while q < parts {
                var times = 1usize
                if be16(d, first_part + 10usize * q + 8usize) & 1u32 != 0u32 { times = reps }
                var t = 0usize
                while t < times {
                    let part_id = be16(d, first_part + 10usize * q)
                    let advance = f32(be16(d, first_part + 10usize * q + 6usize)) / c.upem * size
                    let start_connector = f32(be16(d, first_part + 10usize * q + 2usize)) / c.upem * size
                    if placed > 0usize {
                        // Overlap more than the minimum only as far as both connectors reach.
                        let overlap = min_overlap + minf(extra, maxf(minf(previous_end, start_connector) - min_overlap, 0.0))
                        pen = pen - overlap
                    }
                    let piece = id_atom(c, part_id, scalar, size, class)
                    if c.status != ok { ret piece }
                    c.items[piece.first].x = pen
                    top = maxf(top, piece.height)
                    bottom = maxf(bottom, piece.depth)
                    pen = pen + advance
                    previous_end = f32(be16(d, first_part + 10usize * q + 4usize)) / c.upem * size
                    placed += 1usize
                    t += 1usize
                }
                q += 1usize
            }
            var out: Atom = zero
            out.class = class
            out.first = out_first
            out.last = c.count
            out.width = pen
            out.height = top
            out.depth = bottom
            ret out
        }
    }
    if variants > 0usize {
        let record = cons + 4usize + 4usize * (variants - 1usize)
        c.count = probe.first
        var biggest = id_atom(c, be16(d, record), scalar, size, class)
        biggest.simple = false
        ret biggest
    }
    ret probe
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
    var out = grown(c, scalar, span_h, size, class)
    if c.status != ok { ret out }
    // Centre the ink on the axis.
    let lift = c.k.axis * size - (out.height - out.depth) / 2.0
    shift_range(c, out.first, out.last, 0.0, 0.0 - lift)
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
    let s = c.size * style_scale(c, style)
    let axis = c.k.axis * s
    var delta = maxf(body.height - axis, body.depth + axis)
    var span_h = 2.0 * delta * 0.95
    if span_h < c.k.delim_min * s { span_h = c.k.delim_min * s }
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
    // The denominator is cramped.
    let denominator = parse_argument(c, child | STYLE_CRAMPED)
    var out: Atom = zero
    out.class = CLASS_INNER
    out.first = numerator.first
    if c.status != ok { ret out }
    let s = c.size * style_scale(c, style)
    let display = c.display && style_base(style) == 0u32
    let theta = c.k.rule * s
    let axis = c.k.axis * s
    var up = c.k.num_text * s
    var down = c.k.den_text * s
    var up_gap = c.k.num_gap * s
    var down_gap = c.k.den_gap * s
    if display {
        up = c.k.num_display * s
        down = c.k.den_display * s
        up_gap = c.k.num_gap_display * s
        down_gap = c.k.den_gap_display * s
    }
    if (up - numerator.depth) - (axis + theta / 2.0) < up_gap { up += up_gap - ((up - numerator.depth) - (axis + theta / 2.0)) }
    if (axis - theta / 2.0) - (denominator.height - down) < down_gap { down += down_gap - ((axis - theta / 2.0) - (denominator.height - down)) }
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
    // The radicand is cramped.
    let body = parse_argument(c, style | STYLE_CRAMPED)
    if c.status != ok { ret out }
    let s = c.size * style_scale(c, style)
    let theta = c.k.rad_rule * s
    var clearance = c.k.rad_gap * s
    if c.display && style_base(style) == 0u32 { clearance = c.k.rad_gap_display * s }
    let need = body.height + body.depth + clearance + theta
    // The radical sign, grown to `need`.
    let sign = grown(c, 8730u32, need, s, CLASS_ORD)
    if c.status != ok { ret out }
    // Sit the sign's bottom at the body's bottom plus the clearance's share.
    let top_of_bar = body.height + clearance + theta
    shift_range(c, sign.first, sign.last, 0.0, 0.0 - (top_of_bar - sign.height))
    var sign_x: f32 = 0.0
    var index_x: f32 = 0.0
    if has_index {
        index_x = maxf(c.k.rad_before * s, 0.0)
        sign_x = maxf(index_x + index.width + c.k.rad_after * s, 0.0)
        let raise = c.k.rad_raise * (top_of_bar + body.depth) - body.depth
        shift_range(c, index.first, index.last, index_x, 0.0 - raise)
    }
    shift_range(c, sign.first, sign.last, sign_x, 0.0)
    shift_range(c, body.first, body.last, sign_x + sign.width, 0.0)
    push_rule(c, sign_x + sign.width, 0.0 - top_of_bar, body.width, theta)
    out.last = c.count
    out.width = sign_x + sign.width + body.width
    out.height = top_of_bar + c.k.rad_extra * s
    out.depth = maxf(body.depth, sign.depth - (top_of_bar - sign.height))
    if has_index { out.height = maxf(out.height, c.k.rad_raise * (top_of_bar + body.depth) - body.depth + index.height) }
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

// A row's `\tag` of an `align` or `gather` (D4505): where its text is in the source, and the row.
type RowTag = struct { at: usize, len: usize, star: bool, row: usize }

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
    // 1: columns alternate right and left aligned, pairs one em apart; 2: rows centred.
    var aligned_kind = 0u32
    // `align` and `gather` (not their nested forms) number a row by its `\tag` in a column on the right.
    var numbered = false
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
    } else if word_is(name, "align") || word_is(name, "align*") || word_is(name, "aligned") {
        aligned_kind = 1u32
        numbered = !word_is(name, "aligned")
    } else if word_is(name, "gather") || word_is(name, "gather*") || word_is(name, "gathered") {
        aligned_kind = 2u32
        numbered = !word_is(name, "gathered")
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
    var cell_style = 1u32
    if aligned_kind != 0u32 && c.display { cell_style = 0u32 }
    let (tags, tags_error) = mem.alloc[RowTag](c.a, c.src.len - c.pos + 2usize)
    if tags_error != ok {
        fail(c, Invalid)
        c.nest -= 1usize
        ret out
    }
    var tag_count = 0usize
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
            if numbered && c.tag_at != NONE {
                tags[tag_count] = RowTag { at: c.tag_at, len: c.tag_len, star: c.tag_star, row: row }
                tag_count += 1usize
                c.tag_at = NONE
            }
            row += 1usize
            col = 0usize
            skip_space(c)
            // A trailing row separator before \end adds no row.
            if at_command(c, "end") { break }
        } else if at_command(c, "end") {
            if numbered && c.tag_at != NONE {
                tags[tag_count] = RowTag { at: c.tag_at, len: c.tag_len, star: c.tag_star, row: row }
                tag_count += 1usize
                c.tag_at = NONE
            }
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
    let (col_x, col_x_error) = mem.alloc[f32](c.a, columns + 1usize)
    let (row_h, row_h_error) = mem.alloc[f32](c.a, rows + 1usize)
    let (row_d, row_d_error) = mem.alloc[f32](c.a, rows + 1usize)
    if col_error != ok || col_x_error != ok || row_h_error != ok || row_d_error != ok {
        mem.reset(c.a, m)
        c.nest -= 1usize
        fail(c, Invalid)
        ret out
    }
    let s = c.size * style_scale(c, style)
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
    // Column origins: an em between columns, except inside an `align` pair.
    var total_w: f32 = 0.0
    i = 0usize
    while i < columns {
        col_x[i] = total_w
        total_w += col_w[i]
        if i + 1usize < columns {
            var gap = s
            if aligned_kind == 1u32 && i % 2usize == 0usize { gap = 0.0 }
            total_w += gap
        }
        i += 1usize
    }
    let top = c.k.axis * s + total_h / 2.0
    i = 0usize
    while i < n {
        var x = col_x[cells[i].col]
        if aligned_kind == 1u32 {
            if cells[i].col % 2usize == 0usize { x += col_w[cells[i].col] - cells[i].atom.width }
        } else if !left_align {
            x += (col_w[cells[i].col] - cells[i].atom.width) / 2.0
        }
        var above = top
        var j = 0usize
        while j < cells[i].row {
            above -= row_h[j] + row_d[j]
            j += 1usize
        }
        above -= row_h[cells[i].row]
        shift_range(c, cells[i].atom.first, cells[i].atom.last, x, 0.0 - above)
        i += 1usize
    }
    // Row numbers: a right-aligned column an em right of the table.
    var body_width = total_w
    if tag_count > 0usize {
        let (numbers, numbers_error) = mem.alloc[Atom](c.a, tag_count)
        if numbers_error != ok {
            mem.reset(c.a, m)
            c.nest -= 1usize
            fail(c, Invalid)
            ret out
        }
        var widest: f32 = 0.0
        var t = 0usize
        while t < tag_count {
            numbers[t] = number_atom(c, c.src[tags[t].at..tags[t].at + tags[t].len], tags[t].star)
            widest = maxf(widest, numbers[t].width)
            t += 1usize
        }
        t = 0usize
        while t < tag_count {
            var above = top
            var j = 0usize
            while j < tags[t].row {
                above -= row_h[j] + row_d[j]
                j += 1usize
            }
            above -= row_h[tags[t].row]
            shift_range(c, numbers[t].first, numbers[t].last, total_w + s + (widest - numbers[t].width), 0.0 - above)
            t += 1usize
        }
        body_width = total_w + s + widest
    }
    var body: Atom = zero
    body.first = out.first
    body.last = c.count
    body.width = body_width
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
    var out = text_atom(c, raw, c.size * style_scale(c, style), CLASS_ORD)
    out.simple = false
    ret out
}

fn space_atom(c: *Ctx, em18: f32, style: u32) -> Atom {
    var out: Atom = zero
    out.class = CLASS_SPACE
    out.first = c.count
    out.last = c.count
    out.width = em18 * c.size * style_scale(c, style) / 18.0
    ret out
}

// `\tag{text}` and `\tag*{text}` (L098, D4505): the equation's number, remembered for the end of the row
// (`typeset_numbered`, or an `align` row's right column); in the row itself it is a zero-width space.
fn lay_tag(c: *Ctx) -> Atom {
    var out: Atom = zero
    out.class = CLASS_SPACE
    out.first = c.count
    out.last = c.count
    var star = false
    if byte_at(c, c.pos) == 42u8 {
        star = true
        c.pos += 1usize
    }
    expect_byte(c, 123u8)
    let start = c.pos
    while c.pos < c.src.len && c.src[c.pos] != 125u8 { c.pos += 1usize }
    let len = c.pos - start
    expect_byte(c, 125u8)
    if c.status != ok { ret out }
    if c.tag_at != NONE {
        fail(c, Invalid)
        ret out
    }
    c.tag_at = start
    c.tag_len = len
    c.tag_star = star
    ret out
}

// The number `(text)`, or `text` for a starred tag, upright at the equation's size, at its own origin.
fn number_atom(c: *Ctx, raw: str, star: bool) -> Atom {
    var out: Atom = zero
    out.class = CLASS_ORD
    out.first = c.count
    out.last = c.count
    if c.status != ok { ret out }
    var x: f32 = 0.0
    var height: f32 = 0.0
    var depth: f32 = 0.0
    if !star {
        let open = glyph_atom(c, 40u32, c.size, CLASS_ORD)
        if c.status != ok { ret out }
        x = open.width
        height = open.height
        depth = open.depth
    }
    let body = text_atom(c, raw, c.size, CLASS_ORD)
    if c.status != ok { ret out }
    shift_range(c, body.first, body.last, x, 0.0)
    x += body.width
    height = maxf(height, body.height)
    depth = maxf(depth, body.depth)
    if !star {
        let close = glyph_atom(c, 41u32, c.size, CLASS_ORD)
        if c.status != ok { ret out }
        shift_range(c, close.first, close.last, x, 0.0)
        x += close.width
        height = maxf(height, close.height)
        depth = maxf(depth, close.depth)
    }
    out.last = c.count
    out.width = x
    out.height = height
    out.depth = depth
    ret out
}

// `\substack{a \\ b}` (L098, D4505): the rows, each centred, one baseline skip of 1.2 em of the style apart,
// the block centred on the axis. It is meant for a script or limit, so its rows take the style it is parsed in.
fn lay_substack(c: *Ctx, style: u32) -> Atom {
    var out: Atom = zero
    out.class = CLASS_ORD
    out.first = c.count
    out.last = c.count
    expect_byte(c, 123u8)
    if c.status != ok { ret out }
    if c.nest >= MAX_NEST {
        fail(c, TooDeep)
        ret out
    }
    c.nest += 1usize
    let m = mem.mark(c.a)
    let (cells, cells_error) = mem.alloc[Atom](c.a, c.src.len - c.pos + 2usize)
    if cells_error != ok {
        fail(c, Invalid)
        c.nest -= 1usize
        ret out
    }
    var n = 0usize
    var more = true
    while more && c.status == ok {
        let cell = parse_row(c, style)
        if c.status != ok { break }
        cells[n] = cell
        n += 1usize
        skip_space(c)
        if byte_at(c, c.pos) == 92u8 && byte_at(c, c.pos + 1usize) == 92u8 {
            c.pos += 2usize
            skip_space(c)
            if byte_at(c, c.pos) == 125u8 {
                c.pos += 1usize
                more = false
            }
        } else if byte_at(c, c.pos) == 125u8 {
            c.pos += 1usize
            more = false
        } else {
            fail(c, Invalid)
        }
    }
    if c.status != ok {
        mem.reset(c.a, m)
        c.nest -= 1usize
        ret out
    }
    let s = c.size * style_scale(c, style)
    var width: f32 = 0.0
    var total: f32 = 0.0
    var i = 0usize
    while i < n {
        width = maxf(width, cells[i].width)
        total += maxf(0.84 * s, cells[i].height) + maxf(0.36 * s, cells[i].depth)
        i += 1usize
    }
    let top = c.k.axis * s + total / 2.0
    var used: f32 = 0.0
    i = 0usize
    while i < n {
        let h = maxf(0.84 * s, cells[i].height)
        let d = maxf(0.36 * s, cells[i].depth)
        // The row's baseline sits `used + h` below the top.
        shift_range(c, cells[i].first, cells[i].last, (width - cells[i].width) / 2.0, used + h - top)
        used += h + d
        i += 1usize
    }
    mem.reset(c.a, m)
    c.nest -= 1usize
    out.last = c.count
    out.width = width
    out.height = top
    out.depth = total - top
    ret out
}

// `\big` `\Big` `\bigg` `\Bigg` with an `l`, `r` or `m` for the class (open, close, relation; none: ordinary):
// the delimiter's size in ems of the equation's size, else 0.
fn big_scale(word: str) -> f32 {
    if word.len < 3usize || word.len > 5usize { ret 0.0 }
    var root = word
    if word[word.len - 1usize] == 108u8 || word[word.len - 1usize] == 114u8 || word[word.len - 1usize] == 109u8 {
        // Only l, r and m are suffixes (`bigg` ends in g).
        root = word[0usize..word.len - 1usize]
    }
    if word_is(root, "big") { ret 1.2 }
    if word_is(root, "Big") { ret 1.8 }
    if word_is(root, "bigg") { ret 2.4 }
    if word_is(root, "Bigg") { ret 3.0 }
    ret 0.0
}

fn big_class(word: str) -> u8 {
    let last = word[word.len - 1usize]
    if last == 108u8 { ret CLASS_OPEN }
    if last == 114u8 { ret CLASS_CLOSE }
    if last == 109u8 { ret CLASS_REL }
    ret CLASS_ORD
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
    let s = c.size * style_scale(c, style)
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
        ret glyph_atom(c, alphabet_scalar(c, mapped), s, char_class(mapped))
    }
    c.pos += 1usize
    let word = command_word(c)
    if word.len == 0usize {
        fail(c, Invalid)
        ret out
    }
    if word_is(word, "frac") { ret lay_fraction(c, style) }
    if word_is(word, "sqrt") { ret lay_radical(c, style) }
    if word_is(word, "tag") { ret lay_tag(c) }
    if word_is(word, "notag") || word_is(word, "nonumber") { ret space_atom(c, 0.0, style) }
    if word_is(word, "substack") { ret lay_substack(c, style) }
    let big_factor = big_scale(word)
    if big_factor > 0.0 {
        // `\big(`: the delimiter at a fixed multiple of the equation's size, whatever the style.
        let scalar = delimiter_scalar(c)
        if c.status != ok { ret out }
        var sized = delimiter(c, scalar, big_factor * c.size, c.size, big_class(word))
        sized.simple = false
        ret sized
    }
    let alpha = alphabet_of(word)
    if alpha != 255u8 {
        // `\mathbf{...}` and the like: the group's letters and digits in that alphabet.
        let saved = c.alphabet
        c.alphabet = alpha
        let arg = parse_argument(c, style)
        c.alphabet = saved
        ret as_atom(arg, CLASS_ORD)
    }
    let accent = accent_scalar(word)
    if accent != 0u32 {
        let base = parse_argument(c, style | STYLE_CRAMPED)
        ret accent_over(c, base, accent, word_is(word, "widehat") || word_is(word, "widetilde"), false, s)
    }
    if word_is(word, "overline") { ret lay_bar(c, style, true) }
    if word_is(word, "underline") { ret lay_bar(c, style, false) }
    if word_is(word, "overbrace") { ret lay_brace(c, style, true) }
    if word_is(word, "underbrace") { ret lay_brace(c, style, false) }
    if word_is(word, "overaccent") || word_is(word, "underaccent") {
        // `\overaccent{c}{base}`: the translation of MathML's accented `mover` and `munder`, the
        // accent named by a character (a brace character is `\overbrace`), set as wide as the base.
        expect_byte(c, 123u8)
        let (accent_char, accent_step) = unicode.read_utf8(c.src, c.pos)
        c.pos += accent_step
        expect_byte(c, 125u8)
        let under = word_is(word, "underaccent")
        if accent_char == 9182u32 { ret lay_brace(c, style, true) }
        if accent_char == 9183u32 { ret lay_brace(c, style, false) }
        var arg_style = style
        if !under { arg_style = style | STYLE_CRAMPED }
        let base = parse_argument(c, arg_style)
        ret accent_over(c, base, accent_form(accent_char), true, under, s)
    }
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
        let big = c.display && style_base(style) == 0u32
        var op: Atom = zero
        if big && c.k.op_min > 0.0 {
            // The font names a minimum height for a display operator: its variant.
            op = grown(c, scalar, c.k.op_min * s, s, CLASS_OP)
        } else if big {
            op = glyph_atom(c, scalar, s * 1.4, CLASS_OP)
        } else {
            op = glyph_atom(c, scalar, s, CLASS_OP)
        }
        if c.status != ok { ret op }
        // Centre the operator on the axis.
        let lift = c.k.axis * s - (op.height - op.depth) / 2.0
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
    if scalar != 0u32 { ret glyph_atom(c, alphabet_scalar(c, scalar), s, class) }
    fail(c, Invalid)
    ret out
}

// The alphabet a font command names, or 255 for a word that is not one.
fn alphabet_of(word: str) -> u8 {
    if word_is(word, "mathbf") || word_is(word, "mathbfup") { ret ALPHA_BOLD }
    if word_is(word, "boldsymbol") || word_is(word, "mathbfit") { ret ALPHA_BOLD_ITALIC }
    if word_is(word, "mathcal") || word_is(word, "mathscr") { ret ALPHA_SCRIPT }
    if word_is(word, "mathfrak") { ret ALPHA_FRAKTUR }
    if word_is(word, "mathbb") { ret ALPHA_DOUBLE }
    if word_is(word, "mathsf") { ret ALPHA_SANS }
    if word_is(word, "mathtt") { ret ALPHA_MONO }
    if word_is(word, "mathit") { ret ALPHA_ITALIC }
    ret 255u8
}

// The combining accent a LaTeX accent command names, or 0.
fn accent_scalar(word: str) -> u32 {
    if word_is(word, "hat") || word_is(word, "widehat") { ret 770u32 }
    if word_is(word, "tilde") || word_is(word, "widetilde") { ret 771u32 }
    if word_is(word, "bar") { ret 772u32 }
    if word_is(word, "breve") { ret 774u32 }
    if word_is(word, "dot") { ret 775u32 }
    if word_is(word, "ddot") { ret 776u32 }
    if word_is(word, "mathring") { ret 778u32 }
    if word_is(word, "check") { ret 780u32 }
    if word_is(word, "acute") { ret 769u32 }
    if word_is(word, "grave") { ret 768u32 }
    if word_is(word, "vec") { ret 8407u32 }
    ret 0u32
}

// An accent given as a character (as MathML names them): the combining form it stands for, or the
// character itself.
fn accent_form(scalar: u32) -> u32 {
    if scalar == 94u32 || scalar == 710u32 { ret 770u32 }
    if scalar == 126u32 || scalar == 732u32 { ret 771u32 }
    if scalar == 175u32 || scalar == 8254u32 { ret 772u32 }
    if scalar == 728u32 { ret 774u32 }
    if scalar == 729u32 { ret 775u32 }
    if scalar == 168u32 { ret 776u32 }
    if scalar == 730u32 { ret 778u32 }
    if scalar == 711u32 { ret 780u32 }
    if scalar == 180u32 { ret 769u32 }
    if scalar == 96u32 { ret 768u32 }
    if scalar == 8594u32 { ret 8407u32 }
    ret scalar
}

// An accent over (or under) `base`, laid out; `wide` picks a horizontal variant as wide as the base.
// The accent is centred by the two attachment points (a glyph's MathTopAccentAttachment, else half its
// advance) and raised by the base's height over the font's AccentBaseHeight when it has more.
fn accent_over(c: *Ctx, base: Atom, scalar: u32, wide: bool, below: bool, size: f32) -> Atom {
    var out = base
    if c.status != ok { ret out }
    var accent: Atom = zero
    if wide { accent = grown_h(c, scalar, base.width, size, CLASS_ORD) } else { accent = glyph_atom(c, scalar, size, CLASS_ORD) }
    if c.status != ok { ret out }
    var base_attach = base.width / 2.0
    if base.last == base.first + 1usize && c.items[base.first].kind == .Glyph {
        let item = c.items[base.first]
        let (point, has_point) = top_attach(c, item.glyph, item.size)
        if has_point { base_attach = point }
    }
    var accent_attach = accent.width / 2.0
    if accent.last == accent.first + 1usize {
        let (point, has_point) = top_attach(c, c.items[accent.first].glyph, size)
        if has_point { accent_attach = point }
    }
    var lift = 0.0f32
    var drop = 0.0f32
    if below {
        drop = base.depth + c.k.under_gap * size + accent.height
    } else {
        lift = maxf(0.0, base.height - c.k.accent_base * size)
    }
    shift_range(c, accent.first, accent.last, base_attach - accent_attach, drop - lift)
    out.last = c.count
    out.simple = false
    out.limits = false
    out.class = CLASS_ORD
    if below {
        out.depth = maxf(base.depth, drop + accent.depth)
    } else {
        out.height = maxf(base.height, lift + accent.height)
    }
    ret out
}

// `\overline`, `\underline`: a rule across the body with the font's gap and extra extent.
fn lay_bar(c: *Ctx, style: u32, over: bool) -> Atom {
    var arg_style = style
    if over { arg_style = style | STYLE_CRAMPED }
    let body = parse_argument(c, arg_style)
    var out = body
    if c.status != ok { ret out }
    let s = c.size * style_scale(c, style)
    if over {
        let gap = c.k.over_gap * s
        let thick = c.k.over_rule * s
        push_rule(c, 0.0, 0.0 - (body.height + gap + thick), body.width, thick)
        out.height = body.height + gap + thick + c.k.over_extra * s
    } else {
        let gap = c.k.under_gap * s
        let thick = c.k.under_rule * s
        push_rule(c, 0.0, body.depth + gap, body.width, thick)
        out.depth = body.depth + gap + thick + c.k.under_extra * s
    }
    out.last = c.count
    out.simple = false
    out.limits = false
    out.class = CLASS_ORD
    ret out
}

// `\overbrace`, `\underbrace`: the brace glyph stretched to the body's width, a gap from it, an
// operator with limits so that `^` and `_` place a label beyond the brace.
fn lay_brace(c: *Ctx, style: u32, over: bool) -> Atom {
    let body = parse_argument(c, style)
    var out = body
    if c.status != ok { ret out }
    let s = c.size * style_scale(c, style)
    var scalar = 9183u32
    if over { scalar = 9182u32 }
    let brace = grown_h(c, scalar, body.width, s, CLASS_ORD)
    if c.status != ok { ret out }
    // The brace's ink sits `gap` clear of the body (StretchStackGapBelowMin above it, AboveMin under it).
    let centre = (maxf(body.width, brace.width) - brace.width) / 2.0
    if over {
        let gap = c.k.stretch_below * s
        shift_range(c, brace.first, brace.last, centre, 0.0 - (body.height + gap + brace.depth))
        out.height = body.height + gap + brace.depth + brace.height
    } else {
        let gap = c.k.stretch_above * s
        shift_range(c, brace.first, brace.last, centre, body.depth + gap + brace.height)
        out.depth = body.depth + gap + brace.height + brace.depth
    }
    if brace.width > body.width { shift_range(c, body.first, body.last, (brace.width - body.width) / 2.0, 0.0) }
    out.width = maxf(body.width, brace.width)
    out.last = c.count
    out.simple = false
    out.limits = true
    out.stretch = true
    out.class = CLASS_OP
    ret out
}

fn font_ready(c: *Ctx) -> bool {
    if shape.validate_font(c.font) != ok { ret false }
    let d = c.font.data
    c.head_at = find_table(d, 1751474532u32)
    c.maxp_at = find_table(d, 1835104368u32)
    c.loca_at = find_table(d, 1819239265u32)
    c.glyf_at = find_table(d, 1735162214u32)
    c.hhea_at = find_table(d, 1751672161u32)
    c.hmtx_at = find_table(d, 1752003704u32)
    if c.head_at == NONE { ret false }
    c.upem = f32(be16(d, c.head_at + 18usize))
    ret c.upem > 0.0
}

fn context(a: *mem.Arena, source: str, options: Options, items: []Item) -> (Ctx, bool) {
    var c: Ctx = zero
    c.a = a
    c.font = options.font
    c.items = items
    c.src = source
    c.size = options.size
    c.display = options.display
    c.notdef = options.notdef
    c.status = ok
    c.tag_at = NONE
    if !font_ready(&c) { ret (c, false) }
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
    load_math(&c)
    ret (c, true)
}

// Typesets `source` at `options.size` into `items`.
fn typeset(a: *mem.Arena, source: str, options: Options, items: []Item) -> (Equation, err) {
    let (eq, eq_error) = typeset_numbered(a, source, options, 0.0, items)
    ret (eq, eq_error)
}

// As `typeset`, in a line `line_width` wide (0: as wide as the equation) (L098, D4505). The equation is centred
// in the line; a `\tag{n}` puts `(n)` flush right (`\tag*{n}` without the parentheses), the equation moved
// left if it would come within an em of it, and past the equation by an em when the line has no room. Without
// a tag and with no line width the result is `typeset`'s. `width` is the line's, or the equation's and its
// number's together.
fn typeset_numbered(a: *mem.Arena, source: str, options: Options, line_width: f32, items: []Item) -> (Equation, err) {
    if options.size <= 0.0 || source.len == 0usize { ret (zero, Invalid) }
    let (made_value, ready) = context(a, source, options, items)
    if !ready { ret (zero, Invalid) }
    var made = made_value
    var style = 1u32
    if options.display { style = 0u32 }
    let row = parse_row(&made, style)
    if made.status == ok && made.pos < made.src.len { made.status = Invalid }
    if made.status != ok { ret (zero, made.status) }
    var eq: Equation = zero
    var width = row.width
    var ascent = row.height
    var descent = row.depth
    var eq_x: f32 = 0.0
    if made.tag_at != NONE {
        let number = number_atom(&made, source[made.tag_at..made.tag_at + made.tag_len], made.tag_star)
        if made.status != ok { ret (zero, made.status) }
        let gap = options.size
        var number_x = row.width + gap
        if line_width > 0.0 {
            number_x = line_width - number.width
            eq_x = (line_width - row.width) / 2.0
            if eq_x + row.width + gap > number_x {
                eq_x = maxf(0.0, number_x - gap - row.width)
                if eq_x + row.width + gap > number_x { number_x = eq_x + row.width + gap }
            }
        }
        shift_range(&made, row.first, row.last, eq_x, 0.0)
        shift_range(&made, number.first, number.last, number_x, 0.0)
        width = maxf(line_width, number_x + number.width)
        ascent = maxf(ascent, number.height)
        descent = maxf(descent, number.depth)
    } else if line_width > row.width {
        eq_x = (line_width - row.width) / 2.0
        shift_range(&made, row.first, row.last, eq_x, 0.0)
        width = line_width
    }
    eq.items = items[..made.count]
    eq.width = width
    eq.ascent = ascent
    eq.descent = descent
    ret (eq, ok)
}

// --- Drawing.

// The glyph items as one `e.text.layout.Layout` line, a run of one glyph per item at
// its pen, for `e.gfx.scene`'s `DrawText` (the font must be registered with the
// renderer). Rule items are not glyphs: fill the rectangle `(x, y, w, h)` of each.
fn to_layout(a: *mem.Arena, eq: Equation, font: shape.Font) -> (layout.Layout, err) {
    var glyphs = 0usize
    var i = 0usize
    while i < eq.items.len {
        if eq.items[i].kind == .Glyph { glyphs += 1usize }
        i += 1usize
    }
    let (runs, runs_error) = mem.alloc[layout.GlyphRun](a, glyphs + 1usize)
    if runs_error != ok { ret (zero, runs_error) }
    let (shapes, shapes_error) = mem.alloc[shape.Glyph](a, glyphs + 1usize)
    if shapes_error != ok { ret (zero, shapes_error) }
    let (lines, lines_error) = mem.alloc[layout.Line](a, 1usize)
    if lines_error != ok { ret (zero, lines_error) }
    var n = 0usize
    i = 0usize
    while i < eq.items.len {
        let item = eq.items[i]
        if item.kind == .Glyph && item.size > 0.0 {
            shapes[n] = shape.Glyph { id: item.glyph, cluster: 0usize, advance_x: item.w / item.size, advance_y: 0.0, offset_x: 0.0, offset_y: 0.0 }
            let run = shape.Run { font: font.id, direction: shape.Direction.LeftToRight, script: 0u32, language: "", glyphs: shapes[n..n + 1usize] }
            runs[n] = layout.GlyphRun { run: run, origin: geometry.Point { x: item.x, y: item.y }, size: item.size }
            n += 1usize
        }
        i += 1usize
    }
    let bounds = geometry.Rect { x: 0.0, y: 0.0 - eq.ascent, width: eq.width, height: eq.ascent + eq.descent }
    lines[0usize] = layout.Line { runs: runs[..n], bounds: bounds, baseline: 0.0, start: 0usize, end: 0usize }
    ret (layout.Layout { source: "", lines: lines[0usize..1usize], bounds: bounds }, ok)
}

// --- Presentation MathML, translated to the LaTeX subset and typeset by it.

type Ml = struct { src: str, pos: usize, out: str.Builder, status: err, depth: usize }

fn ml_fail(m: *Ml, why: err) {
    if m.status == ok { m.status = why }
}

fn ml_space(m: *Ml) {
    while m.pos < m.src.len && (m.src[m.pos] == 32u8 || m.src[m.pos] == 10u8 || m.src[m.pos] == 9u8 || m.src[m.pos] == 13u8) { m.pos += 1usize }
}

fn ml_push(m: *Ml, text: str) {
    if m.status != ok { ret }
    let e = str.push(&m.out, text)
    if e != ok { m.status = TooSmall }
}

// The tag at the cursor: `<`, then a name, then attributes up to `>`. Gives the
// name, the attribute text, whether it closes (`</`) and whether it is empty (`/>`).
type Tag = struct { name: str, attrs: str, closing: bool, empty: bool }

fn ml_tag(m: *Ml) -> Tag {
    var t: Tag = zero
    if m.pos >= m.src.len || m.src[m.pos] != 60u8 {
        ml_fail(m, Invalid)
        ret t
    }
    var i = m.pos + 1usize
    if i < m.src.len && m.src[i] == 47u8 {
        t.closing = true
        i += 1usize
    }
    let name_start = i
    while i < m.src.len && m.src[i] != 62u8 && m.src[i] != 32u8 && m.src[i] != 47u8 && m.src[i] != 10u8 && m.src[i] != 9u8 { i += 1usize }
    var name = m.src[name_start..i]
    // Drop a namespace prefix.
    var p = 0usize
    while p < name.len {
        if name[p] == 58u8 {
            name = name[p + 1usize..name.len]
            break
        }
        p += 1usize
    }
    t.name = name
    let attrs_start = i
    var quote = 0u8
    while i < m.src.len {
        let ch = m.src[i]
        if quote != 0u8 {
            if ch == quote { quote = 0u8 }
        } else if ch == 34u8 || ch == 39u8 {
            quote = ch
        } else if ch == 62u8 {
            break
        }
        i += 1usize
    }
    if i >= m.src.len {
        ml_fail(m, Invalid)
        ret t
    }
    t.attrs = m.src[attrs_start..i]
    if t.attrs.len > 0usize && t.attrs[t.attrs.len - 1usize] == 47u8 {
        t.empty = true
        t.attrs = t.attrs[0usize..t.attrs.len - 1usize]
    }
    m.pos = i + 1usize
    ret t
}

// The value of attribute `want` in a tag's attribute text, "" with `found` false.
fn ml_attr(attrs: str, want: str) -> (str, bool) {
    var i = 0usize
    while i + want.len < attrs.len {
        let boundary = i == 0usize || attrs[i - 1usize] == 32u8 || attrs[i - 1usize] == 10u8 || attrs[i - 1usize] == 9u8
        if boundary && word_is(attrs[i..i + want.len], want) && attrs[i + want.len] == 61u8 && i + want.len + 1usize < attrs.len {
            let quote = attrs[i + want.len + 1usize]
            var j = i + want.len + 2usize
            let first = j
            while j < attrs.len && attrs[j] != quote { j += 1usize }
            ret (attrs[first..j], true)
        }
        i += 1usize
    }
    ret ("", false)
}

// The text content up to the closing tag of a token element, entities decoded into
// `buffer` as UTF-8; returns its length. The cursor ends after the closing tag.
fn ml_token_text(m: *Ml, buffer: []u8) -> usize {
    var n = 0usize
    while m.pos < m.src.len && m.status == ok {
        let ch = m.src[m.pos]
        if ch == 60u8 {
            let t = ml_tag(m)
            if m.status != ok { ret n }
            if !t.closing { ml_fail(m, Invalid) }
            ret n
        }
        var scalar = u32(ch)
        var step = 1usize
        if ch == 38u8 {
            var j = m.pos + 1usize
            while j < m.src.len && m.src[j] != 59u8 && j < m.pos + 12usize { j += 1usize }
            if j >= m.src.len || m.src[j] != 59u8 {
                ml_fail(m, Invalid)
                ret n
            }
            let name = m.src[m.pos + 1usize..j]
            step = j + 1usize - m.pos
            scalar = 0u32
            if word_is(name, "lt") { scalar = 60u32 }
            if word_is(name, "gt") { scalar = 62u32 }
            if word_is(name, "amp") { scalar = 38u32 }
            if word_is(name, "quot") { scalar = 34u32 }
            if word_is(name, "minus") { scalar = 8722u32 }
            if word_is(name, "InvisibleTimes") || word_is(name, "ApplyFunction") || word_is(name, "InvisibleComma") { scalar = 1u32 }
            if name.len > 1usize && name[0usize] == 35u8 {
                var value = 0u32
                var k = 1usize
                var base = 10u32
                if name[1usize] == 120u8 || name[1usize] == 88u8 {
                    base = 16u32
                    k = 2usize
                }
                while k < name.len {
                    let digit = name[k]
                    var v = 99u32
                    if digit >= 48u8 && digit <= 57u8 { v = u32(digit) - 48u32 }
                    if digit >= 97u8 && digit <= 102u8 { v = u32(digit) - 87u32 }
                    if digit >= 65u8 && digit <= 70u8 { v = u32(digit) - 55u32 }
                    if v >= base {
                        ml_fail(m, Invalid)
                        ret n
                    }
                    value = value * base + v
                    k += 1usize
                }
                scalar = value
            }
            if scalar == 0u32 {
                ml_fail(m, Invalid)
                ret n
            }
            // The invisible operators (U+2061, U+2062, U+2063) carry no ink.
            if scalar == 8289u32 || scalar == 8290u32 || scalar == 8291u32 { scalar = 1u32 }
            if scalar != 1u32 {
                if n + 4usize > buffer.len {
                    ml_fail(m, TooSmall)
                    ret n
                }
                n = unicode.write_utf8(scalar, buffer, n)
            }
            m.pos += step
            continue
        }
        if ch == 32u8 || ch == 10u8 || ch == 9u8 || ch == 13u8 {
            // Token content has its whitespace collapsed away at the ends and between.
            m.pos += 1usize
            continue
        }
        let (read, width) = unicode.read_utf8(m.src, m.pos)
        if n + 4usize > buffer.len {
            ml_fail(m, TooSmall)
            ret n
        }
        n = unicode.write_utf8(read, buffer, n)
        m.pos += width
    }
    ml_fail(m, Invalid)
    ret n
}

// The LaTeX command or escape for a scalar the subset names, "" otherwise.
fn ml_command(scalar: u32) -> str {
    if scalar == 8721u32 { ret "\\sum" }
    if scalar == 8719u32 { ret "\\prod" }
    if scalar == 8747u32 { ret "\\int" }
    if scalar == 177u32 { ret "\\pm" }
    if scalar == 215u32 { ret "\\times" }
    if scalar == 247u32 { ret "\\div" }
    if scalar == 8901u32 { ret "\\cdot" }
    if scalar == 8804u32 { ret "\\leq" }
    if scalar == 8805u32 { ret "\\geq" }
    if scalar == 8800u32 { ret "\\neq" }
    if scalar == 8776u32 { ret "\\approx" }
    if scalar == 8801u32 { ret "\\equiv" }
    if scalar == 8594u32 { ret "\\to" }
    if scalar == 8592u32 { ret "\\leftarrow" }
    if scalar == 8712u32 { ret "\\in" }
    if scalar == 8734u32 { ret "\\infty" }
    if scalar == 8706u32 { ret "\\partial" }
    if scalar == 8711u32 { ret "\\nabla" }
    if scalar == 8704u32 { ret "\\forall" }
    if scalar == 8707u32 { ret "\\exists" }
    if scalar == 8230u32 { ret "\\ldots" }
    if scalar == 8746u32 { ret "\\cup" }
    if scalar == 8745u32 { ret "\\cap" }
    if scalar == 123u32 { ret "\\{" }
    if scalar == 125u32 { ret "\\}" }
    if scalar == 37u32 { ret "\\%" }
    if scalar == 35u32 { ret "\\#" }
    if scalar == 38u32 { ret "\\&" }
    if scalar == 95u32 { ret "\\_" }
    if scalar == 36u32 { ret "\\$" }
    ret ""
}

// A scalar written as LaTeX: a command for the ones the subset names, else its UTF-8.
fn ml_scalar(m: *Ml, scalar: u32) {
    let command = ml_command(scalar)
    if command.len > 0usize {
        ml_push(m, command)
        ml_push(m, " ")
        ret
    }
    if scalar == 92u32 || scalar == 94u32 || scalar == 126u32 {
        ml_fail(m, Invalid)
        ret
    }
    var buffer: [4]u8 = zero
    let n = unicode.write_utf8(scalar, buffer[0..], 0usize)
    ml_push(m, buffer[..n])
}

fn ml_scalar_count(text: []const u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] & 192u8 != 128u8 { n += 1usize }
        i += 1usize
    }
    ret n
}

// Emits the token element `name` (its start tag is consumed); `wrap` asks for the
// result to be braced when it is more than one atom and the caller needs one.
fn ml_token(m: *Ml, name: str, wrap: bool) {
    var buffer: [256]u8 = zero
    let n = ml_token_text(m, buffer[0..])
    if m.status != ok { ret }
    let text: str = buffer[..n]
    if word_is(name, "mtext") || word_is(name, "ms") {
        ml_push(m, "\\text{")
        ml_push(m, text)
        ml_push(m, "}")
        ret
    }
    let count = ml_scalar_count(buffer[..n])
    if word_is(name, "mi") && count > 1usize {
        if is_operator_name(text) {
            ml_push(m, "\\")
            ml_push(m, text)
            ml_push(m, " ")
        } else {
            ml_push(m, "\\mathrm{")
            ml_push(m, text)
            ml_push(m, "}")
        }
        ret
    }
    if count > 1usize && wrap { ml_push(m, "{") }
    var i = 0usize
    while i < n {
        let (scalar, width) = unicode.read_utf8(text, i)
        ml_scalar(m, scalar)
        i += width
    }
    if count > 1usize && wrap { ml_push(m, "}") }
}

// Advances past one element (or token run) without emitting, tags balanced.
fn ml_skip(m: *Ml) {
    ml_space(m)
    var depth = 0usize
    var started = false
    while m.pos < m.src.len && m.status == ok {
        if m.src[m.pos] != 60u8 {
            m.pos += 1usize
            continue
        }
        let t = ml_tag(m)
        if m.status != ok { ret }
        if t.closing {
            if depth == 0usize {
                ml_fail(m, Invalid)
                ret
            }
            depth -= 1usize
        } else if !t.empty {
            depth += 1usize
        }
        started = true
        if depth == 0usize && started { ret }
    }
    ml_fail(m, Invalid)
}

// One child as a LaTeX argument: a group, or a single token as itself.
fn ml_child(m: *Ml) {
    ml_space(m)
    ml_element(m, true)
}

// The children of the element just opened, up to its closing tag, each emitted
// as a row item (no extra braces).
fn ml_row(m: *Ml, expected: str) {
    while m.status == ok {
        ml_space(m)
        if m.pos >= m.src.len {
            ml_fail(m, Invalid)
            ret
        }
        if m.src[m.pos] != 60u8 {
            ml_fail(m, Invalid)
            ret
        }
        if m.pos + 1usize < m.src.len && m.src[m.pos + 1usize] == 47u8 {
            let t = ml_tag(m)
            if m.status == ok && !word_is(t.name, expected) { ml_fail(m, Invalid) }
            ret
        }
        ml_element(m, false)
    }
}

fn ml_close(m: *Ml, expected: str) {
    ml_space(m)
    let t = ml_tag(m)
    if m.status == ok && (!t.closing || !word_is(t.name, expected)) { ml_fail(m, Invalid) }
}

// A delimiter attribute value as a `\left` or `\right` operand.
fn ml_delimiter(m: *Ml, value: str) {
    if value.len == 0usize {
        ml_push(m, ".")
        ret
    }
    let (scalar, width) = unicode.read_utf8(value, 0usize)
    if scalar == 123u32 {
        ml_push(m, "\\{")
    } else if scalar == 125u32 {
        ml_push(m, "\\}")
    } else {
        ml_push(m, value[0usize..width])
    }
}

// An `mover` or `munder` whose second child is a single accent or brace character in an `mo`
// (and whose `accent`/`accentunder` is not "false") is that accent or brace, not a script: it
// becomes `\overaccent{c}{base}` or `\underaccent{c}{base}`, set as wide as the base. False, with the
// cursor where it was, when it is an ordinary script.
fn ml_accent_script(m: *Ml, attrs: str, name: str, wrap: bool) -> bool {
    var flag_name = "accent"
    if word_is(name, "munder") { flag_name = "accentunder" }
    let (flag, has_flag) = ml_attr(attrs, flag_name)
    if has_flag && word_is(flag, "false") { ret false }
    let start = m.pos
    ml_space(m)
    let base_at = m.pos
    ml_skip(m)
    if m.status != ok {
        m.pos = start
        ret false
    }
    ml_space(m)
    let second = ml_tag(m)
    if m.status != ok || second.closing || second.empty || !word_is(second.name, "mo") {
        m.pos = start
        ret false
    }
    var buffer: [32]u8 = zero
    let n = ml_token_text(m, buffer[0..])
    if m.status != ok || n == 0usize {
        m.pos = start
        ret false
    }
    let text: str = buffer[..n]
    let (scalar, width) = unicode.read_utf8(text, 0usize)
    if width != n {
        m.pos = start
        ret false
    }
    let form = accent_form(scalar)
    let known = form == 768u32 || form == 769u32 || form == 770u32 || form == 771u32 || form == 772u32 || form == 774u32 || form == 775u32 || form == 776u32 || form == 778u32 || form == 780u32 || form == 8407u32 || form == 9182u32 || form == 9183u32
    if !known {
        m.pos = start
        ret false
    }
    let after = m.pos
    if wrap { ml_push(m, "{") }
    if word_is(name, "munder") { ml_push(m, "\\underaccent{") } else { ml_push(m, "\\overaccent{") }
    ml_push(m, text)
    ml_push(m, "}")
    m.pos = base_at
    ml_child(m)
    m.pos = after
    if wrap { ml_push(m, "}") }
    ml_close(m, name)
    ret true
}

fn ml_element(m: *Ml, wrap: bool) {
    if m.status != ok { ret }
    if m.depth >= MAX_NEST {
        ml_fail(m, TooDeep)
        ret
    }
    m.depth += 1usize
    let t = ml_tag(m)
    if m.status != ok || t.closing {
        ml_fail(m, Invalid)
        m.depth -= 1usize
        ret
    }
    let name = t.name
    if t.empty {
        if word_is(name, "mspace") { ml_push(m, "\\,") } else { ml_fail(m, Invalid) }
        m.depth -= 1usize
        ret
    }
    if word_is(name, "mi") || word_is(name, "mn") || word_is(name, "mo") || word_is(name, "mtext") || word_is(name, "ms") {
        ml_token(m, name, wrap)
    } else if word_is(name, "mspace") {
        ml_push(m, "\\,")
        ml_close(m, name)
    } else if word_is(name, "math") || word_is(name, "mrow") || word_is(name, "mstyle") || word_is(name, "mpadded") || word_is(name, "semantics") {
        if wrap { ml_push(m, "{") }
        ml_row(m, name)
        if wrap { ml_push(m, "}") }
    } else if word_is(name, "annotation") || word_is(name, "annotation-xml") {
        // Annotations carry no layout: skip to the matching close.
        var depth = 1usize
        while m.pos < m.src.len && depth > 0usize && m.status == ok {
            if m.src[m.pos] != 60u8 {
                m.pos += 1usize
                continue
            }
            let inner = ml_tag(m)
            if inner.closing { depth -= 1usize } else if !inner.empty { depth += 1usize }
        }
    } else if (word_is(name, "mover") || word_is(name, "munder")) && ml_accent_script(m, t.attrs, name, wrap) {
        // The accent or brace form: ml_accent_script wrote it and consumed the closing tag.
    } else if word_is(name, "msup") || word_is(name, "mover") {
        if wrap { ml_push(m, "{") }
        ml_child(m)
        ml_push(m, "^")
        ml_child(m)
        if wrap { ml_push(m, "}") }
        ml_close(m, name)
    } else if word_is(name, "msub") || word_is(name, "munder") {
        if wrap { ml_push(m, "{") }
        ml_child(m)
        ml_push(m, "_")
        ml_child(m)
        if wrap { ml_push(m, "}") }
        ml_close(m, name)
    } else if word_is(name, "msubsup") || word_is(name, "munderover") {
        if wrap { ml_push(m, "{") }
        ml_child(m)
        ml_push(m, "_")
        ml_child(m)
        ml_push(m, "^")
        ml_child(m)
        if wrap { ml_push(m, "}") }
        ml_close(m, name)
    } else if word_is(name, "mfrac") {
        ml_push(m, "\\frac ")
        ml_child(m)
        ml_push(m, " ")
        ml_child(m)
        ml_close(m, name)
    } else if word_is(name, "msqrt") {
        ml_push(m, "\\sqrt{")
        ml_row(m, name)
        ml_push(m, "}")
    } else if word_is(name, "mroot") {
        // The index is the second child: skip the base, emit the index, return to the base.
        ml_space(m)
        let base_at = m.pos
        ml_skip(m)
        ml_space(m)
        ml_push(m, "\\sqrt[")
        ml_row_one(m)
        ml_push(m, "]")
        let after = m.pos
        m.pos = base_at
        ml_child(m)
        m.pos = after
        ml_close(m, name)
    } else if word_is(name, "mfenced") {
        let (open, has_open) = ml_attr(t.attrs, "open")
        let (close, has_close) = ml_attr(t.attrs, "close")
        let (separators, has_separators) = ml_attr(t.attrs, "separators")
        ml_push(m, "\\left")
        if has_open { ml_delimiter(m, open) } else { ml_push(m, "(") }
        var index = 0usize
        while m.status == ok {
            ml_space(m)
            if m.pos >= m.src.len {
                ml_fail(m, Invalid)
                break
            }
            if m.pos + 1usize < m.src.len && m.src[m.pos + 1usize] == 47u8 {
                ml_close(m, name)
                break
            }
            if index > 0usize {
                var sep = ","
                if has_separators && separators.len > 0usize {
                    var at = index - 1usize
                    if at >= separators.len { at = separators.len - 1usize }
                    sep = separators[at..at + 1usize]
                }
                ml_push(m, sep)
            }
            ml_element(m, true)
            index += 1usize
        }
        ml_push(m, "\\right")
        if has_close { ml_delimiter(m, close) } else { ml_push(m, ")") }
    } else if word_is(name, "mtable") {
        ml_push(m, "\\begin{matrix}")
        var first_row = true
        while m.status == ok {
            ml_space(m)
            if m.pos >= m.src.len {
                ml_fail(m, Invalid)
                break
            }
            if m.pos + 1usize < m.src.len && m.src[m.pos + 1usize] == 47u8 {
                ml_close(m, name)
                break
            }
            if !first_row { ml_push(m, "\\\\") }
            first_row = false
            let row_tag = ml_tag(m)
            if m.status != ok || row_tag.closing || !word_is(row_tag.name, "mtr") {
                ml_fail(m, Invalid)
                break
            }
            var first_cell = true
            while m.status == ok {
                ml_space(m)
                if m.pos >= m.src.len {
                    ml_fail(m, Invalid)
                    break
                }
                if m.pos + 1usize < m.src.len && m.src[m.pos + 1usize] == 47u8 {
                    ml_close(m, "mtr")
                    break
                }
                if !first_cell { ml_push(m, "&") }
                first_cell = false
                let cell_tag = ml_tag(m)
                if m.status != ok || cell_tag.closing || !word_is(cell_tag.name, "mtd") {
                    ml_fail(m, Invalid)
                    break
                }
                ml_push(m, "{")
                ml_row(m, "mtd")
                ml_push(m, "}")
            }
        }
        ml_push(m, "\\end{matrix}")
    } else {
        ml_fail(m, Invalid)
    }
    m.depth -= 1usize
}

// One child element's content as a row (the index of a root), consuming only it.
fn ml_row_one(m: *Ml) {
    ml_space(m)
    ml_element(m, false)
}

// Typesets presentation MathML `source` (an element, usually `math`).
fn typeset_mathml(a: *mem.Arena, source: str, options: Options, items: []Item) -> (Equation, err) {
    var ml: Ml = zero
    ml.src = source
    ml.status = ok
    let (builder, builder_error) = str.builder(a, source.len * 4usize + 64usize)
    if builder_error != ok { ret (zero, TooSmall) }
    ml.out = builder
    ml_space(&ml)
    ml_element(&ml, false)
    ml_space(&ml)
    if ml.status == ok && ml.pos < ml.src.len { ml.status = Invalid }
    if ml.status != ok { ret (zero, ml.status) }
    let latex = str.done(&ml.out)
    let (eq, eq_error) = typeset(a, latex, options, items)
    ret (eq, eq_error)
}
