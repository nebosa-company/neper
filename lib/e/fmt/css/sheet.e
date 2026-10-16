// Style sheet loading (tracker 1.13e), after Vaper's `css/native_parser.dart`: a sheet's text becomes the flat rule list the
// cascade ranks, with the at-rules resolved in document order and never aborting on malformed input.
//
//   * `@media` is evaluated once, against a `MediaEnv` (viewport, colour scheme, motion, contrast, pointer, resolution,
//     print): the media types `all`, `screen` and `print`, `not`/`only`/`and`/`or`, `(feature: value)` with `min-`/`max-`
//     prefixes and the range syntax (`width >= 600px`, `400px <= width < 900px`); a feature the engine does not know makes its
//     query false, as in the spec. Reload the sheet when the environment changes;
//   * `@supports` (`not`, `and`, `or`, `(property: value)`, `selector(...)`), `@layer` (statement and block, nested names
//     joined with a dot, registration order is priority order), `@container` (named, `and`/`or`/`not`, size features and the
//     range forms, `style()`/`scroll-state()` unknown), `@scope (start) to (limit)`, and rule nesting of these at-rules;
//   * `@font-face` is collected (family, the best loadable `src`, weight, style, unicode-range, display), `@keyframes` with its
//     stops sorted by offset, `@property` registrations and `@import` URLs (the caller fetches and loads them in order);
//     `@charset`, `@namespace`, `@page`, `@counter-style` and unknown at-rules contribute nothing.
//
// Not here: nested style rules (`& .x { }` inside a rule) -- a declaration block holds declarations only, as in Vaper.
//
// Memory: the arena is retained; every string and list lives in it.

use e.data.list as list
use e.fmt.css.cascade as cascade
use e.fmt.css.container as container
use e.fmt.css.selector as selector
use e.fmt.css.syntax as syntax
use e.gfx.cssvalue as cv
use e.mem
use e.str

// What `@media` is evaluated against.
type MediaEnv = struct { width: f64, height: f64, dark: bool, reduced_motion: bool, high_contrast: bool, print: bool, dppx: f64, hover: bool, fine_pointer: bool, scripting: bool }

fn media_env(width: f64, height: f64) -> MediaEnv {
    ret MediaEnv { width: width, height: height, dark: false, reduced_motion: false, high_contrast: false, print: false, dppx: 1.0f64, hover: true, fine_pointer: true, scripting: true }
}

type FontFace = struct { family: str, url: str, weight: str, style: str, unicode_range: str, display: str }
type Stop = struct { offset: f64, declarations: []const cascade.Declaration }
type Keyframes = struct { name: str, stops: []const Stop }
type PropertyRule = struct { name: str, syntax: str, inherits: bool, initial: str }

type Loaded = struct { rules: []const cascade.Rule, fonts: []const FontFace, keyframes: []const Keyframes, properties: []const PropertyRule, imports: []const str, layers: []const str, next_order: i64 }

// --- Text helpers.

fn lower_trim(a: *mem.Arena, s: str) -> str { ret cv.lower(a, cv.trim_ws(s)) }

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

// The index just past the `)` that closes the `(` at `open`; the length when unbalanced.
fn skip_group(s: str, open: usize) -> usize {
    var depth = 0i64
    var i = open
    while i < s.len {
        if s[i] == 40u8 { depth += 1i64 }
        if s[i] == 41u8 {
            depth -= 1i64
            if depth == 0i64 { ret i + 1usize }
        }
        i += 1usize
    }
    ret s.len
}

fn inner_of(group: str) -> str {
    if group.len >= 2usize && group[0usize] == 40u8 && group[group.len - 1usize] == 41u8 { ret cv.trim_ws(group[1usize..group.len - 1usize]) }
    ret group
}

fn strip_quotes(s: str) -> str {
    if s.len >= 2usize && ((s[0usize] == 34u8 && s[s.len - 1usize] == 34u8) || (s[0usize] == 39u8 && s[s.len - 1usize] == 39u8)) { ret s[1usize..s.len - 1usize] }
    ret s
}

fn px_of(env: *const MediaEnv, a: *mem.Arena, text: str) -> (f64, bool) {
    var b = cv.no_bases()
    b.has_em = true
    b.em = 16.0f64
    b.has_rem = true
    b.rem = 16.0f64
    b.has_viewport_width = true
    b.viewport_width = env.width
    b.has_viewport_height = true
    b.viewport_height = env.height
    let t = lower_trim(a, text)
    let (l, parsed) = cv.parse_length(a, t, b)
    if !parsed { ret (0.0f64, false) }
    let (px, ok_px) = cv.to_px(l, b)
    ret (px, ok_px)
}

fn near(x: f64, y: f64) -> bool {
    var d = x - y
    if d < 0.0f64 { d = -d }
    ret d < 0.5f64
}

fn number_of(a: *mem.Arena, s: str) -> (f64, bool) {
    let (n, parsed) = cv.try_parse(a, lower_trim(a, s))
    ret (n, parsed)
}

// A resolution in dppx: `2dppx`, `192dpi`, `2x`, `1.5` (the -webkit ratio).
fn resolution_of(a: *mem.Arena, s: str) -> (f64, bool) {
    let t = lower_trim(a, s)
    if str.ends_with(t, "dppx") {
        let (fv101, fg101) = number_of(a, t[..t.len - 4usize])
        ret (fv101, fg101)
    }
    if str.ends_with(t, "dpi") {
        let (n, good) = number_of(a, t[..t.len - 3usize])
        ret (n / 96.0f64, good)
    }
    if str.ends_with(t, "dpcm") {
        let (n, good) = number_of(a, t[..t.len - 4usize])
        ret (n / 37.795275591f64, good)
    }
    if str.ends_with(t, "x") {
        let (fv102, fg102) = number_of(a, t[..t.len - 1usize])
        ret (fv102, fg102)
    }
    let (fv1, fg1) = number_of(a, t)
    ret (fv1, fg1)
}

// --- @media

