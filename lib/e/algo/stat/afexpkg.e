// R afex aov_ez for one within factor (k levels) crossed with an optional between factor (g groups of equal size), Type III: the F tests, Greenhouse-Geisser and Huynh-Feldt corrected p values, generalized eta squared and Mauchly's sphericity test. Rows of the data are subjects: the group index (0-based) followed by the k responses.
//
// Not here: unequal group sizes, several within or between factors, covariates, and the Type II tests.

use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

// out: F_A, p_A, F_B, p_B, F_AB, p_AB, GG eps, HF eps, GG p_B, HF p_B, GG p_AB, HF p_AB, Mauchly W, Mauchly p, ges_A, ges_B, ges_AB (NaN for the terms a single group does not have)
fn rm_anova(a: *mem.Arena, data: []const f64, nsub: usize, g: usize, k: usize, out: []f64) -> err {
    let nan = 0.0f64 / 0.0f64
    let w = k + 1usize
    let (gm, e1) = mem.alloc[f64](a, g)
    let (cell, e2) = mem.alloc[f64](a, g * k)
    let (jm, e3) = mem.alloc[f64](a, k)
    let (ssp, e4) = mem.alloc[f64](a, k * k)
    let (sm, e5) = mem.alloc[f64](a, (k - 1usize) * (k - 1usize))
    let (cm, e6) = mem.alloc[f64](a, (k - 1usize) * k)
    let (tmp, e7) = mem.alloc[f64](a, (k - 1usize) * k)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var i = 0usize
    while i < out.len {
        out[i] = nan
        i += 1usize
    }
    let ng = f64(nsub / g)
    let nf = f64(nsub)
    let kf = f64(k)
    var gi = 0usize
    while gi < g {
        gm[gi] = 0.0f64
        gi += 1usize
    }
    i = 0usize
    while i < g * k {
        cell[i] = 0.0f64
        i += 1usize
    }
    var j = 0usize
    while j < k {
        jm[j] = 0.0f64
        j += 1usize
    }
    var grand = 0.0f64
    i = 0usize
    while i < nsub {
        let gr = usize(data[i * w])
        j = 0usize
        while j < k {
            let v = data[i * w + 1usize + j]
            cell[gr * k + j] += v / ng
            gm[gr] += v / (ng * kf)
            jm[j] += v / nf
            grand += v / (nf * kf)
            j += 1usize
        }
        i += 1usize
    }
    var ssa = 0.0f64
    gi = 0usize
    while gi < g {
        ssa += ng * kf * (gm[gi] - grand) * (gm[gi] - grand)
        gi += 1usize
    }
    var ssb = 0.0f64
    j = 0usize
    while j < k {
        ssb += nf * (jm[j] - grand) * (jm[j] - grand)
        j += 1usize
    }
    var ssab = 0.0f64
    gi = 0usize
    while gi < g {
        j = 0usize
        while j < k {
            let d = cell[gi * k + j] - gm[gi] - jm[j] + grand
            ssab += ng * d * d
            j += 1usize
        }
        gi += 1usize
    }
    var sseb = 0.0f64
    var ssew = 0.0f64
    i = 0usize
    while i < k * k {
        ssp[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nsub {
        let gr = usize(data[i * w])
        var mi = 0.0f64
        j = 0usize
        while j < k {
            mi += data[i * w + 1usize + j] / kf
            j += 1usize
        }
        sseb += kf * (mi - gm[gr]) * (mi - gm[gr])
        j = 0usize
        while j < k {
            let dj = data[i * w + 1usize + j] - cell[gr * k + j]
            var l = 0usize
            while l < k {
                let dl = data[i * w + 1usize + l] - cell[gr * k + l]
                ssp[j * k + l] += dj * dl
                l += 1usize
            }
            let r = data[i * w + 1usize + j] - mi - cell[gr * k + j] + gm[gr]
            ssew += r * r
            j += 1usize
        }
        i += 1usize
    }
    let dfeb = f64(nsub - g)
    let dfb = kf - 1.0f64
    let dfew = dfeb * dfb
    let dfa = f64(g) - 1.0f64
    let dfab = dfa * dfb
    let mseb = sseb / dfeb
    let msew = ssew / dfew
    if g > 1usize {
        out[0usize] = (ssa / dfa) / mseb
        out[1usize] = nb.pf(out[0usize], dfa, dfeb, false, false)
        out[4usize] = (ssab / dfab) / msew
        out[5usize] = nb.pf(out[4usize], dfab, dfew, false, false)
        out[14usize] = ssa / (ssa + sseb + ssew)
        out[16usize] = ssab / (ssab + sseb + ssew)
    }
    out[2usize] = (ssb / dfb) / msew
    out[3usize] = nb.pf(out[2usize], dfb, dfew, false, false)
    out[15usize] = ssb / (ssb + sseb + ssew)
    // Helmert contrasts, orthonormal
    var r = 0usize
    while r < k - 1usize {
        let nrm = math.sqrt[f64](f64((r + 1usize) * (r + 2usize)))
        var c = 0usize
        while c < k {
            var v = 0.0f64
            if c <= r { v = 1.0f64 / nrm }
            if c == r + 1usize { v = 0.0f64 - f64(r + 1usize) / nrm }
            cm[r * k + c] = v
            c += 1usize
        }
        r += 1usize
    }
    let p = k - 1usize
    r = 0usize
    while r < p {
        var c = 0usize
        while c < k {
            var s = 0.0f64
            var l = 0usize
            while l < k {
                s += cm[r * k + l] * ssp[l * k + c]
                l += 1usize
            }
            tmp[r * k + c] = s
            c += 1usize
        }
        r += 1usize
    }
    r = 0usize
    while r < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var l = 0usize
            while l < k {
                s += tmp[r * k + l] * cm[c * k + l]
                l += 1usize
            }
            sm[r * p + c] = s
            c += 1usize
        }
        r += 1usize
    }
    var tr = 0.0f64
    var tr2 = 0.0f64
    r = 0usize
    while r < p {
        tr += sm[r * p + r]
        var c = 0usize
        while c < p {
            tr2 += sm[r * p + c] * sm[c * p + r]
            c += 1usize
        }
        r += 1usize
    }
    let pf64 = f64(p)
    let gg = tr * tr / (pf64 * tr2)
    var hf = (dfeb + 1.0f64) * pf64 * gg - 2.0f64
    hf = hf / (pf64 * (dfeb - pf64 * gg))
    let hfu = hf
    if hf > 1.0f64 { hf = 1.0f64 }
    out[6usize] = gg
    out[7usize] = hfu
    out[8usize] = nb.pf(out[2usize], gg * dfb, gg * dfew, false, false)
    out[9usize] = nb.pf(out[2usize], hf * dfb, hf * dfew, false, false)
    if g > 1usize {
        out[10usize] = nb.pf(out[4usize], gg * dfab, gg * dfew, false, false)
        out[11usize] = nb.pf(out[4usize], hf * dfab, hf * dfew, false, false)
    }
    // Mauchly: det over the elimination of a copy of sm
    var det = 1.0f64
    r = 0usize
    while r < p {
        var piv = r
        var c = r + 1usize
        while c < p {
            if math.abs[f64](sm[c * p + r]) > math.abs[f64](sm[piv * p + r]) { piv = c }
            c += 1usize
        }
        if piv != r {
            var l = 0usize
            while l < p {
                let t = sm[r * p + l]
                sm[r * p + l] = sm[piv * p + l]
                sm[piv * p + l] = t
                l += 1usize
            }
            det = 0.0f64 - det
        }
        det *= sm[r * p + r]
        c = r + 1usize
        while c < p {
            let f = sm[c * p + r] / sm[r * p + r]
            var l = r
            while l < p {
                sm[c * p + l] -= f * sm[r * p + l]
                l += 1usize
            }
            c += 1usize
        }
        r += 1usize
    }
    let wm = det / math.pow[f64](tr / pf64, pf64)
    out[12usize] = wm
    if p >= 2usize {
        let n = dfeb
        let rho = 1.0f64 - (2.0f64 * pf64 * pf64 + pf64 + 2.0f64) / (6.0f64 * pf64 * n)
        let z = 0.0f64 - n * rho * math.log[f64](wm)
        let df = pf64 * (pf64 + 1.0f64) / 2.0f64 - 1.0f64
        let om = (pf64 + 2.0f64) * (pf64 - 1.0f64) * (pf64 - 2.0f64) * (2.0f64 * pf64 * pf64 * pf64 + 6.0f64 * pf64 * pf64 + 3.0f64 * kf + 2.0f64) / (288.0f64 * (n * pf64 * rho) * (n * pf64 * rho))
        out[13usize] = (1.0f64 - om) * nm.pchisq(z, df, false, false) + om * nm.pchisq(z, df + 4.0f64, false, false)
    }
    ret ok
}
