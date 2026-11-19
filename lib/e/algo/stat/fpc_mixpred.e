// R fpc: mixpredictive (the prediction strength of a merged normal mixture, under set.seed) and the "predictive" choice of the number of merged clusters of
// mergenormals. The mixtures are mclustBIC fits with the number of components fixed; the merge is mergenormals(method = "demp", numberstop). Matrices are
// row-major here (the mclust fits are column-major and converted).

use e.algo.rand.r as rg
use e.algo.stat.fpc as fp
use e.algo.stat.fpc_coord as fc
use e.algo.stat.fpc_ridge as fr
use e.algo.stat.mclustfit as mf
use e.mem

error Malformed

// mixpredictive(xdata, Gcomp, Gmix, M): predcorr gets the M values, the mean is returned. x is n by p row-major; models are the mclust model indices of mclustBIC.
fn mixpredictive(a: *mem.Arena, g: *rg.Rng, x: []const f64, n: usize, p: usize, gcomp: usize, gmix: usize, mm: usize, models: []const usize, predcorr: []f64) -> (f64, err) {
    let nf0 = n / 2usize
    let nf1 = n - nf0
    let nm = models.len
    var l = 0usize
    while l < mm {
        let mark = mem.mark(a)
        let (sm, e0) = rg.sample_int(a, g, i64(n), i64(n), false)
        if e0 != ok { ret (0.0f64, e0) }
        let (lab, e1) = mem.alloc[usize](a, 2usize * n)
        let (cpr, e2) = mem.alloc[usize](a, 2usize * n)
        if e1 != ok || e2 != ok { ret (0.0f64, Malformed) }
        var h = 0usize
        while h < 2usize {
            var nh = nf0
            var off = 0usize
            var no = nf1
            var offo = nf0
            if h == 1usize {
                nh = nf1
                off = nf0
                no = nf0
                offo = 0usize
            }
            let (xc, f1) = mem.alloc[f64](a, nh * p)
            let (xr, f2) = mem.alloc[f64](a, nh * p)
            let (xo, f3) = mem.alloc[f64](a, no * p)
            let (res, f4) = mem.alloc[f64](a, 6usize + nm + 2usize * nh + nh * gcomp + gcomp + p * gcomp + gcomp * p * p + nm)
            if f1 != ok || f2 != ok || f3 != ok || f4 != ok { ret (0.0f64, Malformed) }
            var r = 0usize
            while r < nh {
                let row = usize(sm[off + r]) - 1usize
                var j = 0usize
                while j < p {
                    xc[j * nh + r] = x[row * p + j]
                    xr[r * p + j] = x[row * p + j]
                    j += 1usize
                }
                r += 1usize
            }
            r = 0usize
            while r < no {
                let row = usize(sm[offo + r]) - 1usize
                var j = 0usize
                while j < p {
                    xo[r * p + j] = x[row * p + j]
                    j += 1usize
                }
                r += 1usize
            }
            let e3 = mf.mclust_run(a, xc, nh, p, gcomp, gcomp, models, res)
            if e3 != ok { ret (0.0f64, e3) }
            let off_cl = 6usize + nm
            let off_z = off_cl + 2usize * nh
            let off_pro = off_z + nh * gcomp
            let off_mu = off_pro + gcomp
            let off_sg = off_mu + p * gcomp
            let (zz, g1) = mem.alloc[f64](a, nh * gcomp)
            let (pro0, g2) = mem.alloc[f64](a, gcomp)
            let (probs, g3) = mem.alloc[f64](a, gcomp)
            let (mu, g4) = mem.alloc[f64](a, gcomp * p)
            let (sg, g5) = mem.alloc[f64](a, gcomp * p * p)
            let (mu0, g6) = mem.alloc[f64](a, gcomp * p)
            let (sg0, g7) = mem.alloc[f64](a, gcomp * p * p)
            let (map, g8) = mem.alloc[usize](a, gcomp)
            let (vals, g9) = mem.alloc[f64](a, gcomp + 2usize)
            if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok || g6 != ok || g7 != ok || g8 != ok || g9 != ok { ret (0.0f64, Malformed) }
            var q = 0usize
            while q < nh * gcomp {
                // column-major n by G to row-major
                let rr = q % nh
                let cc = q / nh
                zz[rr * gcomp + cc] = res[off_z + q]
                q += 1usize
            }
            q = 0usize
            while q < gcomp {
                pro0[q] = res[off_pro + q]
                probs[q] = res[off_pro + q]
                q += 1usize
            }
            q = 0usize
            while q < gcomp * p {
                mu[q] = res[off_mu + q]
                mu0[q] = res[off_mu + q]
                q += 1usize
            }
            q = 0usize
            while q < gcomp * p * p {
                sg[q] = res[off_sg + q]
                sg0[q] = res[off_sg + q]
                q += 1usize
            }
            let (nv, e4) = fp.merge_bhat(a, xr, nh, p, gcomp, probs, mu, sg, zz, 0.0f64, map, vals, true, gmix)
            if e4 != ok { ret (0.0f64, e4) }
            // the labels of this half under the merged clustering
            r = 0usize
            while r < nh {
                lab[h * n + r] = map[usize(res[off_cl + r]) - 1usize]
                r += 1usize
            }
            // the densities of the other half under each merged cluster; the survivor of a group is its smallest component number
            let (dv, e5) = mem.alloc[f64](a, no * gmix)
            if e5 != ok { ret (0.0f64, Malformed) }
            var k = 0usize
            while k < gmix {
                var surv = gcomp
                var gs = 0usize
                var psum = 0.0f64
                var c = 0usize
                while c < gcomp {
                    if map[c] == k + 1usize {
                        if surv == gcomp { surv = c }
                        gs += 1usize
                        psum += pro0[c]
                    }
                    c += 1usize
                }
                r = 0usize
                while r < no {
                    var dsum = 0.0f64
                    c = 0usize
                    while c < gcomp {
                        if map[c] == k + 1usize {
                            let dd = fr.dens(a, xo[r * p..r * p + p], mu0[c * p..c * p + p], sg0[c * p * p..(c + 1usize) * p * p], p)
                            if gs == 1usize {
                                dsum += dd
                            } else {
                                dsum += (pro0[c] / psum) * dd
                            }
                        }
                        c += 1usize
                    }
                    dv[r * gmix + k] = probs[surv] * dsum
                    r += 1usize
                }
                k += 1usize
            }
            r = 0usize
            while r < no {
                var best = 0usize
                k = 1usize
                while k < gmix {
                    if dv[r * gmix + k] > dv[r * gmix + best] { best = k }
                    k += 1usize
                }
                cpr[(1usize - h) * n + r] = best + 1usize
                r += 1usize
            }
            h += 1usize
        }
        var pm0 = 0.0f64
        var pm1 = 0.0f64
        h = 0usize
        while h < 2usize {
            var nh = nf0
            if h == 1usize { nh = nf1 }
            var mn = 0.0f64
            var k = 0usize
            while k < gmix {
                var nik = 0.0f64
                var ssq = 0.0f64
                var c = 1usize
                while c <= gmix {
                    var ct = 0.0f64
                    var r = 0usize
                    while r < nh {
                        if lab[h * n + r] == k + 1usize && cpr[h * n + r] == c { ct += 1.0f64 }
                        r += 1usize
                    }
                    ssq += ct * ct - ct
                    nik += ct
                    c += 1usize
                }
                var psk = 1.0f64
                if nik > 1.0f64 { psk = ssq / (nik * (nik - 1.0f64)) }
                if k == 0usize || psk < mn { mn = psk }
                k += 1usize
            }
            if h == 0usize { pm0 = mn } else { pm1 = mn }
            h += 1usize
        }
        var two: [2]f64 = zero
        two[0usize] = pm0
        two[1usize] = pm1
        let pv = fc.r_mean(two[0usize..2usize], 2usize)
        mem.reset(a, mark)
        predcorr[l] = pv
        l += 1usize
    }
    ret (fc.r_mean(predcorr, mm), ok)
}

