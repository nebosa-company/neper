// YAML, the subset the fence names: block mappings and sequences by indentation,
// flow collections, plain, single- and double-quoted scalars, literal and folded
// blocks with their chomping indicators, and the core schema's null, bool, integer
// and float forms; comments and one leading `---`. The source is split into logical
// lines once -- indent and content with the comment stripped, quotes respected --
// and parsed by recursive descent on indentation; a sequence item that begins a
// mapping is re-read as that mapping two columns in. Anchors, aliases, tags,
// directives and a second document are `Unsupported`; nesting past `max_depth` is
// `TooDeep`; a repeated key is `DuplicateKey` unless the options allow it. The
// writer emits block style, quoting a string that would otherwise read as another
// type; the typed codec follows the other codecs, a struct being a mapping of its
// fields.
use e.io
use e.mem
use e.meta
use e.str

type Pair = struct { key: Value, value: Value }
type Value = union enum u8 { Null, Bool: bool, Integer: i64, Float: f64, String: str, Sequence: []const Value, Mapping: []const Pair }
type Options = struct { max_depth: u16, allow_duplicate_keys: bool }
error Invalid
error TooDeep
error DuplicateKey
error Unsupported

type Line = struct { indent: usize, text: str, raw: str }
type Parser = struct { a: *mem.Arena, lines: []Line, at: usize, options: Options }

// --- Lines.

fn is_blank(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        if text[i] != 32u8 && text[i] != 9u8 && text[i] != 13u8 { ret false }
        i += 1usize
    }
    ret true
}

// The content of a line up to a `#` that starts a comment: one preceded by a space
// and outside quotes.
fn strip_comment(text: str) -> str {
    var quote = 0u8
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if quote != 0u8 {
            if c == quote { quote = 0u8 }
        } else {
            if c == 34u8 || c == 39u8 {
                quote = c
            } else {
                if c == 35u8 && (i == 0usize || text[i - 1usize] == 32u8 || text[i - 1usize] == 9u8) { ret str.trim_end(text[..i]) }
            }
        }
        i += 1usize
    }
    ret str.trim_end(text)
}

fn split_lines(a: *mem.Arena, source: str) -> ([]Line, err) {
    var count = 1usize
    var i = 0usize
    while i < source.len {
        if source[i] == 10u8 { count += 1usize }
        i += 1usize
    }
    let (lines, lines_error) = mem.alloc[Line](a, count)
    if lines_error != ok { ret (zero, lines_error) }
    var used = 0usize
    var at = 0usize
    while at <= source.len {
        var stop = at
        while stop < source.len && source[stop] != 10u8 { stop += 1usize }
        var raw = source[at..stop]
        if raw.len > 0usize && raw[raw.len - 1usize] == 13u8 { raw = raw[..raw.len - 1usize] }
        var indent = 0usize
        while indent < raw.len && raw[indent] == 32u8 { indent += 1usize }
        if indent < raw.len && raw[indent] == 9u8 { ret (zero, Invalid) }
        lines[used] = Line { indent: indent, text: strip_comment(raw[indent..]), raw: raw }
        used += 1usize
        at = stop + 1usize
    }
    ret (lines[..used], ok)
}

// --- Scalars.

fn all_digits(text: str, from: usize) -> bool {
    if from >= text.len { ret false }
    var i = from
    while i < text.len {
        if !str.is_ascii_digit(text[i]) { ret false }
        i += 1usize
    }
    ret true
}

