// `e.fmt.woff` and `e.fmt.woff2` against Vaper's own decoders (woff_decoder_io.dart, woff2_decoder.dart): scripts/
// woff_vectors.mjs builds random fonts (zlib tables, Brotli-compressed transformed glyf/loca/hmtx) and, per case, the
// sfnt Vaper's Dart answers as hex (`e`, or null where it refuses). The fixture decodes the same input and compares.
use e.algo.ir as ir
use e.fmt.json as json
use e.fmt.woff as woff
use e.fmt.woff2 as woff2
use e.io
use e.mem
use e.os
use e.str

fn text_of(v: json.Value, key: str) -> (str, bool) {
    let (x, found) = ir.get(v, key)
    if !found { ret ("", false) }
    let (s, is_text) = ir.string_of(x)
    ret (s, is_text)
}

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

fn run_one(a: *mem.Arena, c: json.Value) -> bool {
    let (kind, k1) = text_of(c, "k")
    let (hex, k2) = text_of(c, "h")
    let (want, has_want) = text_of(c, "e")
    let input = unhex(a, hex)
    var got: []u8 = zero
    var e: err = ok
    if str.eq(kind, "woff") {
        let (g, ge) = woff.to_sfnt(a, input)
        got = g
        e = ge
    } else {
        let (g, ge) = woff2.to_sfnt(a, input)
        got = g
        e = ge
    }
    if !has_want { ret e != ok }
    if e != ok { ret false }
    let expected = unhex(a, want)
    if expected.len != got.len { ret false }
    var i = 0usize
    while i < got.len {
        if expected[i] != got[i] { ret false }
        i += 1usize
    }
    ret true
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: false, max_depth: 60u16 })
            if parse_error != ok || !run_one(a, root) {
                let shown = io.print(line)
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
    try io.print("fmt woff ok")
    ret ok
}
