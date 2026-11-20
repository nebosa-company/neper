// EpiInfo / EpiData .REC reader as foreign::read.epiinfo reads it. The first line holds the number of header lines; each header line has the variable name,
// five numbers, the field type, the field length and a colour, then the prompt text from column 46. The records follow as fixed-width text, wrapped at
// 78 columns, the last character of a record being "?" when it is deleted.
//
// parse() returns a summary of every column read.epiinfo gives rather than the table: its kind (0 number, 1 logical for type 5, 2 date, 3 text), the number
// of missing values, the sum of the non-missing ones (a text counts its code units), the same sum weighted by the 1-based row, and hashes of the name and
// the prompt. A date is its day number from 1970-01-01. Dates follow strptime: %d/%m/%Y (types 11 and 16), %m/%d/%Y (types 2 and 10), with a missing
// year (len 5, guess) taken from `year` and a two-digit year (len 8, guess) read as 00-68 for 2000-2068 and 69-99 for 1969-1999.
//
// A record count that is not a multiple of the lines per record is refused (R recycles the lines and warns).

use e.mem
use e.str

error BadHeader
error NoRecords
error Ragged

type Col = struct { kind: u8, nna: usize, sum: f64, wsum: f64, nhash: f64, chash: f64 }

type Epi = struct { nvars: usize, nrows: usize, ndeleted: usize, cols: []Col }

// deleted: 0 drop deleted records (read.deleted = FALSE), 1 keep them, 2 keep them with every value missing (NA)
type Opts = struct { deleted: u8, guess: bool, lower: bool, year: str }

fn is_blank(c: u8) -> bool { ret c == 32u8 || c == 9u8 }

