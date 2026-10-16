// Shorthand and logical property expansion for the style resolver (tracker 1.13): a declaration `margin: 1px 2px`
// becomes its longhands `margin-top: 1px` ... so the cascade ranks each longhand on its own (a later `margin-left`
// beats an earlier `margin`, and the other way round), and a logical property (`margin-inline-start`, `inset-block`,
// `inline-size`) becomes its physical counterpart for a horizontal-tb writing mode in the element's direction.
//
// `expand(a, property, value, rtl, out)` appends the longhands to `out` in the order the shorthand sets them and
// answers true when `property` was one it handles; false means it is a plain longhand (or a property this module
// leaves whole, such as `transition` or `grid-template`) and the caller keeps the declaration as it is. A value the
// shorthand grammar rejects (too many values, two widths) expands to nothing, so the declaration is dropped as the
// spec says. A CSS-wide keyword (`inherit`, `initial`, `unset`, `revert`, `revert-layer`) is passed to every longhand.
//
// Values are the raw declaration text; the longhands are text too, in the forms `e.fmt.css.style` reads. The input
// is lower-cased by the caller for keywords it compares, but values keep their case (a font family, a URL).
//
// Memory: the arena is retained; every string and list lives in it.

use e.data.list as list
use e.gfx.cssvalue as cv
use e.mem
use e.str

type Pair = struct { property: str, value: str }

fn emit(out: *list.List[Pair], property: str, value: str) {
    let pushed = list.push[Pair](out, Pair { property: property, value: value })
}

fn lc(a: *mem.Arena, s: str) -> str { ret cv.lower(a, cv.trim_ws(s)) }

fn is_wide_keyword(v: str) -> bool {
    ret str.eq(v, "inherit") || str.eq(v, "initial") || str.eq(v, "unset") || str.eq(v, "revert") || str.eq(v, "revert-layer")
}

fn join2(a: *mem.Arena, x: str, y: str) -> str {
    let (r, e) = str.concat(a, x, y)
    if e != ok { ret x }
    ret r
}

fn dash(a: *mem.Arena, x: str, y: str) -> str {
    ret join2(a, join2(a, x, "-"), y)
}

fn dash3(a: *mem.Arena, x: str, y: str, z: str) -> str {
    ret dash(a, dash(a, x, y), z)
}

fn spaced(a: *mem.Arena, parts: []const str) -> str {
    let (r, e) = str.join(a, parts, " ")
    if e != ok { ret "" }
    ret r
}

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

type Four = struct { top: str, right: str, bottom: str, left: str, good: bool }

// 1 to 4 values to top, right, bottom, left.
fn box4(parts: []const str) -> Four {
    if parts.len == 0usize || parts.len > 4usize { ret Four { top: "", right: "", bottom: "", left: "", good: false } }
    let t = parts[0usize]
    var r = t
    var b = t
    var l = t
    if parts.len >= 2usize {
        r = parts[1usize]
        l = r
    }
    if parts.len >= 3usize { b = parts[2usize] }
    if parts.len == 4usize { l = parts[3usize] }
    ret Four { top: t, right: r, bottom: b, left: l, good: true }
}

fn expand_four(a: *mem.Arena, value: str, prefix: str, suffix: str, out: *list.List[Pair]) {
    let f = box4(cv.split_top_level_spaces(a, value))
    if !f.good { ret }
    var top = dash(a, prefix, "top")
    var right = dash(a, prefix, "right")
    var bottom = dash(a, prefix, "bottom")
    var left = dash(a, prefix, "left")
    if suffix.len > 0usize {
        top = dash(a, top, suffix)
        right = dash(a, right, suffix)
        bottom = dash(a, bottom, suffix)
        left = dash(a, left, suffix)
    }
    emit(out, top, f.top)
    emit(out, right, f.right)
    emit(out, bottom, f.bottom)
    emit(out, left, f.left)
}

// `a b` (or `a`) to a start and end property.
fn expand_pair(a: *mem.Arena, value: str, start: str, end: str, out: *list.List[Pair]) {
    let parts = cv.split_top_level_spaces(a, value)
    if parts.len == 0usize || parts.len > 2usize { ret }
    emit(out, start, parts[0usize])
    if parts.len == 2usize { emit(out, end, parts[1usize]) } else { emit(out, end, parts[0usize]) }
}

// --- border

fn is_style_kw(t: str) -> bool {
    ret nm(",none,hidden,dotted,dashed,solid,double,groove,ridge,inset,outset,", t)
}

fn is_width_kw(t: str) -> bool { ret nm(",thin,medium,thick,", t) }

fn looks_numeric(t: str) -> bool {
    if t.len == 0usize { ret false }
    let c = t[0usize]
    if c >= 48u8 && c <= 57u8 { ret true }
    if c == 46u8 || c == 43u8 || c == 45u8 { ret true }
    ret str.starts_with(t, "calc(") || str.starts_with(t, "min(") || str.starts_with(t, "max(") || str.starts_with(t, "clamp(")
}

type Edge = struct { width: str, style: str, color: str, good: bool }

