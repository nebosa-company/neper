// Computed style values as CSS text (browser tracker 6.4): `value` answers the resolved value of a property of a computed
// `e.fmt.css.style` as `getComputedStyle(el).getPropertyValue(name)` would, for the properties the style engine models.
// Lengths that depend on layout (width, height, the used margins) are answered by the page from the layout box instead
// (see `e.web.page`).

use e.fmt.css.style as style
use e.mem
use e.str

fn cat3(a: *mem.Arena, x: str, y: str, z: str) -> str {
    let (xy, e1) = str.concat(a, x, y)
    let (xyz, e2) = str.concat(a, xy, z)
    if e1 != ok || e2 != ok { ret "" }
    ret xyz
}

fn push_number(b: *str.Builder, x: f64) {
    var v = x
    if v < 0.0f64 {
        let e0 = str.push(b, "-")
        v = 0.0f64 - v
    }
    let scaled = f64(i64(v * 1000.0f64 + 0.5f64))
    let whole = i64(scaled / 1000.0f64)
    var frac = i64(scaled) - whole * 1000i64
    let e1 = str.push_i64(b, whole)
    if frac != 0i64 {
        let e2 = str.push(b, ".")
        var f = frac
        var pad = 100i64
        while pad > 0i64 && f > 0i64 {
            let d = f / pad
            let e3 = str.push_byte(b, u8(48i64 + d))
            f = f - d * pad
            pad = pad / 10i64
        }
    }
}

fn px_text(a: *mem.Arena, x: f64) -> str {
    let (bb, be) = str.builder(a, 24usize)
    var b = bb
    if be != ok { ret "" }
    push_number(&b, x)
    let e = str.push(&b, "px")
    ret str.done(&b)
}

fn number_text(a: *mem.Arena, x: f64) -> str {
    let (bb, be) = str.builder(a, 24usize)
    var b = bb
    if be != ok { ret "" }
    push_number(&b, x)
    ret str.done(&b)
}

fn len_text(a: *mem.Arena, l: style.Len) -> str {
    switch l.kind {
    case .Auto:
        ret "auto"
    case .None:
        ret "none"
    case .MinContent:
        ret "min-content"
    case .MaxContent:
        ret "max-content"
    case .FitContent:
        ret "fit-content"
    case .Normal:
        ret "normal"
    case .Number:
        ret number_text(a, l.px)
    case .Px:
        if l.pct != 0.0f64 && l.px == 0.0f64 {
            let (bb, be) = str.builder(a, 24usize)
            var b = bb
            if be != ok { ret "" }
            push_number(&b, l.pct * 100.0f64)
            let e = str.push(&b, "%")
            ret str.done(&b)
        }
        ret px_text(a, l.px)
    }
    ret "auto"
}

fn color_text(a: *mem.Arena, c: u32) -> str {
    let alpha = (c >> 24u32) & 255u32
    let r = (c >> 16u32) & 255u32
    let g = (c >> 8u32) & 255u32
    let bl = c & 255u32
    let (bb, be) = str.builder(a, 40usize)
    var b = bb
    if be != ok { ret "" }
    if alpha == 255u32 {
        let e0 = str.push(&b, "rgb(")
    } else {
        let e1 = str.push(&b, "rgba(")
    }
    let e2 = str.push_u32(&b, r)
    let e3 = str.push(&b, ", ")
    let e4 = str.push_u32(&b, g)
    let e5 = str.push(&b, ", ")
    let e6 = str.push_u32(&b, bl)
    if alpha != 255u32 {
        let e7 = str.push(&b, ", ")
        push_number(&b, f64(alpha) / 255.0f64)
    }
    let e8 = str.push(&b, ")")
    ret str.done(&b)
}

