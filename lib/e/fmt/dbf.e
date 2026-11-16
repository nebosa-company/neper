// dBase III/IV (.dbf) reader as foreign::read.dbf takes it for the common field types: N and F (numeric), C (character), L (logical) and D (date, kept as
// the digits' text length only). Header: records at 4 (u32 LE), header length at 8 and record length at 10 (u16 LE); 32-byte field descriptors from
// offset 32 up to the 0x0D terminator, each with the name (11 bytes), the type at 11, the length at 16 and the decimals at 17; records follow, each with a
// one-byte deletion flag. Deleted records are skipped. Numeric fields are parsed from the padded text, an empty one is missing; a logical is 1 for T/t/Y/y, 0
// for F/f/N/n and missing otherwise; for a character field the value kept is the trimmed text length.
//
// Not here: memo fields, indexes, code pages and write.dbf.

use e.mem
use e.str

error Malformed
error TooMany

// kind: 0 numeric, 1 character, 2 logical, 3 date
type Dbf = struct { ncols: usize, nrows: usize, kind: []u8, values: []f64 }

fn u16le(b: []const u8, at: usize) -> usize { ret usize(b[at]) + 256usize * usize(b[at + 1usize]) }

fn u32le(b: []const u8, at: usize) -> usize { ret u16le(b, at) + 65536usize * u16le(b, at + 2usize) }

fn parse(a: *mem.Arena, b: []const u8) -> (Dbf, err) {
    var out: Dbf = zero
    if b.len < 33usize { ret (out, Malformed) }
    let nrec = u32le(b, 4usize)
    let reclen = u16le(b, 10usize)
    let (kind, e1) = mem.alloc[u8](a, 128usize)
    if e1 != ok { ret (out, e1) }
    let (flen, e2) = mem.alloc[usize](a, 128usize)
    if e2 != ok { ret (out, e2) }
    var cols = 0usize
    var p = 32usize
    while p < b.len && b[p] != 13u8 {
        if cols >= 128usize { ret (out, TooMany) }
        let t = b[p + 11usize]
        var k = 1u8
        if t == 78u8 || t == 70u8 { k = 0u8 }
        if t == 76u8 { k = 2u8 }
        if t == 68u8 { k = 3u8 }
        kind[cols] = k
        flen[cols] = usize(b[p + 16usize])
        cols += 1usize
        p += 32usize
    }
    let data = p + 1usize
    let (vals, e3) = mem.alloc[f64](a, nrec * cols + 1usize)
    if e3 != ok { ret (out, e3) }
    var r = 0usize
    var rows = 0usize
    while r < nrec {
        let base = data + r * reclen
        if base + reclen > b.len { ret (out, Malformed) }
        if b[base] != 42u8 {
            var off = base + 1usize
            var c = 0usize
            while c < cols {
                let n = flen[c]
                var s = off
                var e = off + n
                while s < e && b[s] == 32u8 { s += 1usize }
                while e > s && b[e - 1usize] == 32u8 { e -= 1usize }
                var v = 0.0f64 / 0.0f64
                if kind[c] == 0u8 {
                    if e > s {
                        let (x, pe) = str.parse_f64(b[s..e])
                        if pe == ok { v = x }
                    }
                } else if kind[c] == 2u8 {
                    if e > s {
                        let ch = b[s]
                        if ch == 84u8 || ch == 116u8 || ch == 89u8 || ch == 121u8 { v = 1.0f64 }
                        if ch == 70u8 || ch == 102u8 || ch == 78u8 || ch == 110u8 { v = 0.0f64 }
                    }
                } else {
                    v = f64(e - s)
                }
                vals[rows * cols + c] = v
                off += n
                c += 1usize
            }
            rows += 1usize
        }
        r += 1usize
    }
    out.ncols = cols
    out.nrows = rows
    out.kind = kind[0usize..cols]
    out.values = vals
    ret (out, ok)
}