fn digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// the numbers as.numeric gives a string: surrounding blanks allowed; false for NA
fn lower_byte(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn eq_nocase(x: str, w: str) -> bool {
    if x.len != w.len { ret false }
    var i = 0usize
    while i < x.len {
        if lower_byte(x[i]) != w[i] { ret false }
        i += 1usize
    }
    ret true
}

fn hex_val(c: u8) -> i64 {
    if c >= 48u8 && c <= 57u8 { ret i64(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret i64(c - 87u8) }
    if c >= 65u8 && c <= 70u8 { ret i64(c - 55u8) }
    ret 0i64 - 1i64
}

// R's as.numeric of a string: blanks around it, a sign, decimal digits with an optional point and exponent ("5.", ".5" and "5.e1" count), 0x hex digits with an
// optional p exponent, and Inf or infinity in any case; NaN and NA are missing here, as are all else
fn as_num(a: *mem.Arena, s: str) -> (f64, bool) {
    var lo = 0usize
    var hi = s.len
    while lo < hi && (is_blank(s[lo]) || s[lo] == 13u8) { lo += 1usize }
    while hi > lo && (is_blank(s[hi - 1usize]) || s[hi - 1usize] == 13u8) { hi -= 1usize }
    var neg = false
    if lo < hi && (s[lo] == 45u8 || s[lo] == 43u8) {
        neg = s[lo] == 45u8
        lo += 1usize
    }
    if lo >= hi { ret (0.0f64, false) }
    let w = s[lo..hi]
    var v = 0.0f64
    if eq_nocase(w, "inf") || eq_nocase(w, "infinity") {
        v = 1.0e308f64 * 10.0f64
    } else if w.len > 2usize && w[0usize] == 48u8 && lower_byte(w[1usize]) == 120u8 {
        var i = 2usize
        var any = false
        while i < w.len && hex_val(w[i]) >= 0i64 {
            v = v * 16.0f64 + f64(hex_val(w[i]))
            any = true
            i += 1usize
        }
        if !any { ret (0.0f64, false) }
        if i < w.len {
            if lower_byte(w[i]) != 112u8 { ret (0.0f64, false) }
            i += 1usize
            var eneg = false
            if i < w.len && (w[i] == 45u8 || w[i] == 43u8) {
                eneg = w[i] == 45u8
                i += 1usize
            }
            var e2 = 0i64
            var edig = false
            while i < w.len && digit(w[i]) {
                e2 = e2 * 10i64 + i64(w[i] - 48u8)
                edig = true
                i += 1usize
            }
            if !edig || i < w.len { ret (0.0f64, false) }
            var k = 0i64
            while k < e2 && k < 2000i64 {
                if eneg { v = v / 2.0f64 } else { v = v * 2.0f64 }
                k += 1i64
            }
        }
    } else {
        // digits [. digits] [e [sign] digits]
        var i = 0usize
        var ni = 0usize
        while i < w.len && digit(w[i]) {
            ni += 1usize
            i += 1usize
        }
        let int_end = i
        var nf = 0usize
        var has_point = false
        if i < w.len && w[i] == 46u8 {
            has_point = true
            i += 1usize
            while i < w.len && digit(w[i]) {
                nf += 1usize
                i += 1usize
            }
        }
        if ni + nf == 0usize { ret (0.0f64, false) }
        let frac_end = i
        if i < w.len {
            if w[i] != 101u8 && w[i] != 69u8 { ret (0.0f64, false) }
            i += 1usize
            if i < w.len && (w[i] == 45u8 || w[i] == 43u8) { i += 1usize }
            var edig = false
            while i < w.len && digit(w[i]) {
                edig = true
                i += 1usize
            }
            if !edig || i < w.len { ret (0.0f64, false) }
        }
        let canon = ni > 0usize && (!has_point || nf > 0usize)
        if canon {
            let (x, pe) = str.parse_f64(w)
            if pe != ok { ret (0.0f64, false) }
            v = x
        } else {
            // ".5" and "5." and "5.e1": spell the number out
            let (b, eb) = str.builder(a, w.len + 4usize)
            if eb != ok { ret (0.0f64, false) }
            var bb = b
            if ni == 0usize { let _ = str.push(&bb, "0") }
            let _ = str.push(&bb, w[0usize..int_end])
            let _ = str.push(&bb, ".")
            if nf == 0usize {
                let _ = str.push(&bb, "0")
            } else {
                let _ = str.push(&bb, w[(int_end + 1usize)..frac_end])
            }
            let _ = str.push(&bb, w[frac_end..w.len])
            let (x, pe) = str.parse_f64(str.done(&bb))
            if pe != ok { ret (0.0f64, false) }
            v = x
        }
    }
    if neg { v = 0.0f64 - v }
    ret (v, true)
}

// from [at, at+max) skip blanks, then 1..max digits: the value and the offset after them (strptime's number)
fn get_num(s: str, at: usize, maxd: usize) -> (i64, usize, bool) {
    var p = at
    while p < s.len && s[p] == 32u8 { p += 1usize }
    var n = 0usize
    var v = 0i64
    while p < s.len && n < maxd && digit(s[p]) {
        v = v * 10i64 + i64(s[p] - 48u8)
        p += 1usize
        n += 1usize
    }
    if n == 0usize { ret (0i64, p, false) }
    ret (v, p, true)
}

fn leap(y: i64) -> bool { ret (y % 4i64 == 0i64 && y % 100i64 != 0i64) || y % 400i64 == 0i64 }

fn month_days(y: i64, m: i64) -> i64 {
    if m == 2i64 {
        if leap(y) { ret 29i64 }
        ret 28i64
    }
    if m == 4i64 || m == 6i64 || m == 9i64 || m == 11i64 { ret 30i64 }
    ret 31i64
}

fn days_from_civil(y0: i64, m: i64, d: i64) -> i64 {
    var y = y0
    if m <= 2i64 { y -= 1i64 }
    var era = y / 400i64
    if y < 0i64 { era = (y - 399i64) / 400i64 }
    let yoe = y - era * 400i64
    var mp = m + 9i64
    if m > 2i64 { mp = m - 3i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + d - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    ret era * 146097i64 + doe - 719468i64
}

// strptime of "<a>/<b>/<year>" where us is false for %d/%m and true for %m/%d; yd is 4 for %Y or 2 for %y. The day number, or false for NA.
fn parse_date(s: str, us: bool, yd: usize) -> (f64, bool) {
    let (f1, p1, ok1) = get_num(s, 0usize, 2usize)
    if !ok1 || p1 >= s.len || s[p1] != 47u8 { ret (0.0f64, false) }
    let (f2, p2, ok2) = get_num(s, p1 + 1usize, 2usize)
    if !ok2 || p2 >= s.len || s[p2] != 47u8 { ret (0.0f64, false) }
    let (y0, p3, ok3) = get_num(s, p2 + 1usize, yd)
    var yy = y0
    if !ok3 { ret (0.0f64, false) }
    if yd == 2usize {
        if yy < 69i64 { yy += 2000i64 } else { yy += 1900i64 }
    }
    var d = f1
    var m = f2
    if us {
        d = f2
        m = f1
    }
    if m < 1i64 || m > 12i64 || d < 1i64 || d > month_days(yy, m) { ret (0.0f64, false) }
    ret (f64(days_from_civil(yy, m, d)), true)
}

// the substring(x, a, b) with 1-based inclusive bounds, clipped to the string
fn sub(x: str, a: usize, b: usize) -> str {
    if a > x.len || b < a { ret x[0usize..0usize] }
    var e = b
    if e > x.len { e = x.len }
    ret x[(a - 1usize)..e]
}

fn code_sum(x: str) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += f64(x[i])
        i += 1usize
    }
    ret s
}

fn hash(x: str) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += f64(x[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

// the whitespace-separated tokens of a line, up to 9: their [start, end) offsets
fn tokens(l: str, ts: []usize, te: []usize) -> usize {
    var n = 0usize
    var p = 0usize
    while p < l.len && n < 9usize {
        while p < l.len && (is_blank(l[p]) || l[p] == 13u8) { p += 1usize }
        var q = p
        while q < l.len && !is_blank(l[q]) && l[q] != 13u8 { q += 1usize }
        if q > p {
            ts[n] = p
            te[n] = q
            n += 1usize
        }
        p = q
    }
    ret n
}

fn line_end(t: str, at: usize) -> usize {
    var e = at
    while e < t.len && t[e] != 10u8 { e += 1usize }
    ret e
}

fn parse(a: *mem.Arena, t: str, o: Opts) -> (Epi, err) {
    var out: Epi = zero
    var nl = 0usize
    var i = 0usize
    while i < t.len {
        nl += 1usize
        i = line_end(t, i) + 1usize
    }
    let (lines, e1) = mem.alloc[str](a, nl + 1usize)
    if e1 != ok { ret (out, e1) }
    var k = 0usize
    i = 0usize
    while i < t.len {
        let le = line_end(t, i)
        var le2 = le
        if le2 > i && t[le2 - 1usize] == 13u8 { le2 -= 1usize }
        lines[k] = t[i..le2]
        k += 1usize
        i = le + 1usize
    }
    if k == 0usize { ret (out, BadHeader) }
    // the first number on the first line is the number of header lines
    var hl = 0usize
    var found = false
    let first = lines[0usize]
    var p = 0usize
    while p < first.len && !found {
        var q = p
        while q < first.len && first[q] != 32u8 { q += 1usize }
        if q > p {
            let (x, good) = as_num(a, first[p..q])
            if good {
                found = true
                if x < 1.0f64 { ret (out, BadHeader) }
                hl = usize(x)
            }
        }
        p = q + 1usize
    }
    if !found || 1usize + hl > k { ret (out, BadHeader) }
    let (names, e2) = mem.alloc[str](a, hl + 1usize)
    if e2 != ok { ret (out, e2) }
    let (proms, e3) = mem.alloc[str](a, hl + 1usize)
    if e3 != ok { ret (out, e3) }
    let (types, e4) = mem.alloc[i64](a, hl + 1usize)
    if e4 != ok { ret (out, e4) }
    let (lens, e5) = mem.alloc[usize](a, hl + 1usize)
    if e5 != ok { ret (out, e5) }
    let (ts, e6) = mem.alloc[usize](a, 9usize)
    if e6 != ok { ret (out, e6) }
    let (te, e7) = mem.alloc[usize](a, 9usize)
    if e7 != ok { ret (out, e7) }
    var total = 0usize
    var h = 0usize
    while h < hl {
        let l = lines[1usize + h]
        proms[h] = sub(l, 46usize, 126usize)
        var need = 9usize
        if h + 1usize == hl { need = 8usize }
        let nt = tokens(l, ts, te)
        if nt < need { ret (out, BadHeader) }
        names[h] = l[ts[0usize]..te[0usize]]
        var f = 1usize
        while f < nt {
            let (xv, good) = as_num(a, l[ts[f]..te[f]])
            if !good { ret (out, BadHeader) }
            f += 1usize
        }
        let (ty, g1) = as_num(a, l[ts[6usize]..te[6usize]])
        let (ln, g2) = as_num(a, l[ts[7usize]..te[7usize]])
        types[h] = i64(ty)
        lens[h] = usize(ln)
        total += lens[h]
        h += 1usize
    }
    var multiline = (total + 77usize) / 78usize
    if multiline == 0usize { multiline = 1usize }
    // the records: non-empty lines after the header
    var nrec_lines = 0usize
    var li = 1usize + hl
    while li < k {
        if lines[li].len > 0usize { nrec_lines += 1usize }
        li += 1usize
    }
    if nrec_lines == 0usize { ret (out, NoRecords) }
    if nrec_lines % multiline != 0usize { ret (out, Ragged) }
    let nrec = nrec_lines / multiline
    let (recs, e8) = mem.alloc[str](a, nrec + 1usize)
    if e8 != ok { ret (out, e8) }
    let (del, e9) = mem.alloc[bool](a, nrec + 1usize)
    if e9 != ok { ret (out, e9) }
    var r = 0usize
    li = 1usize + hl
    while r < nrec {
        let (b, eb) = str.builder(a, 128usize)
        if eb != ok { ret (out, eb) }
        var bb = b
        var m = 0usize
        while m < multiline {
            while lines[li].len == 0usize { li += 1usize }
            var piece = lines[li]
            if m + 1usize < multiline { piece = sub(piece, 1usize, 78usize) }
            let _ = str.push(&bb, piece)
            li += 1usize
            m += 1usize
        }
        let record = str.done(&bb)
        recs[r] = record
        del[r] = record.len > 0usize && record[record.len - 1usize] == 63u8
        r += 1usize
    }
    // the variables that really exist (a length of zero is a label)
    var nv = 0usize
    h = 0usize
    while h < hl {
        if lens[h] != 0usize { nv += 1usize }
        h += 1usize
    }
    let (cols, e10) = mem.alloc[Col](a, nv + 1usize)
    if e10 != ok { ret (out, e10) }
    // all names start with "#" or "_": drop that character and keep 11 more
    var all_marked = true
    h = 0usize
    while h < hl {
        if lens[h] != 0usize {
            let c0 = names[h][0usize]
            if c0 != 35u8 && c0 != 95u8 { all_marked = false }
        }
        h += 1usize
    }
    var kept = 0usize
    r = 0usize
    while r < nrec {
        if o.deleted != 0u8 || !del[r] { kept += 1usize }
        r += 1usize
    }
    var ndel = 0usize
    r = 0usize
    while r < nrec {
        if del[r] { ndel += 1usize }
        r += 1usize
    }
    var start = 1usize
    var vi = 0usize
    h = 0usize
    while h < hl {
        let ln = lens[h]
        let stop = start + ln - 1usize
        let ty = types[h]
        if ln != 0usize {
            var c: Col = zero
            var nm = names[h]
            if all_marked { nm = sub(nm, 2usize, 12usize) }
            var nh = 0.0f64
            var q = 0usize
            while q < nm.len {
                var ch = nm[q]
                if o.lower { ch = lower_byte(ch) }
                nh += f64(ch) * f64(q + 1usize)
                q += 1usize
            }
            c.nhash = nh
            c.chash = hash(proms[h])
            var numbers = ty == 0i64 || ty == 6i64 || ty == 12i64 || ty > 12i64
            if ty == 16i64 || ty == 17i64 { numbers = false }
            var row = 0usize
            r = 0usize
            while r < nrec {
                let skip = del[r] && o.deleted == 0u8
                if !skip {
                    row += 1usize
                    let w = f64(row)
                    var raw = sub(recs[r], start, stop)
                    var missing = del[r] && o.deleted == 2u8
                    var val = 0.0f64
                    if numbers {
                        c.kind = 0u8
                        if !missing {
                            let (x, good) = as_num(a, raw)
                            if good { val = x } else { missing = true }
                        }
                    } else if ty == 5i64 {
                        c.kind = 1u8
                        if !missing {
                            if str.eq(raw, "Y") {
                                val = 1.0f64
                            } else if !str.eq(raw, "N") {
                                missing = true
                            }
                        }
                    } else if (ty == 11i64 || ty == 16i64 || ty == 2i64 || ty == 10i64) && (ln == 10usize || (o.guess && (ln == 5usize || ln == 8usize))) {
                        c.kind = 2u8
                        let us = ty == 2i64 || ty == 10i64
                        if !missing {
                            var text = raw
                            var yd = 4usize
                            if ln == 5usize {
                                let (b, eb) = str.builder(a, 32usize)
                                if eb != ok { ret (out, eb) }
                                var bb = b
                                let _ = str.push(&bb, raw)
                                let _ = str.push(&bb, "/")
                                let _ = str.push(&bb, o.year)
                                text = str.done(&bb)
                            }
                            if ln == 8usize { yd = 2usize }
                            let (d, good) = parse_date(text, us, yd)
                            if good { val = d } else { missing = true }
                        }
                    } else if ty == 17i64 {
                        c.kind = 3u8
                        if !missing && raw.len > 0usize && raw[0usize] == 32u8 { missing = true }
                        if !missing { raw = sub(raw, 1usize, 5usize) }
                        if !missing { val = code_sum(raw) }
                    } else {
                        c.kind = 3u8
                        if !missing {
                            var blank = true
                            var z = 0usize
                            while z < raw.len {
                                if !is_blank(raw[z]) { blank = false }
                                z += 1usize
                            }
                            if blank { missing = true }
                        }
                        if !missing { val = code_sum(raw) }
                    }
                    if missing {
                        c.nna += 1usize
                    } else {
                        c.sum += val
                        c.wsum += val * w
                    }
                }
                r += 1usize
            }
            cols[vi] = c
            vi += 1usize
        }
        start += ln
        h += 1usize
    }
    out.nvars = nv
    out.nrows = kept
    if o.deleted == 1u8 { out.ndeleted = ndel }
    out.cols = cols[0usize..nv]
    ret (out, ok)
}
