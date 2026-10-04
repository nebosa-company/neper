// `e.algo.stat.mixed` random slopes: the log-Cholesky unpack inverts a known
// covariance, a random-slopes LMM recovers its fixed effects, covariance and
// within variance from a simulation with BLUPs near the true random effects,
// with the degenerate-input and short-storage refusals. Each check exits with
// its own code.

use e.algo.rand
use e.algo.stat.mixed
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
    // 1: the log-Cholesky of G = [[4, 2], [2, 3]] is [ln 2, 1, ln sqrt(2)].
    var theta: [3]f64 = zero
    theta[0usize] = 0.6931471805599453f64
    theta[1usize] = 1.0f64
    theta[2usize] = 0.3465735902799727f64
    var gmat: [4]f64 = zero
    if mixed.rs_unpack(theta[..], 2usize, gmat[..]) != ok { os.exit(1i32) }
    if !near(gmat[0usize], 4.0f64, 0.000000001f64) || !near(gmat[1usize], 2.0f64, 0.000000001f64) { os.exit(1i32) }
    if !near(gmat[2usize], 2.0f64, 0.000000001f64) || !near(gmat[3usize], 3.0f64, 0.000000001f64) { os.exit(1i32) }
    var short_g: [3]f64 = zero
    if mixed.rs_unpack(theta[..], 2usize, short_g[..]) != mixed.TooSmall { os.exit(1i32) }
    if mixed.rs_unpack(theta[..], 0usize, gmat[..]) != mixed.Invalid { os.exit(1i32) }

    // 2: two hundred subjects by five visits recover beta = [10, 2],
    // G = [[1, 0.3], [0.3, 0.5]] and sig2 = 1.
    var r = rand.pcg64(41u64, 7u64)
    let (yy, yy_error) = mem.alloc[f64](a, 1000usize)
    if yy_error != ok { ret yy_error }
    let (xx, xx_error) = mem.alloc[f64](a, 2000usize)
    if xx_error != ok { ret xx_error }
    let (zz, zz_error) = mem.alloc[f64](a, 2000usize)
    if zz_error != ok { ret zz_error }
    let (uu, uu_error) = mem.alloc[f64](a, 400usize)
    if uu_error != ok { ret uu_error }
    var counts: [200]usize = zero
    var g = 0usize
    while g < 200usize {
        counts[g] = 5usize
        var z0 = 0.0f64
        var z1 = 0.0f64
        var drew = false
        while !drew {
            var u = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
            var v = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
            let s2 = u * u + v * v
            if s2 < 1.0f64 && s2 > 0.0f64 {
                let scale = math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2)
                z0 = u * scale
                z1 = v * scale
                drew = true
            }
        }
        uu[g * 2usize] = z0
        uu[g * 2usize + 1usize] = 0.3f64 * z0 + 0.6403124237432849f64 * z1
        var t = 0usize
        while t < 5usize {
            var e = 0.0f64
            var made = false
            while !made {
                var u = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
                var v = 2.0f64 * rand.pcg64_f64(&r) - 1.0f64
                let s2 = u * u + v * v
                if s2 < 1.0f64 && s2 > 0.0f64 {
                    e = u * math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2)
                    made = true
                }
            }
            xx[(g * 5usize + t) * 2usize] = 1.0f64
            xx[(g * 5usize + t) * 2usize + 1usize] = f64(t)
            zz[(g * 5usize + t) * 2usize] = 1.0f64
            zz[(g * 5usize + t) * 2usize + 1usize] = f64(t)
            yy[g * 5usize + t] = 10.0f64 + 2.0f64 * f64(t) + uu[g * 2usize] + uu[g * 2usize + 1usize] * f64(t) + e
            t += 1usize
        }
        g += 1usize
    }
    var beta: [2]f64 = zero
    var beta_cov: [4]f64 = zero
    var variances: [4]f64 = zero
    var blups: [400]f64 = zero
    var scratch: [256]f64 = zero
    let (rounds, fit_error) = mixed.lmm_slopes(yy, xx, zz, 1000usize, 2usize, 2usize, counts[..], 200usize, beta[..], beta_cov[..], variances[..], blups[..], scratch[..])
    if fit_error != ok { os.exit(2i32) }
    if rounds == 0u32 { os.exit(2i32) }
    if !near(beta[0usize], 10.0f64, 0.5f64) || !near(beta[1usize], 2.0f64, 0.2f64) { os.exit(2i32) }
    if !near(variances[0usize], 1.0f64, 0.5f64) || !near(variances[1usize], 0.3f64, 0.35f64) { os.exit(2i32) }
    if !near(variances[2usize], 0.5f64, 0.35f64) || !near(variances[3usize], 1.0f64, 0.3f64) { os.exit(2i32) }
    var blup_err = 0.0f64
    g = 0usize
    while g < 200usize {
        var d0 = blups[g * 2usize] - uu[g * 2usize]
        if d0 < 0.0f64 { d0 = 0.0f64 - d0 }
        var d1 = blups[g * 2usize + 1usize] - uu[g * 2usize + 1usize]
        if d1 < 0.0f64 { d1 = 0.0f64 - d1 }
        blup_err += (d0 + d1) / 400.0f64
        g += 1usize
    }
    if blup_err > 0.6f64 { os.exit(2i32) }

    // 3: the refusals -- no random effects, an empty group, a short row
    // total, short outputs and short scratch.
    var bad_counts: [40]usize = zero
    bad_counts[0usize] = 0usize
    var bb = 1usize
    while bb < 40usize {
        bad_counts[bb] = 5usize
        bb += 1usize
    }
    let (_, noq) = mixed.lmm_slopes(yy, xx, zz, 1000usize, 2usize, 0usize, counts[..], 200usize, beta[..], beta_cov[..], variances[..], blups[..], scratch[..])
    if noq != mixed.Invalid { os.exit(3i32) }
    let (_, empty_group) = mixed.lmm_slopes(yy, xx, zz, 195usize, 2usize, 2usize, bad_counts[..], 40usize, beta[..], beta_cov[..], variances[..], blups[..], scratch[..])
    if empty_group != mixed.Invalid { os.exit(3i32) }
    var short_counts: [39]usize = zero
    var sc = 0usize
    while sc < 39usize {
        short_counts[sc] = 5usize
        sc += 1usize
    }
    let (_, short_total) = mixed.lmm_slopes(yy, xx, zz, 200usize, 2usize, 2usize, short_counts[..], 39usize, beta[..], beta_cov[..], variances[..], blups[..], scratch[..])
    if short_total != mixed.Invalid { os.exit(3i32) }
    var short_beta: [1]f64 = zero
    let (_, short_out) = mixed.lmm_slopes(yy, xx, zz, 200usize, 2usize, 2usize, counts[..], 40usize, short_beta[..], beta_cov[..], variances[..], blups[..], scratch[..])
    if short_out != mixed.TooSmall { os.exit(3i32) }
    var short_scratch: [8]f64 = zero
    let (_, short_work) = mixed.lmm_slopes(yy, xx, zz, 200usize, 2usize, 2usize, counts[..], 40usize, beta[..], beta_cov[..], variances[..], blups[..], short_scratch[..])
    if short_work != mixed.TooSmall { os.exit(3i32) }

    // 4: a binomial GLMM with beta = [-0.5, 1] and G = [[0.5, 0.1], [0.1,
    // 0.3]] recovers its fixed effects from sixty subjects by four visits.
    // PQL is documented to bias binary variance components on so few visits
    // per subject, so the covariance asserts positivity and finiteness only;
    // the Poisson panel below pins full recovery.
    var r2 = rand.pcg64(97u64, 13u64)
    let (by, by_error) = mem.alloc[f64](a, 240usize)
    if by_error != ok { ret by_error }
    let (bx, bx_error) = mem.alloc[f64](a, 480usize)
    if bx_error != ok { ret bx_error }
    let (bz, bz_error) = mem.alloc[f64](a, 480usize)
    if bz_error != ok { ret bz_error }
    var bcounts: [60]usize = zero
    var h = 0usize
    while h < 60usize {
        bcounts[h] = 4usize
        var z0 = 0.0f64
        var z1 = 0.0f64
        var drew = false
        while !drew {
            var u = 2.0f64 * rand.pcg64_f64(&r2) - 1.0f64
            var v = 2.0f64 * rand.pcg64_f64(&r2) - 1.0f64
            let s2 = u * u + v * v
            if s2 < 1.0f64 && s2 > 0.0f64 {
                let scale = math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2)
                z0 = u * scale
                z1 = v * scale
                drew = true
            }
        }
        let w0 = z0 * 0.7071067811865476f64
        let w1 = 0.1414213562373095f64 * z0 + 0.5291502622129182f64 * z1
        var t = 0usize
        while t < 4usize {
            bx[(h * 4usize + t) * 2usize] = 1.0f64
            bx[(h * 4usize + t) * 2usize + 1usize] = f64(t)
            bz[(h * 4usize + t) * 2usize] = 1.0f64
            bz[(h * 4usize + t) * 2usize + 1usize] = f64(t)
            let eta = 0.0f64 - 0.5f64 + 1.0f64 * f64(t) + w0 + w1 * f64(t)
            let prob = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
            if rand.pcg64_f64(&r2) < prob {
                by[h * 4usize + t] = 1.0f64
            } else {
                by[h * 4usize + t] = 0.0f64
            }
            t += 1usize
        }
        h += 1usize
    }
    var bbeta: [2]f64 = zero
    var bbeta_cov: [4]f64 = zero
    var bvariances: [4]f64 = zero
    var bblups: [120]f64 = zero
    var bscratch: [1024]f64 = zero
    let (brounds, bfit_error) = mixed.glmm_pql(by, bx, bz, 240usize, 2usize, 2usize, bcounts[..], 60usize, .Binomial, bbeta[..], bbeta_cov[..], bvariances[..], bblups[..], 0.0001f64, 100u32, bscratch[..])
    if bfit_error != ok || brounds == 0u32 { os.exit(4i32) }
    if !near(bbeta[0usize], 0.0f64 - 0.5f64, 0.5f64) || !near(bbeta[1usize], 1.0f64, 0.5f64) { os.exit(4i32) }
    if bvariances[0usize] <= 0.05f64 || bvariances[0usize] >= 3.0f64 { os.exit(4i32) }
    if !near(bvariances[2usize], 0.3f64, 0.7f64) { os.exit(4i32) }
    if bvariances[3usize] <= 0.3f64 || bvariances[3usize] >= 2.0f64 { os.exit(4i32) }

    // 5: a Poisson GLMM with beta = [3, 0.1] and G = [[0.4, 0.05], [0.05,
    // 0.2]] recovers fully at informative counts; the dispersion rides loose
    // since the working response inflates it.
    h = 0usize
    while h < 60usize {
        var z0 = 0.0f64
        var z1 = 0.0f64
        var drew = false
        while !drew {
            var u = 2.0f64 * rand.pcg64_f64(&r2) - 1.0f64
            var v = 2.0f64 * rand.pcg64_f64(&r2) - 1.0f64
            let s2 = u * u + v * v
            if s2 < 1.0f64 && s2 > 0.0f64 {
                let scale = math.sqrt[f64](0.0f64 - 2.0f64 * math.log[f64](s2) / s2)
                z0 = u * scale
                z1 = v * scale
                drew = true
            }
        }
        let w0 = z0 * 0.6324555320336759f64
        let w1 = 0.0790569415042095f64 * z0 + 0.440170f64 * z1
        var t = 0usize
        while t < 4usize {
            let eta = 3.0f64 + 0.1f64 * f64(t) + w0 + w1 * f64(t)
            let mu = math.exp[f64](eta)
            let limit = math.exp[f64](0.0f64 - mu)
            var draw = 0.0f64
            var mass = 1.0f64
            while mass > limit {
                mass *= rand.pcg64_f64(&r2)
                draw += 1.0f64
            }
            by[h * 4usize + t] = draw - 1.0f64
            t += 1usize
        }
        h += 1usize
    }
    var pbeta: [2]f64 = zero
    var pbeta_cov: [4]f64 = zero
    var pvariances: [4]f64 = zero
    var pblups: [120]f64 = zero
    var pscratch: [1024]f64 = zero
    let (prounds, pfit_error) = mixed.glmm_pql(by, bx, bz, 240usize, 2usize, 2usize, bcounts[..], 60usize, .Poisson, pbeta[..], pbeta_cov[..], pvariances[..], pblups[..], 0.0001f64, 100u32, pscratch[..])
    if pfit_error != ok || prounds == 0u32 { os.exit(5i32) }
    if !near(pbeta[0usize], 3.0f64, 0.25f64) || !near(pbeta[1usize], 0.1f64, 0.2f64) { os.exit(5i32) }
    if !near(pvariances[0usize], 0.4f64, 0.3f64) || !near(pvariances[1usize], 0.05f64, 0.15f64) { os.exit(5i32) }
    if !near(pvariances[2usize], 0.2f64, 0.15f64) { os.exit(5i32) }
    if pvariances[3usize] <= 0.5f64 || pvariances[3usize] >= 3.5f64 { os.exit(5i32) }

    // 6: the GLMM refusals -- a non-binary response, a negative count, no
    // outer rounds and short scratch.
    by[0usize] = 2.0f64
    let (_, not_binary) = mixed.glmm_pql(by, bx, bz, 240usize, 2usize, 2usize, bcounts[..], 60usize, .Binomial, bbeta[..], bbeta_cov[..], bvariances[..], bblups[..], 0.0001f64, 100u32, bscratch[..])
    if not_binary != mixed.Invalid { os.exit(6i32) }
    by[0usize] = 0.0f64 - 1.0f64
    let (_, neg_count) = mixed.glmm_pql(by, bx, bz, 240usize, 2usize, 2usize, bcounts[..], 60usize, .Poisson, pbeta[..], pbeta_cov[..], pvariances[..], pblups[..], 0.0001f64, 100u32, pscratch[..])
    if neg_count != mixed.Invalid { os.exit(6i32) }
    by[0usize] = 1.0f64
    let (_, no_rounds) = mixed.glmm_pql(by, bx, bz, 240usize, 2usize, 2usize, bcounts[..], 60usize, .Binomial, bbeta[..], bbeta_cov[..], bvariances[..], bblups[..], 0.0001f64, 0u32, bscratch[..])
    if no_rounds != mixed.Invalid { os.exit(6i32) }
    var tiny_work: [8]f64 = zero
    let (_, tiny_error) = mixed.glmm_pql(by, bx, bz, 240usize, 2usize, 2usize, bcounts[..], 60usize, .Binomial, bbeta[..], bbeta_cov[..], bvariances[..], bblups[..], 0.0001f64, 100u32, tiny_work[..])
    if tiny_error != mixed.TooSmall { os.exit(6i32) }

    try io.print("algo stat mixed ok\n")
    ret ok
}

