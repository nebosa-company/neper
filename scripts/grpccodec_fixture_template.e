// `e.net.grpccodec` against Python's gzip and zlib: scripts/grpccodec_vectors.py compresses random and structured bodies
// (every level, with and without a gzip file name, stored blocks, a single byte, an empty body, 70000 bytes) and corrupts
// some; each line says which encoding, the compressed bytes, the limit and what `inflate` must answer -- the original
// bytes (hex, or length and hash past 1024 bytes) or the codec's error. Generated; do not edit.
use e.algo.deflate as deflate
use e.fmt.gzip as gzip
use e.fmt.zlib as zlib
use e.io
use e.mem
use e.net.grpccodec as codec
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

fn pay(a: *mem.Arena, p: []const u8) -> str {
    if p.len <= 1024usize { ret hex(a, p) }
    var h = 0u64
    var i = 0usize
    while i < p.len {
        h = (h * 31u64 + u64(p[i])) & 4294967295u64
        i += 1usize
    }
    ret cat(a, cat(a, cat(a, "L", dec(a, u64(p.len))), "."), dec(a, h))
}

fn error_name(e: err) -> str {
    if e == gzip.Invalid { ret "gzip.Invalid" }
    if e == gzip.Checksum { ret "gzip.Checksum" }
    if e == zlib.Invalid { ret "zlib.Invalid" }
    if e == zlib.Checksum { ret "zlib.Checksum" }
    if e == deflate.Invalid { ret "deflate.Invalid" }
    if e == deflate.TooLarge { ret "TooLarge" }
    if e == codec.Unsupported { ret "Unsupported" }
    if e == io.TooSmall { ret "TooSmall" }
    ret "other"
}

fn run_one(a: *mem.Arena, line: str) -> bool {
    var rest = line
    let kind = field(&rest)
    if str.eq(kind, "Z") {
        let name = field(&rest)
        let encoding = field(&rest)
        let input = unhex(a, field(&rest))
        let limit = usize(num(field(&rest)))
        let want = field(&rest)
        let (body, e) = codec.inflate(a, encoding, input, limit)
        var got = ""
        if e == ok { got = cat(a, "ok:", pay(a, body)) } else { got = error_name(e) }
        if !str.eq(got, want) {
            let shown = io.print(cat(a, cat(a, cat(a, cat(a, name, " got "), got), " want "), cat(a, want, "\n")))
            ret false
        }
        ret true
    }
    ret false
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            if !run_one(a, line) { ret 1u8 }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("net grpccodec ok")
    ret ok
}
