// ARFF (Weka) reader as foreign::read.arff takes it: @relation, @attribute (numeric, real, string, date and nominal sets; any other type is "Invalid type specification"), and @data rows read
// as read.table(sep = ",", na.strings = "?", comment.char = "%") reads them, so quoting is scan's (a quote starts a quoted section anywhere in a text field, a doubled quote is one quote), a
// number is R_strtod over the field with its blanks dropped (an NA or text is an error), a record that ends inside a quote is dropped, and a row with more fields than columns is an error
// where R would make the first field row names. A nominal value becomes its 1-based rank among the values the data hold (not the declared levels, which read.arff ignores), sorted bytewise as
// in R's C locale (R sorts in its session locale), with the backslashes of a level removed; string columns keep their text.
// A date column holds seconds since 1970-01-01 UTC. Its format is the attribute's own (Weka style, converted as read.arff converts it with
// ISO_8601_to_POSIX_datetime_format, the chain of first-occurrence substitutions) or the default "%Y-%m-%d %H:%M:%S"; the text is parsed the way
// strptime does it (trailing input ignored, numbers up to their width, days checked against the month). A value that does not parse is NaN.
// A sparse row ('{' first) and a relational attribute are errors, as read.arff reports them.
//
// The directives Y y m d H M S j set the time; w and U are read and ignored, as R does. Any other directive makes the value NaN.
// As R's strptime does (glibc_fix), a year the format lacks is today's, a day-of-year (%j) gives the month and day, and otherwise a missing day is today's
// and a missing month is today's, except that a month without a day is not a date. Today is read from the wall clock in UTC.
// Weights are not here.

use e.fmt.dbf as dbf
use e.fmt.systat as sys
use e.mem
use e.str
use e.time

error Malformed
error TooMany

// kind: 0 numeric, 1 nominal, 2 string, 3 date
// values: a nominal column's 1-based code among its levels, a character column's 1-based row, a date's seconds, a number; NaN for missing. lvl: the levels of the nominal columns in column
// order (the values the data hold, sorted bytewise as in the C locale, backslashes removed); txt: the text of a character column at [row * ncols + column]
type Arff = struct { ncols: usize, nrows: usize, kind: []u8, nlev: []usize, values: []f64, lvl: []str, txt: []str }

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 13u8 }

fn starts_ci(t: str, at: usize, word: str) -> bool {
    if at + word.len > t.len { ret false }
    var i = 0usize
    while i < word.len {
        if lower(t[at + i]) != word[i] { ret false }
        i += 1usize
    }
    ret true
}

// buf[0..n] with the first occurrence of pat replaced by rep (lower-case pat matched case-insensitively when ci); returns the new length
fn replace_first(buf: []u8, n: usize, pat: str, rep: str, ci: bool, tmp: []u8) -> (usize, err) {
    var at = 0usize
    var found = false
    var i = 0usize
    while !found && i + pat.len <= n {
        var k = 0usize
        var hit = true
        while k < pat.len {
            var ch = buf[i + k]
            if ci { ch = lower(ch) }
            if ch != pat[k] {
                hit = false
                break
            }
            k += 1usize
        }
        if hit {
            at = i
            found = true
        }
        i += 1usize
    }
    if !found { ret (n, ok) }
    var m = 0usize
    var c = 0usize
    while c < at {
        tmp[m] = buf[c]
        m += 1usize
        c += 1usize
    }
    var r = 0usize
    while r < rep.len {
        tmp[m] = rep[r]
        m += 1usize
        r += 1usize
    }
    c = at + pat.len
    while c < n {
        tmp[m] = buf[c]
        m += 1usize
        c += 1usize
    }
    if m > buf.len { ret (0usize, TooMany) }
    c = 0usize
    while c < m {
        buf[c] = tmp[c]
        c += 1usize
    }
    ret (m, ok)
}

// the strptime format read.arff derives from a Weka date format: foreign's ISO_8601_to_POSIX_datetime_format, each substitution on the first occurrence
fn weka_format(src: str, buf: []u8, tmp: []u8) -> (usize, err) {
    if src.len > buf.len { ret (0usize, TooMany) }
    var n = 0usize
    while n < src.len {
        buf[n] = src[n]
        n += 1usize
    }
    let (n1, e1) = replace_first(buf, n, "yyyy", "%Y", true, tmp)
    if e1 != ok { ret (0usize, e1) }
    let (n2, e2) = replace_first(buf, n1, "dd", "%d", false, tmp)
    if e2 != ok { ret (0usize, e2) }
    let (n3, e3) = replace_first(buf, n2, "HH", "%H", false, tmp)
    if e3 != ok { ret (0usize, e3) }
    let (n4, e4) = replace_first(buf, n3, "CCYY", "%Y", false, tmp)
    if e4 != ok { ret (0usize, e4) }
    let (n5, e5) = replace_first(buf, n4, "YY", "%y", false, tmp)
    if e5 != ok { ret (0usize, e5) }
    let (n6, e6) = replace_first(buf, n5, "MM", "%m", false, tmp)
    if e6 != ok { ret (0usize, e6) }
    let (n7, e7) = replace_first(buf, n6, "DD", "%d", false, tmp)
    if e7 != ok { ret (0usize, e7) }
    let (n8, e8) = replace_first(buf, n7, "DDD", "%j", false, tmp)
    if e8 != ok { ret (0usize, e8) }
    let (n9, e9) = replace_first(buf, n8, "ww", "%U", false, tmp)
    if e9 != ok { ret (0usize, e9) }
    let (n10, e10) = replace_first(buf, n9, "D", "%w", false, tmp)
    if e10 != ok { ret (0usize, e10) }
    let (n11, e11) = replace_first(buf, n10, "hh", "%H", false, tmp)
    if e11 != ok { ret (0usize, e11) }
    let (n12, e12) = replace_first(buf, n11, "mm", "%M", false, tmp)
    if e12 != ok { ret (0usize, e12) }
    let (n13, e13) = replace_first(buf, n12, "ss", "%S", false, tmp)
    if e13 != ok { ret (0usize, e13) }
    ret (n13, ok)
}