fn feature_colon(env: *const MediaEnv, a: *mem.Arena, name: str, value: str) -> bool {
    if str.eq(name, "orientation") {
        if str.eq(value, "portrait") { ret env.height >= env.width }
        if str.eq(value, "landscape") { ret env.width > env.height }
        ret false
    }
    if str.eq(name, "prefers-color-scheme") {
        if str.eq(value, "dark") { ret env.dark }
        if str.eq(value, "light") { ret !env.dark }
        ret false
    }
    if str.eq(name, "prefers-reduced-motion") {
        if str.eq(value, "reduce") { ret env.reduced_motion }
        if str.eq(value, "no-preference") { ret !env.reduced_motion }
        ret false
    }
    if str.eq(name, "prefers-contrast") {
        if str.eq(value, "more") || str.eq(value, "high") { ret env.high_contrast }
        if str.eq(value, "no-preference") { ret !env.high_contrast }
        ret false
    }
    if str.eq(name, "forced-colors") { ret str.eq(value, "none") }
    if str.eq(name, "prefers-reduced-transparency") { ret str.eq(value, "no-preference") }
    if str.eq(name, "hover") || str.eq(name, "any-hover") {
        if str.eq(value, "hover") { ret env.hover }
        if str.eq(value, "none") { ret !env.hover }
        ret false
    }
    if str.eq(name, "pointer") || str.eq(name, "any-pointer") {
        if str.eq(value, "fine") { ret env.fine_pointer }
        if str.eq(value, "coarse") { ret !env.fine_pointer }
        if str.eq(value, "none") { ret false }
        ret false
    }
    if str.eq(name, "scripting") {
        if str.eq(value, "enabled") { ret env.scripting }
        if str.eq(value, "none") { ret !env.scripting }
        ret false
    }
    if str.eq(name, "display-mode") { ret str.eq(value, "browser") }
    if str.eq(name, "update") { ret str.eq(value, "fast") }
    if str.eq(name, "color") || str.eq(name, "min-color") || str.eq(name, "max-color") {
        let (n, good) = number_of(a, value)
        if !good { ret false }
        if str.starts_with(name, "min-") { ret 8.0f64 >= n }
        if str.starts_with(name, "max-") { ret 8.0f64 <= n }
        ret near(8.0f64, n)
    }
    if str.eq(name, "monochrome") || str.eq(name, "min-monochrome") || str.eq(name, "max-monochrome") {
        let (n, good) = number_of(a, value)
        if !good { ret false }
        ret near(0.0f64, n) && !str.starts_with(name, "min-")
    }
    if str.eq(name, "resolution") || str.eq(name, "min-resolution") || str.eq(name, "max-resolution") || str.eq(name, "-webkit-device-pixel-ratio") || str.eq(name, "-webkit-min-device-pixel-ratio") || str.eq(name, "-webkit-max-device-pixel-ratio") {
        let (r, good) = resolution_of(a, value)
        if !good { ret false }
        if str.starts_with(name, "min-") || str.starts_with(name, "-webkit-min-") { ret env.dppx >= r }
        if str.starts_with(name, "max-") || str.starts_with(name, "-webkit-max-") { ret env.dppx <= r }
        ret near(env.dppx, r)
    }
    if str.eq(name, "aspect-ratio") || str.eq(name, "min-aspect-ratio") || str.eq(name, "max-aspect-ratio") {
        let ratio = ratio_of(a, value)
        if ratio <= 0.0f64 || env.height <= 0.0f64 { ret false }
        let actual = env.width / env.height
        if str.starts_with(name, "min-") { ret actual >= ratio }
        if str.starts_with(name, "max-") { ret actual <= ratio }
        ret near(actual * 1000.0f64, ratio * 1000.0f64)
    }
    // Width and height, with min- and max- prefixes.
    var base = name
    var mode = 0i32
    if str.starts_with(name, "min-") {
        base = name[4usize..]
        mode = 1i32
    }
    if str.starts_with(name, "max-") {
        base = name[4usize..]
        mode = 2i32
    }
    var actual = 0.0f64
    if str.eq(base, "width") || str.eq(base, "device-width") || str.eq(base, "inline-size") { actual = env.width } else {
        if str.eq(base, "height") || str.eq(base, "device-height") || str.eq(base, "block-size") { actual = env.height } else { ret false }
    }
    let (px, good) = px_of(env, a, value)
    if !good { ret false }
    if mode == 1i32 { ret actual >= px }
    if mode == 2i32 { ret actual <= px }
    ret near(actual, px)
}

// `a / b` or `a` to a ratio, 0 when unreadable.
fn ratio_of(a: *mem.Arena, s: str) -> f64 {
    let (slash, has) = str.find(s, "/")
    if !has {
        let (n, good) = number_of(a, s)
        if good { ret n }
        ret 0.0f64
    }
    let (x, gx) = number_of(a, s[..slash])
    let (y, gy) = number_of(a, s[slash + 1usize..])
    if !gx || !gy || y == 0.0f64 { ret 0.0f64 }
    ret x / y
}

fn is_cmp(t: str) -> bool { ret nm(",<,<=,>,>=,=,", t) }

// Space out the comparison operators of a range feature so they split as words.
fn spread_ops(a: *mem.Arena, s: str) -> str {
    let (made, e) = str.builder(a, s.len * 2usize + 8usize)
    if e != ok { ret s }
    var out = made
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 60u8 || c == 62u8 || c == 61u8 {
            let _p = str.push(&out, " ")
            let _q = str.push_byte(&out, c)
            if i + 1usize < s.len && s[i + 1usize] == 61u8 && c != 61u8 {
                let _r = str.push_byte(&out, 61u8)
                i += 1usize
            }
            let _s = str.push(&out, " ")
        } else {
            let _t = str.push_byte(&out, c)
        }
        i += 1usize
    }
    ret str.done(&out)
}

fn range_actual(env: *const MediaEnv, name: str) -> (f64, bool) {
    if str.eq(name, "width") || str.eq(name, "inline-size") || str.eq(name, "device-width") { ret (env.width, true) }
    if str.eq(name, "height") || str.eq(name, "block-size") || str.eq(name, "device-height") { ret (env.height, true) }
    if str.eq(name, "resolution") { ret (env.dppx, true) }
    if str.eq(name, "aspect-ratio") && env.height > 0.0f64 { ret (env.width / env.height, true) }
    ret (0.0f64, false)
}

