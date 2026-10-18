// The style resolver (tracker 1.13): the computed style of every element of an `e.fmt.dom` tree.
//
// Per element: the cascade (`e.fmt.css.cascade` ranks and `beats`) over the presentational hints, the user agent
// rules, the author rules and the `style` attribute; each shorthand and logical property is expanded to its longhands
// (`e.fmt.css.expand`) before ranking, so every longhand wins or loses on its own declaration; custom properties
// inherit and `var()` and `env()` are substituted; then each longhand is read into a typed field of `Style`:
//
//   * keywords become enums, colours 32-bit ARGB (`currentcolor`, `light-dark()` and every `e.gfx.cssvalue` form),
//     lengths `Len` (px plus a fraction of the percentage basis, which only layout knows) with `em`, `rem`, `vw`,
//     `vh` and `calc()` resolved against the element's font size, the root's and the viewport;
//   * the inherited properties (colour, font, text, list, table, visibility, direction, cursor, custom properties)
//     start from the parent's value, every other property from its initial value; `inherit`, `initial` and `unset`
//     are honoured;
//   * font size is computed first from the parent's (keywords, `smaller`/`larger`, `em`, `%`), a border's width is
//     0 when its style is none or hidden, `currentcolor` defaults follow this element's colour, a floated or
//     absolutely positioned box is blockified.
//
// Properties this module does not give a field (transforms, transitions, animations, grid templates, shadows,
// filters, masks, background layers, `content`, counters, ...) keep their declared text in `extras` (inherited ones
// carried down) for the consumers that parse them.
//
// Not here yet: pseudo-elements, `revert`, logical properties for vertical writing modes, `attr()`/`counter()` in values.
//
// Memory: the arena is retained; every string and list lives in it.

use e.data.list as list
use e.fmt.css.cascade as cascade
use e.fmt.css.expand as expand
use e.fmt.css.match as cssm
use e.fmt.css.selector as selector
use e.fmt.css.sheet as sheet
use e.fmt.css.syntax as syntax
use e.fmt.css.ua as uacss
use e.fmt.dom as dom
use e.fmt.html as html
use e.gfx.cssvalue as cv
use e.mem
use e.str

const TOP: usize = 0usize
const RIGHT: usize = 1usize
const BOTTOM: usize = 2usize
const LEFT: usize = 3usize

type LenKind = enum u8 { Auto, Px, None, MinContent, MaxContent, FitContent, Number, Normal }

// A length: `px` plus `pct` times the percentage basis (a fraction: 50% is 0.5). `Number` is a unitless
// `line-height` factor (in `px`); `Normal` is `line-height: normal`.
type Len = struct { kind: LenKind, px: f64, pct: f64 }

type Display = enum u8 { Inline, Block, None, Contents, InlineBlock, Flex, InlineFlex, Grid, InlineGrid, Table, InlineTable, TableRow, TableCell, TableRowGroup, TableHeaderGroup, TableFooterGroup, TableColumn, TableColumnGroup, TableCaption, ListItem, FlowRoot, Ruby, RubyText, RubyBase, RubyTextContainer, RubyBaseContainer }
type Position = enum u8 { Static, Relative, Absolute, Fixed, Sticky }
type Float = enum u8 { None, Left, Right, InlineStart, InlineEnd }
type Clear = enum u8 { None, Left, Right, Both, InlineStart, InlineEnd }
type BoxSizing = enum u8 { ContentBox, BorderBox }
type Overflow = enum u8 { Visible, Hidden, Scroll, Auto, Clip }
type Visibility = enum u8 { Visible, Hidden, Collapse }
type BorderStyle = enum u8 { None, Hidden, Dotted, Dashed, Solid, Double, Groove, Ridge, Inset, Outset }
type FontStyle = enum u8 { Normal, Italic, Oblique }
type TextAlign = enum u8 { Start, End, Left, Right, Center, Justify, MatchParent }
type TextTransform = enum u8 { None, Capitalize, Uppercase, Lowercase, FullWidth }
type WhiteSpace = enum u8 { Normal, Pre, Nowrap, PreWrap, PreLine, BreakSpaces }
type WordBreak = enum u8 { Normal, BreakAll, KeepAll, BreakWord }
type OverflowWrap = enum u8 { Normal, BreakWord, Anywhere }
type TextOverflow = enum u8 { Clip, Ellipsis }
type Direction = enum u8 { Ltr, Rtl }
type WritingMode = enum u8 { HorizontalTb, VerticalRl, VerticalLr, SidewaysRl, SidewaysLr }
type ListPosition = enum u8 { Outside, Inside }
type BorderCollapse = enum u8 { Separate, Collapse }
type TableLayout = enum u8 { Auto, Fixed }
type CaptionSide = enum u8 { Top, Bottom }
type EmptyCells = enum u8 { Show, Hide }
type FlexDirection = enum u8 { Row, RowReverse, Column, ColumnReverse }
type FlexWrap = enum u8 { Nowrap, Wrap, WrapReverse }
type Align = enum u8 { Normal, Start, End, FlexStart, FlexEnd, Center, Stretch, SpaceBetween, SpaceAround, SpaceEvenly, Baseline, FirstBaseline, LastBaseline, SelfStart, SelfEnd, Left, Right, Safe, Unsafe, Auto }
type DecorationStyle = enum u8 { Solid, Double, Dotted, Dashed, Wavy }
type VAlign = enum u8 { Baseline, Sub, Super, Top, TextTop, Middle, Bottom, TextBottom, Length }

const DECORATION_UNDERLINE: u8 = 1u8
const DECORATION_OVERLINE: u8 = 2u8
const DECORATION_LINE_THROUGH: u8 = 4u8

type Custom = struct { name: str, value: str }
type Extra = struct { name: str, value: str }

type Style = struct {
    display: Display, was_inline: bool, position: Position, floating: Float, clear: Clear, box_sizing: BoxSizing,
    overflow_x: Overflow, overflow_y: Overflow, visibility: Visibility,
    width: Len, height: Len, min_width: Len, min_height: Len, max_width: Len, max_height: Len,
    inset: [4]Len, margin: [4]Len, padding: [4]Len,
    border_width: [4]f64, border_style: [4]BorderStyle, border_color: [4]u32, border_current: [4]bool,
    radius_h: [4]Len, radius_v: [4]Len,
    z_index_auto: bool, z_index: i64, opacity: f64,
    flex_direction: FlexDirection, flex_wrap: FlexWrap, flex_grow: f64, flex_shrink: f64, flex_basis: Len, order: i64,
    justify_content: Align, justify_items: Align, justify_self: Align, align_items: Align, align_self: Align, align_content: Align,
    row_gap: Len, column_gap: Len,
    color: u32, font_size: f64, font_weight: f64, font_style: FontStyle, font_family: str, line_height: Len,
    letter_spacing: f64, word_spacing: f64, text_indent: Len,
    text_align: TextAlign, text_transform: TextTransform, white_space: WhiteSpace, word_break: WordBreak,
    overflow_wrap: OverflowWrap, text_overflow: TextOverflow, direction: Direction, writing_mode: WritingMode,
    vertical_align: VAlign, vertical_align_length: Len,
    decoration_line: u8, decoration_color: u32, decoration_current: bool, decoration_style: DecorationStyle,
    cursor: str, tab_size: f64,
    list_style_type: str, list_style_position: ListPosition, list_style_image: str,
    background_color: u32,
    outline_width: f64, outline_style: BorderStyle, outline_color: u32, outline_current: bool, outline_offset: f64,
    border_collapse: BorderCollapse, border_spacing_h: f64, border_spacing_v: f64, table_layout: TableLayout,
    caption_side: CaptionSide, empty_cells: EmptyCells,
    custom: []const Custom, extras: []const Extra,
    // The styles of the element's pseudo-elements, by `selector.PseudoElement` (an address of 0: the element has none).
    pseudo: [8]*const Style
}

// `ch` and `ex` are the advance of `0` and the x-height as fractions of the font size for the element being styled.
type Context = struct { a: *mem.Arena, viewport_width: f64, viewport_height: f64, root_font_size: f64, dark: bool, ch: f64, ex: f64 }

fn new_context(a: *mem.Arena, viewport_width: f64, viewport_height: f64) -> Context {
    ret Context { a: a, viewport_width: viewport_width, viewport_height: viewport_height, root_font_size: 16.0f64, dark: false, ch: 0.5f64, ex: 0.5f64 }
}

// --- Small helpers.

fn len_auto() -> Len { ret Len { kind: .Auto, px: 0.0f64, pct: 0.0f64 } }
fn len_px(px: f64) -> Len { ret Len { kind: .Px, px: px, pct: 0.0f64 } }
fn len_none() -> Len { ret Len { kind: .None, px: 0.0f64, pct: 0.0f64 } }
fn len_normal() -> Len { ret Len { kind: .Normal, px: 0.0f64, pct: 0.0f64 } }

fn nm(set: str, name: str) -> bool {
    var i = 1usize
    while i < set.len {
        var j = i
        while j < set.len && set[j] != 44u8 { j += 1usize }
        if j - i == name.len && str.eq(set[i..j], name) { ret true }
        i = j + 1usize
    }
    ret false
}

// The index of `v` in the comma-delimited `set` (-1 when absent).
fn idx_of(set: str, v: str) -> i32 {
    var i = 1usize
    var n = 0i32
    while i < set.len {
        var j = i
        while j < set.len && set[j] != 44u8 { j += 1usize }
        if j - i == v.len && str.eq(set[i..j], v) { ret n }
        n += 1i32
        i = j + 1usize
    }
    ret -1i32
}