// `<width> || <style> || <color>`; an absent part keeps its initial value.
fn border_parts(a: *mem.Arena, value: str) -> Edge {
    let toks = cv.split_top_level_spaces(a, value)
    var width = ""
    var style = ""
    var color = ""
    var i = 0usize
    while i < toks.len {
        let t = lc(a, toks[i])
        i += 1usize
        if is_style_kw(t) {
            if style.len > 0usize { ret Edge { width: "", style: "", color: "", good: false } }
            style = t
        } else if is_width_kw(t) || looks_numeric(t) {
            if width.len > 0usize { ret Edge { width: "", style: "", color: "", good: false } }
            width = t
        } else {
            if color.len > 0usize { ret Edge { width: "", style: "", color: "", good: false } }
            color = toks[i - 1usize]
        }
    }
    if width.len == 0usize { width = "medium" }
    if style.len == 0usize { style = "none" }
    if color.len == 0usize { color = "currentcolor" }
    ret Edge { width: width, style: style, color: color, good: true }
}

fn expand_edge(a: *mem.Arena, value: str, side: str, out: *list.List[Pair]) {
    let e = border_parts(a, value)
    if !e.good { ret }
    emit(out, dash3(a, "border", side, "width"), e.width)
    emit(out, dash3(a, "border", side, "style"), e.style)
    emit(out, dash3(a, "border", side, "color"), e.color)
}

fn expand_border_all(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let e = border_parts(a, value)
    if !e.good { ret }
    var s = 0usize
    while s < 4usize {
        var side = "top"
        if s == 1usize { side = "right" }
        if s == 2usize { side = "bottom" }
        if s == 3usize { side = "left" }
        emit(out, dash3(a, "border", side, "width"), e.width)
        emit(out, dash3(a, "border", side, "style"), e.style)
        emit(out, dash3(a, "border", side, "color"), e.color)
        s += 1usize
    }
    // The `border` shorthand also resets the image.
    emit(out, "border-image-source", "none")
    emit(out, "border-image-slice", "100%")
    emit(out, "border-image-width", "1")
    emit(out, "border-image-outset", "0")
    emit(out, "border-image-repeat", "stretch")
}

// border-radius: up to four horizontal radii, then `/` and up to four vertical ones.
fn expand_radius(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let (slash, found) = str.find(value, "/")
    var hs = value
    var vs = ""
    if found {
        hs = value[..slash]
        vs = value[slash + 1usize..]
    }
    let h = box4(cv.split_top_level_spaces(a, hs))
    if !h.good { ret }
    var v = h
    if found {
        v = box4(cv.split_top_level_spaces(a, vs))
        if !v.good { ret }
    }
    let corner = [_]str{ "border-top-left-radius", "border-top-right-radius", "border-bottom-right-radius", "border-bottom-left-radius" }
    let hv = [_]str{ h.top, h.right, h.bottom, h.left }
    let vv = [_]str{ v.top, v.right, v.bottom, v.left }
    var i = 0usize
    while i < 4usize {
        if str.eq(hv[i], vv[i]) { emit(out, corner[i], hv[i]) } else { emit(out, corner[i], join2(a, join2(a, hv[i], " "), vv[i])) }
        i += 1usize
    }
}

// --- font

fn is_size_kw(t: str) -> bool {
    ret nm(",xx-small,x-small,small,medium,large,x-large,xx-large,xxx-large,smaller,larger,", t)
}

fn is_system_font(t: str) -> bool {
    ret nm(",caption,icon,menu,message-box,small-caption,status-bar,", t)
}

fn is_weight_kw(t: str) -> bool {
    if nm(",bold,bolder,lighter,", t) { ret true }
    ret t.len > 0usize && cv.is_digit(t[0usize]) && !str.contains(t, "px") && !str.contains(t, "em") && !str.contains(t, "%") && !str.contains(t, "/")
}

fn is_stretch_kw(t: str) -> bool {
    ret nm(",ultra-condensed,extra-condensed,condensed,semi-condensed,semi-expanded,expanded,extra-expanded,ultra-expanded,", t)
}

fn size_part(t: str) -> str {
    let (slash, found) = str.find(t, "/")
    if found { ret t[..slash] }
    ret t
}

