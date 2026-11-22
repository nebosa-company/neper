// interp::tri.mesh's triangulation: the s-hull sweep with Cline-Renka flips of interp/src/s_hull_pro.cpp, in the same single precision arithmetic, so the triangle, neighbour and
// vertex order equal R's (shullDeltri.cpp then makes the counter-clockwise lists).
// shull: out holds 6 i64 per triangle (i1, i2, i3, j1, j2, j3: zero-based nodes, neighbours across the edge opposite i1, i2, i3, -1 for none); returns the triangle count or a
// negative s-hull error code (the -13 retry with jitter that R takes when too many flips are needed is not made).
// Every single-precision operation is computed in f64 and rounded once (r32), which is the exact single-precision result for + - * /.

use e.mem

fn r32(x: f64) -> f64 { ret f64(f32(x)) }

fn af(a: *mem.Arena, n: usize) -> []f64 {
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret s }
    var i = 0usize
    while i < n {
        s[i] = 0.0f64
        i += 1usize
    }
    ret s
}

fn au(a: *mem.Arena, n: usize) -> []usize {
    let (s, e) = mem.alloc[usize](a, n)
    if e != ok { ret s }
    var i = 0usize
    while i < n {
        s[i] = 0usize
        i += 1usize
    }
    ret s
}

fn ai(a: *mem.Arena, n: usize) -> []i64 {
    let (s, e) = mem.alloc[i64](a, n)
    if e != ok { ret s }
    var i = 0usize
    while i < n {
        s[i] = 0i64
        i += 1usize
    }
    ret s
}

// circle_cent2: out = [centre r, centre c, squared radius] (squared radius -1 when degenerate)
fn cent2(r1: f64, c1: f64, r2: f64, c2: f64, r3: f64, c3: f64, out: []f64) {
    let a1 = r32(r1 + r2) / 2.0f64
    let a2 = r32(c1 + c2) / 2.0f64
    let b1 = r32(r3 + r2) / 2.0f64
    let b2 = r32(c3 + c2) / 2.0f64
    let e2 = r32(r1 - r2)
    let e1 = r32(c2 - c1)
    let q2 = r32(r3 - r2)
    let q1 = r32(c2 - c3)
    out[0usize] = 0.0f64
    out[1usize] = 0.0f64
    out[2usize] = -1.0f64
    if r32(r32(e1 * (0.0f64 - q2)) + r32(e2 * q1)) == 0.0f64 { ret }
    let num = r32(r32((0.0f64 - e2) * r32(b1 - a1)) + r32(e1 * r32(b2 - a2)))
    let den = r32(r32(e2 * q1) - r32(e1 * q2))
    let beta = r32(num / den)
    let cr = r32(b1 + r32(q1 * beta))
    let cc = r32(b2 + r32(q2 * beta))
    out[0usize] = cr
    out[1usize] = cc
    let d1 = r32(r1 - cr)
    let d2 = r32(c1 - cc)
    out[2usize] = r32(r32(d1 * d1) + r32(d2 * d2))
}

// Cline_Renka_test: true when the shared edge must be flipped (the test answers -1)
fn cline(ax: f64, ay: f64, bx: f64, by: f64, cx: f64, cy: f64, dx: f64, dy: f64) -> bool {
    let v1x = r32(bx - ax)
    let v1y = r32(by - ay)
    let v2x = r32(cx - ax)
    let v2y = r32(cy - ay)
    let v3x = r32(bx - dx)
    let v3y = r32(by - dy)
    let v4x = r32(cx - dx)
    let v4y = r32(cy - dy)
    let cos_a = r32(r32(v1x * v2x) + r32(v1y * v2y))
    let cos_d = r32(r32(v3x * v4x) + r32(v3y * v4y))
    if cos_a < 0.0f64 && cos_d < 0.0f64 { ret true }
    if cos_a > 0.0f64 && cos_d > 0.0f64 { ret false }
    var sin_a = r32(r32(v1x * v2y) - r32(v1y * v2x))
    if sin_a < 0.0f64 { sin_a = 0.0f64 - sin_a }
    var sin_d = r32(r32(v3x * v4y) - r32(v3y * v4x))
    if sin_d < 0.0f64 { sin_d = 0.0f64 - sin_d }
    ret r32(r32(cos_a * sin_d) + r32(sin_a * cos_d)) < 0.0f64
}