// days from 1970-01-01 to y-m-d in the proleptic Gregorian calendar
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    var yy = y
    if m <= 2i64 { yy = yy - 1i64 }
    var era = 0i64
    if yy >= 0i64 {
        era = yy / 400i64
    } else {
        era = (yy - 399i64) / 400i64
    }
    let yoe = yy - era * 400i64
    var mp = m + 9i64
    if m > 2i64 { mp = m - 3i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + d - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    ret era * 146097i64 + doe - 719468i64
}

fn days_in_month(y: i64, m: i64) -> i64 {
    if m == 2i64 {
        if y % 4i64 == 0i64 && (y % 100i64 != 0i64 || y % 400i64 == 0i64) { ret 29i64 }
        ret 28i64
    }
    if m == 4i64 || m == 6i64 || m == 9i64 || m == 11i64 { ret 30i64 }
    ret 31i64
}

// a decimal number of at most maxd digits at `at`, after blanks, within [lo, hi]; (value, next, ok)
fn digits(s: str, at: usize, maxd: usize, lo: i64, hi: i64) -> (i64, usize, bool) {
    var p = at
    while p < s.len && is_space(s[p]) { p += 1usize }
    var v = 0i64
    var d = 0usize
    while p < s.len && d < maxd && s[p] >= 48u8 && s[p] <= 57u8 {
        v = v * 10i64 + i64(s[p] - 48u8)
        p += 1usize
        d += 1usize
    }
    if d == 0usize || v < lo || v > hi { ret (0i64, at, false) }
    ret (v, p, true)
}

// one strptime directive at `at` of s: its number and the next position; an unknown directive does not match
fn directive(dc: u8, s: str, at: usize) -> (i64, usize, bool) {
    var maxd = 2usize
    var lo = 0i64
    var hi = 0i64
    if dc == 89u8 {
        maxd = 4usize
        hi = 9999i64
    } else if dc == 121u8 {
        hi = 99i64
    } else if dc == 109u8 {
        lo = 1i64
        hi = 12i64
    } else if dc == 100u8 {
        lo = 1i64
        hi = 31i64
    } else if dc == 72u8 {
        hi = 23i64
    } else if dc == 77u8 {
        hi = 59i64
    } else if dc == 83u8 {
        hi = 61i64
    } else if dc == 106u8 {
        maxd = 3usize
        lo = 1i64
        hi = 366i64
    } else if dc == 119u8 {
        maxd = 1usize
        hi = 6i64
    } else if dc == 85u8 {
        hi = 53i64
    } else {
        ret (0i64, at, false)
    }
    let (v, nx, g) = digits(s, at, maxd, lo, hi)
    ret (v, nx, g)
}

// seconds since 1970-01-01 UTC of s read with the strptime format f (blanks in f match any run of blanks; trailing text is ignored); NaN when it does not parse
fn strptime(f: []u8, s: str, today: i64) -> f64 {
    let bad = 0.0f64 / 0.0f64
    var y = 0i64
    var mo = 0i64
    var d = 0i64
    var have_y = false
    var hh = 0i64
    var mi = 0i64
    var ss = 0i64
    var yday = 0i64
    var fi = 0usize
    var si = 0usize
    while fi < f.len {
        let c = f[fi]
        if c == 37u8 {
            if fi + 1usize >= f.len { ret bad }
            let dc = f[fi + 1usize]
            fi += 2usize
            let (v, nx, g) = directive(dc, s, si)
            if !g { ret bad }
            si = nx
            if dc == 89u8 {
                y = v
                have_y = true
            }
            if dc == 121u8 {
                have_y = true
                y = 1900i64 + v
                if v < 69i64 { y = 2000i64 + v }
            }
            if dc == 109u8 { mo = v }
            if dc == 100u8 { d = v }
            if dc == 72u8 { hh = v }
            if dc == 77u8 { mi = v }
            if dc == 83u8 { ss = v }
            if dc == 106u8 { yday = v }
        } else if is_space(c) {
            while si < s.len && is_space(s[si]) { si += 1usize }
            fi += 1usize
        } else {
            if si >= s.len || s[si] != c { ret bad }
            si += 1usize
            fi += 1usize
        }
    }
    let (ty, tm, td) = time.civil_from_days(today)
    if !have_y { y = ty }
    var days = 0i64
    if yday > 0i64 && (mo == 0i64 || d == 0i64) {
        days = days_from_civil(y, 1i64, 1i64) + yday - 1i64
    } else {
        if d == 0i64 {
            if mo != 0i64 { ret bad }
            d = td
        }
        if mo == 0i64 { mo = tm }
        if d > days_in_month(y, mo) { ret bad }
        days = days_from_civil(y, mo, d)
    }
    ret f64(days * 86400i64 + hh * 3600i64 + mi * 60i64 + ss)
}

