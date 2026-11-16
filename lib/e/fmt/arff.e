// ARFF (Weka) reader as foreign::read.arff takes it for dense data: @relation, @attribute (numeric, real, integer, string, date and nominal sets),
// @data rows with '?' for a missing value, % comments and quoted fields. Numeric and integer columns keep their values; a nominal value becomes its
// 1-based rank in the sorted set of declared levels (the factor code, as read.arff sorts the levels); string and date columns are recorded as such and read as NaN.
//
// Not here: sparse rows, relational attributes, date parsing and weights.

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
                } else if starts_ci(t, p, "date") {
                    kind[cols] = 3u8
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