// triads: 6 i64 each, a, b, c, ab, bc, ac. One triangle's three neighbour tests of T_flip_pro (mode 0), T_flip_pro_idx (mode 1) and T_flip_edge (mode 2).
fn flip_one(t: usize, mode: usize, pr: []const f64, pc: []const f64, slump: []const i64, td: []i64, ids: []i64, cnt: []usize) -> i64 {
    var flipped = false
    var blk = 0usize
    let ti = i64(t)
    let o = 6usize * t
    while blk < 3usize && !flipped {
        let ta = td[o]
        let tb = td[o + 1usize]
        let tc = td[o + 2usize]
        let tab = td[o + 3usize]
        let tbc = td[o + 4usize]
        let tac = td[o + 5usize]
        var t2i = tbc
        var key = tb
        var go = false
        if blk == 0usize {
            t2i = tbc
            key = tb
            go = tbc >= 0i64
            if mode == 2usize { go = go && (tac < 0i64 || tab < 0i64) }
        }
        if blk == 1usize {
            t2i = tab
            key = ta
            go = tab >= 0i64
            if mode == 2usize { go = go && (tac < 0i64 || tbc < 0i64) }
        }
        if blk == 2usize {
            t2i = tac
            key = ta
            go = tac >= 0i64
            if mode == 2usize { go = go && (tbc < 0i64 || tab < 0i64) }
        }
        if go {
            let pa = usize(slump[usize(ta)])
            let pb = usize(slump[usize(tb)])
            let pcc = usize(slump[usize(tc)])
            let p2 = 6usize * usize(t2i)
            let u_a = td[p2]
            let u_b = td[p2 + 1usize]
            let u_c = td[p2 + 2usize]
            let u_ab = td[p2 + 3usize]
            let u_bc = td[p2 + 4usize]
            let u_ac = td[p2 + 5usize]
            var dn = 0i64
            var l3 = 0i64
            var l4 = 0i64
            if u_ab == ti {
                dn = u_c
                if key == u_a {
                    l3 = u_ac
                    l4 = u_bc
                } else {
                    l3 = u_bc
                    l4 = u_ac
                }
            } else if u_ac == ti {
                dn = u_b
                if key == u_a {
                    l3 = u_ab
                    l4 = u_bc
                } else {
                    l3 = u_bc
                    l4 = u_ab
                }
            } else if u_bc == ti {
                dn = u_a
                if key == u_b {
                    l3 = u_ab
                    l4 = u_ac
                } else {
                    l3 = u_ac
                    l4 = u_ab
                }
            } else {
                if mode == 1usize { ret -6i64 }
                ret -5i64
            }
            let pd = usize(slump[usize(dn)])
            var xx = false
            var l1 = tab
            var l2 = tac
            var na = ta
            var nb = tb
            var ma = ta
            var mb = tc
            if blk == 0usize {
                xx = cline(pr[pa], pc[pa], pr[pb], pc[pb], pr[pcc], pc[pcc], pr[pd], pc[pd])
            }
            if blk == 1usize {
                xx = cline(pr[pcc], pc[pcc], pr[pb], pc[pb], pr[pa], pc[pa], pr[pd], pc[pd])
                l1 = tac
                l2 = tbc
                na = tc
                nb = ta
                ma = tc
                mb = tb
            }
            if blk == 2usize {
                if mode == 1usize {
                    xx = cline(pr[pb], pc[pb], pr[pcc], pc[pcc], pr[pa], pc[pa], pr[pd], pc[pd])
                } else {
                    xx = cline(pr[pb], pc[pb], pr[pa], pc[pa], pr[pcc], pc[pcc], pr[pd], pc[pd])
                }
                l1 = tab
                l2 = tbc
                na = tb
                nb = ta
                ma = tb
                mb = tc
            }
            if xx && (mode == 2usize || (l1 != l3 && l2 != l4)) {
                if cnt[0usize] + 2usize > ids.len { ret -13i64 }
                ids[cnt[0usize]] = ti
                ids[cnt[0usize] + 1usize] = t2i
                cnt[0usize] += 2usize
                td[o] = na
                td[o + 1usize] = nb
                td[o + 2usize] = dn
                td[o + 3usize] = l1
                td[o + 4usize] = l3
                td[o + 5usize] = t2i
                td[p2] = ma
                td[p2 + 1usize] = mb
                td[p2 + 2usize] = dn
                td[p2 + 3usize] = l2
                td[p2 + 4usize] = l4
                td[p2 + 5usize] = ti
                flipped = true
                if l3 >= 0i64 {
                    let q = 6usize * usize(l3)
                    if td[q + 3usize] == t2i {
                        td[q + 3usize] = ti
                    } else if td[q + 4usize] == t2i {
                        td[q + 4usize] = ti
                    } else if td[q + 5usize] == t2i {
                        td[q + 5usize] = ti
                    }
                }
                if l2 >= 0i64 {
                    let q = 6usize * usize(l2)
                    if td[q + 3usize] == ti {
                        td[q + 3usize] = t2i
                    } else if td[q + 4usize] == ti {
                        td[q + 4usize] = t2i
                    } else if td[q + 5usize] == ti {
                        td[q + 5usize] = t2i
                    }
                }
            }
        }
        blk += 1usize
    }
    ret 1i64
}

