// Isolines and isobands of a regular grid, as R's isoband computes them: marching squares over
// each cell, with the elementary polygons (or line segments) merged into rings (or lines) on a hash
// grid of grid points, so a contour that crosses many cells comes out as one path. `isobands`
// answers the polygons of the region lo <= z < hi, `isolines` the lines at z = level. A cell with a
// non-finite corner draws nothing. The 81 cell cases of the band are a table (isoband_table.e,
// generated from isoband's C++); saddles read the mean of the four corners.
//
// z is column-major: z[r + c * nrow], x indexes the columns and y the rows. A result is paths of
// points with an id per path; a ring is not closed by a repeated point, a line from a closed
// contour is. The start point and the order of the paths follow the hash grid, as isoband's do
// not follow a rule either; compare after normalising both.
//
// Not here: isoband's `iso_to_path`, `iso_to_polygon` and sfg conversion, `clip_lines` and the
// label placer.

use e.gfx.isoband_table as table
use e.math
use e.mem
use e.str

error MergeFailed
error TooLarge
error Shape

const GRID: i64 = 0i64
const HLO: i64 = 1i64
const HHI: i64 = 2i64
const VLO: i64 = 3i64
const VHI: i64 = 4i64

type Entry = struct { prev: i64, next: i64, prev2: i64, next2: i64, alt: bool, col: bool, col2: bool }

type Band = struct { nrow: i64, ncol: i64, x: []const f64, y: []const f64, z: []const f64, vlo: f64, vhi: f64, keys: []i64, state: []u8, ents: []Entry, mask: usize, live: usize, failed: bool, tmp: []i64, conn: []Entry, del: []bool, n: usize }

type Contours = struct { x: []f64, y: []f64, id: []i64 }

fn fresh() -> Entry {
    ret Entry { prev: -1i64, next: -1i64, prev2: -1i64, next2: -1i64, alt: false, col: false, col2: false }
}