fn range_value(env: *const MediaEnv, a: *mem.Arena, name: str, text: str) -> (f64, bool) {
    if str.eq(name, "resolution") {
        let (fv103, fg103) = resolution_of(a, text)
        ret (fv103, fg103)
    }
    if str.eq(name, "aspect-ratio") {
        let r = ratio_of(a, text)
        ret (r, r > 0.0f64)
    }
    let (fv2, fg2) = px_of(env, a, text)
    ret (fv2, fg2)
}

fn compare_op(op: str, x: f64, y: f64) -> bool {
    if str.eq(op, "<") { ret x < y }
    if str.eq(op, "<=") { ret x <= y }
    if str.eq(op, ">") { ret x > y }
    if str.eq(op, ">=") { ret x >= y }
    ret near(x, y)
}

fn flip_op(op: str) -> str {
    if str.eq(op, "<") { ret ">" }
    if str.eq(op, "<=") { ret ">=" }
    if str.eq(op, ">") { ret "<" }
    if str.eq(op, ">=") { ret "<=" }
    ret op
}

// `width >= 600px`, `600px <= width`, `400px <= width < 900px`.
fn feature_range(env: *const MediaEnv, a: *mem.Arena, text: str) -> bool {
    let toks = cv.split_top_level_spaces(a, spread_ops(a, text))
    if toks.len == 3usize {
        // name op value | value op name
        if is_cmp(toks[1usize]) {
            let (actual, known) = range_actual(env, toks[0usize])
            if known {
                let (v, good) = range_value(env, a, toks[0usize], toks[2usize])
                ret good && compare_op(toks[1usize], actual, v)
            }
            let (actual2, known2) = range_actual(env, toks[2usize])
            if known2 {
                let (v2, good2) = range_value(env, a, toks[2usize], toks[0usize])
                ret good2 && compare_op(flip_op(toks[1usize]), actual2, v2)
            }
        }
        ret false
    }
    if toks.len == 5usize && is_cmp(toks[1usize]) && is_cmp(toks[3usize]) {
        let (actual, known) = range_actual(env, toks[2usize])
        if !known { ret false }
        let (lo, g1) = range_value(env, a, toks[2usize], toks[0usize])
        let (hi, g2) = range_value(env, a, toks[2usize], toks[4usize])
        ret g1 && g2 && compare_op(flip_op(toks[1usize]), actual, lo) && compare_op(toks[3usize], actual, hi)
    }
    ret false
}

fn feature_true(env: *const MediaEnv, a: *mem.Arena, inner_text: str) -> bool {
    let t = lower_trim(a, inner_text)
    if t.len == 0usize { ret false }
    let (colon, has_colon) = str.find(t, ":")
    if has_colon { ret feature_colon(env, a, cv.trim_ws(t[..colon]), cv.trim_ws(t[colon + 1usize..])) }
    // Boolean context.
    if str.eq(t, "color") { ret true }
    if str.eq(t, "hover") || str.eq(t, "any-hover") { ret env.hover }
    if str.eq(t, "monochrome") { ret false }
    if str.eq(t, "width") || str.eq(t, "height") || str.eq(t, "resolution") { ret true }
    if str.eq(t, "scripting") { ret env.scripting }
    ret feature_range(env, a, t)
}

// `and` / `or` chains of parenthesised terms, each possibly negated or nested.
fn cond_true(env: *const MediaEnv, a: *mem.Arena, text: str) -> bool {
    let toks = cv.split_top_level_spaces(a, lower_trim(a, text))
    if toks.len == 0usize { ret true }
    var any_or = false
    var all = true
    var any = false
    var negate = false
    var i = 0usize
    while i < toks.len {
        let t = toks[i]
        i += 1usize
        if str.eq(t, "and") { continue }
        if str.eq(t, "or") {
            any_or = true
            continue
        }
        if str.eq(t, "not") {
            negate = true
            continue
        }
        if t.len > 0usize && t[0usize] == 40u8 {
            let inner = inner_of(t)
            var v = false
            if inner.len > 0usize && (inner[0usize] == 40u8 || str.starts_with(inner, "not ")) { v = cond_true(env, a, inner) } else { v = feature_true(env, a, inner) }
            if negate {
                v = !v
                negate = false
            }
            if v { any = true } else { all = false }
            continue
        }
        // A bare word where a term should be (an unknown function, junk): false.
        all = false
    }
    if any_or { ret any }
    ret all
}

fn query_true(env: *const MediaEnv, a: *mem.Arena, query: str) -> bool {
    let toks = cv.split_top_level_spaces(a, lower_trim(a, query))
    if toks.len == 0usize { ret true }
    var i = 0usize
    var negated = false
    if str.eq(toks[0usize], "not") {
        negated = true
        i = 1usize
    } else if str.eq(toks[0usize], "only") {
        i = 1usize
    }
    var type_ok = true
    var rest_from = i
    if i < toks.len && !(toks[i].len > 0usize && toks[i][0usize] == 40u8) && !str.eq(toks[i], "and") && !str.eq(toks[i], "or") && !str.eq(toks[i], "not") {
        let ty = toks[i]
        type_ok = str.eq(ty, "all") || str.eq(ty, "screen") || (str.eq(ty, "print") && env.print)
        rest_from = i + 1usize
    }
    var cond_ok = true
    if rest_from < toks.len {
        let rest = toks[rest_from..]
        let (joined, e) = str.join(a, rest, " ")
        if e == ok { cond_ok = cond_true(env, a, joined) } else { cond_ok = false }
    }
    let result = type_ok && cond_ok
    if negated { ret !result }
    ret result
}

fn media_matches(env: *const MediaEnv, a: *mem.Arena, prelude: str) -> bool {
    let t = cv.trim_ws(prelude)
    if t.len == 0usize { ret true }
    let queries = cv.split_top_level_commas(a, t)
    var i = 0usize
    while i < queries.len {
        if query_true(env, a, queries[i]) { ret true }
        i += 1usize
    }
    ret false
}

// --- @supports

