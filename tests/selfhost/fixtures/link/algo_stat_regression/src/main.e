// `e.algo.stat.regression`: Poisson rates and NB recoveries from Gamma-Poisson
// simulations, a matched conditional logistic recovery, an ordinal recovery
// from cumulative sampling, with every refusal. Each check exits with its own
// code.

use e.algo.rand
use e.algo.stat.regression
use e.io
use e.math
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    var r = rand.pcg64(31u64, 17u64)
    // 1: Poisson with beta = [0.7, 0.5], dose in {0, 1}, exposure 1..3.
    let (px, px_error) = mem.alloc[f64](a, 200usize)
    if px_error != ok { ret px_error }
    let (py, py_error) = mem.alloc[f64](a, 200usize)
    if py_error != ok { ret py_error }
    let (pe, pe_error) = mem.alloc[f64](a, 200usize)
    if pe_error != ok { ret pe_error }
    var i = 0usize
    while i < 200usize {
        let dose = f64(i % 2usize)
        px[i] = dose
        pe[i] = 1.0f64 + f64(i % 3usize)
        let mu = pe[i] * math.exp[f64](0.7f64 + 0.5f64 * dose)
        let limit = math.exp[f64](0.0f64 - mu)
        var draw = 0.0f64
        var mass = 1.0f64
        while mass > limit {
            mass *= rand.pcg64_f64(&r)
            draw += 1.0f64
        }
        py[i] = draw - 1.0f64
        i += 1usize
    }
    var pcoef: [2]f64 = zero
    var pcov: [4]f64 = zero
    var pscratch: [32]f64 = zero
    let (piters, pfit_error) = regression.poisson(px[..], py[..], pe[..], 200usize, 1usize, 0.0000000001f64, 100u32, pcoef[..], pcov[..], pscratch[..])
    if pfit_error != ok || piters == 0u32 { os.exit(1i32) }
    if !near(pcoef[0usize], 0.5f64, 0.15f64) || !near(pcoef[1usize], 0.7f64, 0.15f64) { os.exit(1i32) }
    if !(pcov[0usize] > 0.0f64) || !(pcov[3usize] > 0.0f64) { os.exit(1i32) }
    var bad_exposure: [200]f64 = zero
    let (_, exposure_bad) = regression.poisson(px[..], py[..], bad_exposure[..], 200usize, 1usize, 0.0000000001f64, 100u32, pcoef[..], pcov[..], pscratch[..])
    if exposure_bad != regression.Invalid { os.exit(1i32) }
    let (_, room_bad) = regression.poisson(px[..], py[..], pe[..], 200usize, 1usize, 0.0000000001f64, 100u32, pcoef[..1usize], pcov[..], pscratch[..])
    if room_bad != regression.TooSmall { os.exit(1i32) }

    // 2: negative-binomial with the same mean and theta = 3.
    i = 0usize
    while i < 200usize {
        let dose = f64(i % 2usize)
        let mu = pe[i] * math.exp[f64](0.7f64 + 0.5f64 * dose)
        let shape = 3.0f64
        let dd = shape - 1.0f64 / 3.0f64
        let cc = 1.0f64 / math.sqrt[f64](9.0f64 * dd)
        var lam = 0.0f64
        var shaped = false
        while !shaped {
            var u = 0.0f64
            var v = 0.0f64
            var s2 = 2.0f64
            while s2 >= 1.0f64 || s2 == 0.0f64 {
                u = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
                v = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
                s2 = u * u + v * v
            }
            let z = u * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2)
            let vv = (1.0f64 + cc * z) * (1.0f64 + cc * z) * (1.0f64 + cc * z)
            if vv > 0.0f64 {
                let uu = rand.pcg64_f64(&r)
                if math.log[f64](uu) < 0.5f64 * z * z + dd - dd * vv + dd * math.log[f64](vv) {
                    lam = dd * vv * mu / shape
                    shaped = true
                }
            }
        }
        let limit = math.exp[f64](0.0f64 - lam)
        var draw = 0.0f64
        var mass = 1.0f64
        while mass > limit {
            mass *= rand.pcg64_f64(&r)
            draw += 1.0f64
        }
        py[i] = draw - 1.0f64
        i += 1usize
    }
    var theta: [1]f64 = zero
    theta[0usize] = 1.0f64
    var ncoef: [2]f64 = zero
    var ncov: [4]f64 = zero
    var nscratch: [32]f64 = zero
    let (nouter, nfit_error) = regression.negbin(px[..], py[..], pe[..], 200usize, 1usize, 0.0000000001f64, 100u32, 100u32, theta[..], ncoef[..], ncov[..], nscratch[..])
    if nfit_error != ok || nouter == 0u32 { os.exit(2i32) }
    if !near(ncoef[0usize], 0.5f64, 0.2f64) || !near(ncoef[1usize], 0.7f64, 0.2f64) { os.exit(2i32) }
    if !(theta[0usize] > 1.0f64) || !(theta[0usize] < 8.0f64) { os.exit(2i32) }
    var bad_theta: [1]f64 = zero
    bad_theta[0usize] = 0.0f64 - 1.0f64
    let (_, theta_bad) = regression.negbin(px[..], py[..], pe[..], 200usize, 1usize, 0.0000000001f64, 100u32, 100u32, bad_theta[..], ncoef[..], ncov[..], nscratch[..])
    if theta_bad != regression.Invalid { os.exit(2i32) }

    // 3: conditional logistic on sixty 1:2 sets with beta = 1.2.
    let (cx, cx_error) = mem.alloc[f64](a, 180usize)
    if cx_error != ok { ret cx_error }
    let (cy, cy_error) = mem.alloc[u8](a, 180usize)
    if cy_error != ok { ret cy_error }
    let (cs, cs_error) = mem.alloc[usize](a, 180usize)
    if cs_error != ok { ret cs_error }
    var s = 0usize
    while s < 60usize {
        var j = 0usize
        while j < 3usize {
            var u = 0.0f64
            var v = 0.0f64
            var s2 = 2.0f64
            while s2 >= 1.0f64 || s2 == 0.0f64 {
                u = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
                v = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
                s2 = u * u + v * v
            }
            cx[s * 3usize + j] = u * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2)
            cy[s * 3usize + j] = 0u8
            cs[s * 3usize + j] = s
            j += 1usize
        }
        let w0 = math.exp[f64](1.2f64 * cx[s * 3usize])
        let w1 = math.exp[f64](1.2f64 * cx[s * 3usize + 1usize])
        let w2 = math.exp[f64](1.2f64 * cx[s * 3usize + 2usize])
        let pick = rand.pcg64_f64(&r) * (w0 + w1 + w2)
        if pick < w0 {
            cy[s * 3usize] = 1u8
        } else if pick < w0 + w1 {
            cy[s * 3usize + 1usize] = 1u8
        } else {
            cy[s * 3usize + 2usize] = 1u8
        }
        s += 1usize
    }
    var ccoef: [1]f64 = zero
    var ccov: [1]f64 = zero
    var cscratch: [16]f64 = zero
    let (citers, cfit_error) = regression.cond_logistic(cx[..], cy[..], cs[..], 180usize, 1usize, 0.0000000001f64, 100u32, ccoef[..], ccov[..], cscratch[..])
    if cfit_error != ok || citers == 0u32 { os.exit(3i32) }
    if !near(ccoef[0usize], 1.2f64, 0.4f64) { os.exit(3i32) }
    if !(ccov[0usize] > 0.0f64) { os.exit(3i32) }
    var case_at = 0usize
    while cy[case_at] != 1u8 {
        case_at += 1usize
    }
    cy[case_at] = 0u8
    let (_, nocase) = regression.cond_logistic(cx[..], cy[..], cs[..], 180usize, 1usize, 0.0000000001f64, 100u32, ccoef[..], ccov[..], cscratch[..])
    if nocase != regression.Invalid { os.exit(3i32) }
    cy[case_at] = 1u8

    // 4: ordinal with thresholds [-0.5, 0.8] and slope 1 over dose in {0, 1}.
    let (ox, ox_error) = mem.alloc[f64](a, 400usize)
    if ox_error != ok { ret ox_error }
    let (oy, oy_error) = mem.alloc[u8](a, 400usize)
    if oy_error != ok { ret oy_error }
    i = 0usize
    while i < 400usize {
        let dose = f64(i / 200usize)
        ox[i] = dose
        let c0 = 1.0f64 / (1.0f64 + math.exp[f64](0.5f64 + dose))
        let c1 = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - 0.8f64 + dose))
        let draw = rand.pcg64_f64(&r)
        if draw < c0 {
            oy[i] = 0u8
        } else if draw < c1 {
            oy[i] = 1u8
        } else {
            oy[i] = 2u8
        }
        i += 1usize
    }
    var thresholds: [2]f64 = zero
    var ocoef: [1]f64 = zero
    var ocov: [9]f64 = zero
    var oscratch: [128]f64 = zero
    let (oiters, ofit_error) = regression.ordinal_logistic(ox[..], oy[..], 400usize, 1usize, 3usize, 0.0000000001f64, 5000u32, thresholds[..], ocoef[..], ocov[..], oscratch[..])
    if ofit_error != ok || oiters == 0u32 { os.exit(4i32) }
    if !near(thresholds[0usize], 0.0f64 - 0.5f64, 0.3f64) || !near(thresholds[1usize], 0.8f64, 0.3f64) { os.exit(4i32) }
    if !near(ocoef[0usize], 1.0f64, 0.3f64) { os.exit(4i32) }
    if !(ocov[0usize] > 0.0f64) || !(ocov[8usize] > 0.0f64) { os.exit(4i32) }
    let (_, levels_bad) = regression.ordinal_logistic(ox[..], oy[..], 400usize, 1usize, 2usize, 0.0000000001f64, 100u32, thresholds[..1usize], ocoef[..], ocov[..], oscratch[..])
    if levels_bad != regression.Invalid { os.exit(4i32) }

    try io.print("algo stat regression ok\n")
    ret ok
}
