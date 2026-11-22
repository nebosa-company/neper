// R spdep neighbours, weights and global and local tests on dense n by n row-major matrices (adj[i * n + j] is 1 when j is a neighbour of i): knn2nb, dnearneigh, tri2nb, nb2listw, moran.test, moran.mc, geary.test, globalG.test, localmoran, localG, joincount.test.
//
// Not here: poly2nb, joincount.multi, the quadrant attributes, na.action subsets; the regression models are in e.algo.stat.spdepreg.

use e.algo.geom as geom
use e.algo.rand.r as rr
use e.math
use e.math.dist as dist
use e.mem

// knn2nb(knearneigh(co, k)); co holds x then y per point. Ties go to the lower index.
fn knn(a: *mem.Arena, co: []const f64, n: usize, k: usize, adj: []f64) -> err {
    let (d, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < n * n {
        adj[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = co[2usize * i] - co[2usize * j]
            let dy = co[2usize * i + 1usize] - co[2usize * j + 1usize]
            d[j] = dx * dx + dy * dy
            j += 1usize
        }
        d[i] = 1.0e300f64
        var t = 0usize
        while t < k {
            var best = 0usize
            j = 1usize
            while j < n {
                if d[j] < d[best] { best = j }
                j += 1usize
            }
            adj[i * n + best] = 1.0f64
            d[best] = 1.0e300f64
            t += 1usize
        }
        i += 1usize
    }
    ret ok
}

// dnearneigh(co, d1, d2): d1 < distance <= d2, self excluded.
fn dnear(co: []const f64, n: usize, d1: f64, d2: f64, adj: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let dx = co[2usize * i] - co[2usize * j]
            let dy = co[2usize * i + 1usize] - co[2usize * j + 1usize]
            let dd = math.sqrt[f64](dx * dx + dy * dy)
            adj[i * n + j] = 0.0f64
            if i != j && dd > d1 && dd <= d2 { adj[i * n + j] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
}

// tri2nb(co): the edges of the Delaunay triangulation, both ways.
fn tri(a: *mem.Arena, co: []const f64, n: usize, adj: []f64) -> err {
    let (pts, e1) = mem.alloc[geom.Point](a, n)
    if e1 != ok { ret e1 }
    let (tris, e2) = mem.alloc[usize](a, 6usize * n)
    if e2 != ok { ret e2 }
    let (scr, e3) = mem.alloc[usize](a, 6usize * n)
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n {
        pts[i] = geom.Point { x: co[2usize * i], y: co[2usize * i + 1usize] }
        i += 1usize
    }
    i = 0usize
    while i < n * n {
        adj[i] = 0.0f64
        i += 1usize
    }
    let (cnt, e4) = geom.delaunay(pts, tris, scr)
    if e4 != ok { ret e4 }
    var t = 0usize
    while t < cnt {
        let p = tris[t]
        let q = tris[t + 1usize]
        let r = tris[t + 2usize]
        if p < n && q < n && r < n {
            adj[p * n + q] = 1.0f64
            adj[q * n + p] = 1.0f64
            adj[q * n + r] = 1.0f64
            adj[r * n + q] = 1.0f64
            adj[p * n + r] = 1.0f64
            adj[r * n + p] = 1.0f64
        }
        t += 3usize
    }
    ret ok
}

// nb2listw(nb, style = ...) as a dense matrix; style 0 W, 1 B, 2 C, 3 U, 4 S. Rows without neighbours stay zero (zero.policy).
fn listw(adj: []const f64, n: usize, style: usize, w: []f64) {
    var eff = 0.0f64
    var total = 0.0f64
    var big_q = 0.0f64
    var i = 0usize
    while i < n {
        var c = 0.0f64
        var j = 0usize
        while j < n {
            c += adj[i * n + j]
            j += 1usize
        }
        if c > 0.0f64 { eff += 1.0f64 }
        total += c
        let q = math.sqrt[f64](c)
        if q > 0.0f64 {
            j = 0usize
            while j < n {
                big_q += adj[i * n + j] / q
                j += 1usize
            }
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var d = 0.0f64
        var j = 0usize
        while j < n {
            d += adj[i * n + j]
            j += 1usize
        }
        let q = math.sqrt[f64](d)
        j = 0usize
        while j < n {
            let b = adj[i * n + j]
            var v = b
            if style == 0usize {
                v = 0.0f64
                if d > 0.0f64 { v = (1.0f64 / d) * b }
            }
            if style == 2usize { v = (eff / total) * b }
            if style == 3usize { v = (1.0f64 / total) * b }
            if style == 4usize {
                v = 0.0f64
                if q > 0.0f64 { v = (eff / big_q) * ((1.0f64 / q) * b) }
            }
            w[i * n + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

// spweights.constants: out = n (isolates dropped), S0, S1, S2
fn wconst(w: []const f64, n: usize, out: []f64) {
    var eff = 0.0f64
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var i = 0usize
    while i < n {
        var ri = 0.0f64
        var ci = 0.0f64
        var card = 0usize
        var j = 0usize
        while j < n {
            let wij = w[i * n + j]
            let wji = w[j * n + i]
            if wij != 0.0f64 { card += 1usize }
            s0 += wij
            s1 += wij * wij + wij * wji
            ri += wij
            ci += wji
            j += 1usize
        }
        if card > 0usize { eff += 1.0f64 }
        s2 += (ri + ci) * (ri + ci)
        i += 1usize
    }
    out[0usize] = eff
    out[1usize] = s0
    out[2usize] = s1
    out[3usize] = s2
}

// p value of a standard deviate: alt 0 greater, 1 less, 2 two.sided
fn pval(z: f64, alt: usize) -> f64 {
    if alt == 0usize { ret dist.pnorm(z, 0.0f64, 1.0f64, false, false) }
    if alt == 1usize { ret dist.pnorm(z, 0.0f64, 1.0f64, true, false) }
    ret 2.0f64 * dist.pnorm(math.abs[f64](z), 0.0f64, 1.0f64, false, false)
}

// moran(x, listw, n, S0): the statistic, and the kurtosis taken over all of x
fn moran_i(x: []const f64, w: []const f64, n: usize, neff: f64, s0: f64) -> (f64, f64) {
    let nf = f64(n)
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / nf
    var zz = 0.0f64
    var z4 = 0.0f64
    var cr = 0.0f64
    i = 0usize
    while i < n {
        let zi = x[i] - mean
        zz += zi * zi
        z4 += zi * zi * zi * zi
        var lz = 0.0f64
        var j = 0usize
        while j < n {
            lz += w[i * n + j] * (x[j] - mean)
            j += 1usize
        }
        cr += zi * lz
        i += 1usize
    }
    ret ((neff / s0) * (cr / zz), (nf * z4) / (zz * zz))
}

// moran.test: out = I, E, Var, z, p. randomisation, rank, drop_ei2 are 0/1; alt as in pval
fn moran_test(x: []const f64, w: []const f64, n: usize, randomisation: usize, rank: usize, drop_ei2: usize, alt: usize, out: []f64) {
    var c: [4]f64 = zero
    wconst(w, n, c[0usize..4usize])
    let nn = c[0usize]
    let s0 = c[1usize]
    let s1 = c[2usize]
    let s2 = c[3usize]
    let n1 = nn - 1.0f64
    let n2 = nn - 2.0f64
    let n3 = nn - 3.0f64
    let nsq = nn * nn
    let s02 = s0 * s0
    let (ii, k0) = moran_i(x, w, n, nn, s0)
    var k = k0
    if rank == 1usize { k = (3.0f64 * (3.0f64 * nsq - 7.0f64)) / (5.0f64 * (nsq - 1.0f64)) }
    let ei = 0.0f64 - 1.0f64 / n1
    var vi = 0.0f64
    if randomisation == 1usize {
        let v0 = nn * (s1 * (nsq - 3.0f64 * nn + 3.0f64) - nn * s2 + 3.0f64 * s02)
        let tmp = k * (s1 * (nsq - nn) - 2.0f64 * nn * s2 + 6.0f64 * s02)
        vi = (v0 - tmp) / (n1 * n2 * n3 * s02)
    } else {
        vi = (nsq * s1 - nn * s2 + 3.0f64 * s02) / (s02 * (nsq - 1.0f64))
    }
    if drop_ei2 == 0usize { vi = vi - ei * ei }
    let z = (ii - ei) / math.sqrt[f64](vi)
    out[0usize] = ii
    out[1usize] = ei
    out[2usize] = vi
    out[3usize] = z
    out[4usize] = pval(z, alt)
}

// geary.test: out = C, E, Var, z, p; alt as in pval
fn geary_test(x: []const f64, w: []const f64, n: usize, randomisation: usize, alt: usize, out: []f64) {
    var c: [4]f64 = zero
    wconst(w, n, c[0usize..4usize])
    let nn = c[0usize]
    let s0 = c[1usize]
    let s1 = c[2usize]
    let s2 = c[3usize]
    let n1 = nn - 1.0f64
    let n2 = nn - 2.0f64
    let n3 = nn - 3.0f64
    let nsq = nn * nn
    let s02 = s0 * s0
    let nf = f64(n)
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / nf
    var zz = 0.0f64
    var z4 = 0.0f64
    var diff = 0.0f64
    i = 0usize
    while i < n {
        let zi = x[i] - mean
        zz += zi * zi
        z4 += zi * zi * zi * zi
        var j = 0usize
        while j < n {
            diff += w[i * n + j] * (x[i] - x[j]) * (x[i] - x[j])
            j += 1usize
        }
        i += 1usize
    }
    let k = (nn * z4) / (zz * zz)
    let cg = (n1 / (2.0f64 * s0)) * (diff / zz)
    var vc = 0.0f64
    if randomisation == 1usize {
        // R mixes the full count nf with the isolate-adjusted nn here, as geary.test does
        vc = n1 * s1 * (nsq - 3.0f64 * nf + 3.0f64 - k * n1)
        vc = vc - 0.25f64 * (n1 * s2 * (nsq + 3.0f64 * nf - 6.0f64 - k * (nsq - nf + 2.0f64)))
        vc = vc + s02 * (nsq - 3.0f64 - k * (n1 * n1))
        vc = vc / (nf * n2 * n3 * s02)
    } else {
        vc = ((2.0f64 * s1 + s2) * n1 - 4.0f64 * s02) / (2.0f64 * (nf + 1.0f64) * s02)
    }
    let z = (1.0f64 - cg) / math.sqrt[f64](vc)
    out[0usize] = cg
    out[1usize] = 1.0f64
    out[2usize] = vc
    out[3usize] = z
    out[4usize] = pval(z, alt)
}

// moran.mc with set.seed(seed): out[0..nsim] the simulated statistics, out[nsim] the observed one, out[nsim + 1] its rank, out[nsim + 2] the p value
fn moran_mc(a: *mem.Arena, x: []const f64, w: []const f64, n: usize, nsim: usize, seed: i64, alt: usize, out: []f64) -> err {
    var c: [4]f64 = zero
    wconst(w, n, c[0usize..4usize])
    var rng: rr.Rng = zero
    rr.seed(&rng, seed)
    let (xp, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var s = 0usize
    while s < nsim {
        let start = mem.mark(a)
        let (p, e2) = rr.sample_int(a, &rng, i64(n), i64(n), false)
        if e2 != ok { ret e2 }
        var i = 0usize
        while i < n {
            xp[i] = x[usize(p[i] - 1i64)]
            i += 1usize
        }
        let (ii, kk) = moran_i(xp, w, n, c[0usize], c[1usize])
        out[s] = ii
        mem.reset(a, start)
        s += 1usize
    }
    let (io, ko) = moran_i(x, w, n, c[0usize], c[1usize])
    out[nsim] = io
    var less = 0.0f64
    var eq = 0.0f64
    s = 0usize
    while s <= nsim {
        if out[s] < io { less += 1.0f64 }
        if out[s] == io { eq += 1.0f64 }
        s += 1usize
    }
    let xrank = less + (eq + 1.0f64) / 2.0f64
    var df = f64(nsim) - xrank
    if df < 0.0f64 { df = 0.0f64 }
    let ns1 = f64(nsim) + 1.0f64
    var pv = (df + 1.0f64) / ns1
    if alt == 1usize { pv = 1.0f64 - pv }
    if alt == 2usize {
        pv = 1.0f64 - 2.0f64 * math.abs[f64](xrank - ns1 / 2.0f64) / ns1
        if pv < 0.0f64 { pv = 0.0f64 }
    }
    out[nsim + 1usize] = xrank
    out[nsim + 2usize] = pv
    ret ok
}

// globalG.test: out = G, E, Var, z, p
fn global_g(x: []const f64, w: []const f64, n: usize, alt: usize, out: []f64) {
    var c: [4]f64 = zero
    wconst(w, n, c[0usize..4usize])
    let nn = c[0usize]
    let s0 = c[1usize]
    let s1 = c[2usize]
    let s2 = c[3usize]
    let n1 = nn - 1.0f64
    let n2 = nn - 2.0f64
    let n3 = nn - 3.0f64
    let nsq = nn * nn
    let s02 = s0 * s0
    var numer = 0.0f64
    var sx = 0.0f64
    var sx2 = 0.0f64
    var sx3 = 0.0f64
    var sx4 = 0.0f64
    var i = 0usize
    while i < n {
        var card = 0usize
        var lx = 0.0f64
        var j = 0usize
        while j < n {
            lx += w[i * n + j] * x[j]
            if w[i * n + j] != 0.0f64 { card += 1usize }
            j += 1usize
        }
        numer += x[i] * lx
        if card > 0usize {
            sx += x[i]
            sx2 += x[i] * x[i]
            sx3 += x[i] * x[i] * x[i]
            sx4 += x[i] * x[i] * x[i] * x[i]
        }
        i += 1usize
    }
    let g = numer / (sx * sx - sx2)
    let eg = s0 / (nn * n1)
    let b0 = (nsq - 3.0f64 * nn + 3.0f64) * s1 - nn * s2 + 3.0f64 * s02
    let b1 = 0.0f64 - ((nsq - nn) * s1 - 2.0f64 * nn * s2 + 6.0f64 * s02)
    let b2 = 0.0f64 - (2.0f64 * nn * s1 - (nn + 3.0f64) * s2 + 6.0f64 * s02)
    let b3 = 4.0f64 * n1 * s1 - 2.0f64 * (nn + 1.0f64) * s2 + 8.0f64 * s02
    let b4 = s1 - s2 + s02
    let dd = sx * sx - sx2
    let vg = (b0 * (sx2 * sx2) + b1 * sx4 + b2 * (sx * sx) * sx2 + b3 * sx * sx3 + b4 * (sx * sx * sx * sx)) / ((dd * dd) * nn * n1 * n2 * n3) - eg * eg
    let z = (g - eg) / math.sqrt[f64](vg)
    out[0usize] = g
    out[1usize] = eg
    out[2usize] = vg
    out[3usize] = z
    out[4usize] = pval(z, alt)
}

// localmoran: out is n by 5 (Ii, E.Ii, Var.Ii, Z.Ii, Pr); conditional, mlvar, adjust_x are 0/1
fn local_moran(x: []const f64, w: []const f64, n: usize, conditional: usize, mlvar: usize, adjust_x: usize, alt: usize, out: []f64) {
    let nf = f64(n)
    var nc = 0.0f64
    var xs = 0.0f64
    var i = 0usize
    while i < n {
        var card = 0usize
        var j = 0usize
        while j < n {
            if w[i * n + j] != 0.0f64 { card += 1usize }
            j += 1usize
        }
        if adjust_x == 0usize || card > 0usize {
            xs += x[i]
            nc += 1.0f64
        }
        i += 1usize
    }
    let xx = xs / nc
    var zsq = 0.0f64
    var z4 = 0.0f64
    var zsq_all = 0.0f64
    i = 0usize
    while i < n {
        var card = 0usize
        var j = 0usize
        while j < n {
            if w[i * n + j] != 0.0f64 { card += 1usize }
            j += 1usize
        }
        let zi = x[i] - xx
        zsq_all += zi * zi
        if adjust_x == 0usize || card > 0usize {
            zsq += zi * zi
            z4 += zi * zi * zi * zi
        }
        i += 1usize
    }
    var den = nc
    if mlvar == 0usize { den = nc - 1.0f64 }
    let s2 = zsq / den
    let b2 = (z4 / den) / (s2 * s2)
    let m2 = zsq_all / nf
    let a_ = (nf - b2) / (nf - 1.0f64)
    let b_ = (2.0f64 * b2 - nf) / ((nf - 1.0f64) * (nf - 2.0f64))
    i = 0usize
    while i < n {
        var lz = 0.0f64
        var wi = 0.0f64
        var wi2 = 0.0f64
        var j = 0usize
        while j < n {
            lz += w[i * n + j] * (x[j] - xx)
            wi += w[i * n + j]
            wi2 += w[i * n + j] * w[i * n + j]
            j += 1usize
        }
        let zi = x[i] - xx
        let ii = (zi / s2) * lz
        var e = 0.0f64 - wi / (nf - 1.0f64)
        var v = 0.0f64
        if conditional == 1usize {
            e = 0.0f64 - (zi * zi * wi) / ((nf - 1.0f64) * m2)
            v = (zi / m2) * (zi / m2) * (nf / (nf - 2.0f64)) * (wi2 - (wi * wi / (nf - 1.0f64))) * (m2 - (zi * zi / (nf - 1.0f64)))
        } else {
            v = a_ * wi2 + b_ * (wi * wi - wi2) - e * e
        }
        let z = (ii - e) / math.sqrt[f64](v)
        out[5usize * i] = ii
        out[5usize * i + 1usize] = e
        out[5usize * i + 2usize] = v
        out[5usize * i + 3usize] = z
        out[5usize * i + 4usize] = pval(z, alt)
        i += 1usize
    }
}

// localG (Gi when star is 0; G*i when star is 1, w then carries the diagonal): out is n by 5 (G, E(G), V(G), Z(G), Pr); alt as in pval
fn local_g(x: []const f64, w: []const f64, n: usize, star: usize, alt: usize, out: []f64) {
    let nf = f64(n)
    var sx = 0.0f64
    var sx2 = 0.0f64
    var i = 0usize
    while i < n {
        sx += x[i]
        sx2 += x[i] * x[i]
        i += 1usize
    }
    let mean = sx / nf
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (x[i] - mean) * (x[i] - mean)
        i += 1usize
    }
    i = 0usize
    while i < n {
        var lx = 0.0f64
        var wi = 0.0f64
        var s1i = 0.0f64
        var j = 0usize
        while j < n {
            lx += w[i * n + j] * x[j]
            wi += w[i * n + j]
            s1i += w[i * n + j] * w[i * n + j]
            j += 1usize
        }
        var xibar = 0.0f64
        var si2 = 0.0f64
        var vg = 0.0f64
        var xstar = sx
        if star == 1usize {
            xibar = mean
            si2 = ss / nf
            vg = si2 * ((nf * s1i - wi * wi) / (nf - 1.0f64))
        } else {
            xibar = (sx - x[i]) / (nf - 1.0f64)
            si2 = (sx2 - x[i] * x[i]) / (nf - 1.0f64) - xibar * xibar
            vg = si2 * (((nf - 1.0f64) * s1i - wi * wi) / (nf - 2.0f64))
            xstar = sx - x[i]
        }
        let eg = wi * xibar
        let z = (lx - eg) / math.sqrt[f64](vg)
        out[5usize * i] = lx / xstar
        out[5usize * i + 1usize] = eg / xstar
        out[5usize * i + 2usize] = vg / (xstar * xstar)
        out[5usize * i + 3usize] = z
        out[5usize * i + 4usize] = pval(z, alt)
        i += 1usize
    }
}

// poly2nb: pts holds every polygon's vertices (x then y each) one after another, cnt[p] is polygon p's vertex count; neighbours share more than one (rook) or at least one (queen) vertex pair within snap
fn poly(pts: []const f64, cnt: []const f64, n: usize, snap: f64, queen: usize, adj: []f64) {
    var i = 0usize
    while i < n * n {
        adj[i] = 0.0f64
        i += 1usize
    }
    var crit = 1usize
    if queen == 1usize { crit = 0usize }
    var oi = 0usize
    i = 0usize
    while i < n {
        let ni = usize(cnt[i])
        var oj = oi + ni
        var j = i + 1usize
        while j < n {
            let nj = usize(cnt[j])
            var xlo_i = 1.0e300f64
            var xhi_i = 0.0f64 - 1.0e300f64
            var ylo_i = 1.0e300f64
            var yhi_i = 0.0f64 - 1.0e300f64
            var xlo_j = 1.0e300f64
            var xhi_j = 0.0f64 - 1.0e300f64
            var ylo_j = 1.0e300f64
            var yhi_j = 0.0f64 - 1.0e300f64
            var p = 0usize
            while p < ni {
                let x = pts[2usize * (oi + p)]
                let y = pts[2usize * (oi + p) + 1usize]
                if x < xlo_i { xlo_i = x }
                if x > xhi_i { xhi_i = x }
                if y < ylo_i { ylo_i = y }
                if y > yhi_i { yhi_i = y }
                p += 1usize
            }
            p = 0usize
            while p < nj {
                let x = pts[2usize * (oj + p)]
                let y = pts[2usize * (oj + p) + 1usize]
                if x < xlo_j { xlo_j = x }
                if x > xhi_j { xhi_j = x }
                if y < ylo_j { ylo_j = y }
                if y > yhi_j { yhi_j = y }
                p += 1usize
            }
            let apart = (xlo_i - snap > xhi_j + snap) || (ylo_i - snap > yhi_j + snap) || (xhi_i + snap < xlo_j - snap) || (yhi_i + snap < ylo_j - snap)
            if !apart {
                var k = 0usize
                var s = 0usize
                while s < ni {
                    var t = 0usize
                    while t < nj {
                        let xd = pts[2usize * (oi + s)] - pts[2usize * (oj + t)]
                        let yd = pts[2usize * (oi + s) + 1usize] - pts[2usize * (oj + t) + 1usize]
                        if math.abs[f64](xd) <= snap && math.abs[f64](yd) <= snap && math.sqrt[f64](xd * xd + yd * yd) <= snap { k += 1usize }
                        t += 1usize
                    }
                    s += 1usize
                }
                if k > crit {
                    adj[i * n + j] = 1.0f64
                    adj[j * n + i] = 1.0f64
                }
            }
            oj += nj
            j += 1usize
        }
        oi += ni
        i += 1usize
    }
}

// joincount.test for level lev (1-based) of a factor given by codes[0..n]: out = same colour count, E, Var, z, p; sampling 0 nonfree, 1 free
fn join_count(codes: []const f64, w: []const f64, n: usize, lev: usize, sampling: usize, alt: usize, out: []f64) {
    var c: [4]f64 = zero
    wconst(w, n, c[0usize..4usize])
    let nn = c[0usize]
    let s0 = c[1usize]
    let s1 = c[2usize]
    let s2 = c[3usize]
    let n1 = nn - 1.0f64
    let n2 = nn - 2.0f64
    let n3 = nn - 3.0f64
    let s02 = s0 * s0
    var bb = 0.0f64
    var nt = 0.0f64
    var i = 0usize
    while i < n {
        if usize(codes[i]) == lev {
            nt += 1.0f64
            var j = 0usize
            while j < n {
                if usize(codes[j]) == lev { bb += w[i * n + j] }
                j += 1usize
            }
        }
        i += 1usize
    }
    let bb5 = 0.5f64 * bb
    var ejc = 0.0f64
    var vjc = 0.0f64
    if sampling == 0usize {
        ejc = (s0 * (nt * (nt - 1.0f64))) / (2.0f64 * nn * n1)
        vjc = (s1 * (nt * (nt - 1.0f64))) / (nn * n1)
        vjc = vjc + ((s2 - 2.0f64 * s1) * nt * (nt - 1.0f64) * (nt - 2.0f64)) / (nn * n1 * n2)
        vjc = vjc + ((s02 + s1 - s2) * nt * (nt - 1.0f64) * (nt - 2.0f64) * (nt - 3.0f64)) / (nn * n1 * n2 * n3)
        vjc = 0.25f64 * vjc - ejc * ejc
    } else {
        let p = nt / f64(n)
        ejc = (s0 * (p * p)) / 2.0f64
        vjc = ((s1 * (p * p)) + ((s2 - 2.0f64 * s1) * (p * p * p)) + ((s1 - s2) * (p * p * p * p))) / 4.0f64
    }
    let z = (bb5 - ejc) / math.sqrt[f64](vjc)
    out[0usize] = bb5
    out[1usize] = ejc
    out[2usize] = vjc
    out[3usize] = z
    out[4usize] = pval(z, alt)
}
