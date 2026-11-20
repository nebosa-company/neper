// Octave text-format reader (the files `save -text` writes) as foreign::read.octave reads them: "# name: x" starts a variable, "# type: scalar", "matrix"
// (with "# rows: r" and "# columns: c" followed by r lines of c numbers) or "string" ("# elements: 1", "# length: n" and the text line); lines starting with
// "# Created" or "% " are comments. Numbers are read as f64 (Inf, -Inf and NA/NaN accepted); a string counts as one element whose sum is its code units.
// Bool values and bool matrices are 0 or 1. A complex value keeps its real parts in sum and its imaginary parts in isum. A range (base, limit, increment)
// has the elements read.octave's seq.int gives. An integer type is unknown to read.octave, which returns NULL for it: here it is a variable with no elements.
//
// An N-d array ("# ndims: d", the dimensions, then the numbers one per line) and a string array (several "# elements") are read as well.
// Lists, structs (the old "# type: struct") and cells are read recursively. An unknown type skips to the next "# name:" line as read.octave does.

use e.mem
use e.str

error Malformed
error TooMany

// kind: 0 scalar, 1 matrix, 2 string, 3 no elements (an unknown type), 4 list, struct or cell (count its elements, sum and isum those of everything inside)
type Var = struct { kind: u8, rows: usize, cols: usize, count: usize, sum: f64, isum: f64, wsum: f64, wisum: f64, nhash: f64 }

type Octave = struct { nvars: usize, vars: []Var }

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 13u8 }

fn starts(t: str, at: usize, w: str) -> bool {
    if at + w.len > t.len { ret false }
    var i = 0usize
    while i < w.len {
        if t[at + i] != w[i] { ret false }
        i += 1usize
    }
    ret true
}

fn line_end(t: str, at: usize) -> usize {
    var e = at
    while e < t.len && t[e] != 10u8 { e += 1usize }
    ret e
}

fn read_uint(t: str, at: usize, end: usize) -> usize {
    var i = at
    while i < end && is_space(t[i]) { i += 1usize }
    var v = 0usize
    while i < end && t[i] >= 48u8 && t[i] <= 57u8 {
        v = v * 10usize + usize(t[i] - 48u8)
        i += 1usize
    }
    ret v
}

fn number(t: str, s: usize, e: usize) -> f64 {
    if e - s == 3usize && t[s] == 73u8 { ret 1.0e308f64 * 10.0f64 }
    if e - s == 4usize && t[s] == 45u8 && t[s + 1usize] == 73u8 { ret 0.0f64 - 1.0e308f64 * 10.0f64 }
    if e - s == 2usize && t[s] == 78u8 && t[s + 1usize] == 65u8 { ret 0.0f64 / 0.0f64 }
    if e - s == 3usize && t[s] == 78u8 { ret 0.0f64 / 0.0f64 }
    let (x, pe) = str.parse_f64(t[s..e])
    if pe != ok { ret 0.0f64 / 0.0f64 }
    ret x
}

// the line [at, end) with trailing blanks dropped is exactly w
fn is_line(t: str, at: usize, end: usize, w: str) -> bool {
    var e = end
    while e > at && is_space(t[e - 1usize]) { e -= 1usize }
    if e - at != w.len { ret false }
    ret starts(t, at, w)
}

// a complex value "(re,im)" (or a real one) over [s, e): its real and imaginary parts
fn complex_tok(t: str, s: usize, e: usize) -> (f64, f64) {
    var a = s
    var b = e
    if b > a && t[a] == 40u8 { a += 1usize }
    if b > a && t[b - 1usize] == 41u8 { b -= 1usize }
    var c = a
    while c < b && t[c] != 44u8 { c += 1usize }
    if c >= b { ret (number(t, a, b), 0.0f64) }
    ret (number(t, a, c), number(t, c + 1usize, b))
}

