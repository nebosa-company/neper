// dBase III/IV (.dbf) reader as foreign::read.dbf takes it for the common field types: N and F (numeric), C (character), L (logical) and D (date, kept as
// the digits' text length only). Header: records at 4 (u32 LE), header length at 8 and record length at 10 (u16 LE); 32-byte field descriptors from
// offset 32 up to the 0x0D terminator, each with the name (11 bytes), the type at 11, the length at 16 and the decimals at 17; records follow, each with a
// one-byte deletion flag. Deleted records are skipped. Numeric fields are parsed from the padded text, an empty one is missing; a logical is 1 for T/t/Y/y, 0
// for F/f/N/n and missing otherwise; for a character field the value kept is the trimmed text length.
//
// A memo (M) or any other type letter is text (its block number), a date field is days since 1970 (missing for blanks, 00000000 or a day beyond its month). Deleted records are read, as foreign does.
// Not here: the memo file itself, indexes and code pages (foreign reads none of them).

use e.fmt.systat as sys
use e.math
use e.mem
use e.str
use e.time

error Malformed
error TooMany

// kind: 0 numeric, 1 character, 2 logical, 3 date
// names: the field names as read.dbf leaves them (make.names, made unique); dtype: the field type letters (the "data_types" attribute); txt: the text of a character, memo or other-typed field at
// [row * ncols + column], trimmed ("" when missing)
type Dbf = struct { ncols: usize, nrows: usize, kind: []u8, values: []f64, names: []str, dtype: []u8, txt: []str }

fn u16le(b: []const u8, at: usize) -> usize { ret usize(b[at]) + 256usize * usize(b[at + 1usize]) }

fn u32le(b: []const u8, at: usize) -> usize { ret u16le(b, at) + 65536usize * u16le(b, at + 2usize) }

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// words compared against it are lower-case letters, which only a letter of either case matches after this
fn lower(c: u8) -> u8 { ret c | 32u8 }

fn starts_ci(s: []const u8, at: usize, w: str) -> bool {
    if at + w.len > s.len { ret false }
    var i = 0usize
    while i < w.len {
        if lower(s[at + i]) != w[i] { ret false }
        i += 1usize
    }
    ret true
}

// R_atof as shapelib reads a numeric field with it: blanks, an optional sign, then "NA" (missing), NaN, Inf/infinity, or the longest decimal prefix with an optional e exponent;
// text with no digits is missing.
fn atof(a: *mem.Arena, s: []const u8) -> f64 {
    let nan = 0.0f64 / 0.0f64
    var p = 0usize
    while p < s.len && (s[p] == 32u8 || (s[p] >= 9u8 && s[p] <= 13u8)) { p += 1usize }
    if p + 2usize <= s.len && s[p] == 78u8 && s[p + 1usize] == 65u8 { ret nan }
    var start = p
    var neg = false
    if p < s.len && (s[p] == 45u8 || s[p] == 43u8) {
        neg = s[p] == 45u8
        if !neg { start = p + 1usize }
        p += 1usize
    }
    if starts_ci(s, p, "nan") { ret nan }
    if starts_ci(s, p, "inf") {
        if neg { ret -1.0f64 / 0.0f64 }
        ret 1.0f64 / 0.0f64
    }
    var nd = 0usize
    while p < s.len && is_digit(s[p]) {
        p += 1usize
        nd += 1usize
    }
    if p < s.len && s[p] == 46u8 {
        p += 1usize
        while p < s.len && is_digit(s[p]) {
            p += 1usize
            nd += 1usize
        }
    }
    if nd == 0usize { ret nan }
    var q = p
    if q < s.len && (s[q] == 101u8 || s[q] == 69u8) {
        q += 1usize
        if q < s.len && (s[q] == 45u8 || s[q] == 43u8) { q += 1usize }
        let ds = q
        while q < s.len && is_digit(s[q]) { q += 1usize }
        if q == ds { ret nan }
        p = q
    }
    let lit = s[start..p]
    let (v, pe) = str.parse_f64(lit)
    if pe == ok { ret v }
    // parse_f64 wants a digit on both sides of a point: rebuild ".5" and "5." with the missing zero
    let (bb, be) = str.builder(a, lit.len + 4usize)
    if be != ok { ret nan }
    var w = bb
    var i = 0usize
    if i < lit.len && (lit[i] == 45u8 || lit[i] == 43u8) {
        let _ = str.push_byte(&w, lit[i])
        i += 1usize
    }
    if i < lit.len && lit[i] == 46u8 { let _ = str.push_byte(&w, 48u8) }
    while i < lit.len {
        if lit[i] == 43u8 && i > 0usize && (lit[i - 1usize] == 101u8 || lit[i - 1usize] == 69u8) {
            i += 1usize
            continue
        }
        if lit[i] == 69u8 { let _ = str.push_byte(&w, 101u8) } else { let _ = str.push_byte(&w, lit[i]) }
        if lit[i] == 46u8 && (i + 1usize >= lit.len || !is_digit(lit[i + 1usize])) { let _ = str.push_byte(&w, 48u8) }
        i += 1usize
    }
    let (v2, pe2) = str.parse_f64(str.done(&w))
    if pe2 == ok { ret v2 }
    ret nan
}