fn expand_font(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let v = cv.trim_ws(value)
    let low = lc(a, v)
    if is_system_font(low) {
        emit(out, "font-style", "normal")
        emit(out, "font-variant-caps", "normal")
        emit(out, "font-weight", "normal")
        emit(out, "font-stretch", "normal")
        emit(out, "font-size", "13.3333px")
        emit(out, "line-height", "normal")
        emit(out, "font-family", "system-ui")
        ret
    }
    let toks = cv.split_top_level_spaces(a, v)
    var size_at = toks.len
    var i = 0usize
    while i < toks.len {
        let t = lc(a, size_part(toks[i]))
        if is_size_kw(t) || (looks_numeric(t) && !is_weight_kw(t)) || (is_weight_kw(t) && (str.contains(toks[i], "/") || i + 1usize == size_at)) {
            size_at = i
            break
        }
        // A bare number is a weight before the size; a length has a unit.
        if looks_numeric(t) && (str.contains(t, "px") || str.contains(t, "em") || str.contains(t, "pt") || str.contains(t, "%") || str.contains(t, "rem") || str.contains(t, "vw") || str.contains(t, "vh") || str.contains(t, "ex") || t.len > 0usize && str.eq(t, "0")) {
            size_at = i
            break
        }
        i += 1usize
    }
    if size_at >= toks.len || size_at + 1usize >= toks.len { ret }
    var style = "normal"
    var variant = "normal"
    var weight = "normal"
    var stretch = "normal"
    var j = 0usize
    while j < size_at {
        let t = lc(a, toks[j])
        if str.eq(t, "italic") || str.eq(t, "oblique") {
            style = t
            if j + 1usize < size_at && looks_numeric(lc(a, toks[j + 1usize])) && (str.contains(toks[j + 1usize], "deg") || str.contains(toks[j + 1usize], "turn") || str.contains(toks[j + 1usize], "rad")) {
                style = join2(a, join2(a, t, " "), toks[j + 1usize])
                j += 1usize
            }
        } else if str.eq(t, "small-caps") {
            variant = t
        } else if is_weight_kw(t) {
            weight = t
        } else if is_stretch_kw(t) {
            stretch = t
        } else if !str.eq(t, "normal") {
            ret
        }
        j += 1usize
    }
    let size_tok = toks[size_at]
    var size = size_tok
    var line = "normal"
    let (slash, has_slash) = str.find(size_tok, "/")
    if has_slash {
        size = size_tok[..slash]
        line = size_tok[slash + 1usize..]
        if line.len == 0usize && size_at + 1usize < toks.len { line = "normal" }
    }
    var family_from = size_at + 1usize
    // `size / line-height` written with spaces around the slash.
    if !has_slash && size_at + 1usize < toks.len && str.starts_with(toks[size_at + 1usize], "/") {
        let rest = toks[size_at + 1usize]
        if rest.len > 1usize {
            line = rest[1usize..]
            family_from = size_at + 2usize
        } else if size_at + 2usize < toks.len {
            line = toks[size_at + 2usize]
            family_from = size_at + 3usize
        }
    } else if has_slash && size_tok.len > 0usize && str.eq(size_tok[size_tok.len - 1usize..], "/") && size_at + 1usize < toks.len {
        line = toks[size_at + 1usize]
        family_from = size_at + 2usize
    }
    if family_from >= toks.len { ret }
    emit(out, "font-style", style)
    emit(out, "font-variant-caps", variant)
    emit(out, "font-weight", weight)
    emit(out, "font-stretch", stretch)
    emit(out, "font-size", size)
    emit(out, "line-height", line)
    emit(out, "font-family", spaced(a, toks[family_from..]))
}

// --- flex

fn is_plain_number(t: str) -> bool {
    if t.len == 0usize { ret false }
    var i = 0usize
    var digits = 0usize
    while i < t.len {
        let c = t[i]
        if c >= 48u8 && c <= 57u8 { digits += 1usize } else {
            if !(c == 46u8 || ((c == 43u8 || c == 45u8) && i == 0usize)) { ret false }
        }
        i += 1usize
    }
    ret digits > 0usize
}

fn expand_flex(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let v = lc(a, value)
    if str.eq(v, "none") {
        emit(out, "flex-grow", "0")
        emit(out, "flex-shrink", "0")
        emit(out, "flex-basis", "auto")
        ret
    }
    if str.eq(v, "auto") {
        emit(out, "flex-grow", "1")
        emit(out, "flex-shrink", "1")
        emit(out, "flex-basis", "auto")
        ret
    }
    if str.eq(v, "initial") {
        emit(out, "flex-grow", "0")
        emit(out, "flex-shrink", "1")
        emit(out, "flex-basis", "auto")
        ret
    }
    let toks = cv.split_top_level_spaces(a, v)
    if toks.len == 0usize || toks.len > 3usize { ret }
    var numbers: [2]str = zero
    var count = 0usize
    var basis = ""
    var i = 0usize
    while i < toks.len {
        if is_plain_number(toks[i]) && count < 2usize && !(count == 1usize && i == toks.len - 1usize && basis.len == 0usize && toks.len == 3usize && false) {
            // A number after the basis ends the number pair; a third plain number would be the basis `0`.
            if basis.len > 0usize && count == 0usize { numbers[count] = toks[i] } else { numbers[count] = toks[i] }
            count += 1usize
        } else {
            if basis.len > 0usize { ret }
            basis = toks[i]
        }
        i += 1usize
    }
    // `flex: 1 1 0` -- the last plain number is the basis when two numbers precede it and nothing else gave one.
    if basis.len == 0usize && toks.len == 3usize { ret }
    if count == 0usize { numbers[0usize] = "1" }
    if count <= 1usize { numbers[1usize] = "1" }
    if basis.len == 0usize { basis = "0%" }
    emit(out, "flex-grow", numbers[0usize])
    emit(out, "flex-shrink", numbers[1usize])
    emit(out, "flex-basis", basis)
}

// --- background

fn is_repeat_kw(t: str) -> bool { ret nm(",repeat,repeat-x,repeat-y,no-repeat,space,round,", t) }

fn is_attach_kw(t: str) -> bool { ret nm(",scroll,fixed,local,", t) }

fn is_box_kw(t: str) -> bool { ret nm(",border-box,padding-box,content-box,text,", t) }

fn is_position_kw(t: str) -> bool { ret nm(",left,right,top,bottom,center,", t) }

