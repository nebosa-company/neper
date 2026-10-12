// `e.net.http2` against the python-hyper libraries (L101): scripts/http2_vectors.py writes header blocks with
// `hpack.Encoder` (Huffman on and off, size updates, never-indexed fields), serialises every frame type with
// `hyperframe`, and takes Neper's own encoder output (golden bytes) only after `hpack.Decoder` has read it back to the
// model's headers. This fixture decodes the library's bytes and re-encodes its own, comparing bytes and header lists.
// Generated from scripts/http2_fixture_template.e; do not edit.
use e.io
use e.mem
use e.net.http2 as h2
use e.os
use e.str

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

fn dec(a: *mem.Arena, n: u64) -> str {
    var buf: [24]u8 = zero
    var at = 24usize
    var v = n
    if v == 0u64 {
        at -= 1usize
        buf[at] = 48u8
    }
    while v > 0u64 {
        at -= 1usize
        buf[at] = 48u8 + u8(v % 10u64)
        v = v / 10u64
    }
    let (out, e) = mem.alloc[u8](a, 24usize - at)
    if e != ok { os.exit(93i32) }
    mem.copy[u8](out, buf[at..24usize])
    ret out
}

fn num(s: str) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < s.len {
        v = v * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
    ret v
}

fn field(rest: *str) -> str {
    let (head, tail, found) = str.split_once(*rest, "\t")
    if !found {
        let all = *rest
        *rest = ""
        ret all
    }
    *rest = tail
    ret head
}

fn item_at(text: str, sep: u8, index: usize) -> (str, bool) {
    var start = 0usize
    var n = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == sep {
            if n == index { ret (text[start..i], true) }
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret ("", false)
}

fn item_count(text: str, sep: u8) -> usize {
    if text.len == 0usize { ret 0usize }
    var n = 1usize
    var i = 0usize
    while i < text.len {
        if text[i] == sep { n += 1usize }
        i += 1usize
    }
    ret n
}

fn err_name(e: err) -> str {
    if e == h2.Incomplete { ret "Incomplete" }
    if e == h2.Invalid { ret "Invalid" }
    if e == h2.FrameSize { ret "FrameSize" }
    if e == h2.Compression { ret "Compression" }
    if e == h2.TooSmall { ret "TooSmall" }
    if e == ok { ret "ok" }
    ret "other"
}

// `hexname=hexvalue,...` (or `-`) into headers.
fn parse_headers(a: *mem.Arena, text: str, out: []h2.Header) -> usize {
    if str.eq(text, "-") { ret 0usize }
    let n = item_count(text, 44u8)
    var i = 0usize
    while i < n {
        let (pair, found) = item_at(text, 44u8, i)
        let (name_hex, value_hex, eq) = str.split_once(pair, "=")
        if !found || !eq { os.exit(96i32) }
        out[i] = h2.Header { name: unhex(a, name_hex), value: unhex(a, value_hex) }
        i += 1usize
    }
    ret n
}

fn same_headers(got: []const h2.Header, want: []const h2.Header) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if !str.eq(got[i].name, want[i].name) || !str.eq(got[i].value, want[i].value) { ret false }
        i += 1usize
    }
    ret true
}

fn new_table(a: *mem.Arena, size: usize) -> h2.Table {
    let (data, data_error) = mem.alloc[u8](a, 8192usize)
    let (lens, lens_error) = mem.alloc[u32](a, 512usize)
    if data_error != ok || lens_error != ok { os.exit(97i32) }
    ret h2.table_new(data, lens, size)
}

