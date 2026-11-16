// R permute::shuffleSet(n, nset, control, check = FALSE): nset permutations of one design, drawn in the order doShuffleSet takes
// them (every row of the plot-level shuffles first, then every row of the within-plot shuffles, one block after another),
// which is not the order of nset calls to shuffle(). Rows are 1-based permutations, row-major nset by n.
//
// Not here: the checks of check = TRUE (they replace the set by every permutation when the design has too few) and partition plots.

use e.algo.rand.r as rng
use e.algo.stat.permute as pm
use e.math
use e.mem

// the permutation positions of the plots: out[w] = positions of the observations, where the plot at rank lvl takes the positions of
// plot pl[lvl]; lab are the plot labels of the block, levs the sorted labels
fn plot_positions(lab: []const i64, levs: []const i64, nl: usize, pl: []const usize, out: []usize) -> bool {
    let n = lab.len
    var lvl = 0usize
    while lvl < nl {
        var cnt = 0usize
        var q = 0usize
        while q < n {
            if lab[q] == levs[pl[lvl]] {
                var w = 0usize
                var seen = 0usize
                var found = false
                while w < n && !found {
                    if lab[w] == levs[lvl] {
                        if seen == cnt {
                            out[w] = q
                            found = true
                        }
                        seen += 1usize
                    }
                    w += 1usize
                }
                if !found { ret false }
                cnt += 1usize
            }
            q += 1usize
        }
        lvl += 1usize
    }
    ret true
}