// the three numbers of a line [s, e): base, limit and increment of a range
fn range_line(t: str, s: usize, e: usize) -> (f64, f64, f64) {
    var x0 = 0.0f64
    var x1 = 0.0f64
    var x2 = 0.0f64
    var k = 0usize
    var p = s
    while p < e && k < 3usize {
        while p < e && is_space(t[p]) { p += 1usize }
        var q = p
        while q < e && !is_space(t[q]) { q += 1usize }
        if q > p {
            let x = number(t, p, q)
            if k == 0usize { x0 = x }
            if k == 1usize { x1 = x }
            if k == 2usize { x2 = x }
            k += 1usize
        }
        p = q
    }
    ret (x0, x1, x2)
}

// the start of the next "# name: " line at or after at, or the end of the text (read.octave's skip_lines_to_next_item)
fn skip_to_name(t: str, at: usize) -> usize {
    var c = at
    while c < t.len {
        if starts(t, c, "# name: ") { ret c }
        c = line_end(t, c) + 1usize
    }
    ret t.len
}

// the item whose "# type: " line starts at i, and the offset just after it
fn read_item(t: str, i: usize) -> (Var, usize) {
    let le = line_end(t, i)
    var v: Var = zero
    let ts = i + 8usize
    var cur = le + 1usize
    if is_line(t, ts, le, "scalar") || is_line(t, ts, le, "bool") {
        v.kind = 0u8
        let l2 = line_end(t, cur)
        var s = cur
        while s < l2 && is_space(t[s]) { s += 1usize }
        var e = l2
        while e > s && is_space(t[e - 1usize]) { e -= 1usize }
        v.rows = 1usize
        v.cols = 1usize
        v.count = 1usize
        v.sum = number(t, s, e)
        v.wsum = v.sum
        cur = l2 + 1usize
    } else if is_line(t, ts, le, "matrix") && starts(t, cur, "# ndims:") {
        // an N-d array: the dimensions on one line, then prod(dims) numbers, one per line (read.octave scans them across lines)
        v.kind = 1u8
        var l2 = line_end(t, cur)
        cur = l2 + 1usize
        l2 = line_end(t, cur)
        var total = 1usize
        var p = cur
        while p < l2 {
            while p < l2 && is_space(t[p]) { p += 1usize }
            var q = p
            while q < l2 && !is_space(t[q]) { q += 1usize }
            if q > p { total = total * usize(number(t, p, q)) }
            p = q
        }
        cur = l2 + 1usize
        var got = 0usize
        var s = 0.0f64
        while got < total && cur < t.len {
            l2 = line_end(t, cur)
            p = cur
            while p < l2 && got < total {
                while p < l2 && is_space(t[p]) { p += 1usize }
                var q = p
                while q < l2 && !is_space(t[q]) { q += 1usize }
                if q > p {
                    let x = number(t, p, q)
                    s += x
                    got += 1usize
                    v.wsum += x * f64(got)
                }
                p = q
            }
            cur = l2 + 1usize
        }
        v.rows = total
        v.cols = 1usize
        v.count = total
        v.sum = s
    } else if is_line(t, ts, le, "matrix") || is_line(t, ts, le, "bool matrix") {
        v.kind = 1u8
        var l2 = line_end(t, cur)
        v.rows = read_uint(t, cur + 8usize, l2)
        cur = l2 + 1usize
        l2 = line_end(t, cur)
        v.cols = read_uint(t, cur + 11usize, l2)
        cur = l2 + 1usize
        v.count = v.rows * v.cols
        var r = 0usize
        var s = 0.0f64
        while r < v.rows {
            l2 = line_end(t, cur)
            var p = cur
            var cc = 0usize
            while p < l2 {
                while p < l2 && is_space(t[p]) { p += 1usize }
                var q = p
                while q < l2 && !is_space(t[q]) { q += 1usize }
                if q > p {
                    let x = number(t, p, q)
                    s += x
                    v.wsum += x * f64(cc * v.rows + r + 1usize)
                    cc += 1usize
                }
                p = q
            }
            cur = l2 + 1usize
            r += 1usize
        }
        v.sum = s
    } else if is_line(t, ts, le, "complex scalar") {
        let l2 = line_end(t, cur)
        var s = cur
        while s < l2 && is_space(t[s]) { s += 1usize }
        var e = l2
        while e > s && is_space(t[e - 1usize]) { e -= 1usize }
        v.rows = 1usize
        v.cols = 1usize
        v.count = 1usize
        let (re, im) = complex_tok(t, s, e)
        v.sum = re
        v.isum = im
        v.wsum = re
        v.wisum = im
        cur = l2 + 1usize
    } else if is_line(t, ts, le, "complex matrix") {
        var l2 = line_end(t, cur)
        v.rows = read_uint(t, cur + 8usize, l2)
        cur = l2 + 1usize
        l2 = line_end(t, cur)
        v.cols = read_uint(t, cur + 11usize, l2)
        cur = l2 + 1usize
        v.count = v.rows * v.cols
        var r = 0usize
        var s = 0.0f64
        var im = 0.0f64
        while r < v.rows {
            l2 = line_end(t, cur)
            var p = cur
            var cc = 0usize
            while p < l2 {
                while p < l2 && is_space(t[p]) { p += 1usize }
                var q = p
                while q < l2 && !is_space(t[q]) { q += 1usize }
                if q > p {
                    let (re, ci) = complex_tok(t, p, q)
                    s += re
                    im += ci
                    let w = f64(cc * v.rows + r + 1usize)
                    v.wsum += re * w
                    v.wisum += ci * w
                    cc += 1usize
                }
                p = q
            }
            cur = l2 + 1usize
            r += 1usize
        }
        v.sum = s
        v.isum = im
    } else if is_line(t, ts, le, "range") {
        // the "# base, limit, increment" comment line, then the three numbers
        cur = line_end(t, cur) + 1usize
        let l2 = line_end(t, cur)
        let (base, limit, inc) = range_line(t, cur, l2)
        let tol = 0.0000000001f64
        var k = 0usize
        while k < 10000000usize {
            let x = base + f64(k) * inc
            var inside = x <= limit + tol
            if inc < 0.0f64 { inside = x >= limit - tol }
            if inc == 0.0f64 { inside = false }
            if !inside { break }
            k += 1usize
        }
        var s = 0.0f64
        var j = 0usize
        while j < k {
            s += base + f64(j) * inc
            v.wsum += (base + f64(j) * inc) * f64(j + 1usize)
            j += 1usize
        }
        v.rows = 1usize
        v.cols = k
        v.count = k
        v.sum = s
        cur = l2 + 1usize
    } else if is_line(t, ts, le, "string") || is_line(t, ts, le, "string array") {
        // "# elements: k", then for each element a "# length: n" line and its text line; the sum counts the code units of all of them
        v.kind = 2u8
        var l2 = line_end(t, cur)
        let k = read_uint(t, cur + 12usize, l2)
        cur = l2 + 1usize
        var s = 0.0f64
        var e = 0usize
        while e < k {
            l2 = line_end(t, cur)
            let len = read_uint(t, cur + 9usize, l2)
            cur = l2 + 1usize
            l2 = line_end(t, cur)
            var c = 0usize
            while c < len && cur + c < l2 {
                s += f64(t[cur + c])
                c += 1usize
            }
            cur = l2 + 1usize
            e += 1usize
        }
        v.rows = 1usize
        v.cols = 1usize
        v.count = k
        v.sum = s
    } else if is_line(t, ts, le, "list") || is_line(t, ts, le, "struct") {
        // "# length: n", then n elements, each a name line and an item
        v.kind = 4u8
        let l2 = line_end(t, cur)
        let k = read_uint(t, cur + 10usize, l2)
        cur = l2 + 1usize
        var e = 0usize
        while e < k && cur < t.len {
            cur = line_end(t, cur) + 1usize
            let (c, nc) = read_item(t, cur)
            v.sum += c.sum
            v.isum += c.isum
            v.wsum += c.wsum
            v.wisum += c.wisum
            cur = nc
            e += 1usize
        }
        v.count = k
    } else if is_line(t, ts, le, "cell") {
        // "# rows: r", "# columns: c", then the elements by column, each a name line and an item; read.octave skips to the next "# name:" line after every column
        v.kind = 4u8
        var l2 = line_end(t, cur)
        let nr = read_uint(t, cur + 8usize, l2)
        cur = l2 + 1usize
        l2 = line_end(t, cur)
        let nc = read_uint(t, cur + 11usize, l2)
        cur = l2 + 1usize
        var j = 0usize
        while j < nc {
            var r = 0usize
            while r < nr && cur < t.len {
                cur = line_end(t, cur) + 1usize
                let (c, nx) = read_item(t, cur)
                v.sum += c.sum
                v.isum += c.isum
                v.wsum += c.wsum
                v.wisum += c.wisum
                cur = nx
                r += 1usize
            }
            cur = skip_to_name(t, cur)
            j += 1usize
        }
        v.count = nr * nc
        v.rows = nr
        v.cols = nc
    } else {
        v.kind = 3u8
        cur = skip_to_name(t, cur)
    }
    ret (v, cur)
}

