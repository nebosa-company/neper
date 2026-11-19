// Minitab portable worksheet reader as foreign::read.mtp takes it (minitab.c). The first line must begin "Minitab Portable Worksheet "; each entry is a record line
// "%" + four 7-wide integers (type, column number, length, data type) + one blank + an 8-character name, then `length` numbers read as C's %lg reads them (blank separated, over lines),
// then the rest of that line. Data type 0 is numeric; a matrix (type 4) has the number of columns in its data type field and is returned with length / columns rows; any other
// data type is an error ("non-numeric data types are not yet implemented"). Every number is rounded to 6 significant digits, as read.mtp's signif(x, 6L) does.
// Lines are read the way fgets(buf, 85) reads them, so the end of the file is met where C meets it: an entry whose record line is the last line without a newline is not read.
// Hexadecimal numbers (0x1A, 0x1.8p3) are read as %lg reads them; the rounding is R's fprec, including its branch for numbers beyond 1e306 or below 1e-306.

use e.fmt.dbf as dbf
use e.math
use e.mem

error Malformed
error NonNumeric

// kind: 0 vector, 1 matrix. A name is src[nameat..nameat + namelen]; the values of entry i are vals[i]; a matrix is column-major with nrow rows
type Mtp = struct { n: usize, kind: []u8, nrow: []usize, ncol: []usize, nameat: []usize, namelen: []usize, vals: [][]f64, src: []const u8 }

type Rd = struct { b: []const u8, pos: usize, eof: bool }

fn is_space(c: u8) -> bool { ret c == 32u8 || (c >= 9u8 && c <= 13u8) }

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// fgets(buf, 85, f): up to 84 bytes or through a newline; (start, end, got)
fn fgets(r: *Rd) -> (usize, usize, bool) {
    let b = r.b
    if r.pos >= b.len {
        r.eof = true
        ret (0usize, 0usize, false)
    }
    let start = r.pos
    var n = 0usize
    var nl = false
    while r.pos < b.len && n < 84usize && !nl {
        if b[r.pos] == 10u8 { nl = true }
        r.pos += 1usize
        n += 1usize
    }
    if !nl && n < 84usize && r.pos >= b.len { r.eof = true }
    ret (start, r.pos, true)
}

fn rint(x: f64) -> f64 {
    let f = math.floor[f64](x)
    let d = x - f
    if d < 0.5f64 { ret f }
    if d > 0.5f64 { ret f + 1.0f64 }
    var h = f / 2.0f64
    if math.floor[f64](h) == h { ret f }
    ret f + 1.0f64
}

fn pow_di10(n: i64) -> f64 {
    var x = 10.0f64
    var m = n
    var neg = false
    if m < 0i64 {
        neg = true
        m = 0i64 - m
    }
    var xn = 1.0f64
    while true {
        if (m & 1i64) != 0i64 { xn = xn * x }
        m = m / 2i64
        if m > 0i64 { x = x * x } else { break }
    }
    if neg { ret 1.0f64 / xn }
    ret xn
}

// signif(x, 6): R's fprec (digits 6, MAX_DIGITS 22)
fn signif6(x0: f64) -> f64 {
    if x0 != x0 || x0 == 0.0f64 || x0 > 1.7976931348623157e308f64 || x0 < -1.7976931348623157e308f64 { ret x0 }
    var sgn = 1.0f64
    var x = x0
    if x < 0.0f64 {
        sgn = -1.0f64
        x = 0.0f64 - x
    }
    let l10 = math.log10[f64](x)
    var e10 = 5i64 - i64(math.floor[f64](l10))
    // max10e is DBL_MAX_EXP * log10(2) = 308.2547
    if l10 < 306.25471555991675f64 && l10 > -306.25471555991675f64 {
        var p10 = 1.0f64
        if e10 > 308i64 {
            p10 = pow_di10(e10 - 308i64)
            e10 = 308i64
        }
        if e10 > 0i64 {
            let pw = pow_di10(e10)
            ret sgn * (rint((x * pw) * p10) / pw) / p10
        }
        let pw = pow_di10(0i64 - e10)
        ret sgn * (rint(x / pw) * pw)
    }
    let do_round = 308.25471555991675f64 - l10 >= pow_di10(-6i64)
    var e2 = 6i64 - 22i64
    if e10 > 0i64 { e2 = 6i64 + 22i64 }
    let p10 = pow_di10(e2)
    x = x * p10
    let pp = pow_di10(e10 - e2)
    x = x * pp
    if do_round { x += 0.5f64 }
    x = math.floor[f64](x) / p10
    ret sgn * x / pp
}

