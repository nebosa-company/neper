// A set of font faces with CSS-style matching (tracker 3.16): families by name, generic family mapping (`serif`,
// `sans-serif`, `monospace`, ...), weight and italic closeness, a fallback chain of every other face for characters
// the chosen face lacks, and the two measurements a layout engine asks for -- the advance width of a string and the
// vertical metrics of a face at a size -- plus `layout_run`, a single-line `e.text.layout` for drawing.
//
// The caller hands over the font bytes (a face is `shape.Font`, validated on `add`); nothing is read from disk or
// discovered. Matching follows CSS Fonts 4 in its common case: the first family in the list that has any face wins,
// within it a face of the requested style (italic or not) beats one of the other, then the nearest weight (heavier
// preferred above 400 and when the request is above 500, lighter below).
//
// Memory: the set keeps its faces in the arena it was made with; `width` and `metrics` allocate nothing that
// survives the call (they mark and reset the arena); `layout_run` allocates its result in the arena it is given.

use e.data.list as list
use e.gfx.cssvalue as cv
use e.mem
use e.str
use e.text.layout as tl
use e.text.shape as shape

type Face = struct {
    family: str, weight: u32, italic: bool, font: shape.Font,
    ascent: f64, descent: f64, line_gap: f64, x_height: f64
}

type Generics = struct { serif: str, sans: str, mono: str, cursive: str, fantasy: str, ui: str }

type Set = struct { a: *mem.Arena, faces: list.List[Face], generics: Generics }

type Metrics = struct { ascent: f64, descent: f64, line_gap: f64, x_height: f64 }

error NoFace

const TAG_HEAD: u32 = 1751474532u32
const TAG_HHEA: u32 = 1751672161u32
const TAG_OS2: u32 = 1330851634u32

fn new(a: *mem.Arena) -> (Set, err) {
    let (faces, e) = list.init[Face](a, 8usize)
    if e != ok { ret (zero, e) }
    ret (Set { a: a, faces: faces, generics: Generics { serif: "", sans: "", mono: "", cursive: "", fantasy: "", ui: "" } }, ok)
}

// Registers a face. Metrics come from `hhea` (and `OS/2` for the x-height) in em units.
fn add(s: *Set, family: str, weight: u32, italic: bool, data: []const u8, face_index: u32) -> err {
    let font = shape.Font { id: u32(s.faces.len), data: data, face_index: face_index }
    let valid = shape.validate_font(font)
    if valid != ok { ret valid }
    let (head, has_head) = shape.find_table(font, TAG_HEAD)
    let (hhea, has_hhea) = shape.find_table(font, TAG_HHEA)
    if !has_head || !has_hhea { ret shape.Unsupported }
    let em = f64(shape.u16_at(data, head.at + 18usize))
    var ascent = 0.8f64
    var descent = 0.2f64
    var gap = 0.0f64
    var xh = 0.5f64
    if em > 0.0f64 {
        ascent = f64(shape.i16_at(data, hhea.at + 4usize)) / em
        descent = -f64(shape.i16_at(data, hhea.at + 6usize)) / em
        gap = f64(shape.i16_at(data, hhea.at + 8usize)) / em
        let (os2, has_os2) = shape.find_table(font, TAG_OS2)
        if has_os2 && os2.len >= 90usize && shape.u16_at(data, os2.at) >= 2u32 {
            let x = f64(shape.i16_at(data, os2.at + 86usize)) / em
            if x > 0.0f64 { xh = x }
        }
    }
    if descent < 0.0f64 { descent = 0.0f64 }
    let low = cv.lower(s.a, cv.trim_ws(family))
    let pushed = list.push[Face](&s.faces, Face { family: low, weight: weight, italic: italic, font: font, ascent: ascent, descent: descent, line_gap: gap, x_height: xh })
    ret pushed
}