fn parse(a: *mem.Arena, t: str) -> (Arff, err) {
    var today = 0i64
    let (now, ne) = time.now()
    if ne == ok { today = time.floor_div(now.nanos, 86400000000000i64) }
    let (pr, pe) = parse_on(a, t, today)
    ret (pr, pe)
}

// parse with the day a date format's missing parts are taken from (days since 1970-01-01)
fn parse_on(a: *mem.Arena, t: str, today: i64) -> (Arff, err) {
    var out: Arff = zero
    // pass 1: the attributes and the line where the data start
    var cols = 0usize
    var i = 0usize
    var data_at = t.len
    let (kind, e1) = mem.alloc[u8](a, 256usize)
    if e1 != ok { ret (out, e1) }
    let (nlev, e2) = mem.alloc[usize](a, 256usize)
    if e2 != ok { ret (out, e2) }
    // date columns: the strptime format of each, at most 128 bytes at c * 128
    let (fbuf, e6) = mem.alloc[u8](a, 256usize * 128usize)
    if e6 != ok { ret (out, e6) }
    let (fmt_n, e7) = mem.alloc[usize](a, 256usize)
    if e7 != ok { ret (out, e7) }
    let (wbuf, e8) = mem.alloc[u8](a, 128usize)
    if e8 != ok { ret (out, e8) }
    let (tmp, e9) = mem.alloc[u8](a, 128usize)
    if e9 != ok { ret (out, e9) }
    while i < t.len {
        var le = i
        while le < t.len && t[le] != 10u8 { le += 1usize }
        var s = i
        while s < le && is_space(t[s]) { s += 1usize }
        if s < le && t[s] != 37u8 {
            if starts_ci(t, s, "@attribute") {
                if cols >= 256usize { ret (out, TooMany) }
                var p = s + 10usize
                while p < le && is_space(t[p]) { p += 1usize }
                // skip the name
                if p < le && (t[p] == 39u8 || t[p] == 34u8) {
                    let q = t[p]
                    p += 1usize
                    while p < le && t[p] != q { p += 1usize }
                    p += 1usize
                } else {
                    while p < le && !is_space(t[p]) { p += 1usize }
                }
                while p < le && is_space(t[p]) { p += 1usize }
                if p < le && t[p] == 123u8 {
                    kind[cols] = 1u8
                    nlev[cols] = 0usize
                } else if starts_ci(t, p, "string") {
                    kind[cols] = 2u8
                } else if starts_ci(t, p, "relational") {
                    ret (out, Malformed)
                } else if starts_ci(t, p, "date") {
                    kind[cols] = 3u8
                    var src: str = "%Y-%m-%d %H:%M:%S"
                    var q = p + 4usize
                    while q < le && is_space(t[q]) { q += 1usize }
                    if q < le && (t[q] == 39u8 || t[q] == 34u8) {
                        let qc = t[q]
                        var fe = q + 1usize
                        while fe < le && t[fe] != qc { fe += 1usize }
                        src = t[q + 1usize..fe]
                    } else if q < le {
                        var fe = q
                        while fe < le && !is_space(t[fe]) { fe += 1usize }
                        src = t[q..fe]
                    }
                    let (n, ef) = weka_format(src, wbuf, tmp)
                    if ef != ok { ret (out, ef) }
                    var j = 0usize
                    while j < n {
                        fbuf[cols * 128usize + j] = wbuf[j]
                        j += 1usize
                    }
                    fmt_n[cols] = n
                } else if starts_ci(t, p, "numeric") || starts_ci(t, p, "real") {
                    kind[cols] = 0u8
                } else {
                    // read.arff accepts only numeric, real, string, date and a nominal set; "Invalid type specification"
                    ret (out, Malformed)
                }
                cols += 1usize
            } else if starts_ci(t, s, "@data") {
                data_at = le + 1usize
                break
            }
        }
        i = le + 1usize
    }
    // pass 2: the data as read.table(sep = ",", na.strings = "?", comment.char = "%", colClasses) reads them
    var maxrows = 1usize
    i = data_at
    while i < t.len {
        if t[i] == 10u8 { maxrows += 1usize }
        i += 1usize
    }
    let (vals, e5) = mem.alloc[f64](a, maxrows * cols + 1usize)
    if e5 != ok { ret (out, e5) }
    let (ts, e10) = mem.alloc[usize](a, maxrows * cols + 1usize)
    let (tl, e11) = mem.alloc[usize](a, maxrows * cols + 1usize)
    let (dsx, e12) = mem.alloc[usize](a, maxrows + 1usize)
    let (drank, e13) = mem.alloc[usize](a, maxrows + 1usize)
    let (lvls, e16) = mem.alloc[str](a, maxrows * cols + 1usize)
    let (txts, e17) = mem.alloc[str](a, maxrows * cols + 1usize)
    let (sbuf, sbe) = mem.alloc[u8](a, t.len - data_at + cols + 16usize)
    if e10 != ok || e11 != ok || e12 != ok || e13 != ok || e16 != ok || e17 != ok || sbe != ok { ret (out, mem.Full) }
    var sn = 0usize
    var sc = Scn { t: t, p: data_at }
    var r = 0usize
    var more = true
    while more {
        // blank lines are skipped, the end of the file ends the data
        let save = sc.p
        let c0 = getc(&sc, false)
        if c0 < 0i64 {
            more = false
        } else if c0 != 10i64 {
            sc.p = save
            var eofq = false
            var c = 0usize
            while c < cols {
                var term = 0i64
                if kind[c] == 0u8 {
                    // blanks anywhere in a number are dropped; empty, "?" and NA are missing
                    let nstart = sn
                    var go = true
                    while go {
                        let ch = getc(&sc, false)
                        if ch == 44i64 || ch == 10i64 || ch < 0i64 {
                            term = ch
                            go = false
                        } else if ch != 32i64 && ch != 9i64 {
                            sbuf[sn] = u8(ch)
                            sn += 1usize
                        }
                    }
                    let nt = sbuf[nstart..sn]
                    var v = 0.0f64 / 0.0f64
                    if sn > nstart && !str.eq(nt, "?") {
                        let (x, okn) = strict_number(a, nt)
                        if !okn { ret (out, Malformed) }
                        v = x
                    }
                    vals[r * cols + c] = v
                    sn = nstart
                } else {
                    let st = sn
                    var go = true
                    while go {
                        let ch = getc(&sc, false)
                        if ch == 44i64 || ch == 10i64 || ch < 0i64 {
                            term = ch
                            go = false
                        } else if ch == 39i64 || ch == 34i64 {
                            var inq = true
                            while inq {
                                var ch2 = getc(&sc, true)
                                while ch2 >= 0i64 && ch2 != ch {
                                    sbuf[sn] = u8(ch2)
                                    sn += 1usize
                                    ch2 = getc(&sc, true)
                                }
                                if ch2 < 0i64 {
                                    // the end inside a quote: scan drops the unfinished record
                                    eofq = true
                                    term = ch2
                                    go = false
                                    inq = false
                                } else {
                                    let save2 = sc.p
                                    let ch3 = getc(&sc, true)
                                    if ch3 == ch {
                                        sbuf[sn] = u8(ch)
                                        sn += 1usize
                                    } else if ch3 == 44i64 || ch3 == 10i64 || ch3 < 0i64 {
                                        term = ch3
                                        go = false
                                        inq = false
                                    } else {
                                        sc.p = save2
                                        inq = false
                                    }
                                }
                            }
                        } else {
                            sbuf[sn] = u8(ch)
                            sn += 1usize
                        }
                    }
                    ts[r * cols + c] = st
                    tl[r * cols + c] = sn - st
                    vals[r * cols + c] = 0.0f64
                    // "?" is missing
                    if sn - st == 1usize && sbuf[st] == 63u8 { vals[r * cols + c] = 0.0f64 / 0.0f64 }
                }
                if eofq {
                    more = false
                } else {
                    if c + 1usize < cols && term != 44i64 { ret (out, Malformed) }
                    if c + 1usize == cols && term == 44i64 { ret (out, Malformed) }
                    if term < 0i64 { more = false }
                }
                c += 1usize
            }
            if !eofq { r += 1usize }
        }
    }
    let all = sbuf[0usize..sn]
    // dates, strings and the factors with the levels the data hold, sorted, with the backslashes removed
    var nl_total = 0usize
    var c1 = 0usize
    while c1 < cols {
        if kind[c1] == 3u8 {
            var rr = 0usize
            while rr < r {
                let ix = rr * cols + c1
                if vals[ix] == vals[ix] { vals[ix] = strptime(fbuf[c1 * 128usize..c1 * 128usize + fmt_n[c1]], all[ts[ix]..ts[ix] + tl[ix]], today) }
                rr += 1usize
            }
        } else if kind[c1] == 2u8 {
            var rr = 0usize
            while rr < r {
                let ix = rr * cols + c1
                txts[ix] = all[ts[ix]..ts[ix] + tl[ix]]
                if vals[ix] == vals[ix] { vals[ix] = f64(rr + 1usize) }
                rr += 1usize
            }
        } else if kind[c1] == 1u8 {
            var nd = 0usize
            var rr = 0usize
            while rr < r {
                let ix = rr * cols + c1
                if vals[ix] == vals[ix] {
                    var found = false
                    var k = 0usize
                    while k < nd && !found {
                        let jx = dsx[k]
                        if same(all, ts[jx], ts[jx] + tl[jx], ts[ix], ts[ix] + tl[ix]) { found = true }
                        k += 1usize
                    }
                    if !found {
                        dsx[nd] = ix
                        nd += 1usize
                    }
                }
                rr += 1usize
            }
            var k = 0usize
            while k < nd {
                let kx = dsx[k]
                var rank = 1usize
                var m = 0usize
                while m < nd {
                    let mx = dsx[m]
                    if m != k && less(all, ts[mx], ts[mx] + tl[mx], ts[kx], ts[kx] + tl[kx]) { rank += 1usize }
                    m += 1usize
                }
                drank[k] = rank
                // the level text without its backslashes
                var nb = 0usize
                var q = 0usize
                while q < tl[kx] {
                    if all[ts[kx] + q] == 92u8 { nb += 1usize }
                    q += 1usize
                }
                var txt: str = all[ts[kx]..ts[kx] + tl[kx]]
                if nb > 0usize {
                    let (lb, le2) = str.builder(a, tl[kx])
                    if le2 != ok { ret (out, le2) }
                    var lw = lb
                    q = 0usize
                    while q < tl[kx] {
                        if all[ts[kx] + q] != 92u8 { let _ = str.push_byte(&lw, all[ts[kx] + q]) }
                        q += 1usize
                    }
                    txt = str.done(&lw)
                }
                lvls[nl_total + rank - 1usize] = txt
                k += 1usize
            }
            rr = 0usize
            while rr < r {
                let ix = rr * cols + c1
                if vals[ix] == vals[ix] {
                    k = 0usize
                    while k < nd {
                        let jx = dsx[k]
                        if same(all, ts[jx], ts[jx] + tl[jx], ts[ix], ts[ix] + tl[ix]) { vals[ix] = f64(drank[k]) }
                        k += 1usize
                    }
                }
                rr += 1usize
            }
            nlev[c1] = nd
            nl_total += nd
        }
        c1 += 1usize
    }
    out.ncols = cols
    out.nrows = r
    out.kind = kind[0usize..cols]
    out.nlev = nlev[0usize..cols]
    out.values = vals
    out.lvl = lvls[0usize..nl_total]
    out.txt = txts
    ret (out, ok)
}