fn declaration_supported(a: *mem.Arena, inner: str) -> bool {
    let (colon, has) = str.find(inner, ":")
    if !has { ret false }
    let prop = lower_trim(a, inner[..colon])
    let value = cv.trim_ws(inner[colon + 1usize..])
    if prop.len == 0usize || value.len == 0usize { ret false }
    var i = 0usize
    while i < prop.len {
        let c = prop[i]
        let ok_c = (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) || c == 45u8 || c == 95u8
        if !ok_c { ret false }
        i += 1usize
    }
    var depth = 0i64
    var k = 0usize
    while k < value.len {
        if value[k] == 40u8 { depth += 1i64 }
        if value[k] == 41u8 { depth -= 1i64 }
        if depth < 0i64 { ret false }
        k += 1usize
    }
    ret depth == 0i64
}

fn supports_true(a: *mem.Arena, source: str, text: str) -> bool {
    let t = cv.trim_ws(text)
    if t.len == 0usize { ret true }
    let low = cv.lower(a, t)
    if str.starts_with(low, "not ") || str.starts_with(low, "not(") { ret !supports_true(a, source, cv.trim_ws(t[3usize..])) }
    var values = 0usize
    var all = true
    var any = false
    var any_or = false
    var i = 0usize
    while i < t.len {
        while i < t.len && (t[i] == 32u8 || t[i] == 9u8 || t[i] == 10u8) { i += 1usize }
        if i >= t.len { break }
        let rest = cv.lower(a, t[i..])
        if str.starts_with(rest, "and ") || str.starts_with(rest, "and(") {
            i += 3usize
            continue
        }
        if str.starts_with(rest, "or ") || str.starts_with(rest, "or(") {
            any_or = true
            i += 2usize
            continue
        }
        var value = true
        var next = i
        if str.starts_with(rest, "selector(") {
            let close = skip_group(t, i + 8usize)
            let inner = t[i + 9usize..close - 1usize]
            value = selector_parses(a, inner)
            next = close
        } else if t[i] == 40u8 {
            let close = skip_group(t, i)
            let inner = inner_of(t[i..close])
            if inner.len > 0usize && (inner[0usize] == 40u8 || str.starts_with(cv.lower(a, inner), "not ") || str.starts_with(cv.lower(a, inner), "selector(")) { value = supports_true(a, source, inner) } else { value = declaration_supported(a, inner) }
            next = close
        } else if str.starts_with(rest, "font-tech(") || str.starts_with(rest, "font-format(") {
            let (po, _ph) = str.find(rest, "(")
            let open_at = i + po
            next = skip_group(t, open_at)
            value = true
        } else {
            next = i + 1usize
        }
        values += 1usize
        if value { any = true } else { all = false }
        if next <= i { next = i + 1usize }
        i = next
    }
    if values == 0usize { ret true }
    if any_or && !str.contains(cv.lower(a, t), " and ") { ret any }
    ret all
}

fn selector_parses(a: *mem.Arena, text: str) -> bool {
    let (tokens, e) = syntax.tokenize(a, text)
    if e != ok { ret false }
    let (chosen, ce) = selector.parse_selector_list_for_rule(a, text, tokens)
    ret ce == ok && chosen.len > 0usize
}

// --- @container

fn unknown_cond() -> container.Condition { ret container.unknown_condition() }

fn feature_cond(kind: container.FeatureKind, op: container.Op, value: f64) -> container.Condition {
    ret container.Condition { kind: .Feature, parts: zero, feature: kind, op: op, value: value }
}

fn parts_cond(a: *mem.Arena, kind: container.CondKind, parts: []const container.Condition) -> container.Condition {
    let (copy, e) = mem.alloc[container.Condition](a, parts.len)
    if e != ok { ret unknown_cond() }
    mem.copy[container.Condition](copy, parts)
    ret container.Condition { kind: kind, parts: copy, feature: .Width, op: .Eq, value: 0.0f64 }
}

fn axis_of(name: str) -> (container.FeatureKind, bool) {
    if str.eq(name, "width") || str.eq(name, "inline-size") { ret (.Width, true) }
    if str.eq(name, "height") || str.eq(name, "block-size") { ret (.Height, true) }
    if str.eq(name, "aspect-ratio") { ret (.AspectRatio, true) }
    ret (.Width, false)
}

fn op_of(text: str) -> container.Op {
    if str.eq(text, "<") { ret .Lt }
    if str.eq(text, "<=") { ret .Le }
    if str.eq(text, ">") { ret .Gt }
    if str.eq(text, ">=") { ret .Ge }
    ret .Eq
}

fn flip_container_op(op: container.Op) -> container.Op {
    if op == .Lt { ret .Gt }
    if op == .Le { ret .Ge }
    if op == .Gt { ret .Lt }
    if op == .Ge { ret .Le }
    ret op
}

fn container_value(a: *mem.Arena, kind: container.FeatureKind, text: str) -> (f64, bool) {
    if kind == .AspectRatio {
        let r = ratio_of(a, text)
        ret (r, r > 0.0f64)
    }
    let env = media_env(1280.0f64, 720.0f64)
    let (px, good) = px_of(&env, a, text)
    ret (px, good)
}

fn container_feature(a: *mem.Arena, text: str) -> (container.Condition, bool) {
    let t = lower_trim(a, text)
    if t.len == 0usize { ret (unknown_cond(), false) }
    let (colon, has_colon) = str.find(t, ":")
    if has_colon {
        let name = cv.trim_ws(t[..colon])
        let value = cv.trim_ws(t[colon + 1usize..])
        if str.eq(name, "orientation") {
            if str.contains(value, "portrait") { ret (feature_cond(.OrientationPortrait, .Eq, 0.0f64), true) }
            if str.contains(value, "landscape") { ret (feature_cond(.OrientationLandscape, .Eq, 0.0f64), true) }
            ret (unknown_cond(), false)
        }
        var base = name
        var op: container.Op = .Eq
        if str.starts_with(name, "min-") {
            base = name[4usize..]
            op = .Ge
        }
        if str.starts_with(name, "max-") {
            base = name[4usize..]
            op = .Le
        }
        let (kind, known) = axis_of(base)
        if !known { ret (unknown_cond(), false) }
        let (v, good) = container_value(a, kind, value)
        if !good { ret (unknown_cond(), false) }
        ret (feature_cond(kind, op, v), true)
    }
    let toks = cv.split_top_level_spaces(a, spread_ops(a, t))
    if toks.len == 3usize && is_cmp(toks[1usize]) {
        let (kind, known) = axis_of(toks[0usize])
        if known {
            let (v, good) = container_value(a, kind, toks[2usize])
            if good { ret (feature_cond(kind, op_of(toks[1usize]), v), true) }
        }
        let (kind2, known2) = axis_of(toks[2usize])
        if known2 {
            let (v2, good2) = container_value(a, kind2, toks[0usize])
            if good2 { ret (feature_cond(kind2, flip_container_op(op_of(toks[1usize])), v2), true) }
        }
        ret (unknown_cond(), false)
    }
    if toks.len == 5usize && is_cmp(toks[1usize]) && is_cmp(toks[3usize]) {
        let (kind, known) = axis_of(toks[2usize])
        if known {
            let (lo, g1) = container_value(a, kind, toks[0usize])
            let (hi, g2) = container_value(a, kind, toks[4usize])
            if g1 && g2 {
                let parts = [_]container.Condition{ feature_cond(kind, flip_container_op(op_of(toks[1usize])), lo), feature_cond(kind, op_of(toks[3usize]), hi) }
                ret (parts_cond(a, .And, parts[0..]), true)
            }
        }
    }
    ret (unknown_cond(), false)
}