// A plain scalar by the core schema: null, bool, integer, float, else a string.
fn resolve_plain(text: str) -> (Value, err) {
    if text.len == 0usize || str.eq(text, "~") || str.eq(text, "null") || str.eq(text, "Null") || str.eq(text, "NULL") { ret (.Null, ok) }
    if str.eq(text, "true") || str.eq(text, "True") || str.eq(text, "TRUE") { ret (Value{ Bool: true }, ok) }
    if str.eq(text, "false") || str.eq(text, "False") || str.eq(text, "FALSE") { ret (Value{ Bool: false }, ok) }
    var from = 0usize
    var negative = false
    if text[0] == 43u8 || text[0] == 45u8 {
        negative = text[0] == 45u8
        from = 1usize
    }
    let body = text[from..]
    if str.eq(body, ".inf") || str.eq(body, ".Inf") || str.eq(body, ".INF") {
        var inf = mem.bitcast[f64](9218868437227405312u64)
        if negative { inf = 0.0 - inf }
        ret (Value{ Float: inf }, ok)
    }
    if str.eq(body, ".nan") || str.eq(body, ".NaN") || str.eq(body, ".NAN") { ret (Value{ Float: mem.bitcast[f64](9221120237041090560u64) }, ok) }
    if body.len > 2usize && body[0] == 48u8 && (body[1] == 120u8 || body[1] == 111u8) {
        var radix = 16u8
        if body[1] == 111u8 { radix = 8u8 }
        let (magnitude, radix_error) = str.parse_u64_radix(body[2usize..], radix)
        if radix_error == ok && magnitude <= 9223372036854775807u64 {
            var number = i64(magnitude)
            if negative { number = 0i64 - number }
            ret (Value{ Integer: number }, ok)
        }
        ret (Value{ String: text }, ok)
    }
    if all_digits(body, 0usize) {
        let (number, number_error) = str.parse_i64(text)
        if number_error == ok { ret (Value{ Integer: number }, ok) }
        ret (Value{ String: text }, ok)
    }
    // A float has digits with a point or an exponent and nothing else.
    var digits = 0usize
    var points = 0usize
    var exponents = 0usize
    var shape_ok = body.len > 0usize
    var i = 0usize
    while i < body.len {
        let c = body[i]
        if str.is_ascii_digit(c) {
            digits += 1usize
        } else {
        if c == 46u8 {
            points += 1usize
            if exponents > 0usize { shape_ok = false }
        } else {
        if c == 101u8 || c == 69u8 {
            exponents += 1usize
            if digits == 0usize || i + 1usize >= body.len { shape_ok = false }
            if i + 1usize < body.len && (body[i + 1usize] == 43u8 || body[i + 1usize] == 45u8) { i += 1usize }
        } else {
            shape_ok = false
        }
        }
        }
        i += 1usize
    }
    if shape_ok && digits > 0usize && points <= 1usize && exponents <= 1usize && (points == 1usize || exponents == 1usize) {
        let (number, number_error) = str.parse_f64(text)
        if number_error == ok { ret (Value{ Float: number }, ok) }
    }
    ret (Value{ String: text }, ok)
}

fn hex_value(c: u8) -> (u32, bool) {
    if c >= 48u8 && c <= 57u8 { ret (u32(c - 48u8), true) }
    if c >= 97u8 && c <= 102u8 { ret (u32(c - 87u8), true) }
    if c >= 65u8 && c <= 70u8 { ret (u32(c - 55u8), true) }
    ret (0u32, false)
}