// the field texts equal
fn same(t: str, a: usize, b: usize, c: usize, d: usize) -> bool {
    if b - a != d - c { ret false }
    var i = 0usize
    while i < b - a {
        if t[a + i] != t[c + i] { ret false }
        i += 1usize
    }
    ret true
}

fn less(t: str, a: usize, b: usize, c: usize, d: usize) -> bool {
    var i = 0usize
    while i < b - a && i < d - c {
        if t[a + i] != t[c + i] { ret t[a + i] < t[c + i] }
        i += 1usize
    }
    ret b - a < d - c
}

// scan's reader over the data: the next byte or -1 at the end; an unquoted % skips the rest of its line and answers the newline, and CRLF is one newline
type Scn = struct { t: str, p: usize }

fn getc(s: *Scn, inq: bool) -> i64 {
    let t = s.t
    if s.p >= t.len { ret 0i64 - 1i64 }
    var c = t[s.p]
    s.p += 1usize
    if c == 13u8 && s.p < t.len && t[s.p] == 10u8 {
        c = 10u8
        s.p += 1usize
    }
    if !inq && c == 37u8 {
        while s.p < t.len && t[s.p] != 10u8 { s.p += 1usize }
        if s.p < t.len {
            s.p += 1usize
            ret 10i64
        }
        ret 0i64 - 1i64
    }
    ret i64(c)
}