fn parse(a: *mem.Arena, t: str) -> (Octave, err) {
    var out: Octave = zero
    let (vars, e1) = mem.alloc[Var](a, 64usize)
    if e1 != ok { ret (out, e1) }
    var n = 0usize
    var i = 0usize
    var nh = 0.0f64
    while i < t.len {
        let le = line_end(t, i)
        if starts(t, i, "# name: ") {
            // nhash: each byte of the name times its 1-based position, to compare against names(read.octave(...))
            nh = 0.0f64
            var k = i + 8usize
            while k < le && t[k] != 13u8 {
                nh += f64(t[k]) * f64(k - i - 7usize)
                k += 1usize
            }
            i = le + 1usize
        } else if starts(t, i, "# type: ") {
            if n >= 64usize { ret (out, TooMany) }
            let (v0, cur) = read_item(t, i)
            var v = v0
            v.nhash = nh
            vars[n] = v
            n += 1usize
            i = cur
        } else {
            i = le + 1usize
        }
    }
    out.nvars = n
    out.vars = vars[0usize..n]
    ret (out, ok)
}

// Error behaviour: strict() follows read.octave's control flow line by line (readLines, scan, as.integer, stopifnot) and reports whether R stops with an
// error (Malformed) and how many elements each top-level variable has; values are read by parse(). A line read.octave hands to scan() must hold numbers
// (NA, NaN, Inf and -Inf included), the extents of a matrix, list or cell must be whole numbers, and readLines past the end of the file gives nothing,
// which is an error wherever R then switches on or subscripts it.
type Strict = struct { nvars: usize, counts: []usize }

