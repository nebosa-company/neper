// R geometry package in n dimensions (2 to 7): convhulln (facet count, boundary measure, enclosed measure), delaunayn through the lifted lower hull, circumcentres (the Voronoi vertices), tsearch and tsearchn, cart2bary, inhulln, intersectn through the dual hull of the facet planes, surf.tri and dot. The hull is incremental (beneath and beyond) with simplicial facets; a point coplanar with a facet is not visible from it, so a degenerate input (the vertices of a polytope with non-simplicial facets) still gives the right measures.
//
// Not here: the Qhull option string, distmesh, tsearch with the quadtree order of results on ties, the facet adjacency that convhulln returns.

use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// determinant of the k by k row-major matrix m, destroyed
fn det_lu(m: []f64, k: usize) -> f64 {
    var det = 1.0f64
    var c = 0usize
    while c < k {
        var piv = c
        var best = math.abs[f64](m[c * k + c])
        var r = c + 1usize
        while r < k {
            let v = math.abs[f64](m[r * k + c])
            if v > best {
                best = v
                piv = r
            }
            r += 1usize
        }
        if best == 0.0f64 { ret 0.0f64 }
        if piv != c {
            var t = 0usize
            while t < k {
                let x = m[c * k + t]
                m[c * k + t] = m[piv * k + t]
                m[piv * k + t] = x
                t += 1usize
            }
            det = 0.0f64 - det
        }
        det = det * m[c * k + c]
        r = c + 1usize
        while r < k {
            let f = m[r * k + c] / m[c * k + c]
            var t = c
            while t < k {
                m[r * k + t] = m[r * k + t] - f * m[c * k + t]
                t += 1usize
            }
            r += 1usize
        }
        c += 1usize
    }
    ret det
}

// solves the k by k system m x = b (row-major m, destroyed; b becomes x); false when singular
fn solve_lu(m: []f64, b: []f64, k: usize) -> bool {
    var c = 0usize
    while c < k {
        var piv = c
        var best = math.abs[f64](m[c * k + c])
        var r = c + 1usize
        while r < k {
            let v = math.abs[f64](m[r * k + c])
            if v > best {
                best = v
                piv = r
            }
            r += 1usize
        }
        if best < 1.0e-300f64 { ret false }
        if piv != c {
            var t = 0usize
            while t < k {
                let x = m[c * k + t]
                m[c * k + t] = m[piv * k + t]
                m[piv * k + t] = x
                t += 1usize
            }
            let y = b[c]
            b[c] = b[piv]
            b[piv] = y
        }
        r = c + 1usize
        while r < k {
            let f = m[r * k + c] / m[c * k + c]
            var t = c
            while t < k {
                m[r * k + t] = m[r * k + t] - f * m[c * k + t]
                t += 1usize
            }
            b[r] = b[r] - f * b[c]
            r += 1usize
        }
        c += 1usize
    }
    var i = k
    while i > 0usize {
        i -= 1usize
        var s = b[i]
        var j = i + 1usize
        while j < k {
            s = s - m[i * k + j] * b[j]
            j += 1usize
        }
        b[i] = s / m[i * k + i]
    }
    ret true
}

// unit normal of the hyperplane through the d points vs (indices into the n by d array p) into nrm; answers the offset n.x, NaN when the points do not span a hyperplane. mat is scratch of d*d.
fn plane(p: []const f64, vs: []const usize, d: usize, mat: []f64, nrm: []f64) -> f64 {
    let k = d - 1usize
    var j = 0usize
    var len = 0.0f64
    while j < d {
        var r = 0usize
        while r < k {
            var cc = 0usize
            var col = 0usize
            while col < d {
                if col != j {
                    mat[r * k + cc] = p[vs[r + 1usize] * d + col] - p[vs[0usize] * d + col]
                    cc += 1usize
                }
                col += 1usize
            }
            r += 1usize
        }
        var v = 0.0f64
        if k == 0usize { v = 1.0f64 } else { v = det_lu(mat[0usize..k * k], k) }
        if j % 2usize == 1usize { v = 0.0f64 - v }
        nrm[j] = v
        len += v * v
        j += 1usize
    }
    len = math.sqrt[f64](len)
    if len < 1.0e-300f64 { ret nan() }
    var off = 0.0f64
    j = 0usize
    while j < d {
        nrm[j] = nrm[j] / len
        off += nrm[j] * p[vs[0usize] * d + j]
        j += 1usize
    }
    ret off
}