// `generic` is `serif`, `sans-serif`, `monospace`, `cursive`, `fantasy` or `system-ui`; `family` the face family it names.
fn set_generic(s: *Set, generic: str, family: str) {
    let low = cv.lower(s.a, cv.trim_ws(family))
    if str.eq(generic, "serif") { s.generics.serif = low } else if str.eq(generic, "sans-serif") { s.generics.sans = low } else if str.eq(generic, "monospace") { s.generics.mono = low } else if str.eq(generic, "cursive") { s.generics.cursive = low } else if str.eq(generic, "fantasy") { s.generics.fantasy = low } else if str.eq(generic, "system-ui") { s.generics.ui = low }
}

fn unquote(a: *mem.Arena, name: str) -> str {
    var t = cv.trim_ws(name)
    if t.len >= 2usize && (t[0usize] == 34u8 || t[0usize] == 39u8) && t[t.len - 1usize] == t[0usize] { t = cv.trim_ws(t[1usize..t.len - 1usize]) }
    ret cv.lower(a, t)
}

fn generic_family(s: *const Set, name: str) -> str {
    if str.eq(name, "serif") { ret s.generics.serif }
    if str.eq(name, "sans-serif") { ret s.generics.sans }
    if str.eq(name, "monospace") || str.eq(name, "ui-monospace") { ret s.generics.mono }
    if str.eq(name, "cursive") { ret s.generics.cursive }
    if str.eq(name, "fantasy") { ret s.generics.fantasy }
    if str.eq(name, "system-ui") || str.eq(name, "ui-sans-serif") || str.eq(name, "-apple-system") || str.eq(name, "blinkmacsystemfont") { ret s.generics.ui }
    ret ""
}

// The best face of `family` (lower case) for a weight and slant, or the face count when it has none.
fn best_of(s: *const Set, family: str, weight: f64, italic: bool) -> usize {
    var best = s.faces.len
    var score = 1000000.0f64
    var i = 0usize
    while i < s.faces.len {
        let f = &s.faces.items[i]
        if str.eq(f.family, family) {
            var penalty = 0.0f64
            if f.italic != italic { penalty += 10000.0f64 }
            let wf = f64(f.weight)
            if weight >= 400.0f64 && weight <= 500.0f64 {
                // Between 400 and 500: try up to 500 first, then below, then above.
                if wf >= weight && wf <= 500.0f64 { penalty += wf - weight } else if wf < weight { penalty += 100.0f64 + (weight - wf) } else { penalty += 1000.0f64 + (wf - weight) }
            } else if weight < 400.0f64 {
                if wf <= weight { penalty += weight - wf } else { penalty += 1000.0f64 + (wf - weight) }
            } else {
                if wf >= weight { penalty += wf - weight } else { penalty += 1000.0f64 + (weight - wf) }
            }
            if penalty < score {
                score = penalty
                best = i
            }
        }
        i += 1usize
    }
    ret best
}

// The face a CSS `font-family` list picks for a weight and slant (the first registered face when none of the families
// exists; `NoFace` when the set is empty).
fn pick(s: *Set, families: str, weight: f64, italic: bool) -> (usize, err) {
    if s.faces.len == 0usize { ret (0usize, NoFace) }
    let mark = mem.mark(s.a)
    let names = cv.split_top_level_commas(s.a, families)
    var i = 0usize
    var found = s.faces.len
    while i < names.len && found >= s.faces.len {
        var name = unquote(s.a, names[i])
        let generic = generic_family(s, name)
        if generic.len > 0usize { name = generic }
        found = best_of(s, name, weight, italic)
        i += 1usize
    }
    mem.reset(s.a, mark)
    if found >= s.faces.len { found = 0usize }
    ret (found, ok)
}

fn metrics(s: *Set, families: str, weight: f64, italic: bool, size: f64) -> Metrics {
    let (idx, e) = pick(s, families, weight, italic)
    if e != ok { ret Metrics { ascent: 0.8f64 * size, descent: 0.2f64 * size, line_gap: 0.0f64, x_height: 0.5f64 * size } }
    let f = &s.faces.items[idx]
    ret Metrics { ascent: f.ascent * size, descent: f.descent * size, line_gap: f.line_gap * size, x_height: f.x_height * size }
}