// The enum value of keyword `v` in `set` (declared in the same order), or `fallback`.
fn kw[T: type](v: str, set: str, fallback: T) -> T {
    let at = idx_of(set, v)
    if at < 0i32 { ret fallback }
    ret mem.bitcast[T](u8(at))
}

fn has_kw(v: str, set: str) -> bool { ret idx_of(set, v) >= 0i32 }

fn is_wide(v: str) -> bool {
    ret str.eq(v, "inherit") || str.eq(v, "initial") || str.eq(v, "unset") || str.eq(v, "revert") || str.eq(v, "revert-layer")
}

fn bases_for(c: *const Context, em: f64) -> cv.Bases {
    var b = cv.no_bases()
    b.has_em = true
    b.em = em
    b.has_rem = true
    b.rem = c.root_font_size
    b.has_viewport_width = true
    b.viewport_width = c.viewport_width
    b.has_viewport_height = true
    b.viewport_height = c.viewport_height
    b.ch = c.ch
    b.ex = c.ex
    ret b
}

const A_AUTO: u32 = 1u32
const A_NONE: u32 = 2u32
const A_CONTENT: u32 = 4u32
const A_NORMAL: u32 = 8u32
const A_NUMBER: u32 = 16u32
const A_NEGATIVE: u32 = 32u32
const A_PERCENT: u32 = 64u32

// A length, percentage, `calc()` or one of the keywords `allow` admits.
fn parse_len(c: *const Context, v: str, em: f64, allow: u32) -> (Len, bool) {
    let t = cv.lower(c.a, cv.trim_ws(v))
    if t.len == 0usize { ret (len_auto(), false) }
    if (allow & A_AUTO) != 0u32 && str.eq(t, "auto") { ret (len_auto(), true) }
    if (allow & A_NONE) != 0u32 && str.eq(t, "none") { ret (len_none(), true) }
    if (allow & A_NORMAL) != 0u32 && str.eq(t, "normal") { ret (len_normal(), true) }
    if (allow & A_CONTENT) != 0u32 {
        if str.eq(t, "min-content") { ret (Len { kind: .MinContent, px: 0.0f64, pct: 0.0f64 }, true) }
        if str.eq(t, "max-content") { ret (Len { kind: .MaxContent, px: 0.0f64, pct: 0.0f64 }, true) }
        if str.eq(t, "fit-content") || str.eq(t, "-moz-fit-content") || str.eq(t, "-webkit-fit-content") { ret (Len { kind: .FitContent, px: 0.0f64, pct: 0.0f64 }, true) }
    }
    if (allow & A_NUMBER) != 0u32 {
        let (n, is_number) = plain_number(c, t)
        if is_number && (n >= 0.0f64 || (allow & A_NEGATIVE) != 0u32) { ret (Len { kind: .Number, px: n, pct: 0.0f64 }, true) }
    }
    let bases = bases_for(c, em)
    let (l, parsed) = cv.parse_length(c.a, t, bases)
    if !parsed { ret (len_auto(), false) }
    if l.op == .None && l.unit == .Percent {
        if (allow & A_PERCENT) == 0u32 { ret (len_auto(), false) }
        let r = Len { kind: .Px, px: l.px_offset, pct: l.value / 100.0f64 }
        if (allow & A_NEGATIVE) == 0u32 && (r.px < 0.0f64 || r.pct < 0.0f64) && r.pct < 0.0f64 { ret (len_auto(), false) }
        ret (r, true)
    }
    let (px, ok_px) = cv.to_px(l, bases)
    if !ok_px { ret (len_auto(), false) }
    if px < 0.0f64 && (allow & A_NEGATIVE) == 0u32 { ret (len_auto(), false) }
    ret (len_px(px), true)
}

fn plain_number(c: *const Context, t: str) -> (f64, bool) {
    if t.len == 0usize { ret (0.0f64, false) }
    var i = 0usize
    var digits = 0usize
    while i < t.len {
        let ch = t[i]
        if ch >= 48u8 && ch <= 57u8 { digits += 1usize } else {
            if !(ch == 46u8 || ((ch == 43u8 || ch == 45u8) && i == 0usize)) { ret (0.0f64, false) }
        }
        i += 1usize
    }
    if digits == 0usize { ret (0.0f64, false) }
    let (n, parsed) = cv.try_parse(c.a, t)
    ret (n, parsed)
}

fn parse_px(c: *const Context, v: str, em: f64) -> (f64, bool) {
    let (l, good) = parse_len(c, v, em, A_NEGATIVE)
    if !good || l.kind != .Px || l.pct != 0.0f64 { ret (0.0f64, false) }
    ret (l.px, true)
}

// A colour: `currentcolor` is `current`, `light-dark()` follows the context, the rest is `e.gfx.cssvalue`.
fn parse_color_value(c: *const Context, v: str, current: u32) -> (u32, bool) {
    let t = cv.trim_ws(v)
    let low = cv.lower(c.a, t)
    if str.eq(low, "currentcolor") { ret (current, true) }
    if str.eq(low, "transparent") { ret (0u32, true) }
    if str.starts_with(low, "light-dark(") {
        let (picked, picked_ok) = cv.pick_light_dark(c.a, t, c.dark)
        if !picked_ok { ret (0u32, false) }
        let (inner, inner_ok) = parse_color_value(c, picked, current)
        ret (inner, inner_ok)
    }
    if str.starts_with(low, "color-mix(") {
        let (mixed, mixed_ok) = cv.parse_color_mix(c.a, t, true, current)
        ret (mixed, mixed_ok)
    }
    if str.starts_with(low, "contrast-color(") {
        let (contrast, contrast_ok) = cv.parse_contrast_color(c.a, t, true, current)
        ret (contrast, contrast_ok)
    }
    let (rgba, parsed) = cv.parse_color(c.a, t)
    ret (rgba, parsed)
}

fn border_width_value(c: *const Context, v: str, em: f64) -> (f64, bool) {
    let t = cv.lower(c.a, cv.trim_ws(v))
    if str.eq(t, "thin") { ret (1.0f64, true) }
    if str.eq(t, "medium") { ret (3.0f64, true) }
    if str.eq(t, "thick") { ret (5.0f64, true) }
    let (px, parsed) = parse_px(c, t, em)
    if !parsed || px < 0.0f64 { ret (0.0f64, false) }
    // A used border width is a whole number of device pixels: fractions are dropped and a thin one still draws as one pixel.
    if px > 0.0f64 && px < 1.0f64 { ret (1.0f64, true) }
    ret (f64(i64(px + 0.001f64)), true)
}

fn parse_number_value(c: *const Context, v: str) -> (f64, bool) {
    let t = cv.lower(c.a, cv.trim_ws(v))
    if t.len > 0usize && t[t.len - 1usize] == 37u8 {
        let (p, good) = plain_number(c, t[..t.len - 1usize])
        if good { ret (p / 100.0f64, true) }
        ret (0.0f64, false)
    }
    let (n, parsed) = plain_number(c, t)
    ret (n, parsed)
}

fn clamp01(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 }
    if x > 1.0f64 { ret 1.0f64 }
    ret x
}

fn initial_style() -> Style {
    var s: Style = zero
    s.display = .Inline
    s.position = .Static
    s.floating = .None
    s.clear = .None
    s.box_sizing = .ContentBox
    s.overflow_x = .Visible
    s.overflow_y = .Visible
    s.visibility = .Visible
    s.width = len_auto()
    s.height = len_auto()
    s.min_width = len_auto()
    s.min_height = len_auto()
    s.max_width = len_none()
    s.max_height = len_none()
    var i = 0usize
    while i < 4usize {
        s.inset[i] = len_auto()
        s.margin[i] = len_px(0.0f64)
        s.padding[i] = len_px(0.0f64)
        s.border_width[i] = 3.0f64
        s.border_style[i] = .None
        s.border_color[i] = 0u32
        s.border_current[i] = true
        s.radius_h[i] = len_px(0.0f64)
        s.radius_v[i] = len_px(0.0f64)
        i += 1usize
    }
    s.z_index_auto = true
    s.opacity = 1.0f64
    s.flex_direction = .Row
    s.flex_wrap = .Nowrap
    s.flex_grow = 0.0f64
    s.flex_shrink = 1.0f64
    s.flex_basis = len_auto()
    s.justify_content = .Normal
    s.justify_items = .Normal
    s.justify_self = .Auto
    s.align_items = .Normal
    s.align_self = .Auto
    s.align_content = .Normal
    s.row_gap = len_normal()
    s.column_gap = len_normal()
    s.color = 4278190080u32
    s.font_size = 16.0f64
    s.font_weight = 400.0f64
    s.font_style = .Normal
    s.font_family = "serif"
    s.line_height = len_normal()
    s.text_indent = len_px(0.0f64)
    s.text_align = .Start
    s.text_transform = .None
    s.white_space = .Normal
    s.word_break = .Normal
    s.overflow_wrap = .Normal
    s.text_overflow = .Clip
    s.direction = .Ltr
    s.writing_mode = .HorizontalTb
    s.vertical_align = .Baseline
    s.vertical_align_length = len_px(0.0f64)
    s.decoration_color = 4278190080u32
    s.decoration_current = true
    s.decoration_style = .Solid
    s.cursor = "auto"
    s.tab_size = 8.0f64
    s.list_style_type = "disc"
    s.list_style_position = .Outside
    s.list_style_image = "none"
    s.outline_style = .None
    s.outline_width = 3.0f64
    s.outline_color = 4278190080u32
    s.outline_current = true
    s.border_collapse = .Separate
    s.table_layout = .Auto
    s.caption_side = .Top
    s.empty_cells = .Show
    ret s
}