fn display_text(d: style.Display) -> str {
    switch d {
    case .Inline:
        ret "inline"
    case .Block:
        ret "block"
    case .None:
        ret "none"
    case .Contents:
        ret "contents"
    case .InlineBlock:
        ret "inline-block"
    case .Flex:
        ret "flex"
    case .InlineFlex:
        ret "inline-flex"
    case .Grid:
        ret "grid"
    case .InlineGrid:
        ret "inline-grid"
    case .Table:
        ret "table"
    case .InlineTable:
        ret "inline-table"
    case .TableRow:
        ret "table-row"
    case .TableCell:
        ret "table-cell"
    case .TableRowGroup:
        ret "table-row-group"
    case .TableHeaderGroup:
        ret "table-header-group"
    case .TableFooterGroup:
        ret "table-footer-group"
    case .TableColumn:
        ret "table-column"
    case .TableColumnGroup:
        ret "table-column-group"
    case .TableCaption:
        ret "table-caption"
    case .ListItem:
        ret "list-item"
    case .FlowRoot:
        ret "flow-root"
    default:
        ret "inline"
    }
    ret "inline"
}

fn position_text(p: style.Position) -> str {
    switch p {
    case .Relative:
        ret "relative"
    case .Absolute:
        ret "absolute"
    case .Fixed:
        ret "fixed"
    case .Sticky:
        ret "sticky"
    default:
        ret "static"
    }
    ret "static"
}

fn border_style_text(s: style.BorderStyle) -> str {
    switch s {
    case .Hidden:
        ret "hidden"
    case .Dotted:
        ret "dotted"
    case .Dashed:
        ret "dashed"
    case .Solid:
        ret "solid"
    case .Double:
        ret "double"
    case .Groove:
        ret "groove"
    case .Ridge:
        ret "ridge"
    case .Inset:
        ret "inset"
    case .Outset:
        ret "outset"
    default:
        ret "none"
    }
    ret "none"
}

fn overflow_text(o: style.Overflow) -> str {
    switch o {
    case .Hidden:
        ret "hidden"
    case .Scroll:
        ret "scroll"
    case .Auto:
        ret "auto"
    case .Clip:
        ret "clip"
    default:
        ret "visible"
    }
    ret "visible"
}

fn align_text(x: style.Align) -> str {
    switch x {
    case .Start:
        ret "start"
    case .End:
        ret "end"
    case .FlexStart:
        ret "flex-start"
    case .FlexEnd:
        ret "flex-end"
    case .Center:
        ret "center"
    case .Stretch:
        ret "stretch"
    case .SpaceBetween:
        ret "space-between"
    case .SpaceAround:
        ret "space-around"
    case .SpaceEvenly:
        ret "space-evenly"
    case .Baseline:
        ret "baseline"
    case .Left:
        ret "left"
    case .Right:
        ret "right"
    case .Auto:
        ret "auto"
    default:
        ret "normal"
    }
    ret "normal"
}

fn side_index(prop: str, prefix: str, suffix: str) -> i32 {
    // "margin-top" with prefix "margin-" and an empty suffix, or "border-top-width" with "border-" and "-width".
    if !str.starts_with(prop, prefix) { ret -1i32 }
    if !str.ends_with(prop, suffix) { ret -1i32 }
    if prop.len < prefix.len + suffix.len { ret -1i32 }
    let mid = prop[prefix.len..prop.len - suffix.len]
    if str.eq(mid, "top") { ret 0i32 }
    if str.eq(mid, "right") { ret 1i32 }
    if str.eq(mid, "bottom") { ret 2i32 }
    if str.eq(mid, "left") { ret 3i32 }
    ret -1i32
}