fn container_cond(a: *mem.Arena, text: str) -> (container.Condition, bool) {
    let t = cv.trim_ws(text)
    if t.len == 0usize { ret (unknown_cond(), false) }
    let low = cv.lower(a, t)
    if str.starts_with(low, "not ") || str.starts_with(low, "not(") {
        let (inner, good) = container_cond(a, t[3usize..])
        if !good { ret (unknown_cond(), false) }
        let one = [_]container.Condition{ inner }
        ret (parts_cond(a, .Not, one[0..]), true)
    }
    let (made, e) = list.init[container.Condition](a, 4usize)
    if e != ok { ret (unknown_cond(), false) }
    var parts = made
    var any_or = false
    var i = 0usize
    while i < t.len {
        while i < t.len && (t[i] == 32u8 || t[i] == 9u8 || t[i] == 10u8) { i += 1usize }
        if i >= t.len { break }
        var next = i
        var cond = unknown_cond()
        if t[i] == 40u8 {
            let close = skip_group(t, i)
            let inner = inner_of(t[i..close])
            let inner_low = cv.lower(a, inner)
            if inner.len == 0usize {
                cond = unknown_cond()
            } else if inner[0usize] == 40u8 || str.starts_with(inner_low, "not ") {
                let (nested, good) = container_cond(a, inner)
                if good { cond = nested }
            } else {
                let (feature, good) = container_feature(a, inner)
                if good { cond = feature }
            }
            next = close
        } else {
            // style(...), scroll-state(...) or another function: unknown.
            let (open_at, has_open) = str.find(t[i..], "(")
            if !has_open { break }
            next = skip_group(t, i + open_at)
            cond = unknown_cond()
        }
        let pushed = list.push[container.Condition](&parts, cond)
        i = next
        while i < t.len && (t[i] == 32u8 || t[i] == 9u8 || t[i] == 10u8) { i += 1usize }
        let rest = cv.lower(a, t[i..])
        if str.starts_with(rest, "and ") || str.starts_with(rest, "and(") {
            i += 3usize
            continue
        }
        if str.starts_with(rest, "or ") || str.starts_with(rest, "or(") {
            any_or = true
            i += 2usize
            continue
        }
        break
    }
    if parts.len == 0usize { ret (unknown_cond(), false) }
    if parts.len == 1usize { ret (parts.items[0usize], true) }
    var kind: container.CondKind = .And
    if any_or { kind = .Or }
    ret (parts_cond(a, kind, list.slice_const[container.Condition](&parts)), true)
}

// `[<name>] <condition>`; false when no condition can be read (the body then applies, so unknown syntax never hides content).
fn container_query(a: *mem.Arena, prelude: str) -> (cascade.ContainerQuery, bool) {
    var t = cv.trim_ws(prelude)
    var has_name = false
    var name = ""
    let first_end = first_word_end(t)
    if first_end > 0usize {
        let word = cv.lower(a, t[..first_end])
        if t[0usize] != 40u8 && !str.eq(word, "not") && !str.eq(word, "and") && !str.eq(word, "or") && !str.contains(word, "(") {
            has_name = true
            name = word
            t = cv.trim_ws(t[first_end..])
        }
    }
    let (cond, good) = container_cond(a, t)
    if !good { ret (cascade.ContainerQuery { has_name: false, name: "", condition: unknown_cond() }, false) }
    ret (cascade.ContainerQuery { has_name: has_name, name: name, condition: cond }, true)
}

fn first_word_end(t: str) -> usize {
    var i = 0usize
    while i < t.len && t[i] != 32u8 && t[i] != 9u8 && t[i] != 10u8 && t[i] != 40u8 { i += 1usize }
    ret i
}

// --- @scope

fn scope_selectors(a: *mem.Arena, text: str) -> []const selector.Selector {
    let (tokens, e) = syntax.tokenize(a, text)
    if e != ok { ret zero }
    let (chosen, ce) = selector.parse_selector_list_for_rule(a, text, tokens)
    if ce != ok { ret zero }
    let (made, me) = list.init[selector.Selector](a, chosen.len + 1usize)
    if me != ok { ret zero }
    var out = made
    var i = 0usize
    while i < chosen.len {
        if !chosen[i].has_pseudo {
            let pushed = list.push[selector.Selector](&out, chosen[i].selector)
        }
        i += 1usize
    }
    ret list.slice_const[selector.Selector](&out)
}

fn scope_rule(a: *mem.Arena, prelude: str) -> cascade.Scope {
    let t = cv.trim_ws(prelude)
    var starts: []const selector.Selector = zero
    var limits: []const selector.Selector = zero
    var i = 0usize
    while i < t.len && (t[i] == 32u8 || t[i] == 9u8 || t[i] == 10u8) { i += 1usize }
    if i < t.len && t[i] == 40u8 {
        let close = skip_group(t, i)
        starts = scope_selectors(a, inner_of(t[i..close]))
        i = close
    }
    while i < t.len && (t[i] == 32u8 || t[i] == 9u8 || t[i] == 10u8) { i += 1usize }
    if i + 2usize <= t.len && str.eq(cv.lower(a, t[i..i + 2usize]), "to") {
        i += 2usize
        while i < t.len && (t[i] == 32u8 || t[i] == 9u8 || t[i] == 10u8) { i += 1usize }
        if i < t.len && t[i] == 40u8 {
            let close = skip_group(t, i)
            limits = scope_selectors(a, inner_of(t[i..close]))
        }
    }
    ret cascade.Scope { starts: starts, limits: limits }
}

