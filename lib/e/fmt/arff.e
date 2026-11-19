// ARFF (Weka) reader as foreign::read.arff takes it for dense data: @relation, @attribute (numeric, real, integer, string, date and nominal sets),
// @data rows with '?' for a missing value, % comments and quoted fields. Numeric and integer columns keep their values; a nominal value becomes its
// 1-based rank in the sorted set of declared levels (the factor code, as read.arff sorts the levels); string columns are recorded as such and read as NaN.
// A date column holds seconds since 1970-01-01 UTC. Its format is the attribute's own (Weka style, converted as read.arff converts it with
// ISO_8601_to_POSIX_datetime_format, the chain of first-occurrence substitutions) or the default "%Y-%m-%d %H:%M:%S"; the text is parsed the way
// strptime does it (trailing input ignored, numbers up to their width, days checked against the month). A value that does not parse is NaN.
// A sparse row ('{' first) and a relational attribute are errors, as read.arff reports them.
//
// The directives Y y m d H M S j set the time; w and U are read and ignored, as R does. Any other directive makes the value NaN.
// Ceiling: R fills a month or day that the format lacks from today's date; this reader leaves it at January 1st (1970), so such a value differs.
// Weights are not here.

use e.mem
use e.str

error Malformed
error TooMany

// kind: 0 numeric, 1 nominal, 2 string, 3 date
type Arff = struct { ncols: usize, nrows: usize, kind: []u8, nlev: []usize, values: []f64 }

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

// the end of the field starting at `at` within [at, end): quoted fields end at the closing quote; others at a comma; returns (start, stop, next)
fn field(t: str, at: usize, end: usize) -> (usize, usize, usize) {
    var i = at
    while i < end && is_space(t[i]) { i += 1usize }
    if i < end && (t[i] == 39u8 || t[i] == 34u8) {
        let q = t[i]
        let s = i + 1usize
        var j = s
        while j < end && t[j] != q { j += 1usize }
        var nx = j + 1usize
        while nx < end && is_space(t[nx]) { nx += 1usize }
        if nx < end && t[nx] == 44u8 { nx += 1usize }
        ret (s, j, nx)
    }
    var j = i
    while j < end && t[j] != 44u8 { j += 1usize }
    var e = j
    while e > i && is_space(t[e - 1usize]) { e -= 1usize }
    var nx = j
    if nx < end { nx += 1usize }
    ret (i, e, nx)
}

fn same(t: str, a: usize, b: usize, c: usize, d: usize) -> bool {
    if b - a != d - c { ret false }
    var i = 0usize
    while i < b - a {
        if t[a + i] != t[c + i] { ret false }
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
fn strptime(f: []u8, s: str) -> f64 {
    let bad = 0.0f64 / 0.0f64
    var y = 1970i64
    var mo = 1i64
    var d = 1i64
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
            if dc == 89u8 { y = v }
            if dc == 121u8 {
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
    var days = 0i64
    if yday > 0i64 {
        days = days_from_civil(y, 1i64, 1i64) + yday - 1i64
    } else {
        if d > days_in_month(y, mo) { ret bad }
        days = days_from_civil(y, mo, d)
    }
    ret f64(days * 86400i64 + hh * 3600i64 + mi * 60i64 + ss)
}

fn parse(a: *mem.Arena, t: str) -> (Arff, err) {
    var out: Arff = zero
    // pass 1: the attributes and the line where the data start
    var cols = 0usize
    var i = 0usize
    var data_at = t.len
    let (kind, e1) = mem.alloc[u8](a, 256usize)
    if e1 != ok { ret (out, e1) }
    let (nlev, e2) = mem.alloc[usize](a, 256usize)
    if e2 != ok { ret (out, e2) }
    // level boundaries: lv_s[c * 64 + l], lv_e likewise
    let (lv_s, e3) = mem.alloc[usize](a, 256usize * 64usize)
    if e3 != ok { ret (out, e3) }
    let (lv_e, e4) = mem.alloc[usize](a, 256usize * 64usize)
    if e4 != ok { ret (out, e4) }
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
                    var n = 0usize
                    p += 1usize
                    let close = le
                    var cl = p
                    while cl < close && t[cl] != 125u8 { cl += 1usize }
                    while p < cl {
                        let (fs, fe, nx) = field(t, p, cl)
                        if n < 64usize {
                            lv_s[cols * 64usize + n] = fs
                            lv_e[cols * 64usize + n] = fe
                            n += 1usize
                        }
                        p = nx
                    }
                    nlev[cols] = n
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
                } else {
                    kind[cols] = 0u8
                }
                cols += 1usize
            } else if starts_ci(t, s, "@data") {
                data_at = le + 1usize
                break
            }
        }
        i = le + 1usize
    }
    // pass 2: count the data rows and read them
    var rows = 0usize
    i = data_at
    while i < t.len {
        var le = i
        while le < t.len && t[le] != 10u8 { le += 1usize }
        var s = i
        while s < le && is_space(t[s]) { s += 1usize }
        if s < le && t[s] != 37u8 { rows += 1usize }
        i = le + 1usize
    }
    let (vals, e5) = mem.alloc[f64](a, rows * cols + 1usize)
    if e5 != ok { ret (out, e5) }
    var r = 0usize
    i = data_at
    while i < t.len {
        var le = i
        while le < t.len && t[le] != 10u8 { le += 1usize }
        var s = i
        while s < le && is_space(t[s]) { s += 1usize }
        if s < le && t[s] != 37u8 {
            if t[s] == 123u8 { ret (out, Malformed) }
            var p = s
            var c = 0usize
            while c < cols {
                let (fs, fe, nx) = field(t, p, le)
                p = nx
                var v = 0.0f64 / 0.0f64
                let miss = fe == fs + 1usize && t[fs] == 63u8
                if !miss && fe > fs {
                    if kind[c] == 0u8 {
                        let (x, pe) = str.parse_f64(t[fs..fe])
                        if pe == ok { v = x }
                    } else if kind[c] == 3u8 {
                        v = strptime(fbuf[c * 128usize..c * 128usize + fmt_n[c]], t[fs..fe])
                    } else if kind[c] == 1u8 {
                        var l = 0usize
                        while l < nlev[c] {
                            if same(t, fs, fe, lv_s[c * 64usize + l], lv_e[c * 64usize + l]) {
                                v = f64(sorted_rank(t, lv_s, lv_e, c * 64usize, nlev[c], l))
                                break
                            }
                            l += 1usize
                        }
                    }
                }
                vals[r * cols + c] = v
                c += 1usize
            }
            r += 1usize
        }
        i = le + 1usize
    }
    out.ncols = cols
    out.nrows = rows
    out.kind = kind[0usize..cols]
    out.nlev = nlev[0usize..cols]
    out.values = vals
    ret (out, ok)
}