fn is_image(t: str) -> bool {
    ret str.eq(t, "none") || str.starts_with(t, "url(") || str.starts_with(t, "linear-gradient(") || str.starts_with(t, "radial-gradient(") || str.starts_with(t, "conic-gradient(") || str.starts_with(t, "repeating-linear-gradient(") || str.starts_with(t, "repeating-radial-gradient(") || str.starts_with(t, "repeating-conic-gradient(") || str.starts_with(t, "image-set(") || str.starts_with(t, "-webkit-image-set(") || str.starts_with(t, "image(") || str.starts_with(t, "cross-fade(") || str.starts_with(t, "element(")
}

// One layer's parts, each "" when absent.
type Layer = struct { image: str, position: str, size: str, repeat: str, attachment: str, origin: str, clip: str, color: str, good: bool }

fn parse_layer(a: *mem.Arena, text: str) -> Layer {
    let toks = cv.split_top_level_spaces(a, cv.trim_ws(text))
    var l = Layer { image: "", position: "", size: "", repeat: "", attachment: "", origin: "", clip: "", color: "", good: true }
    var in_size = false
    var i = 0usize
    while i < toks.len {
        let raw = toks[i]
        let t = lc(a, raw)
        i += 1usize
        if str.eq(t, "/") {
            in_size = true
            continue
        }
        if in_size && (looks_numeric(t) || str.eq(t, "auto") || str.eq(t, "cover") || str.eq(t, "contain") || str.ends_with(t, "%")) {
            if l.size.len == 0usize { l.size = t } else { l.size = join2(a, join2(a, l.size, " "), t) }
            continue
        }
        in_size = false
        if is_image(t) {
            l.image = raw
        } else if is_repeat_kw(t) {
            if l.repeat.len == 0usize { l.repeat = t } else { l.repeat = join2(a, join2(a, l.repeat, " "), t) }
        } else if is_attach_kw(t) {
            l.attachment = t
        } else if is_box_kw(t) {
            if l.origin.len == 0usize && !str.eq(t, "text") { l.origin = t } else { l.clip = t }
        } else if is_position_kw(t) || looks_numeric(t) {
            if str.contains(t, "/") {
                let (sl, _) = str.find(t, "/")
                let before = t[..sl]
                let after = t[sl + 1usize..]
                if before.len > 0usize {
                    if l.position.len == 0usize { l.position = before } else { l.position = join2(a, join2(a, l.position, " "), before) }
                }
                in_size = true
                if after.len > 0usize { l.size = after }
            } else {
                if l.position.len == 0usize { l.position = t } else { l.position = join2(a, join2(a, l.position, " "), t) }
            }
        } else if str.eq(t, "auto") || str.eq(t, "cover") || str.eq(t, "contain") {
            l.size = t
        } else {
            if l.color.len > 0usize { l.good = false }
            l.color = raw
        }
    }
    if l.origin.len > 0usize && l.clip.len == 0usize { l.clip = l.origin }
    ret l
}

fn comma_join(a: *mem.Arena, parts: []const str) -> str {
    let (r, e) = str.join(a, parts, ", ")
    if e != ok { ret "" }
    ret r
}

fn expand_background(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let layers = cv.split_top_level_commas(a, value)
    if layers.len == 0usize { ret }
    let (made, e) = list.init[str](a, layers.len * 7usize + 1usize)
    if e != ok { ret }
    var parts = made
    var color = "transparent"
    var li = 0usize
    var images: [16]str = zero
    var positions: [16]str = zero
    var sizes: [16]str = zero
    var repeats: [16]str = zero
    var attachments: [16]str = zero
    var origins: [16]str = zero
    var clips: [16]str = zero
    if layers.len > 16usize { ret }
    while li < layers.len {
        let l = parse_layer(a, layers[li])
        if !l.good { ret }
        images[li] = l.image
        positions[li] = l.position
        sizes[li] = l.size
        repeats[li] = l.repeat
        attachments[li] = l.attachment
        origins[li] = l.origin
        clips[li] = l.clip
        if li == layers.len - 1usize && l.color.len > 0usize { color = l.color }
        li += 1usize
    }
    var k = 0usize
    while k < 7usize {
        var src = images[0..]
        var prop = "background-image"
        var initial = "none"
        if k == 1usize {
            src = positions[0..]
            prop = "background-position"
            initial = "0% 0%"
        }
        if k == 2usize {
            src = sizes[0..]
            prop = "background-size"
            initial = "auto"
        }
        if k == 3usize {
            src = repeats[0..]
            prop = "background-repeat"
            initial = "repeat"
        }
        if k == 4usize {
            src = attachments[0..]
            prop = "background-attachment"
            initial = "scroll"
        }
        if k == 5usize {
            src = origins[0..]
            prop = "background-origin"
            initial = "padding-box"
        }
        if k == 6usize {
            src = clips[0..]
            prop = "background-clip"
            initial = "border-box"
        }
        let (items, items_error) = list.init[str](a, layers.len + 1usize)
        if items_error == ok {
            var column = items
            var n = 0usize
            while n < layers.len {
                if src[n].len == 0usize { let pushed = list.push[str](&column, initial) } else { let pushed = list.push[str](&column, src[n]) }
                n += 1usize
            }
            emit(out, prop, comma_join(a, list.slice_const[str](&column)))
        }
        k += 1usize
    }
    emit(out, "background-color", color)
}