// --- Fonts

fn url_in(a: *mem.Arena, entry: str) -> (str, bool) {
    let low = cv.lower(a, entry)
    let (at, found) = str.find(low, "url(")
    if !found { ret ("", false) }
    let close = skip_group(entry, at + 3usize)
    if close <= at + 4usize { ret ("", false) }
    let inner = cv.trim_ws(entry[at + 4usize..close - 1usize])
    let u = cv.trim_ws(strip_quotes(inner))
    ret (u, u.len > 0usize)
}

fn format_in(a: *mem.Arena, entry: str, url: str) -> str {
    let low = cv.lower(a, entry)
    let (at, found) = str.find(low, "format(")
    if found {
        let close = skip_group(entry, at + 6usize)
        if close > at + 7usize { ret cv.lower(a, cv.trim_ws(strip_quotes(cv.trim_ws(entry[at + 7usize..close - 1usize])))) }
    }
    // From the extension (sans query and fragment).
    var path = url
    var i = 0usize
    while i < path.len {
        if path[i] == 63u8 || path[i] == 35u8 {
            path = path[..i]
            break
        }
        i += 1usize
    }
    let (dot, has_dot) = str.rfind(path, ".")
    if !has_dot { ret "" }
    let ext = cv.lower(a, path[dot + 1usize..])
    if str.eq(ext, "ttf") || str.eq(ext, "ttc") { ret "truetype" }
    if str.eq(ext, "otf") { ret "opentype" }
    if str.eq(ext, "woff") { ret "woff" }
    if str.eq(ext, "woff2") { ret "woff2" }
    if str.eq(ext, "eot") { ret "embedded-opentype" }
    if str.eq(ext, "svg") { ret "svg" }
    ret ""
}

// The best loadable source: truetype/opentype, then woff2, then woff, then a format we cannot name, else the first url.
fn select_font_src(a: *mem.Arena, value: str) -> str {
    let entries = cv.split_top_level_commas(a, value)
    var woff2 = ""
    var woff = ""
    var unknown = ""
    var first = ""
    var i = 0usize
    while i < entries.len {
        let (u, has) = url_in(a, entries[i])
        i += 1usize
        if !has { continue }
        if first.len == 0usize { first = u }
        let fmt = format_in(a, entries[i - 1usize], u)
        if str.eq(fmt, "truetype") || str.eq(fmt, "opentype") || str.eq(fmt, "truetype-aat") { ret u }
        if str.eq(fmt, "woff2") {
            if woff2.len == 0usize { woff2 = u }
        } else if str.eq(fmt, "woff") {
            if woff.len == 0usize { woff = u }
        } else if str.eq(fmt, "embedded-opentype") || str.eq(fmt, "svg") {
            // not loadable
        } else if unknown.len == 0usize {
            unknown = u
        }
    }
    if woff2.len > 0usize { ret woff2 }
    if woff.len > 0usize { ret woff }
    if unknown.len > 0usize { ret unknown }
    ret first
}

// --- The loader

type Ctx = struct { has_layer: bool, layer: i64, path: str, containers: []const cascade.ContainerQuery, scopes: []const cascade.Scope }

type Loader = struct {
    a: *mem.Arena, env: MediaEnv,
    rules: list.List[cascade.Rule], fonts: list.List[FontFace], keyframes: list.List[Keyframes],
    properties: list.List[PropertyRule], imports: list.List[str], layers: list.List[str],
    order: i64, anonymous: usize
}

fn new_loader(a: *mem.Arena, env: MediaEnv) -> Loader {
    var l: Loader = zero
    l.a = a
    l.env = env
    let (r, _e1) = list.init[cascade.Rule](a, 32usize)
    let (f, _e2) = list.init[FontFace](a, 4usize)
    let (k, _e3) = list.init[Keyframes](a, 4usize)
    let (p, _e4) = list.init[PropertyRule](a, 2usize)
    let (i, _e5) = list.init[str](a, 2usize)
    let (y, _e6) = list.init[str](a, 4usize)
    l.rules = r
    l.fonts = f
    l.keyframes = k
    l.properties = p
    l.imports = i
    l.layers = y
    ret l
}

fn layer_index(l: *Loader, name: str) -> i64 {
    var i = 0usize
    while i < l.layers.len {
        if str.eq(l.layers.items[i], name) { ret i64(i) }
        i += 1usize
    }
    let pushed = list.push[str](&l.layers, name)
    ret i64(l.layers.len) - 1i64
}

fn decls_of(l: *Loader, src: str, tokens: []const syntax.Token) -> []const cascade.Declaration {
    let (parsed, e) = syntax.parse_declarations(l.a, tokens)
    if e != ok { ret zero }
    let (out, me) = mem.alloc[cascade.Declaration](l.a, parsed.len + 1usize)
    if me != ok { ret zero }
    var i = 0usize
    while i < parsed.len {
        out[i] = cascade.Declaration { property: cv.lower(l.a, parsed[i].name), value: cv.trim_ws(syntax.raw_text(src, parsed[i].value)), important: parsed[i].important }
        i += 1usize
    }
    ret out[..parsed.len]
}

fn decl_value(decls: []const cascade.Declaration, name: str) -> (str, bool) {
    var i = decls.len
    while i > 0usize {
        i -= 1usize
        if str.eq(decls[i].property, name) { ret (decls[i].value, true) }
    }
    ret ("", false)
}

fn style_rule(l: *Loader, src: str, one: syntax.Rule, ctx: Ctx) {
    let (chosen, ce) = selector.parse_selector_list_for_rule(l.a, src, one.prelude)
    if ce != ok || chosen.len == 0usize { ret }
    let decls = decls_of(l, src, one.block.inner)
    if decls.len == 0usize { ret }
    let order = l.order
    l.order += 1i64
    var q = 0usize
    while q < chosen.len {
        if !chosen[q].has_pseudo {
            let pushed = list.push[cascade.Rule](&l.rules, cascade.Rule { selector: chosen[q].selector, declarations: decls, source: order, has_layer: ctx.has_layer, layer: ctx.layer, containers: ctx.containers, scopes: ctx.scopes })
        }
        q += 1usize
    }
}