// mergenormals(method = "predictive", cutoff, M) on the mclust fit of x with gcomp components: predvalues gets the gcomp values (index q - 1 for q merged clusters, 1 for one),
// map the mergedtonumbers of the final demp merge to the chosen number; the chosen number is returned
fn predictive(a: *mem.Arena, g: *rg.Rng, x: []const f64, n: usize, p: usize, gcomp: usize, cutoff: f64, mm: usize, models: []const usize, predvalues: []f64, map: []usize, clus: []usize) -> (usize, err) {
    let nm = models.len
    let (xc, e1) = mem.alloc[f64](a, n * p)
    let (res, e2) = mem.alloc[f64](a, 6usize + nm + 2usize * n + n * gcomp + gcomp + p * gcomp + gcomp * p * p + nm)
    let (pc, e3) = mem.alloc[f64](a, mm)
    if e1 != ok || e2 != ok || e3 != ok { ret (0usize, Malformed) }
    var r = 0usize
    while r < n {
        var j = 0usize
        while j < p {
            xc[j * n + r] = x[r * p + j]
            j += 1usize
        }
        r += 1usize
    }
    let e4 = mf.mclust_run(a, xc, n, p, gcomp, gcomp, models, res)
    if e4 != ok { ret (0usize, e4) }
    var q = 0usize
    while q < gcomp {
        predvalues[q] = 1.0f64
        q += 1usize
    }
    q = gcomp
    while q >= 2usize {
        let (mp0, e5) = mixpredictive(a, g, x, n, p, gcomp, q, mm, models, pc)
        if e5 != ok { ret (0usize, e5) }
        predvalues[q - 1usize] = mp0
        q -= 1usize
    }
    var gopt = 1usize
    q = 1usize
    while q <= gcomp {
        if predvalues[q - 1usize] > cutoff { gopt = q }
        q += 1usize
    }
    let off_cl = 6usize + nm
    let off_z = off_cl + 2usize * n
    let off_pro = off_z + n * gcomp
    let off_mu = off_pro + gcomp
    let off_sg = off_mu + p * gcomp
    let (zz, f1) = mem.alloc[f64](a, n * gcomp)
    let (probs, f2) = mem.alloc[f64](a, gcomp)
    let (mu, f3) = mem.alloc[f64](a, gcomp * p)
    let (sg, f4) = mem.alloc[f64](a, gcomp * p * p)
    let (vals, f5) = mem.alloc[f64](a, gcomp + 2usize)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok { ret (0usize, Malformed) }
    q = 0usize
    while q < n * gcomp {
        zz[(q % n) * gcomp + q / n] = res[off_z + q]
        q += 1usize
    }
    q = 0usize
    while q < gcomp {
        probs[q] = res[off_pro + q]
        q += 1usize
    }
    q = 0usize
    while q < gcomp * p {
        mu[q] = res[off_mu + q]
        q += 1usize
    }
    q = 0usize
    while q < gcomp * p * p {
        sg[q] = res[off_sg + q]
        q += 1usize
    }
    let (nv, e6) = fp.merge_bhat(a, x, n, p, gcomp, probs, mu, sg, zz, 0.0f64, map, vals, true, gopt)
    if e6 != ok { ret (0usize, e6) }
    r = 0usize
    while r < n {
        clus[r] = map[usize(res[off_cl + r]) - 1usize]
        r += 1usize
    }
    ret (gopt, ok)
}