type St = struct { lines: []str, at: usize, n: usize, bad: bool }

fn s_eof(st: *St) -> bool { ret st.at >= st.n }

fn s_take(st: *St) -> str {
    let l = st.lines[st.at]
    st.at += 1usize
    ret l
}

// gsub(w, "", l) for a prefix w
fn s_after(l: str, w: str) -> str {
    if starts(l, 0usize, w) { ret l[w.len..l.len] }
    ret l
}

fn s_trim(l: str) -> str {
    var a = 0usize
    var b = l.len
    while a < b && is_space(l[a]) { a += 1usize }
    while b > a && is_space(l[b - 1usize]) { b -= 1usize }
    ret l[a..b]
}

// as.integer or as.numeric used as a length or extent: a whole number from 0 to 2^31
fn s_extent(l: str) -> (usize, bool) {
    let s = s_trim(l)
    if s.len == 0usize { ret (0usize, false) }
    let (x, pe) = str.parse_f64(s)
    if pe != ok { ret (0usize, false) }
    if x != x || x < 0.0f64 || x > 2147483647.0f64 { ret (0usize, false) }
    ret (usize(x), true)
}

fn s_numeric(w: str) -> bool {
    if str.eq(w, "NA") || str.eq(w, "NaN") || str.eq(w, "Inf") || str.eq(w, "-Inf") || str.eq(w, "+Inf") { ret true }
    let (x, pe) = str.parse_f64(w)
    ret pe == ok
}

// the number of blank-separated tokens of a line, and whether scan() takes every one as a real
fn s_tokens(l: str) -> (usize, bool) {
    var n = 0usize
    var good = true
    var p = 0usize
    while p < l.len {
        while p < l.len && is_space(l[p]) { p += 1usize }
        var q = p
        while q < l.len && !is_space(l[q]) { q += 1usize }
        if q > p {
            n += 1usize
            if !s_numeric(l[p..q]) { good = false }
        }
        p = q
    }
    ret (n, good)
}