// a date field read as as.Date(text, "%Y%m%d") reads it: up to four digits of year, two of month, two of day, trailing text ignored, a day beyond its month missing; days since 1970-01-01
fn date_days(s: []const u8) -> f64 {
    let nan = 0.0f64 / 0.0f64
    var at = 0usize
    var y = 0i64
    var m = 0i64
    var d = 0i64
    var f = 0usize
    while f < 3usize {
        var maxd = 2usize
        if f == 0usize { maxd = 4usize }
        while at < s.len && (s[at] == 32u8 || (s[at] >= 9u8 && s[at] <= 13u8)) { at += 1usize }
        var v = 0i64
        var n = 0usize
        while at < s.len && n < maxd && is_digit(s[at]) {
            v = v * 10i64 + i64(s[at] - 48u8)
            at += 1usize
            n += 1usize
        }
        if n == 0usize { ret nan }
        if f == 0usize { y = v }
        if f == 1usize { m = v }
        if f == 2usize { d = v }
        f += 1usize
    }
    if m < 1i64 || m > 12i64 || d < 1i64 { ret nan }
    var dim = 31i64
    if m == 4i64 || m == 6i64 || m == 9i64 || m == 11i64 { dim = 30i64 }
    if m == 2i64 {
        dim = 28i64
        if y % 4i64 == 0i64 && (y % 100i64 != 0i64 || y % 400i64 == 0i64) { dim = 29i64 }
    }
    if d > dim { ret nan }
    ret f64(time.days_from_civil(y, m, d))
}

fn all_zero8(s: []const u8) -> bool {
    if s.len < 8usize { ret false }
    var i = 0usize
    while i < 8usize {
        if s[i] != 48u8 { ret false }
        i += 1usize
    }
    ret true
}

// The way foreign's Rdbfread reads the table through shapelib: the field count is (header length - 32) / 32, every record is read (a deletion mark is not looked at), a field is the bytes up to
// its first NUL with leading and trailing blanks trimmed, and a numeric field is R_atof of the untrimmed bytes, truncated to an integer while its column is an integer one and every value fits.
fn parse(a: *mem.Arena, b: []const u8) -> (Dbf, err) {
    var out: Dbf = zero
    if b.len < 33usize { ret (out, Malformed) }
    let nrec = u32le(b, 4usize)
    let hlen = u16le(b, 8usize)
    let reclen = u16le(b, 10usize)
    if hlen <= 32usize || hlen > b.len { ret (out, Malformed) }
    let cols = (hlen - 32usize) / 32usize
    if cols > 128usize { ret (out, TooMany) }
    let (kind, e1) = mem.alloc[u8](a, 128usize)
    if e1 != ok { ret (out, e1) }
    let (flen, e2) = mem.alloc[usize](a, 128usize)
    if e2 != ok { ret (out, e2) }
    let (isint, e4) = mem.alloc[bool](a, 128usize)
    if e4 != ok { ret (out, e4) }
    var c0 = 0usize
    while c0 < cols {
        let p = 32usize + 32usize * c0
        let t = b[p + 11usize]
        var k = 1u8
        if t == 78u8 || t == 70u8 { k = 0u8 }
        if t == 76u8 { k = 2u8 }
        if t == 68u8 { k = 3u8 }
        kind[c0] = k
        flen[c0] = usize(b[p + 16usize])
        isint[c0] = k == 0u8 && b[p + 17usize] == 0u8
        c0 += 1usize
    }
    let (vals, e3) = mem.alloc[f64](a, nrec * cols + 1usize)
    if e3 != ok { ret (out, e3) }
    let (txt, e5) = mem.alloc[str](a, nrec * cols + 1usize)
    if e5 != ok { ret (out, e5) }
    var ti = 0usize
    while ti < nrec * cols + 1usize {
        txt[ti] = ""
        ti += 1usize
    }
    let (names, e6) = mem.alloc[str](a, cols + 1usize)
    let (dtype, e7) = mem.alloc[u8](a, cols + 1usize)
    if e6 != ok || e7 != ok { ret (out, mem.Full) }
    var nc0 = 0usize
    while nc0 < cols {
        let p = 32usize + 32usize * nc0
        dtype[nc0] = b[p + 11usize]
        // shapelib's name: up to 11 bytes or the first NUL, trailing blanks dropped
        var ne = p
        while ne < p + 11usize && b[ne] != 0u8 { ne += 1usize }
        while ne > p + 1usize && b[ne - 1usize] == 32u8 { ne -= 1usize }
        let (nm, me) = sys.make_name(a, b[p..ne])
        if me != ok { ret (out, me) }
        names[nc0] = nm
        nc0 += 1usize
    }
    let ue = sys.make_unique(a, names, cols)
    if ue != ok { ret (out, ue) }
    var r = 0usize
    while r < nrec {
        let base = hlen + r * reclen
        if base + reclen > b.len { ret (out, Malformed) }
        var off = base + 1usize
        var c = 0usize
        while c < cols {
            let n = flen[c]
            var z = off
            while z < off + n && b[z] != 0u8 { z += 1usize }
            var s = off
            var e = z
            while s < e && b[s] == 32u8 { s += 1usize }
            while e > s && b[e - 1usize] == 32u8 { e -= 1usize }
            var v = 0.0f64 / 0.0f64
            if kind[c] == 0u8 {
                if e > s && b[s] != 42u8 {
                    v = atof(a, b[off..z])
                    if isint[c] && v == v {
                        if v > 2147483647.0f64 || v < -2147483646.0f64 {
                            isint[c] = false
                        } else {
                            v = math.trunc[f64](v)
                        }
                    }
                }
            } else if kind[c] == 2u8 {
                if e > s && b[s] != 63u8 {
                    let ch = b[s]
                    if ch == 84u8 || ch == 116u8 || ch == 89u8 || ch == 121u8 { v = 1.0f64 }
                    if ch == 70u8 || ch == 102u8 || ch == 78u8 || ch == 110u8 { v = 0.0f64 }
                }
            } else if kind[c] == 3u8 {
                if e > s && !all_zero8(b[s..e]) { v = date_days(b[s..e]) }
            } else if e > s {
                v = f64(e - s)
                txt[r * cols + c] = b[s..e]
            }
            vals[r * cols + c] = v
            off += n
            c += 1usize
        }
        r += 1usize
    }
    out.ncols = cols
    out.nrows = nrec
    out.kind = kind[0usize..cols]
    out.values = vals
    out.names = names
    out.dtype = dtype
    out.txt = txt
    ret (out, ok)
}

