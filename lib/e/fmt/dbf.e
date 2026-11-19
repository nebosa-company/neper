// dBase III/IV (.dbf) reader as foreign::read.dbf takes it for the common field types: N and F (numeric), C (character), L (logical) and D (date, kept as
// the digits' text length only). Header: records at 4 (u32 LE), header length at 8 and record length at 10 (u16 LE); 32-byte field descriptors from
// offset 32 up to the 0x0D terminator, each with the name (11 bytes), the type at 11, the length at 16 and the decimals at 17; records follow, each with a
// one-byte deletion flag. Deleted records are skipped. Numeric fields are parsed from the padded text, an empty one is missing; a logical is 1 for T/t/Y/y, 0
// for F/f/N/n and missing otherwise; for a character field the value kept is the trimmed text length.
//
// Not here: memo fields, indexes, code pages and write.dbf.

use e.math
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

// foreign::write.dbf. Columns come as kinds 0 double (F), 1 integer (N), 2 logical (L), 3 character or factor (C) and 4 date already formatted yyyymmdd (D); numv holds the numbers
// (NaN for NA), column-major, and strv the text of the kinds 3 and 4. Width and decimals are chosen as write.dbf chooses them (a double is 19 wide with min(19 - (3 or log10 digits + 3), 15)
// decimals; an integer is its widest log10 plus 3, at least the name; a character field the longest text, at least the name, at most 254; a logical 1). Header bytes 1 to 3 (the date)
// are left zero. A missing number is a row of stars, a missing character field NULs, a missing logical '?', a missing date zeros.
fn write_dbf(a: *mem.Arena, nrows: usize, ncols: usize, kinds: []const usize, names: []const str, numv: []const f64, strv: []const str) -> ([]u8, err) {
    var nobytes: []u8 = zero
    let (prec, e1) = mem.alloc[usize](a, ncols)
    let (scale, e2) = mem.alloc[usize](a, ncols)
    if e1 != ok || e2 != ok { ret (nobytes, mem.Full) }
    var rl = 1usize
    var j = 0usize
    while j < ncols {
        let nlen = names[j].len
        let k = kinds[j]
        scale[j] = 0usize
        if k == 2usize { prec[j] = 1usize }
        if k == 4usize { prec[j] = nlen }
        if k == 1usize || k == 0usize {
            var lo = 0.0f64
            var hi = 0.0f64
            var any = false
            var i = 0usize
            while i < nrows {
                let v = numv[j * nrows + i]
                if v == v {
                    if !any || v < lo { lo = v }
                    if !any || v > hi { hi = v }
                    any = true
                }
                i += 1usize
            }
            if k == 1usize {
                if lo == 0.0f64 || hi == 0.0f64 {
                    lo += 1.0f64
                    hi += 1.0f64
                }
                let la = math.ceil[f64](math.log10[f64](math.abs[f64](lo)))
                let ha = math.ceil[f64](math.log10[f64](math.abs[f64](hi)))
                var m = la
                if ha > m { m = ha }
                var p = i64(m) + 3i64
                if p < i64(nlen) { p = i64(nlen) }
                if p > 19i64 { p = 19i64 }
                prec[j] = usize(p)
            } else {
                prec[j] = 19usize
                let la = math.ceil[f64](math.log10[f64](math.abs[f64](lo)))
                let ha = math.ceil[f64](math.log10[f64](math.abs[f64](hi)))
                var m = la
                if ha > m { m = ha }
                var s = 19i64 - 3i64
                if m > 0.0f64 { s = 19i64 - (i64(m) + 3i64) }
                if s > 15i64 { s = 15i64 }
                scale[j] = usize(s)
            }
        }
        if k == 3usize || k == 4usize {
            var p = nlen
            var i = 0usize
            while i < nrows {
                let v = numv[j * nrows + i]
                if v == v && strv[j * nrows + i].len > p { p = strv[j * nrows + i].len }
                i += 1usize
            }
            if p > 254usize { p = 254usize }
            if k == 4usize && p < 8usize { p = 8usize }
            prec[j] = p
        }
        rl += prec[j]
        j += 1usize
    }
    let hl = 33usize + 32usize * ncols
    let (out, e3) = mem.alloc[u8](a, hl + nrows * rl)
    if e3 != ok { ret (nobytes, e3) }
    var q = 0usize
    while q < hl + nrows * rl {
        out[q] = 32u8
        q += 1usize
    }
    q = 0usize
    while q < hl {
        out[q] = 0u8
        q += 1usize
    }
    out[0usize] = 3u8
    out[4usize] = u8(nrows & 255usize)
    out[5usize] = u8(nrows / 256usize & 255usize)
    out[6usize] = u8(nrows / 65536usize & 255usize)
    out[7usize] = u8(nrows / 16777216usize & 255usize)
    out[8usize] = u8(hl & 255usize)
    out[9usize] = u8(hl / 256usize)
    out[10usize] = u8(rl & 255usize)
    out[11usize] = u8(rl / 256usize)
    j = 0usize
    while j < ncols {
        let d = 32usize + 32usize * j
        var c = 0usize
        while c < names[j].len && c < 10usize {
            out[d + c] = names[j][c]
            c += 1usize
        }
        let k = kinds[j]
        var t = 78u8
        if k == 1usize { t = 78u8 }
        if k == 2usize { t = 76u8 }
        if k == 3usize { t = 67u8 }
        if k == 4usize { t = 68u8 }
        out[d + 11usize] = t
        out[d + 16usize] = u8(prec[j])
        out[d + 17usize] = u8(scale[j])
        j += 1usize
    }
    out[hl - 1usize] = 13u8
    var i = 0usize
    while i < nrows {
        var at = hl + i * rl
        out[at] = 32u8
        at += 1usize
        j = 0usize
        while j < ncols {
            let v = numv[j * nrows + i]
            let w = prec[j]
            let k = kinds[j]
            let na = v != v
            if k == 0usize || k == 1usize {
                if na {
                    var c = 0usize
                    while c < w {
                        out[at + c] = 42u8
                        c += 1usize
                    }
                } else {
                    let start = mem.mark(a)
                    let (bb, be) = str.builder(a, 64usize)
                    if be != ok { ret (nobytes, be) }
                    var b = bb
                    if k == 1usize { let _ = str.push_i64(&b, i64(v)) } else { let _ = str.push_f64_fixed(&b, v, u8(scale[j])) }
                    let s = str.done(&b)
                    var c = 0usize
                    while c < s.len && c < w {
                        out[at + w - s.len + c] = s[c]
                        c += 1usize
                    }
                    mem.reset(a, start)
                }
            }
            if k == 2usize {
                if na { out[at] = 63u8 } else if v != 0.0f64 { out[at] = 84u8 } else { out[at] = 70u8 }
            }
            if k == 3usize || k == 4usize {
                var c = 0usize
                if na {
                    while c < w {
                        if k == 4usize { out[at + c] = 48u8 } else { out[at + c] = 0u8 }
                        c += 1usize
                    }
                } else {
                    let s = strv[j * nrows + i]
                    while c < s.len && c < w {
                        out[at + c] = s[c]
                        c += 1usize
                    }
                }
            }
            at += w
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}