// --- the rest of the shorthands

fn expand_list_style(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let toks = cv.split_top_level_spaces(a, value)
    var kind = ""
    var position = ""
    var image = ""
    var nones = 0usize
    var i = 0usize
    while i < toks.len {
        let t = lc(a, toks[i])
        i += 1usize
        if str.eq(t, "inside") || str.eq(t, "outside") {
            position = t
        } else if str.eq(t, "none") {
            nones += 1usize
        } else if str.starts_with(t, "url(") || str.starts_with(t, "linear-gradient(") || str.starts_with(t, "radial-gradient(") {
            image = toks[i - 1usize]
        } else {
            kind = toks[i - 1usize]
        }
    }
    if nones > 2usize { ret }
    if nones >= 1usize && kind.len == 0usize { kind = "none" }
    if nones == 2usize && image.len == 0usize { image = "none" }
    if kind.len == 0usize { kind = "disc" }
    if position.len == 0usize { position = "outside" }
    if image.len == 0usize { image = "none" }
    emit(out, "list-style-type", kind)
    emit(out, "list-style-position", position)
    emit(out, "list-style-image", image)
}

fn expand_text_decoration(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let toks = cv.split_top_level_spaces(a, value)
    var lines = ""
    var style = "solid"
    var color = "currentcolor"
    var thickness = "auto"
    var i = 0usize
    while i < toks.len {
        let t = lc(a, toks[i])
        i += 1usize
        if nm(",underline,overline,line-through,blink,none,", t) {
            if lines.len == 0usize { lines = t } else { lines = join2(a, join2(a, lines, " "), t) }
        } else if nm(",solid,double,dotted,dashed,wavy,", t) {
            style = t
        } else if str.eq(t, "auto") || str.eq(t, "from-font") || looks_numeric(t) {
            thickness = t
        } else {
            color = toks[i - 1usize]
        }
    }
    if lines.len == 0usize { lines = "none" }
    emit(out, "text-decoration-line", lines)
    emit(out, "text-decoration-style", style)
    emit(out, "text-decoration-color", color)
    emit(out, "text-decoration-thickness", thickness)
}

fn expand_outline(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let toks = cv.split_top_level_spaces(a, value)
    var width = ""
    var style = ""
    var color = ""
    var i = 0usize
    while i < toks.len {
        let t = lc(a, toks[i])
        i += 1usize
        if is_style_kw(t) || str.eq(t, "auto") {
            if style.len > 0usize { ret }
            style = t
        } else if is_width_kw(t) || looks_numeric(t) {
            if width.len > 0usize { ret }
            width = t
        } else {
            if color.len > 0usize { ret }
            color = toks[i - 1usize]
        }
    }
    if width.len == 0usize { width = "medium" }
    if style.len == 0usize { style = "none" }
    if color.len == 0usize { color = "currentcolor" }
    emit(out, "outline-width", width)
    emit(out, "outline-style", style)
    emit(out, "outline-color", color)
}

fn expand_columns(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let toks = cv.split_top_level_spaces(a, value)
    if toks.len == 0usize || toks.len > 2usize { ret }
    var width = "auto"
    var count = "auto"
    var i = 0usize
    while i < toks.len {
        let t = lc(a, toks[i])
        i += 1usize
        if str.eq(t, "auto") { continue }
        if is_plain_number(t) { count = t } else { width = t }
    }
    emit(out, "column-width", width)
    emit(out, "column-count", count)
}

fn expand_overflow(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let toks = cv.split_top_level_spaces(a, value)
    if toks.len == 0usize || toks.len > 2usize { ret }
    emit(out, "overflow-x", toks[0usize])
    if toks.len == 2usize { emit(out, "overflow-y", toks[1usize]) } else { emit(out, "overflow-y", toks[0usize]) }
}

// --- grid-template and grid.

// The top-level "/" split: (before, after, whether there was a slash), quotes and brackets respected.
fn split_grid_slash(s: str) -> (str, str, bool) {
    var depth = 0i64
    var quote = 0u8
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if quote != 0u8 {
            if c == quote { quote = 0u8 }
        } else if c == 34u8 || c == 39u8 {
            quote = c
        } else if c == 40u8 || c == 91u8 {
            depth += 1i64
        } else if c == 41u8 || c == 93u8 {
            if depth > 0i64 { depth -= 1i64 }
        } else if c == 47u8 && depth == 0i64 {
            ret (cv.trim_ws(s[0usize..i]), cv.trim_ws(s[i + 1usize..]), true)
        }
        i += 1usize
    }
    ret (cv.trim_ws(s), "", false)
}

fn has_quote(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] == 34u8 || s[i] == 39u8 { ret true }
        i += 1usize
    }
    ret false
}