// fills the slot's plane from its (sorted) vertices and orients it away from the interior point c; false when degenerate
fn make_facet(p: []const f64, d: usize, slot: usize, vo: []const usize, no: []f64, oo: []f64, c: []const f64, mat: []f64) -> bool {
    var off = plane(p, vo[slot * d..slot * d + d], d, mat, no[slot * d..slot * d + d])
    if off != off { ret false }
    var s = 0.0f64 - off
    var j = 0usize
    while j < d {
        s += no[slot * d + j] * c[j]
        j += 1usize
    }
    if math.abs[f64](s) < 1.0e-14f64 { ret false }
    if s > 0.0f64 {
        j = 0usize
        while j < d {
            no[slot * d + j] = 0.0f64 - no[slot * d + j]
            j += 1usize
        }
        off = 0.0f64 - off
    }
    oo[slot] = off
    ret true
}

fn same_ridge(vo: []const usize, d: usize, f1: usize, j1: usize, f2: usize, j2: usize) -> bool {
    var s = 0usize
    var t = 0usize
    while s < d {
        if s == j1 { s += 1usize }
        if t == j2 { t += 1usize }
        if s < d && t < d {
            if vo[f1 * d + s] != vo[f2 * d + t] { ret false }
        }
        s += 1usize
        t += 1usize
    }
    ret true
}

const HULL_CAP: usize = 40000usize

