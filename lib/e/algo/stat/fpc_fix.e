// R fpc: fixmahal (fixed point clusters on the Mahalanobis distance: method "fuzzy", "ml" or "classical", cgen "fixed", pointit, init.group), with fpmi, mahalconf, wfu,
// fpclusters and simmatrix. Matrices are row-major.
//
// Not here: cgen "auto", method "mcd" / "mve" (cov.rob subsampling), subset < n (a draw of the iteration points), and the collinear path of solvecov (coll is always FALSE).

use e.algo.stat.fpc as fp
use e.algo.stat.fpc_coord as fc
use e.algo.stat.fpc_extra as fx
use e.algo.stat.fpc_misc as fm
use e.math
use e.mem

error Malformed

// wfu(md, ca, ca2): the weight 1 up to ca, falling linearly to 0 at ca2
fn wfu1(md: f64, ca: f64, ca2: f64) -> f64 {
    let a1 = 1.0f64 / (ca - ca2)
    let a0 = (0.0f64 - a1) * ca2
    if md <= ca { ret 1.0f64 }
    if md <= ca2 { ret a1 * md + a0 }
    ret 0.0f64
}

// sseg(i, j) of fpc as a 0-based position of the packed triangle (i, j are 0-based)
fn sseg0(i: usize, j: usize) -> usize {
    if i >= j { ret (i + 1usize) * i / 2usize + j }
    ret (j + 1usize) * j / 2usize + i
}

fn dsum(v: []const f64, m: usize) -> f64 {
    var sh = 0.0f64
    var sl = 0.0f64
    var i = 0usize
    while i < m {
        let (h1, l1) = fp.dd_add(sh, sl, v[i], 0.0f64)
        sh = h1
        sl = l1
        i += 1usize
    }
    ret sh + sl
}

// fpmi: the fixed point iteration from the weights gv (updated); mode 0 fuzzy, 1 ml, 2 classical. mg, covg, md receive the last fit; the returned ca is cn
fn fpmi(a: *mem.Arena, dat: []const f64, n: usize, p: usize, gv: []f64, mode: usize, ca: f64, ca2: f64, maxit: usize, iter: f64, mg: []f64, covg: []f64, md: []f64) -> err {
    let (gva, e1) = mem.alloc[f64](a, n)
    let (cinv, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret Malformed }
    var i = 0usize
    while i < n {
        gva[i] = 0.0f64
        i += 1usize
    }
    var change = true
    var ir = 0usize
    while change {
        ir += 1usize
        if mode == 0usize {
            var cnt = 0usize
            i = 0usize
            while i < n {
                let df = gv[i] - gva[i]
                if df * df > iter { cnt += 1usize }
                i += 1usize
            }
            change = cnt > 0usize
        } else {
            change = false
            i = 0usize
            while i < n {
                if gv[i] != gva[i] { change = true }
                i += 1usize
            }
            // fpc's identical() sees the logical weights against the numeric start as different, so the first pass always has a successor
            if ir == 1usize { change = true }
        }
        if ir > maxit { change = false }
        i = 0usize
        while i < n {
            gva[i] = gv[i]
            i += 1usize
        }
        let e = fx.mahalanofix(a, dat, n, p, gv, mode == 0usize, mode == 2usize, md, mg, covg, cinv)
        if e != ok { ret e }
        i = 0usize
        while i < n {
            if mode == 0usize {
                gv[i] = wfu1(md[i], ca, ca2)
            } else {
                gv[i] = 0.0f64
                if md[i] <= ca { gv[i] = 1.0f64 }
            }
            i += 1usize
        }
    }
    ret ok
}