// the code of level l of a column among its declared levels sorted bytewise (foreign::read.arff returns the factor levels sorted)
fn sorted_rank(t: str, lv_s: []const usize, lv_e: []const usize, base: usize, n: usize, l: usize) -> usize {
    var rank = 1usize
    var o = 0usize
    while o < n {
        if o != l && less(t, lv_s[base + o], lv_e[base + o], lv_s[base + l], lv_e[base + l]) { rank += 1usize }
        o += 1usize
    }
    ret rank
}

fn less(t: str, a: usize, b: usize, c: usize, d: usize) -> bool {
    var i = 0usize
    while i < b - a && i < d - c {
        if t[a + i] != t[c + i] { ret t[a + i] < t[c + i] }
        i += 1usize
    }
    ret b - a < d - c
}

// foreign::write.arff for numeric and factor columns: "@relation <relation>", one "@attribute <name> numeric" or "@attribute <name> {'l1','l2',...}" per column, "@data", then the
// rows as comma-separated values (a missing value is ?, a nominal value its quoted level, a number its shortest round-trip text). t holds the columns (kind 0 numeric, 1 nominal
// with the 1-based level code in values and nlev levels); names and levels (the levels of the nominal columns in column order, flat) are the labels. Characters ' and \ in a
// level are escaped with a backslash as write.arff does. Ceiling: R prints numbers with 15 significant digits, this the shortest text that reads back, so the two agree for numbers
// with at most 15 significant digits.
fn write(a: *mem.Arena, relation: str, names: []const str, levels: []const str, t: Arff) -> (str, err) {
    let (b0, e0) = str.builder(a, 4096usize)
    if e0 != ok { ret ("", e0) }
    var b = b0
    let _ = str.push(&b, "@relation ")
    let _ = str.push(&b, relation)
    let _ = str.push_byte(&b, 10u8)
    var lbase = 0usize
    var j = 0usize
    while j < t.ncols {
        let _ = str.push(&b, "@attribute ")
        let _ = str.push(&b, names[j])
        if t.kind[j] == 1u8 {
            let _ = str.push(&b, " {")
            var l = 0usize
            while l < t.nlev[j] {
                if l > 0usize { let _ = str.push_byte(&b, 44u8) }
                quote_level(&b, levels[lbase + l])
                l += 1usize
            }
            let _ = str.push_byte(&b, 125u8)
            lbase += t.nlev[j]
        } else {
            let _ = str.push(&b, " numeric")
        }
        let _ = str.push_byte(&b, 10u8)
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
            if v != v {
                let _ = str.push_byte(&b, 63u8)
            } else if t.kind[j] == 1u8 {
                quote_level(&b, levels[base2 + usize(v) - 1usize])
            } else {
                let _ = str.push_f64(&b, v)
            }
            if t.kind[j] == 1u8 { base2 += t.nlev[j] }
            j += 1usize
        }
        let _ = str.push_byte(&b, 10u8)
        r += 1usize
    }
    ret (str.done(&b), ok)
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