// std::sort of Shx on (ro, r, c) over [lo, hi); the key is total for distinct points, so an insertion sort gives the same order
fn sort_pts(pid: []i64, pr: []f64, pc: []f64, pro: []f64, lo: usize, hi: usize) {
    var i = lo + 1usize
    while i < hi {
        let vid = pid[i]
        let vr = pr[i]
        let vc = pc[i]
        let vo = pro[i]
        var j = i
        var go = true
        while j > lo && go {
            let k = j - 1usize
            var less = false
            if vo < pro[k] {
                less = true
            } else if vo == pro[k] {
                if vr < pr[k] {
                    less = true
                } else if vr == pr[k] {
                    less = vc < pc[k]
                }
            }
            if less {
                pid[j] = pid[k]
                pr[j] = pr[k]
                pc[j] = pc[k]
                pro[j] = pro[k]
                j = k
            } else {
                go = false
            }
        }
        pid[j] = vid
        pr[j] = vr
        pc[j] = vc
        pro[j] = vo
        i += 1usize
    }
}

// hull records: 6 f64 each, id, r, c, tr, tc, trid
fn h_ins(hl: []f64, hn: usize, at: usize, id: f64, r: f64, c: f64, tr: f64, tc: f64, trid: f64) -> usize {
    var i = hn
    while i > at {
        var f = 0usize
        while f < 6usize {
            hl[6usize * i + f] = hl[6usize * (i - 1usize) + f]
            f += 1usize
        }
        i -= 1usize
    }
    hl[6usize * at] = id
    hl[6usize * at + 1usize] = r
    hl[6usize * at + 2usize] = c
    hl[6usize * at + 3usize] = tr
    hl[6usize * at + 4usize] = tc
    hl[6usize * at + 5usize] = trid
    ret hn + 1usize
}

// erase the records [from, to)
fn h_del(hl: []f64, hn: usize, from: usize, to: usize) -> usize {
    let w = to - from
    var i = from
    while i + w < hn {
        var f = 0usize
        while f < 6usize {
            hl[6usize * i + f] = hl[6usize * (i + w) + f]
            f += 1usize
        }
        i += 1usize
    }
    ret hn - w
}

fn vis(dc: f64, tr: f64, dr: f64, tc: f64) -> f64 { ret r32(r32((0.0f64 - dc) * tr) + r32(dr * tc)) }

fn ins_front(v: []i64, n: usize, x: i64) {
    var i = n
    while i > 0usize {
        v[i] = v[i - 1usize]
        i -= 1usize
    }
    v[0usize] = x
}

// the back-index of s_hull_pro: triangle q (its edge b-c) now neighbours triangle nt
fn back_index(td: []i64, q: i64, b: i64, c: i64, nt: i64) {
    let o = 6usize * usize(q)
    let xa = td[o]
    let xb = td[o + 1usize]
    let xc = td[o + 2usize]
    if (b == xa && c == xb) || (b == xb && c == xa) {
        td[o + 3usize] = nt
    } else if (b == xa && c == xc) || (b == xc && c == xa) {
        td[o + 5usize] = nt
    } else if (b == xb && c == xc) || (b == xc && c == xb) {
        td[o + 4usize] = nt
    }
}