// mahalconf(x, no, startn, covall): the start weights (0/1) grown from the point no (0-based)
fn mahalconf(a: *mem.Arena, x: []const f64, n: usize, p: usize, no: usize, startn: usize, covall: []const f64, gv: []f64) -> err {
    let (cinv, e1) = mem.alloc[f64](a, p * p)
    let (md, e2) = mem.alloc[f64](a, n)
    let (om, e3) = mem.alloc[usize](a, n)
    let (mg, e4) = mem.alloc[f64](a, p)
    let (cg, e5) = mem.alloc[f64](a, p * p)
    let (ci2, e6) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret Malformed }
    let e7 = fp.lu_inverse(a, covall, p, cinv)
    if e7 != ok { ret e7 }
    let e8 = fc.mahal_rows(a, x, n, p, x[no * p..no * p + p], cinv, md)
    if e8 != ok { ret e8 }
    var i = 0usize
    while i < n {
        gv[i] = 0.0f64
        i += 1usize
    }
    order_into(md, n, om)
    i = 0usize
    while i < p + 1usize {
        gv[om[i]] = 1.0f64
        i += 1usize
    }
    var pn = p + 2usize
    while pn <= startn {
        let e9 = fx.mahalanofix(a, x, n, p, gv, false, false, md, mg, cg, ci2)
        if e9 != ok { ret e9 }
        order_into(md, n, om)
        var cnt = 0usize
        i = 0usize
        while i < n {
            if gv[i] != 0.0f64 { cnt += 1usize }
            i += 1usize
        }
        var j = 0usize
        while cnt < pn {
            if gv[om[j]] == 0.0f64 {
                gv[om[j]] = 1.0f64
                cnt += 1usize
            }
            j += 1usize
        }
        pn += 1usize
    }
    ret ok
}

// cov(x) of the n by p matrix
fn cov_all(a: *mem.Arena, x: []const f64, n: usize, p: usize, out: []f64) -> (usize, err) {
    let (cl, e1) = mem.alloc[usize](a, n)
    if e1 != ok { ret (0usize, Malformed) }
    var i = 0usize
    while i < n {
        cl[i] = 1usize
        i += 1usize
    }
    let (k, e2) = fp.cov_rows(a, x, n, p, cl, 1usize, out)
    ret (k, e2)
}

// order(v): the stable ascending order of the m values
fn order_into(v: []const f64, m: usize, o: []usize) {
    var i = 0usize
    while i < m {
        o[i] = i
        i += 1usize
    }
    i = 1usize
    while i < m {
        let t = o[i]
        var w = i
        while w > 0usize && v[o[w - 1usize]] > v[t] {
            o[w] = o[w - 1usize]
            w -= 1usize
        }
        o[w] = t
        i += 1usize
    }
}

// the state of fixmahal: nc fixed point clusters with their centres, covariances and weights, the counts found, the packed intersection matrix
type Fx = struct { nc: usize, tsc: usize, ncoll: usize, means: []f64, covs: []f64, glist: []f64, nfound: []f64, imat: []f64 }