fn push_utf8(out: []u8, at: usize, scalar: u32) -> usize {
    if scalar < 128u32 {
        out[at] = u8(scalar)
        ret at + 1usize
    }
    if scalar < 2048u32 {
        out[at] = u8(192u32 | (scalar >> 6u32))
        out[at + 1usize] = u8(128u32 | (scalar & 63u32))
        ret at + 2usize
    }
    if scalar < 65536u32 {
        out[at] = u8(224u32 | (scalar >> 12u32))
        out[at + 1usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
        out[at + 2usize] = u8(128u32 | (scalar & 63u32))
        ret at + 3usize
    }
    out[at] = u8(240u32 | (scalar >> 18u32))
    out[at + 1usize] = u8(128u32 | ((scalar >> 12u32) & 63u32))
    out[at + 2usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
    out[at + 3usize] = u8(128u32 | (scalar & 63u32))
    ret at + 4usize
}

// A double-quoted body with its escapes decoded into the arena.
fn unescape_double(a: *mem.Arena, body: str) -> (str, err) {
    let (slash, has_slash) = str.find(body, "\\")
    if !has_slash { ret (body, ok) }
    let (out, out_error) = mem.alloc[u8](a, body.len)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var i = 0usize
    while i < body.len {
        let c = body[i]
        if c != 92u8 {
            out[used] = c
            used += 1usize
            i += 1usize
            continue
        }
        i += 1usize
        if i >= body.len { ret ("", Invalid) }
        let e = body[i]
        i += 1usize
        if e == 110u8 { out[used] = 10u8 } else {
        if e == 116u8 { out[used] = 9u8 } else {
        if e == 114u8 { out[used] = 13u8 } else {
        if e == 48u8 { out[used] = 0u8 } else {
        if e == 34u8 || e == 92u8 || e == 47u8 || e == 32u8 { out[used] = e } else {
        if e == 120u8 || e == 117u8 || e == 85u8 {
            var width = 2usize
            if e == 117u8 { width = 4usize }
            if e == 85u8 { width = 8usize }
            if i + width > body.len { ret ("", Invalid) }
            var scalar = 0u32
            var k = 0usize
            while k < width {
                let (digit, is_hex) = hex_value(body[i + k])
                if !is_hex { ret ("", Invalid) }
                scalar = (scalar << 4u32) | digit
                k += 1usize
            }
            i += width
            if scalar > 1114111u32 || (scalar >= 55296u32 && scalar <= 57343u32) { ret ("", Invalid) }
            used = push_utf8(out, used, scalar)
            continue
        } else {
            ret ("", Invalid)
        }
        }
        }
        }
        }
        }
        used += 1usize
    }
    ret (out[..used], ok)
}

// The single-quoted body, `''` folded to one quote.
fn unescape_single(a: *mem.Arena, body: str) -> (str, err) {
    let (pair, has_pair) = str.find(body, "''")
    if !has_pair { ret (body, ok) }
    let (out, out_error) = mem.alloc[u8](a, body.len)
    if out_error != ok { ret ("", out_error) }
    var used = 0usize
    var i = 0usize
    while i < body.len {
        out[used] = body[i]
        used += 1usize
        if body[i] == 39u8 && i + 1usize < body.len && body[i + 1usize] == 39u8 { i += 1usize }
        i += 1usize
    }
    ret (out[..used], ok)
}

// Where a scalar starting at `at` ends inside flow context: at an unquoted `,`, `]`,
// `}` or `: `; (end, error).
fn scalar_end(text: str, at: usize, in_flow: bool) -> (usize, err) {
    if at < text.len && (text[at] == 34u8 || text[at] == 39u8) {
        let quote = text[at]
        var i = at + 1usize
        while i < text.len {
            if text[i] == 92u8 && quote == 34u8 {
                i += 2usize
                continue
            }
            if text[i] == quote {
                if quote == 39u8 && i + 1usize < text.len && text[i + 1usize] == 39u8 {
                    i += 2usize
                    continue
                }
                ret (i + 1usize, ok)
            }
            i += 1usize
        }
        ret (0usize, Invalid)
    }
    var i = at
    while i < text.len {
        let c = text[i]
        if in_flow && (c == 44u8 || c == 93u8 || c == 125u8) { break }
        if c == 58u8 && (i + 1usize == text.len || text[i + 1usize] == 32u8) { break }
        i += 1usize
    }
    ret (i, ok)
}

fn scalar_value(a: *mem.Arena, text: str) -> (Value, err) {
    let trimmed = str.trim(text)
    if trimmed.len >= 2usize && trimmed[0] == 34u8 && trimmed[trimmed.len - 1usize] == 34u8 {
        let (decoded, decode_error) = unescape_double(a, trimmed[1usize..trimmed.len - 1usize])
        if decode_error != ok { ret (zero, decode_error) }
        ret (Value{ String: decoded }, ok)
    }
    if trimmed.len >= 2usize && trimmed[0] == 39u8 && trimmed[trimmed.len - 1usize] == 39u8 {
        let (decoded, decode_error) = unescape_single(a, trimmed[1usize..trimmed.len - 1usize])
        if decode_error != ok { ret (zero, decode_error) }
        ret (Value{ String: decoded }, ok)
    }
    if trimmed.len > 0usize && (trimmed[0] == 38u8 || trimmed[0] == 42u8 || trimmed[0] == 33u8 || trimmed[0] == 37u8) { ret (zero, Unsupported) }
    if trimmed.len > 0usize && (trimmed[0] == 34u8 || trimmed[0] == 39u8) { ret (zero, Invalid) }
    let (resolved, resolve_error) = resolve_plain(trimmed)
    ret (resolved, resolve_error)
}

// --- Flow collections, on one line.

fn flow_value(p: *Parser, text: str, at_in: usize, depth: usize) -> (Value, usize, err) {
    var at = at_in
    while at < text.len && text[at] == 32u8 { at += 1usize }
    if at >= text.len { ret (zero, at, Invalid) }
    if text[at] == 91u8 {
        if depth >= usize(p.options.max_depth) { ret (zero, at, TooDeep) }
        var items: [64]Value = zero
        var count = 0usize
        at += 1usize
        while true {
            while at < text.len && text[at] == 32u8 { at += 1usize }
            if at >= text.len { ret (zero, at, Invalid) }
            if text[at] == 93u8 {
                at += 1usize
                break
            }
            if count == 64usize { ret (zero, at, Invalid) }
            let (item, after, item_error) = flow_value(p, text, at, depth + 1usize)
            if item_error != ok { ret (zero, at, item_error) }
            items[count] = item
            count += 1usize
            at = after
            while at < text.len && text[at] == 32u8 { at += 1usize }
            if at < text.len && text[at] == 44u8 { at += 1usize }
        }
        let (copy, copy_error) = mem.alloc[Value](p.a, count)
        if copy_error != ok { ret (zero, at, copy_error) }
        mem.copy[Value](copy, items[..count])
        ret (Value{ Sequence: copy[0..] }, at, ok)
    }
    if text[at] == 123u8 {
        if depth >= usize(p.options.max_depth) { ret (zero, at, TooDeep) }
        var pairs: [64]Pair = zero
        var count = 0usize
        at += 1usize
        while true {
            while at < text.len && text[at] == 32u8 { at += 1usize }
            if at >= text.len { ret (zero, at, Invalid) }
            if text[at] == 125u8 {
                at += 1usize
                break
            }
            if count == 64usize { ret (zero, at, Invalid) }
            let (key, after_key, key_error) = flow_value(p, text, at, depth + 1usize)
            if key_error != ok { ret (zero, at, key_error) }
            at = after_key
            while at < text.len && text[at] == 32u8 { at += 1usize }
            var value: Value = .Null
            if at < text.len && text[at] == 58u8 {
                at += 1usize
                while at < text.len && text[at] == 32u8 { at += 1usize }
                if at < text.len && text[at] != 44u8 && text[at] != 125u8 {
                    let (parsed, after_value, value_error) = flow_value(p, text, at, depth + 1usize)
                    if value_error != ok { ret (zero, at, value_error) }
                    value = parsed
                    at = after_value
                }
            }
            if !p.options.allow_duplicate_keys && has_key(pairs[..count], key) { ret (zero, at, DuplicateKey) }
            pairs[count] = Pair { key: key, value: value }
            count += 1usize
            while at < text.len && text[at] == 32u8 { at += 1usize }
            if at < text.len && text[at] == 44u8 { at += 1usize }
        }
        let (copy, copy_error) = mem.alloc[Pair](p.a, count)
        if copy_error != ok { ret (zero, at, copy_error) }
        mem.copy[Pair](copy, pairs[..count])
        ret (Value{ Mapping: copy[0..] }, at, ok)
    }
    let (stop, stop_error) = scalar_end(text, at, true)
    if stop_error != ok { ret (zero, at, stop_error) }
    let (scalar, scalar_error) = scalar_value(p.a, text[at..stop])
    if scalar_error != ok { ret (zero, at, scalar_error) }
    ret (scalar, stop, ok)
}

fn same_key(a: Value, b: Value) -> bool {
    switch a {
    case .String as x:
        switch b {
        case .String as y:
            ret str.eq(x, y)
        default:
            ret false
        }
    case .Integer as x:
        switch b {
        case .Integer as y:
            ret x == y
        default:
            ret false
        }
    case .Bool as x:
        switch b {
        case .Bool as y:
            ret x == y
        default:
            ret false
        }
    case .Null:
        switch b {
        case .Null:
            ret true
        default:
            ret false
        }
    default:
        ret false
    }
}

fn has_key(pairs: []const Pair, key: Value) -> bool {
    var i = 0usize
    while i < pairs.len {
        if same_key(pairs[i].key, key) { ret true }
        i += 1usize
    }
    ret false
}

// --- Block structure.

// Skips blank lines; false at the end.
fn skip_blank(p: *Parser) -> bool {
    while p.at < p.lines.len && is_blank(p.lines[p.at].text) { p.at += 1usize }
    ret p.at < p.lines.len
}

// A value that begins on this line after `prefix` columns: inline, or on the lines
// below when the rest of the line is empty or a block scalar indicator.
fn parse_inline_or_below(p: *Parser, rest: str, parent_indent: usize, depth: usize) -> (Value, err) {
    let trimmed = str.trim(rest)
    if trimmed.len > 0usize && (trimmed[0] == 124u8 || trimmed[0] == 62u8) {
        p.at += 1usize
        let (block, block_error) = parse_block_scalar(p, trimmed, parent_indent)
        ret (block, block_error)
    }
    if trimmed.len > 0usize {
        p.at += 1usize
        if trimmed[0] == 91u8 || trimmed[0] == 123u8 {
            let (flow, after, flow_error) = flow_value(p, trimmed, 0usize, depth)
            if flow_error != ok { ret (zero, flow_error) }
            if after != trimmed.len { ret (zero, Invalid) }
            ret (flow, ok)
        }
        let (scalar, scalar_error) = scalar_value(p.a, trimmed)
        ret (scalar, scalar_error)
    }
    p.at += 1usize
    if !skip_blank(p) { ret (.Null, ok) }
    if p.lines[p.at].indent > parent_indent {
        let (nested, nested_error) = parse_node(p, p.lines[p.at].indent, depth + 1usize)
        ret (nested, nested_error)
    }
    // A sequence may sit at the parent's own indent under a mapping key.
    if p.lines[p.at].indent == parent_indent && str.starts_with(p.lines[p.at].text, "-") {
        let (nested, nested_error) = parse_node(p, parent_indent, depth + 1usize)
        ret (nested, nested_error)
    }
    ret (.Null, ok)
}

// A literal or folded block: the lines indented past the parent, joined by newlines
// or spaces, chomped as the indicator says.
fn parse_block_scalar(p: *Parser, indicator: str, parent_indent: usize) -> (Value, err) {
    let folded = indicator[0] == 62u8
    var chomp = 0u8
    if indicator.len > 1usize && indicator[1] == 45u8 { chomp = 1u8 }
    if indicator.len > 1usize && indicator[1] == 43u8 { chomp = 2u8 }
    if indicator.len > 2usize || (indicator.len == 2usize && chomp == 0u8) { ret (zero, Invalid) }
    var block_indent = 0usize
    var probe = p.at
    while probe < p.lines.len && is_blank(p.lines[probe].raw) { probe += 1usize }
    if probe < p.lines.len && p.lines[probe].indent > parent_indent { block_indent = p.lines[probe].indent }
    var total = 0usize
    var stop = p.at
    while stop < p.lines.len && (is_blank(p.lines[stop].raw) || p.lines[stop].indent >= block_indent) {
        if block_indent == 0usize && !is_blank(p.lines[stop].raw) { break }
        total += p.lines[stop].raw.len + 1usize
        stop += 1usize
    }
    let (out, out_error) = mem.alloc[u8](p.a, total + 1usize)
    if out_error != ok { ret (zero, out_error) }
    var used = 0usize
    var trailing = 0usize
    var i = p.at
    while i < stop {
        let raw = p.lines[i].raw
        if is_blank(raw) {
            // Folded: the break before the first empty line is the newline it becomes.
            if folded && trailing == 0usize && used > 0usize {
                trailing = 1usize
            } else {
                out[used] = 10u8
                used += 1usize
                trailing += 1usize
            }
        } else {
            let body = raw[block_indent..]
            if folded && trailing == 0usize && used > 0usize && out[used - 1usize] == 10u8 && body.len > 0usize && body[0] != 32u8 {
                out[used - 1usize] = 32u8
            }
            mem.copy[u8](out[used..used + body.len], body)
            used += body.len
            out[used] = 10u8
            used += 1usize
            trailing = 0usize
        }
        i += 1usize
    }
    p.at = stop
    if used == 0usize { ret (Value{ String: "" }, ok) }
    // Chomping: strip keeps no final break, clip one, keep all.
    var stop_at = used
    if chomp != 2u8 {
        while stop_at > 0usize && out[stop_at - 1usize] == 10u8 { stop_at -= 1usize }
        if chomp == 0u8 && stop_at < used { stop_at += 1usize }
    }
    ret (Value{ String: out[..stop_at] }, ok)
}

fn parse_node(p: *Parser, indent: usize, depth: usize) -> (Value, err) {
    if depth > usize(p.options.max_depth) { ret (zero, TooDeep) }
    if !skip_blank(p) { ret (.Null, ok) }
    let first = p.lines[p.at]
    if first.indent != indent { ret (zero, Invalid) }
    if first.text.len > 0usize && first.text[0] == 45u8 && (first.text.len == 1usize || first.text[1] == 32u8) {
        // A sequence at this indent.
        var items: [256]Value = zero
        var count = 0usize
        while skip_blank(p) && p.lines[p.at].indent == indent && p.lines[p.at].text.len > 0usize && p.lines[p.at].text[0] == 45u8 && (p.lines[p.at].text.len == 1usize || p.lines[p.at].text[1] == 32u8) {
            if count == 256usize { ret (zero, Invalid) }
            let text = p.lines[p.at].text
            var rest = ""
            if text.len > 1usize { rest = text[2usize..] }
            let trimmed = str.trim(rest)
            let nested_sequence = trimmed.len > 0usize && trimmed[0] == 45u8 && (trimmed.len == 1usize || trimmed[1] == 32u8)
            if trimmed.len > 0usize && trimmed[0] != 91u8 && trimmed[0] != 123u8 && trimmed[0] != 124u8 && trimmed[0] != 62u8 && trimmed[0] != 34u8 && trimmed[0] != 39u8 {
                let (colon, has_colon) = key_end(trimmed)
                if has_colon || nested_sequence {
                    // The item is a mapping or sequence whose first entry sits on this line.
                    let shifted = indent + 2usize + (text.len - 2usize - str.trim_start(rest).len)
                    p.lines[p.at] = Line { indent: shifted, text: str.trim_start(rest), raw: p.lines[p.at].raw }
                    let (item, item_error) = parse_node(p, shifted, depth + 1usize)
                    if item_error != ok { ret (zero, item_error) }
                    items[count] = item
                    count += 1usize
                    continue
                }
            }
            let (item, item_error) = parse_inline_or_below(p, rest, indent, depth)
            if item_error != ok { ret (zero, item_error) }
            items[count] = item
            count += 1usize
        }
        let (copy, copy_error) = mem.alloc[Value](p.a, count)
        if copy_error != ok { ret (zero, copy_error) }
        mem.copy[Value](copy, items[..count])
        ret (Value{ Sequence: copy[0..] }, ok)
    }
    let (colon, has_colon) = key_end(first.text)
    if has_colon {
        var pairs: [256]Pair = zero
        var count = 0usize
        while skip_blank(p) && p.lines[p.at].indent == indent {
            let text = p.lines[p.at].text
            let (key_stop, is_entry) = key_end(text)
            if !is_entry { ret (zero, Invalid) }
            if count == 256usize { ret (zero, Invalid) }
            let (key, key_error) = scalar_value(p.a, text[..key_stop])
            if key_error != ok { ret (zero, key_error) }
            var rest = ""
            if key_stop + 1usize < text.len { rest = text[key_stop + 1usize..] }
            let (value, value_error) = parse_inline_or_below(p, rest, indent, depth)
            if value_error != ok { ret (zero, value_error) }
            if !p.options.allow_duplicate_keys && has_key(pairs[..count], key) { ret (zero, DuplicateKey) }
            pairs[count] = Pair { key: key, value: value }
            count += 1usize
        }
        if p.at < p.lines.len && !is_blank(p.lines[p.at].text) && p.lines[p.at].indent > indent { ret (zero, Invalid) }
        let (copy, copy_error) = mem.alloc[Pair](p.a, count)
        if copy_error != ok { ret (zero, copy_error) }
        mem.copy[Pair](copy, pairs[..count])
        ret (Value{ Mapping: copy[0..] }, ok)
    }
    // A lone scalar or flow collection.
    let (value, value_error) = parse_inline_or_below(p, first.text, indent, depth)
    ret (value, value_error)
}

// The end of a mapping key on a line: the `:` that ends it, outside quotes and
// followed by a space or the end.
fn key_end(text: str) -> (usize, bool) {
    if text.len == 0usize { ret (0usize, false) }
    if text[0] == 91u8 || text[0] == 123u8 { ret (0usize, false) }
    let (stop, stop_error) = scalar_end(text, 0usize, false)
    if stop_error != ok { ret (0usize, false) }
    var i = stop
    while i < text.len && text[i] == 32u8 { i += 1usize }
    if i < text.len && text[i] == 58u8 && (i + 1usize == text.len || text[i + 1usize] == 32u8) { ret (i, true) }
    ret (0usize, false)
}

fn parse(a: *mem.Arena, source: str, options: Options) -> (Value, err) {
    let (lines, lines_error) = split_lines(a, source)
    if lines_error != ok { ret (zero, lines_error) }
    var p = Parser { a: a, lines: lines, at: 0usize, options: options }
    // Directives and a second document are beyond the subset; one `---` is allowed.
    var i = 0usize
    var markers = 0usize
    while i < lines.len {
        let text = lines[i].text
        if lines[i].indent == 0usize {
            if text.len > 0usize && text[0] == 37u8 { ret (zero, Unsupported) }
            if str.eq(text, "---") || str.starts_with(text, "--- ") {
                markers += 1usize
                if markers > 1usize || i > 0usize && has_content(lines[..i]) { ret (zero, Unsupported) }
                lines[i] = Line { indent: 0usize, text: str.trim(text[3usize..]), raw: lines[i].raw }
            }
            if str.eq(text, "...") { ret (zero, Unsupported) }
        }
        i += 1usize
    }
    if !skip_blank(&p) { ret (.Null, ok) }
    let (root, root_error) = parse_node(&p, p.lines[p.at].indent, 0usize)
    if root_error != ok { ret (zero, root_error) }
    if skip_blank(&p) { ret (zero, Invalid) }
    ret (root, ok)
}

fn has_content(lines: []const Line) -> bool {
    var i = 0usize
    while i < lines.len {
        if !is_blank(lines[i].text) { ret true }
        i += 1usize
    }
    ret false
}

// --- Writing, block style.

fn needs_quotes(text: str) -> bool {
    if text.len == 0usize { ret true }
    let (resolved, resolve_error) = resolve_plain(text)
    var stays_text = false
    switch resolved {
    case .String as same:
        stays_text = true
    default:
        stays_text = false
    }
    if !stays_text { ret true }
    if text[0] == 32u8 || text[text.len - 1usize] == 32u8 { ret true }
    let first = text[0]
    if first == 45u8 || first == 63u8 || first == 58u8 || first == 44u8 || first == 91u8 || first == 93u8 || first == 123u8 || first == 125u8 || first == 35u8 || first == 38u8 || first == 42u8 || first == 33u8 || first == 124u8 || first == 62u8 || first == 39u8 || first == 34u8 || first == 37u8 || first == 64u8 || first == 96u8 { ret true }
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c < 32u8 || c == 34u8 || c == 92u8 { ret true }
        if c == 58u8 && (i + 1usize == text.len || text[i + 1usize] == 32u8) { ret true }
        if c == 35u8 && i > 0usize && text[i - 1usize] == 32u8 { ret true }
        i += 1usize
    }
    ret false
}

fn write_string(writer: *io.Writer, text: str) -> err {
    if !needs_quotes(text) { ret io.write_all(writer, text) }
    try io.write_all(writer, "\"")
    var run = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        var escape = ""
        if c == 34u8 { escape = "\\\"" }
        if c == 92u8 { escape = "\\\\" }
        if c == 10u8 { escape = "\\n" }
        if c == 13u8 { escape = "\\r" }
        if c == 9u8 { escape = "\\t" }
        if escape.len > 0usize {
            try io.write_all(writer, text[run..i])
            try io.write_all(writer, escape)
            run = i + 1usize
        }
        i += 1usize
    }
    try io.write_all(writer, text[run..])
    ret io.write_all(writer, "\"")
}

