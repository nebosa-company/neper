// e.gfx.isoband against R's isoband: isolines and isobands over seeded grids (smooth, noisy,
// integer-valued with ties at the level, saddles, NA cells, irregular spacing).
// tests/oracle/isoband.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R
// isoband`; the layout is at the top of scripts/r_oracle/groups/isoband.R. Both sides
// canonicalise the paths: a closed path starts at its smallest (x, y), paths sort by their
// coordinates then length, and the three answers are x, y and the path number per point.

use e.gfx.isoband as iso
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Canon = struct { x: []f64, y: []f64, id: []f64 }

// Whether path p sorts before path q: the coordinates in order, then the shorter first.
fn less(px: []const f64, py: []const f64, pn: usize, qx: []const f64, qy: []const f64, qn: usize) -> bool {
    let n = pn
    var m = n
    if qn < m { m = qn }
    var i = 0usize
    while i < m {
        if px[i] != qx[i] { ret px[i] < qx[i] }
        if py[i] != qy[i] { ret py[i] < qy[i] }
        i += 1usize
    }
    ret pn < qn
}

fn canon(a: *mem.Arena, c: iso.Contours, ring: bool) -> Canon {
    let n = c.x.len
    let (rx, e1) = mem.alloc[f64](a, n + 1usize)
    let (ry, e2) = mem.alloc[f64](a, n + 1usize)
    let (start, e3) = mem.alloc[usize](a, n + 1usize)
    let (len, e4) = mem.alloc[usize](a, n + 1usize)
    if e1 != ok { os.exit(5) }
    if e2 != ok { os.exit(5) }
    if e3 != ok { os.exit(5) }
    if e4 != ok { os.exit(5) }
    var np = 0usize
    var at = 0usize
    var i = 0usize
    while i < n {
        var j = i
        while j < n && c.id[j] == c.id[i] { j += 1usize }
        var m = j - i
        let closed = ring || (m > 2usize && c.x[i] == c.x[j - 1usize] && c.y[i] == c.y[j - 1usize])
        if closed {
            if !ring { m -= 1usize }
            var k = 0usize
            var t = 1usize
            while t < m {
                if c.x[i + t] < c.x[i + k] || (c.x[i + t] == c.x[i + k] && c.y[i + t] < c.y[i + k]) { k = t }
                t += 1usize
            }
            // among the points equal to the smallest, the rotation that sorts first
            var best = k
            t = 0usize
            while t < m {
                if c.x[i + t] == c.x[i + k] && c.y[i + t] == c.y[i + k] && t != best {
                    var u = 0usize
                    var decided = false
                    while u < m && !decided {
                        let bx = c.x[i + (best + u) % m]
                        let by = c.y[i + (best + u) % m]
                        let cx = c.x[i + (t + u) % m]
                        let cy = c.y[i + (t + u) % m]
                        if cx != bx || cy != by {
                            decided = true
                            if cx < bx || (cx == bx && cy < by) { best = t }
                        }
                        u += 1usize
                    }
                }
                t += 1usize
            }
            k = best
            start[np] = at
            t = 0usize
            while t < m {
                rx[at] = c.x[i + (k + t) % m]
                ry[at] = c.y[i + (k + t) % m]
                at += 1usize
                t += 1usize
            }
            if !ring {
                rx[at] = rx[start[np]]
                ry[at] = ry[start[np]]
                at += 1usize
                m += 1usize
            }
            len[np] = m
        } else {
            start[np] = at
            var t = 0usize
            while t < m {
                rx[at] = c.x[i + t]
                ry[at] = c.y[i + t]
                at += 1usize
                t += 1usize
            }
            len[np] = m
        }
        np += 1usize
        i = j
    }
    // insertion sort of the paths
    let (order, e5) = mem.alloc[usize](a, np + 1usize)
    if e5 != ok { os.exit(5) }
    var p = 0usize
    while p < np {
        var q = p
        while q > 0usize && less(rx[start[p]..start[p] + len[p]], ry[start[p]..start[p] + len[p]], len[p], rx[start[order[q - 1usize]]..start[order[q - 1usize]] + len[order[q - 1usize]]], ry[start[order[q - 1usize]]..start[order[q - 1usize]] + len[order[q - 1usize]]], len[order[q - 1usize]]) {
            order[q] = order[q - 1usize]
            q -= 1usize
        }
        order[q] = p
        p += 1usize
    }
    let (ox, e6) = mem.alloc[f64](a, at + 1usize)
    let (oy, e7) = mem.alloc[f64](a, at + 1usize)
    let (oi, e8) = mem.alloc[f64](a, at + 1usize)
    if e6 != ok { os.exit(5) }
    if e7 != ok { os.exit(5) }
    if e8 != ok { os.exit(5) }
    var w = 0usize
    p = 0usize
    while p < np {
        let s = order[p]
        var t = 0usize
        while t < len[s] {
            ox[w] = rx[start[s] + t]
            oy[w] = ry[start[s] + t]
            oi[w] = f64(p + 1usize)
            w += 1usize
            t += 1usize
        }
        p += 1usize
    }
    ret Canon { x: ox[0usize..w], y: oy[0usize..w], id: oi[0usize..w] }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    var name = c.name
    var wants_len = false
    if name.len > 4usize && name[0usize] == 108u8 && name[1usize] == 101u8 && name[2usize] == 110u8 && name[3usize] == 58u8 {
        name = name[4usize..name.len]
        wants_len = true
    } else if name.len > 2usize && name[1usize] == 58u8 {
        name = name[2usize..name.len]
    }
    let x = c.args
    let nr = usize(x[3usize])
    let nc = usize(x[4usize])
    let xs = x[5usize..5usize + nc]
    let ys = x[5usize + nc..5usize + nc + nr]
    let z = x[5usize + nc + nr..5usize + nc + nr + nr * nc]
    var res: iso.Contours = zero
    var e = ok
    if x[0usize] == 0.0f64 {
        let (r, re) = iso.isobands(a, xs, ys, z, x[1usize], x[2usize])
        res = r
        e = re
    } else {
        let (r, re) = iso.isolines(a, xs, ys, z, x[1usize])
        res = r
        e = re
    }
    if e != ok { os.exit(7) }
    let cn = canon(a, res, x[0usize] == 0.0f64)
    var v = cn.x
    if str.eq(name, "isoy") { v = cn.y }
    if str.eq(name, "isoid") { v = cn.id }
    if wants_len { ret f64(v.len) }
    let i = usize(x[x.len - 1usize])
    if i < v.len { ret v[i] }
    ret 0.0f64 / 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/isoband.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 10usize {
                let _ = io.print(c.name)
                let _ = io.print(" kind ")
                if c.args[0usize] == 0.0f64 { let _ = io.print("band") } else { let _ = io.print("line") }
                let _ = io.print(" ")
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