// the convex hull of the n by d array p as simplicial facets: (slots used, vertices per slot (sorted, d each), outward unit normal per slot, offset per slot, alive flag per slot, interior point). Zero slots when the points do not span d dimensions or the hull outgrows HULL_CAP facets.
fn hull_core(a: *mem.Arena, p: []const f64, n: usize, d: usize) -> (usize, []usize, []f64, []f64, []usize, []f64) {
    let cap = HULL_CAP
    let (vo, e1) = mem.alloc[usize](a, cap * d)
    let (no, e2) = mem.alloc[f64](a, cap * d)
    let (oo, e3) = mem.alloc[f64](a, cap)
    let (al, e4) = mem.alloc[usize](a, cap)
    let (c, e5) = mem.alloc[f64](a, d)
    let (fr, e6) = mem.alloc[usize](a, cap)
    let (vis, e7) = mem.alloc[usize](a, cap)
    let (rf, e8) = mem.alloc[usize](a, cap * d)
    let (rj, e9) = mem.alloc[usize](a, cap * d)
    let (mt, e10) = mem.alloc[usize](a, cap * d)
    let (nw, e11) = mem.alloc[usize](a, cap * d)
    let (mat, e12) = mem.alloc[f64](a, d * d)
    let (bs, e13) = mem.alloc[f64](a, d * d)
    let (rs, e14) = mem.alloc[f64](a, d)
    let (used, e15) = mem.alloc[usize](a, n)
    let (ch, e16) = mem.alloc[usize](a, d + 1usize)
    var failed = e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok
    if e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok { failed = true }
    if failed { ret (0usize, vo, no, oo, al, c) }
    var scale = 0.0f64
    var i = 0usize
    while i < n * d {
        if math.abs[f64](p[i]) > scale { scale = math.abs[f64](p[i]) }
        i += 1usize
    }
    if scale == 0.0f64 { ret (0usize, vo, no, oo, al, c) }
    i = 0usize
    while i < n {
        used[i] = 0usize
        i += 1usize
    }
    ch[0usize] = 0usize
    used[0usize] = 1usize
    var nb = 0usize
    var k = 1usize
    while k <= d {
        var best = 0.0f64 - 1.0f64
        var bi = n
        i = 0usize
        while i < n {
            if used[i] == 0usize {
                var j = 0usize
                while j < d {
                    rs[j] = p[i * d + j] - p[j]
                    j += 1usize
                }
                var pass = 0usize
                while pass < 2usize {
                    var b = 0usize
                    while b < nb {
                        var dp = 0.0f64
                        j = 0usize
                        while j < d {
                            dp += rs[j] * bs[b * d + j]
                            j += 1usize
                        }
                        j = 0usize
                        while j < d {
                            rs[j] = rs[j] - dp * bs[b * d + j]
                            j += 1usize
                        }
                        b += 1usize
                    }
                    pass += 1usize
                }
                var len = 0.0f64
                j = 0usize
                while j < d {
                    len += rs[j] * rs[j]
                    j += 1usize
                }
                len = math.sqrt[f64](len)
                if len > best {
                    best = len
                    bi = i
                }
            }
            i += 1usize
        }
        if bi == n || best < 1.0e-10f64 * scale { ret (0usize, vo, no, oo, al, c) }
        // orthonormal residual of the chosen point
        var j = 0usize
        while j < d {
            rs[j] = p[bi * d + j] - p[j]
            j += 1usize
        }
        var pass = 0usize
        while pass < 2usize {
            var b = 0usize
            while b < nb {
                var dp = 0.0f64
                j = 0usize
                while j < d {
                    dp += rs[j] * bs[b * d + j]
                    j += 1usize
                }
                j = 0usize
                while j < d {
                    rs[j] = rs[j] - dp * bs[b * d + j]
                    j += 1usize
                }
                b += 1usize
            }
            pass += 1usize
        }
        var len = 0.0f64
        j = 0usize
        while j < d {
            len += rs[j] * rs[j]
            j += 1usize
        }
        len = math.sqrt[f64](len)
        j = 0usize
        while j < d {
            bs[nb * d + j] = rs[j] / len
            j += 1usize
        }
        nb += 1usize
        ch[k] = bi
        used[bi] = 1usize
        k += 1usize
    }
    var j = 0usize
    while j < d {
        c[j] = 0.0f64
        j += 1usize
    }
    k = 0usize
    while k <= d {
        j = 0usize
        while j < d {
            c[j] += p[ch[k] * d + j] / f64(d + 1usize)
            j += 1usize
        }
        k += 1usize
    }
    // the chosen indices sorted
    i = 1usize
    while i <= d {
        let v = ch[i]
        var q = i
        while q > 0usize && ch[q - 1usize] > v {
            ch[q] = ch[q - 1usize]
            q -= 1usize
        }
        ch[q] = v
        i += 1usize
    }
    var ns = 0usize
    var om = 0usize
    while om <= d {
        var t = 0usize
        k = 0usize
        while k <= d {
            if k != om {
                vo[ns * d + t] = ch[k]
                t += 1usize
            }
            k += 1usize
        }
        if !make_facet(p, d, ns, vo, no, oo, c, mat) { ret (0usize, vo, no, oo, al, c) }
        al[ns] = 1usize
        ns += 1usize
        om += 1usize
    }
    var nfr = 0usize
    let eps = 1.0e-10f64 * scale
    var pt = 0usize
    while pt < n {
        if used[pt] == 0usize {
            var nv = 0usize
            var s = 0usize
            while s < ns {
                if al[s] == 1usize {
                    var dist = 0.0f64 - oo[s]
                    j = 0usize
                    while j < d {
                        dist += no[s * d + j] * p[pt * d + j]
                        j += 1usize
                    }
                    if dist > eps {
                        vis[nv] = s
                        nv += 1usize
                    }
                }
                s += 1usize
            }
            if nv > 0usize {
                var nr = 0usize
                var v = 0usize
                while v < nv {
                    j = 0usize
                    while j < d {
                        rf[nr] = vis[v]
                        rj[nr] = j
                        mt[nr] = 0usize
                        nr += 1usize
                        j += 1usize
                    }
                    v += 1usize
                }
                var r1 = 0usize
                while r1 < nr {
                    if mt[r1] == 0usize {
                        var r2 = r1 + 1usize
                        while r2 < nr {
                            if mt[r2] == 0usize && same_ridge(vo, d, rf[r1], rj[r1], rf[r2], rj[r2]) {
                                mt[r1] = 1usize
                                mt[r2] = 1usize
                                r2 = nr
                            }
                            r2 += 1usize
                        }
                    }
                    r1 += 1usize
                }
                // new facets: every horizon ridge with the point, vertices sorted
                var nn = 0usize
                r1 = 0usize
                while r1 < nr {
                    if mt[r1] == 0usize {
                        var t = 0usize
                        var put = false
                        k = 0usize
                        while k < d {
                            if k != rj[r1] {
                                let w = vo[rf[r1] * d + k]
                                if !put && pt < w {
                                    nw[nn * d + t] = pt
                                    t += 1usize
                                    put = true
                                }
                                nw[nn * d + t] = w
                                t += 1usize
                            }
                            k += 1usize
                        }
                        if !put { nw[nn * d + t] = pt }
                        nn += 1usize
                    }
                    r1 += 1usize
                }
                v = 0usize
                while v < nv {
                    al[vis[v]] = 0usize
                    fr[nfr] = vis[v]
                    nfr += 1usize
                    v += 1usize
                }
                var q = 0usize
                while q < nn {
                    var slot = 0usize
                    if nfr > 0usize {
                        nfr -= 1usize
                        slot = fr[nfr]
                    } else {
                        slot = ns
                        ns += 1usize
                        if ns >= cap { ret (0usize, vo, no, oo, al, c) }
                    }
                    j = 0usize
                    while j < d {
                        vo[slot * d + j] = nw[q * d + j]
                        j += 1usize
                    }
                    if !make_facet(p, d, slot, vo, no, oo, c, mat) { ret (0usize, vo, no, oo, al, c) }
                    al[slot] = 1usize
                    q += 1usize
                }
            }
        }
        pt += 1usize
    }
    ret (ns, vo, no, oo, al, c)
}

fn fact(k: usize) -> f64 {
    var f = 1.0f64
    var i = 2usize
    while i <= k {
        f = f * f64(i)
        i += 1usize
    }
    ret f
}

// |det| of the d vertices vs of a facet taken relative to the point c, over d!
fn cone_volume(p: []const f64, vs: []const usize, d: usize, c: []const f64, mat: []f64) -> f64 {
    var r = 0usize
    while r < d {
        var j = 0usize
        while j < d {
            mat[r * d + j] = p[vs[r] * d + j] - c[j]
            j += 1usize
        }
        r += 1usize
    }
    ret math.abs[f64](det_lu(mat[0usize..d * d], d)) / fact(d)
}

