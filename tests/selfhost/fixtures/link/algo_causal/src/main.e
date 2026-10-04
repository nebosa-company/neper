// `e.algo.stat.causal`: propensity scores feeding Hajek IPTW and
// augmented doubly robust effects against references, hand-checkable
// units, a MICE mean imputation with determinism and interval checks, and
// the storage and degenerate cases. Each check exits with its own code.

use e.algo.rand
use e.algo.stat.causal as causal
use e.math
use e.mem
use e.ml.linear as linear
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

type MeanCtx = struct { col: usize }

fn mean_estimate(ctx: *MeanCtx, data: []const f64, n: usize, d: usize) -> (f64, f64) {
    if n < 2usize { ret (0.0f64, 1.0e300f64) }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += data[i * d + ctx.col] / f64(n)
        i += 1usize
    }
    var spread = 0.0f64
    i = 0usize
    while i < n {
        let t = data[i * d + ctx.col] - mean
        spread += t * t
        i += 1usize
    }
    ret (mean, spread / f64(n - 1usize) / f64(n))
}

fn main(a: *mem.Arena, args: []str) -> err {
    var y: [30]f64 = zero
    y[0usize] = 4.565664281554431f64
    y[1usize] = 5.06317733963714f64
    y[2usize] = 3.0589671749953835f64
    y[3usize] = 2.1595903790974385f64
    y[4usize] = 1.256590826671241f64
    y[5usize] = 3.7882963625430834f64
    y[6usize] = 4.775800180636238f64
    y[7usize] = 0.1697513438408642f64
    y[8usize] = 2.9174599340222542f64
    y[9usize] = 0.2123936005580025f64
    y[10usize] = 3.1460824396611113f64
    y[11usize] = 2.1208806612191493f64
    y[12usize] = 4.407827435854224f64
    y[13usize] = 3.1030301254005694f64
    y[14usize] = 2.8383680218113696f64
    y[15usize] = 1.9729772981957099f64
    y[16usize] = 2.951853720755496f64
    y[17usize] = 0.21002952681838938f64
    y[18usize] = 3.977270403491347f64
    y[19usize] = 4.337989659347858f64
    y[20usize] = 0.25479172024111785f64
    y[21usize] = 0.5628675513542232f64
    y[22usize] = 2.1227382026072155f64
    y[23usize] = 4.102238293093484f64
    y[24usize] = 0.0f64 - 1.317998715785323f64
    y[25usize] = 1.8175349250302686f64
    y[26usize] = 0.0f64 - 1.1490410371146669f64
    y[27usize] = 2.5340346539154877f64
    y[28usize] = 3.330815686895961f64
    y[29usize] = 2.2340218031933325f64
    var x1: [30]f64 = zero
    x1[0usize] = 0.03419276725318417f64
    x1[1usize] = 1.3597475403099617f64
    x1[2usize] = 1.2247210785859324f64
    x1[3usize] = 0.0f64 - 0.5103070767876675f64
    x1[4usize] = 0.0f64 - 0.2979695111064471f64
    x1[5usize] = 0.0f64 - 0.5273841930334252f64
    x1[6usize] = 0.5697263575719601f64
    x1[7usize] = 0.0f64 - 0.056064439045617594f64
    x1[8usize] = 0.7468856162565439f64
    x1[9usize] = 0.0f64 - 1.8473247989741095f64
    x1[10usize] = 1.5665487746995206f64
    x1[11usize] = 0.0f64 - 0.09643216015562055f64
    x1[12usize] = 0.6803784532741461f64
    x1[13usize] = 0.0f64 - 0.13656633397682774f64
    x1[14usize] = 0.0f64 - 0.3790985670748533f64
    x1[15usize] = 0.46311015859758675f64
    x1[16usize] = 0.824513527530113f64
    x1[17usize] = 0.0f64 - 0.20252987069345152f64
    x1[18usize] = 0.0f64 - 0.15278617857019708f64
    x1[19usize] = 0.685698610809258f64
    x1[20usize] = 0.0f64 - 0.8703406419471712f64
    x1[21usize] = 0.0f64 - 1.5143835037313955f64
    x1[22usize] = 0.39498186274953f64
    x1[23usize] = 0.0f64 - 0.6705658236878794f64
    x1[24usize] = 0.0f64 - 1.9203405901180286f64
    x1[25usize] = 0.0f64 - 0.8140536639453595f64
    x1[26usize] = 0.0f64 - 0.467597558892747f64
    x1[27usize] = 0.0f64 - 1.1932024774322612f64
    x1[28usize] = 0.0f64 - 1.4924638840630338f64
    x1[29usize] = 0.03663782694480509f64
    var x2: [30]f64 = zero
    x2[3usize] = 1.0f64
    x2[6usize] = 1.0f64
    x2[8usize] = 1.0f64
    x2[14usize] = 1.0f64
    x2[15usize] = 1.0f64
    x2[19usize] = 1.0f64
    x2[21usize] = 1.0f64
    x2[24usize] = 1.0f64
    x2[25usize] = 1.0f64
    var treated: [30]u8 = zero
    treated[0usize] = 1u8
    treated[2usize] = 1u8
    treated[3usize] = 1u8
    treated[5usize] = 1u8
    treated[6usize] = 1u8
    treated[9usize] = 1u8
    treated[11usize] = 1u8
    treated[12usize] = 1u8
    treated[13usize] = 1u8
    treated[14usize] = 1u8
    treated[16usize] = 1u8
    treated[18usize] = 1u8
    treated[19usize] = 1u8
    treated[20usize] = 1u8
    treated[23usize] = 1u8
    treated[25usize] = 1u8
    treated[27usize] = 1u8
    treated[28usize] = 1u8
    treated[29usize] = 1u8
    var x: [60]f64 = zero
    var i = 0usize
    while i < 30usize {
        x[i * 2usize] = x1[i]
        x[i * 2usize + 1usize] = x2[i]
        i += 1usize
    }
    var scores: [30]f64 = zero
    var pscratch: [18]f64 = zero

    // 1: propensity scores and the Hajek-weighted effect.
    let (ps_rounds, ps_error) = causal.propensity_scores(x[..], treated[..], 30usize, 2usize, 0.0000000001f64, 100u32, scores[..], pscratch[..])
    if ps_error != ok { os.exit(1i32) }
    if ps_rounds == 0u32 { os.exit(1i32) }
    if !near(scores[0usize], 0.6603161372243087f64, 0.000000001f64) { os.exit(1i32) }
    if !near(scores[1usize], 0.5492253912739561f64, 0.000000001f64) { os.exit(1i32) }
    if !near(scores[2usize], 0.5609770935286565f64, 0.000000001f64) { os.exit(1i32) }
    if !near(scores[29usize], 0.6601228309278934f64, 0.000000001f64) { os.exit(1i32) }
    let (ate, se, p_value, ate_error) = causal.iptw_ate(y[..], treated[..], scores[..], 30usize)
    if ate_error != ok { os.exit(1i32) }
    if !near(ate, 1.9907392972613982f64, 0.000000001f64) { os.exit(1i32) }
    if !near(se, 0.6067716297880965f64, 0.000000001f64) { os.exit(1i32) }
    if p_value < 0.0f64 || p_value > 1.0f64 { os.exit(1i32) }

    // 2: the doubly robust effect over per-arm least squares.
    var xa1: [38]f64 = zero
    var ya1: [19]f64 = zero
    var xa0: [22]f64 = zero
    var ya0: [11]f64 = zero
    var c1 = 0usize
    var c0 = 0usize
    i = 0usize
    while i < 30usize {
        if treated[i] == 1u8 {
            xa1[c1 * 2usize] = x1[i]
            xa1[c1 * 2usize + 1usize] = x2[i]
            ya1[c1] = y[i]
            c1 += 1usize
        } else {
            xa0[c0 * 2usize] = x1[i]
            xa0[c0 * 2usize + 1usize] = x2[i]
            ya0[c0] = y[i]
            c0 += 1usize
        }
        i += 1usize
    }
    var coef1: [3]f64 = zero
    var coef0: [3]f64 = zero
    var lscratch: [9]f64 = zero
    if linear.ols(xa1[..], ya1[..], 19usize, 2usize, coef1[..], lscratch[..]) != ok { os.exit(2i32) }
    if linear.ols(xa0[..], ya0[..], 11usize, 2usize, coef0[..], lscratch[..]) != ok { os.exit(2i32) }
    var mu1: [30]f64 = zero
    var mu0: [30]f64 = zero
    i = 0usize
    while i < 30usize {
        mu1[i] = linear.predict(x[..], 2usize, i, coef1[..])
        mu0[i] = linear.predict(x[..], 2usize, i, coef0[..])
        i += 1usize
    }
    let (dr, drse, drp, dr_error) = causal.doubly_robust(y[..], treated[..], scores[..], mu1[..], mu0[..], 30usize)
    if dr_error != ok { os.exit(2i32) }
    if !near(dr, 2.0501919722473696f64, 0.000000001f64) { os.exit(2i32) }
    if !near(drse, 0.3920547073568013f64, 0.000000001f64) { os.exit(2i32) }
    if drp < 0.0f64 || drp > 1.0f64 { os.exit(2i32) }

    // 3: hand-checkable units.
    var he: [4]f64 = zero
    he[0usize] = 4.0f64
    he[1usize] = 6.0f64
    he[2usize] = 2.0f64
    he[3usize] = 4.0f64
    var ht: [4]u8 = zero
    ht[0usize] = 1u8
    ht[1usize] = 1u8
    var hs: [4]f64 = zero
    hs[0usize] = 0.5f64
    hs[1usize] = 0.5f64
    hs[2usize] = 0.5f64
    hs[3usize] = 0.5f64
    let (hate, hse, _, hand_error) = causal.iptw_ate(he[..], ht[..], hs[..], 4usize)
    if hand_error != ok { os.exit(3i32) }
    if hate != 2.0f64 || hse != 1.0f64 { os.exit(3i32) }
    var hm1: [4]f64 = zero
    hm1[0usize] = 5.0f64
    hm1[1usize] = 5.0f64
    hm1[2usize] = 4.0f64
    hm1[3usize] = 4.0f64
    var hm0: [4]f64 = zero
    hm0[0usize] = 3.0f64
    hm0[1usize] = 3.0f64
    hm0[2usize] = 3.0f64
    hm0[3usize] = 3.0f64
    let (hdr, hdrse, _, dr_hand_error) = causal.doubly_robust(he[..], ht[..], hs[..], hm1[..], hm0[..], 4usize)
    if dr_hand_error != ok { os.exit(3i32) }
    if hdr != 1.5f64 { os.exit(3i32) }
    if !near(hdrse, 1.1902380714238083f64, 0.000000000001f64) { os.exit(3i32) }
    var pest: [3]f64 = zero
    pest[0usize] = 1.0f64
    pest[1usize] = 2.0f64
    pest[2usize] = 3.0f64
    var pvar: [3]f64 = zero
    pvar[0usize] = 0.1f64
    pvar[1usize] = 0.2f64
    pvar[2usize] = 0.3f64
    let (pq, pt, pdf, pool_error) = causal.mice_pool(pest[..], pvar[..], 3usize)
    if pool_error != ok { os.exit(3i32) }
    if pq != 2.0f64 { os.exit(3i32) }
    if !near(pt, 1.5333333333333332f64, 0.000000000001f64) { os.exit(3i32) }
    if !near(pdf, 2.6450000000000005f64, 0.000000000001f64) { os.exit(3i32) }

    // 4: multiple imputation of the outcome column, twice for determinism.
    var mdata: [90]f64 = zero
    var mmask: [90]u8 = zero
    mmask[2usize * 3usize] = 1u8
    mmask[3usize * 3usize] = 1u8
    mmask[6usize * 3usize] = 1u8
    mmask[7usize * 3usize] = 1u8
    mmask[12usize * 3usize] = 1u8
    mmask[20usize * 3usize] = 1u8
    mmask[25usize * 3usize] = 1u8
    mmask[27usize * 3usize] = 1u8
    i = 0usize
    while i < 30usize {
        mdata[i * 3usize] = y[i]
        mdata[i * 3usize + 1usize] = x1[i]
        mdata[i * 3usize + 2usize] = x2[i]
        i += 1usize
    }
    var completed1: [90]f64 = zero
    var completed2: [90]f64 = zero
    var pooled1: [3]f64 = zero
    var pooled2: [3]f64 = zero
    var mscratch: [112]f64 = zero
    var mctx = MeanCtx { col: 0usize }
    var rng1 = rand.pcg64(42u64, 54u64)
    if causal.mice[MeanCtx](mdata[..], mmask[..], 30usize, 3usize, 10u32, 3usize, &rng1, &mctx, mean_estimate, completed1[..], pooled1[..], mscratch[..]) != ok { os.exit(4i32) }
    var rng2 = rand.pcg64(42u64, 54u64)
    if causal.mice[MeanCtx](mdata[..], mmask[..], 30usize, 3usize, 10u32, 3usize, &rng2, &mctx, mean_estimate, completed2[..], pooled2[..], mscratch[..]) != ok { os.exit(4i32) }
    i = 0usize
    while i < 90usize {
        if completed1[i] != completed2[i] { os.exit(4i32) }
        i += 1usize
    }
    if pooled1[0usize] < 1.5f64 || pooled1[0usize] > 3.5f64 { os.exit(4i32) }
    if pooled1[0usize] != pooled2[0usize] { os.exit(4i32) }
    if pooled1[2usize] >= 1.0e300f64 { os.exit(4i32) }

    // 5: storage and degenerate cases.
    var badt: [30]u8 = zero
    i = 0usize
    while i < 30usize {
        badt[i] = treated[i]
        i += 1usize
    }
    badt[0usize] = 2u8
    let (_, ps_bad_error) = causal.propensity_scores(x[..], badt[..], 30usize, 2usize, 0.0000000001f64, 100u32, scores[..], pscratch[..])
    if ps_bad_error != causal.Invalid { os.exit(5i32) }
    let (_, ps_short_error) = causal.propensity_scores(x[..], treated[..], 30usize, 2usize, 0.0000000001f64, 100u32, scores[..], pscratch[..10usize])
    if ps_short_error != causal.TooSmall { os.exit(5i32) }
    var zeros: [30]f64 = zero
    let (_, _, _, iptw_zero_error) = causal.iptw_ate(y[..], treated[..], zeros[..], 30usize)
    if iptw_zero_error != causal.Invalid { os.exit(5i32) }
    var onesided: [4]u8 = zero
    onesided[0usize] = 1u8
    onesided[1usize] = 1u8
    onesided[2usize] = 1u8
    onesided[3usize] = 1u8
    let (_, _, _, iptw_onesided_error) = causal.iptw_ate(he[..], onesided[..], hs[..], 4usize)
    if iptw_onesided_error != causal.Invalid { os.exit(5i32) }
    let (_, _, _, iptw_empty_error) = causal.iptw_ate(y[..0usize], treated[..0usize], zeros[..0usize], 0usize)
    if iptw_empty_error != causal.Invalid { os.exit(5i32) }
    let (_, _, _, dr_short_error) = causal.doubly_robust(he[..3usize], ht[..3usize], hs[..3usize], hm1[..3usize], hm0[..3usize], 4usize)
    if dr_short_error != causal.TooSmall { os.exit(5i32) }
    let (_, _, _, pool_one_error) = causal.mice_pool(pest[..1usize], pvar[..1usize], 1usize)
    if pool_one_error != causal.Invalid { os.exit(5i32) }
    pvar[1usize] = 0.0f64 - 1.0f64
    let (_, _, _, pool_neg_error) = causal.mice_pool(pest[..], pvar[..], 3usize)
    if pool_neg_error != causal.Invalid { os.exit(5i32) }
    pvar[1usize] = 0.2f64
    ret ok
}