fn write_scalar(writer: *io.Writer, value: *const Value) -> err {
    var scratch: [64]u8 = zero
    var arena = mem.arena_from(scratch[0..])
    switch *value {
    case .Null:
        ret io.write_all(writer, "null")
    case .Bool as flag:
        if flag { ret io.write_all(writer, "true") }
        ret io.write_all(writer, "false")
    case .Integer as number:
        let (b0, builder_error) = str.builder(&arena, 64usize)
        if builder_error != ok { ret builder_error }
        var b = b0
        try str.push_i64(&b, number)
        ret io.write_all(writer, str.done(&b))
    case .Float as number:
        let (b0, builder_error) = str.builder(&arena, 64usize)
        if builder_error != ok { ret builder_error }
        var b = b0
        try str.push_f64(&b, number)
        let text = str.done(&b)
        if str.eq(text, "inf") { ret io.write_all(writer, ".inf") }
        if str.eq(text, "-inf") { ret io.write_all(writer, "-.inf") }
        if str.eq(text, "nan") { ret io.write_all(writer, ".nan") }
        try io.write_all(writer, text)
        if !str.contains(text, ".") && !str.contains(text, "e") { ret io.write_all(writer, ".0") }
        ret ok
    case .String as text:
        ret write_string(writer, text)
    default:
        ret Invalid
    }
}