fn run_one(a: *mem.Arena, line: str) -> bool {
    var rest = line
    let kind = field(&rest)
    var scratch: [8192]u8 = zero
    var headers: [16]h2.Header = zero
    if str.eq(kind, "H") {
        let size = usize(num(field(&rest)))
        let blocks = field(&rest)
        var table = new_table(a, 4096usize)
        let n = item_count(blocks, 59u8)
        var i = 0usize
        while i < n {
            let (entry, found) = item_at(blocks, 59u8, i)
            let (block_hex, list_text, colon) = str.split_once(entry, ":")
            if !found || !colon { ret false }
            let block = unhex(a, block_hex)
            var want: [16]h2.Header = zero
            let want_count = parse_headers(a, list_text, want[0usize..])
            let (count, e) = h2.decode_block(&table, block, headers[0usize..], scratch[0usize..])
            if e != ok { ret false }
            if !same_headers(headers[0usize..count], want[0usize..want_count]) { ret false }
            i += 1usize
        }
        ret true
    }
    if str.eq(kind, "E") {
        let block = unhex(a, field(&rest))
        let want = field(&rest)
        var table = new_table(a, 4096usize)
        let (count, e) = h2.decode_block(&table, block, headers[0usize..], scratch[0usize..])
        ret str.eq(err_name(e), want)
    }
    if str.eq(kind, "U") {
        let raw = unhex(a, field(&rest))
        let want = field(&rest)
        var encoded: [2048]u8 = zero
        let (n, e) = h2.huffman_encode(raw, encoded[0usize..])
        if e != ok || !str.eq(hex(a, encoded[0usize..n]), want) { ret false }
        if h2.huffman_len(raw) != n { ret false }
        var back: [2048]u8 = zero
        let (m, de) = h2.huffman_decode(encoded[0usize..n], back[0usize..])
        ret de == ok && str.eq(back[0usize..m], raw)
    }
    if str.eq(kind, "I") {
        let prefix = u8(num(field(&rest)))
        let value = num(field(&rest))
        let want = field(&rest)
        var buf: [16]u8 = zero
        var at = 0usize
        let e = h2.write_int(buf[0usize..], &at, value, prefix, 0u8)
        if e != ok || !str.eq(hex(a, buf[0usize..at]), want) { ret false }
        var pos = 0usize
        let (back, re) = h2.read_int(buf[0usize..at], &pos, prefix)
        ret re == ok && back == value && pos == at
    }
    if str.eq(kind, "F") {
        let raw = unhex(a, field(&rest))
        let ftype = u8(num(field(&rest)))
        let flags = u8(num(field(&rest)))
        let stream = u32(num(field(&rest)))
        let payload = field(&rest)
        let (f, used, e) = h2.frame_decode(raw, 16384usize)
        if e != ok || used != raw.len { ret false }
        if f.kind != ftype || f.flags != flags || f.stream != stream || !str.eq(hex(a, f.payload), payload) { ret false }
        var out: [512]u8 = zero
        let (n, ee) = h2.frame_encode(out[0usize..], f.kind, f.flags, f.stream, f.payload)
        ret ee == ok && str.eq(out[0usize..n], raw)
    }
    if str.eq(kind, "R") {
        let raw = unhex(a, field(&rest))
        let want = usize(num(field(&rest)))
        var at = 0usize
        var count = 0usize
        while at < raw.len {
            let (f, used, e) = h2.frame_decode(raw[at..], 16384usize)
            if e != ok { ret false }
            at += used
            count += 1usize
        }
        ret count == want
    }
    if str.eq(kind, "P") {
        let raw = unhex(a, field(&rest))
        let want = field(&rest)
        let (f, used, e) = h2.frame_decode(raw, 16384usize)
        ret str.eq(err_name(e), want)
    }
    if str.eq(kind, "S") {
        let payload = unhex(a, field(&rest))
        let want = field(&rest)
        var settings: [8]h2.Setting = zero
        let (n, e) = h2.settings_decode(payload, settings[0usize..])
        if str.eq(want, "FrameSize") { ret e == h2.FrameSize }
        if e != ok { ret false }
        var text = "-"
        var i = 0usize
        while i < n {
            var item = cat(a, cat(a, dec(a, u64(settings[i].id)), "="), dec(a, u64(settings[i].value)))
            if i == 0usize {
                text = item
            } else {
                text = cat(a, cat(a, text, ","), item)
            }
            i += 1usize
        }
        ret str.eq(text, want)
    }
    if str.eq(kind, "X") {
        let index = num(field(&rest))
        let size = usize(num(field(&rest)))
        let huffman = str.eq(field(&rest), "1")
        let sensitive_text = field(&rest)
        let blocks = field(&rest)
        var sensitive: [4]str = zero
        var sensitive_count = 0usize
        if !str.eq(sensitive_text, "-") {
            sensitive_count = item_count(sensitive_text, 44u8)
            var s = 0usize
            while s < sensitive_count {
                let (one, found) = item_at(sensitive_text, 44u8, s)
                sensitive[s] = unhex(a, one)
                s += 1usize
            }
        }
        var table = new_table(a, size)
        let n = item_count(blocks, 59u8)
        var i = 0usize
        while i < n {
            let (entry, found) = item_at(blocks, 59u8, i)
            let (announce, rest_entry, c1) = str.split_once(entry, ":")
            let (list_text, golden, c2) = str.split_once(rest_entry, ":")
            if !found || !c1 || !c2 { ret false }
            if !str.eq(announce, "-") { h2.table_announce(&table, usize(num(announce))) }
            var want: [16]h2.Header = zero
            let want_count = parse_headers(a, list_text, want[0usize..])
            var out: [4096]u8 = zero
            let (used, e) = h2.encode_block(&table, out[0usize..], want[0usize..want_count], sensitive[0usize..sensitive_count], huffman)
            if e != ok { ret false }
            if golden.len == 0usize {
                var gold = cat(a, "GOLD\t", dec(a, index))
                gold = cat(a, cat(a, gold, "\t"), dec(a, u64(i)))
                gold = cat(a, cat(a, gold, "\t"), hex(a, out[0usize..used]))
                let shown = io.print(cat(a, gold, "\n"))
            } else if !str.eq(hex(a, out[0usize..used]), golden[1usize..]) {
                ret false
            }
            i += 1usize
        }
        ret true
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
    try io.print("net http2 ok")
    ret ok
}