// The computed value of `prop` (a lowercase CSS property name) of `s`; false when the property is not modelled.
fn value(a: *mem.Arena, s: *const style.Style, prop: str) -> (str, bool) {
    if str.eq(prop, "display") { ret (display_text(s.display), true) }
    if str.eq(prop, "position") { ret (position_text(s.position), true) }
    if str.eq(prop, "float") || str.eq(prop, "css-float") {
        switch s.floating {
        case .Left:
            ret ("left", true)
        case .Right:
            ret ("right", true)
        default:
            ret ("none", true)
        }
    }
    if str.eq(prop, "clear") {
        switch s.clear {
        case .Left:
            ret ("left", true)
        case .Right:
            ret ("right", true)
        case .Both:
            ret ("both", true)
        default:
            ret ("none", true)
        }
    }
    if str.eq(prop, "box-sizing") {
        if s.box_sizing == .BorderBox { ret ("border-box", true) }
        ret ("content-box", true)
    }
    if str.eq(prop, "overflow-x") { ret (overflow_text(s.overflow_x), true) }
    if str.eq(prop, "overflow-y") { ret (overflow_text(s.overflow_y), true) }
    if str.eq(prop, "overflow") {
        if s.overflow_x == s.overflow_y { ret (overflow_text(s.overflow_x), true) }
        ret (cat3(a, overflow_text(s.overflow_x), " ", overflow_text(s.overflow_y)), true)
    }
    if str.eq(prop, "visibility") {
        switch s.visibility {
        case .Hidden:
            ret ("hidden", true)
        case .Collapse:
            ret ("collapse", true)
        default:
            ret ("visible", true)
        }
    }
    if str.eq(prop, "width") { ret (len_text(a, s.width), true) }
    if str.eq(prop, "height") { ret (len_text(a, s.height), true) }
    if str.eq(prop, "min-width") { ret (len_text(a, s.min_width), true) }
    if str.eq(prop, "min-height") { ret (len_text(a, s.min_height), true) }
    if str.eq(prop, "max-width") { ret (len_text(a, s.max_width), true) }
    if str.eq(prop, "max-height") { ret (len_text(a, s.max_height), true) }
    let m = side_index(prop, "margin-", "")
    if m >= 0i32 { ret (len_text(a, s.margin[usize(m)]), true) }
    let pd = side_index(prop, "padding-", "")
    if pd >= 0i32 { ret (len_text(a, s.padding[usize(pd)]), true) }
    let ins = side_index(prop, "", "")
    if ins >= 0i32 { ret (len_text(a, s.inset[usize(ins)]), true) }
    let bw = side_index(prop, "border-", "-width")
    if bw >= 0i32 {
        var w = s.border_width[usize(bw)]
        if s.border_style[usize(bw)] == .None || s.border_style[usize(bw)] == .Hidden { w = 0.0f64 }
        ret (px_text(a, w), true)
    }
    let bs = side_index(prop, "border-", "-style")
    if bs >= 0i32 { ret (border_style_text(s.border_style[usize(bs)]), true) }
    let bc = side_index(prop, "border-", "-color")
    if bc >= 0i32 {
        if s.border_current[usize(bc)] { ret (color_text(a, s.color), true) }
        ret (color_text(a, s.border_color[usize(bc)]), true)
    }
    if str.eq(prop, "z-index") {
        if s.z_index_auto { ret ("auto", true) }
        ret (number_text(a, f64(s.z_index)), true)
    }
    if str.eq(prop, "opacity") { ret (number_text(a, s.opacity), true) }
    if str.eq(prop, "color") { ret (color_text(a, s.color), true) }
    if str.eq(prop, "background-color") { ret (color_text(a, s.background_color), true) }
    if str.eq(prop, "font-size") { ret (px_text(a, s.font_size), true) }
    if str.eq(prop, "font-weight") { ret (number_text(a, s.font_weight), true) }
    if str.eq(prop, "font-style") {
        switch s.font_style {
        case .Italic:
            ret ("italic", true)
        case .Oblique:
            ret ("oblique", true)
        default:
            ret ("normal", true)
        }
    }
    if str.eq(prop, "font-family") { ret (s.font_family, true) }
    if str.eq(prop, "line-height") { ret (len_text(a, s.line_height), true) }
    if str.eq(prop, "letter-spacing") {
        if s.letter_spacing == 0.0f64 { ret ("normal", true) }
        ret (px_text(a, s.letter_spacing), true)
    }
    if str.eq(prop, "word-spacing") {
        if s.word_spacing == 0.0f64 { ret ("normal", true) }
        ret (px_text(a, s.word_spacing), true)
    }
    if str.eq(prop, "text-indent") { ret (len_text(a, s.text_indent), true) }
    if str.eq(prop, "text-align") {
        switch s.text_align {
        case .End:
            ret ("end", true)
        case .Left:
            ret ("left", true)
        case .Right:
            ret ("right", true)
        case .Center:
            ret ("center", true)
        case .Justify:
            ret ("justify", true)
        default:
            ret ("start", true)
        }
    }
    if str.eq(prop, "text-transform") {
        switch s.text_transform {
        case .Capitalize:
            ret ("capitalize", true)
        case .Uppercase:
            ret ("uppercase", true)
        case .Lowercase:
            ret ("lowercase", true)
        default:
            ret ("none", true)
        }
    }
    if str.eq(prop, "white-space") {
        switch s.white_space {
        case .Pre:
            ret ("pre", true)
        case .Nowrap:
            ret ("nowrap", true)
        case .PreWrap:
            ret ("pre-wrap", true)
        case .PreLine:
            ret ("pre-line", true)
        case .BreakSpaces:
            ret ("break-spaces", true)
        default:
            ret ("normal", true)
        }
    }
    if str.eq(prop, "direction") {
        if s.direction == .Rtl { ret ("rtl", true) }
        ret ("ltr", true)
    }
    if str.eq(prop, "text-decoration-line") {
        if s.decoration_line == 0u8 { ret ("none", true) }
        var out = ""
        if (s.decoration_line & style.DECORATION_UNDERLINE) != 0u8 { out = "underline" }
        if (s.decoration_line & style.DECORATION_OVERLINE) != 0u8 { out = cat3(a, out, " ", "overline") }
        if (s.decoration_line & style.DECORATION_LINE_THROUGH) != 0u8 { out = cat3(a, out, " ", "line-through") }
        ret (str.trim(out), true)
    }
    if str.eq(prop, "cursor") {
        if s.cursor.len == 0usize { ret ("auto", true) }
        ret (s.cursor, true)
    }
    if str.eq(prop, "list-style-type") {
        if s.list_style_type.len == 0usize { ret ("disc", true) }
        ret (s.list_style_type, true)
    }
    if str.eq(prop, "flex-direction") {
        switch s.flex_direction {
        case .RowReverse:
            ret ("row-reverse", true)
        case .Column:
            ret ("column", true)
        case .ColumnReverse:
            ret ("column-reverse", true)
        default:
            ret ("row", true)
        }
    }
    if str.eq(prop, "flex-wrap") {
        switch s.flex_wrap {
        case .Wrap:
            ret ("wrap", true)
        case .WrapReverse:
            ret ("wrap-reverse", true)
        default:
            ret ("nowrap", true)
        }
    }
    if str.eq(prop, "flex-grow") { ret (number_text(a, s.flex_grow), true) }
    if str.eq(prop, "flex-shrink") { ret (number_text(a, s.flex_shrink), true) }
    if str.eq(prop, "flex-basis") { ret (len_text(a, s.flex_basis), true) }
    if str.eq(prop, "order") { ret (number_text(a, f64(s.order)), true) }
    if str.eq(prop, "justify-content") { ret (align_text(s.justify_content), true) }
    if str.eq(prop, "align-items") { ret (align_text(s.align_items), true) }
    if str.eq(prop, "align-self") { ret (align_text(s.align_self), true) }
    if str.eq(prop, "align-content") { ret (align_text(s.align_content), true) }
    if str.eq(prop, "row-gap") { ret (len_text(a, s.row_gap), true) }
    if str.eq(prop, "column-gap") { ret (len_text(a, s.column_gap), true) }
    // Custom properties and the properties the engine keeps as text.
    var i = 0usize
    while i < s.custom.len {
        if str.eq(s.custom[i].name, prop) { ret (s.custom[i].value, true) }
        i += 1usize
    }
    var j = 0usize
    while j < s.extras.len {
        if str.eq(s.extras[j].name, prop) { ret (s.extras[j].value, true) }
        j += 1usize
    }
    ret ("", false)
}