// grid-template: none | <rows> / <columns> | the areas form ("a b" 100px "c d" auto / 1fr 1fr).
fn expand_grid_template(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let low = lc(a, value)
    if str.eq(low, "none") {
        emit(out, "grid-template-rows", "none")
        emit(out, "grid-template-columns", "none")
        emit(out, "grid-template-areas", "none")
        ret
    }
    let (left, right, has_slash) = split_grid_slash(value)
    if !has_quote(left) {
        if !has_slash { ret }
        emit(out, "grid-template-rows", left)
        emit(out, "grid-template-columns", right)
        emit(out, "grid-template-areas", "none")
        ret
    }
    // Areas form: each string is a row, followed by an optional track size; line names may sit around them.
    var areas = ""
    var rows = ""
    var i = 0usize
    var pending_names = ""
    var have_size = false
    var row_size = "auto"
    var first = true
    while i < left.len {
        let c = left[i]
        if c == 32u8 || c == 9u8 || c == 10u8 {
            i += 1usize
        } else if c == 34u8 || c == 39u8 {
            // Close the previous row.
            if !first {
                rows = join2(a, join2(a, rows, " "), row_size)
            }
            var e = i + 1usize
            while e < left.len && left[e] != c { e += 1usize }
            let text = left[i..e + 1usize]
            if areas.len > 0usize { areas = join2(a, areas, " ") }
            areas = join2(a, areas, text)
            if pending_names.len > 0usize { rows = join2(a, join2(a, rows, " "), pending_names) }
            pending_names = ""
            row_size = "auto"
            first = false
            i = e + 1usize
        } else if c == 91u8 {
            var e2 = i
            while e2 < left.len && left[e2] != 93u8 { e2 += 1usize }
            let names = left[i..e2 + 1usize]
            if first { pending_names = names } else { row_size = join2(a, join2(a, row_size, " "), names) }
            i = e2 + 1usize
        } else {
            var e3 = i
            var depth = 0i64
            while e3 < left.len && !(depth == 0i64 && (left[e3] == 32u8 || left[e3] == 9u8 || left[e3] == 10u8)) {
                if left[e3] == 40u8 { depth += 1i64 }
                if left[e3] == 41u8 { depth -= 1i64 }
                e3 += 1usize
            }
            row_size = left[i..e3]
            have_size = true
            i = e3
        }
    }
    if !first { rows = join2(a, join2(a, rows, " "), row_size) }
    emit(out, "grid-template-areas", areas)
    emit(out, "grid-template-rows", cv.trim_ws(rows))
    if has_slash { emit(out, "grid-template-columns", right) } else { emit(out, "grid-template-columns", "none") }
}

// grid: a grid-template, or one axis explicit and the other auto-flow with its auto track size.
fn expand_grid(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let low = lc(a, value)
    if !str.contains(low, "auto-flow") {
        expand_grid_template(a, value, out)
        emit(out, "grid-auto-flow", "row")
        emit(out, "grid-auto-rows", "auto")
        emit(out, "grid-auto-columns", "auto")
        ret
    }
    let (left, right, has_slash) = split_grid_slash(value)
    if !has_slash { ret }
    let llow = lc(a, left)
    if str.starts_with(llow, "auto-flow") || str.contains(llow, "auto-flow") {
        // auto-flow [dense] <auto-rows>? / <template-columns>
        var rest = cv.trim_ws(replace_word(a, replace_word(a, llow, "auto-flow", ""), "dense", ""))
        var flow = "row"
        if str.contains(llow, "dense") { flow = "row dense" }
        if rest.len == 0usize { rest = "auto" }
        emit(out, "grid-template-rows", "none")
        emit(out, "grid-template-areas", "none")
        emit(out, "grid-template-columns", right)
        emit(out, "grid-auto-flow", flow)
        emit(out, "grid-auto-rows", rest)
        emit(out, "grid-auto-columns", "auto")
    } else {
        // <template-rows> / auto-flow [dense] <auto-columns>?
        let rlow = lc(a, right)
        var rest2 = cv.trim_ws(replace_word(a, replace_word(a, rlow, "auto-flow", ""), "dense", ""))
        var flow2 = "column"
        if str.contains(rlow, "dense") { flow2 = "column dense" }
        if rest2.len == 0usize { rest2 = "auto" }
        emit(out, "grid-template-rows", left)
        emit(out, "grid-template-areas", "none")
        emit(out, "grid-template-columns", "none")
        emit(out, "grid-auto-flow", flow2)
        emit(out, "grid-auto-columns", rest2)
        emit(out, "grid-auto-rows", "auto")
    }
}

fn replace_word(a: *mem.Arena, s: str, word: str, with: str) -> str {
    let (at, found) = str.find(s, word)
    if !found { ret s }
    let (h1, e1) = str.concat(a, s[0usize..at], with)
    if e1 != ok { ret s }
    let (h2, e2) = str.concat(a, h1, s[at + word.len..])
    if e2 != ok { ret s }
    ret h2
}

fn expand_flex_flow(a: *mem.Arena, value: str, out: *list.List[Pair]) {
    let toks = cv.split_top_level_spaces(a, value)
    if toks.len == 0usize || toks.len > 2usize { ret }
    var direction = "row"
    var wrap = "nowrap"
    var i = 0usize
    while i < toks.len {
        let t = lc(a, toks[i])
        i += 1usize
        if nm(",row,row-reverse,column,column-reverse,", t) { direction = t } else {
            if nm(",nowrap,wrap,wrap-reverse,", t) { wrap = t } else { ret }
        }
    }
    emit(out, "flex-direction", direction)
    emit(out, "flex-wrap", wrap)
}

