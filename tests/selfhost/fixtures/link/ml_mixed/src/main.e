// `e.algo.stat.mixed`: GEE under three working correlations against
// statsmodels, a random-intercept LMM against statsmodels MixedLM
// (coefficients, standard errors, variance components, BLUPs), MMRM with
// unstructured covariance against an independent REML implementation on
// complete and dropout data, treatment contrasts, and the helper and error
// cases. Each check exits with its own code.

use e.algo.stat.mixed as mixed
use e.math
use e.mem
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn bit(on: bool) -> f64 {
    if on { ret 1.0f64 }
    ret 0.0f64
}

fn se_of(covariance: []const f64, d: usize, i: usize) -> f64 { ret math.sqrt[f64](covariance[i * d + i]) }

fn main(a: *mem.Arena, args: []str) -> err {
    var y: [36]f64 = zero
    y[0usize] = 10.300221721537449f64
    y[1usize] = 11.227338328666761f64
    y[2usize] = 12.110884345271705f64
    y[3usize] = 8.46274850279747f64
    y[4usize] = 11.014538660391372f64
    y[5usize] = 13.794610303348467f64
    y[6usize] = 8.788877277918463f64
    y[7usize] = 11.399194227923601f64
    y[8usize] = 12.766239185898465f64
    y[9usize] = 9.196029054089273f64
    y[10usize] = 11.597245276334204f64
    y[11usize] = 13.821800293255766f64
    y[12usize] = 7.929326782217684f64
    y[13usize] = 7.985719803457058f64
    y[14usize] = 10.097404803472926f64
    y[15usize] = 7.554826823575239f64
    y[16usize] = 8.022471473206217f64
    y[17usize] = 11.061182313471623f64
    y[18usize] = 10.001170359319115f64
    y[19usize] = 10.171341593128556f64
    y[20usize] = 14.649408408102433f64
    y[21usize] = 10.05510785152202f64
    y[22usize] = 10.91166310001332f64
    y[23usize] = 14.464045589484783f64
    y[24usize] = 8.016939866906434f64
    y[25usize] = 12.386675729718112f64
    y[26usize] = 13.018242431000138f64
    y[27usize] = 10.845363821448549f64
    y[28usize] = 11.877373521322074f64
    y[29usize] = 14.849272004481216f64
    y[30usize] = 10.196338746154439f64
    y[31usize] = 11.407501145481683f64
    y[32usize] = 15.208697202276385f64
    y[33usize] = 10.083443427961363f64
    y[34usize] = 14.989970794111445f64
    y[35usize] = 16.749942131786426f64
    var arm: [12]f64 = zero
    var s = 6usize
    while s < 12usize {
        arm[s] = 1.0f64
        s += 1usize
    }
    // The complete design: intercept, arm, two visit dummies and their
    // arm interactions, rows grouped by subject.
    var x: [216]f64 = zero
    var visit: [36]usize = zero
    var r = 0usize
    while r < 36usize {
        let subj = r / 3usize
        let v = r % 3usize
        let av = arm[subj]
        visit[r] = v
        x[r * 6usize] = 1.0f64
        x[r * 6usize + 1usize] = av
        x[r * 6usize + 2usize] = bit(v == 1usize)
        x[r * 6usize + 3usize] = bit(v == 2usize)
        x[r * 6usize + 4usize] = av * bit(v == 1usize)
        x[r * 6usize + 5usize] = av * bit(v == 2usize)
        r += 1usize
    }
    var counts: [12]usize = zero
    s = 0usize
    while s < 12usize {
        counts[s] = 3usize
        s += 1usize
    }
    var beta: [6]f64 = zero
    var covariance: [36]f64 = zero
    var scratch: [192]f64 = zero

    // 1: GEE under exchangeable, independence and AR(1) working correlation.
    let (exch_rounds, exch_error) = mixed.gee(y[..], x[..], 36usize, 6usize, counts[..], 12usize, .Exchangeable, beta[..], covariance[..], scratch[..])
    if exch_error != ok { os.exit(1i32) }
    if exch_rounds == 0u32 { os.exit(1i32) }
    if !near(beta[0usize], 8.70533836035593f64, 0.000001f64) { os.exit(1i32) }
    if !near(beta[1usize], 1.1610556518627237f64, 0.000001f64) { os.exit(1i32) }
    if !near(beta[2usize], 1.5024129346406054f64, 0.000001f64) { os.exit(1i32) }
    if !near(beta[3usize], 3.570015180430563f64, 0.000001f64) { os.exit(1i32) }
    if !near(beta[4usize], 0.5886140337699384f64, 0.000001f64) { os.exit(1i32) }
    if !near(beta[5usize], 1.3868587685393472f64, 0.000001f64) { os.exit(1i32) }
    if !near(se_of(covariance[..], 6usize, 0usize), 0.36423930046429914f64, 0.000001f64) { os.exit(1i32) }
    if !near(se_of(covariance[..], 6usize, 1usize), 0.5100311462249344f64, 0.000001f64) { os.exit(1i32) }
    if !near(se_of(covariance[..], 6usize, 2usize), 0.42911977320456723f64, 0.000001f64) { os.exit(1i32) }
    if !near(se_of(covariance[..], 6usize, 3usize), 0.5123328317624398f64, 0.000001f64) { os.exit(1i32) }
    if !near(se_of(covariance[..], 6usize, 4usize), 0.8637453843211199f64, 0.000001f64) { os.exit(1i32) }
    if !near(se_of(covariance[..], 6usize, 5usize), 0.6164630450786794f64, 0.000001f64) { os.exit(1i32) }
    let (_, indep_error) = mixed.gee(y[..], x[..], 36usize, 6usize, counts[..], 12usize, .Independence, beta[..], covariance[..], scratch[..])
    if indep_error != ok { os.exit(1i32) }
    if !near(beta[5usize], 1.3868587685393472f64, 0.000001f64) { os.exit(1i32) }
    if !near(se_of(covariance[..], 6usize, 5usize), 0.6164630450786799f64, 0.000001f64) { os.exit(1i32) }
    let (_, ar1_error) = mixed.gee(y[..], x[..], 36usize, 6usize, counts[..], 12usize, .Ar1, beta[..], covariance[..], scratch[..])
    if ar1_error != ok { os.exit(1i32) }
    if !near(beta[5usize], 1.386858768539347f64, 0.000001f64) { os.exit(1i32) }
    if !near(se_of(covariance[..], 6usize, 5usize), 0.6164630450786807f64, 0.000001f64) { os.exit(1i32) }

    // 2: the random-intercept fit with variance components and BLUPs.
    var variances: [2]f64 = zero
    var blups: [12]f64 = zero
    var rscratch: [100]f64 = zero
    let (ri_rounds, ri_error) = mixed.lmm_intercept(y[..], x[..], 36usize, 6usize, counts[..], 12usize, beta[..], covariance[..], variances[..], blups[..], rscratch[..])
    if ri_error != ok { os.exit(2i32) }
    if ri_rounds == 0u32 { os.exit(2i32) }
    if !near(beta[0usize], 8.705338360355942f64, 0.000001f64) { os.exit(21i32) }
    if !near(beta[5usize], 1.3868587685393463f64, 0.000001f64) { os.exit(21i32) }
    if !near(variances[0usize], 0.9838278492553041f64, 0.0001f64) { os.exit(23i32) }
    if !near(variances[1usize], 0.9013474816030266f64, 0.0001f64) { os.exit(23i32) }
    if !near(se_of(covariance[..], 6usize, 0usize), 0.5605317907812087f64, 0.0001f64) { os.exit(22i32) }
    if !near(se_of(covariance[..], 6usize, 5usize), 0.7751763161169752f64, 0.0001f64) { os.exit(22i32) }
    if !near(blups[0usize], 0.6256125410751179f64, 0.0001f64) { os.exit(24i32) }
    if !near(blups[4usize], 0.0f64 - 1.321699510935839f64, 0.0001f64) { os.exit(24i32) }
    if !near(blups[11usize], 1.3217714162095562f64, 0.0001f64) { os.exit(24i32) }

    // 3: MMRM with unstructured covariance on complete and dropout data.
    var mbeta: [6]f64 = zero
    var mcov: [36]f64 = zero
    var un: [9]f64 = zero
    var mscratch: [150]f64 = zero
    let (full_rounds, full_error) = mixed.mmrm_un(y[..], x[..], 36usize, 6usize, counts[..], 12usize, visit[..], 3usize, mbeta[..], mcov[..], un[..], mscratch[..])
    if full_error != ok { os.exit(3i32) }
    if full_rounds == 0u32 { os.exit(3i32) }
    if !near(mbeta[0usize], 8.70533836035594f64, 0.000001f64) { os.exit(3i32) }
    if !near(mbeta[5usize], 1.3868587685393503f64, 0.000001f64) { os.exit(3i32) }
    if !near(un[0usize], 0.9364743556019468f64, 0.0001f64) { os.exit(3i32) }
    if !near(un[4usize], 2.8726691212144604f64, 0.0001f64) { os.exit(3i32) }
    if !near(un[8usize], 1.8464019819231776f64, 0.0001f64) { os.exit(3i32) }
    if !near(un[1usize], 0.5616707908808865f64, 0.0001f64) { os.exit(3i32) }
    if !near(un[5usize], 1.6824510805650512f64, 0.0001f64) { os.exit(3i32) }
    var ym: [34]f64 = zero
    var xm: [204]f64 = zero
    var visitm: [34]usize = zero
    var countsm: [12]usize = zero
    var kept = 0usize
    r = 0usize
    while r < 36usize {
        if r != 8usize && r != 25usize {
            ym[kept] = y[r]
            visitm[kept] = visit[r]
            var j = 0usize
            while j < 6usize {
                xm[kept * 6usize + j] = x[r * 6usize + j]
                j += 1usize
            }
            kept += 1usize
        }
        r += 1usize
    }
    s = 0usize
    while s < 12usize {
        countsm[s] = 3usize
        s += 1usize
    }
    countsm[2usize] = 2usize
    countsm[8usize] = 2usize
    let (miss_rounds, miss_error) = mixed.mmrm_un(ym[..], xm[..], 34usize, 6usize, countsm[..], 12usize, visitm[..], 3usize, mbeta[..], mcov[..], un[..], mscratch[..])
    if miss_error != ok { os.exit(3i32) }
    if miss_rounds == 0u32 { os.exit(3i32) }
    if !near(mbeta[3usize], 3.632729710418662f64, 0.000001f64) { os.exit(3i32) }
    if !near(mbeta[4usize], 0.0f64 - 0.11001944681943505f64, 0.000001f64) { os.exit(3i32) }
    if !near(mbeta[5usize], 1.3241442385512436f64, 0.000001f64) { os.exit(3i32) }
    if !near(un[0usize], 0.9364743735669434f64, 0.0001f64) { os.exit(3i32) }
    if !near(un[4usize], 4.034743125759829f64, 0.0001f64) { os.exit(3i32) }
    if !near(un[8usize], 1.9329566558314573f64, 0.0001f64) { os.exit(3i32) }

    // 4: the visit-2 treatment contrast on the dropout fit, plus hand checks.
    var weights: [6]f64 = zero
    weights[5usize] = 1.0f64
    let (est, se, p_value, contrast_error) = mixed.mixed_contrast(mbeta[..], mcov[..], 6usize, weights[..])
    if contrast_error != ok { os.exit(4i32) }
    if !near(est, 1.3241442385512436f64, 0.000001f64) { os.exit(4i32) }
    if !near(se, 0.7038409754580774f64, 0.0001f64) { os.exit(4i32) }
    if !near(p_value, 0.05992953492410835f64, 0.0001f64) { os.exit(4i32) }
    var hbeta: [2]f64 = zero
    hbeta[0usize] = 2.0f64
    hbeta[1usize] = 0.0f64 - 1.0f64
    var hcov: [4]f64 = zero
    hcov[0usize] = 1.0f64
    hcov[1usize] = 0.5f64
    hcov[2usize] = 0.5f64
    hcov[3usize] = 2.0f64
    var hl: [2]f64 = zero
    hl[0usize] = 1.0f64
    hl[1usize] = 1.0f64
    let (hest, hse, hp, hand_error) = mixed.mixed_contrast(hbeta[..], hcov[..], 2usize, hl[..])
    if hand_error != ok { os.exit(4i32) }
    if hest != 1.0f64 || hse != 2.0f64 { os.exit(4i32) }
    if !near(hp, 0.6170750774519738f64, 0.000000001f64) { os.exit(4i32) }
    let (wp, wp_error) = mixed.wald_p(1.96f64, 1.0f64)
    if wp_error != ok { os.exit(4i32) }
    if !near(wp, 0.04999579029644087f64, 0.000000001f64) { os.exit(4i32) }

    // 5: storage and degenerate cases.
    let (_, gee_short_error) = mixed.gee(y[..], x[..], 36usize, 6usize, counts[..], 12usize, .Exchangeable, beta[..], covariance[..], scratch[..10usize])
    if gee_short_error != mixed.TooSmall { os.exit(5i32) }
    var badvisit: [36]usize = zero
    var w = 0usize
    while w < 36usize {
        badvisit[w] = visit[w]
        w += 1usize
    }
    badvisit[2usize] = 9usize
    let (_, bad_visit_error) = mixed.mmrm_un(y[..], x[..], 36usize, 6usize, counts[..], 12usize, badvisit[..], 3usize, mbeta[..], mcov[..], un[..], mscratch[..])
    if bad_visit_error != mixed.Invalid { os.exit(5i32) }
    badvisit[2usize] = 1usize
    let (_, dup_visit_error) = mixed.mmrm_un(y[..], x[..], 36usize, 6usize, counts[..], 12usize, badvisit[..], 3usize, mbeta[..], mcov[..], un[..], mscratch[..])
    if dup_visit_error != mixed.Invalid { os.exit(5i32) }
    var badcounts: [12]usize = zero
    s = 0usize
    while s < 12usize {
        badcounts[s] = 3usize
        s += 1usize
    }
    badcounts[0usize] = 2usize
    let (_, bad_counts_error) = mixed.lmm_intercept(y[..], x[..], 36usize, 6usize, badcounts[..], 12usize, beta[..], covariance[..], variances[..], blups[..], rscratch[..])
    if bad_counts_error != mixed.Invalid { os.exit(5i32) }
    let (_, _, _, short_contrast_error) = mixed.mixed_contrast(hbeta[..0usize], hcov[..], 2usize, hl[..])
    if short_contrast_error != mixed.TooSmall { os.exit(5i32) }
    let (_, empty_wald_error) = mixed.wald_p(1.0f64, 0.0f64)
    if empty_wald_error != mixed.Invalid { os.exit(5i32) }

    // 6: the GLS algebra at fixed variances, isolating the optimizer.
    var fxvx: [36]f64 = zero
    var fxvy: [6]f64 = zero
    var fctx = mixed.RiCtx { y: y[..], x: x[..], n: 36usize, d: 6usize, counts: counts[..], groups: 12usize, xvx: fxvx[..], xvy: fxvy[..] }
    let (fld, fld_error) = mixed.ri_fit_given(&fctx, 0.9838278492553041f64, 0.9013474816030266f64)
    if fld_error != ok { os.exit(6i32) }
    if !near(fld, 22.161350247841867f64, 0.000001f64) { os.exit(6i32) }
    if !near(fxvy[0usize], 8.705338360355928f64, 0.000001f64) { os.exit(6i32) }
    var otheta: [2]f64 = zero
    otheta[0usize] = 0.0f64 - 0.016304347179206865f64
    otheta[1usize] = 0.0f64 - 0.10386443356581135f64
    if !near(mixed.ri_objective(&fctx, otheta[..]), 53.64883112006111f64, 0.00001f64) { os.exit(6i32) }
    ret ok
}
