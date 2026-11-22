// R FactoMineR::PCA (row and column weights, scale.unit, supplementary individuals and quantitative variables) and CA (row weights, supplementary rows and columns). The axes carry FactoMineR's own signs: svd.triplet flips every axis so the (column-weight scaled) loadings sum positive, so no caller needs an absolute value.
//
// ncp must keep svd.triplet on its exact SVD branch (ncp >= half of min(rows, columns)); R switches to irlba, a 1e-5 approximation, below that.
// Also here: MCA, FAMD, MFA over quantitative groups and dimdesc (condes). Not here: supplementary qualitative variables of a PCA, MFA of qualitative groups, HCPC.

use e.algo.linalg.lapack_gesdd as gs
use e.algo.stat.fpc_km as km
use e.algo.stat.hclust as hc
use e.math
use e.math.nmath_beta as nb
use e.mem

error Malformed

// FactoMineR svd.triplet on x (n by m, row-major): vs (nd) singular values, u (n by nd) and v (m by nd) row-major, scaled by 1/sqrt of the weights. rw need not sum to one (it is normalised here as R does)
fn triplet(a: *mem.Arena, x: []const f64, n: usize, m: usize, rw: []const f64, cw: []const f64, nd: usize, vs: []f64, u: []f64, v: []f64) -> err {
    var k = n
    if m < k { k = m }
    let (xw, e1) = mem.alloc[f64](a, n * m)
    let (s, e2) = mem.alloc[f64](a, k)
    let (uu, e3) = mem.alloc[f64](a, n * k)
    let (vt, e4) = mem.alloc[f64](a, k * m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        tot += rw[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < m {
            xw[j * n + i] = x[i * m + j] * math.sqrt[f64](cw[j]) * math.sqrt[f64](rw[i] / tot)
            j += 1usize
        }
        i += 1usize
    }
    let r = gs.svd_all(a, xw, n, m, s, uu, vt)
    if r != ok { ret r }
    var c = 0usize
    while c < nd {
        var sv = 0.0f64
        var j = 0usize
        while j < m {
            sv += vt[c + j * k]
            j += 1usize
        }
        var mult = 1.0f64
        if sv < 0.0f64 { mult = -1.0f64 }
        vs[c] = s[c]
        i = 0usize
        while i < n {
            u[i * nd + c] = uu[i + c * n] * mult / math.sqrt[f64](rw[i] / tot)
            i += 1usize
        }
        j = 0usize
        while j < m {
            v[j * nd + c] = vt[c + j * k] * mult / math.sqrt[f64](cw[j])
            j += 1usize
        }
        c += 1usize
    }
    ret ok
}

// number of axes FactoMineR keeps: min(ncp, rows - 1, columns)
fn pca_axes(n: usize, p: usize, ncp: usize) -> usize {
    var nd = ncp
    if n - 1usize < nd { nd = n - 1usize }
    if p < nd { nd = p }
    ret nd
}

// PCA of x (n by p row-major) with row weights rw0 (n), column weights cw (p), standardisation scale, ncp axes, supplementary individuals xs (ns by p) and supplementary quantitative variables q (n by nq). out layout, nd = pca_axes: eig (nd), percentage (nd), var coord, cor, cos2, contrib (each p by nd), ind coord, cos2, contrib (each n by nd), ind dist (n), sup ind coord, cos2 (each ns by nd), sup ind dist (ns), sup var coord, cor, cos2 (each nq by nd)
fn pca(a: *mem.Arena, x: []const f64, n: usize, p: usize, rw0: []const f64, cw: []const f64, scale: bool, ncp: usize, xs: []const f64, ns: usize, q: []const f64, nq: usize, out: []f64) -> err {
    let nd = pca_axes(n, p, ncp)
    let (z, e1) = mem.alloc[f64](a, n * p)
    let (rw, e2) = mem.alloc[f64](a, n)
    let (ce, e3) = mem.alloc[f64](a, p)
    let (sd, e4) = mem.alloc[f64](a, p)
    let (d2i, e5) = mem.alloc[f64](a, n)
    let (d2v, e6) = mem.alloc[f64](a, p)
    let (vs, e7) = mem.alloc[f64](a, nd)
    let (uu, e8) = mem.alloc[f64](a, n * nd)
    let (vv, e9) = mem.alloc[f64](a, p * nd)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        tot += rw0[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        rw[i] = rw0[i] / tot
        i += 1usize
    }
    var j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += rw[i] * x[i * p + j]
            i += 1usize
        }
        ce[j] = m
        var s2 = 0.0f64
        i = 0usize
        while i < n {
            let d = x[i * p + j] - m
            s2 += rw[i] * (d * d)
            i += 1usize
        }
        var s = 1.0f64
        if scale {
            s = math.sqrt[f64](s2)
            if s <= 1.0e-16f64 { s = 1.0f64 }
        }
        sd[j] = s
        i = 0usize
        while i < n {
            z[i * p + j] = (x[i * p + j] - m) / s
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < n {
        var d2 = 0.0f64
        j = 0usize
        while j < p {
            d2 += z[i * p + j] * z[i * p + j] * cw[j]
            d2v[j] = 0.0f64
            j += 1usize
        }
        d2i[i] = d2
        i += 1usize
    }
    j = 0usize
    while j < p {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += z[i * p + j] * (rw[i] * z[i * p + j])
            i += 1usize
        }
        d2v[j] = s
        j += 1usize
    }
    let r = triplet(a, z, n, p, rw, cw, nd, vs, uu, vv)
    if r != ok { ret r }
    var sumvp = 0.0f64
    i = 0usize
    while i < n {
        sumvp += rw[i] * d2i[i]
        i += 1usize
    }
    let o_vc = 2usize * nd
    let o_vr = o_vc + p * nd
    let o_vk = o_vr + p * nd
    let o_vn = o_vk + p * nd
    let o_ic = o_vn + p * nd
    let o_ik = o_ic + n * nd
    let o_in = o_ik + n * nd
    let o_id = o_in + n * nd
    let o_sc = o_id + n
    let o_sk = o_sc + ns * nd
    let o_sd = o_sk + ns * nd
    let o_qc = o_sd + ns
    let o_qr = o_qc + nq * nd
    let o_qk = o_qr + nq * nd
    var k = 0usize
    while k < nd {
        let ev = vs[k] * vs[k]
        let se = math.sqrt[f64](ev)
        out[k] = ev
        out[nd + k] = ev / sumvp * 100.0f64
        j = 0usize
        while j < p {
            let c = vv[j * nd + k] * se
            out[o_vc + j * nd + k] = c
            let cr = c / math.sqrt[f64](d2v[j])
            out[o_vr + j * nd + k] = cr
            out[o_vk + j * nd + k] = cr * cr
            out[o_vn + j * nd + k] = c * c * cw[j] / ev * 100.0f64
            j += 1usize
        }
        i = 0usize
        while i < n {
            let c = uu[i * nd + k] * se
            out[o_ic + i * nd + k] = c
            out[o_ik + i * nd + k] = c * c / d2i[i]
            out[o_in + i * nd + k] = c * c * rw[i] / ev * 100.0f64
            i += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < n {
        out[o_id + i] = math.sqrt[f64](d2i[i])
        i += 1usize
    }
    var si = 0usize
    while si < ns {
        var d2 = 0.0f64
        j = 0usize
        while j < p {
            let t = (xs[si * p + j] - ce[j]) / sd[j]
            d2 += t * t * cw[j]
            j += 1usize
        }
        out[o_sd + si] = math.sqrt[f64](d2)
        k = 0usize
        while k < nd {
            var c = 0.0f64
            j = 0usize
            while j < p {
                let t = (xs[si * p + j] - ce[j]) / sd[j]
                c += t * cw[j] * vv[j * nd + k]
                j += 1usize
            }
            out[o_sc + si * nd + k] = c
            out[o_sk + si * nd + k] = c * c / d2
            k += 1usize
        }
        si += 1usize
    }
    var qj = 0usize
    while qj < nq {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += rw[i] * q[i * nq + qj]
            i += 1usize
        }
        var s2 = 0.0f64
        i = 0usize
        while i < n {
            let d = q[i * nq + qj] - m
            s2 += rw[i] * (d * d)
            i += 1usize
        }
        var s = 1.0f64
        if scale {
            s = math.sqrt[f64](s2)
            if s <= 1.0e-16f64 { s = 1.0f64 }
        }
        var dq = 0.0f64
        i = 0usize
        while i < n {
            let t = (q[i * nq + qj] - m) / s
            dq += t * t * rw[i]
            i += 1usize
        }
        k = 0usize
        while k < nd {
            var c = 0.0f64
            i = 0usize
            while i < n {
                let t = (q[i * nq + qj] - m) / s
                c += t * rw[i] * uu[i * nd + k]
                i += 1usize
            }
            out[o_qc + qj * nd + k] = c
            let cr = c / math.sqrt[f64](dq)
            out[o_qr + qj * nd + k] = cr
            out[o_qk + qj * nd + k] = cr * cr
            k += 1usize
        }
        qj += 1usize
    }
    ret ok
}

// number of axes CA keeps: min(ncp, rows - 1, columns - 1)
fn ca_axes(nr: usize, nc: usize, ncp: usize) -> usize {
    var nd = ncp
    if nr - 1usize < nd { nd = nr - 1usize }
    if nc - 1usize < nd { nd = nc - 1usize }
    ret nd
}

// CA of t (nr by nc row-major) with row weights rw, ncp axes, supplementary rows rs (nrs by nc) and supplementary columns cs (nr by ncs). out layout, nd = ca_axes: eig (nd), percentage (nd), row coord, contrib, cos2 (each nr by nd), row inertia (nr), col coord, contrib, cos2 (each nc by nd), col inertia (nc), sup row coord, cos2 (each nrs by nd), sup col coord, cos2 (each ncs by nd)
fn ca(a: *mem.Arena, t: []const f64, nr: usize, nc: usize, rw: []const f64, ncp: usize, rs: []const f64, nrs: usize, cs: []const f64, ncs: usize, out: []f64) -> err {
    let nd = ca_axes(nr, nc, ncp)
    let (mr, e1) = mem.alloc[f64](a, nr)
    let (mc, e2) = mem.alloc[f64](a, nc)
    let (tc, e3) = mem.alloc[f64](a, nr * nc)
    let (vs, e4) = mem.alloc[f64](a, nd)
    let (uu, e5) = mem.alloc[f64](a, nr * nd)
    let (vv, e6) = mem.alloc[f64](a, nc * nd)
    let (d2r, e7) = mem.alloc[f64](a, nr)
    let (d2c, e8) = mem.alloc[f64](a, nc)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    var total = 0.0f64
    var i = 0usize
    var j = 0usize
    while j < nc {
        i = 0usize
        while i < nr {
            total += t[i * nc + j] * rw[i]
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < nc {
        mc[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < nr {
        mr[i] = 0.0f64
        i += 1usize
    }
    j = 0usize
    while j < nc {
        i = 0usize
        while i < nr {
            let f = t[i * nc + j] * (rw[i] / total)
            mc[j] += f
            mr[i] += f
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < nr {
        j = 0usize
        while j < nc {
            let f = t[i * nc + j] * (rw[i] / total)
            tc[i * nc + j] = f / (mr[i] * mc[j]) - 1.0f64
            j += 1usize
        }
        i += 1usize
    }
    let r = triplet(a, tc, nr, nc, mr, mc, nd, vs, uu, vv)
    if r != ok { ret r }
    i = 0usize
    while i < nr {
        var s = 0.0f64
        j = 0usize
        while j < nc {
            s += tc[i * nc + j] * tc[i * nc + j] * mc[j]
            j += 1usize
        }
        d2r[i] = s
        i += 1usize
    }
    j = 0usize
    while j < nc {
        var s = 0.0f64
        i = 0usize
        while i < nr {
            s += tc[i * nc + j] * (tc[i * nc + j] * mr[i])
            i += 1usize
        }
        d2c[j] = s
        j += 1usize
    }
    var sumvp = 0.0f64
    i = 0usize
    while i < nr {
        sumvp += mr[i] * d2r[i]
        i += 1usize
    }
    let o_rc = 2usize * nd
    let o_rn = o_rc + nr * nd
    let o_rk = o_rn + nr * nd
    let o_ri = o_rk + nr * nd
    let o_cc = o_ri + nr
    let o_cn = o_cc + nc * nd
    let o_ck = o_cn + nc * nd
    let o_ci = o_ck + nc * nd
    let o_sr = o_ci + nc
    let o_sk = o_sr + nrs * nd
    let o_sc = o_sk + nrs * nd
    let o_sl = o_sc + ncs * nd
    var k = 0usize
    while k < nd {
        let ev = vs[k] * vs[k]
        let se = math.sqrt[f64](ev)
        out[k] = ev
        out[nd + k] = ev / sumvp * 100.0f64
        i = 0usize
        while i < nr {
            let c = uu[i * nd + k] * se
            out[o_rc + i * nd + k] = c
            out[o_rn + i * nd + k] = c * (c * mr[i]) / ev * 100.0f64
            out[o_rk + i * nd + k] = c * (c / d2r[i])
            i += 1usize
        }
        j = 0usize
        while j < nc {
            let c = vv[j * nd + k] * se
            out[o_cc + j * nd + k] = c
            out[o_cn + j * nd + k] = c * (c * mc[j]) / ev * 100.0f64
            out[o_ck + j * nd + k] = c * (c / d2c[j])
            j += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < nr {
        out[o_ri + i] = mr[i] * d2r[i]
        i += 1usize
    }
    j = 0usize
    while j < nc {
        out[o_ci + j] = mc[j] * d2c[j]
        j += 1usize
    }
    var si = 0usize
    while si < nrs {
        var rsum = 0.0f64
        j = 0usize
        while j < nc {
            rsum += rs[si * nc + j]
            j += 1usize
        }
        var d2 = 0.0f64
        j = 0usize
        while j < nc {
            let pj = rs[si * nc + j] / rsum
            d2 += (pj - mc[j]) * (pj - mc[j]) / mc[j]
            j += 1usize
        }
        k = 0usize
        while k < nd {
            var c = 0.0f64
            j = 0usize
            while j < nc {
                c += rs[si * nc + j] / rsum * vv[j * nd + k]
                j += 1usize
            }
            out[o_sr + si * nd + k] = c
            out[o_sk + si * nd + k] = c * c / d2
            k += 1usize
        }
        si += 1usize
    }
    var sj = 0usize
    while sj < ncs {
        var csum = 0.0f64
        i = 0usize
        while i < nr {
            csum += cs[i * ncs + sj] * rw[i]
            i += 1usize
        }
        var d2 = 0.0f64
        i = 0usize
        while i < nr {
            let pq = cs[i * ncs + sj] * rw[i] / csum
            d2 += (pq - mr[i]) * (pq - mr[i]) / mr[i]
            i += 1usize
        }
        k = 0usize
        while k < nd {
            var c = 0.0f64
            i = 0usize
            while i < nr {
                c += cs[i * ncs + sj] * rw[i] / csum * uu[i * nd + k]
                i += 1usize
            }
            out[o_sc + sj * nd + k] = c
            out[o_sl + sj * nd + k] = c * c / d2
            k += 1usize
        }
        sj += 1usize
    }
    ret ok
}

// length of the block ca writes
fn ca_len(nr: usize, nc: usize, nd: usize, nrs: usize, ncs: usize) -> usize {
    ret 2usize * nd + 3usize * nr * nd + nr + 3usize * nc * nd + nc + 2usize * nrs * nd + 2usize * ncs * nd
}

// MCA (Indicator method, no excl, no ventilation) of j active factors then jq supplementary factors. codes is (n + ns) by (j + jq) row-major, 1-based levels, active individuals first; lev holds the level count of each of the j + jq factors; rw (n); q (n by nq) supplementary quantitative variables. out: ca's layout over the indicator table (k = sum of active levels, kq = sum of supplementary levels; supplementary categories are ca's supplementary columns), then var v.test (k by nd), var eta2 (j by nd), supplementary-category v.test (kq by nd), supplementary-factor eta2 (jq by nd), supplementary quantitative coord (nq by nd). ncp is the axes asked of ca: pass k - j
fn mca(a: *mem.Arena, codes: []const f64, n: usize, ns: usize, j: usize, jq: usize, lev: []const f64, rw: []const f64, q: []const f64, nq: usize, ncp: usize, out: []f64) -> err {
    var k = 0usize
    var v = 0usize
    while v < j {
        k += usize(lev[v])
        v += 1usize
    }
    var kq = 0usize
    while v < j + jq {
        kq += usize(lev[v])
        v += 1usize
    }
    let w = j + jq
    let (tb, e1) = mem.alloc[f64](a, n * k)
    let (rs, e2) = mem.alloc[f64](a, ns * k + 1usize)
    let (cs, e3) = mem.alloc[f64](a, n * kq + 1usize)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n + ns {
        var at = 0usize
        var atq = 0usize
        v = 0usize
        while v < w {
            let nl = usize(lev[v])
            let code = usize(codes[i * w + v]) - 1usize
            var l = 0usize
            while l < nl {
                var hit = 0.0f64
                if l == code { hit = 1.0f64 }
                if v < j {
                    if i < n { tb[i * k + at + l] = hit }
                    if i >= n { rs[(i - n) * k + at + l] = hit }
                }
                if v >= j && i < n { cs[i * kq + atq + l] = hit }
                l += 1usize
            }
            if v < j { at += nl }
            if v >= j { atq += nl }
            v += 1usize
        }
        i += 1usize
    }
    let nd = ca_axes(n, k, ncp)
    let r = ca(a, tb, n, k, rw, ncp, rs, ns, cs, kq, out)
    if r != ok { ret r }
    let o_rc = 2usize * nd
    let o_cc = o_rc + 3usize * n * nd + n
    let o_cn = o_cc + k * nd
    let o_sc = o_cc + 3usize * k * nd + k + 2usize * ns * nd
    let o_vt = ca_len(n, k, nd, ns, kq)
    let o_ve = o_vt + k * nd
    let o_qt = o_ve + j * nd
    let o_qe = o_qt + kq * nd
    let o_qc = o_qe + jq * nd
    var tot = 0.0f64
    i = 0usize
    while i < n {
        tot += rw[i]
        i += 1usize
    }
    var c = 0usize
    while c < k {
        var nj = 0.0f64
        i = 0usize
        while i < n {
            nj += tb[i * k + c] * rw[i]
            i += 1usize
        }
        var coef = math.sqrt[f64](nj)
        if tot > 1.0f64 { coef = math.sqrt[f64](nj * ((tot - 1.0f64) / (tot - nj))) }
        var d = 0usize
        while d < nd {
            out[o_vt + c * nd + d] = out[o_cc + c * nd + d] * coef
            d += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < kq {
        var nj = 0.0f64
        i = 0usize
        while i < n {
            nj += cs[i * kq + c] * rw[i]
            i += 1usize
        }
        var coef = math.sqrt[f64](nj)
        if tot > 1.0f64 { coef = math.sqrt[f64](nj * ((tot - 1.0f64) / (tot - nj))) }
        var d = 0usize
        while d < nd {
            out[o_qt + c * nd + d] = out[o_sc + c * nd + d] * coef
            d += 1usize
        }
        c += 1usize
    }
    var at = 0usize
    var v2 = 0usize
    while v2 < j {
        let nl = usize(lev[v2])
        var d = 0usize
        while d < nd {
            var s = 0.0f64
            var l = 0usize
            while l < nl {
                s += out[o_cn + (at + l) * nd + d] / 100.0f64
                l += 1usize
            }
            out[o_ve + v2 * nd + d] = s * out[d] * f64(j)
            d += 1usize
        }
        at += nl
        v2 += 1usize
    }
    at = 0usize
    v2 = 0usize
    while v2 < jq {
        let nl = usize(lev[j + v2])
        var d = 0usize
        while d < nd {
            var mean = 0.0f64
            i = 0usize
            while i < n {
                mean += rw[i] / tot * out[o_rc + i * nd + d]
                i += 1usize
            }
            var sct = 0.0f64
            i = 0usize
            while i < n {
                let dv = out[o_rc + i * nd + d] - mean
                sct += rw[i] * (dv * dv)
                i += 1usize
            }
            var sce = 0.0f64
            var l = 0usize
            while l < nl {
                var wg = 0.0f64
                var sg = 0.0f64
                i = 0usize
                while i < n {
                    let hit = cs[i * kq + at + l]
                    wg += hit * rw[i]
                    sg += hit * rw[i] * out[o_rc + i * nd + d]
                    i += 1usize
                }
                let dg = sg / wg - mean
                sce += wg * (dg * dg)
                l += 1usize
            }
            out[o_qe + v2 * nd + d] = sce / sct
            d += 1usize
        }
        at += nl
        v2 += 1usize
    }
    var qj = 0usize
    while qj < nq {
        var mq = 0.0f64
        i = 0usize
        while i < n {
            mq += rw[i] / tot * q[i * nq + qj]
            i += 1usize
        }
        var vq = 0.0f64
        i = 0usize
        while i < n {
            let dq = q[i * nq + qj] - mq
            vq += rw[i] / tot * (dq * dq)
            i += 1usize
        }
        var d = 0usize
        while d < nd {
            var mu = 0.0f64
            i = 0usize
            while i < n {
                mu += rw[i] / tot * out[o_rc + i * nd + d]
                i += 1usize
            }
            var vu = 0.0f64
            var cv = 0.0f64
            i = 0usize
            while i < n {
                let du = out[o_rc + i * nd + d] - mu
                vu += rw[i] / tot * (du * du)
                cv += rw[i] / tot * (du * (q[i * nq + qj] - mq))
                i += 1usize
            }
            out[o_qc + qj * nd + d] = cv / math.sqrt[f64](vu * vq)
            d += 1usize
        }
        qj += 1usize
    }
    ret ok
}

// length of the block pca writes
fn pca_len(n: usize, p: usize, nd: usize, ns: usize, nq: usize) -> usize {
    ret 2usize * nd + 4usize * p * nd + 3usize * n * nd + n + 2usize * ns * nd + ns + 3usize * nq * nd
}

// FAMD with active variables only: pq quantitative columns (x, (n + ns) by pq row-major, active rows first) and jf factors (codes (n + ns) by jf, 1-based; lev levels each), row weights rw (n), ns supplementary individuals. out: pca's layout (nq = 0) over the pq + k transformed columns (k = sum of levels), then category coord, cos2, v.test (each k by nd), variable coord, contrib, cos2 (each pq + jf by nd). ncp: pass pq + k - jf
fn famd(a: *mem.Arena, x: []const f64, codes: []const f64, n: usize, ns: usize, pq: usize, jf: usize, lev: []const f64, rw: []const f64, ncp: usize, out: []f64) -> err {
    var k = 0usize
    var v = 0usize
    while v < jf {
        k += usize(lev[v])
        v += 1usize
    }
    let p = pq + k
    let nt = n + ns
    let (xt, e1) = mem.alloc[f64](a, nt * p)
    let (prop, e2) = mem.alloc[f64](a, k + 1usize)
    let (ones, e3) = mem.alloc[f64](a, p)
    let (z, e4) = mem.alloc[f64](a, nt * k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        sw += rw[i]
        i += 1usize
    }
    var j = 0usize
    while j < p {
        ones[j] = 1.0f64
        j += 1usize
    }
    j = 0usize
    while j < pq {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += rw[i] / sw * x[i * pq + j]
            i += 1usize
        }
        var s2 = 0.0f64
        i = 0usize
        while i < n {
            let d = x[i * pq + j] - m
            s2 += rw[i] / sw * (d * d)
            i += 1usize
        }
        var s = math.sqrt[f64](s2)
        if s <= 1.0e-16f64 { s = 1.0f64 }
        i = 0usize
        while i < nt {
            xt[i * p + j] = (x[i * pq + j] - m) / s
            i += 1usize
        }
        j += 1usize
    }
    var at = 0usize
    v = 0usize
    while v < jf {
        let nl = usize(lev[v])
        var l = 0usize
        while l < nl {
            var pr = 0.0f64
            i = 0usize
            while i < n {
                var hit = 0.0f64
                if usize(codes[i * jf + v]) - 1usize == l { hit = 1.0f64 }
                pr += hit * (rw[i] / sw)
                i += 1usize
            }
            prop[at + l] = pr
            i = 0usize
            while i < nt {
                var hit = 0.0f64
                if usize(codes[i * jf + v]) - 1usize == l { hit = 1.0f64 }
                z[i * k + at + l] = hit
                xt[i * p + pq + at + l] = (hit - pr) / math.sqrt[f64](pr)
                i += 1usize
            }
            l += 1usize
        }
        at += nl
        v += 1usize
    }
    let nd = pca_axes(n, p, ncp)
    let r = pca(a, xt[0usize..n * p], n, p, rw, ones, false, ncp, xt[n * p..nt * p], ns, xt[0usize..0usize], 0usize, out)
    if r != ok { ret r }
    let o_vc = 2usize * nd
    let o_vk = o_vc + 2usize * p * nd
    let o_vn = o_vk + p * nd
    let o_ic = o_vn + p * nd
    let o_qc = pca_len(n, p, nd, ns, 0usize)
    let o_qk = o_qc + k * nd
    let o_qt = o_qk + k * nd
    let o_ac = o_qt + k * nd
    let o_an = o_ac + (pq + jf) * nd
    let o_ak = o_an + (pq + jf) * nd
    var c = 0usize
    while c < k {
        var d2 = 0.0f64
        var col = 0usize
        while col < p {
            var bs = 0.0f64
            var bw = 0.0f64
            i = 0usize
            while i < n {
                if z[i * k + c] != 0.0f64 {
                    bs += rw[i] * xt[i * p + col]
                    bw += rw[i]
                }
                i += 1usize
            }
            let bary = bs / bw
            d2 += bary * bary
            col += 1usize
        }
        var nbv = prop[c] * sw
        if sw > 1.0f64 {
            nbv = (sw - nbv) / (sw - 1.0f64) / sw
        }
        if sw <= 1.0f64 {
            nbv = (f64(n) - nbv) / (f64(n) - 1.0f64) / f64(n)
        }
        var d = 0usize
        while d < nd {
            let cc = out[o_vc + (pq + c) * nd + d] / math.sqrt[f64](prop[c]) * math.sqrt[f64](out[d])
            out[o_qc + c * nd + d] = cc
            out[o_qk + c * nd + d] = cc * cc / d2
            out[o_qt + c * nd + d] = out[o_vc + (pq + c) * nd + d] / math.sqrt[f64](nbv)
            d += 1usize
        }
        c += 1usize
    }
    var d = 0usize
    while d < nd {
        j = 0usize
        while j < pq {
            let cc = out[o_vc + j * nd + d]
            out[o_ac + j * nd + d] = cc * cc
            out[o_an + j * nd + d] = out[o_vn + j * nd + d]
            out[o_ak + j * nd + d] = out[o_vk + j * nd + d] * out[o_vk + j * nd + d]
            j += 1usize
        }
        var mean = 0.0f64
        i = 0usize
        while i < n {
            mean += rw[i] / sw * out[o_ic + i * nd + d]
            i += 1usize
        }
        var sct = 0.0f64
        i = 0usize
        while i < n {
            let dv = out[o_ic + i * nd + d] - mean
            sct += rw[i] / sw * (dv * dv)
            i += 1usize
        }
        at = 0usize
        v = 0usize
        while v < jf {
            let nl = usize(lev[v])
            var sc = 0.0f64
            var sce = 0.0f64
            var l = 0usize
            while l < nl {
                sc += out[o_vn + (pq + at + l) * nd + d]
                var wg = 0.0f64
                var sg = 0.0f64
                i = 0usize
                while i < n {
                    if z[i * k + at + l] != 0.0f64 {
                        wg += rw[i] / sw
                        sg += rw[i] / sw * out[o_ic + i * nd + d]
                    }
                    i += 1usize
                }
                let dg = sg / wg - mean
                sce += wg * (dg * dg)
                l += 1usize
            }
            let eta = sce / sct
            out[o_ac + (pq + v) * nd + d] = eta
            out[o_an + (pq + v) * nd + d] = sc
            out[o_ak + (pq + v) * nd + d] = eta * eta / f64(nl - 1usize)
            at += nl
            v += 1usize
        }
        d += 1usize
    }
    ret ok
}

// weighted (ML) correlation of x with y and its two-sided t-test probability, as FactoMineR's condes computes them; w sums to at least 3. out[0] = r, out[1] = p
fn condes_cor(x: []const f64, y: []const f64, w: []const f64, n: usize, out: []f64) {
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        sw += w[i]
        i += 1usize
    }
    var mx = 0.0f64
    var my = 0.0f64
    i = 0usize
    while i < n {
        mx += w[i] / sw * x[i]
        my += w[i] / sw * y[i]
        i += 1usize
    }
    var vx = 0.0f64
    var vy = 0.0f64
    var cv = 0.0f64
    i = 0usize
    while i < n {
        let dx = x[i] - mx
        let dy = y[i] - my
        vx += w[i] / sw * (dx * dx)
        vy += w[i] / sw * (dy * dy)
        cv += w[i] / sw * (dx * dy)
        i += 1usize
    }
    let r = cv / math.sqrt[f64](vx * vy)
    out[0usize] = r
    out[1usize] = nb.pt(math.sqrt[f64](sw - 2.0f64) * math.sqrt[f64](r * r / (1.0f64 - r * r)), sw - 2.0f64, false, false) * 2.0f64
}

// FactoMineR condes of the response y (n) against nq quantitative columns xq (n by nq, row-major) and jf factors (codes n by jf, 1-based, lev levels each, every level present), row weights w0, all rows kept (proba = 1), in input order. out: correlation (nq), p.value (nq), R2 (jf), p.value (jf), category Estimate (k), category p.value (k), k = sum of levels
fn condes(a: *mem.Arena, y: []const f64, w0: []const f64, xq: []const f64, n: usize, nq: usize, codes: []const f64, jf: usize, lev: []const f64, out: []f64) -> err {
    let (w, e1) = mem.alloc[f64](a, n)
    let (col, e2) = mem.alloc[f64](a, n)
    let (ind, e3) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    var k = 0usize
    var v = 0usize
    while v < jf {
        k += usize(lev[v])
        v += 1usize
    }
    var sw0 = 0.0f64
    var i = 0usize
    while i < n {
        sw0 += w0[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        w[i] = w0[i]
        if sw0 < 3.0f64 { w[i] = w0[i] * f64(n) }
        i += 1usize
    }
    var tmp: [2]f64 = zero
    var j = 0usize
    while j < nq {
        i = 0usize
        while i < n {
            col[i] = xq[i * nq + j]
            i += 1usize
        }
        condes_cor(col, y, w, n, tmp[0usize..])
        out[j] = tmp[0usize]
        out[nq + j] = tmp[1usize]
        j += 1usize
    }
    var sw = 0.0f64
    var mu = 0.0f64
    var sct = 0.0f64
    i = 0usize
    while i < n {
        sw += w[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        mu += w[i] * y[i]
        i += 1usize
    }
    mu = mu / sw
    i = 0usize
    while i < n {
        sct += w[i] * ((y[i] - mu) * (y[i] - mu))
        i += 1usize
    }
    let o_r2 = 2usize * nq
    let o_pf = o_r2 + jf
    let o_es = o_pf + jf
    let o_pt = o_es + k
    var at = 0usize
    v = 0usize
    while v < jf {
        let nl = usize(lev[v])
        let (mg, e4) = mem.alloc[f64](a, nl)
        if e4 != ok { ret e4 }
        var sce = 0.0f64
        var l = 0usize
        var msum = 0.0f64
        while l < nl {
            var wg = 0.0f64
            var sg = 0.0f64
            i = 0usize
            while i < n {
                if usize(codes[i * jf + v]) - 1usize == l {
                    wg += w[i]
                    sg += w[i] * y[i]
                }
                i += 1usize
            }
            mg[l] = sg / wg
            sce += wg * ((mg[l] - mu) * (mg[l] - mu))
            msum += mg[l]
            l += 1usize
        }
        let scr = sct - sce
        let ddl_e = f64(nl - 1usize)
        let ddl_r = f64(n) - f64(nl)
        let fs = (sce / ddl_e) / (scr / ddl_r)
        out[o_r2 + v] = sce / sct
        out[o_pf + v] = nb.pf(fs, ddl_e, ddl_r, false, false)
        let mc = msum / f64(nl)
        var k1 = 0.0f64
        l = 0usize
        while l + 1usize < nl {
            out[o_es + at + l] = mg[l] - mc
            k1 += mg[l] - mc
            l += 1usize
        }
        out[o_es + at + nl - 1usize] = -k1
        l = 0usize
        while l < nl {
            i = 0usize
            while i < n {
                ind[i] = 0.0f64
                if usize(codes[i * jf + v]) - 1usize == l { ind[i] = 1.0f64 }
                i += 1usize
            }
            condes_cor(ind, y, w, n, tmp[0usize..])
            out[o_pt + at + l] = tmp[1usize]
            l += 1usize
        }
        at += nl
        v += 1usize
    }
    ret ok
}

// MFA over ng quantitative groups: gsz (ng) columns each, gty 1 = standardised group ("s"), 0 = centred only ("c"). x is n by P row-major (P = sum of gsz, active rows), xs is ns by P supplementary individuals, rw (n). out: pca's layout (nq = 0) of the global analysis over the P weighted columns, then Lg and RV ((ng + 1) squared each, the last row and column being the whole analysis), group coord, contrib (percent), cos2 (each ng by nd), group dist2 (ng), group-factor correlation (ng by nd). Keep each group's ncp at least half its size (R switches to irlba below that)
fn mfa(a: *mem.Arena, x: []const f64, xs: []const f64, n: usize, ns: usize, gsz: []const f64, gty: []const f64, ng: usize, rw: []const f64, ncp: usize, out: []f64) -> err {
    var pp = 0usize
    var g = 0usize
    while g < ng {
        pp += usize(gsz[g])
        g += 1usize
    }
    let nt = n + ns
    let (dt, e1) = mem.alloc[f64](a, nt * pp)
    let (pond, e2) = mem.alloc[f64](a, pp)
    let (sub, e3) = mem.alloc[f64](a, n * pp)
    let (sout, e4) = mem.alloc[f64](a, 1usize << 15usize)
    let (ones, e5) = mem.alloc[f64](a, pp)
    let (ctr, e6) = mem.alloc[f64](a, pp)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        sw += rw[i]
        i += 1usize
    }
    var j = 0usize
    while j < pp {
        ones[j] = 1.0f64
        j += 1usize
    }
    var c0 = 0usize
    g = 0usize
    while g < ng {
        let sz = usize(gsz[g])
        i = 0usize
        while i < n {
            j = 0usize
            while j < sz {
                sub[i * sz + j] = x[i * pp + c0 + j]
                j += 1usize
            }
            i += 1usize
        }
        let r = pca(a, sub[0usize..n * sz], n, sz, rw, ones[0usize..sz], gty[g] != 0.0f64, ncp, sub[0usize..0usize], 0usize, sub[0usize..0usize], 0usize, sout)
        if r != ok { ret r }
        j = 0usize
        while j < sz {
            pond[c0 + j] = 1.0f64 / sout[0usize]
            var m = 0.0f64
            i = 0usize
            while i < n {
                m += x[i * pp + c0 + j] * rw[i]
                i += 1usize
            }
            m = m / sw
            var s2 = 0.0f64
            i = 0usize
            while i < n {
                let d = x[i * pp + c0 + j] - m
                s2 += d * d * rw[i]
                i += 1usize
            }
            var s = math.sqrt[f64](s2 / sw)
            if s <= 1.0e-8f64 { s = 1.0f64 }
            i = 0usize
            while i < nt {
                var v = 0.0f64
                if i < n { v = x[i * pp + c0 + j] }
                if i >= n { v = xs[(i - n) * pp + c0 + j] }
                if gty[g] != 0.0f64 { v = (v - m) / s }
                dt[i * pp + c0 + j] = v
                i += 1usize
            }
            j += 1usize
        }
        c0 += sz
        g += 1usize
    }
    let nd = pca_axes(n, pp, ncp)
    let rg = pca(a, dt[0usize..n * pp], n, pp, rw, pond, false, ncp, dt[n * pp..nt * pp], ns, sub[0usize..0usize], 0usize, out)
    if rg != ok { ret rg }
    let o_vc = 2usize * nd
    let o_vn = o_vc + 3usize * pp * nd
    let o_ic = o_vn + pp * nd
    let base = pca_len(n, pp, nd, ns, 0usize)
    let ng1 = ng + 1usize
    let o_lg = base
    let o_rv = o_lg + ng1 * ng1
    let o_gc = o_rv + ng1 * ng1
    let o_gn = o_gc + ng * nd
    let o_gk = o_gn + ng * nd
    let o_gd = o_gk + ng * nd
    let o_gr = o_gd + ng
    j = 0usize
    while j < pp {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += rw[i] / sw * dt[i * pp + j]
            i += 1usize
        }
        ctr[j] = m
        j += 1usize
    }
    var gl = 0usize
    var cl = 0usize
    while gl < ng {
        let szl = usize(gsz[gl])
        var gc = gl
        var cc = cl
        while gc < ng {
            let szc = usize(gsz[gc])
            var tot = 0.0f64
            var a1 = 0usize
            while a1 < szl {
                var b1 = 0usize
                while b1 < szc {
                    var mat = 0.0f64
                    i = 0usize
                    while i < n {
                        let xl = (dt[i * pp + cl + a1] - ctr[cl + a1]) * math.sqrt[f64](pond[cl + a1])
                        let xc = (dt[i * pp + cc + b1] - ctr[cc + b1]) * math.sqrt[f64](pond[cc + b1])
                        mat += math.sqrt[f64](rw[i] / sw) * xl * (math.sqrt[f64](rw[i] / sw) * xc)
                        i += 1usize
                    }
                    tot += mat * mat
                    b1 += 1usize
                }
                a1 += 1usize
            }
            out[o_lg + gl * ng1 + gc] = tot
            out[o_lg + gc * ng1 + gl] = tot
            cc += szc
            gc += 1usize
        }
        cl += szl
        gl += 1usize
    }
    let e1v = out[0usize]
    gc_loop(out, o_lg, ng, e1v)
    var r1 = 0usize
    while r1 < ng1 {
        var c1 = 0usize
        while c1 < ng1 {
            out[o_rv + r1 * ng1 + c1] = out[o_lg + r1 * ng1 + c1] / math.sqrt[f64](out[o_lg + c1 * ng1 + c1]) / math.sqrt[f64](out[o_lg + r1 * ng1 + r1])
            c1 += 1usize
        }
        r1 += 1usize
    }
    var cs = 0usize
    g = 0usize
    while g < ng {
        let sz = usize(gsz[g])
        var d = 0usize
        while d < nd {
            var s = 0.0f64
            j = 0usize
            while j < sz {
                s += out[o_vn + (cs + j) * nd + d] / 100.0f64
                j += 1usize
            }
            out[o_gn + g * nd + d] = s * 100.0f64
            let cg = s * out[d]
            out[o_gc + g * nd + d] = cg
            out[o_gd + g] = out[o_lg + g * ng1 + g]
            out[o_gk + g * nd + d] = cg * cg / out[o_lg + g * ng1 + g]
            d += 1usize
        }
        cs += sz
        g += 1usize
    }
    cs = 0usize
    g = 0usize
    while g < ng {
        let sz = usize(gsz[g])
        var d = 0usize
        while d < nd {
            let (pc, e7) = mem.alloc[f64](a, n)
            if e7 != ok { ret e7 }
            i = 0usize
            while i < n {
                var s = 0.0f64
                j = 0usize
                while j < sz {
                    s += f64(ng) * (dt[i * pp + cs + j] - ctr[cs + j]) * pond[cs + j] * (out[o_vc + (cs + j) * nd + d] / math.sqrt[f64](out[d]))
                    j += 1usize
                }
                pc[i] = s
                i += 1usize
            }
            var mp = 0.0f64
            var mq = 0.0f64
            i = 0usize
            while i < n {
                mp += rw[i] / sw * pc[i]
                mq += rw[i] / sw * out[o_ic + i * nd + d]
                i += 1usize
            }
            var vp = 0.0f64
            var vq = 0.0f64
            var cv = 0.0f64
            i = 0usize
            while i < n {
                let dp = pc[i] - mp
                let dq = out[o_ic + i * nd + d] - mq
                vp += rw[i] / sw * (dp * dp)
                vq += rw[i] / sw * (dq * dq)
                cv += rw[i] / sw * (dp * dq)
                i += 1usize
            }
            out[o_gr + g * nd + d] = cv / math.sqrt[f64](vp * vq)
            d += 1usize
        }
        cs += sz
        g += 1usize
    }
    ret ok
}

// the MFA row and column of Lg: the sum over groups of each column divided by the first eigenvalue, and the corner
fn gc_loop(out: []f64, o_lg: usize, ng: usize, e1: f64) {
    let ng1 = ng + 1usize
    var c = 0usize
    while c < ng {
        var s = 0.0f64
        var g = 0usize
        while g < ng {
            s += out[o_lg + g * ng1 + c]
            g += 1usize
        }
        out[o_lg + ng * ng1 + c] = s / e1
        out[o_lg + c * ng1 + ng] = s / e1
        c += 1usize
    }
    var t = 0.0f64
    var g2 = 0usize
    while g2 < ng {
        t += out[o_lg + g2 * ng1 + ng]
        g2 += 1usize
    }
    out[o_lg + ng * ng1 + ng] = t / e1
}

// R round(n / 2) (half to even)
fn round_half_n(n: usize) -> usize {
    if n % 2usize == 0usize { ret n / 2usize }
    let h = (n - 1usize) / 2usize
    if h % 2usize == 0usize { ret h }
    ret h + 1usize
}

// FactoMineR HCPC (graph = FALSE, order = TRUE, graph.scale "inertia", method "ward", metric "euclidean", kk = Inf) on the individual coordinates coord (n by nd row-major)
// of a PCA, MCA, FAMD or MFA with raw row weights w (row.w.init). ncl <= 1 picks the number of clusters by the inertia-gain criterion between minc and maxc (0 = the default
// min(10, round(n/2), n - 2)); consol runs the k-means consolidation (Hartigan-Wong, iter_max) from the cluster means.
// out: [nb, nq, perm (n, 1-based original index of each sorted row), merge a (n-1), merge b (n-1), height (n-1), order (n, sorted positions),
// clust (n, original row order), centers (nb by nd, ordered by the first coordinate), quot (nq), inertia gain (n-1)]
fn hcpc(a: *mem.Arena, coord: []const f64, n: usize, nd: usize, w: []const f64, ncl: usize, consol: bool, minc: usize, maxc: usize, iter_max: usize, out: []f64) -> err {
    let (perm, e1) = mem.alloc[usize](a, n)
    let (xs, e2) = mem.alloc[f64](a, n * nd)
    let (ws, e3) = mem.alloc[f64](a, n)
    let (dm, e4) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    var i = 0usize
    while i < n {
        perm[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let cur = perm[i]
        var j = i
        while j > 0usize && coord[perm[j - 1usize] * nd] > coord[cur * nd] {
            perm[j] = perm[j - 1usize]
            j -= 1usize
        }
        perm[j] = cur
        i += 1usize
    }
    var wt = 0.0f64
    i = 0usize
    while i < n {
        ws[i] = w[perm[i]]
        wt += ws[i]
        var k = 0usize
        while k < nd {
            xs[i * nd + k] = coord[perm[i] * nd + k]
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var k = 0usize
            while k < nd {
                let d = xs[i * nd + k] - xs[j * nd + k]
                s += d * d
                k += 1usize
            }
            let dd = math.sqrt[f64](s)
            dm[i * n + j] = (dd * dd) * (ws[i] * ws[j] / wt / (ws[i] + ws[j]))
            j += 1usize
        }
        i += 1usize
    }
    let (tr, e5) = hc.hclust_members(a, dm, n, 1usize, ws)
    if e5 != ok { ret e5 }
    let m = n - 1usize
    let o_perm = 2usize
    let o_ma = o_perm + n
    let o_mb = o_ma + m
    let o_ht = o_mb + m
    let o_ord = o_ht + m
    let o_cl = o_ord + n
    i = 0usize
    while i < n {
        out[o_perm + i] = f64(perm[i] + 1usize)
        out[o_ord + i] = f64(tr.order[i])
        i += 1usize
    }
    i = 0usize
    while i < m {
        out[o_ma + i] = f64(tr.merge_a[i])
        out[o_mb + i] = f64(tr.merge_b[i])
        out[o_ht + i] = tr.height[i]
        i += 1usize
    }
    let (gain, e6) = mem.alloc[f64](a, m)
    let (intra, e7) = mem.alloc[f64](a, m + 2usize)
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    i = 0usize
    while i < m {
        gain[i] = tr.height[m - 1usize - i]
        i += 1usize
    }
    var run = 0.0f64
    i = m
    while i > 0usize {
        run += gain[i - 1usize]
        intra[i] = run
        i -= 1usize
    }
    var mx = maxc
    if mx == 0usize {
        mx = 10usize
        if round_half_n(n) < mx { mx = round_half_n(n) }
        if n - 2usize < mx { mx = n - 2usize }
    }
    var mn = minc
    if mn < 2usize { mn = 2usize }
    if mx < mn { mn = mx }
    let nq = mx - mn + 1usize
    var kc = ncl
    let o_ce0 = o_cl + n
    var best = -1.0f64
    var kq = mn
    let p2 = 2.0f64 / f64(nd)
    let (quot, e8) = mem.alloc[f64](a, nq)
    if e8 != ok { ret e8 }
    while kq <= mx {
        let i0 = math.pow64(f64(kq - 1usize), p2) * intra[kq - 1usize]
        let i1 = math.pow64(f64(kq), p2) * intra[kq]
        let i2 = math.pow64(f64(kq + 1usize), p2) * intra[kq + 1usize]
        var qv = (i0 - i1) / (i1 - i2)
        if qv < 0.0f64 { qv = 0.0f64 - qv }
        quot[kq - mn] = qv
        if qv > best {
            best = qv
            if ncl <= 1usize { kc = kq }
        }
        kq += 1usize
    }
    let (lab, e9) = mem.alloc[usize](a, n)
    if e9 != ok { ret e9 }
    let e10 = hc.cutree(a, &tr, n, kc, lab)
    if e10 != ok { ret e10 }
    let (cen, e11) = mem.alloc[f64](a, kc * nd)
    let (cnt, e12) = mem.alloc[f64](a, kc)
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    i = 0usize
    while i < kc * nd {
        cen[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < kc {
        cnt[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let c = lab[i] - 1usize
        cnt[c] += 1.0f64
        var k = 0usize
        while k < nd {
            cen[c * nd + k] += xs[i * nd + k]
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < kc {
        var k = 0usize
        while k < nd {
            cen[i * nd + k] = cen[i * nd + k] / cnt[i]
            k += 1usize
        }
        i += 1usize
    }
    if consol {
        let (ic1, e13) = mem.alloc[usize](a, n + 1usize)
        let (nc, e14) = mem.alloc[usize](a, kc + 1usize)
        let (wss, e15) = mem.alloc[f64](a, kc)
        if e13 != ok { ret e13 }
        if e14 != ok { ret e14 }
        if e15 != ok { ret e15 }
        let (flt, _it, e16) = km.kmns(a, xs, n, nd, cen, kc, iter_max, ic1, nc, wss)
        if e16 != ok { ret e16 }
        if flt == 1usize || flt == 3usize { ret Malformed }
        i = 0usize
        while i < n {
            lab[i] = ic1[i + 1usize]
            i += 1usize
        }
    }
    let (rk, e17) = mem.alloc[usize](a, kc)
    if e17 != ok { ret e17 }
    i = 0usize
    while i < kc {
        var r = 0usize
        var j = 0usize
        while j < kc {
            if cen[j * nd] < cen[i * nd] || (cen[j * nd] == cen[i * nd] && j < i) { r += 1usize }
            j += 1usize
        }
        rk[i] = r
        i += 1usize
    }
    i = 0usize
    while i < n {
        out[o_cl + perm[i]] = f64(rk[lab[i] - 1usize] + 1usize)
        i += 1usize
    }
    i = 0usize
    while i < kc {
        var k = 0usize
        while k < nd {
            out[o_ce0 + rk[i] * nd + k] = cen[i * nd + k]
            k += 1usize
        }
        i += 1usize
    }
    out[0usize] = f64(kc)
    out[1usize] = f64(nq)
    let o_q = o_ce0 + kc * nd
    i = 0usize
    while i < nq {
        out[o_q + i] = quot[i]
        i += 1usize
    }
    i = 0usize
    while i < m {
        out[o_q + nq + i] = gain[i]
        i += 1usize
    }
    ret ok
}
