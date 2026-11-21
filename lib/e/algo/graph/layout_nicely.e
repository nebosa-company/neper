// R igraph layout_nicely and align_layout (igraph_layout_align), in two dimensions, ported from igraph 2.3.4:
// a forest of at most 30 vertices gets layout_as_tree, a smaller-than-1000 graph layout_with_fr followed by
// the alignment of the layout with the axes, a graph of 1000 vertices or more layout_with_drl with its default options.
// Weights are not taken.

use e.algo.graph.layout_drl as ld
use e.algo.graph.layout_force as lf
use e.algo.graph.layout_tree as lt
use e.algo.graph.games as gg
use e.algo.linalg.lapack_syevr as lap
use e.algo.rand.r as rg
use e.math
use e.mem
use e.os

// igraph_layout_align for a 2-column layout, in place
fn align(a: *mem.Arena, n: usize, ed: []const i64, lay: []f64) {
    if n == 0usize { ret }
    var cx = 0.0f64
    var cy = 0.0f64
    var i = 0usize
    while i < n {
        cx += lay[i * 2usize]
        cy += lay[i * 2usize + 1usize]
        i += 1usize
    }
    let nf = f64(n)
    cx = cx * (1.0f64 / nf)
    cy = cy * (1.0f64 / nf)
    i = 0usize
    while i < n {
        lay[i * 2usize] -= cx
        lay[i * 2usize + 1usize] -= cy
        i += 1usize
    }
    let m = gg.zf(a, 4usize)
    let mc = gg.zf(a, 4usize)
    var norm2 = 0.0f64
    var norm2c = 0.0f64
    var saved = false
    var k = 0usize
    while k + 1usize < ed.len {
        let from = usize(ed[k])
        let to = usize(ed[k + 1usize])
        k += 2usize
        if from != to {
            let ev = gg.zf(a, 2usize)
            ev[0usize] = lay[from * 2usize] - lay[to * 2usize]
            ev[1usize] = lay[from * 2usize + 1usize] - lay[to * 2usize + 1usize]
            var p = 0usize
            while p < 2usize {
                var q = 0usize
                while q < 2usize {
                    let mm = ev[p] * ev[q]
                    m[p + q * 2usize] += mm
                    if p == q { norm2 += mm }
                    q += 1usize
                }
                p += 1usize
            }
            if !saved && norm2 > 0.0f64 {
                saved = true
                norm2c = norm2
                var z = 0usize
                while z < 4usize {
                    mc[z] = m[z]
                    z += 1usize
                }
            }
        }
    }
    if norm2 == 0.0f64 {
        i = 0usize
        while i < n {
            var p = 0usize
            while p < 2usize {
                var q = 0usize
                while q < 2usize {
                    let mm = lay[i * 2usize + p] * lay[i * 2usize + q]
                    m[p + q * 2usize] += mm
                    if p == q { norm2 += mm }
                    q += 1usize
                }
                p += 1usize
            }
            if !saved && norm2 > 0.0f64 {
                saved = true
                norm2c = norm2
                var z = 0usize
                while z < 4usize {
                    mc[z] = m[z]
                    z += 1usize
                }
            }
            i += 1usize
        }
    }
    if norm2 == 0.0f64 { ret }
    let q4 = gg.zf(a, 4usize)
    let w = gg.zf(a, 2usize)
    let rot = gg.zf(a, 4usize)
    var retried = false
    while true {
        var z = 0usize
        while z < 4usize {
            q4[z] = m[z] * (1.0f64 / norm2)
            z += 1usize
        }
        q4[0usize] -= 1.0f64 / 2.0f64
        q4[3usize] -= 1.0f64 / 2.0f64
        let (isuppz, e2) = mem.alloc[i64](a, 4usize)
        if e2 != ok { os.exit(9) }
        var mcnt = 0i64
        var info = 0i64
        var wk: [1]f64 = zero
        var iwk: [1]i64 = zero
        let qq = gg.zf(a, 4usize)
        z = 0usize
        while z < 4usize {
            qq[z] = q4[z]
            z += 1usize
        }
        lap.dsyevr("V", "A", "U", 2i64, qq[0usize..], 2i64, 0.0f64, 0.0f64, 0i64, 0i64, 1e-6f64, &mcnt, w[0usize..], rot[0usize..], 2i64, isuppz[0usize..], wk[0usize..], 0i64 - 1i64, iwk[0usize..], 0i64 - 1i64, &info)
        let lwork = usize(i64(wk[0usize]))
        let liwork = usize(iwk[0usize])
        let (work, e3) = mem.alloc[f64](a, lwork)
        let (iwork, e4) = mem.alloc[i64](a, liwork)
        if e3 != ok || e4 != ok { os.exit(9) }
        z = 0usize
        while z < 4usize {
            qq[z] = q4[z]
            z += 1usize
        }
        lap.dsyevr("V", "A", "U", 2i64, qq[0usize..], 2i64, 0.0f64, 0.0f64, 0i64, 0i64, 1e-6f64, &mcnt, w[0usize..], rot[0usize..], 2i64, isuppz[0usize..], work[0usize..], i64(lwork), iwork[0usize..], i64(liwork), &info)
        if info != 0i64 { os.exit(9) }
        var mnorm = 0.0f64
        z = 0usize
        while z < 2usize {
            let mag = math.abs[f64](w[z])
            if mag > mnorm { mnorm = mag }
            z += 1usize
        }
        if mnorm > 1e-3f64 || retried { break }
        z = 0usize
        while z < 4usize {
            m[z] = m[z] - mc[z]
            z += 1usize
        }
        norm2 -= norm2c
        retried = true
    }
    // temp = layout * rot (dgemm, columns of rot are the eigenvectors)
    let tmp = gg.zf(a, 2usize * n)
    var j = 0usize
    while j < 2usize {
        var l = 0usize
        while l < 2usize {
            let t = rot[l + j * 2usize]
            i = 0usize
            while i < n {
                tmp[i * 2usize + j] += t * lay[i * 2usize + l]
                i += 1usize
            }
            l += 1usize
        }
        j += 1usize
    }
    var e0 = 0.0f64
    var e1 = 0.0f64
    j = 0usize
    while j < 2usize {
        var lo = 1.0f64 / 0.0f64
        var hi = 0.0f64 - 1.0f64 / 0.0f64
        i = 0usize
        while i < n {
            let c = tmp[i * 2usize + j]
            if c < lo { lo = c }
            if c > hi { hi = c }
            i += 1usize
        }
        if j == 0usize { e0 = hi - lo } else { e1 = hi - lo }
        j += 1usize
    }
    var p0 = 0usize
    var p1 = 1usize
    if e0 < e1 {
        p0 = 1usize
        p1 = 0usize
    }
    i = 0usize
    while i < n {
        lay[i * 2usize] = tmp[i * 2usize + p0]
        lay[i * 2usize + 1usize] = tmp[i * 2usize + p1]
        i += 1usize
    }
}