// read.dbf(as.is = FALSE): a character column as a factor, the codes 1-based among the distinct texts sorted bytewise (the C locale; R sorts in its session locale), 0 for missing, and the levels
fn factor(a: *mem.Arena, d: Dbf, col: usize) -> ([]f64, []str, err) {
    var nolev: []str = zero
    let (codes, e1) = mem.alloc[f64](a, d.nrows + 1usize)
    let (lv, e2) = mem.alloc[str](a, d.nrows + 1usize)
    if e1 != ok || e2 != ok { ret (codes, nolev, mem.Full) }
    var nl = 0usize
    var r = 0usize
    while r < d.nrows {
        let x = d.txt[r * d.ncols + col]
        if x.len > 0usize {
            var found = false
            var k = 0usize
            while k < nl {
                if str.eq(lv[k], x) { found = true }
                k += 1usize
            }
            if !found {
                lv[nl] = x
                nl += 1usize
            }
        }
        r += 1usize
    }
    // insertion sort, bytewise
    var i = 1usize
    while i < nl {
        let x = lv[i]
        var j = i
        while j > 0usize && str_less(x, lv[j - 1usize]) {
            lv[j] = lv[j - 1usize]
            j -= 1usize
        }
        lv[j] = x
        i += 1usize
    }
    r = 0usize
    while r < d.nrows {
        let x = d.txt[r * d.ncols + col]
        codes[r] = 0.0f64
        var k = 0usize
        while k < nl {
            if x.len > 0usize && str.eq(lv[k], x) { codes[r] = f64(k + 1usize) }
            k += 1usize
        }
        r += 1usize
    }
    ret (codes, lv[0usize..nl], ok)
}

fn str_less(a: str, b: str) -> bool {
    var i = 0usize
    while i < a.len && i < b.len {
        if a[i] != b[i] { ret a[i] < b[i] }
        i += 1usize
    }
    ret a.len < b.len
}

// foreign::write.dbf. Columns come as kinds 0 double (F), 1 integer (N), 2 logical (L), 3 character or factor (C) and 4 date already formatted yyyymmdd (D); numv holds the numbers
// (NaN for NA), column-major, and strv the text of the kinds 3 and 4. Width and decimals are chosen as write.dbf chooses them (a double is 19 wide with min(19 - (3 or log10 digits + 3), 15)
// decimals; an integer is its widest log10 plus 3, at least the name; a character field the longest text, at least the name, at most max_nchar (write.dbf's default is 254); a logical 1).
// Kind 3 also stands for a factor written as text (factor2char = TRUE); kind 5 is a factor written as its integer codes (factor2char = FALSE), taken as kind 1. Header bytes 1 to 3 (the date)
// are left zero. A missing number is a row of stars, a missing character field NULs, a missing logical '?', a missing date zeros.
fn write_dbf(a: *mem.Arena, nrows: usize, ncols: usize, kinds_in: []const usize, names: []const str, numv: []const f64, strv: []const str, max_nchar: usize) -> ([]u8, err) {
    var nobytes: []u8 = zero
    let (kinds, e0) = mem.alloc[usize](a, ncols)
    if e0 != ok { ret (nobytes, mem.Full) }
    var j0 = 0usize
    while j0 < ncols {
        kinds[j0] = kinds_in[j0]
        if kinds[j0] == 5usize { kinds[j0] = 1usize }
        j0 += 1usize
    }
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
            if p > max_nchar { p = max_nchar }
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