fn hexval(c: u8) -> i64 {
    if c >= 48u8 && c <= 57u8 { ret i64(c - 48u8) }
    if c >= 97u8 && c <= 102u8 { ret i64(c - 87u8) }
    if c >= 65u8 && c <= 70u8 { ret i64(c - 55u8) }
    ret 0i64 - 1i64
}

// a number as scan(what = double) takes it: R_strtod over the whole field (blanks were dropped): NaN, Inf, or [sign] digits [. digits] [e [sign] digits]
fn strict_number(a: *mem.Arena, s: str) -> (f64, bool) {
    let nan = 0.0f64 / 0.0f64
    var p = 0usize
    if p < s.len && (s[p] == 45u8 || s[p] == 43u8) { p += 1usize }
    let rest = s[p..s.len]
    if str.eq(rest, "NaN") || str.eq(rest, "nan") { ret (nan, true) }
    if str.eq(rest, "Inf") || str.eq(rest, "inf") || str.eq(rest, "infinity") || str.eq(rest, "Infinity") {
        if s[0usize] == 45u8 { ret (0.0f64 - 1.0f64 / 0.0f64, true) }
        ret (1.0f64 / 0.0f64, true)
    }
    if s.len > p + 2usize && s[p] == 48u8 && (s[p + 1usize] == 120u8 || s[p + 1usize] == 88u8) {
        // hexadecimal: digits [. digits] [p [sign] decimal exponent of two]
        var q = p + 2usize
        var m = 0.0f64
        var any = false
        while q < s.len && hexval(s[q]) >= 0i64 {
            m = m * 16.0f64 + f64(hexval(s[q]))
            q += 1usize
            any = true
        }
        var e2 = 0i64
        if q < s.len && s[q] == 46u8 {
            q += 1usize
            while q < s.len && hexval(s[q]) >= 0i64 {
                m = m * 16.0f64 + f64(hexval(s[q]))
                e2 -= 4i64
                q += 1usize
                any = true
            }
        }
        if !any { ret (nan, false) }
        if q < s.len && (s[q] == 112u8 || s[q] == 80u8) {
            q += 1usize
            var sg = 1i64
            if q < s.len && (s[q] == 45u8 || s[q] == 43u8) {
                if s[q] == 45u8 { sg = 0i64 - 1i64 }
                q += 1usize
            }
            var ex = 0i64
            var ed2 = 0usize
            while q < s.len && s[q] >= 48u8 && s[q] <= 57u8 {
                ex = ex * 10i64 + i64(s[q] - 48u8)
                q += 1usize
                ed2 += 1usize
            }
            if ed2 == 0usize { ret (nan, false) }
            e2 += sg * ex
        }
        if q != s.len { ret (nan, false) }
        var hv = m
        var ee = e2
        while ee > 0i64 {
            hv = hv * 2.0f64
            ee -= 1i64
        }
        while ee < 0i64 {
            hv = hv / 2.0f64
            ee += 1i64
        }
        if s[0usize] == 45u8 { hv = 0.0f64 - hv }
        ret (hv, true)
    }
    var nd = 0usize
    while p < s.len && s[p] >= 48u8 && s[p] <= 57u8 {
        p += 1usize
        nd += 1usize
    }
    if p < s.len && s[p] == 46u8 {
        p += 1usize
        while p < s.len && s[p] >= 48u8 && s[p] <= 57u8 {
            p += 1usize
            nd += 1usize
        }
    }
    if nd == 0usize { ret (nan, false) }
    if p < s.len && (s[p] == 101u8 || s[p] == 69u8) {
        p += 1usize
        if p < s.len && (s[p] == 45u8 || s[p] == 43u8) { p += 1usize }
        var ed = 0usize
        while p < s.len && s[p] >= 48u8 && s[p] <= 57u8 {
            p += 1usize
            ed += 1usize
        }
        if ed == 0usize { ret (nan, false) }
    }
    if p != s.len { ret (nan, false) }
    ret (dbf.atof(a, s), true)
}