fn make_band(a: *mem.Arena, x: []const f64, y: []const f64, z: []const f64, vlo: f64, vhi: f64) -> (Band, err) {
    var empty: Band = zero
    if z.len != x.len * y.len { ret (empty, Shape) }
    var cap = 64usize
    while cap < 8usize * z.len + 64usize { cap = cap * 2usize }
    let (keys, ke) = mem.alloc[i64](a, cap)
    let (state, se) = mem.alloc[u8](a, cap)
    let (ents, ee) = mem.alloc[Entry](a, cap)
    let (tmp, te) = mem.alloc[i64](a, 8usize)
    let (conn, ce) = mem.alloc[Entry](a, 8usize)
    let (del, de) = mem.alloc[bool](a, 8usize)
    if ke != ok { ret (empty, ke) }
    if se != ok { ret (empty, se) }
    if ee != ok { ret (empty, ee) }
    if te != ok { ret (empty, te) }
    if ce != ok { ret (empty, ce) }
    if de != ok { ret (empty, de) }
    var i = 0usize
    while i < cap {
        state[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        conn[i] = fresh()
        del[i] = false
        i += 1usize
    }
    ret (Band { nrow: i64(y.len), ncol: i64(x.len), x: x, y: y, z: z, vlo: vlo, vhi: vhi, keys: keys, state: state, ents: ents, mask: cap - 1usize, live: 0usize, failed: false, tmp: tmp, conn: conn, del: del, n: 0usize }, ok)
}

fn reset_grid(s: *Band) {
    var i = 0usize
    while i < s.state.len {
        s.state[i] = 0u8
        i += 1usize
    }
    s.live = 0usize
    i = 0usize
    while i < 8usize {
        s.conn[i] = fresh()
        i += 1usize
    }
}

fn key_of(s: *Band, r: i64, c: i64, t: i64) -> i64 { ret (r * s.ncol + c) * 5i64 + t }

fn slot_hash(s: *Band, key: i64) -> usize {
    let h = u64(key) *% 11400714819323198485u64
    ret usize(h >> 24u64) & s.mask
}

// The slot of a live key.
fn find(s: *Band, key: i64) -> (usize, bool) {
    var i = slot_hash(s, key)
    var n = 0usize
    while n <= s.mask {
        if s.state[i] == 0u8 { ret (0usize, false) }
        if s.state[i] == 1u8 && s.keys[i] == key { ret (i, true) }
        i = (i + 1usize) & s.mask
        n += 1usize
    }
    ret (0usize, false)
}

// The slot of a key, inserted with a fresh entry when it is not there (polygon_grid[key]).
fn slot_for(s: *Band, key: i64) -> usize {
    var i = slot_hash(s, key)
    var first_dead = s.mask + 1usize
    var n = 0usize
    while n <= s.mask {
        if s.state[i] == 1u8 && s.keys[i] == key { ret i }
        if s.state[i] == 2u8 && first_dead > s.mask { first_dead = i }
        if s.state[i] == 0u8 { break }
        i = (i + 1usize) & s.mask
        n += 1usize
    }
    var at = i
    if first_dead <= s.mask { at = first_dead }
    s.keys[at] = key
    s.state[at] = 1u8
    s.ents[at] = fresh()
    s.live += 1usize
    if s.live * 2usize > s.mask { s.failed = true }
    ret at
}

fn erase(s: *Band, key: i64) {
    let (i, found) = find(s, key)
    if found {
        s.state[i] = 2u8
        s.live -= 1usize
    }
}

fn zat(s: *Band, r: i64, c: i64) -> f64 { ret s.z[usize(r + c * s.nrow)] }

fn central_value(s: *Band, r: i64, c: i64) -> f64 {
    ret (zat(s, r, c) + zat(s, r, c + 1i64) + zat(s, r + 1i64, c) + zat(s, r + 1i64, c + 1i64)) / 4.0f64
}

fn finite(v: f64) -> bool { ret v == v && v - v == 0.0f64 }

fn poly_start(s: *Band, r: i64, c: i64, t: i64) {
    s.tmp[0usize] = key_of(s, r, c, t)
    s.n = 1usize
}

fn poly_add(s: *Band, r: i64, c: i64, t: i64) {
    s.tmp[s.n] = key_of(s, r, c, t)
    s.n += 1usize
}

// poly_merge: the current elementary polygon joins the polygons already on the grid.
fn poly_merge(s: *Band) {
    let n = s.n
    var i = 0usize
    while i < 8usize {
        s.del[i] = false
        i += 1usize
    }
    i = 0usize
    while i < n {
        var cn = s.conn[i]
        cn.alt = false
        var nx = i + 1usize
        if nx >= n { nx = 0usize }
        var pv = n - 1usize
        if i >= 1usize { pv = i - 1usize }
        cn.next = s.tmp[nx]
        cn.prev = s.tmp[pv]
        let p = s.tmp[i]
        let (slot, found) = find(s, p)
        if found {
            let old = s.ents[slot]
            if !old.alt {
                var score = 0i64
                if cn.next == old.prev { score += 2i64 }
                if cn.prev == old.next { score += 1i64 }
                if score == 3i64 {
                    s.del[i] = true
                } else if score == 2i64 {
                    cn.next = old.next
                } else if score == 1i64 {
                    cn.prev = old.prev
                } else {
                    cn.prev2 = old.prev
                    cn.next2 = old.next
                    cn.alt = true
                }
            } else {
                var score = 0i64
                if cn.next == old.prev2 { score += 8i64 }
                if cn.prev == old.next2 { score += 4i64 }
                if cn.next == old.prev { score += 2i64 }
                if cn.prev == old.next { score += 1i64 }
                if score == 9i64 {
                    cn.next = old.next2
                    cn.prev = old.prev
                } else if score == 6i64 {
                    cn.next = old.next
                    cn.prev = old.prev2
                } else if score == 8i64 {
                    cn.next2 = old.next2
                    cn.prev2 = cn.prev
                    cn.prev = old.prev
                    cn.next = old.next
                    cn.alt = true
                } else if score == 4i64 {
                    cn.prev2 = old.prev2
                    cn.next2 = cn.next
                    cn.prev = old.prev
                    cn.next = old.next
                    cn.alt = true
                } else if score == 2i64 {
                    cn.next = old.next
                    cn.prev2 = old.prev2
                    cn.next2 = old.next2
                    cn.alt = true
                } else if score == 1i64 {
                    cn.prev = old.prev
                    cn.prev2 = old.prev2
                    cn.next2 = old.next2
                    cn.alt = true
                } else {
                    s.failed = true
                }
            }
        }
        s.conn[i] = cn
        i += 1usize
    }
    i = 0usize
    while i < n {
        if s.del[i] {
            erase(s, s.tmp[i])
        } else {
            let slot = slot_for(s, s.tmp[i])
            s.ents[slot] = s.conn[i]
        }
        i += 1usize
    }
}

fn interpolate(x0: f64, x1: f64, z0: f64, z1: f64, value: f64) -> f64 {
    let d = (value - z0) / (z1 - z0)
    ret x0 + d * (x1 - x0)
}

// The coordinates of a grid point.
fn coords(s: *Band, key: i64) -> (f64, f64) {
    let t = key % 5i64
    let rc = key / 5i64
    let r = rc / s.ncol
    let c = rc % s.ncol
    let ur = usize(r)
    let uc = usize(c)
    if t == GRID { ret (s.x[uc], s.y[ur]) }
    if t == HLO { ret (interpolate(s.x[uc], s.x[uc + 1usize], zat(s, r, c), zat(s, r, c + 1i64), s.vlo), s.y[ur]) }
    if t == HHI { ret (interpolate(s.x[uc], s.x[uc + 1usize], zat(s, r, c), zat(s, r, c + 1i64), s.vhi), s.y[ur]) }
    if t == VLO { ret (s.x[uc], interpolate(s.y[ur], s.y[ur + 1usize], zat(s, r, c), zat(s, r + 1i64, c), s.vlo)) }
    ret (s.x[uc], interpolate(s.y[ur], s.y[ur + 1usize], zat(s, r, c), zat(s, r + 1i64, c), s.vhi))
}

// --- The band table, decoded once per call.

type Table = struct { kind: []u8, vstart: []usize, vcount: []usize, pstart: []usize, plen: []usize, pts: []u8 }

fn decode_table(a: *mem.Arena) -> (Table, err) {
    var empty: Table = zero
    let text = table.band_table()
    let (kind, ke) = mem.alloc[u8](a, 81usize)
    let (vstart, vse) = mem.alloc[usize](a, 81usize * 3usize)
    let (vcount, vce) = mem.alloc[usize](a, 81usize * 3usize)
    let (pstart, pse) = mem.alloc[usize](a, 400usize)
    let (plen, ple) = mem.alloc[usize](a, 400usize)
    let (pts, pte) = mem.alloc[u8](a, text.len + 8usize)
    if ke != ok { ret (empty, ke) }
    if vse != ok { ret (empty, vse) }
    if vce != ok { ret (empty, vce) }
    if pse != ok { ret (empty, pse) }
    if ple != ok { ret (empty, ple) }
    if pte != ok { ret (empty, pte) }
    var np = 0usize
    var nt = 0usize
    var i = 0usize
    while i < text.len {
        // N:K:variants;
        var n = 0usize
        while text[i] != 58u8 {
            n = n * 10usize + usize(text[i] - 48u8)
            i += 1usize
        }
        i += 1usize
        kind[n] = text[i] - 48u8
        i += 2usize
        var v = 0usize
        vstart[n * 3usize] = np
        vcount[n * 3usize] = 0usize
        var started = false
        while text[i] != 59u8 {
            let c = text[i]
            if c == 124u8 {
                v += 1usize
                vstart[n * 3usize + v] = np
                vcount[n * 3usize + v] = 0usize
                started = false
            } else if c == 46u8 {
                started = false
            } else {
                if !started {
                    pstart[np] = nt
                    plen[np] = 0usize
                    np += 1usize
                    vcount[n * 3usize + v] += 1usize
                    started = true
                }
                pts[nt] = c - 97u8
                nt += 1usize
                plen[np - 1usize] += 1usize
            }
            i += 1usize
        }
        i += 1usize
    }
    ret (Table { kind: kind, vstart: vstart, vcount: vcount, pstart: pstart, plen: plen, pts: pts }, ok)
}

fn apply_polys(s: *Band, t: *Table, idx: usize, v: usize, r: i64, c: i64) {
    var p = 0usize
    while p < t.vcount[idx * 3usize + v] {
        let q = t.vstart[idx * 3usize + v] + p
        var k = 0usize
        while k < t.plen[q] {
            let code = i64(t.pts[t.pstart[q] + k])
            let ty = code % 5i64
            let cell = code / 5i64
            let dr = cell / 2i64
            let dc = cell % 2i64
            if k == 0usize { poly_start(s, r + dr, c + dc, ty) } else { poly_add(s, r + dr, c + dc, ty) }
            k += 1usize
        }
        poly_merge(s)
        p += 1usize
    }
}

fn calculate_band(s: *Band, t: *Table, tern: []i64) {
    reset_grid(s)
    var i = 0usize
    while i < s.z.len {
        let v = s.z[i]
        var tv = 0i64
        if v >= s.vlo && v < s.vhi { tv = 1i64 }
        if v >= s.vhi { tv = 2i64 }
        tern[i] = tv
        i += 1usize
    }
    var r = 0i64
    while r < s.nrow - 1i64 {
        var c = 0i64
        while c < s.ncol - 1i64 {
            var idx = 0i64
            if finite(zat(s, r, c)) && finite(zat(s, r, c + 1i64)) && finite(zat(s, r + 1i64, c)) && finite(zat(s, r + 1i64, c + 1i64)) {
                idx = 27i64 * tern[usize(r + c * s.nrow)] + 9i64 * tern[usize(r + (c + 1i64) * s.nrow)] + 3i64 * tern[usize(r + 1i64 + (c + 1i64) * s.nrow)] + tern[usize(r + 1i64 + c * s.nrow)]
            }
            if idx != 0i64 && idx != 80i64 {
                let u = usize(idx)
                let k = t.kind[u]
                if k == 0u8 {
                    apply_polys(s, t, u, 0usize, r, c)
                } else {
                    let vc = central_value(s, r, c)
                    if k == 1u8 {
                        if vc < s.vlo { apply_polys(s, t, u, 0usize, r, c) } else { apply_polys(s, t, u, 1usize, r, c) }
                    } else if k == 2u8 {
                        if vc >= s.vhi { apply_polys(s, t, u, 0usize, r, c) } else { apply_polys(s, t, u, 1usize, r, c) }
                    } else {
                        if vc < s.vlo {
                            apply_polys(s, t, u, 0usize, r, c)
                        } else if vc >= s.vhi {
                            apply_polys(s, t, u, 1usize, r, c)
                        } else {
                            apply_polys(s, t, u, 2usize, r, c)
                        }
                    }
                }
            }
            c += 1i64
        }
        r += 1i64
    }
}

fn contours_buffers(a: *mem.Arena, s: *Band) -> (Contours, err) {
    var empty: Contours = zero
    let cap = 2usize * s.live + 8usize
    let (xs, xe) = mem.alloc[f64](a, cap)
    let (ys, ye) = mem.alloc[f64](a, cap)
    let (ids, ie) = mem.alloc[i64](a, cap)
    if xe != ok { ret (empty, xe) }
    if ye != ok { ret (empty, ye) }
    if ie != ok { ret (empty, ie) }
    ret (Contours { x: xs, y: ys, id: ids }, ok)
}

// --- isobands

// The polygons of lo <= z < hi, one ring per id, each point once.
fn isobands(a: *mem.Arena, x: []const f64, y: []const f64, z: []const f64, lo: f64, hi: f64) -> (Contours, err) {
    var empty: Contours = zero
    let (s0, se) = make_band(a, x, y, z, lo, hi)
    if se != ok { ret (empty, se) }
    var s = s0
    let (t0, te) = decode_table(a)
    if te != ok { ret (empty, te) }
    var t = t0
    let (tern, ne) = mem.alloc[i64](a, z.len + 1usize)
    if ne != ok { ret (empty, ne) }
    calculate_band(&s, &t, tern)
    if s.failed { ret (empty, MergeFailed) }
    let (out, oe) = contours_buffers(a, &s)
    if oe != ok { ret (empty, oe) }
    var n = 0usize
    var cur_id = 0i64
    var k = 0usize
    while k < s.state.len {
        if s.state[k] == 1u8 {
            let e0 = s.ents[k]
            if !((e0.col && !e0.alt) || (e0.col && e0.col2 && e0.alt)) {
                cur_id += 1i64
                let start = s.keys[k]
                var cur = start
                var prev = e0.prev
                if e0.alt && !e0.col2 { prev = e0.prev2 }
                var go = true
                var guard = 0usize
                while go {
                    let (px, py) = coords(&s, cur)
                    out.x[n] = px
                    out.y[n] = py
                    out.id[n] = cur_id
                    n += 1usize
                    let (slot, found) = find(&s, cur)
                    if !found { ret (empty, MergeFailed) }
                    var en = s.ents[slot]
                    var newcur = en.next
                    if en.alt && en.prev2 == prev {
                        en.col2 = true
                        newcur = en.next2
                    } else {
                        en.col = true
                    }
                    s.ents[slot] = en
                    prev = cur
                    cur = newcur
                    guard += 1usize
                    if guard > 4usize * s.state.len { ret (empty, MergeFailed) }
                    go = cur != start
                    if n + 2usize > out.x.len { ret (empty, TooLarge) }
                }
            }
        }
        k += 1usize
    }
    ret (Contours { x: out.x[0usize..n], y: out.y[0usize..n], id: out.id[0usize..n] }, ok)
}

// --- isolines

fn line_start(s: *Band, r: i64, c: i64, t: i64) { poly_start(s, r, c, t) }

fn line_add(s: *Band, r: i64, c: i64, t: i64) { poly_add(s, r, c, t) }

fn line_merge(s: *Band) {
    let k0 = s.tmp[0usize]
    let k1 = s.tmp[1usize]
    let (i0, f0) = find(s, k0)
    let (i1, f1) = find(s, k1)
    var score = 0i64
    if f1 { score += 2i64 }
    if f0 { score += 1i64 }
    if score == 0i64 {
        let a0 = slot_for(s, k0)
        var e0 = s.ents[a0]
        e0.next = k1
        s.ents[a0] = e0
        let a1 = slot_for(s, k1)
        var e1 = s.ents[a1]
        e1.prev = k0
        s.ents[a1] = e1
    } else if score == 1i64 {
        var e0 = s.ents[i0]
        if e0.next == -1i64 {
            e0.next = k1
            s.ents[i0] = e0
            let a1 = slot_for(s, k1)
            var e1 = s.ents[a1]
            e1.prev = k0
            s.ents[a1] = e1
        } else if e0.prev == -1i64 {
            e0.prev = k1
            s.ents[i0] = e0
            let a1 = slot_for(s, k1)
            var e1 = s.ents[a1]
            e1.next = k0
            s.ents[a1] = e1
        } else {
            s.failed = true
        }
    } else if score == 2i64 {
        var e1 = s.ents[i1]
        if e1.next == -1i64 {
            e1.next = k0
            s.ents[i1] = e1
            let a0 = slot_for(s, k0)
            var e0 = s.ents[a0]
            e0.prev = k1
            s.ents[a0] = e0
        } else if e1.prev == -1i64 {
            e1.prev = k0
            s.ents[i1] = e1
            let a0 = slot_for(s, k0)
            var e0 = s.ents[a0]
            e0.next = k1
            s.ents[a0] = e0
        } else {
            s.failed = true
        }
    } else {
        var e0 = s.ents[i0]
        var e1 = s.ents[i1]
        var score2 = 0i64
        if e0.next == -1i64 { score2 += 8i64 }
        if e0.prev == -1i64 { score2 += 4i64 }
        if e1.next == -1i64 { score2 += 2i64 }
        if e1.prev == -1i64 { score2 += 1i64 }
        if score2 == 9i64 {
            e0.next = k1
            e1.prev = k0
            s.ents[i0] = e0
            s.ents[i1] = e1
        } else if score2 == 6i64 {
            e0.prev = k1
            e1.next = k0
            s.ents[i0] = e0
            s.ents[i1] = e1
        } else if score2 == 10i64 {
            e0.next = k1
            e1.next = k0
            s.ents[i0] = e0
            s.ents[i1] = e1
            var cur = k1
            var guard = 0usize
            var go = true
            while go {
                let (sl, fnd) = find(s, cur)
                if !fnd {
                    s.failed = true
                    ret
                }
                var en = s.ents[sl]
                let tmp = en.prev
                en.prev = en.next
                en.next = tmp
                s.ents[sl] = en
                cur = tmp
                guard += 1usize
                go = cur != -1i64
                if guard > s.state.len {
                    s.failed = true
                    ret
                }
            }
        } else if score2 == 5i64 {
            e0.prev = k1
            e1.prev = k0
            s.ents[i0] = e0
            s.ents[i1] = e1
            var cur = k0
            var guard = 0usize
            var go = true
            while go {
                let (sl, fnd) = find(s, cur)
                if !fnd {
                    s.failed = true
                    ret
                }
                var en = s.ents[sl]
                let tmp = en.next
                en.next = en.prev
                en.prev = tmp
                s.ents[sl] = en
                cur = tmp
                guard += 1usize
                go = cur != -1i64
                if guard > s.state.len {
                    s.failed = true
                    ret
                }
            }
        } else {
            s.failed = true
        }
    }
}

fn seg(s: *Band, r0: i64, c0: i64, t0: i64, r1: i64, c1: i64, t1: i64) {
    line_start(s, r0, c0, t0)
    line_add(s, r1, c1, t1)
    line_merge(s)
}

fn calculate_line(s: *Band) {
    reset_grid(s)
    var r = 0i64
    while r < s.nrow - 1i64 {
        var c = 0i64
        while c < s.ncol - 1i64 {
            var idx = 0i64
            if finite(zat(s, r, c)) && finite(zat(s, r, c + 1i64)) && finite(zat(s, r + 1i64, c)) && finite(zat(s, r + 1i64, c + 1i64)) {
                var b00 = 0i64
                var b01 = 0i64
                var b11 = 0i64
                var b10 = 0i64
                if zat(s, r, c) >= s.vlo { b00 = 1i64 }
                if zat(s, r, c + 1i64) >= s.vlo { b01 = 1i64 }
                if zat(s, r + 1i64, c + 1i64) >= s.vlo { b11 = 1i64 }
                if zat(s, r + 1i64, c) >= s.vlo { b10 = 1i64 }
                idx = 8i64 * b00 + 4i64 * b01 + 2i64 * b11 + b10
            }
            if idx == 5i64 && central_value(s, r, c) < s.vlo {
                idx = 10i64
            } else if idx == 10i64 && central_value(s, r, c) < s.vlo {
                idx = 5i64
            }
            if idx == 1i64 || idx == 14i64 {
                seg(s, r, c, VLO, r + 1i64, c, HLO)
            } else if idx == 2i64 || idx == 13i64 {
                seg(s, r, c + 1i64, VLO, r + 1i64, c, HLO)
            } else if idx == 3i64 || idx == 12i64 {
                seg(s, r, c, VLO, r, c + 1i64, VLO)
            } else if idx == 4i64 || idx == 11i64 {
                seg(s, r, c, HLO, r, c + 1i64, VLO)
            } else if idx == 5i64 {
                seg(s, r, c + 1i64, VLO, r + 1i64, c, HLO)
                seg(s, r, c, HLO, r, c, VLO)
            } else if idx == 6i64 || idx == 9i64 {
                seg(s, r, c, HLO, r + 1i64, c, HLO)
            } else if idx == 7i64 || idx == 8i64 {
                seg(s, r, c, HLO, r, c, VLO)
            } else if idx == 10i64 {
                seg(s, r, c, VLO, r + 1i64, c, HLO)
                seg(s, r, c, HLO, r, c + 1i64, VLO)
            }
            c += 1i64
        }
        r += 1i64
    }
}

// The lines at z = level. A closed contour repeats its first point at the end.
fn isolines(a: *mem.Arena, x: []const f64, y: []const f64, z: []const f64, level: f64) -> (Contours, err) {
    var empty: Contours = zero
    let (s0, se) = make_band(a, x, y, z, level, 0.0f64)
    if se != ok { ret (empty, se) }
    var s = s0
    calculate_line(&s)
    if s.failed { ret (empty, MergeFailed) }
    let (out, oe) = contours_buffers(a, &s)
    if oe != ok { ret (empty, oe) }
    var n = 0usize
    var cur_id = 0i64
    var k = 0usize
    while k < s.state.len {
        if s.state[k] == 1u8 && !s.ents[k].col {
            cur_id += 1i64
            let first = s.keys[k]
            var cur = first
            var guard = 0usize
            let (f0, found0) = find(&s, cur)
            if found0 && s.ents[f0].prev != -1i64 {
                var go = true
                while go {
                    let (sl, fnd) = find(&s, cur)
                    if !fnd { ret (empty, MergeFailed) }
                    cur = s.ents[sl].prev
                    guard += 1usize
                    if guard > s.state.len { ret (empty, MergeFailed) }
                    let (sl2, fnd2) = find(&s, cur)
                    go = !(cur == first || (fnd2 && s.ents[sl2].prev == -1i64))
                }
            }
            let start = cur
            var go2 = true
            guard = 0usize
            while go2 {
                let (px, py) = coords(&s, cur)
                out.x[n] = px
                out.y[n] = py
                out.id[n] = cur_id
                n += 1usize
                let (sl, fnd) = find(&s, cur)
                if !fnd { ret (empty, MergeFailed) }
                var en = s.ents[sl]
                en.col = true
                s.ents[sl] = en
                cur = en.next
                guard += 1usize
                if guard > s.state.len { ret (empty, MergeFailed) }
                go2 = !(cur == start || cur == -1i64)
                if n + 2usize > out.x.len { ret (empty, TooLarge) }
            }
            if cur == start {
                let (px, py) = coords(&s, cur)
                out.x[n] = px
                out.y[n] = py
                out.id[n] = cur_id
                n += 1usize
            }
        }
        k += 1usize
    }
    ret (Contours { x: out.x[0usize..n], y: out.y[0usize..n], id: out.id[0usize..n] }, ok)
}