// scan(con, nlines = 1): the count of numbers on the next line, none at the end of the file
fn s_scan_line(st: *St) -> usize {
    if s_eof(st) { ret 0usize }
    let (n, good) = s_tokens(s_take(st))
    if !good { st.bad = true }
    ret n
}

// scan(con, n = total): numbers across lines until total are read or the file ends
fn s_scan_n(st: *St, total: usize) -> usize {
    var got = 0usize
    while got < total && !s_eof(st) {
        let (n, good) = s_tokens(s_take(st))
        if !good { st.bad = true }
        got += n
    }
    ret got
}

// skip_lines_to_next_item: stop just before the next "# name: " line
fn s_skip(st: *St) {
    while !s_eof(st) {
        if starts(st.lines[st.at], 0usize, "# name: ") { ret }
        st.at += 1usize
    }
}

// the pieces strsplit(l, ",") gives once "(" and ")" are removed: none for an empty string, and a trailing comma adds no empty piece
fn s_cpieces(l: str) -> usize {
    var n = 0usize
    var i = 0usize
    var last_comma = false
    var any = false
    while i < l.len {
        if l[i] != 40u8 && l[i] != 41u8 {
            any = true
            if l[i] == 44u8 { n += 1usize }
            last_comma = l[i] == 44u8
        }
        i += 1usize
    }
    if !any { ret 0usize }
    n += 1usize
    if last_comma { n -= 1usize }
    ret n
}

// seq.int(from, to, by): the number of elements, or false where R stops
fn s_range(x0: f64, x1: f64, by: f64) -> (usize, bool) {
    let del = x1 - x0
    if del == 0.0f64 { ret (1usize, true) }
    let n = del / by
    if n != n || n < 0.0f64 || n > 2147483647.0f64 { ret (0usize, false) }
    var ad = del
    if ad < 0.0f64 { ad = 0.0f64 - ad }
    var m = x1
    if m < 0.0f64 { m = 0.0f64 - m }
    var m0 = x0
    if m0 < 0.0f64 { m0 = 0.0f64 - m0 }
    if m0 > m { m = m0 }
    if ad / m < 0.000000000000022204f64 { ret (1usize, true) }
    ret (usize(n + 0.0000000001f64) + 1usize, true)
}

// the dimensions line of an N-d array: their product (an error when the line is missing, empty or not whole numbers)
fn s_dims(st: *St) -> usize {
    if s_eof(st) {
        st.bad = true
        ret 0usize
    }
    let l = s_take(st)
    let (n, good) = s_tokens(l)
    if !good || n == 0usize {
        st.bad = true
        ret 0usize
    }
    var total = 1usize
    var p = 0usize
    while p < l.len {
        while p < l.len && is_space(l[p]) { p += 1usize }
        var q = p
        while q < l.len && !is_space(l[q]) { q += 1usize }
        if q > p {
            let (d, dok) = s_extent(l[p..q])
            if !dok {
                st.bad = true
                ret 0usize
            }
            total = total * d
        }
        p = q
    }
    ret total
}

// kind 0 real, 1 bool, 2 complex
fn s_matrix(st: *St, kind: u8) -> usize {
    if s_eof(st) {
        st.bad = true
        ret 0usize
    }
    let l1 = s_take(st)
    if kind != 1u8 && !starts(l1, 0usize, "# rows:") {
        let total = s_dims(st)
        if st.bad { ret 0usize }
        if kind == 0u8 {
            let _ = s_scan_n(st, total)
        } else {
            // each element is "(re,im)": exactly two parts
            var r = 0usize
            while r < total && !s_eof(st) {
                if s_cpieces(s_take(st)) != 2usize { st.bad = true }
                r += 1usize
            }
        }
        ret total
    }
    let (nr, rok) = s_extent(s_after(l1, "# rows: "))
    if !rok || s_eof(st) {
        st.bad = true
        ret 0usize
    }
    let (nc, cok) = s_extent(s_after(s_take(st), "# columns: "))
    if !cok {
        st.bad = true
        ret 0usize
    }
    var r = 0usize
    while r < nr && !s_eof(st) {
        if kind == 2u8 {
            let _ = s_take(st)
        } else {
            let _ = s_scan_line(st)
        }
        r += 1usize
    }
    ret nr * nc
}

