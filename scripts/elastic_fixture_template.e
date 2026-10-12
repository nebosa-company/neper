// `x.elastic.rest` against elasticsearch-py (L114): scripts/elastic_vectors.py gives URL-part and query-string quoting
// from the client's own `_quote`/`_quote_query`, the `_bulk` action lines from `expand_action` serialized by
// elastic-transport's NDJSON serializer, and response shapes from a model (the client returns decoded JSON as is).
// This fixture encodes and parses the same inputs and compares bytes and text.
// Generated from scripts/elastic_fixture_template.e; do not edit.
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.elastic.rest as rest

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(a: *mem.Arena, h: str) -> []u8 {
    let (out, e) = mem.alloc[u8](a, h.len / 2usize + 1usize)
    if e != ok { os.exit(90i32) }
    var i = 0usize
    while i + 1usize < h.len {
        out[i / 2usize] = (nibble(h[i]) << 4u8) | nibble(h[i + 1usize])
        i += 2usize
    }
    ret out[0usize..h.len / 2usize]
}

fn hex(a: *mem.Arena, b: []const u8) -> str {
    let digits = "0123456789abcdef"
    let (out, e) = mem.alloc[u8](a, b.len * 2usize + 1usize)
    if e != ok { os.exit(91i32) }
    var i = 0usize
    while i < b.len {
        out[i * 2usize] = digits[usize(b[i] >> 4u8)]
        out[i * 2usize + 1usize] = digits[usize(b[i] & 15u8)]
        i += 1usize
    }
    ret out[0usize..b.len * 2usize]
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(92i32) }
    ret out
}

fn dec(a: *mem.Arena, n: i64) -> str {
    let negative = n < 0i64
    var magnitude = 0u64
    if negative {
        magnitude = u64(0i64 - (n + 1i64)) + 1u64
    } else {
        magnitude = u64(n)
    }
    var buf: [24]u8 = zero
    var at = 24usize
    if magnitude == 0u64 {
        at -= 1usize
        buf[at] = 48u8
    }
    while magnitude > 0u64 {
        at -= 1usize
        buf[at] = 48u8 + u8(magnitude % 10u64)
        magnitude = magnitude / 10u64
    }
    if negative {
        at -= 1usize
        buf[at] = 45u8
    }
    let (out, e) = mem.alloc[u8](a, 24usize - at)
    if e != ok { os.exit(93i32) }
    mem.copy[u8](out, buf[at..24usize])
    ret out
}