// A style that starts from `parent`: its inherited values, everything else initial.
fn inherit_from(parent: *const Style) -> Style {
    var s = initial_style()
    s.color = parent.color
    s.font_size = parent.font_size
    s.font_weight = parent.font_weight
    s.font_style = parent.font_style
    s.font_family = parent.font_family
    s.line_height = parent.line_height
    s.letter_spacing = parent.letter_spacing
    s.word_spacing = parent.word_spacing
    s.text_indent = parent.text_indent
    s.text_align = parent.text_align
    s.text_transform = parent.text_transform
    s.white_space = parent.white_space
    s.word_break = parent.word_break
    s.overflow_wrap = parent.overflow_wrap
    s.text_overflow = s.text_overflow
    s.direction = parent.direction
    s.writing_mode = parent.writing_mode
    s.visibility = parent.visibility
    s.cursor = parent.cursor
    s.tab_size = parent.tab_size
    s.list_style_type = parent.list_style_type
    s.list_style_position = parent.list_style_position
    s.list_style_image = parent.list_style_image
    s.border_collapse = parent.border_collapse
    s.border_spacing_h = parent.border_spacing_h
    s.border_spacing_v = parent.border_spacing_v
    s.caption_side = parent.caption_side
    s.empty_cells = parent.empty_cells
    s.custom = parent.custom
    ret s
}

fn inherited_extra(name: str) -> bool {
    ret nm(",text-shadow,font-variant-caps,font-variant-ligatures,font-variant-numeric,font-variant-east-asian,font-feature-settings,font-variation-settings,font-kerning,font-stretch,font-optical-sizing,font-size-adjust,hyphens,text-rendering,caret-color,accent-color,image-rendering,quotes,text-justify,text-decoration-skip-ink,color-scheme,orphans,widows,line-break,text-size-adjust,pointer-events,user-select,paint-order,fill,stroke,stroke-width,fill-opacity,stroke-opacity,text-anchor,font-synthesis,hanging-punctuation,text-wrap,", name)
}

// --- Reading one longhand into the style.

type Ap = struct { c: *const Context, s: *Style, parent: *const Style, a: *mem.Arena, extras: list.List[Extra] }

fn side_of(rest: str) -> i32 {
    if str.eq(rest, "top") { ret 0i32 }
    if str.eq(rest, "right") { ret 1i32 }
    if str.eq(rest, "bottom") { ret 2i32 }
    if str.eq(rest, "left") { ret 3i32 }
    ret -1i32
}

fn parse_display(v: str) -> (Display, bool) {
    let set = ",inline,block,none,contents,inline-block,flex,inline-flex,grid,inline-grid,table,inline-table,table-row,table-cell,table-row-group,table-header-group,table-footer-group,table-column,table-column-group,table-caption,list-item,flow-root,ruby,ruby-text,ruby-base,ruby-text-container,ruby-base-container,"
    if has_kw(v, set) { ret (kw[Display](v, set, .Inline), true) }
    if str.eq(v, "-webkit-box") { ret (.Block, true) }
    if str.eq(v, "-webkit-inline-box") { ret (.InlineBlock, true) }
    if str.eq(v, "block flow") || str.eq(v, "flow") { ret (.Block, true) }
    if str.eq(v, "inline flow") { ret (.Inline, true) }
    if str.eq(v, "block flex") { ret (.Flex, true) }
    if str.eq(v, "inline flex") { ret (.InlineFlex, true) }
    if str.eq(v, "block grid") { ret (.Grid, true) }
    if str.eq(v, "inline grid") { ret (.InlineGrid, true) }
    if str.eq(v, "block flow-root") || str.eq(v, "flow-root block") { ret (.FlowRoot, true) }
    if str.eq(v, "inline flow-root") { ret (.InlineBlock, true) }
    if str.eq(v, "block table") { ret (.Table, true) }
    if str.eq(v, "inline table") { ret (.InlineTable, true) }
    if str.eq(v, "list-item block") || str.eq(v, "block list-item") || str.eq(v, "list-item block flow") || str.eq(v, "block flow list-item") { ret (.ListItem, true) }
    ret (.Inline, false)
}

// The last word of an alignment value ("safe center", "first baseline").
fn last_word(a: *mem.Arena, v: str) -> str {
    let parts = cv.split_top_level_spaces(a, v)
    if parts.len == 0usize { ret v }
    ret parts[parts.len - 1usize]
}

fn parse_align(ap: *const Ap, v: str, fallback: Align) -> Align {
    let t = last_word(ap.a, v)
    let set = ",normal,start,end,flex-start,flex-end,center,stretch,space-between,space-around,space-evenly,baseline,first-baseline,last-baseline,self-start,self-end,left,right,safe,unsafe,auto,"
    ret kw[Align](t, set, fallback)
}

fn apply_box(ap: *Ap, prop: str, v: str) -> bool {
    let s = ap.s
    if str.starts_with(prop, "margin-") {
        let side = side_of(prop[7usize..])
        if side < 0i32 { ret false }
        let (l, good) = parse_len(ap.c, v, s.font_size, A_AUTO | A_PERCENT | A_NEGATIVE)
        if good { s.margin[usize(side)] = l }
        ret true
    }
    if str.starts_with(prop, "padding-") {
        let side = side_of(prop[8usize..])
        if side < 0i32 { ret false }
        let (l, good) = parse_len(ap.c, v, s.font_size, A_PERCENT)
        if good { s.padding[usize(side)] = l }
        ret true
    }
    let inset_side = side_of(prop)
    if inset_side >= 0i32 {
        let (l, good) = parse_len(ap.c, v, s.font_size, A_AUTO | A_PERCENT | A_NEGATIVE)
        if good { s.inset[usize(inset_side)] = l }
        ret true
    }
    if str.starts_with(prop, "border-") {
        var rest = prop[7usize..]
        var kind = ""
        if str.ends_with(rest, "-width") {
            kind = "width"
            rest = rest[..rest.len - 6usize]
        } else if str.ends_with(rest, "-style") {
            kind = "style"
            rest = rest[..rest.len - 6usize]
        } else if str.ends_with(rest, "-color") {
            kind = "color"
            rest = rest[..rest.len - 6usize]
        }
        let bside = side_of(rest)
        if bside >= 0i32 && kind.len > 0usize {
            let i = usize(bside)
            if str.eq(kind, "width") {
                let (w, good) = border_width_value(ap.c, v, s.font_size)
                if good { s.border_width[i] = w }
            } else if str.eq(kind, "style") {
                s.border_style[i] = kw[BorderStyle](cv.lower(ap.a, v), ",none,hidden,dotted,dashed,solid,double,groove,ridge,inset,outset,", s.border_style[i])
            } else {
                let (col, good) = parse_color_value(ap.c, v, s.color)
                if good {
                    s.border_color[i] = col
                    s.border_current[i] = str.eq(cv.lower(ap.a, v), "currentcolor")
                }
            }
            ret true
        }
        var corner = -1i32
        if str.eq(prop, "border-top-left-radius") { corner = 0i32 }
        if str.eq(prop, "border-top-right-radius") { corner = 1i32 }
        if str.eq(prop, "border-bottom-right-radius") { corner = 2i32 }
        if str.eq(prop, "border-bottom-left-radius") { corner = 3i32 }
        if corner >= 0i32 {
            let parts = cv.split_top_level_spaces(ap.a, v)
            if parts.len == 0usize || parts.len > 2usize { ret true }
            let (h, good_h) = parse_len(ap.c, parts[0usize], s.font_size, A_PERCENT)
            var vert = h
            var good_v = good_h
            if parts.len == 2usize {
                let (l2, g2) = parse_len(ap.c, parts[1usize], s.font_size, A_PERCENT)
                vert = l2
                good_v = g2
            }
            if good_h && good_v {
                s.radius_h[usize(corner)] = h
                s.radius_v[usize(corner)] = vert
            }
            ret true
        }
    }
    ret false
}

fn apply_size(ap: *Ap, prop: str, v: str) -> bool {
    let s = ap.s
    if str.eq(prop, "width") {
        let (l, good) = parse_len(ap.c, v, s.font_size, A_AUTO | A_CONTENT | A_PERCENT)
        if good { s.width = l }
        ret true
    }
    if str.eq(prop, "height") {
        let (l, good) = parse_len(ap.c, v, s.font_size, A_AUTO | A_CONTENT | A_PERCENT)
        if good { s.height = l }
        ret true
    }
    if str.eq(prop, "min-width") {
        let (l, good) = parse_len(ap.c, v, s.font_size, A_AUTO | A_CONTENT | A_PERCENT)
        if good { s.min_width = l }
        ret true
    }
    if str.eq(prop, "min-height") {
        let (l, good) = parse_len(ap.c, v, s.font_size, A_AUTO | A_CONTENT | A_PERCENT)
        if good { s.min_height = l }
        ret true
    }
    if str.eq(prop, "max-width") {
        let (l, good) = parse_len(ap.c, v, s.font_size, A_NONE | A_CONTENT | A_PERCENT)
        if good { s.max_width = l }
        ret true
    }
    if str.eq(prop, "max-height") {
        let (l, good) = parse_len(ap.c, v, s.font_size, A_NONE | A_CONTENT | A_PERCENT)
        if good { s.max_height = l }
        ret true
    }
    ret false
}

fn font_size_keyword(t: str) -> f64 {
    if str.eq(t, "xx-small") { ret 9.0f64 }
    if str.eq(t, "x-small") { ret 10.0f64 }
    if str.eq(t, "small") { ret 13.0f64 }
    if str.eq(t, "medium") { ret 16.0f64 }
    if str.eq(t, "large") { ret 18.0f64 }
    if str.eq(t, "x-large") { ret 24.0f64 }
    if str.eq(t, "xx-large") { ret 32.0f64 }
    if str.eq(t, "xxx-large") { ret 48.0f64 }
    ret -1.0f64
}