// one block (ind 0-based observations): nset rows of ind[perm], answers the matrix nset by ind.len
fn do_shuffle_set(a: *mem.Arena, g: *rng.Rng, ind: []const usize, nset: usize, d: *const pm.Design) -> ([]usize, err) {
    var none: []usize = zero
    let n = ind.len
    let (set, se) = mem.alloc[usize](a, nset * n)
    if se != ok { ret (none, se) }
    var r = 0usize
    var i = 0usize
    if d.plots.len == 0usize {
        r = 0usize
        while r < nset {
            if d.within_type == pm.NONE {
                i = 0usize
                while i < n {
                    set[r * n + i] = i
                    i += 1usize
                }
            } else if d.within_type == pm.FREE {
                let (p, e) = pm.free_draw(a, g, n, n)
                if e != ok { ret (none, e) }
                i = 0usize
                while i < n {
                    set[r * n + i] = usize(p[i]) - 1usize
                    i += 1usize
                }
            } else if d.within_type == pm.SERIES {
                let (p, e) = pm.series_order(a, g, n, d.within_mirror, 0i64 - 1i64, 0i64 - 1i64)
                if e != ok { ret (none, e) }
                i = 0usize
                while i < n {
                    set[r * n + i] = p[i]
                    i += 1usize
                }
            } else {
                let (p, e) = pm.grid_perm(a, g, d.within_nrow, d.within_ncol, d.within_mirror, d.within_sym, 0i64 - 1i64, 0i64 - 1i64, 0i64 - 1i64, 0i64 - 1i64)
                if e != ok { ret (none, e) }
                i = 0usize
                while i < n {
                    set[r * n + i] = p[i]
                    i += 1usize
                }
            }
            r += 1usize
        }
    } else {
        let (lab, le) = mem.alloc[i64](a, n)
        let (levs, lve) = mem.alloc[i64](a, n)
        if le != ok { ret (none, le) }
        if lve != ok { ret (none, lve) }
        i = 0usize
        var nl = 0usize
        while i < n {
            lab[i] = d.plots[ind[i]]
            var seen = false
            var j = 0usize
            while j < nl {
                if levs[j] == lab[i] { seen = true }
                j += 1usize
            }
            if !seen {
                levs[nl] = lab[i]
                nl += 1usize
            }
            i += 1usize
        }
        i = 1usize
        while i < nl {
            var j = i
            while j > 0usize && levs[j - 1usize] > levs[j] {
                let t = levs[j]
                levs[j] = levs[j - 1usize]
                levs[j - 1usize] = t
                j -= 1usize
            }
            i += 1usize
        }
        // the plot-level permutations, every row first
        r = 0usize
        while r < nset {
            if d.plot_type == pm.NONE {
                i = 0usize
                while i < n {
                    set[r * n + i] = i
                    i += 1usize
                }
            } else {
                let (pl, ple) = mem.alloc[usize](a, nl)
                if ple != ok { ret (none, ple) }
                if d.plot_type == pm.FREE {
                    let (p, e) = pm.free_draw(a, g, nl, nl)
                    if e != ok { ret (none, e) }
                    i = 0usize
                    while i < nl {
                        pl[i] = usize(p[i]) - 1usize
                        i += 1usize
                    }
                } else if d.plot_type == pm.SERIES {
                    let (p, e) = pm.series_order(a, g, nl, d.plot_mirror, 0i64 - 1i64, 0i64 - 1i64)
                    if e != ok { ret (none, e) }
                    i = 0usize
                    while i < nl {
                        pl[i] = p[i]
                        i += 1usize
                    }
                } else {
                    let (p, e) = pm.grid_perm(a, g, d.plot_nrow, d.plot_ncol, d.plot_mirror, d.plot_sym, 0i64 - 1i64, 0i64 - 1i64, 0i64 - 1i64, 0i64 - 1i64)
                    if e != ok { ret (none, e) }
                    i = 0usize
                    while i < nl {
                        pl[i] = p[i]
                        i += 1usize
                    }
                }
                let (row, rwe) = mem.alloc[usize](a, n)
                if rwe != ok { ret (none, rwe) }
                if !plot_positions(lab, levs[0usize..nl], nl, pl, row) { ret (none, pm.UnequalPlots) }
                i = 0usize
                while i < n {
                    set[r * n + i] = row[i]
                    i += 1usize
                }
            }
            r += 1usize
        }
        if d.within_type != pm.NONE {
            let (tmp, te) = mem.alloc[usize](a, n)
            let (sizes, sze) = mem.alloc[usize](a, nl)
            let (pl2, p2e) = mem.alloc[i64](a, n)
            if te != ok { ret (none, te) }
            if sze != ok { ret (none, sze) }
            if p2e != ok { ret (none, p2e) }
            r = 0usize
            while r < nset {
                i = 0usize
                while i < n {
                    tmp[i] = set[r * n + i]
                    pl2[i] = lab[set[r * n + i]]
                    i += 1usize
                }
                i = 0usize
                while i < nl {
                    sizes[i] = 0usize
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    var j = 0usize
                    while levs[j] != pl2[i] { j += 1usize }
                    sizes[j] += 1usize
                    i += 1usize
                }
                var same: []i64 = zero
                var start = 0i64 - 1i64
                var flip = 0i64 - 1i64
                var sr = 0i64 - 1i64
                var sc = 0i64 - 1i64
                var gf0 = 0i64 - 1i64
                var gf1 = 0i64 - 1i64
                if d.constant {
                    if d.within_type == pm.FREE {
                        let (s, e) = pm.free_draw(a, g, sizes[0usize], sizes[0usize])
                        if e != ok { ret (none, e) }
                        same = s
                    } else if d.within_type == pm.SERIES {
                        let (s, e) = pm.free_draw(a, g, n / nl, 1usize)
                        if e != ok { ret (none, e) }
                        start = s[0usize]
                        if rng.unif(g) < 0.5f64 { flip = 1i64 } else { flip = 0i64 }
                    } else {
                        let (s1, e1) = pm.free_draw(a, g, d.within_nrow, 1usize)
                        if e1 != ok { ret (none, e1) }
                        sr = s1[0usize]
                        let (s2, e2) = pm.free_draw(a, g, d.within_ncol, 1usize)
                        if e2 != ok { ret (none, e2) }
                        sc = s2[0usize]
                        let (b0, b1, be) = pm.grid_flip(a, g, d.within_mirror, d.within_sym, 0i64 - 1i64, 0i64 - 1i64)
                        if be != ok { ret (none, be) }
                        gf0 = b0
                        gf1 = b1
                    }
                }
                var lv = 0usize
                while lv < nl {
                    let ng = sizes[lv]
                    if ng > 1usize {
                        let (gr, gre) = mem.alloc[usize](a, ng)
                        let (sel, sele) = mem.alloc[usize](a, ng)
                        if gre != ok { ret (none, gre) }
                        if sele != ok { ret (none, sele) }
                        var m = 0usize
                        i = 0usize
                        while i < n {
                            if pl2[i] == levs[lv] {
                                gr[m] = set[r * n + i]
                                m += 1usize
                            }
                            i += 1usize
                        }
                        if d.within_type == pm.FREE {
                            if d.constant {
                                i = 0usize
                                while i < ng {
                                    sel[i] = usize(same[i]) - 1usize
                                    i += 1usize
                                }
                            } else {
                                let (p, e) = pm.free_draw(a, g, ng, ng)
                                if e != ok { ret (none, e) }
                                i = 0usize
                                while i < ng {
                                    sel[i] = usize(p[i]) - 1usize
                                    i += 1usize
                                }
                            }
                        } else if d.within_type == pm.SERIES {
                            let (p, e) = pm.series_order(a, g, ng, d.within_mirror, start, flip)
                            if e != ok { ret (none, e) }
                            i = 0usize
                            while i < ng {
                                sel[i] = p[i]
                                i += 1usize
                            }
                        } else {
                            let (p, e) = pm.grid_perm(a, g, d.within_nrow, d.within_ncol, d.within_mirror, d.within_sym, sr, sc, gf0, gf1)
                            if e != ok { ret (none, e) }
                            i = 0usize
                            while i < ng {
                                sel[i] = p[i]
                                i += 1usize
                            }
                        }
                        m = 0usize
                        i = 0usize
                        while i < n {
                            if pl2[i] == levs[lv] {
                                tmp[i] = gr[sel[m]]
                                m += 1usize
                            }
                            i += 1usize
                        }
                    }
                    lv += 1usize
                }
                i = 0usize
                while i < n {
                    set[r * n + i] = tmp[i]
                    i += 1usize
                }
                r += 1usize
            }
        }
    }
    r = 0usize
    while r < nset {
        i = 0usize
        while i < n {
            set[r * n + i] = ind[set[r * n + i]]
            i += 1usize
        }
        r += 1usize
    }
    ret (set, ok)
}