fn is_forest(a: *mem.Arena, n: usize, ed: []const i64, directed: bool) -> bool {
    let par = gg.zi(a, n)
    let indeg = gg.zi(a, n)
    var i = 0usize
    while i < n {
        par[i] = i64(i)
        i += 1usize
    }
    var comps = n
    var k = 0usize
    while k + 1usize < ed.len {
        var x = ed[k]
        var y = ed[k + 1usize]
        indeg[usize(y)] += 1i64
        while par[usize(x)] != x { x = par[usize(x)] }
        while par[usize(y)] != y { y = par[usize(y)] }
        if x != y {
            par[usize(x)] = y
            comps -= 1usize
        }
        k += 2usize
    }
    if ed.len / 2usize != n - comps { ret false }
    if directed {
        i = 0usize
        while i < n {
            if indeg[i] > 1i64 { ret false }
            i += 1usize
        }
    }
    ret true
}

fn nicely(a: *mem.Arena, r: *rg.Rng, n: usize, ed: []const i64, directed: bool) -> []f64 {
    let none = gg.alloc_u(a, 0usize)
    let nl = gg.zi(a, 0usize)
    if is_forest(a, n, ed, directed) && n <= 30usize {
        ret lt.tree(a, n, ed, directed, 1usize, none[0usize..0usize], nl[0usize..0usize], false, true)
    }
    let w = gg.zf(a, 0usize)
    if n >= 1000usize {
        let o = gg.zf(a, 25usize)
        o[0usize] = 0.8f64
        o[1usize] = 0.0f64
        o[2usize] = 2000.0f64
        o[3usize] = 10.0f64
        o[4usize] = 1.0f64
        o[5usize] = 200.0f64
        o[6usize] = 2000.0f64
        o[7usize] = 10.0f64
        o[8usize] = 1.0f64
        o[9usize] = 200.0f64
        o[10usize] = 2000.0f64
        o[11usize] = 2.0f64
        o[12usize] = 1.0f64
        o[13usize] = 200.0f64
        o[14usize] = 2000.0f64
        o[15usize] = 1.0f64
        o[16usize] = 0.1f64
        o[17usize] = 50.0f64
        o[18usize] = 250.0f64
        o[19usize] = 1.0f64
        o[20usize] = 0.25f64
        o[21usize] = 100.0f64
        o[22usize] = 250.0f64
        o[23usize] = 0.5f64
        o[24usize] = 0.0f64
        ret ld.drl(a, r, n, ed, w[0usize..0usize], o[0usize..25usize])
    }
    let lay = lf.fr(a, r, n, ed, 500usize, math.sqrt[f64](f64(n)), w[0usize..0usize])
    align(a, n, ed, lay)
    ret lay
}