fn apply_font(ap: *Ap, prop: str, v: str) -> bool {
    let s = ap.s
    let c = ap.c
    if str.eq(prop, "font-size") {
        let t = cv.lower(ap.a, v)
        let named = font_size_keyword(t)
        if named >= 0.0f64 {
            s.font_size = named
            ret true
        }
        if str.eq(t, "smaller") {
            s.font_size = ap.parent.font_size / 1.2f64
            ret true
        }
        if str.eq(t, "larger") {
            s.font_size = ap.parent.font_size * 1.2f64
            ret true
        }
        let (l, good) = parse_len(c, t, ap.parent.font_size, A_PERCENT)
        if good { s.font_size = l.px + l.pct * ap.parent.font_size }
        ret true
    }
    if str.eq(prop, "font-weight") {
        let t = cv.lower(ap.a, v)
        if str.eq(t, "normal") {
            s.font_weight = 400.0f64
        } else if str.eq(t, "bold") {
            s.font_weight = 700.0f64
        } else if str.eq(t, "bolder") {
            let w = ap.parent.font_weight
            if w < 400.0f64 { s.font_weight = 400.0f64 } else if w < 600.0f64 { s.font_weight = 700.0f64 } else { s.font_weight = 900.0f64 }
        } else if str.eq(t, "lighter") {
            let w = ap.parent.font_weight
            if w < 600.0f64 { s.font_weight = 100.0f64 } else if w < 800.0f64 { s.font_weight = 400.0f64 } else { s.font_weight = 700.0f64 }
        } else {
            let (n, good) = plain_number(c, t)
            if good && n >= 1.0f64 && n <= 1000.0f64 { s.font_weight = n }
        }
        ret true
    }
    if str.eq(prop, "font-style") {
        let parts = cv.split_top_level_spaces(ap.a, cv.lower(ap.a, v))
        if parts.len > 0usize { s.font_style = kw[FontStyle](parts[0usize], ",normal,italic,oblique,", s.font_style) }
        ret true
    }
    if str.eq(prop, "font-family") {
        s.font_family = cv.trim_ws(v)
        ret true
    }
    if str.eq(prop, "line-height") {
        let (l, good) = parse_len(c, v, s.font_size, A_NORMAL | A_NUMBER | A_PERCENT)
        if good {
            if l.kind == .Px { s.line_height = len_px(l.px + l.pct * s.font_size) } else { s.line_height = l }
        }
        ret true
    }
    if str.eq(prop, "letter-spacing") {
        let t = cv.lower(ap.a, v)
        if str.eq(t, "normal") {
            s.letter_spacing = 0.0f64
        } else {
            let (px, good) = parse_px(c, t, s.font_size)
            if good { s.letter_spacing = px }
        }
        ret true
    }
    if str.eq(prop, "word-spacing") {
        let t = cv.lower(ap.a, v)
        if str.eq(t, "normal") {
            s.word_spacing = 0.0f64
        } else {
            let (px, good) = parse_px(c, t, s.font_size)
            if good { s.word_spacing = px }
        }
        ret true
    }
    ret false
}

fn parse_decoration_lines(a: *mem.Arena, v: str) -> (u8, bool) {
    let parts = cv.split_top_level_spaces(a, cv.lower(a, v))
    var bits = 0u8
    var i = 0usize
    while i < parts.len {
        let t = parts[i]
        if str.eq(t, "underline") {
            bits |= DECORATION_UNDERLINE
        } else if str.eq(t, "overline") {
            bits |= DECORATION_OVERLINE
        } else if str.eq(t, "line-through") {
            bits |= DECORATION_LINE_THROUGH
        } else if !str.eq(t, "none") && !str.eq(t, "blink") && !str.eq(t, "spelling-error") && !str.eq(t, "grammar-error") {
            ret (0u8, false)
        }
        i += 1usize
    }
    ret (bits, true)
}

fn apply_text(ap: *Ap, prop: str, v: str) -> bool {
    let s = ap.s
    let low = cv.lower(ap.a, v)
    if str.eq(prop, "text-align") {
        s.text_align = kw[TextAlign](low, ",start,end,left,right,center,justify,match-parent,", s.text_align)
        if str.eq(low, "-webkit-center") || str.eq(low, "-moz-center") { s.text_align = .Center }
        ret true
    }
    if str.eq(prop, "text-transform") {
        s.text_transform = kw[TextTransform](last_word(ap.a, low), ",none,capitalize,uppercase,lowercase,full-width,", s.text_transform)
        ret true
    }
    if str.eq(prop, "white-space") {
        s.white_space = kw[WhiteSpace](low, ",normal,pre,nowrap,pre-wrap,pre-line,break-spaces,", s.white_space)
        ret true
    }
    if str.eq(prop, "word-break") {
        s.word_break = kw[WordBreak](low, ",normal,break-all,keep-all,break-word,", s.word_break)
        ret true
    }
    if str.eq(prop, "overflow-wrap") || str.eq(prop, "word-wrap") {
        s.overflow_wrap = kw[OverflowWrap](low, ",normal,break-word,anywhere,", s.overflow_wrap)
        ret true
    }
    if str.eq(prop, "text-overflow") {
        let parts = cv.split_top_level_spaces(ap.a, low)
        if parts.len > 0usize { s.text_overflow = kw[TextOverflow](parts[0usize], ",clip,ellipsis,", s.text_overflow) }
        ret true
    }
    if str.eq(prop, "direction") {
        s.direction = kw[Direction](low, ",ltr,rtl,", s.direction)
        ret true
    }
    if str.eq(prop, "writing-mode") {
        s.writing_mode = kw[WritingMode](low, ",horizontal-tb,vertical-rl,vertical-lr,sideways-rl,sideways-lr,", s.writing_mode)
        if str.eq(low, "lr") || str.eq(low, "lr-tb") || str.eq(low, "rl") || str.eq(low, "rl-tb") { s.writing_mode = .HorizontalTb }
        if str.eq(low, "tb") || str.eq(low, "tb-rl") { s.writing_mode = .VerticalRl }
        if str.eq(low, "tb-lr") { s.writing_mode = .VerticalLr }
        ret true
    }
    if str.eq(prop, "text-indent") {
        let parts = cv.split_top_level_spaces(ap.a, low)
        if parts.len > 0usize {
            let (l, good) = parse_len(ap.c, parts[0usize], s.font_size, A_PERCENT | A_NEGATIVE)
            if good { s.text_indent = l }
        }
        ret true
    }
    if str.eq(prop, "vertical-align") {
        let at = idx_of(",baseline,sub,super,top,text-top,middle,bottom,text-bottom,", low)
        if at >= 0i32 {
            s.vertical_align = mem.bitcast[VAlign](u8(at))
        } else {
            let (l, good) = parse_len(ap.c, low, s.font_size, A_PERCENT | A_NEGATIVE)
            if good {
                s.vertical_align = .Length
                s.vertical_align_length = l
            }
        }
        ret true
    }
    if str.eq(prop, "text-decoration-line") {
        let (bits, good) = parse_decoration_lines(ap.a, low)
        if good { s.decoration_line = bits }
        ret true
    }
    if str.eq(prop, "text-decoration-style") {
        s.decoration_style = kw[DecorationStyle](low, ",solid,double,dotted,dashed,wavy,", s.decoration_style)
        ret true
    }
    if str.eq(prop, "text-decoration-color") {
        let (col, good) = parse_color_value(ap.c, v, s.color)
        if good {
            s.decoration_color = col
            s.decoration_current = str.eq(low, "currentcolor")
        }
        ret true
    }
    if str.eq(prop, "cursor") {
        s.cursor = low
        ret true
    }
    if str.eq(prop, "tab-size") {
        let (n, good) = plain_number(ap.c, low)
        if good {
            s.tab_size = n
        } else {
            let (px, good_px) = parse_px(ap.c, low, s.font_size)
            if good_px { s.tab_size = px }
        }
        ret true
    }
    ret false
}

fn apply_flex(ap: *Ap, prop: str, v: str) -> bool {
    let s = ap.s
    let low = cv.lower(ap.a, v)
    if str.eq(prop, "flex-direction") {
        s.flex_direction = kw[FlexDirection](low, ",row,row-reverse,column,column-reverse,", s.flex_direction)
        ret true
    }
    if str.eq(prop, "flex-wrap") {
        s.flex_wrap = kw[FlexWrap](low, ",nowrap,wrap,wrap-reverse,", s.flex_wrap)
        ret true
    }
    if str.eq(prop, "flex-grow") {
        let (n, good) = plain_number(ap.c, low)
        if good && n >= 0.0f64 { s.flex_grow = n }
        ret true
    }
    if str.eq(prop, "flex-shrink") {
        let (n, good) = plain_number(ap.c, low)
        if good && n >= 0.0f64 { s.flex_shrink = n }
        ret true
    }
    if str.eq(prop, "flex-basis") {
        if str.eq(low, "content") {
            s.flex_basis = len_auto()
            ret true
        }
        let (l, good) = parse_len(ap.c, low, s.font_size, A_AUTO | A_CONTENT | A_PERCENT)
        if good { s.flex_basis = l }
        ret true
    }
    if str.eq(prop, "order") {
        let (n, good) = plain_number(ap.c, low)
        if good { s.order = i64(n) }
        ret true
    }
    if str.eq(prop, "justify-content") {
        s.justify_content = parse_align(ap, low, s.justify_content)
        ret true
    }
    if str.eq(prop, "justify-items") {
        s.justify_items = parse_align(ap, low, s.justify_items)
        ret true
    }
    if str.eq(prop, "justify-self") {
        s.justify_self = parse_align(ap, low, s.justify_self)
        ret true
    }
    if str.eq(prop, "align-items") {
        s.align_items = parse_align(ap, low, s.align_items)
        ret true
    }
    if str.eq(prop, "align-self") {
        s.align_self = parse_align(ap, low, s.align_self)
        ret true
    }
    if str.eq(prop, "align-content") {
        s.align_content = parse_align(ap, low, s.align_content)
        ret true
    }
    if str.eq(prop, "row-gap") {
        let (l, good) = parse_len(ap.c, low, s.font_size, A_NORMAL | A_PERCENT)
        if good { s.row_gap = l }
        ret true
    }
    if str.eq(prop, "column-gap") {
        let (l, good) = parse_len(ap.c, low, s.font_size, A_NORMAL | A_PERCENT)
        if good { s.column_gap = l }
        ret true
    }
    ret false
}