fn expand_place(a: *mem.Arena, value: str, first: str, second: str, out: *list.List[Pair]) {
    expand_pair(a, value, first, second, out)
}

// The physical side `start` / `end` of the inline axis in this direction.
fn inline_start(rtl: bool) -> str {
    if rtl { ret "right" }
    ret "left"
}

fn inline_end(rtl: bool) -> str {
    if rtl { ret "left" }
    ret "right"
}

// Expands `property`; true when it is a shorthand or a logical property.
fn expand(a: *mem.Arena, property: str, value: str, rtl: bool, out: *list.List[Pair]) -> bool {
    let v = cv.trim_ws(value)
    let low = lc(a, v)
    let istart = inline_start(rtl)
    let iend = inline_end(rtl)
    if !is_shorthand(property) { ret false }
    if is_wide_keyword(low) {
        // The same longhands with the keyword, found by expanding a harmless value.
        let (made, e) = list.init[Pair](a, 8usize)
        if e != ok { ret true }
        var probe = made
        let sample = sample_value(property)
        let handled = expand_value(a, property, sample, rtl, &probe)
        var i = 0usize
        while i < probe.len {
            emit(out, probe.items[i].property, low)
            i += 1usize
        }
        ret true
    }
    let handled = expand_value(a, property, v, rtl, out)
    ret handled
}

fn is_shorthand(p: str) -> bool {
    ret nm(",grid-template,grid,margin,padding,inset,margin-block,margin-inline,padding-block,padding-inline,inset-block,inset-inline,margin-block-start,margin-block-end,margin-inline-start,margin-inline-end,padding-block-start,padding-block-end,padding-inline-start,padding-inline-end,inset-block-start,inset-block-end,inset-inline-start,inset-inline-end,border,border-top,border-right,border-bottom,border-left,border-width,border-style,border-color,border-block,border-inline,border-block-start,border-block-end,border-inline-start,border-inline-end,border-block-width,border-block-style,border-block-color,border-inline-width,border-inline-style,border-inline-color,border-block-start-width,border-block-end-width,border-inline-start-width,border-inline-end-width,border-block-start-style,border-block-end-style,border-inline-start-style,border-inline-end-style,border-block-start-color,border-block-end-color,border-inline-start-color,border-inline-end-color,border-radius,font,flex,flex-flow,gap,grid-gap,place-items,place-content,place-self,overflow,list-style,text-decoration,outline,columns,background,block-size,inline-size,min-block-size,min-inline-size,max-block-size,max-inline-size,", p)
}

// A value each shorthand accepts, used only to learn its longhand names.
fn sample_value(p: str) -> str {
    if str.eq(p, "grid-template") || str.eq(p, "grid") { ret "none" }
    if str.eq(p, "font") { ret "1px a" }
    if str.eq(p, "flex") { ret "none" }
    if str.eq(p, "flex-flow") { ret "row" }
    if str.eq(p, "list-style") { ret "none" }
    if str.eq(p, "background") { ret "none" }
    if str.eq(p, "columns") { ret "auto" }
    ret "0"
}

// The physical property a single-valued logical property stands for ("" when `p` is not one).
fn logical_target(a: *mem.Arena, p: str, rtl: bool) -> str {
    let istart = inline_start(rtl)
    let iend = inline_end(rtl)
    if str.eq(p, "margin-block-start") { ret "margin-top" }
    if str.eq(p, "margin-block-end") { ret "margin-bottom" }
    if str.eq(p, "margin-inline-start") { ret dash(a, "margin", istart) }
    if str.eq(p, "margin-inline-end") { ret dash(a, "margin", iend) }
    if str.eq(p, "padding-block-start") { ret "padding-top" }
    if str.eq(p, "padding-block-end") { ret "padding-bottom" }
    if str.eq(p, "padding-inline-start") { ret dash(a, "padding", istart) }
    if str.eq(p, "padding-inline-end") { ret dash(a, "padding", iend) }
    if str.eq(p, "inset-block-start") { ret "top" }
    if str.eq(p, "inset-block-end") { ret "bottom" }
    if str.eq(p, "inset-inline-start") { ret istart }
    if str.eq(p, "inset-inline-end") { ret iend }
    if str.eq(p, "block-size") { ret "height" }
    if str.eq(p, "inline-size") { ret "width" }
    if str.eq(p, "min-block-size") { ret "min-height" }
    if str.eq(p, "min-inline-size") { ret "min-width" }
    if str.eq(p, "max-block-size") { ret "max-height" }
    if str.eq(p, "max-inline-size") { ret "max-width" }
    ret ""
}