fn s_item(st: *St) -> usize {
    if s_eof(st) {
        st.bad = true
        ret 0usize
    }
    let ty = s_after(s_take(st), "# type: ")
    if str.eq(ty, "scalar") || str.eq(ty, "bool") { ret s_scan_line(st) }
    if str.eq(ty, "matrix") { ret s_matrix(st, 0u8) }
    if str.eq(ty, "bool matrix") { ret s_matrix(st, 1u8) }
    if str.eq(ty, "complex matrix") { ret s_matrix(st, 2u8) }
    if str.eq(ty, "complex scalar") {
        var pieces = 0usize
        if !s_eof(st) { pieces = s_cpieces(s_take(st)) }
        if pieces != 2usize { st.bad = true }
        ret 1usize
    }
    if str.eq(ty, "range") {
        if !s_eof(st) { st.at += 1usize }
        if s_eof(st) {
            st.bad = true
            ret 0usize
        }
        let l = s_take(st)
        let (n, good) = s_tokens(l)
        if !good || n != 3usize {
            st.bad = true
            ret 0usize
        }
        let (x0, x1, by) = range_line(l, 0usize, l.len)
        let (k, rok) = s_range(x0, x1, by)
        if !rok { st.bad = true }
        ret k
    }
    if str.eq(ty, "string") || str.eq(ty, "string array") {
        if s_eof(st) {
            st.bad = true
            ret 0usize
        }
        let (k, kok) = s_extent(s_after(s_take(st), "# elements: "))
        if !kok {
            st.bad = true
            ret 0usize
        }
        var got = 0usize
        while got < 2usize * k && !s_eof(st) {
            st.at += 1usize
            got += 1usize
        }
        ret (got + 1usize) / 2usize
    }
    if str.eq(ty, "list") || str.eq(ty, "struct") {
        if s_eof(st) {
            st.bad = true
            ret 0usize
        }
        let (k, kok) = s_extent(s_after(s_take(st), "# length: "))
        if !kok {
            st.bad = true
            ret 0usize
        }
        var i = 0usize
        while i < k && !st.bad {
            if !s_eof(st) { st.at += 1usize }
            let _ = s_item(st)
            i += 1usize
        }
        ret k
    }
    if str.eq(ty, "cell") {
        if s_eof(st) {
            st.bad = true
            ret 0usize
        }
        let (nr, rok) = s_extent(s_after(s_take(st), "# rows: "))
        if !rok || s_eof(st) {
            st.bad = true
            ret 0usize
        }
        let (nc, cok) = s_extent(s_after(s_take(st), "# columns: "))
        if !cok {
            st.bad = true
            ret 0usize
        }
        var j = 0usize
        while j < nc && !st.bad {
            var i = 0usize
            while i < nr && !st.bad {
                if !s_eof(st) { st.at += 1usize }
                let _ = s_item(st)
                i += 1usize
            }
            s_skip(st)
            j += 1usize
        }
        ret nr * nc
    }
    s_skip(st)
    ret 0usize
}

// the top level: the first line is skipped, then every line is a name and the item after it
fn strict(a: *mem.Arena, t: str) -> (Strict, err) {
    var out: Strict = zero
    var nl = 0usize
    var i = 0usize
    while i < t.len {
        nl += 1usize
        i = line_end(t, i) + 1usize
    }
    let (lines, e1) = mem.alloc[str](a, nl + 1usize)
    if e1 != ok { ret (out, e1) }
    let (counts, e2) = mem.alloc[usize](a, nl + 1usize)
    if e2 != ok { ret (out, e2) }
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
    var st: St = zero
    st.lines = lines[0usize..k]
    st.n = k
    if k > 0usize { st.at = 1usize }
    var n = 0usize
    while !s_eof(&st) && !st.bad {
        st.at += 1usize
        counts[n] = s_item(&st)
        n += 1usize
    }
    if st.bad { ret (out, Malformed) }
    out.nvars = n
    out.counts = counts[0usize..n]
    ret (out, ok)
}