fn apply_misc(ap: *Ap, prop: str, v: str) -> bool {
    let s = ap.s
    let low = cv.lower(ap.a, v)
    if str.eq(prop, "display") {
        let (dv, good) = parse_display(low)
        if good { s.display = dv }
        ret true
    }
    if str.eq(prop, "position") {
        s.position = kw[Position](low, ",static,relative,absolute,fixed,sticky,", s.position)
        if str.eq(low, "-webkit-sticky") { s.position = .Sticky }
        ret true
    }
    if str.eq(prop, "float") {
        s.floating = kw[Float](low, ",none,left,right,inline-start,inline-end,", s.floating)
        ret true
    }
    if str.eq(prop, "clear") {
        s.clear = kw[Clear](low, ",none,left,right,both,inline-start,inline-end,", s.clear)
        ret true
    }
    if str.eq(prop, "box-sizing") {
        s.box_sizing = kw[BoxSizing](low, ",content-box,border-box,", s.box_sizing)
        ret true
    }
    if str.eq(prop, "overflow-x") {
        s.overflow_x = kw[Overflow](low, ",visible,hidden,scroll,auto,clip,", s.overflow_x)
        ret true
    }
    if str.eq(prop, "overflow-y") {
        s.overflow_y = kw[Overflow](low, ",visible,hidden,scroll,auto,clip,", s.overflow_y)
        ret true
    }
    if str.eq(prop, "visibility") {
        s.visibility = kw[Visibility](low, ",visible,hidden,collapse,", s.visibility)
        ret true
    }
    if str.eq(prop, "opacity") {
        let (n, good) = parse_number_value(ap.c, low)
        if good { s.opacity = clamp01(n) }
        ret true
    }
    if str.eq(prop, "z-index") {
        if str.eq(low, "auto") {
            s.z_index_auto = true
            s.z_index = 0i64
        } else {
            let (n, good) = plain_number(ap.c, low)
            if good {
                s.z_index_auto = false
                s.z_index = i64(n)
            }
        }
        ret true
    }
    if str.eq(prop, "color") {
        let (col, good) = parse_color_value(ap.c, v, ap.parent.color)
        if good { s.color = col }
        ret true
    }
    if str.eq(prop, "background-color") {
        let (col, good) = parse_color_value(ap.c, v, s.color)
        if good {
            s.background_color = col
            // A colour function that mentions currentcolor is resolved again where it is inherited (the child's own `color`).
            let bg_low = cv.lower(ap.a, v)
            if (str.starts_with(cv.trim_ws(bg_low), "color-mix(") || str.starts_with(cv.trim_ws(bg_low), "contrast-color(")) && str.contains(bg_low, "currentcolor") {
                put_extra(ap, "x-bg-currentcolor", cv.trim_ws(v))
            } else {
                drop_extra(ap, "x-bg-currentcolor")
            }
        }
        ret true
    }
    if str.eq(prop, "list-style-type") {
        s.list_style_type = cv.trim_ws(v)
        ret true
    }
    if str.eq(prop, "list-style-position") {
        s.list_style_position = kw[ListPosition](low, ",outside,inside,", s.list_style_position)
        ret true
    }
    if str.eq(prop, "list-style-image") {
        s.list_style_image = cv.trim_ws(v)
        ret true
    }
    if str.eq(prop, "outline-width") {
        let (w, good) = border_width_value(ap.c, v, s.font_size)
        if good { s.outline_width = w }
        ret true
    }
    if str.eq(prop, "outline-style") {
        if str.eq(low, "auto") {
            s.outline_style = .Solid
        } else {
            s.outline_style = kw[BorderStyle](low, ",none,hidden,dotted,dashed,solid,double,groove,ridge,inset,outset,", s.outline_style)
        }
        ret true
    }
    if str.eq(prop, "outline-color") {
        let (col, good) = parse_color_value(ap.c, v, s.color)
        if good {
            s.outline_color = col
            s.outline_current = str.eq(low, "currentcolor")
        }
        ret true
    }
    if str.eq(prop, "outline-offset") {
        let (px, good) = parse_px(ap.c, low, s.font_size)
        if good { s.outline_offset = px }
        ret true
    }
    if str.eq(prop, "border-collapse") {
        s.border_collapse = kw[BorderCollapse](low, ",separate,collapse,", s.border_collapse)
        ret true
    }
    if str.eq(prop, "border-spacing") {
        let parts = cv.split_top_level_spaces(ap.a, low)
        if parts.len == 0usize || parts.len > 2usize { ret true }
        let (h, good_h) = parse_px(ap.c, parts[0usize], s.font_size)
        var vert = h
        var good_v = good_h
        if parts.len == 2usize {
            let (v2, g2) = parse_px(ap.c, parts[1usize], s.font_size)
            vert = v2
            good_v = g2
        }
        if good_h && good_v && h >= 0.0f64 && vert >= 0.0f64 {
            s.border_spacing_h = h
            s.border_spacing_v = vert
        }
        ret true
    }
    if str.eq(prop, "table-layout") {
        s.table_layout = kw[TableLayout](low, ",auto,fixed,", s.table_layout)
        ret true
    }
    if str.eq(prop, "caption-side") {
        s.caption_side = kw[CaptionSide](low, ",top,bottom,", s.caption_side)
        ret true
    }
    if str.eq(prop, "empty-cells") {
        s.empty_cells = kw[EmptyCells](low, ",show,hide,", s.empty_cells)
        ret true
    }
    ret false
}

// A property with no field: its declared text, kept for the consumers.
fn put_extra(ap: *Ap, prop: str, v: str) {
    var i = 0usize
    while i < ap.extras.len {
        if str.eq(ap.extras.items[i].name, prop) {
            ap.extras.items[i].value = v
            ret
        }
        i += 1usize
    }
    let pushed = list.push[Extra](&ap.extras, Extra { name: prop, value: v })
}

fn drop_extra(ap: *Ap, prop: str) {
    var i = 0usize
    while i < ap.extras.len {
        if str.eq(ap.extras.items[i].name, prop) {
            let gone = list.remove[Extra](&ap.extras, i)
            ret
        }
        i += 1usize
    }
}

fn tier_inherits(prop: str) -> bool {
    if nm(",color,font-size,font-weight,font-style,font-family,line-height,letter-spacing,word-spacing,text-indent,text-align,text-transform,white-space,word-break,overflow-wrap,word-wrap,text-overflow,direction,writing-mode,visibility,cursor,tab-size,list-style-type,list-style-position,list-style-image,border-collapse,border-spacing,caption-side,empty-cells,", prop) { ret true }
    ret inherited_extra(prop)
}

fn apply(ap: *Ap, prop: str, value: str) {
    let v = cv.trim_ws(value)
    if v.len == 0usize { ret }
    let low = cv.lower(ap.a, v)
    if is_wide(low) {
        apply_wide(ap, prop, low)
        ret
    }
    if apply_misc(ap, prop, v) { ret }
    if apply_font(ap, prop, v) { ret }
    if apply_text(ap, prop, v) { ret }
    if apply_size(ap, prop, v) { ret }
    if apply_flex(ap, prop, v) { ret }
    if apply_box(ap, prop, v) { ret }
    put_extra(ap, prop, v)
}

// `inherit`, `initial`, `unset` (and `revert`, taken as `unset`).
fn apply_wide(ap: *Ap, prop: str, keyword: str) {
    var take_parent = str.eq(keyword, "inherit")
    if str.eq(keyword, "unset") || str.eq(keyword, "revert") || str.eq(keyword, "revert-layer") { take_parent = tier_inherits(prop) }
    if take_parent {
        copy_prop(ap, ap.parent, prop)
        if str.eq(prop, "background-color") {
            var k = 0usize
            while k < ap.parent.extras.len {
                if str.eq(ap.parent.extras[k].name, "x-bg-currentcolor") {
                    let (col, good) = parse_color_value(ap.c, ap.parent.extras[k].value, ap.s.color)
                    if good {
                        ap.s.background_color = col
                        put_extra(ap, "x-bg-currentcolor", ap.parent.extras[k].value)
                    }
                }
                k += 1usize
            }
        }
    } else {
        let init = initial_style()
        copy_prop(ap, &init, prop)
    }
}