// the part of fixmahal that registers a fixed point cluster found from the weights g with centre mg and covariance covg; returns the cluster number it matched or created (0-based)
fn register(a: *mem.Arena, st: *Fx, dat: []const f64, n: usize, p: usize, g: []const f64, mg: []const f64, covg: []const f64, mode: usize, ca: f64, ca2: f64, mnc: usize, ind_storage: bool) -> (usize, err) {
    var neu = true
    var cnum = 0usize
    var j = 0usize
    while j < st.nc {
        var s1 = 0.0f64
        var q = 0usize
        while q < p {
            let t = st.means[j * p + q] - mg[q]
            s1 += t * t
            q += 1usize
        }
        var s2 = 0.0f64
        q = 0usize
        while q < p * p {
            let t = st.covs[j * p * p + q] - covg[q]
            s2 += t * t
            q += 1usize
        }
        if s1 < 1.0e-6f64 && s2 < 1.0e-5f64 {
            neu = false
            cnum = j
        }
        j += 1usize
    }
    let ng = dsum(g, n)
    let (mn, e1) = mem.alloc[f64](a, n)
    let (gj, e2) = mem.alloc[f64](a, n)
    let (cinv, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret (0usize, Malformed) }
    if neu && ng >= f64(mnc) {
        let nc = st.nc
        st.nfound[nc] = 1.0f64
        var q = 0usize
        while q < p {
            st.means[nc * p + q] = mg[q]
            q += 1usize
        }
        q = 0usize
        while q < p * p {
            st.covs[nc * p * p + q] = covg[q]
            q += 1usize
        }
        q = 0usize
        while q < n {
            st.glist[nc * n + q] = g[q]
            q += 1usize
        }
        j = 0usize
        while j < nc {
            if ind_storage {
                q = 0usize
                while q < n {
                    gj[q] = st.glist[j * n + q]
                    q += 1usize
                }
            } else {
                let e4 = fp.lu_inverse(a, st.covs[j * p * p..(j + 1usize) * p * p], p, cinv)
                if e4 != ok { ret (0usize, e4) }
                let e5 = fc.mahal_rows(a, dat, n, p, st.means[j * p..j * p + p], cinv, mn)
                if e5 != ok { ret (0usize, e5) }
                q = 0usize
                while q < n {
                    if mode == 0usize {
                        gj[q] = wfu1(mn[q], ca, ca2)
                    } else {
                        gj[q] = 0.0f64
                        if mn[q] <= ca { gj[q] = 1.0f64 }
                    }
                    q += 1usize
                }
            }
            q = 0usize
            while q < n {
                mn[q] = g[q]
                if gj[q] < g[q] { mn[q] = gj[q] }
                q += 1usize
            }
            st.imat[sseg0(nc, j)] = dsum(mn, n)
            j += 1usize
        }
        st.imat[sseg0(nc, nc)] = ng
        st.nc = nc + 1usize
        cnum = nc
    }
    if ng < f64(mnc) { st.tsc += 1usize }
    if !neu { st.nfound[cnum] += 1.0f64 }
    // fpc answers nc, the last cluster, for a new weight vector too small to be kept
    if neu { cnum = st.nc - 1usize }
    ret (cnum, ok)
}

// fixmahal(dat, method, ca, ca2, pointit, startn, mnc, mer, distcut, maxit, iter, init.group, ind.storage): the fixed point clusters. ncmax bounds the clusters found.
// out: 0 nc, 1 tsc, 2 ncoll, 3 skc, 4 stn; then nfound[ncmax], er[ncmax], imatrix[ncmax * (ncmax + 1) / 2], smatrix[same], struc[ncmax], stfound[ncmax], ser[ncmax], sfpc[ncmax] (1-based),
// sto[ncmax] (1-based, the first stn_all entries), grto[ninit] (1-based), then means (ncmax by p), covs (ncmax blocks), g (ncmax by n). Use fx_len for the length.
fn fx_len(ncmax: usize, n: usize, p: usize, ninit: usize) -> usize { ret 5usize + 7usize * ncmax + ncmax * (ncmax + 1usize) + ninit + ncmax * p + ncmax * p * p + ncmax * n }