fn expand_value(a: *mem.Arena, p: str, v: str, rtl: bool, out: *list.List[Pair]) -> bool {
    let istart = inline_start(rtl)
    let iend = inline_end(rtl)
    let single = logical_target(a, p, rtl)
    if single.len > 0usize {
        emit(out, single, v)
        ret true
    }
    if str.eq(p, "grid-template") {
        expand_grid_template(a, v, out)
        ret true
    }
    if str.eq(p, "grid") {
        expand_grid(a, v, out)
        ret true
    }
    if str.eq(p, "margin") {
        expand_four(a, v, "margin", "", out)
        ret true
    }
    if str.eq(p, "padding") {
        expand_four(a, v, "padding", "", out)
        ret true
    }
    if str.eq(p, "inset") {
        let f = box4(cv.split_top_level_spaces(a, v))
        if f.good {
            emit(out, "top", f.top)
            emit(out, "right", f.right)
            emit(out, "bottom", f.bottom)
            emit(out, "left", f.left)
        }
        ret true
    }
    if str.eq(p, "margin-block") {
        expand_pair(a, v, "margin-top", "margin-bottom", out)
        ret true
    }
    if str.eq(p, "margin-inline") {
        expand_pair(a, v, dash(a, "margin", istart), dash(a, "margin", iend), out)
        ret true
    }
    if str.eq(p, "padding-block") {
        expand_pair(a, v, "padding-top", "padding-bottom", out)
        ret true
    }
    if str.eq(p, "padding-inline") {
        expand_pair(a, v, dash(a, "padding", istart), dash(a, "padding", iend), out)
        ret true
    }
    if str.eq(p, "inset-block") {
        expand_pair(a, v, "top", "bottom", out)
        ret true
    }
    if str.eq(p, "inset-inline") {
        expand_pair(a, v, istart, iend, out)
        ret true
    }
    if str.eq(p, "border") {
        expand_border_all(a, v, out)
        ret true
    }
    if str.eq(p, "border-top") {
        expand_edge(a, v, "top", out)
        ret true
    }
    if str.eq(p, "border-right") {
        expand_edge(a, v, "right", out)
        ret true
    }
    if str.eq(p, "border-bottom") {
        expand_edge(a, v, "bottom", out)
        ret true
    }
    if str.eq(p, "border-left") {
        expand_edge(a, v, "left", out)
        ret true
    }
    if str.eq(p, "border-block-start") {
        expand_edge(a, v, "top", out)
        ret true
    }
    if str.eq(p, "border-block-end") {
        expand_edge(a, v, "bottom", out)
        ret true
    }
    if str.eq(p, "border-inline-start") {
        expand_edge(a, v, istart, out)
        ret true
    }
    if str.eq(p, "border-inline-end") {
        expand_edge(a, v, iend, out)
        ret true
    }
    if str.eq(p, "border-block") {
        expand_edge(a, v, "top", out)
        expand_edge(a, v, "bottom", out)
        ret true
    }
    if str.eq(p, "border-inline") {
        expand_edge(a, v, istart, out)
        expand_edge(a, v, iend, out)
        ret true
    }
    if str.eq(p, "border-width") {
        expand_four(a, v, "border", "width", out)
        ret true
    }
    if str.eq(p, "border-style") {
        expand_four(a, v, "border", "style", out)
        ret true
    }
    if str.eq(p, "border-color") {
        expand_four(a, v, "border", "color", out)
        ret true
    }
    if str.eq(p, "border-block-width") {
        expand_pair(a, v, "border-top-width", "border-bottom-width", out)
        ret true
    }
    if str.eq(p, "border-block-style") {
        expand_pair(a, v, "border-top-style", "border-bottom-style", out)
        ret true
    }
    if str.eq(p, "border-block-color") {
        expand_pair(a, v, "border-top-color", "border-bottom-color", out)
        ret true
    }
    if str.eq(p, "border-inline-width") {
        expand_pair(a, v, dash3(a, "border", istart, "width"), dash3(a, "border", iend, "width"), out)
        ret true
    }
    if str.eq(p, "border-inline-style") {
        expand_pair(a, v, dash3(a, "border", istart, "style"), dash3(a, "border", iend, "style"), out)
        ret true
    }
    if str.eq(p, "border-inline-color") {
        expand_pair(a, v, dash3(a, "border", istart, "color"), dash3(a, "border", iend, "color"), out)
        ret true
    }
    if str.eq(p, "border-radius") {
        expand_radius(a, v, out)
        ret true
    }
    if str.eq(p, "font") {
        expand_font(a, v, out)
        ret true
    }
    if str.eq(p, "flex") {
        expand_flex(a, v, out)
        ret true
    }
    if str.eq(p, "flex-flow") {
        expand_flex_flow(a, v, out)
        ret true
    }
    if str.eq(p, "gap") || str.eq(p, "grid-gap") {
        expand_pair(a, v, "row-gap", "column-gap", out)
        ret true
    }
    if str.eq(p, "place-items") {
        expand_place(a, v, "align-items", "justify-items", out)
        ret true
    }
    if str.eq(p, "place-content") {
        expand_place(a, v, "align-content", "justify-content", out)
        ret true
    }
    if str.eq(p, "place-self") {
        expand_place(a, v, "align-self", "justify-self", out)
        ret true
    }
    if str.eq(p, "overflow") {
        expand_overflow(a, v, out)
        ret true
    }
    if str.eq(p, "list-style") {
        expand_list_style(a, v, out)
        ret true
    }
    if str.eq(p, "text-decoration") {
        expand_text_decoration(a, v, out)
        ret true
    }
    if str.eq(p, "outline") {
        expand_outline(a, v, out)
        ret true
    }
    if str.eq(p, "columns") {
        expand_columns(a, v, out)
        ret true
    }
    if str.eq(p, "background") {
        expand_background(a, v, out)
        ret true
    }
    ret false
}