fn copy_prop(ap: *Ap, src: *const Style, prop: str) {
    let s = ap.s
    if str.eq(prop, "display") { s.display = src.display } else if str.eq(prop, "position") { s.position = src.position } else if str.eq(prop, "float") { s.floating = src.floating } else if str.eq(prop, "clear") { s.clear = src.clear } else if str.eq(prop, "box-sizing") { s.box_sizing = src.box_sizing } else if str.eq(prop, "overflow-x") { s.overflow_x = src.overflow_x } else if str.eq(prop, "overflow-y") { s.overflow_y = src.overflow_y } else if str.eq(prop, "visibility") { s.visibility = src.visibility } else if str.eq(prop, "opacity") { s.opacity = src.opacity } else if str.eq(prop, "z-index") {
        s.z_index_auto = src.z_index_auto
        s.z_index = src.z_index
    } else if str.eq(prop, "width") { s.width = src.width } else if str.eq(prop, "height") { s.height = src.height } else if str.eq(prop, "min-width") { s.min_width = src.min_width } else if str.eq(prop, "min-height") { s.min_height = src.min_height } else if str.eq(prop, "max-width") { s.max_width = src.max_width } else if str.eq(prop, "max-height") { s.max_height = src.max_height } else if str.eq(prop, "color") { s.color = src.color } else if str.eq(prop, "background-color") { s.background_color = src.background_color } else if str.eq(prop, "font-size") { s.font_size = src.font_size } else if str.eq(prop, "font-weight") { s.font_weight = src.font_weight } else if str.eq(prop, "font-style") { s.font_style = src.font_style } else if str.eq(prop, "font-family") { s.font_family = src.font_family } else if str.eq(prop, "line-height") { s.line_height = src.line_height } else if str.eq(prop, "letter-spacing") { s.letter_spacing = src.letter_spacing } else if str.eq(prop, "word-spacing") { s.word_spacing = src.word_spacing } else if str.eq(prop, "text-indent") { s.text_indent = src.text_indent } else if str.eq(prop, "text-align") { s.text_align = src.text_align } else if str.eq(prop, "text-transform") { s.text_transform = src.text_transform } else if str.eq(prop, "white-space") { s.white_space = src.white_space } else if str.eq(prop, "word-break") { s.word_break = src.word_break } else if str.eq(prop, "overflow-wrap") || str.eq(prop, "word-wrap") { s.overflow_wrap = src.overflow_wrap } else if str.eq(prop, "text-overflow") { s.text_overflow = src.text_overflow } else if str.eq(prop, "direction") { s.direction = src.direction } else if str.eq(prop, "writing-mode") { s.writing_mode = src.writing_mode } else if str.eq(prop, "vertical-align") {
        s.vertical_align = src.vertical_align
        s.vertical_align_length = src.vertical_align_length
    } else if str.eq(prop, "text-decoration-line") { s.decoration_line = src.decoration_line } else if str.eq(prop, "text-decoration-style") { s.decoration_style = src.decoration_style } else if str.eq(prop, "text-decoration-color") {
        s.decoration_color = src.decoration_color
        s.decoration_current = src.decoration_current
    } else if str.eq(prop, "cursor") { s.cursor = src.cursor } else if str.eq(prop, "tab-size") { s.tab_size = src.tab_size } else if str.eq(prop, "list-style-type") { s.list_style_type = src.list_style_type } else if str.eq(prop, "list-style-position") { s.list_style_position = src.list_style_position } else if str.eq(prop, "list-style-image") { s.list_style_image = src.list_style_image } else if str.eq(prop, "flex-direction") { s.flex_direction = src.flex_direction } else if str.eq(prop, "flex-wrap") { s.flex_wrap = src.flex_wrap } else if str.eq(prop, "flex-grow") { s.flex_grow = src.flex_grow } else if str.eq(prop, "flex-shrink") { s.flex_shrink = src.flex_shrink } else if str.eq(prop, "flex-basis") { s.flex_basis = src.flex_basis } else if str.eq(prop, "order") { s.order = src.order } else if str.eq(prop, "justify-content") { s.justify_content = src.justify_content } else if str.eq(prop, "justify-items") { s.justify_items = src.justify_items } else if str.eq(prop, "justify-self") { s.justify_self = src.justify_self } else if str.eq(prop, "align-items") { s.align_items = src.align_items } else if str.eq(prop, "align-self") { s.align_self = src.align_self } else if str.eq(prop, "align-content") { s.align_content = src.align_content } else if str.eq(prop, "row-gap") { s.row_gap = src.row_gap } else if str.eq(prop, "column-gap") { s.column_gap = src.column_gap } else if str.eq(prop, "outline-width") { s.outline_width = src.outline_width } else if str.eq(prop, "outline-style") { s.outline_style = src.outline_style } else if str.eq(prop, "outline-color") {
        s.outline_color = src.outline_color
        s.outline_current = src.outline_current
    } else if str.eq(prop, "outline-offset") { s.outline_offset = src.outline_offset } else if str.eq(prop, "border-collapse") { s.border_collapse = src.border_collapse } else if str.eq(prop, "border-spacing") {
        s.border_spacing_h = src.border_spacing_h
        s.border_spacing_v = src.border_spacing_v
    } else if str.eq(prop, "table-layout") { s.table_layout = src.table_layout } else if str.eq(prop, "caption-side") { s.caption_side = src.caption_side } else if str.eq(prop, "empty-cells") { s.empty_cells = src.empty_cells } else if str.starts_with(prop, "margin-") {
        let side = side_of(prop[7usize..])
        if side >= 0i32 { s.margin[usize(side)] = src.margin[usize(side)] }
    } else if str.starts_with(prop, "padding-") {
        let side = side_of(prop[8usize..])
        if side >= 0i32 { s.padding[usize(side)] = src.padding[usize(side)] }
    } else if side_of(prop) >= 0i32 { s.inset[usize(side_of(prop))] = src.inset[usize(side_of(prop))] } else if str.starts_with(prop, "border-") { copy_border(ap, src, prop) } else { copy_extra(ap, src, prop) }
}

fn copy_border(ap: *Ap, src: *const Style, prop: str) {
    let s = ap.s
    let rest = prop[7usize..]
    if str.ends_with(rest, "-width") {
        let side = side_of(rest[..rest.len - 6usize])
        if side >= 0i32 { s.border_width[usize(side)] = src.border_width[usize(side)] }
        ret
    }
    if str.ends_with(rest, "-style") {
        let side = side_of(rest[..rest.len - 6usize])
        if side >= 0i32 { s.border_style[usize(side)] = src.border_style[usize(side)] }
        ret
    }
    if str.ends_with(rest, "-color") {
        let side = side_of(rest[..rest.len - 6usize])
        if side >= 0i32 {
            s.border_color[usize(side)] = src.border_color[usize(side)]
            s.border_current[usize(side)] = src.border_current[usize(side)]
        }
        ret
    }
    var corner = -1i32
    if str.eq(prop, "border-top-left-radius") { corner = 0i32 }
    if str.eq(prop, "border-top-right-radius") { corner = 1i32 }
    if str.eq(prop, "border-bottom-right-radius") { corner = 2i32 }
    if str.eq(prop, "border-bottom-left-radius") { corner = 3i32 }
    if corner >= 0i32 {
        s.radius_h[usize(corner)] = src.radius_h[usize(corner)]
        s.radius_v[usize(corner)] = src.radius_v[usize(corner)]
        ret
    }
    copy_extra(ap, src, prop)
}

fn copy_extra(ap: *Ap, src: *const Style, prop: str) {
    var found = false
    var i = 0usize
    while i < src.extras.len {
        if str.eq(src.extras[i].name, prop) {
            put_extra(ap, prop, src.extras[i].value)
            found = true
        }
        i += 1usize
    }
    if !found { drop_extra(ap, prop) }
}

// --- var() and env().

fn find_custom(customs: []const Custom, name: str) -> (str, bool) {
    var i = customs.len
    while i > 0usize {
        i -= 1usize
        if str.eq(customs[i].name, name) { ret (customs[i].value, true) }
    }
    ret ("", false)
}

// Index of the `)` that closes the `(` at `open`, or -1.
fn close_paren(s: str, open: usize) -> i64 {
    var depth = 0i64
    var i = open
    while i < s.len {
        if s[i] == 40u8 { depth += 1i64 }
        if s[i] == 41u8 {
            depth -= 1i64
            if depth == 0i64 { ret i64(i) }
        }
        i += 1usize
    }
    ret -1i64
}

// `value` with every `var(--x, fallback)` and `env(name, fallback)` replaced; false when a reference has neither a
// value nor a fallback (the declaration is then invalid at computed-value time).
fn substitute(a: *mem.Arena, value: str, customs: []const Custom, depth: usize) -> (str, bool) {
    if depth > 8usize { ret ("", false) }
    if !str.contains(value, "var(") && !str.contains(value, "env(") { ret (value, true) }
    var b = try_builder(a, value.len + 16usize)
    var i = 0usize
    while i < value.len {
        var is_var = false
        var is_env = false
        if i + 4usize <= value.len && str.eq(value[i..i + 4usize], "var(") { is_var = true }
        if i + 4usize <= value.len && str.eq(value[i..i + 4usize], "env(") { is_env = true }
        if !is_var && !is_env {
            builder_byte(&b, value[i])
            i += 1usize
            continue
        }
        let close = close_paren(value, i + 3usize)
        if close < 0i64 { ret ("", false) }
        let inner = value[i + 4usize..usize(close)]
        var name = inner
        var fallback = ""
        var has_fallback = false
        var depth_in = 0i64
        var k = 0usize
        while k < inner.len {
            if inner[k] == 40u8 { depth_in += 1i64 }
            if inner[k] == 41u8 { depth_in -= 1i64 }
            if inner[k] == 44u8 && depth_in == 0i64 {
                name = inner[..k]
                fallback = cv.trim_ws(inner[k + 1usize..])
                has_fallback = true
                break
            }
            k += 1usize
        }
        name = cv.trim_ws(name)
        var replacement = ""
        var found = false
        if is_var {
            let (raw, has) = find_custom(customs, name)
            if has {
                let (inner_value, good) = substitute(a, raw, customs, depth + 1usize)
                if good {
                    replacement = inner_value
                    found = true
                }
            }
        } else {
            if str.starts_with(cv.lower(a, name), "safe-area-inset-") {
                replacement = "0px"
                found = true
            }
        }
        if !found {
            if !has_fallback { ret ("", false) }
            let (fb, good) = substitute(a, fallback, customs, depth + 1usize)
            if !good { ret ("", false) }
            replacement = fb
        }
        builder_text(&b, replacement)
        i = usize(close) + 1usize
    }
    ret (builder_done(&b), true)
}