// (d-1)-volume of the facet with vertices vs: sqrt(det Gram) / (d-1)!
fn facet_area(p: []const f64, vs: []const usize, d: usize, mat: []f64, gram: []f64) -> f64 {
    let k = d - 1usize
    var r = 0usize
    while r < k {
        var j = 0usize
        while j < d {
            mat[r * d + j] = p[vs[r + 1usize] * d + j] - p[vs[0usize] * d + j]
            j += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < k {
        var s = 0usize
        while s < k {
            var dp = 0.0f64
            var j = 0usize
            while j < d {
                dp += mat[r * d + j] * mat[s * d + j]
                j += 1usize
            }
            gram[r * k + s] = dp
            s += 1usize
        }
        r += 1usize
    }
    let g = det_lu(gram[0usize..k * k], k)
    if g < 0.0f64 { ret 0.0f64 }
    ret math.sqrt[f64](g) / fact(k)
}

// convhulln(p, "FA") on n points in d dimensions: out = facets, boundary measure (perimeter, area, ...), enclosed measure (area, volume, ...); NaN when the points do not span d dimensions
fn convhull(a: *mem.Arena, p: []const f64, n: usize, d: usize, out: []f64) {
    let (ns, vo, no, oo, al, c) = hull_core(a, p, n, d)
    out[0usize] = nan()
    out[1usize] = nan()
    out[2usize] = nan()
    if ns == 0usize { ret }
    let (mat, e1) = mem.alloc[f64](a, d * d)
    let (gram, e2) = mem.alloc[f64](a, d * d)
    if e1 != ok || e2 != ok { ret }
    var cnt = 0.0f64
    var area = 0.0f64
    var vol = 0.0f64
    var s = 0usize
    while s < ns {
        if al[s] == 1usize {
            cnt += 1.0f64
            area += facet_area(p, vo[s * d..s * d + d], d, mat, gram)
            vol += cone_volume(p, vo[s * d..s * d + d], d, c, mat)
        }
        s += 1usize
    }
    out[0usize] = cnt
    out[1usize] = area
    out[2usize] = vol
}

// delaunayn(p) on n points in d dimensions through the lower hull of the paraboloid lift. out = simplices, total volume, hash of the sorted 1-based vertex tuples (sum of sum_k (v_k+1) 41^k), sum of the circumcentre coordinates, sum of their squares. NaN when the points do not span d dimensions.
fn delaunay(a: *mem.Arena, p: []const f64, n: usize, d: usize, out: []f64) {
    out[0usize] = nan()
    out[1usize] = nan()
    out[2usize] = nan()
    out[3usize] = nan()
    out[4usize] = nan()
    let dd = d + 1usize
    let (lp, e0) = mem.alloc[f64](a, n * dd)
    let (mat, e1) = mem.alloc[f64](a, dd * dd)
    let (rhs, e2) = mem.alloc[f64](a, dd)
    if e0 != ok || e1 != ok || e2 != ok { ret }
    var i = 0usize
    while i < n {
        var q = 0.0f64
        var j = 0usize
        while j < d {
            lp[i * dd + j] = p[i * d + j]
            q += p[i * d + j] * p[i * d + j]
            j += 1usize
        }
        lp[i * dd + d] = q
        i += 1usize
    }
    let (ns, vo, no, oo, al, c) = hull_core(a, lp, n, dd)
    if ns == 0usize { ret }
    var cnt = 0.0f64
    var vol = 0.0f64
    var hash = 0.0f64
    var csum = 0.0f64
    var csq = 0.0f64
    var s = 0usize
    while s < ns {
        if al[s] == 1usize && no[s * dd + d] < 0.0f64 - 1.0e-9f64 {
            cnt += 1.0f64
            var wgt = 1.0f64
            var k = 0usize
            while k < dd {
                hash += f64(vo[s * dd + k] + 1usize) * wgt
                wgt = wgt * 41.0f64
                k += 1usize
            }
            // volume: det of the edges from the first vertex over d!
            var r = 0usize
            while r < d {
                var j = 0usize
                while j < d {
                    mat[r * d + j] = p[vo[s * dd + r + 1usize] * d + j] - p[vo[s * dd] * d + j]
                    j += 1usize
                }
                r += 1usize
            }
            vol += math.abs[f64](det_lu(mat[0usize..d * d], d)) / fact(d)
            // circumcentre: 2 (p_k - p_0) x = |p_k|^2 - |p_0|^2
            var sq0 = 0.0f64
            var j = 0usize
            while j < d {
                sq0 += p[vo[s * dd] * d + j] * p[vo[s * dd] * d + j]
                j += 1usize
            }
            r = 0usize
            while r < d {
                var sqk = 0.0f64
                j = 0usize
                while j < d {
                    let pk = p[vo[s * dd + r + 1usize] * d + j]
                    mat[r * d + j] = 2.0f64 * (pk - p[vo[s * dd] * d + j])
                    sqk += pk * pk
                    j += 1usize
                }
                rhs[r] = sqk - sq0
                r += 1usize
            }
            if solve_lu(mat[0usize..d * d], rhs[0usize..d], d) {
                j = 0usize
                while j < d {
                    csum += rhs[j]
                    csq += rhs[j] * rhs[j]
                    j += 1usize
                }
            }
        }
        s += 1usize
    }
    out[0usize] = cnt
    out[1usize] = vol
    out[2usize] = hash
    out[3usize] = csum
    out[4usize] = csq
}

// barycentric coordinates of the point x in the simplex whose d+1 vertices are the rows of sx (d+1 by d): beta = (x - v_d) inv(V - v_d), then 1 - sum. false for a degenerate simplex. mat and rhs are scratch of d*d and d.
fn bary(sx: []const f64, d: usize, x: []const f64, mat: []f64, rhs: []f64, out: []f64) -> bool {
    var r = 0usize
    while r < d {
        var j = 0usize
        while j < d {
            mat[j * d + r] = sx[r * d + j] - sx[d * d + j]
            j += 1usize
        }
        rhs[r] = 0.0f64
        r += 1usize
    }
    var j = 0usize
    while j < d {
        rhs[j] = x[j] - sx[d * d + j]
        j += 1usize
    }
    // beta X1 = (x - v_d)  =>  X1^T beta^T = (x - v_d)^T
    if !solve_lu(mat[0usize..d * d], rhs[0usize..d], d) { ret false }
    var s = 0.0f64
    j = 0usize
    while j < d {
        out[j] = rhs[j]
        s += rhs[j]
        j += 1usize
    }
    out[d] = 1.0f64 - s
    ret true
}

// tsearchn(p, t, x): the 1-based index of the first simplex of t (nt by d+1, 1-based vertex indices) holding x with every barycentric coordinate at least -1e-12, 0 when none; the coordinates go to out (d+1). tsearch is the case d = 2.
fn tsearchn(a: *mem.Arena, p: []const f64, d: usize, t: []const f64, nt: usize, x: []const f64, out: []f64) -> usize {
    let (sx, e1) = mem.alloc[f64](a, (d + 1usize) * d)
    let (mat, e2) = mem.alloc[f64](a, d * d)
    let (rhs, e3) = mem.alloc[f64](a, d)
    let (bb, e4) = mem.alloc[f64](a, d + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0usize }
    var s = 0usize
    while s < nt {
        var k = 0usize
        while k <= d {
            let v = usize(t[s * (d + 1usize) + k]) - 1usize
            var j = 0usize
            while j < d {
                sx[k * d + j] = p[v * d + j]
                j += 1usize
            }
            k += 1usize
        }
        if bary(sx, d, x, mat, rhs, bb) {
            var inside = true
            k = 0usize
            while k <= d {
                if bb[k] < 0.0f64 - 1.0e-12f64 { inside = false }
                k += 1usize
            }
            if inside {
                k = 0usize
                while k <= d {
                    out[k] = bb[k]
                    k += 1usize
                }
                ret s + 1usize
            }
        }
        s += 1usize
    }
    ret 0usize
}

// inhulln(convhulln(p), q): 1 when q lies inside the hull of the n points p (no facet plane has it strictly outside), else 0
fn inhulln(a: *mem.Arena, p: []const f64, n: usize, d: usize, q: []const f64) -> f64 {
    let (ns, vo, no, oo, al, c) = hull_core(a, p, n, d)
    if ns == 0usize { ret nan() }
    var s = 0usize
    while s < ns {
        if al[s] == 1usize {
            var dist = 0.0f64 - oo[s]
            var j = 0usize
            while j < d {
                dist += no[s * d + j] * q[j]
                j += 1usize
            }
            if dist > 0.0f64 { ret 0.0f64 }
        }
        s += 1usize
    }
    ret 1.0f64
}

// the k-volume of the bounded polytope {x : A x <= b} (A is m by k, row-major) about the interior point y0, with its boundary measure and vertex count into out: vertices come from the dual hull of A_j / (b_j - A_j y0), and the volume is the cone sum (1/k) sum_j dist_j vol_{k-1}(F_j) over the facets F_j, each one a polytope of the hyperplane j taken in k-1 coordinates (mean of the vertices on it as its interior point). out is NaN on failure.
fn poly_measure(a: *mem.Arena, am: []const f64, b: []const f64, m: usize, k: usize, y0: []const f64, out: []f64) {
    out[0usize] = nan()
    out[1usize] = nan()
    out[2usize] = nan()
    if k == 1usize {
        var lo = 0.0f64 - 1.0e300f64
        var hi = 1.0e300f64
        var j = 0usize
        while j < m {
            if am[j] > 1.0e-300f64 && b[j] / am[j] < hi { hi = b[j] / am[j] }
            if am[j] < 0.0f64 - 1.0e-300f64 && b[j] / am[j] > lo { lo = b[j] / am[j] }
            j += 1usize
        }
        out[0usize] = hi - lo
        out[1usize] = 2.0f64
        out[2usize] = 2.0f64
        ret
    }
    let (q, e1) = mem.alloc[f64](a, m * k)
    let (mat, e2) = mem.alloc[f64](a, k * k)
    let (rhs, e3) = mem.alloc[f64](a, k)
    let (used, e4) = mem.alloc[usize](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret }
    var j = 0usize
    while j < m {
        var hh = b[j]
        var t = 0usize
        while t < k {
            hh = hh - am[j * k + t] * y0[t]
            t += 1usize
        }
        if hh <= 1.0e-12f64 {
            out[0usize] = 0.0f64
            out[1usize] = 0.0f64
            out[2usize] = 0.0f64
            ret
        }
        t = 0usize
        while t < k {
            q[j * k + t] = am[j * k + t] / hh
            t += 1usize
        }
        used[j] = 0usize
        j += 1usize
    }
    let (ns, vo, no, oo, al, cc) = hull_core(a, q, m, k)
    if ns == 0usize { ret }
    var cap = 0usize
    var s = 0usize
    while s < ns {
        if al[s] == 1usize { cap += 1usize }
        s += 1usize
    }
    let (vs, e5) = mem.alloc[f64](a, cap * k)
    if e5 != ok { ret }
    var nv = 0usize
    s = 0usize
    while s < ns {
        if al[s] == 1usize {
            var r = 0usize
            while r < k {
                used[vo[s * k + r]] = 1usize
                var t = 0usize
                while t < k {
                    mat[r * k + t] = q[vo[s * k + r] * k + t]
                    t += 1usize
                }
                rhs[r] = 1.0f64
                r += 1usize
            }
            if !solve_lu(mat[0usize..k * k], rhs[0usize..k], k) { ret }
            var t = 0usize
            while t < k {
                vs[nv * k + t] = rhs[t] + y0[t]
                t += 1usize
            }
            var dup = false
            var u = 0usize
            while u < nv && !dup {
                var same = true
                t = 0usize
                while t < k {
                    if math.abs[f64](vs[u * k + t] - vs[nv * k + t]) > 1.0e-8f64 * (1.0f64 + math.abs[f64](vs[u * k + t])) { same = false }
                    t += 1usize
                }
                if same { dup = true }
                u += 1usize
            }
            if !dup { nv += 1usize }
        }
        s += 1usize
    }
    var vol = 0.0f64
    var surf = 0.0f64
    j = 0usize
    while j < m {
        if used[j] == 1usize {
            var len = 0.0f64
            var t = 0usize
            while t < k {
                len += am[j * k + t] * am[j * k + t]
                t += 1usize
            }
            len = math.sqrt[f64](len)
            // vertices on the plane j
            var cnt = 0usize
            var xc: [8]f64 = zero
            var u = 0usize
            while u < nv {
                var dist = 0.0f64 - b[j]
                t = 0usize
                while t < k {
                    dist += am[j * k + t] * vs[u * k + t]
                    t += 1usize
                }
                if math.abs[f64](dist) / len < 1.0e-8f64 * (1.0f64 + math.abs[f64](b[j]) / len) {
                    cnt += 1usize
                    t = 0usize
                    while t < k {
                        xc[t] += vs[u * k + t]
                        t += 1usize
                    }
                }
                u += 1usize
            }
            if cnt >= k {
                t = 0usize
                while t < k {
                    xc[t] = xc[t] / f64(cnt)
                    t += 1usize
                }
                // orthonormal basis of the hyperplane: the unit vectors but the one with the largest component of the normal, taken orthogonal to the normal
                var nn: [8]f64 = zero
                var big = 0usize
                t = 0usize
                while t < k {
                    nn[t] = am[j * k + t] / len
                    if math.abs[f64](nn[t]) > math.abs[f64](nn[big]) { big = t }
                    t += 1usize
                }
                let start = mem.mark(a)
                let (bas, e6) = mem.alloc[f64](a, k * k)
                let (a2, e7) = mem.alloc[f64](a, m * k)
                let (b2, e8) = mem.alloc[f64](a, m)
                let (z0, e9) = mem.alloc[f64](a, k)
                if e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret }
                var nb = 0usize
                var e = 0usize
                while e < k {
                    if e != big {
                        var w: [8]f64 = zero
                        w[e] = 1.0f64
                        var pass = 0usize
                        while pass < 2usize {
                            var dp = 0.0f64
                            t = 0usize
                            while t < k {
                                dp += w[t] * nn[t]
                                t += 1usize
                            }
                            t = 0usize
                            while t < k {
                                w[t] = w[t] - dp * nn[t]
                                t += 1usize
                            }
                            var c2 = 0usize
                            while c2 < nb {
                                dp = 0.0f64
                                t = 0usize
                                while t < k {
                                    dp += w[t] * bas[c2 * k + t]
                                    t += 1usize
                                }
                                t = 0usize
                                while t < k {
                                    w[t] = w[t] - dp * bas[c2 * k + t]
                                    t += 1usize
                                }
                                c2 += 1usize
                            }
                            pass += 1usize
                        }
                        var wl = 0.0f64
                        t = 0usize
                        while t < k {
                            wl += w[t] * w[t]
                            t += 1usize
                        }
                        wl = math.sqrt[f64](wl)
                        t = 0usize
                        while t < k {
                            bas[nb * k + t] = w[t] / wl
                            t += 1usize
                        }
                        nb += 1usize
                    }
                    e += 1usize
                }
                // a point on the plane and the restricted constraints of the other facets
                var x0: [8]f64 = zero
                t = 0usize
                while t < k {
                    x0[t] = am[j * k + t] * b[j] / (len * len)
                    t += 1usize
                }
                var m2 = 0usize
                var l = 0usize
                while l < m {
                    if l != j && used[l] == 1usize {
                        var bl = b[l]
                        t = 0usize
                        while t < k {
                            bl = bl - am[l * k + t] * x0[t]
                            t += 1usize
                        }
                        var an = 0.0f64
                        var c2 = 0usize
                        while c2 < k - 1usize {
                            var dp = 0.0f64
                            t = 0usize
                            while t < k {
                                dp += bas[c2 * k + t] * am[l * k + t]
                                t += 1usize
                            }
                            a2[m2 * (k - 1usize) + c2] = dp
                            an += dp * dp
                            c2 += 1usize
                        }
                        if an > 1.0e-18f64 {
                            b2[m2] = bl
                            m2 += 1usize
                        }
                    }
                    l += 1usize
                }
                var c2 = 0usize
                while c2 < k - 1usize {
                    var dp = 0.0f64
                    t = 0usize
                    while t < k {
                        dp += bas[c2 * k + t] * (xc[t] - x0[t])
                        t += 1usize
                    }
                    z0[c2] = dp
                    c2 += 1usize
                }
                var sub: [3]f64 = zero
                poly_measure(a, a2[0usize..m2 * (k - 1usize)], b2[0usize..m2], m2, k - 1usize, z0[0usize..k - 1usize], sub[0usize..3usize])
                if sub[0usize] != sub[0usize] { ret }
                var hj = b[j]
                t = 0usize
                while t < k {
                    hj = hj - am[j * k + t] * y0[t]
                    t += 1usize
                }
                vol += hj / len * sub[0usize] / f64(k)
                surf += sub[0usize]
                mem.reset(a, start)
            }
        }
        j += 1usize
    }
    out[0usize] = vol
    out[1usize] = surf
    out[2usize] = f64(nv)
}

// intersectn(p1, p2, fp = fp): the intersection of the two hulls, the facet planes of each about the feasible point fp. out = vertices, volume, boundary measure of the intersection polytope. NaN on failure.
fn intersect(a: *mem.Arena, p1: []const f64, n1: usize, p2: []const f64, n2: usize, d: usize, fp: []const f64, out: []f64) {
    out[0usize] = nan()
    out[1usize] = nan()
    out[2usize] = nan()
    let (s1, vo1, no1, oo1, al1, c1) = hull_core(a, p1, n1, d)
    let (s2, vo2, no2, oo2, al2, c2) = hull_core(a, p2, n2, d)
    if s1 == 0usize || s2 == 0usize { ret }
    let (am, e1) = mem.alloc[f64](a, (s1 + s2) * d)
    let (bm, e2) = mem.alloc[f64](a, s1 + s2)
    if e1 != ok || e2 != ok { ret }
    var m = 0usize
    var s = 0usize
    while s < s1 {
        if al1[s] == 1usize {
            var j = 0usize
            while j < d {
                am[m * d + j] = no1[s * d + j]
                j += 1usize
            }
            bm[m] = oo1[s]
            m += 1usize
        }
        s += 1usize
    }
    s = 0usize
    while s < s2 {
        if al2[s] == 1usize {
            var j = 0usize
            while j < d {
                am[m * d + j] = no2[s * d + j]
                j += 1usize
            }
            bm[m] = oo2[s]
            m += 1usize
        }
        s += 1usize
    }
    var res: [3]f64 = zero
    poly_measure(a, am[0usize..m * d], bm[0usize..m], m, d, fp, res[0usize..3usize])
    out[0usize] = res[2usize]
    out[1usize] = res[0usize]
    out[2usize] = res[1usize]
}

// surf.tri(p, t) for a tetrahedral mesh (t is nt by 4, 1-based): the boundary triangles, each as the row R returns it (first vertex the smallest, wound so the normal points away from the fourth vertex), answered as count in out[0] and the sum of 1-based rows read in base 100 (a + 100 b + 10000 c) in out[1]
fn surf_tri(a: *mem.Arena, p: []const f64, t: []const f64, nt: usize, out: []f64) {
    out[0usize] = nan()
    out[1usize] = nan()
    let (fk, e1) = mem.alloc[usize](a, nt * 4usize * 5usize)
    if e1 != ok { ret }
    // each face: sorted a<b<c, fourth vertex
    var nf = 0usize
    var s = 0usize
    while s < nt {
        var om = 0usize
        while om < 4usize {
            var v: [3]usize = zero
            var k = 0usize
            var w = 0usize
            while k < 4usize {
                if k != om {
                    v[w] = usize(t[s * 4usize + k])
                    w += 1usize
                }
                k += 1usize
            }
            var x = 0usize
            while x < 3usize {
                var y = x + 1usize
                while y < 3usize {
                    if v[y] < v[x] {
                        let tmp = v[x]
                        v[x] = v[y]
                        v[y] = tmp
                    }
                    y += 1usize
                }
                x += 1usize
            }
            fk[nf * 5usize] = v[0usize]
            fk[nf * 5usize + 1usize] = v[1usize]
            fk[nf * 5usize + 2usize] = v[2usize]
            // R builds node4 with rbind of vectors, a 4 by nt matrix read as a vector, so the "fourth vertex" of face row r is t[r div 4, 4 - r mod 4]; replicated
            let r = (3usize - om) * nt + s
            fk[nf * 5usize + 3usize] = usize(t[(r / 4usize) * 4usize + 3usize - r % 4usize])
            fk[nf * 5usize + 4usize] = 1usize
            nf += 1usize
            om += 1usize
        }
        s += 1usize
    }
    var cnt = 0.0f64
    var hash = 0.0f64
    var i = 0usize
    while i < nf {
        var once = true
        var j = 0usize
        while j < nf {
            if j != i && fk[j * 5usize] == fk[i * 5usize] && fk[j * 5usize + 1usize] == fk[i * 5usize + 1usize] && fk[j * 5usize + 2usize] == fk[i * 5usize + 2usize] { once = false }
            j += 1usize
        }
        if once {
            let a0 = fk[i * 5usize] - 1usize
            var b0 = fk[i * 5usize + 1usize] - 1usize
            var c0 = fk[i * 5usize + 2usize] - 1usize
            let n4 = fk[i * 5usize + 3usize] - 1usize
            var v1: [3]f64 = zero
            var v2: [3]f64 = zero
            var v3: [3]f64 = zero
            var q = 0usize
            while q < 3usize {
                v1[q] = p[b0 * 3usize + q] - p[a0 * 3usize + q]
                v2[q] = p[c0 * 3usize + q] - p[a0 * 3usize + q]
                v3[q] = p[n4 * 3usize + q] - p[a0 * 3usize + q]
                q += 1usize
            }
            let ta = (v1[1usize] * v2[2usize] - v1[2usize] * v2[1usize]) * v3[0usize]
            let tb = (v1[2usize] * v2[0usize] - v1[0usize] * v2[2usize]) * v3[1usize]
            let tc = (v1[0usize] * v2[1usize] - v1[1usize] * v2[0usize]) * v3[2usize]
            // R sums the three products in long double; a quirk node4 can make them cancel exactly, so the sign is taken from the exact two-sum pair rather than a rounded double sum
            let h1 = ta + tb
            let bb = h1 - ta
            let l1 = (ta - (h1 - bb)) + (tb - bb)
            let h2 = h1 + tc
            let b2 = h2 - h1
            let l2 = (h1 - (h2 - b2)) + (tc - b2)
            let trip = h2 + (l2 + l1)
            if trip > 0.0f64 {
                let tmp = b0
                b0 = c0
                c0 = tmp
            }
            cnt += 1.0f64
            hash += f64(a0 + 1usize) + 100.0f64 * f64(b0 + 1usize) + 10000.0f64 * f64(c0 + 1usize)
        }
        i += 1usize
    }
    out[0usize] = cnt
    out[1usize] = hash
}

// dot(x, y, dsel) for m by n row-major matrices: entry k of the sums down the columns (dsel 1, k < n) or along the rows (dsel 2, k < m)
fn dot(x: []const f64, y: []const f64, m: usize, n: usize, dsel: usize, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    if dsel == 1usize {
        while i < m {
            s += x[i * n + k] * y[i * n + k]
            i += 1usize
        }
    } else {
        while i < n {
            s += x[k * n + i] * y[k * n + i]
            i += 1usize
        }
    }
    ret s
}