// shuffleSet(n, nset, control, check = FALSE): nset by n row-major, 1-based
fn shuffle_set(a: *mem.Arena, g: *rng.Rng, n: usize, nset: usize, d: *const pm.Design) -> ([]usize, err) {
    var none: []usize = zero
    let (out, oe) = mem.alloc[usize](a, nset * n)
    if oe != ok { ret (none, oe) }
    if d.blocks.len == 0usize {
        let (ind, ie) = mem.alloc[usize](a, n)
        if ie != ok { ret (none, ie) }
        var i = 0usize
        while i < n {
            ind[i] = i
            i += 1usize
        }
        let (r, re) = do_shuffle_set(a, g, ind, nset, d)
        if re != ok { ret (none, re) }
        i = 0usize
        while i < nset * n {
            out[i] = r[i] + 1usize
            i += 1usize
        }
        ret (out, ok)
    }
    let (levs, le) = mem.alloc[i64](a, n)
    if le != ok { ret (none, le) }
    var nl = 0usize
    var i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < nl {
            if levs[j] == d.blocks[i] { seen = true }
            j += 1usize
        }
        if !seen {
            levs[nl] = d.blocks[i]
            nl += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < nl {
        var j = i
        while j > 0usize && levs[j - 1usize] > levs[j] {
            let t = levs[j]
            levs[j] = levs[j - 1usize]
            levs[j - 1usize] = t
            j -= 1usize
        }
        i += 1usize
    }
    // the blocks one after another; the columns of the block's matrix go back to the observations they came from
    var b = 0usize
    while b < nl {
        var cnt = 0usize
        i = 0usize
        while i < n {
            if d.blocks[i] == levs[b] { cnt += 1usize }
            i += 1usize
        }
        let (ind, ie) = mem.alloc[usize](a, cnt)
        if ie != ok { ret (none, ie) }
        var m = 0usize
        i = 0usize
        while i < n {
            if d.blocks[i] == levs[b] {
                ind[m] = i
                m += 1usize
            }
            i += 1usize
        }
        let (r, re) = do_shuffle_set(a, g, ind, nset, d)
        if re != ok { ret (none, re) }
        var s = 0usize
        while s < nset {
            m = 0usize
            while m < cnt {
                out[s * n + ind[m]] = r[s * cnt + m] + 1usize
                m += 1usize
            }
            s += 1usize
        }
        b += 1usize
    }
    ret (out, ok)
}

// ---- allPerms of a design: within, plot-level and block enumeration in the order of permute::allPerms

type Mat = struct { v: []usize, rows: usize, cols: usize }

fn norient(mirror: bool, symmetric: bool, nr: usize, nc: usize) -> usize {
    var c = 1usize
    if mirror && nr > 2usize { c += 1usize }
    if mirror && nc > 2usize { c += 1usize }
    if mirror && !symmetric && nr > 2usize && nc > 2usize { c += 1usize }
    ret c
}

fn fact(n: usize) -> usize {
    var f = 1usize
    var i = 2usize
    while i <= n {
        f = f * i
        i += 1usize
    }
    ret f
}

// allFree(n): all permutations in lexicographic order, 1-based
fn all_free(a: *mem.Arena, n: usize) -> (Mat, err) {
    var none: Mat = zero
    let rows = fact(n)
    let (v, e) = mem.alloc[usize](a, rows * n + 1usize)
    let (cur, ce) = mem.alloc[usize](a, n)
    if e != ok { ret (none, e) }
    if ce != ok { ret (none, ce) }
    var i = 0usize
    while i < n {
        cur[i] = i + 1usize
        i += 1usize
    }
    var r = 0usize
    while r < rows {
        i = 0usize
        while i < n {
            v[r * n + i] = cur[i]
            i += 1usize
        }
        var k = n
        while k >= 2usize && cur[k - 2usize] > cur[k - 1usize] { k -= 1usize }
        if k >= 2usize {
            var l = n
            while cur[l - 1usize] < cur[k - 2usize] { l -= 1usize }
            let t = cur[k - 2usize]
            cur[k - 2usize] = cur[l - 1usize]
            cur[l - 1usize] = t
            var lo = k - 1usize
            var hi = n - 1usize
            while lo < hi {
                let t2 = cur[lo]
                cur[lo] = cur[hi]
                cur[hi] = t2
                lo += 1usize
                hi -= 1usize
            }
        }
        r += 1usize
    }
    ret (Mat { v: v, rows: rows, cols: n }, ok)
}

// allSeries(n, nperms, mirror): the cyclic shifts, then the shifts reversed when mirroring (and nperms > 2)
fn all_series(a: *mem.Arena, n: usize, mirror: bool) -> (Mat, err) {
    var none: Mat = zero
    var rows = n
    if mirror && n > 2usize { rows = 2usize * n }
    let (v, e) = mem.alloc[usize](a, rows * n + 1usize)
    if e != ok { ret (none, e) }
    var i = 0usize
    while i < n {
        var k = 0usize
        while k < n {
            v[i * n + k] = (i + 1usize + k) % n + 1usize
            k += 1usize
        }
        i += 1usize
    }
    if rows > n {
        i = 0usize
        while i < n {
            var k = 0usize
            while k < n {
                v[(n + i) * n + k] = v[i * n + (n - 1usize - k)]
                k += 1usize
            }
            i += 1usize
        }
    }
    ret (Mat { v: v, rows: rows, cols: n }, ok)
}

fn all_grid(a: *mem.Arena, nr: usize, nc: usize, mirror: bool, symmetric: bool) -> (Mat, err) {
    var none: Mat = zero
    let n = nr * nc
    let no = norient(mirror, symmetric, nr, nc)
    let rows = n * no
    let (v, e) = mem.alloc[usize](a, rows * n + 1usize)
    if e != ok { ret (none, e) }
    // the orientations in the order of gridOrientations
    var ofr: [4]bool = zero
    var ofc: [4]bool = zero
    var cnt = 1usize
    if mirror && nr > 2usize {
        ofr[cnt] = true
        cnt += 1usize
    }
    if mirror && nc > 2usize {
        ofc[cnt] = true
        cnt += 1usize
    }
    if mirror && !symmetric && nr > 2usize && nc > 2usize {
        ofr[cnt] = true
        ofc[cnt] = true
        cnt += 1usize
    }
    var row = 0usize
    var k = 0usize
    while k < no {
        let fr = ofr[k]
        let fc = ofc[k]
        var i = 1usize
        while i <= nr {
            var j = 1usize
            while j <= nc {
                var c = 0usize
                while c < nc {
                    var ic = (j + c) % nc
                    if fc { ic = (j + nc - 1usize - c) % nc }
                    var r = 0usize
                    while r < nr {
                        var ir = (i + r) % nr
                        if fr { ir = (i + nr - 1usize - r) % nr }
                        v[row * n + c * nr + r] = ic * nr + ir + 1usize
                        r += 1usize
                    }
                    c += 1usize
                }
                row += 1usize
                j += 1usize
            }
            i += 1usize
        }
        k += 1usize
    }
    ret (Mat { v: v, rows: rows, cols: n }, ok)
}

// the within or plot-level enumeration of m objects: type FREE, SERIES or GRID
fn all_type(a: *mem.Arena, t: u8, m: usize, mirror: bool, symmetric: bool, nr: usize, nc: usize) -> (Mat, err) {
    if t == pm.FREE {
        let (x, e) = all_free(a, m)
        ret (x, e)
    }
    if t == pm.SERIES {
        let (x, e) = all_series(a, m, mirror)
        ret (x, e)
    }
    let (x, e) = all_grid(a, nr, nc, mirror, symmetric)
    ret (x, e)
}

// cbindAllPerms: the matrices side by side, the first varying slowest
fn cbind_all(a: *mem.Arena, ms: []const Mat, nm: usize) -> (Mat, err) {
    var none: Mat = zero
    var rows = 1usize
    var cols = 0usize
    var i = 0usize
    while i < nm {
        rows = rows * ms[i].rows
        cols += ms[i].cols
        i += 1usize
    }
    let (v, e) = mem.alloc[usize](a, rows * cols + 1usize)
    if e != ok { ret (none, e) }
    var r = 0usize
    while r < rows {
        var rem = r
        var off = cols
        i = nm
        while i > 0usize {
            i -= 1usize
            let idx = rem % ms[i].rows
            rem = rem / ms[i].rows
            off -= ms[i].cols
            var c = 0usize
            while c < ms[i].cols {
                v[r * cols + off + c] = ms[i].v[idx * ms[i].cols + c]
                c += 1usize
            }
        }
        r += 1usize
    }
    ret (Mat { v: v, rows: rows, cols: cols }, ok)
}

// doAllPerms for one block (obs the 0-based observations): rows of observation indices (1-based)
fn do_all_perms(a: *mem.Arena, obs: []const usize, d: *const pm.Design) -> (Mat, err) {
    var none: Mat = zero
    let n = obs.len
    var res: Mat = zero
    var have = false
    if d.plots.len == 0usize {
        if d.within_type != pm.NONE {
            let (m, e) = all_type(a, d.within_type, n, d.within_mirror, d.within_sym, d.within_nrow, d.within_ncol)
            if e != ok { ret (none, e) }
            res = m
            have = true
        }
    } else {
        let (lab, le) = mem.alloc[i64](a, n)
        let (levs, lve) = mem.alloc[i64](a, n)
        if le != ok { ret (none, le) }
        if lve != ok { ret (none, lve) }
        var nl = 0usize
        var i = 0usize
        while i < n {
            lab[i] = d.plots[obs[i]]
            var seen = false
            var j = 0usize
            while j < nl {
                if levs[j] == lab[i] { seen = true }
                j += 1usize
            }
            if !seen {
                levs[nl] = lab[i]
                nl += 1usize
            }
            i += 1usize
        }
        i = 1usize
        while i < nl {
            var j = i
            while j > 0usize && levs[j - 1usize] > levs[j] {
                let t = levs[j]
                levs[j] = levs[j - 1usize]
                levs[j - 1usize] = t
                j -= 1usize
            }
            i += 1usize
        }
        let (sizes, se) = mem.alloc[usize](a, nl)
        if se != ok { ret (none, se) }
        i = 0usize
        while i < nl {
            sizes[i] = 0usize
            i += 1usize
        }
        i = 0usize
        while i < n {
            var j = 0usize
            while levs[j] != lab[i] { j += 1usize }
            sizes[j] += 1usize
            i += 1usize
        }
        var equal = true
        i = 1usize
        while i < nl {
            if sizes[i] != sizes[0usize] { equal = false }
            i += 1usize
        }
        if d.within_type != pm.NONE {
            let (parts, pe) = mem.alloc[Mat](a, nl)
            if pe != ok { ret (none, pe) }
            var off = 0usize
            if d.constant && equal {
                let (base, be) = all_type(a, d.within_type, sizes[0usize], d.within_mirror, d.within_sym, d.within_nrow, d.within_ncol)
                if be != ok { ret (none, be) }
                let (v, ve) = mem.alloc[usize](a, base.rows * n + 1usize)
                if ve != ok { ret (none, ve) }
                var r = 0usize
                while r < base.rows {
                    var q = 0usize
                    while q < nl {
                        var c = 0usize
                        while c < base.cols {
                            v[r * n + q * base.cols + c] = base.v[r * base.cols + c] + q * base.cols
                            c += 1usize
                        }
                        q += 1usize
                    }
                    r += 1usize
                }
                res = Mat { v: v, rows: base.rows, cols: n }
            } else {
                i = 0usize
                while i < nl {
                    let (m1, e1) = all_type(a, d.within_type, sizes[i], d.within_mirror, d.within_sym, d.within_nrow, d.within_ncol)
                    if e1 != ok { ret (none, e1) }
                    var k = 0usize
                    while k < m1.rows * m1.cols {
                        m1.v[k] += off
                        k += 1usize
                    }
                    parts[i] = m1
                    off += sizes[i]
                    i += 1usize
                }
                let (cb, ce) = cbind_all(a, parts, nl)
                if ce != ok { ret (none, ce) }
                res = cb
            }
            have = true
        }
        if d.plot_type != pm.NONE {
            // allStrata: the plots permuted as wholes, rows of positions
            let (pp, pe2) = all_type(a, d.plot_type, nl, d.plot_mirror, d.plot_sym, d.plot_nrow, d.plot_ncol)
            if pe2 != ok { ret (none, pe2) }
            let (sp, spe) = mem.alloc[usize](a, n + 1usize)
            let (spo, spoe) = mem.alloc[usize](a, nl + 1usize)
            if spe != ok { ret (none, spe) }
            if spoe != ok { ret (none, spoe) }
            var at = 0usize
            var j = 0usize
            while j < nl {
                spo[j] = at
                i = 0usize
                while i < n {
                    if lab[i] == levs[j] {
                        sp[at] = i + 1usize
                        at += 1usize
                    }
                    i += 1usize
                }
                j += 1usize
            }
            spo[nl] = at
            let (st, ste) = mem.alloc[usize](a, pp.rows * n + 1usize)
            if ste != ok { ret (none, ste) }
            var r = 0usize
            while r < pp.rows {
                j = 0usize
                while j < nl {
                    let src = pp.v[r * nl + j] - 1usize
                    var w = 0usize
                    var q = 0usize
                    while q < n {
                        if lab[q] == levs[j] {
                            st[r * n + q] = sp[spo[src] + w]
                            w += 1usize
                        }
                        q += 1usize
                    }
                    j += 1usize
                }
                r += 1usize
            }
            if !have {
                res = Mat { v: st, rows: pp.rows, cols: n }
            } else {
                let rows = pp.rows * res.rows
                let (v, ve) = mem.alloc[usize](a, rows * n + 1usize)
                if ve != ok { ret (none, ve) }
                var pr = 0usize
                while pr < pp.rows {
                    var wr = 0usize
                    while wr < res.rows {
                        var c = 0usize
                        while c < n {
                            v[(pr * res.rows + wr) * n + c] = res.v[wr * n + (st[pr * n + c] - 1usize)]
                            c += 1usize
                        }
                        wr += 1usize
                    }
                    pr += 1usize
                }
                res = Mat { v: v, rows: rows, cols: n }
            }
            have = true
        }
    }
    if !have { ret (none, pm.Unsupported) }
    var k = 0usize
    while k < res.rows * res.cols {
        res.v[k] = obs[res.v[k] - 1usize] + 1usize
        k += 1usize
    }
    ret (res, ok)
}

// allPerms(n, control, check = FALSE) with observed = FALSE: the matrix of all permutations of the design but the identity;
// answers the number of rows written to out (row-major, 1-based); out must be large enough
fn all_perms_design(a: *mem.Arena, n: usize, d: *const pm.Design, out: []usize) -> (usize, err) {
    var nb = 1usize
    let (levs, le) = mem.alloc[i64](a, n)
    if le != ok { ret (0usize, le) }
    if d.blocks.len > 0usize {
        nb = 0usize
        var i = 0usize
        while i < n {
            var seen = false
            var j = 0usize
            while j < nb {
                if levs[j] == d.blocks[i] { seen = true }
                j += 1usize
            }
            if !seen {
                levs[nb] = d.blocks[i]
                nb += 1usize
            }
            i += 1usize
        }
        i = 1usize
        while i < nb {
            var j = i
            while j > 0usize && levs[j - 1usize] > levs[j] {
                let t = levs[j]
                levs[j] = levs[j - 1usize]
                levs[j - 1usize] = t
                j -= 1usize
            }
            i += 1usize
        }
    }
    let (ms, me) = mem.alloc[Mat](a, nb)
    let (inds, ie) = mem.alloc[usize](a, n)
    let (starts, ste) = mem.alloc[usize](a, nb + 1usize)
    if me != ok { ret (0usize, me) }
    if ie != ok { ret (0usize, ie) }
    if ste != ok { ret (0usize, ste) }
    var at = 0usize
    var b = 0usize
    while b < nb {
        starts[b] = at
        var i = 0usize
        while i < n {
            if d.blocks.len == 0usize || d.blocks[i] == levs[b] {
                inds[at] = i
                at += 1usize
            }
            i += 1usize
        }
        let (m, e) = do_all_perms(a, inds[starts[b]..at], d)
        if e != ok { ret (0usize, e) }
        ms[b] = m
        b += 1usize
    }
    starts[nb] = at
    let (cb, ce) = cbind_all(a, ms, nb)
    if ce != ok { ret (0usize, ce) }
    var rows = 0usize
    var r = 0usize
    while r < cb.rows {
        var same = true
        var c = 0usize
        while c < n {
            if cb.v[r * n + c] != inds[c] + 1usize { same = false }
            c += 1usize
        }
        if !same {
            c = 0usize
            while c < n {
                out[rows * n + inds[c]] = cb.v[r * n + c]
                c += 1usize
            }
            rows += 1usize
        }
        r += 1usize
    }
    ret (rows, ok)
}
