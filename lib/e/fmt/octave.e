// Octave text-format reader (the files `save -text` writes) as foreign::read.octave reads them: "# name: x" starts a variable, "# type: scalar", "matrix"
// (with "# rows: r" and "# columns: c" followed by r lines of c numbers) or "string" ("# elements: 1", "# length: n" and the text line); lines starting with
// "# Created" or "% " are comments. Numbers are read as f64 (Inf, -Inf and NA/NaN accepted); a string counts as one element whose sum is its code units.
//
// Not here: integer and complex types, bool matrices, ranges, cells, structs and N-d arrays.

use e.mem
use e.str

error Malformed
error TooMany

// kind: 0 scalar, 1 matrix, 2 string
type Var = struct { kind: u8, rows: usize, cols: usize, count: usize, sum: f64 }

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
            var v: Var = zero
            let ts = i + 8usize
            var cur = le + 1usize
            if starts(t, ts, "scalar") {
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
            } else if starts(t, ts, "matrix") {
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
            } else if starts(t, ts, "string") {
                v.kind = 2u8
                var l2 = line_end(t, cur)
                cur = l2 + 1usize
                l2 = line_end(t, cur)
                let len = read_uint(t, cur + 9usize, l2)
                cur = l2 + 1usize
                l2 = line_end(t, cur)
                var s = 0.0f64
                var k = 0usize
                while k < len && cur + k < l2 {
                    s += f64(t[cur + k])
                    k += 1usize
                }
                v.rows = 1usize
                v.cols = 1usize
                v.count = 1usize
                v.sum = s
                cur = l2 + 1usize
            } else {
                ret (out, Malformed)
            }
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