// foreign::write.arff: "@relation <relation>" (make.names, then quoted or X-prefixed as write.arff's spquote does), one "@attribute <name> <type>" per column, "@data", then the rows as
// comma-separated values with ? for a missing one. t holds the columns, kind 0 numeric (written as R writes a double: up to 15 significant digits, fixed or scientific whichever is
// narrower), 1 nominal ({'l1','l2',...}; the 1-based level code in values), 2 character (string, each value quoted), 3 Date (date "yyyy-MM-dd"; days since 1970, quoted), 4 POSIXct (date
// "yyyy-MM-dd HH:mm:ss"; seconds since 1970 in UTC, quoted, written as R's default format picks it: the date alone when every time is midnight),
// 5 logical (numeric; TRUE or FALSE), 6 integer (numeric; plain digits). For kinds 1 and 2 `levels` holds, in column order, nlev levels (a nominal column's levels; the strings of a character
// column, the value being the 1-based index into them); a ' or \ in them is escaped with a backslash as write.arff does. Names with a blank are double-quoted and ones that do not start
// with a letter are prefixed with X. A NaN is taken as NA. eol ends every line but "@data", which write.arff always ends with "\n".
fn write(a: *mem.Arena, relation: str, names: []const str, levels: []const str, t: Arff, eol: str) -> (str, err) {
    // everything that stays allocated comes before the builder, which must be the last claim on the arena
    let (rel, re) = sys.make_name(a, relation)
    if re != ok { ret ("", re) }
    // a POSIXct column's format: 0 date, 1 minutes, 2 seconds
    let (pfmt, pe) = mem.alloc[u8](a, t.ncols + 1usize)
    if pe != ok { ret ("", pe) }
    let (sig, se) = mem.alloc[u8](a, 16usize)
    if se != ok { ret ("", se) }
    let (b0, e0) = str.builder(a, 4096usize)
    if e0 != ok { ret ("", e0) }
    var b = b0
    let _ = str.push(&b, "@relation ")
    push_spquote(&b, rel)
    let _ = str.push(&b, eol)
    var lbase = 0usize
    var j = 0usize
    while j < t.ncols {
        let _ = str.push(&b, "@attribute ")
        push_spquote(&b, names[j])
        let k = t.kind[j]
        if k == 1u8 {
            let _ = str.push(&b, " {")
            var l = 0usize
            while l < t.nlev[j] {
                if l > 0usize { let _ = str.push_byte(&b, 44u8) }
                quote_level(&b, levels[lbase + l])
                l += 1usize
            }
            let _ = str.push_byte(&b, 125u8)
        } else if k == 2u8 {
            let _ = str.push(&b, " string")
        } else if k == 3u8 {
            let _ = str.push(&b, " date \"yyyy-MM-dd\"")
        } else if k == 4u8 {
            let _ = str.push(&b, " date \"yyyy-MM-dd HH:mm:ss\"")
        } else {
            let _ = str.push(&b, " numeric")
        }
        if k == 1u8 || k == 2u8 { lbase += t.nlev[j] }
        if k == 4u8 {
            var allmid = true
            var allsec = true
            var r = 0usize
            while r < t.nrows {
                let v = t.values[r * t.ncols + j]
                if v == v {
                    let s = i64(math_floor(v))
                    if s % 86400i64 != 0i64 { allmid = false }
                    if s % 60i64 != 0i64 { allsec = false }
                }
                r += 1usize
            }
            pfmt[j] = 2u8
            if allmid { pfmt[j] = 0u8 }
        }
        let _ = str.push(&b, eol)
        j += 1usize
    }
    let _ = str.push(&b, "@data\n")
    var r = 0usize
    while r < t.nrows {
        var base2 = 0usize
        j = 0usize
        while j < t.ncols {
            if j > 0usize { let _ = str.push_byte(&b, 44u8) }
            let v = t.values[r * t.ncols + j]
            let k = t.kind[j]
            if v != v {
                let _ = str.push_byte(&b, 63u8)
            } else if k == 1u8 || k == 2u8 {
                quote_level(&b, levels[base2 + usize(v) - 1usize])
            } else if k == 3u8 {
                let _ = str.push_byte(&b, 39u8)
                push_date(&b, i64(math_floor(v)))
                let _ = str.push_byte(&b, 39u8)
            } else if k == 4u8 {
                let s = i64(math_floor(v))
                var days = s / 86400i64
                var rem = s % 86400i64
                if rem < 0i64 {
                    rem += 86400i64
                    days -= 1i64
                }
                let _ = str.push_byte(&b, 39u8)
                push_date(&b, days)
                if pfmt[j] >= 1u8 {
                    let _ = str.push_byte(&b, 32u8)
                    push2(&b, rem / 3600i64)
                    let _ = str.push_byte(&b, 58u8)
                    push2(&b, rem / 60i64 % 60i64)
                    if pfmt[j] == 2u8 {
                        let _ = str.push_byte(&b, 58u8)
                        push2(&b, rem % 60i64)
                    }
                }
                let _ = str.push_byte(&b, 39u8)
            } else if k == 5u8 {
                if v != 0.0f64 { let _ = str.push(&b, "TRUE") } else { let _ = str.push(&b, "FALSE") }
            } else if k == 6u8 {
                let _ = str.push_i64(&b, i64(v))
            } else {
                let pe2 = push_r15(a, &b, sig, v)
                if pe2 != ok { ret ("", pe2) }
            }
            if k == 1u8 || k == 2u8 { base2 += t.nlev[j] }
            j += 1usize
        }
        let _ = str.push(&b, eol)
        r += 1usize
    }
    ret (str.done(&b), ok)
}