fn hexd(c: u8) -> i64 {
    if c >= 48u8 && c <= 57u8 { ret i64(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret i64(c - 87u8) }
    if c >= 65u8 && c <= 70u8 { ret i64(c - 55u8) }
    ret 0i64 - 1i64
}

// fscanf(f, "%lg"): (value, got a number, end of file before one)
fn scan_double(a: *mem.Arena, r: *Rd) -> (f64, bool, bool) {
    let b = r.b
    var p = r.pos
    while p < b.len && is_space(b[p]) { p += 1usize }
    if p >= b.len {
        r.pos = p
        r.eof = true
        ret (0.0f64, false, true)
    }
    let start = p
    var q = p
    if b[q] == 45u8 || b[q] == 43u8 { q += 1usize }
    var ok_num = false
    if q + 3usize <= b.len && (b[q] | 32u8) == 105u8 && (b[q + 1usize] | 32u8) == 110u8 && (b[q + 2usize] | 32u8) == 102u8 {
        q += 3usize
        ok_num = true
    } else if q + 3usize <= b.len && (b[q] | 32u8) == 110u8 && (b[q + 1usize] | 32u8) == 97u8 && (b[q + 2usize] | 32u8) == 110u8 {
        q += 3usize
        ok_num = true
    } else if q + 2usize < b.len && b[q] == 48u8 && (b[q + 1usize] | 32u8) == 120u8 && (hexd(b[q + 2usize]) >= 0i64 || (b[q + 2usize] == 46u8 && q + 3usize < b.len && hexd(b[q + 3usize]) >= 0i64)) {
        // hexadecimal: 0x, hex digits with an optional point, an optional p exponent in decimal
        var m = 0.0f64
        var sc = 0i64
        var pt = false
        q += 2usize
        while q < b.len && (hexd(b[q]) >= 0i64 || (b[q] == 46u8 && !pt)) {
            if b[q] == 46u8 {
                pt = true
            } else {
                m = m * 16.0f64 + f64(hexd(b[q]))
                if pt { sc -= 4i64 }
            }
            q += 1usize
        }
        if q < b.len && (b[q] | 32u8) == 112u8 {
            var z = q + 1usize
            var en = false
            if z < b.len && (b[z] == 45u8 || b[z] == 43u8) {
                en = b[z] == 45u8
                z += 1usize
            }
            let ds = z
            var ev = 0i64
            while z < b.len && is_digit(b[z]) {
                if ev < 100000i64 { ev = ev * 10i64 + i64(b[z] - 48u8) }
                z += 1usize
            }
            if z > ds {
                q = z
                if en { sc -= ev } else { sc += ev }
            }
        }
        var v = m
        var sg = 1.0f64
        if b[start] == 45u8 { sg = -1.0f64 }
        while sc > 0i64 && v < 1.0e308f64 {
            v = v * 2.0f64
            sc -= 1i64
        }
        while sc < 0i64 && v > 0.0f64 {
            v = v / 2.0f64
            sc += 1i64
        }
        if sc > 0i64 { v = 1.0f64 / 0.0f64 }
        r.pos = q
        if q >= b.len { r.eof = true }
        ret (sg * v, true, false)
    } else {
        var nd = 0usize
        while q < b.len && is_digit(b[q]) {
            q += 1usize
            nd += 1usize
        }
        if q < b.len && b[q] == 46u8 {
            q += 1usize
            while q < b.len && is_digit(b[q]) {
                q += 1usize
                nd += 1usize
            }
        }
        if nd > 0usize {
            ok_num = true
            if q < b.len && (b[q] == 101u8 || b[q] == 69u8) {
                var z = q + 1usize
                if z < b.len && (b[z] == 45u8 || b[z] == 43u8) { z += 1usize }
                let ds = z
                while z < b.len && is_digit(b[z]) { z += 1usize }
                if z > ds { q = z }
            }
        }
    }
    if !ok_num {
        r.pos = start
        ret (0.0f64, false, false)
    }
    r.pos = q
    if q >= b.len { r.eof = true }
    ret (dbf.atof(a, b[start..q]), true, false)
}

// sscanf(line, "%%%7d%7d%7d%7d%c%8c"): the four integers, the name's start, and whether all six conversions matched
fn header(l: []const u8) -> (i64, i64, i64, i64, usize, bool) {
    if l.len < 1usize || l[0usize] != 37u8 { ret (0i64, 0i64, 0i64, 0i64, 0usize, false) }
    var p = 1usize
    var v0 = 0i64
    var v1 = 0i64
    var v2 = 0i64
    var v3 = 0i64
    var k = 0usize
    while k < 4usize {
        while p < l.len && is_space(l[p]) { p += 1usize }
        var neg = false
        var used = 0usize
        if p < l.len && (l[p] == 45u8 || l[p] == 43u8) {
            neg = l[p] == 45u8
            p += 1usize
            used += 1usize
        }
        var nd = 0usize
        var x = 0i64
        while p < l.len && used < 7usize && is_digit(l[p]) {
            x = x * 10i64 + i64(l[p] - 48u8)
            p += 1usize
            used += 1usize
            nd += 1usize
        }
        if nd == 0usize { ret (0i64, 0i64, 0i64, 0i64, 0usize, false) }
        if neg { x = 0i64 - x }
        if k == 0usize { v0 = x }
        if k == 1usize { v1 = x }
        if k == 2usize { v2 = x }
        if k == 3usize { v3 = x }
        k += 1usize
    }
    if p + 9usize > l.len { ret (0i64, 0i64, 0i64, 0i64, 0usize, false) }
    ret (v0, v1, v2, v3, p + 1usize, true)
}

fn parse(a: *mem.Arena, b: []const u8) -> (Mtp, err) {
    var out: Mtp = zero
    var r = Rd { b: b, pos: 0usize, eof: false }
    let (s0, e0, g0) = fgets(&r)
    if !g0 || e0 - s0 < 27usize { ret (out, Malformed) }
    let sig = "Minitab Portable Worksheet "
    var si = 0usize
    while si < 27usize {
        if b[s0 + si] != sig[si] { ret (out, Malformed) }
        si += 1usize
    }
    let (ls0, le0, lg) = fgets(&r)
    if !lg { ret (out, Malformed) }
    var ls = ls0
    var le = le0
    let cap = 256usize
    let (kind, k1) = mem.alloc[u8](a, cap)
    let (nrow, k2) = mem.alloc[usize](a, cap)
    let (ncol, k3) = mem.alloc[usize](a, cap)
    let (nat, k4) = mem.alloc[usize](a, cap)
    let (nlen, k5) = mem.alloc[usize](a, cap)
    let (vals, k6) = mem.alloc[[]f64](a, cap)
    if k1 != ok || k2 != ok || k3 != ok || k4 != ok || k5 != ok || k6 != ok { ret (out, mem.Full) }
    var n = 0usize
    while !r.eof {
        if n >= cap { ret (out, Malformed) }
        let (ty, cnum, len, dt, nameoff, good) = header(b[ls..le])
        if !good || len < 0i64 || len > 99999999i64 { ret (out, Malformed) }
        let ul = usize(len)
        // the name: 8 characters, trailing white space trimmed
        var ne = ls + nameoff + 8usize
        while ne > ls + nameoff && is_space(b[ne - 1usize]) { ne -= 1usize }
        nat[n] = ls + nameoff
        nlen[n] = ne - (ls + nameoff)
        let (v, ve) = mem.alloc[f64](a, ul + 1usize)
        if ve != ok { ret (out, ve) }
        if dt != 0i64 && ty != 4i64 { ret (out, NonNumeric) }
        var j = 0usize
        while j < ul {
            let (x, got, eof) = scan_double(a, &r)
            if eof { ret (out, Malformed) }
            v[j] = 0.0f64
            if got { v[j] = x }
            j += 1usize
        }
        j = 0usize
        while j < ul {
            v[j] = signif6(v[j])
            j += 1usize
        }
        kind[n] = 0u8
        nrow[n] = ul
        ncol[n] = 1usize
        if dt != 0i64 {
            if dt < 0i64 { ret (out, Malformed) }
            kind[n] = 1u8
            nrow[n] = ul / usize(dt)
            ncol[n] = usize(dt)
        }
        vals[n] = v[0usize..ul]
        n += 1usize
        let (cs, ce, cg) = fgets(&r)
        if !cg { ret (out, Malformed) }
        let (s2, e2, g2) = fgets(&r)
        ls = s2
        le = e2
    }
    out.n = n
    out.kind = kind
    out.nrow = nrow
    out.ncol = ncol
    out.nameat = nat
    out.namelen = nlen
    out.vals = vals
    out.src = b
    ret (out, ok)
}