fn with_container(l: *Loader, ctx: Ctx, q: cascade.ContainerQuery) -> Ctx {
    let (copy, e) = mem.alloc[cascade.ContainerQuery](l.a, ctx.containers.len + 1usize)
    if e != ok { ret ctx }
    mem.copy[cascade.ContainerQuery](copy[..ctx.containers.len], ctx.containers)
    copy[ctx.containers.len] = q
    var next = ctx
    next.containers = copy
    ret next
}

fn with_scope(l: *Loader, ctx: Ctx, sc: cascade.Scope) -> Ctx {
    let (copy, e) = mem.alloc[cascade.Scope](l.a, ctx.scopes.len + 1usize)
    if e != ok { ret ctx }
    mem.copy[cascade.Scope](copy[..ctx.scopes.len], ctx.scopes)
    copy[ctx.scopes.len] = sc
    var next = ctx
    next.scopes = copy
    ret next
}

fn add_font_face(l: *Loader, src: str, tokens: []const syntax.Token) {
    let decls = decls_of(l, src, tokens)
    let (family_raw, has_family) = decl_value(decls, "font-family")
    let (src_raw, has_src) = decl_value(decls, "src")
    if !has_family || !has_src { ret }
    let family = cv.trim_ws(strip_quotes(cv.trim_ws(family_raw)))
    let url = select_font_src(l.a, src_raw)
    if family.len == 0usize || url.len == 0usize { ret }
    let (weight, _w) = decl_value(decls, "font-weight")
    let (fstyle, _s) = decl_value(decls, "font-style")
    let (range, _r) = decl_value(decls, "unicode-range")
    let (display, _d) = decl_value(decls, "font-display")
    let pushed = list.push[FontFace](&l.fonts, FontFace { family: family, url: url, weight: weight, style: fstyle, unicode_range: range, display: display })
}

fn stop_offset(a: *mem.Arena, s: str) -> (f64, bool) {
    let t = lower_trim(a, s)
    if str.eq(t, "from") { ret (0.0f64, true) }
    if str.eq(t, "to") { ret (1.0f64, true) }
    if t.len > 1usize && t[t.len - 1usize] == 37u8 {
        let (n, good) = number_of(a, t[..t.len - 1usize])
        ret (n / 100.0f64, good)
    }
    ret (0.0f64, false)
}

fn add_keyframes(l: *Loader, src: str, one: syntax.Rule) {
    let prelude = cv.trim_ws(syntax.raw_text(src, one.prelude))
    let name = strip_quotes(prelude)
    if name.len == 0usize { ret }
    let (inner_rules, e) = syntax.parse_rules(l.a, one.block.inner, false)
    if e != ok { ret }
    let (made, me) = list.init[Stop](l.a, inner_rules.len + 1usize)
    if me != ok { ret }
    var stops = made
    var i = 0usize
    while i < inner_rules.len {
        let inner = inner_rules[i]
        i += 1usize
        if inner.at || !inner.has_block { continue }
        let decls = decls_of(l, src, inner.block.inner)
        let selectors = cv.split_top_level_commas(l.a, syntax.raw_text(src, inner.prelude))
        var k = 0usize
        while k < selectors.len {
            let (off, good) = stop_offset(l.a, selectors[k])
            if good {
                let pushed = list.push[Stop](&stops, Stop { offset: off, declarations: decls })
            }
            k += 1usize
        }
    }
    // Sorted by offset (stable): insertion sort.
    var a1 = 1usize
    while a1 < stops.len {
        let cur = stops.items[a1]
        var b1 = a1
        while b1 > 0usize && stops.items[b1 - 1usize].offset > cur.offset {
            stops.items[b1] = stops.items[b1 - 1usize]
            b1 -= 1usize
        }
        stops.items[b1] = cur
        a1 += 1usize
    }
    let pushed = list.push[Keyframes](&l.keyframes, Keyframes { name: name, stops: list.slice_const[Stop](&stops) })
}

fn add_property(l: *Loader, src: str, one: syntax.Rule) {
    let name = cv.trim_ws(syntax.raw_text(src, one.prelude))
    if !str.starts_with(name, "--") { ret }
    let decls = decls_of(l, src, one.block.inner)
    let (syn, _a) = decl_value(decls, "syntax")
    let (inh, _b) = decl_value(decls, "inherits")
    let (init, _c) = decl_value(decls, "initial-value")
    let pushed = list.push[PropertyRule](&l.properties, PropertyRule { name: name, syntax: strip_quotes(cv.trim_ws(syn)), inherits: str.eq(cv.lower(l.a, inh), "true"), initial: init })
}

fn add_import(l: *Loader, src: str, one: syntax.Rule) {
    let text = cv.trim_ws(syntax.raw_text(src, one.prelude))
    var url = ""
    var rest = ""
    let low = cv.lower(l.a, text)
    if str.starts_with(low, "url(") {
        let close = skip_group(text, 3usize)
        url = cv.trim_ws(strip_quotes(cv.trim_ws(text[4usize..close - 1usize])))
        rest = cv.trim_ws(text[close..])
    } else if text.len > 0usize && (text[0usize] == 34u8 || text[0usize] == 39u8) {
        let q = text[0usize]
        var e = 1usize
        while e < text.len && text[e] != q { e += 1usize }
        url = text[1usize..e]
        if e + 1usize <= text.len { rest = cv.trim_ws(text[e + 1usize..]) }
    }
    if url.len == 0usize { ret }
    // `layer(...)` / `supports(...)` are accepted as they are; a trailing media list must match.
    var cursor = rest
    var guard = 0usize
    while guard < 4usize && cursor.len > 0usize {
        guard += 1usize
        let cl = cv.lower(l.a, cursor)
        if str.starts_with(cl, "layer(") || str.starts_with(cl, "supports(") {
            let (po, _h) = str.find(cursor, "(")
            cursor = cv.trim_ws(cursor[skip_group(cursor, po)..])
        } else if str.starts_with(cl, "layer") && (cl.len == 5usize || cl[5usize] == 32u8) {
            cursor = cv.trim_ws(cursor[5usize..])
        } else {
            break
        }
    }
    if cursor.len > 0usize && !media_matches(&l.env, l.a, cursor) { ret }
    let pushed = list.push[str](&l.imports, url)
}