fn write_indent(writer: *io.Writer, columns: usize) -> err {
    var i = 0usize
    while i < columns {
        try io.write_all(writer, " ")
        i += 1usize
    }
    ret ok
}

fn is_collection(value: *const Value) -> bool {
    switch *value {
    case .Sequence as items:
        ret items.len > 0usize
    case .Mapping as pairs:
        ret pairs.len > 0usize
    default:
        ret false
    }
}

// Writes `value` where the cursor already stands at column `columns` of a fresh line.
fn write_at(writer: *io.Writer, value: *const Value, columns: usize, indent: usize) -> err {
    switch *value {
    case .Sequence as items:
        if items.len == 0usize { ret io.write_all(writer, "[]\n") }
        var i = 0usize
        while i < items.len {
            if i > 0usize { try write_indent(writer, columns) }
            try io.write_all(writer, "- ")
            if is_collection(&items[i]) {
                try write_at(writer, &items[i], columns + 2usize, indent)
            } else {
                try write_scalar_or_empty(writer, &items[i])
                try io.write_all(writer, "\n")
            }
            i += 1usize
        }
        ret ok
    case .Mapping as pairs:
        if pairs.len == 0usize { ret io.write_all(writer, "{}\n") }
        var i = 0usize
        while i < pairs.len {
            if i > 0usize { try write_indent(writer, columns) }
            try write_scalar(writer, &pairs[i].key)
            try io.write_all(writer, ":")
            if is_collection(&pairs[i].value) {
                try io.write_all(writer, "\n")
                try write_indent(writer, columns + indent)
                try write_at(writer, &pairs[i].value, columns + indent, indent)
            } else {
                try io.write_all(writer, " ")
                try write_scalar_or_empty(writer, &pairs[i].value)
                try io.write_all(writer, "\n")
            }
            i += 1usize
        }
        ret ok
    default:
        try write_scalar(writer, value)
        ret io.write_all(writer, "\n")
    }
}