// The fonts of a layout: the chosen face first, then every other face for characters it lacks.
fn choices(s: *Set, a: *mem.Arena, primary: usize, size: f64) -> ([]tl.FontChoice, err) {
    let (out, e) = mem.alloc[tl.FontChoice](a, s.faces.len)
    if e != ok { ret (zero, e) }
    out[0usize] = tl.FontChoice { font: s.faces.items[primary].font, size: f32(size) }
    var n = 1usize
    var i = 0usize
    while i < s.faces.len {
        if i != primary {
            out[n] = tl.FontChoice { font: s.faces.items[i].font, size: f32(size) }
            n += 1usize
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

fn opts(limit: f32) -> tl.Options {
    ret tl.Options { width: limit, max_lines: 0u32, align: .Start, wrap: .None, ellipsis: "", notdef: true }
}

// The advance width of `text` on one line.
fn width(s: *Set, families: str, weight: f64, italic: bool, size: f64, text: str) -> f64 {
    if text.len == 0usize { ret 0.0f64 }
    let (idx, e) = pick(s, families, weight, italic)
    if e != ok { ret 0.0f64 }
    let mark = mem.mark(s.a)
    var total = 0.0f64
    let (run, shape_error) = shape.shape(s.a, s.faces.items[idx].font, text, shape.Options { direction: .LeftToRight, script: 0u32, language: "", features: zero, ppem: 0u32 })
    var missing = shape_error != ok
    if !missing {
        var g = 0usize
        while g < run.glyphs.len {
            if run.glyphs[g].id == 0u32 { missing = true }
            total += f64(run.glyphs[g].advance_x)
            g += 1usize
        }
    }
    if missing {
        // Some character is not in the chosen face: lay the text out through the fallback chain.
        let (fonts, fe) = choices(s, s.a, idx, size)
        total = 0.0f64
        if fe == ok {
            let (lay, le) = tl.layout(s.a, text, tl.Style { fonts: fonts, language: "", line_height: 0.0f32 }, opts(1000000000.0f32))
            if le == ok { total = f64(lay.bounds.width) / size }
        }
    }
    mem.reset(s.a, mark)
    ret total * size
}

// A single-line layout of `text` in the face the family list picks, for drawing; allocated in `a`.
fn layout_run(s: *Set, a: *mem.Arena, families: str, weight: f64, italic: bool, size: f64, text: str) -> (*const tl.Layout, err) {
    let (idx, pe) = pick(s, families, weight, italic)
    if pe != ok { ret (zero, pe) }
    let (fonts, fe) = choices(s, a, idx, size)
    if fe != ok { ret (zero, fe) }
    let (lay0, le0) = tl.layout(a, text, tl.Style { fonts: fonts, language: "", line_height: 0.0f32 }, opts(1000000000.0f32))
    if le0 != ok { ret (zero, le0) }
    var lay = lay0
    var le: err = ok
    // A right-to-left paragraph starts at the right edge of the limit: lay it out again against its own width, so its
    // origin is the left edge of the run like a left-to-right one.
    if lay0.lines.len > 0usize && lay0.lines[0usize].bounds.x > 1.0f32 {
        let (lay1, le1) = tl.layout(a, text, tl.Style { fonts: fonts, language: "", line_height: 0.0f32 }, opts(lay0.lines[0usize].bounds.width + 0.01f32))
        if le1 == ok { lay = lay1 } else { le = le1 }
    }
    if le != ok { ret (zero, le) }
    let (cell, ce) = mem.alloc[tl.Layout](a, 1usize)
    if ce != ok { ret (zero, ce) }
    cell[0usize] = lay
    ret (&cell[0usize], ok)
}