fn math_floor(v: f64) -> f64 {
    let t = f64(i64(v))
    if t > v { ret t - 1.0f64 }
    ret t
}

fn push2(b: *str.Builder, v: i64) {
    if v < 10i64 { let _ = str.push_byte(b, 48u8) }
    let _ = str.push_i64(b, v)
}

// yyyy-MM-dd of a day number (the year as R's format prints it: at least four digits)
fn push_date(b: *str.Builder, days: i64) {
    let (y, m, d) = time.civil_from_days(days)
    if y >= 0i64 && y < 1000i64 { let _ = str.push_byte(b, 48u8) }
    if y >= 0i64 && y < 100i64 { let _ = str.push_byte(b, 48u8) }
    if y >= 0i64 && y < 10i64 { let _ = str.push_byte(b, 48u8) }
    let _ = str.push_i64(b, y)
    let _ = str.push_byte(b, 45u8)
    push2(b, m)
    let _ = str.push_byte(b, 45u8)
    push2(b, d)
}

// spquote: an X in front of a name that does not start with a letter, double quotes around one with a blank
fn push_spquote(b: *str.Builder, s: str) {
    var quote = false
    var i = 0usize
    while i < s.len {
        if s[i] == 32u8 { quote = true }
        i += 1usize
    }
    var x = true
    if s.len > 0usize {
        let c = s[0usize]
        if (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) { x = false }
    }
    if x { quote = false }
    if x {
        // the blank test is on the prefixed text, which has the same blanks
        i = 0usize
        while i < s.len {
            if s[i] == 32u8 { quote = true }
            i += 1usize
        }
    }
    if quote { let _ = str.push_byte(b, 34u8) }
    if x { let _ = str.push_byte(b, 88u8) }
    let _ = str.push(b, s)
    if quote { let _ = str.push_byte(b, 34u8) }
}