fn write_scalar_or_empty(writer: *io.Writer, value: *const Value) -> err {
    switch *value {
    case .Sequence as items:
        ret io.write_all(writer, "[]")
    case .Mapping as pairs:
        ret io.write_all(writer, "{}")
    default:
        ret write_scalar(writer, value)
    }
}

fn write(writer: *io.Writer, value: *const Value, indent: u8) -> err {
    if indent == 0u8 { ret Invalid }
    ret write_at(writer, value, 0usize, usize(indent))
}

// --- The typed codec.

fn pair_of(pairs: []const Pair, name: str) -> (Value, bool) {
    var i = 0usize
    while i < pairs.len {
        var matched = false
        switch pairs[i].key {
        case .String as key:
            matched = str.eq(key, name)
        default:
            matched = false
        }
        if matched { ret (pairs[i].value, true) }
        i += 1usize
    }
    ret (.Null, false)
}

fn decode[T: type](a: *mem.Arena, source: str, options: Options) -> (T, err) {
    var out: T = zero
    let (root, parse_error) = parse(a, source, options)
    if parse_error != ok { ret (out, parse_error) }
    var pairs: []const Pair = zero
    switch root {
    case .Mapping as found:
        pairs = found
    default:
        ret (out, Invalid)
    }
    for f in meta.fields[T]() {
        let (found, present) = pair_of(pairs, f.name)
        if present {
            if meta.kind[f.ty]() == .Slice {
                var text = ""
                switch found {
                case .String as written:
                    text = written
                default:
                    ret (out, Invalid)
                }
                meta.set[f, T](&out, text)
            } else {
            if meta.kind[f.ty]() == .Bool {
                var flag = false
                switch found {
                case .Bool as written:
                    flag = written
                default:
                    ret (out, Invalid)
                }
                meta.set[f, T](&out, flag)
            } else {
            if meta.kind[f.ty]() == .Int {
                var number = 0i64
                switch found {
                case .Integer as written:
                    number = written
                default:
                    ret (out, Invalid)
                }
                var slot: f.ty = zero
                slot = f.ty(number)
                meta.set[f, T](&out, slot)
            } else {
            if meta.kind[f.ty]() == .Float {
                var number: f64 = 0.0
                switch found {
                case .Float as written:
                    number = written
                case .Integer as written:
                    number = f64(written)
                default:
                    ret (out, Invalid)
                }
                var slot: f.ty = zero
                slot = f.ty(number)
                meta.set[f, T](&out, slot)
            } else {
                ret (out, Invalid)
            }
            }
            }
            }
        }
    }
    ret (out, ok)
}

fn encode[T: type](writer: *io.Writer, value: *const T) -> err {
    for f in meta.fields[T]() {
        var slot: f.ty = zero
        slot = meta.get[f, T](value)
        try write_string(writer, f.name)
        try io.write_all(writer, ": ")
        if meta.kind[f.ty]() == .Slice {
            try write_string(writer, slot)
        } else {
        if meta.kind[f.ty]() == .Bool {
            let item: Value = Value{ Bool: slot }
            try write_scalar(writer, &item)
        } else {
        if meta.kind[f.ty]() == .Int {
            let item: Value = Value{ Integer: i64(slot) }
            try write_scalar(writer, &item)
        } else {
        if meta.kind[f.ty]() == .Float {
            let item: Value = Value{ Float: f64(slot) }
            try write_scalar(writer, &item)
        } else {
            ret Invalid
        }
        }
        }
        }
        try io.write_all(writer, "\n")
    }
    ret ok
}