fn layer_names(l: *Loader, ctx: Ctx, prelude: str) -> []const str {
    let parts = cv.split_top_level_commas(l.a, prelude)
    let (made, e) = list.init[str](l.a, parts.len + 1usize)
    if e != ok { ret zero }
    var out = made
    var i = 0usize
    while i < parts.len {
        let n = lower_trim(l.a, parts[i])
        if n.len > 0usize {
            var full = n
            if ctx.path.len > 0usize {
                let (joined, je) = str.concat(l.a, ctx.path, ".")
                if je == ok {
                    let (full2, fe) = str.concat(l.a, joined, n)
                    if fe == ok { full = full2 }
                }
            }
            let pushed = list.push[str](&out, full)
        }
        i += 1usize
    }
    ret list.slice_const[str](&out)
}

fn at_rule(l: *Loader, src: str, one: syntax.Rule, ctx: Ctx) {
    let name = one.name
    let prelude = syntax.raw_text(src, one.prelude)
    if str.eq(name, "import") {
        add_import(l, src, one)
        ret
    }
    if str.eq(name, "layer") {
        let names = layer_names(l, ctx, prelude)
        var i = 0usize
        while i < names.len {
            let idx = layer_index(l, names[i])
            i += 1usize
        }
        if !one.has_block { ret }
        var path = ""
        if names.len > 0usize {
            path = names[names.len - 1usize]
        } else {
            let (num, _ne) = str.concat(l.a, "~anonymous", "")
            l.anonymous += 1usize
            var b = try_text(l.a, 24usize)
            text_push(&b, "~anonymous-")
            text_push_usize(&b, l.anonymous)
            path = text_done(&b)
            if ctx.path.len > 0usize { path = cat3(l.a, ctx.path, ".", path) }
        }
        var next = ctx
        next.has_layer = true
        next.layer = layer_index(l, path)
        next.path = path
        walk_block(l, src, one, next)
        ret
    }
    if !one.has_block { ret }
    if str.eq(name, "media") {
        if media_matches(&l.env, l.a, prelude) { walk_block(l, src, one, ctx) }
        ret
    }
    if str.eq(name, "supports") {
        if supports_true(l.a, src, prelude) { walk_block(l, src, one, ctx) }
        ret
    }
    if str.eq(name, "container") {
        let (q, good) = container_query(l.a, prelude)
        if good { walk_block(l, src, one, with_container(l, ctx, q)) } else { walk_block(l, src, one, ctx) }
        ret
    }
    if str.eq(name, "scope") {
        walk_block(l, src, one, with_scope(l, ctx, scope_rule(l.a, prelude)))
        ret
    }
    if str.eq(name, "font-face") {
        add_font_face(l, src, one.block.inner)
        ret
    }
    if str.eq(name, "keyframes") || str.eq(name, "-webkit-keyframes") {
        add_keyframes(l, src, one)
        ret
    }
    if str.eq(name, "property") {
        add_property(l, src, one)
        ret
    }
}

fn cat3(a: *mem.Arena, x: str, y: str, z: str) -> str {
    let (xy, e1) = str.concat(a, x, y)
    if e1 != ok { ret x }
    let (xyz, e2) = str.concat(a, xy, z)
    if e2 != ok { ret xy }
    ret xyz
}

// A small builder that never fails (a refusal drops the byte).
type Text = struct { b: str.Builder, bad: bool }

fn try_text(a: *mem.Arena, cap: usize) -> Text {
    let (made, e) = str.builder(a, cap)
    var t: Text = zero
    t.b = made
    t.bad = e != ok
    ret t
}

fn text_push(t: *Text, s: str) {
    if t.bad { ret }
    let e = str.push(&t.b, s)
    if e != ok { t.bad = true }
}

fn text_push_usize(t: *Text, v: usize) {
    if t.bad { ret }
    let e = str.push_usize(&t.b, v)
    if e != ok { t.bad = true }
}

fn text_done(t: *Text) -> str {
    if t.bad { ret "" }
    ret str.done(&t.b)
}

fn walk_block(l: *Loader, src: str, one: syntax.Rule, ctx: Ctx) {
    let (inner, e) = syntax.parse_rules(l.a, one.block.inner, false)
    if e != ok { ret }
    walk(l, src, inner, ctx)
}

fn walk(l: *Loader, src: str, rules: []const syntax.Rule, ctx: Ctx) {
    var i = 0usize
    while i < rules.len {
        let one = rules[i]
        i += 1usize
        if one.at {
            at_rule(l, src, one, ctx)
        } else if one.has_block {
            style_rule(l, src, one, ctx)
        }
    }
}

// Appends the rules of `source` (rule order continues across sheets; the sheet's `@import`s are listed, not fetched).
fn load(l: *Loader, source: str) -> err {
    var text = source
    if str.contains(text, "<![CDATA[") {
        let (a1, e1) = str.replace(l.a, text, "<![CDATA[", "")
        if e1 == ok {
            let (a2, e2) = str.replace(l.a, a1, "]]>", "")
            if e2 == ok { text = a2 }
        }
    }
    let tokens = try syntax.tokenize(l.a, text)
    let rules = try syntax.parse_rules(l.a, tokens, true)
    let ctx = Ctx { has_layer: false, layer: 0i64, path: "", containers: zero, scopes: zero }
    walk(l, text, rules, ctx)
    ret ok
}

fn finish(l: *Loader) -> Loaded {
    ret Loaded { rules: list.slice_const[cascade.Rule](&l.rules), fonts: list.slice_const[FontFace](&l.fonts), keyframes: list.slice_const[Keyframes](&l.keyframes), properties: list.slice_const[PropertyRule](&l.properties), imports: list.slice_const[str](&l.imports), layers: list.slice_const[str](&l.layers), next_order: l.order }
}

fn parse_sheet(a: *mem.Arena, env: MediaEnv, source: str) -> (Loaded, err) {
    var l = new_loader(a, env)
    let e = load(&l, source)
    if e != ok { ret (zero, e) }
    ret (finish(&l), ok)
}