fn num(s: str) -> i64 {
    var negative = false
    var i = 0usize
    if s.len > 0usize && s[0usize] == 45u8 {
        negative = true
        i = 1usize
    }
    var magnitude = 0u64
    while i < s.len {
        magnitude = magnitude * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
    if negative { ret 0i64 - i64(magnitude) }
    ret i64(magnitude)
}

fn field(rest_text: *str) -> str {
    let (head, tail, found) = str.split_once(*rest_text, "\t")
    if !found {
        let all = *rest_text
        *rest_text = ""
        ret all
    }
    *rest_text = tail
    ret head
}

// Comma-separated items; `-` stands for an absent one. Calls `on_item` semantics inline via the caller's arrays.
fn split_items(a: *mem.Arena, text: str, out: [][]const u8, present: []bool) -> usize {
    var count = 0usize
    var cursor = text
    while cursor.len > 0usize {
        let (item, tail, more) = str.split_once(cursor, ",")
        var current = cursor
        if more {
            current = item
            cursor = tail
        } else {
            cursor = ""
        }
        if str.eq(current, "-") {
            present[count] = false
            out[count] = ""
        } else {
            present[count] = true
            out[count] = unhex(a, current)
        }
        count += 1usize
    }
    ret count
}

// The `index`th comma-separated item of `text` (empty when there is none).
fn item_at(text: str, index: usize) -> str {
    var start = 0usize
    var n = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 44u8 {
            if n == index { ret text[start..i] }
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret ""
}

fn run_one(a: *mem.Arena, line: str) -> bool {
    var rest_text = line
    let kind = field(&rest_text)
    var buf: [2048]u8 = zero
    if str.eq(kind, "Q") {
        let value = unhex(a, field(&rest_text))
        let want = field(&rest_text)
        var at = 0usize
        let e = rest.quote(buf[0usize..], &at, value, ",*")
        ret e == ok && str.eq(hex(a, buf[0usize..at]), want)
    }
    if str.eq(kind, "P") {
        var parts: [8][]const u8 = zero
        var present: [8]bool = zero
        let n = split_items(a, field(&rest_text), parts[0usize..], present[0usize..])
        let want = field(&rest_text)
        var segments: [8]str = zero
        var i = 0usize
        while i < n {
            segments[i] = ""
            if present[i] { segments[i] = parts[i] }
            i += 1usize
        }
        let (used, e) = rest.path(buf[0usize..], segments[0usize..n])
        ret e == ok && str.eq(hex(a, buf[0usize..used]), want)
    }
    if str.eq(kind, "Z") {
        let list_text = field(&rest_text)
        let want = field(&rest_text)
        var params: [8]rest.Param = zero
        var n = 0usize
        var cursor = list_text
        if str.eq(list_text, "-") { cursor = "" }
        while cursor.len > 0usize {
            let (item, tail, more) = str.split_once(cursor, ",")
            var current = cursor
            if more {
                current = item
                cursor = tail
            } else {
                cursor = ""
            }
            let (name_hex, value_hex, colon) = str.split_once(current, ":")
            if !colon { os.exit(96i32) }
            params[n] = rest.Param { name: unhex(a, name_hex), value: unhex(a, value_hex) }
            n += 1usize
        }
        let (used, e) = rest.query(buf[0usize..], params[0usize..n])
        ret e == ok && str.eq(hex(a, buf[0usize..used]), want)
    }
    if str.eq(kind, "B") {
        let op = field(&rest_text)
        let spec = field(&rest_text)
        let source = unhex(a, field(&rest_text))
        let want = field(&rest_text)
        var values: [9][]const u8 = zero
        var present: [9]bool = zero
        let n = split_items(a, spec, values[0usize..], present[0usize..])
        var m = rest.meta()
        if present[0usize] { m.id = values[0usize] }
        if present[1usize] { m.index = values[1usize] }
        if present[2usize] { m.if_seq_no = num(item_at(spec, 2usize)) }
        if present[3usize] { m.if_primary_term = num(item_at(spec, 3usize)) }
        if present[4usize] { m.retry_on_conflict = num(item_at(spec, 4usize)) }
        if present[5usize] { m.routing = values[5usize] }
        if present[6usize] { m.version = num(item_at(spec, 6usize)) }
        if present[7usize] { m.version_type = values[7usize] }
        if present[8usize] { m.pipeline = values[8usize] }
        let (big, big_error) = mem.alloc[u8](a, 4096usize)
        if big_error != ok { os.exit(99i32) }
        let (used, e) = rest.bulk_line(big, op, &m, source)
        ret e == ok && str.eq(hex(a, big[0usize..used]), want)
    }
    if str.eq(kind, "R") {
        let body = unhex(a, field(&rest_text))
        let want = field(&rest_text)
        let (r, e) = rest.parse_bulk(a, body)
        if str.eq(want, "Invalid") { ret e == rest.Invalid }
        if e != ok { ret false }
        var s = cat(a, cat(a, dec(a, r.took), "|"), "0")
        if r.errors { s = cat(a, cat(a, dec(a, r.took), "|"), "1") }
        s = cat(a, s, "|")
        var i = 0usize
        while i < r.items.len {
            let it = r.items[i]
            if i > 0usize { s = cat(a, s, ";") }
            s = cat(a, s, hex(a, it.op))
            s = cat(a, cat(a, s, ":"), hex(a, it.index))
            s = cat(a, cat(a, s, ":"), hex(a, it.id))
            s = cat(a, cat(a, s, ":"), dec(a, it.status))
            s = cat(a, cat(a, s, ":"), hex(a, it.result))
            s = cat(a, cat(a, s, ":"), hex(a, it.error_type))
            s = cat(a, cat(a, s, ":"), hex(a, it.error_reason))
            s = cat(a, cat(a, s, ":"), dec(a, it.version))
            i += 1usize
        }
        ret str.eq(s, want)
    }
    if str.eq(kind, "S") {
        let body = unhex(a, field(&rest_text))
        let want = field(&rest_text)
        let (r, e) = rest.parse_search(a, body)
        if str.eq(want, "Invalid") { ret e == rest.Invalid }
        if e != ok { ret false }
        var flag = "0"
        if r.timed_out { flag = "1" }
        var s = cat(a, cat(a, cat(a, dec(a, r.took), "|"), flag), "|")
        s = cat(a, cat(a, s, dec(a, r.total)), "|")
        s = cat(a, cat(a, s, hex(a, r.relation)), "|")
        s = cat(a, cat(a, s, hex(a, r.scroll_id)), "|")
        s = cat(a, cat(a, s, dec(a, r.shards_failed)), "|")
        var i = 0usize
        while i < r.hits.len {
            let h = r.hits[i]
            if i > 0usize { s = cat(a, s, ";") }
            s = cat(a, s, hex(a, h.index))
            s = cat(a, cat(a, s, ":"), hex(a, h.id))
            s = cat(a, s, ":")
            if h.has_score {
                let bits = mem.bitcast[u64](h.score)
                var raw: [8]u8 = zero
                var b = 0usize
                while b < 8usize {
                    raw[b] = u8((bits >> (56u64 - u64(b) * 8u64)) & 255u64)
                    b += 1usize
                }
                s = cat(a, s, hex(a, raw[0usize..8usize]))
            } else {
                s = cat(a, s, "-")
            }
            s = cat(a, s, ":")
            switch h.source {
            case .Object as members:
                s = cat(a, cat(a, s, "m"), dec(a, i64(members.len)))
            default:
                s = cat(a, s, "x")
            }
            i += 1usize
        }
        ret str.eq(s, want)
    }
    if str.eq(kind, "E") {
        let body = unhex(a, field(&rest_text))
        let want = field(&rest_text)
        let (r, e) = rest.parse_error(a, body)
        if str.eq(want, "Invalid") { ret e == rest.Invalid }
        if e != ok { ret false }
        var s = cat(a, dec(a, r.status), "|")
        s = cat(a, cat(a, s, hex(a, r.kind)), "|")
        s = cat(a, cat(a, s, hex(a, r.reason)), "|")
        s = cat(a, cat(a, s, hex(a, r.root_kind)), "|")
        s = cat(a, s, hex(a, r.root_reason))
        ret str.eq(s, want)
    }
    ret false
}

//__VECTOR_FUNCTIONS__
fn fail(line: str) {
    let shown = io.print(line)
}

fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            if !run_one(a, line) {
                fail(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("x elastic rest ok")
    ret ok
}