// A growable byte string on the arena that never fails: a refusal drops the byte.
type Text = struct { a: *mem.Arena, b: str.Builder, bad: bool }

fn try_builder(a: *mem.Arena, cap: usize) -> Text {
    let (made, e) = str.builder(a, cap)
    var t: Text = zero
    t.a = a
    t.b = made
    t.bad = e != ok
    ret t
}

fn builder_byte(t: *Text, c: u8) {
    if t.bad { ret }
    let e = str.push_byte(&t.b, c)
    if e != ok { t.bad = true }
}

fn builder_text(t: *Text, s: str) {
    if t.bad { ret }
    let e = str.push(&t.b, s)
    if e != ok { t.bad = true }
}

fn builder_done(t: *Text) -> str {
    if t.bad { ret "" }
    ret str.done(&t.b)
}

// --- Ranking after expansion.

// `pseudo_kinds` has bit k set when some rule styles pseudo-element k.
type Sheet = struct { rules: []const cascade.Rule, index: cascade.Index, pindex: cascade.Index, author: bool, pseudo_kinds: u32 }

fn new_sheet(a: *mem.Arena, rules: []const cascade.Rule, author: bool) -> Sheet {
    var kinds = 0u32
    var i = 0usize
    while i < rules.len {
        if rules[i].pseudo >= 0i64 { kinds |= 1u32 << u32(rules[i].pseudo) }
        i += 1usize
    }
    ret Sheet { rules: rules, index: cascade.build_index(a, rules, false), pindex: cascade.build_index(a, rules, true), author: author, pseudo_kinds: kinds }
}

fn gather(m: *const cssm.Matcher, out: *list.List[cascade.Declared], rs: *const Sheet, el: html.NodeId, stack: []const cascade.ContainerBox, want: i64) {
    var which = &rs.index
    if want >= 0i64 { which = &rs.pindex }
    let visit = cascade.candidates(m, which, el)
    var v = 0usize
    while v < visit.len {
        let rule = rs.rules[visit[v]]
        v += 1usize
        if rule.pseudo != want { continue }
        if !cascade.containers_match(stack, rule.containers) { continue }
        var proximity = cascade.UNSCOPED
        if rule.scopes.len > 0usize {
            let (p, in_scope) = cascade.scope_proximity(m, rule.scopes, rule.selector, el)
            if !in_scope { continue }
            proximity = p
        } else if !cssm.selector_matches(m, rule.selector, el) {
            continue
        }
        let spec = selector.ordinal(selector.specificity(rule.selector))
        var d = 0usize
        while d < rule.declarations.len {
            let pushed = list.push[cascade.Declared](out, cascade.Declared { declaration: rule.declarations[d], author: rs.author, hint: false, specificity: spec, source: rule.source, has_layer: rule.has_layer, layer: rule.layer, proximity: proximity })
            d += 1usize
        }
    }
}

fn consider(best: *list.List[cascade.Declared], entry: cascade.Declared) {
    let at = cascade.find_property(best, entry.declaration.property)
    if at < 0i64 {
        let pushed = list.push[cascade.Declared](best, entry)
    } else if cascade.beats(entry, best.items[usize(at)]) {
        best.items[usize(at)] = entry
    }
}

// The winning longhand declarations: every shorthand is expanded first, each longhand then ranked by the
// declaration it came from. `rtl` selects the physical side of an inline-start property.
// A negative number is invalid for these properties: the declaration is dropped at parse time and must not override an earlier
// valid one in the cascade.
fn invalid_length_value(prop: str, v: str) -> bool {
    if !(str.eq(prop, "width") || str.eq(prop, "height") || str.eq(prop, "min-width") || str.eq(prop, "min-height") || str.eq(prop, "max-width") || str.eq(prop, "max-height") || str.starts_with(prop, "padding")) { ret false }
    let t = cv.trim_ws(v)
    if !(t.len > 1usize && t[0usize] == 45u8 && ((t[1usize] >= 48u8 && t[1usize] <= 57u8) || t[1usize] == 46u8)) { ret false }
    // `-0px` is a zero length and stays valid: invalid means some non-zero digit in the number.
    var i = 1usize
    while i < t.len && ((t[i] >= 48u8 && t[i] <= 57u8) || t[i] == 46u8) {
        if t[i] >= 49u8 && t[i] <= 57u8 { ret true }
        i += 1usize
    }
    ret false
}

fn rank_expanded(a: *mem.Arena, declared: []const cascade.Declared, rtl: bool) -> []const cascade.Declared {
    let (made, e) = list.init[cascade.Declared](a, declared.len + 8usize)
    if e != ok { ret zero }
    var best = made
    // One pair list for every declaration: its pairs are consumed before the next one is expanded.
    let (tmp_made, tmp_error) = list.init[expand.Pair](a, 8usize)
    if tmp_error != ok { ret zero }
    var pairs = tmp_made
    var i = 0usize
    while i < declared.len {
        let d = declared[i]
        i += 1usize
        let prop = d.declaration.property
        if str.starts_with(prop, "--") {
            consider(&best, d)
            continue
        }
        pairs.len = 0usize
        if expand.expand(a, prop, d.declaration.value, rtl, &pairs) {
            var p = 0usize
            while p < pairs.len {
                var copy = d
                copy.declaration = cascade.Declaration { property: pairs.items[p].property, value: pairs.items[p].value, important: d.declaration.important }
                if !invalid_length_value(pairs.items[p].property, pairs.items[p].value) { consider(&best, copy) }
                p += 1usize
            }
        } else if !invalid_length_value(prop, d.declaration.value) {
            consider(&best, d)
        }
    }
    ret list.slice_const[cascade.Declared](&best)
}

fn declared_direction(declared: []const cascade.Declared, fallback: bool) -> bool {
    var winner: cascade.Declared = zero
    var have = false
    var i = 0usize
    while i < declared.len {
        if str.eq(declared[i].declaration.property, "direction") {
            if !have || cascade.beats(declared[i], winner) {
                winner = declared[i]
                have = true
            }
        }
        i += 1usize
    }
    if !have { ret fallback }
    let v = cv.trim_ws(winner.declaration.value)
    if str.eq(v, "rtl") { ret true }
    if str.eq(v, "ltr") { ret false }
    ret fallback
}

// --- One element.

fn blockify(d: Display) -> Display {
    if d == .Inline || d == .InlineBlock || d == .TableRow || d == .TableCell || d == .TableRowGroup || d == .TableHeaderGroup || d == .TableFooterGroup || d == .TableColumn || d == .TableColumnGroup || d == .TableCaption || d == .Ruby || d == .RubyText || d == .RubyBase || d == .RubyTextContainer || d == .RubyBaseContainer { ret .Block }
    if d == .InlineFlex { ret .Flex }
    if d == .InlineGrid { ret .Grid }
    if d == .InlineTable { ret .Table }
    ret d
}

fn finish(s: *Style) {
    var i = 0usize
    while i < 4usize {
        if s.border_style[i] == .None || s.border_style[i] == .Hidden { s.border_width[i] = 0.0f64 }
        if s.border_current[i] { s.border_color[i] = s.color }
        i += 1usize
    }
    if s.outline_style == .None || s.outline_style == .Hidden { s.outline_width = 0.0f64 }
    if s.outline_current { s.outline_color = s.color }
    if s.decoration_current { s.decoration_color = s.color }
    if s.position == .Absolute || s.position == .Fixed || s.floating != .None {
        // An absolutely positioned box that was inline-level keeps its static position on the line.
        if s.display == .Inline || s.display == .InlineBlock || s.display == .InlineFlex || s.display == .InlineGrid || s.display == .InlineTable { s.was_inline = true }
        s.display = blockify(s.display)
    }
}

// The computed style of `el` given its parent's. `stack` holds the ancestor query containers (none for now).
fn compute(c: *const Context, m: *const cssm.Matcher, ua: *const Sheet, author: *const Sheet, el: html.NodeId, parent: *const Style) -> (Style, err) {
    let (s, _has, e) = compute_for(c, m, ua, author, el, parent, -1i64)
    ret (s, e)
}

