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
type Var = struct { kind: u8, rows: usize, cols: usize, count: usize, sum: f64, isum: f64 }

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
                    s += number(t, p, q)
                    got += 1usize
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
            while p < l2 {
                while p < l2 && is_space(t[p]) { p += 1usize }
                var q = p
                while q < l2 && !is_space(t[q]) { q += 1usize }
                if q > p { s += number(t, p, q) }
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
            while p < l2 {
                while p < l2 && is_space(t[p]) { p += 1usize }
                var q = p
                while q < l2 && !is_space(t[q]) { q += 1usize }
                if q > p {
                    let (re, ci) = complex_tok(t, p, q)
                    s += re
                    im += ci
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
                cur = nx
                r += 1usize
            }
            cur = skip_to_name(t, cur)
            j += 1usize
        }
        v.count = nr * nc
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
    while i < t.len {
        let le = line_end(t, i)
        if starts(t, i, "# type: ") {
            if n >= 64usize { ret (out, TooMany) }
            let (v, cur) = read_item(t, i)
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