// a double as write.table prints it, digits = 15: the fewest significant digits (at most 15) that show the value rounded to 15, in fixed notation unless scientific is narrower
fn push_r15(a: *mem.Arena, b: *str.Builder, sig: []u8, v: f64) -> err {
    if v == 0.0f64 {
        let _ = str.push_byte(b, 48u8)
        ret ok
    }
    var x = v
    if v < 0.0f64 { x = 0.0f64 - v }
    if x > 1.0e300f64 {
        if x > 1.7976931348623157e308f64 {
            if v < 0.0f64 { let _ = str.push_byte(b, 45u8) }
            let _ = str.push(b, "Inf")
            ret ok
        }
        ret str.push_f64(b, v)
    }
    if x < 1.0e-80f64 { ret str.push_f64(b, v) }
    let start = mem.mark(a)
    let (bb, be) = str.builder(a, 512usize)
    if be != ok { ret be }
    var w = bb
    let fe = str.push_f64_fixed(&w, x, 99u8)
    if fe != ok { ret fe }
    let txt = str.done(&w)
    let (dg, de) = mem.alloc[u8](a, txt.len + 20usize)
    if de != ok { ret de }
    var n = 0usize
    var intlen = 0usize
    var seen_point = false
    var i = 0usize
    while i < txt.len {
        if txt[i] == 46u8 {
            seen_point = true
        } else {
            dg[n] = txt[i] - 48u8
            n += 1usize
            if !seen_point { intlen += 1usize }
        }
        i += 1usize
    }
    var z = 0usize
    while z < 20usize {
        dg[n + z] = 0u8
        z += 1usize
    }
    var fnz = 0usize
    while fnz < n && dg[fnz] == 0u8 { fnz += 1usize }
    var e10 = i64(intlen) - 1i64 - i64(fnz)
    var q = 0usize
    while q < 15usize {
        sig[q] = dg[fnz + q]
        q += 1usize
    }
    let next = dg[fnz + 15usize]
    var rest = false
    q = fnz + 16usize
    while q < n {
        if dg[q] != 0u8 { rest = true }
        q += 1usize
    }
    var up = false
    if next > 5u8 { up = true }
    if next == 5u8 && (rest || sig[14usize] % 2u8 == 1u8) { up = true }
    if up {
        var c = 14i64
        var carry = true
        while carry && c >= 0i64 {
            if sig[usize(c)] == 9u8 {
                sig[usize(c)] = 0u8
                c -= 1i64
            } else {
                sig[usize(c)] += 1u8
                carry = false
            }
        }
        if carry {
            sig[0usize] = 1u8
            e10 += 1i64
        }
    }
    var nsig = 15usize
    while nsig > 1usize && sig[nsig - 1usize] == 0u8 { nsig -= 1usize }
    mem.reset(a, start)
    var neg = 0i64
    if v < 0.0f64 { neg = 1i64 }
    var left = 1i64
    if e10 >= 0i64 { left = e10 + 1i64 }
    var rgt = i64(nsig) - e10 - 1i64
    if rgt < 0i64 { rgt = 0i64 }
    var wf = neg + left
    if rgt > 0i64 { wf += rgt + 1i64 }
    var expw = 2i64
    if e10 >= 100i64 || e10 <= -100i64 { expw = 3i64 }
    var ws = neg + 1i64 + expw + 2i64
    if nsig > 1usize { ws += i64(nsig) }
    if v < 0.0f64 { let _ = str.push_byte(b, 45u8) }
    if wf <= ws {
        // sprintf("%.*f"): the value itself to rgt decimals, so a number past 15 digits shows its true digits
        let fe2 = str.push_f64_fixed(b, x, u8(rgt))
        if fe2 != ok { ret fe2 }
    } else {
        let _ = str.push_byte(b, 48u8 + sig[0usize])
        if nsig > 1usize {
            let _ = str.push_byte(b, 46u8)
            var p = 1usize
            while p < nsig {
                let _ = str.push_byte(b, 48u8 + sig[p])
                p += 1usize
            }
        }
        let _ = str.push_byte(b, 101u8)
        var ae = e10
        if e10 < 0i64 {
            let _ = str.push_byte(b, 45u8)
            ae = 0i64 - e10
        } else {
            let _ = str.push_byte(b, 43u8)
        }
        if ae < 10i64 { let _ = str.push_byte(b, 48u8) }
        let _ = str.push_i64(b, ae)
    }
    ret ok
}

fn quote_level(b: *str.Builder, s: str) {
    let _ = str.push_byte(b, 39u8)
    var i = 0usize
    while i < s.len {
        if s[i] == 39u8 || s[i] == 92u8 { let _ = str.push_byte(b, 92u8) }
        let _ = str.push_byte(b, s[i])
        i += 1usize
    }
    let _ = str.push_byte(b, 39u8)
}