fn shull(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, out: []i64) -> i64 {
    if n < 3usize { ret -1i64 }
    let pid = ai(a, n + 4usize)
    let pr = af(a, n + 4usize)
    let pc = af(a, n + 4usize)
    let pro = af(a, n + 4usize)
    let o3 = af(a, 4usize)
    var i = 0usize
    while i < n {
        pid[i] = i64(i)
        pr[i] = r32(x[i])
        pc[i] = r32(y[i])
        i += 1usize
    }
    let r0 = pr[0usize]
    let c0 = pc[0usize]
    i = 0usize
    while i < n {
        let dr = r32(pr[i] - r0)
        let dc = r32(pc[i] - c0)
        pro[i] = r32(r32(dr * dr) + r32(dc * dc))
        i += 1usize
    }
    sort_pts(pid, pr, pc, pro, 0usize, n)
    let r1 = pr[0usize]
    let c1 = pc[0usize]
    let r2 = pr[1usize]
    let c2 = pc[1usize]
    var mid = 0usize
    var found = false
    var romin2 = r32(9.0e20f64)
    var sr = 0.0f64
    var sc = 0.0f64
    var k = 2usize
    while k < n {
        cent2(r1, c1, r2, c2, pr[k], pc[k], o3)
        let ro2 = o3[2usize]
        if ro2 < romin2 && ro2 > 0.0f64 {
            mid = k
            found = true
            romin2 = ro2
            sr = o3[0usize]
            sc = o3[1usize]
        } else if r32(romin2 * 4.0f64) < pro[k] {
            k = n
        }
        k += 1usize
    }
    if !found { ret -2i64 }
    let id0 = pid[0usize]
    let id1 = pid[1usize]
    let id2 = pid[mid]
    let p0r = pr[0usize]
    let p0c = pc[0usize]
    let p1r = pr[1usize]
    let p1c = pc[1usize]
    let p2r = pr[mid]
    let p2c = pc[mid]
    // the remaining points, in order, by distance from the seed centre
    let m = n - 3usize
    let rid = ai(a, m + 1usize)
    let rr = af(a, m + 1usize)
    let rc = af(a, m + 1usize)
    let rro = af(a, m + 1usize)
    var w = 0usize
    i = 2usize
    while i < n {
        if i != mid {
            rid[w] = pid[i]
            rr[w] = pr[i]
            rc[w] = pc[i]
            w += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m {
        let dr = r32(rr[i] - sr)
        let dc = r32(rc[i] - sc)
        rro[i] = r32(r32(dr * dr) + r32(dc * dc))
        i += 1usize
    }
    sort_pts(rid, rr, rc, rro, 0usize, m)
    pid[0usize] = id0
    pr[0usize] = p0r
    pc[0usize] = p0c
    pid[1usize] = id1
    pr[1usize] = p1r
    pc[1usize] = p1c
    pid[2usize] = id2
    pr[2usize] = p2r
    pc[2usize] = p2c
    i = 0usize
    while i < m {
        pid[3usize + i] = rid[i]
        pr[3usize + i] = rr[i]
        pc[3usize + i] = rc[i]
        i += 1usize
    }
    let slump = ai(a, n + 4usize)
    i = 0usize
    while i < n {
        slump[usize(pid[i])] = i64(i)
        i += 1usize
    }
    let ccr = r32(r32(r32(p0r + p1r) + p2r) / 3.0f64)
    let ccc = r32(r32(r32(p0c + p1c) + p2c) / 3.0f64)
    let dr0 = r32(p0r - ccr)
    let dc0 = r32(p0c - ccc)
    let tr01 = r32(p1r - p0r)
    let tc01 = r32(p1c - p0c)
    let df0 = r32(r32((0.0f64 - tr01) * dc0) + r32(tc01 * dr0))
    let hl = af(a, 6usize * (n + 8usize))
    var hn = 0usize
    let td = ai(a, 6usize * (2usize * n + 8usize))
    var nt = 0usize
    if df0 < 0.0f64 {
        hn = h_ins(hl, hn, 0usize, f64(id0), p0r, p0c, r32(p1r - p0r), r32(p1c - p0c), 0.0f64)
        hn = h_ins(hl, hn, 1usize, f64(id1), p1r, p1c, r32(p2r - p1r), r32(p2c - p1c), 0.0f64)
        hn = h_ins(hl, hn, 2usize, f64(id2), p2r, p2c, r32(p0r - p2r), r32(p0c - p2c), 0.0f64)
        td[0usize] = id0
        td[1usize] = id1
        td[2usize] = id2
    } else {
        hn = h_ins(hl, hn, 0usize, f64(id0), p0r, p0c, r32(p2r - p0r), r32(p2c - p0c), 0.0f64)
        hn = h_ins(hl, hn, 1usize, f64(id2), p2r, p2c, r32(p1r - p2r), r32(p1c - p2c), 0.0f64)
        hn = h_ins(hl, hn, 2usize, f64(id1), p1r, p1c, r32(p0r - p1r), r32(p0c - p1c), 0.0f64)
        td[0usize] = id0
        td[1usize] = id2
        td[2usize] = id1
    }
    td[3usize] = -1i64
    td[4usize] = -1i64
    td[5usize] = -1i64
    nt = 1usize
    let pidx = ai(a, n + 8usize)
    let tidx = ai(a, n + 8usize)
    k = 3usize
    while k < n {
        let rx = pr[k]
        let cx = pc[k]
        let xid = pid[k]
        var xtr = 0.0f64
        var xtc = 0.0f64
        var numh = i64(hn)
        if numh == 0i64 { ret -15i64 }
        var dr = r32(rx - hl[1usize])
        var dc = r32(cx - hl[2usize])
        var pn = 0usize
        var tn = 0usize
        var hidx = 0usize
        var df = vis(dc, hl[3usize], dr, hl[4usize])
        if df < 0.0f64 {
            hidx = 0usize
            let lh = 6usize * usize(numh - 1i64)
            df = vis(dc, hl[lh + 3usize], dr, hl[lh + 4usize])
            if df < 0.0f64 {
                pidx[pn] = i64(hl[lh])
                pn += 1usize
                tidx[tn] = i64(hl[lh + 5usize])
                tn += 1usize
                var h = 0i64
                var stop = false
                while h < numh - 1i64 && !stop {
                    let hb = 6usize * usize(h)
                    dr = r32(rx - hl[hb + 1usize])
                    dc = r32(cx - hl[hb + 2usize])
                    df = vis(dc, hl[hb + 3usize], dr, hl[hb + 4usize])
                    pidx[pn] = i64(hl[hb])
                    pn += 1usize
                    tidx[tn] = i64(hl[hb + 5usize])
                    tn += 1usize
                    if df < 0.0f64 {
                        hn = h_del(hl, hn, usize(h), usize(h) + 1usize)
                        h -= 1i64
                        numh -= 1i64
                    } else {
                        xtr = r32(hl[hb + 1usize] - rx)
                        xtc = r32(hl[hb + 2usize] - cx)
                        hn = h_ins(hl, hn, 0usize, f64(xid), rx, cx, xtr, xtc, 0.0f64)
                        numh += 1i64
                        stop = true
                    }
                    if !stop { h += 1i64 }
                }
                h = numh - 2i64
                stop = false
                while h > 0i64 && !stop {
                    let hb = 6usize * usize(h)
                    dr = r32(rx - hl[hb + 1usize])
                    dc = r32(cx - hl[hb + 2usize])
                    df = vis(dc, hl[hb + 3usize], dr, hl[hb + 4usize])
                    if df < 0.0f64 {
                        ins_front(pidx, pn, i64(hl[hb]))
                        pn += 1usize
                        ins_front(tidx, tn, i64(hl[hb + 5usize]))
                        tn += 1usize
                        hn = h_del(hl, hn, usize(h) + 1usize, usize(h) + 2usize)
                        h -= 1i64
                    } else {
                        h = i64(hn) - 1i64
                        let lb = 6usize * usize(h)
                        hl[lb + 3usize] = r32(rx - hl[lb + 1usize])
                        hl[lb + 4usize] = r32(cx - hl[lb + 2usize])
                        stop = true
                    }
                }
            } else {
                hidx = 1usize
                tidx[tn] = i64(hl[5usize])
                tn += 1usize
                pidx[pn] = i64(hl[0usize])
                pn += 1usize
                var h = 1i64
                var stop = false
                while h < numh && !stop {
                    let hb = 6usize * usize(h)
                    dr = r32(rx - hl[hb + 1usize])
                    dc = r32(cx - hl[hb + 2usize])
                    df = vis(dc, hl[hb + 3usize], dr, hl[hb + 4usize])
                    pidx[pn] = i64(hl[hb])
                    pn += 1usize
                    tidx[tn] = i64(hl[hb + 5usize])
                    tn += 1usize
                    if df < 0.0f64 {
                        hn = h_del(hl, hn, usize(h), usize(h) + 1usize)
                        h -= 1i64
                        numh -= 1i64
                    } else {
                        xtr = r32(hl[hb + 1usize] - rx)
                        xtc = r32(hl[hb + 2usize] - cx)
                        let pb = 6usize * usize(h - 1i64)
                        hl[pb + 3usize] = r32(rx - hl[pb + 1usize])
                        hl[pb + 4usize] = r32(cx - hl[pb + 2usize])
                        hn = h_ins(hl, hn, usize(h), f64(xid), rx, cx, xtr, xtc, 0.0f64)
                        stop = true
                    }
                    if !stop { h += 1i64 }
                }
            }
        } else {
            var e1 = -1i64
            var e2 = numh
            var h = 1i64
            var stop = false
            while h < numh && !stop {
                let hb = 6usize * usize(h)
                dr = r32(rx - hl[hb + 1usize])
                dc = r32(cx - hl[hb + 2usize])
                df = vis(dc, hl[hb + 3usize], dr, hl[hb + 4usize])
                if df < 0.0f64 {
                    if e1 < 0i64 { e1 = h }
                } else {
                    if e1 > 0i64 {
                        e2 = h
                        stop = true
                    }
                }
                if !stop { h += 1i64 }
            }
            if e1 == -1i64 { ret -14i64 }
            var e = e1
            if e2 < numh {
                while e <= e2 {
                    pidx[pn] = i64(hl[6usize * usize(e)])
                    pn += 1usize
                    tidx[tn] = i64(hl[6usize * usize(e) + 5usize])
                    tn += 1usize
                    e += 1i64
                }
            } else {
                while e < e2 {
                    pidx[pn] = i64(hl[6usize * usize(e)])
                    pn += 1usize
                    tidx[tn] = i64(hl[6usize * usize(e) + 5usize])
                    tn += 1usize
                    e += 1i64
                }
                pidx[pn] = i64(hl[0usize])
                pn += 1usize
            }
            if e1 < e2 - 1i64 {
                hn = h_del(hl, hn, usize(e1) + 1usize, usize(e2))
            }
            if e2 == numh {
                xtr = r32(hl[1usize] - rx)
                xtc = r32(hl[2usize] - cx)
            } else {
                xtr = r32(hl[6usize * usize(e1 + 1i64) + 1usize] - rx)
                xtc = r32(hl[6usize * usize(e1 + 1i64) + 2usize] - cx)
            }
            let eb = 6usize * usize(e1)
            hl[eb + 3usize] = r32(rx - hl[eb + 1usize])
            hl[eb + 4usize] = r32(cx - hl[eb + 2usize])
            hn = h_ins(hl, hn, usize(e1) + 1usize, f64(xid), rx, cx, xtr, xtc, 0.0f64)
            hidx = usize(e1) + 1usize
        }
        let npx = i64(pn) - 1i64
        let t0 = nt
        if npx == 1i64 {
            let tb = pidx[0usize]
            let tcv = pidx[1usize]
            let nb = 6usize * nt
            td[nb] = xid
            td[nb + 1usize] = tb
            td[nb + 2usize] = tcv
            td[nb + 3usize] = -1i64
            td[nb + 4usize] = tidx[0usize]
            td[nb + 5usize] = -1i64
            back_index(td, tidx[0usize], tb, tcv, i64(nt))
            hl[6usize * hidx + 5usize] = f64(nt)
            if hidx > 0usize {
                hl[6usize * (hidx - 1usize) + 5usize] = f64(nt)
            } else {
                if hn == 0usize { ret -15i64 }
                hl[6usize * (hn - 1usize) + 5usize] = f64(nt)
            }
            nt += 1usize
        } else {
            var p = 0usize
            var tab_prev = -1i64
            while p < usize(npx) {
                let tb = pidx[p]
                let tcv = pidx[p + 1usize]
                if p > 0usize { tab_prev = i64(nt) - 1i64 }
                let nb = 6usize * nt
                td[nb] = xid
                td[nb + 1usize] = tb
                td[nb + 2usize] = tcv
                td[nb + 3usize] = tab_prev
                td[nb + 4usize] = tidx[p]
                td[nb + 5usize] = i64(nt) + 1i64
                if i64(nt) < tidx[p] + 1i64 { ret -10i64 }
                back_index(td, tidx[p], tb, tcv, i64(nt))
                nt += 1usize
                p += 1usize
            }
            td[6usize * (nt - 1usize) + 5usize] = -1i64
            hl[6usize * hidx + 5usize] = f64(nt - 1usize)
            if hidx > 0usize {
                hl[6usize * (hidx - 1usize) + 5usize] = f64(t0)
            } else {
                if hn == 0usize { ret -15i64 }
                hl[6usize * (hn - 1usize) + 5usize] = f64(t0)
            }
        }
        k += 1usize
    }
    // flipping: a first pass over every triangle, then rounds over the flipped ones
    let cap = 64usize * n + 256usize
    let ids = ai(a, cap)
    let ids2 = ai(a, cap)
    let cntu = au(a, 1usize)
    cntu[0usize] = 0usize
    var t = 0usize
    var tf = 1i64
    while t < nt && tf >= 0i64 {
        tf = flip_one(t, 0usize, pr, pc, slump, td, ids, cntu)
        t += 1usize
    }
    if tf < 0i64 { ret -3i64 }
    var cur = ids
    var nxt = ids2
    var cn = cntu[0usize]
    var nits = cn
    var nit = 1usize
    while nits > 0usize && nit < 50usize {
        cntu[0usize] = 0usize
        var x2 = 0usize
        tf = 1i64
        while x2 < cn && tf >= 0i64 {
            tf = flip_one(usize(cur[x2]), 1usize, pr, pc, slump, td, nxt, cntu)
            x2 += 1usize
        }
        cn = cntu[0usize]
        nits = cn
        let sw = cur
        cur = nxt
        nxt = sw
        nit += 1usize
        if tf < 0i64 { ret -4i64 }
    }
    cntu[0usize] = 0usize
    t = 0usize
    tf = 1i64
    while t < nt && tf >= 0i64 {
        tf = flip_one(t, 2usize, pr, pc, slump, td, cur, cntu)
        t += 1usize
    }
    cn = cntu[0usize]
    nits = 1usize
    if tf < 0i64 { nits = 0usize }
    nit = 0usize
    while nits > 0usize && nit < 100usize {
        cntu[0usize] = 0usize
        var x3 = 0usize
        tf = 1i64
        while x3 < cn && tf >= 0i64 {
            tf = flip_one(usize(cur[x3]), 1usize, pr, pc, slump, td, nxt, cntu)
            x3 += 1usize
        }
        cn = cntu[0usize]
        nits = cn
        let sw2 = cur
        cur = nxt
        nxt = sw2
        nit += 1usize
        if tf < 0i64 { ret -4i64 }
    }
    // counter-clockwise triples as shullDeltri.cpp makes them
    t = 0usize
    while t < nt {
        let o = 6usize * t
        let ta = td[o]
        let tb = td[o + 1usize]
        let tc = td[o + 2usize]
        let orient = (x[usize(tc)] - x[usize(tb)]) * (y[usize(tb)] - y[usize(ta)]) + (y[usize(tc)] - y[usize(tb)]) * (x[usize(ta)] - x[usize(tb)])
        out[o] = ta
        out[o + 3usize] = td[o + 4usize]
        if orient < 0.0f64 {
            out[o + 1usize] = tb
            out[o + 2usize] = tc
            out[o + 4usize] = td[o + 5usize]
            out[o + 5usize] = td[o + 3usize]
        } else {
            out[o + 1usize] = tc
            out[o + 2usize] = tb
            out[o + 4usize] = td[o + 3usize]
            out[o + 5usize] = td[o + 5usize]
        }
        t += 1usize
    }
    ret i64(nt)
}