// The style of element `el` (`want` -1) or of its pseudo-element `want`; `has` is false when nothing styles the
// pseudo-element (an element always has a style).
fn compute_for(c: *const Context, m: *const cssm.Matcher, ua: *const Sheet, author: *const Sheet, el: html.NodeId, parent: *const Style, want: i64) -> (Style, bool, err) {
    let a = c.a
    let stack: []const cascade.ContainerBox = zero
    let (made, made_error) = list.init[cascade.Declared](a, 32usize)
    if made_error != ok { ret (initial_style(), false, made_error) }
    var declared = made
    var hints: []const cascade.Declaration = zero
    if want < 0i64 { hints = cascade.presentational_hints(m, el) }
    var h = 0usize
    while h < hints.len {
        let pushed = list.push[cascade.Declared](&declared, cascade.Declared { declaration: hints[h], author: false, hint: true, specificity: 0i64, source: -1i64, has_layer: false, layer: 0i64, proximity: cascade.UNSCOPED })
        h += 1usize
    }
    gather(m, &declared, ua, el, stack, want)
    gather(m, &declared, author, el, stack, want)
    let (style_text, has_style) = html.attribute(&m.doc.nodes[usize(el)], "style")
    if has_style && want < 0i64 {
        let inline = cascade.inline_declarations(a, style_text)
        var k = 0usize
        while k < inline.len {
            let pushed = list.push[cascade.Declared](&declared, cascade.Declared { declaration: inline[k], author: true, hint: false, specificity: cascade.INLINE_SPECIFICITY, source: i64(k), has_layer: false, layer: 0i64, proximity: cascade.UNSCOPED })
            k += 1usize
        }
    }
    let all = list.slice_const[cascade.Declared](&declared)
    if want >= 0i64 && all.len == 0usize { ret (initial_style(), false, ok) }
    let rtl = declared_direction(all, parent.direction == .Rtl)
    let winners = rank_expanded(a, all, rtl)

    // Custom properties: the parent's, overridden by this element's, each with its own var() resolved. An element that sets
    // none shares its parent's list (copying it per element is what made custom-property-heavy sites cost gigabytes).
    var sets_custom = false
    var w = 0usize
    while w < winners.len {
        if str.starts_with(winners[w].declaration.property, "--") { sets_custom = true }
        w += 1usize
    }
    var custom_all = parent.custom
    if sets_custom {
        let (cmade, cerror) = list.init[Custom](a, parent.custom.len + 8usize)
        if cerror != ok { ret (initial_style(), false, cerror) }
        var customs = cmade
        var pc = 0usize
        while pc < parent.custom.len {
            let pushed = list.push[Custom](&customs, parent.custom[pc])
            pc += 1usize
        }
        w = 0usize
        while w < winners.len {
            let prop = winners[w].declaration.property
            if str.starts_with(prop, "--") {
                let (value, good) = substitute(a, cv.trim_ws(winners[w].declaration.value), list.slice_const[Custom](&customs), 0usize)
                if good {
                    let pushed = list.push[Custom](&customs, Custom { name: prop, value: value })
                }
            }
            w += 1usize
        }
        custom_all = list.slice_const[Custom](&customs)
    }

    var s = inherit_from(parent)
    s.custom = custom_all
    let (emade, eerror) = list.init[Extra](a, 8usize)
    if eerror != ok { ret (s, false, eerror) }
    // Font-relative `ch` and `ex` depend on the element's own font: Ahem (the test font) has a square `0` and an 0.8 em x-height.
    var cc = Context { a: c.a, viewport_width: c.viewport_width, viewport_height: c.viewport_height, root_font_size: c.root_font_size, dark: c.dark, ch: c.ch, ex: c.ex }
    var fw = 0usize
    if str.contains(cv.lower(a, parent.font_family), "ahem") {
        cc.ch = 1.0f64
        cc.ex = 0.8f64
    }
    while fw < winners.len {
        if str.eq(winners[fw].declaration.property, "font-family") {
            let fam = cv.lower(a, winners[fw].declaration.value)
            cc.ch = c.ch
            cc.ex = c.ex
            if str.contains(fam, "ahem") {
                cc.ch = 1.0f64
                cc.ex = 0.8f64
            }
        }
        fw += 1usize
    }
    var ap = Ap { c: &cc, s: &s, parent: parent, a: a, extras: emade }
    // Inherited extras start as the parent's.
    var px = 0usize
    while px < parent.extras.len {
        if inherited_extra(parent.extras[px].name) { put_extra(&ap, parent.extras[px].name, parent.extras[px].value) }
        px += 1usize
    }
    // Order: direction and writing mode, colour, font size, then the rest (they resolve against those).
    var pass = 0usize
    while pass < 4usize {
        var j = 0usize
        while j < winners.len {
            let prop = winners[j].declaration.property
            j += 1usize
            if str.starts_with(prop, "--") { continue }
            var wanted = 3usize
            if str.eq(prop, "direction") || str.eq(prop, "writing-mode") { wanted = 0usize }
            if str.eq(prop, "color") { wanted = 1usize }
            if str.eq(prop, "font-size") { wanted = 2usize }
            if wanted != pass { continue }
            let (value, good) = substitute(a, winners[j - 1usize].declaration.value, custom_all, 0usize)
            if good { apply(&ap, prop, value) } else { apply_wide(&ap, prop, "unset") }
        }
        pass += 1usize
    }
    finish(&s)
    s.extras = list.slice_const[Extra](&ap.extras)
    ret (s, true, ok)
}

// --- Style sheets: the rules of one sheet's text (see `e.fmt.css.sheet` for the at-rules it resolves).

fn parse_rules(a: *mem.Arena, source: str, order_start: i64) -> ([]const cascade.Rule, err) {
    var l = sheet.new_loader(a, sheet.media_env(1280.0f64, 720.0f64))
    l.order = order_start
    try sheet.load(&l, source)
    ret (sheet.finish(&l).rules, ok)
}

// --- The whole tree.

fn compute_below(c: *Context, m: *const cssm.Matcher, d: *const dom.Dom, ua: *const Sheet, author: *const Sheet, id: html.NodeId, parent: *const Style, out: []Style) -> err {
    var kid = d.nodes[usize(id)].first_child
    while kid != html.NONE {
        if d.nodes[usize(kid)].kind == .Element {
            let (s, e) = compute(c, m, ua, author, kid, parent)
            if e != ok { ret e }
            out[usize(kid)] = s
            let kinds = ua.pseudo_kinds | author.pseudo_kinds
            if kinds != 0u32 {
                var pk = 0usize
                while pk < 8usize {
                    if (kinds & (1u32 << u32(pk))) != 0u32 {
                        let (ps, has, pe) = compute_for(c, m, ua, author, kid, &out[usize(kid)], i64(pk))
                        if pe != ok { ret pe }
                        if has {
                            let (cell, ce) = mem.alloc[Style](c.a, 1usize)
                            if ce != ok { ret ce }
                            cell[0usize] = ps
                            out[usize(kid)].pseudo[pk] = &cell[0usize]
                        }
                    }
                    pk += 1usize
                }
            }
            if kid == first_root_element(d) { c.root_font_size = s.font_size }
            try compute_below(c, m, d, ua, author, kid, &out[usize(kid)], out)
        } else {
            try compute_below(c, m, d, ua, author, kid, parent, out)
        }
        kid = d.nodes[usize(kid)].next_sibling
    }
    ret ok
}

fn first_root_element(d: *const dom.Dom) -> html.NodeId {
    ret dom.first_element_child(d, d.root)
}

// The computed style of every element, indexed by node id (`out` holds at least `d.used` styles; other nodes keep
// the initial style). `ua` and `author` are the rule lists of the two origins.
fn compute_tree(c: *Context, d: *const dom.Dom, ua: []const cascade.Rule, author: []const cascade.Rule, out: []Style) -> err {
    if out.len < d.used { ret dom.Full }
    var i = 0usize
    while i < d.used {
        out[i] = initial_style()
        i += 1usize
    }
    let doc = dom.view(d)
    let m = cssm.new_matcher(c.a, &doc, cssm.no_state())
    let ua_sheet = new_sheet(c.a, ua, false)
    let author_sheet = new_sheet(c.a, author, true)
    let root_style = initial_style()
    try compute_below(c, &m, d, &ua_sheet, &author_sheet, d.root, &root_style, out)
    // The principal writing mode of the page comes from `<body>` when the root has one.
    let root_el = dom.first_element_child(d, d.root)
    if root_el != html.NONE {
        var kid = dom.first_element_child(d, root_el)
        while kid != html.NONE {
            if dom.is_html_named(d, kid, "body") {
                out[usize(root_el)].writing_mode = out[usize(kid)].writing_mode
                kid = html.NONE
            } else {
                kid = dom.next_element_sibling(d, kid)
            }
        }
    }
    ret ok
}

// --- A document with its own style sheets.

fn media_env_of(c: *const Context) -> sheet.MediaEnv {
    var env = sheet.media_env(c.viewport_width, c.viewport_height)
    env.dark = c.dark
    ret env
}

// Loads the text of every `<style>` element of the tree (in tree order) into `l`, skipping one whose `media` does not match.
fn load_style_elements(l: *sheet.Loader, d: *const dom.Dom) -> err {
    var cur = dom.next_in_tree(d, d.root, d.root)
    while cur != html.NONE {
        if dom.is_html_named(d, cur, "style") {
            let (media, has_media) = dom.get_attribute(d, cur, "media")
            if !has_media || sheet.media_matches(&l.env, l.a, media) {
                let text = try dom.text_content(l.a, d, cur)
                try sheet.load(l, text)
            }
        }
        cur = dom.next_in_tree(d, d.root, cur)
    }
    ret ok
}

// Every element's computed style with the user agent sheet, the document's `<style>` elements and `sheets` (author
// style sheets the caller fetched, as text, in cascade order: `<link>`s and `@import`s are the caller's to place).
fn compute_document(c: *Context, d: *const dom.Dom, sheets: []const str, out: []Style) -> err {
    ret compute_document_with(c, d, sheets, true, out)
}

// As `compute_document`, but the caller has placed every style sheet, `<style>` elements included, in `sheets`, in
// document order (a page loader that fetched the `<link>`s interleaves them).
fn compute_document_sheets(c: *Context, d: *const dom.Dom, sheets: []const str, out: []Style) -> err {
    ret compute_document_with(c, d, sheets, false, out)
}

fn compute_document_with(c: *Context, d: *const dom.Dom, sheets: []const str, style_elements: bool, out: []Style) -> err {
    let env = media_env_of(c)
    // Quirks mode (`Document.quirks` 2) adds the quirks-only user agent rules.
    let ua_loaded = try uacss.rules_for(c.a, env, d.quirks == 2u8)
    var l = sheet.new_loader(c.a, env)
    var i = 0usize
    while i < sheets.len {
        try sheet.load(&l, sheets[i])
        i += 1usize
    }
    if style_elements { try load_style_elements(&l, d) }
    let author_loaded = sheet.finish(&l)
    ret compute_tree(c, d, ua_loaded.rules, author_loaded.rules, out)
}