fn fixmahal(a: *mem.Arena, dat: []const f64, n: usize, p: usize, mode: usize, ca: f64, ca2: f64, pointit: bool, startn0: usize, mnc: usize, mer: f64, distcut: f64, maxit: usize, iter: f64, init: []const f64, ninit: usize, ind_storage: bool, ncmax: usize, out: []f64) -> err {
    var startn = startn0
    if startn > n { startn = n }
    let np = ncmax * (ncmax + 1usize) / 2usize
    let (means, e1) = mem.alloc[f64](a, ncmax * p)
    let (covs, e2) = mem.alloc[f64](a, ncmax * p * p)
    let (glist, e3) = mem.alloc[f64](a, ncmax * n)
    let (nfound, e4) = mem.alloc[f64](a, ncmax)
    let (imat, e5) = mem.alloc[f64](a, np)
    let (gv, e6) = mem.alloc[f64](a, n)
    let (mg, e7) = mem.alloc[f64](a, p)
    let (cg, e8) = mem.alloc[f64](a, p * p)
    let (md, e9) = mem.alloc[f64](a, n)
    let (covall, e10) = mem.alloc[f64](a, p * p)
    let (cl, e11) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret Malformed }
    var st: Fx = zero
    st.means = means
    st.covs = covs
    st.glist = glist
    st.nfound = nfound
    st.imat = imat
    var ncoll = 0usize
    var i = 0usize
    while i < out.len {
        out[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        gv[i] = 1.0f64
        i += 1usize
    }
    let ef = fpmi(a, dat, n, p, gv, mode, ca, ca2, maxit, iter, mg, cg, md)
    if ef != ok { ret ef }
    var q = 0usize
    while q < p {
        means[q] = mg[q]
        q += 1usize
    }
    q = 0usize
    while q < p * p {
        covs[q] = cg[q]
        q += 1usize
    }
    q = 0usize
    while q < n {
        glist[q] = gv[q]
        q += 1usize
    }
    nfound[0usize] = 1.0f64
    imat[0usize] = dsum(gv, n)
    st.nc = 1usize
    let grb = 5usize + 7usize * ncmax + ncmax * (ncmax + 1usize)
    if pointit {
        i = 0usize
        while i < n {
            cl[i] = 1usize
            i += 1usize
        }
        let (kk, ec) = fp.cov_rows(a, dat, n, p, cl, 1usize, covall)
        if ec != ok { ret ec }
        var ni = 0usize
        while ni < n {
            let mk = mem.mark(a)
            let em = mahalconf(a, dat, n, p, ni, startn, covall, gv)
            if em != ok { ret em }
            let ep = fpmi(a, dat, n, p, gv, mode, ca, ca2, maxit, iter, mg, cg, md)
            if ep != ok { ret ep }
            let (cn0, er) = register(a, &st, dat, n, p, gv, mg, cg, mode, ca, ca2, mnc, ind_storage)
            if er != ok { ret er }
            mem.reset(a, mk)
            ni += 1usize
        }
    }
    var gi = 0usize
    while gi < ninit {
        i = 0usize
        while i < n {
            gv[i] = init[gi * n + i]
            i += 1usize
        }
        let ep = fpmi(a, dat, n, p, gv, mode, ca, ca2, maxit, iter, mg, cg, md)
        if ep != ok { ret ep }
        let (cn0, er) = register(a, &st, dat, n, p, gv, mg, cg, mode, ca, ca2, mnc, ind_storage)
        if er != ok { ret er }
        out[grb + gi] = f64(cn0 + 1usize)
        gi += 1usize
    }
    let nc = st.nc
    let npc = nc * (nc + 1usize) / 2usize
    let (smat, e12) = mem.alloc[f64](a, np)
    let (comat, e13) = mem.alloc[f64](a, nc * nc)
    let (struc, e14) = mem.alloc[usize](a, nc)
    if e12 != ok || e13 != ok || e14 != ok { ret Malformed }
    if nc > 1usize {
        i = 0usize
        while i + 1usize < nc {
            smat[sseg0(i, i)] = imat[sseg0(i, i)]
            var j = i + 1usize
            while j < nc {
                smat[sseg0(i, j)] = 2.0f64 * imat[sseg0(i, j)] / (imat[sseg0(i, i)] + imat[sseg0(j, j)])
                j += 1usize
            }
            i += 1usize
        }
        smat[sseg0(nc - 1usize, nc - 1usize)] = imat[sseg0(nc - 1usize, nc - 1usize)]
        i = 0usize
        while i < nc * nc {
            comat[i] = 0.0f64
            i += 1usize
        }
        i = 0usize
        while i + 1usize < nc {
            var j = i + 1usize
            while j < nc {
                if smat[sseg0(i, j)] >= distcut {
                    comat[i * nc + j] = 1.0f64
                    comat[j * nc + i] = 1.0f64
                }
                j += 1usize
            }
            i += 1usize
        }
    } else {
        comat[0usize] = 1.0f64
        smat[0usize] = imat[0usize]
    }
    fm.con_comp(comat, nc, struc)
    var stn = 0usize
    i = 0usize
    while i < nc {
        if struc[i] > stn { stn = struc[i] }
        i += 1usize
    }
    let (tf, e15) = mem.alloc[f64](a, stn)
    let (maxf, e16) = mem.alloc[f64](a, stn)
    let (sfpc, e17) = mem.alloc[usize](a, stn)
    let (ser, e18) = mem.alloc[f64](a, stn)
    let (er2, e19) = mem.alloc[f64](a, nc)
    if e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok { ret Malformed }
    i = 0usize
    while i < stn {
        tf[i] = 0.0f64
        maxf[i] = 0.0f64
        sfpc[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < nc {
        er2[i] = nfound[i] / imat[sseg0(i, i)]
        let s = struc[i] - 1usize
        tf[s] += nfound[i]
        if er2[i] == maxf[s] && sfpc[s] > 0usize {
            if imat[sseg0(i, i)] < imat[sseg0(sfpc[s] - 1usize, sfpc[s] - 1usize)] { sfpc[s] = i + 1usize }
        }
        if er2[i] > maxf[s] {
            sfpc[s] = i + 1usize
            maxf[s] = er2[i]
        }
        i += 1usize
    }
    i = 0usize
    while i < stn {
        ser[i] = (tf[i] * f64(n)) / (imat[sseg0(sfpc[i] - 1usize, sfpc[i] - 1usize)] * f64(n))
        i += 1usize
    }
    var skc = stn
    var stn2 = 0usize
    i = 0usize
    while i < stn {
        if ser[i] >= mer { stn2 += 1usize }
        i += 1usize
    }
    skc = stn - stn2
    out[0usize] = f64(nc)
    out[1usize] = f64(st.tsc)
    out[2usize] = f64(ncoll)
    out[3usize] = f64(skc)
    out[4usize] = f64(stn2)
    var o = 5usize
    i = 0usize
    while i < ncmax {
        out[o + i] = 0.0f64
        if i < nc { out[o + i] = nfound[i] }
        i += 1usize
    }
    o += ncmax
    i = 0usize
    while i < nc {
        out[o + i] = er2[i]
        i += 1usize
    }
    o += ncmax
    i = 0usize
    while i < npc {
        out[o + i] = imat[i]
        i += 1usize
    }
    o += np
    i = 0usize
    while i < npc {
        out[o + i] = smat[i]
        i += 1usize
    }
    o += np
    i = 0usize
    while i < nc {
        out[o + i] = f64(struc[i])
        i += 1usize
    }
    o += ncmax
    i = 0usize
    while i < stn {
        out[o + i] = tf[i]
        out[o + ncmax + i] = ser[i]
        out[o + 2usize * ncmax + i] = f64(sfpc[i])
        i += 1usize
    }
    // sto = order(-ser): decreasing ser, ties by index
    let (sto, e20) = mem.alloc[usize](a, stn)
    if e20 != ok { ret Malformed }
    i = 0usize
    while i < stn {
        sto[i] = i
        i += 1usize
    }
    i = 1usize
    while i < stn {
        let t = sto[i]
        var w = i
        while w > 0usize && ser[sto[w - 1usize]] < ser[t] {
            sto[w] = sto[w - 1usize]
            w -= 1usize
        }
        sto[w] = t
        i += 1usize
    }
    i = 0usize
    while i < stn {
        out[o + 3usize * ncmax + i] = f64(sto[i] + 1usize)
        i += 1usize
    }
    let mb = grb + ninit
    i = 0usize
    while i < nc * p {
        out[mb + i] = means[i]
        i += 1usize
    }
    i = 0usize
    while i < nc * p * p {
        out[mb + ncmax * p + i] = covs[i]
        i += 1usize
    }
    i = 0usize
    while i < nc * n {
        out[mb + ncmax * p + ncmax * p * p + i] = glist[i]
        i += 1usize
    }
    ret ok
}
