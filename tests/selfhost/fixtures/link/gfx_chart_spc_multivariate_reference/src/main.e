// The multivariate SPC charts and ANOM of e.gfx.chart against independent numpy and scipy computations
// (L071, D2255; scripts/chart_spc_multivariate_reference.py writes this file): Hotelling T-squared in both
// phases with the F and beta limits, the generalized-variance chart with its moment-normal limits, MEWMA with
// the finite-time covariance factor, and ANOM's decision limits. Every check has its own exit code.
use e.gfx.chart
use e.gfx.geometry
use e.mem
use e.os

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn close(got: f64, want: f64, tolerance: f64) -> bool {
    ret abs64(got - want) <= tolerance * (1.0f64 + abs64(want))
}

fn all_close(got: []const f64, want: []const f64, tolerance: f64) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if !close(got[i], want[i], tolerance) { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let hot_historical = [90]f64{ 4.4258f64, 8.5944f64, -3.5074f64, 4.0673f64, 7.8006f64, -1.7345f64, 4.692f64, 9.0484f64, -1.6683f64, 6.903f64, 10.587f64, -1.4571f64, 5.4229f64, 7.9813f64, -1.625f64, 4.9758f64, 10.1388f64, -3.8002f64, 5.1329f64, 12.3804f64, -1.0814f64, 4.2769f64, 8.4913f64, -4.0898f64, 6.1625f64, 9.2167f64, -2.654f64, 5.1463f64, 9.7171f64, -1.8754f64, 5.3083f64, 9.8488f64, -1.6624f64, 5.5439f64, 10.0371f64, -1.4121f64, 6.0259f64, 9.9789f64, -2.0209f64, 4.564f64, 9.8851f64, -1.4382f64, 4.9332f64, 9.3733f64, -1.2861f64, 5.681f64, 9.7098f64, -2.706f64, 4.6108f64, 9.1047f64, -3.4271f64, 5.5405f64, 10.529f64, -1.402f64, 5.0128f64, 12.1223f64, -1.7831f64, 5.7851f64, 10.2296f64, -1.1195f64, 5.298f64, 9.7282f64, -1.3916f64, 4.0052f64, 10.192f64, -2.2806f64, 4.1019f64, 10.0193f64, -2.7017f64, 5.9021f64, 11.1427f64, -1.8489f64, 3.5784f64, 10.5101f64, -2.7771f64, 3.6416f64, 8.9238f64, -1.2044f64, 1.5213f64, 4.7064f64, -2.8767f64, 6.3801f64, 11.7537f64, -1.0327f64, 4.426f64, 8.9946f64, -2.3399f64, 4.1405f64, 8.6626f64, -2.5617f64 }
    let hot_monitored = [36]f64{ 4.8444f64, 10.1936f64, -2.7837f64, 3.2208f64, 8.1648f64, -2.6804f64, 4.379f64, 10.4024f64, -2.2564f64, 5.5237f64, 10.3353f64, -0.8168f64, 5.0466f64, 8.3702f64, -1.5005f64, 7.4923f64, 5.256500000000001f64, -0.7730999999999999f64, 5.3346f64, 12.8523f64, -2.063f64, 4.1276f64, 9.6548f64, -1.431f64, 4.6669f64, 9.9908f64, -0.4032f64, 8.9084f64, 12.6074f64, -5.689f64, 7.0074f64, 12.7167f64, -0.1518f64, 4.7618f64, 11.0255f64, -0.2335f64 }
    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)
    var h_means: [3]f64 = zero
    var h_covariance: [9]f64 = zero
    var h_factor: [9]f64 = zero
    var h_residual: [3]f64 = zero
    var h_scores: [12]f64 = zero
    var h_points: [12]chart.Coord = zero
    var h_segments: [11]chart.Segment = zero
    var h_signals: [12]chart.Coord = zero
    var h_upper: [1]chart.Segment = zero
    var h_storage = chart.HotellingStorage { means: h_means[..], covariance: h_covariance[..], factor: h_factor[..], residual: h_residual[..], scores: h_scores[..], points: h_points[..], segments: h_segments[..], signals: h_signals[..], upper: h_upper[..] }
    let want_hot_mean = [3]f64{ 4.906866666666667f64, 9.64693333333333f64, -2.0921933333333333f64 }
    let want_hot_cov = [9]f64{ 1.0879151871264365f64, 0.9520151504597698f64, 0.3413748791954023f64, 0.9520151504597698f64, 2.066880482988505f64, 0.46238499735632194f64, 0.3413748791954023f64, 0.46238499735632194f64, 0.7194746123678162f64 }
    let want_hot_scores = [12]f64{ 1.2532507533097113f64, 2.618871752410178f64, 1.5007094454236618f64, 2.2775997410787907f64, 2.5150014992585024f64, 45.290858049734524f64, 7.055330020245454f64, 2.066256969550025f64, 5.141832045000188f64, 53.649921127255f64, 7.400981507208401f64, 6.775393846372923f64 }
    let (two_500, two_500_error) = chart.hotelling_t2_individuals(hot_monitored[..], 3usize, hot_historical[..], 0.05f64, bounds, &h_storage)
    if two_500_error != ok || !two_500.phase_two || two_500.historical_count != 30usize { os.exit(1) }
    if !all_close(two_500.means, want_hot_mean[..], 1e-09f64) || !all_close(two_500.covariance, want_hot_cov[..], 1e-09f64) { os.exit(2) }
    if !all_close(two_500.scores, want_hot_scores[..], 1e-08f64) { os.exit(3) }
    if !close(two_500.upper_limit, 9.856873463895356f64, 1e-09f64) { os.exit(4) }
    if two_500.signals.coords.len != 2usize { os.exit(5) }
    let (two_27, two_27_error) = chart.hotelling_t2_individuals(hot_monitored[..], 3usize, hot_historical[..], 0.0027f64, bounds, &h_storage)
    if two_27_error != ok || !two_27.phase_two || two_27.historical_count != 30usize { os.exit(6) }
    if !all_close(two_27.means, want_hot_mean[..], 1e-09f64) || !all_close(two_27.covariance, want_hot_cov[..], 1e-09f64) { os.exit(7) }
    if !all_close(two_27.scores, want_hot_scores[..], 1e-08f64) { os.exit(8) }
    if !close(two_27.upper_limit, 20.202525180612774f64, 1e-09f64) { os.exit(9) }
    if two_27.signals.coords.len != 2usize { os.exit(10) }
    var h1_scores: [30]f64 = zero
    var h1_points: [30]chart.Coord = zero
    var h1_segments: [29]chart.Segment = zero
    var h1_signals: [30]chart.Coord = zero
    var h1_storage = chart.HotellingStorage { means: h_means[..], covariance: h_covariance[..], factor: h_factor[..], residual: h_residual[..], scores: h1_scores[..], points: h1_points[..], segments: h1_segments[..], signals: h1_signals[..], upper: h_upper[..] }
    let (one, one_error) = chart.hotelling_t2_individuals(hot_historical[..], 3usize, hot_historical[..0usize], 0.05f64, bounds, &h1_storage)
    let want_hot1_scores = [30]f64{ 2.8953470984431493f64, 2.649645950148664f64, 0.6833179035179409f64, 4.21270278624062f64, 4.459524358628616f64, 5.561130651459018f64, 5.874927198467226f64, 5.668206018766419f64, 4.30406067405884f64, 0.11185787455120524f64, 0.3435663583849955f64, 0.8230202499579056f64, 1.5543345082938382f64, 1.1493449304390202f64, 1.258596922163133f64, 1.8743990978826675f64, 2.601656727332761f64, 0.7956980507455007f64, 4.614402883906056f64, 1.6189575017402003f64, 0.8309601681880016f64, 2.2013728744358794f64, 1.958190449515095f64, 1.2659628169415844f64, 5.435814376804587f64, 4.168677669047794f64, 14.20060258566493f64, 2.941238606735541f64, 0.2633955075653768f64, 0.6790871999734456f64 }
    if one_error != ok || one.phase_two || one.historical_count != 30usize || !all_close(one.scores, want_hot1_scores[..], 1e-08f64) || !close(one.upper_limit, 7.164127110028207f64, 1e-09f64) { os.exit(11) }
    if one.signals.coords.len != 1usize { os.exit(12) }
    let gv_one = [216]f64{ -0.5258f64, -0.7527f64, 0.4069f64, -0.0849f64, 1.6032f64, 0.5687f64, -2.4918f64, -1.9745f64, -1.345f64, 0.9712f64, -0.9676f64, 0.3039f64, -1.135f64, -1.8015f64, 0.0812f64, -1.09f64, 0.3578f64, -0.049f64, 0.167f64, 0.0344f64, -1.2287f64, 0.9196f64, 1.2071f64, -0.4469f64, 0.2329f64, 0.4803f64, -0.4339f64, 3.7567f64, 2.5068f64, 1.4582f64, 0.6771f64, 0.3345f64, -0.1648f64, -0.3718f64, -0.961f64, -0.2253f64, 0.54f64, 2.5423f64, -0.1152f64, 1.0876f64, 1.8569f64, 0.6179f64, -0.3046f64, 0.1759f64, -0.1286f64, 0.3633f64, -1.1002f64, -0.5391f64, 0.3133f64, -1.3312f64, 0.8617f64, -0.6409f64, 0.4814f64, -0.839f64, 1.3749f64, 0.8555f64, 0.834f64, -1.0381f64, 0.4516f64, -0.9181f64, 0.4197f64, 0.6509f64, -0.0916f64, -0.2774f64, 1.1012f64, 0.0229f64, 0.0781f64, -1.0466f64, -0.5977f64, 1.0516f64, 1.94f64, 0.1246f64, 1.0564f64, 0.2664f64, 0.6948f64, -0.4581f64, 1.7393f64, 0.3418f64, 1.0284f64, 0.0018f64, 0.7966f64, 0.0315f64, 1.253f64, 0.4315f64, 0.6045f64, -0.3684f64, 1.019f64, -1.7988f64, -1.8593f64, 0.3915f64, 1.1551f64, -0.2287f64, 0.6007f64, -0.3703f64, -0.6746f64, -0.5643f64, -1.7773f64, -1.5322f64, -1.5088f64, -0.8631f64, -0.4801f64, -0.1958f64, -0.8651f64, -1.2648f64, -1.1292f64, 0.9327f64, 0.8989f64, 0.1024f64, 1.3054f64, -0.6805f64, -1.6239f64, 0.2759f64, 0.8281f64, -0.887f64, 0.129f64, 0.4326f64, -0.8565f64, -1.4654f64, -3.7307f64, -0.4295f64, 0.6628f64, 0.8806f64, 1.4612f64, 0.1752f64, 1.3513f64, 0.6517f64, -0.6695f64, 0.2102f64, 0.5372f64, -0.9765f64, -0.1297f64, 0.3072f64, 0.1722f64, 0.0911f64, -0.6747f64, 1.0855f64, -0.1873f64, 0.547f64, -0.2788f64, 0.7303f64, -0.9702f64, 1.6083f64, 0.9903f64, 0.1978f64, 1.0789f64, 0.6358f64, 0.762f64, 0.4263f64, 2.0224f64, 1.352f64, 0.8024f64, -0.6212f64, 1.0039f64, 0.6138f64, 0.7477f64, 1.0743f64, -0.5397f64, -0.0388f64, 0.9177f64, -0.6536f64, -1.0587f64, -0.2719f64, -0.2981f64, -0.1739f64, 1.1059f64, 0.4269f64, -0.0775f64, 0.0424f64, 0.1003f64, 1.3625f64, -0.7591f64, 0.3769f64, -0.2513f64, 0.3549f64, 0.6911f64, -0.5366f64, -0.0139f64, 0.645f64, -1.5199f64, -1.2233f64, 1.1617f64, 0.0373f64, 1.4862f64, -0.9899f64, 0.0557f64, 0.9983f64, 0.5155f64, 0.7525f64, 1.1837f64, -1.2538f64, -0.4476f64, -0.4255f64, 0.9458f64, -0.2446f64, -0.8597f64, 0.1387f64, -1.4959f64, 0.3439f64, -0.7744f64, 0.947f64, 0.2663f64, 0.1266f64, 0.4164f64, 0.6243f64, -0.7427f64, -0.9373f64, 0.8804f64, -0.5315f64, 1.3383f64, -0.0636f64, -0.4317f64, 2.0512f64, 0.9416f64, 1.049f64, 2.4578f64, 0.3047f64 }
    let gv_two = [72]f64{ -0.0302f64, 0.2649f64, -0.499f64, 0.2654f64, -0.4767f64, 0.2298f64, -1.0442f64, -0.9151f64, 0.7685f64, 0.6229f64, -1.1621f64, -0.4462f64, 2.0824f64, 1.6478f64, 1.2982f64, 1.3843f64, 3.395f64, 1.1274f64, -0.0399f64, -0.6105f64, -0.9617f64, 0.5161f64, -0.3818f64, 0.4798f64, -1.2711f64, 1.5619f64, 1.2105f64, -0.2408f64, 1.3489f64, -0.3979f64, 0.5197f64, 2.379f64, 2.8876f64, -0.6825f64, -0.2421f64, -0.5778f64, -0.8585f64, -1.7691f64, 2.0189f64, 2.9777f64, 0.9495f64, 0.1105f64, 3.9826f64, 2.0699f64, 2.8451f64, 4.0189f64, 5.4023f64, 1.0668f64, 1.1657f64, 4.0116f64, -0.4765f64, -1.9945f64, 0.9943f64, 1.2976f64, -0.2349f64, -0.5007f64, 1.1057f64, -0.0629f64, 0.7712f64, 0.8316f64, -0.7788f64, 0.2953f64, -0.4491f64, -1.3037f64, 0.7312f64, -0.7657f64, -0.6211f64, -1.6085f64, -0.7025f64, -1.5211f64, -0.5709f64, -1.3022f64 }
    var g_covariance: [9]f64 = zero
    var g_pooled: [9]f64 = zero
    var g_factor: [9]f64 = zero
    var g_determinants: [16]f64 = zero
    var g_points: [16]chart.Coord = zero
    var g_segments: [15]chart.Segment = zero
    var g_signals: [16]chart.Coord = zero
    var g_upper: [1]chart.Segment = zero
    var g_lower: [1]chart.Segment = zero
    var g_center: [1]chart.Segment = zero
    var g_storage = chart.GeneralizedVarianceStorage { covariance: g_covariance[..], pooled: g_pooled[..], factor: g_factor[..], determinants: g_determinants[..], points: g_points[..], segments: g_segments[..], signals: g_signals[..], upper: g_upper[..], lower: g_lower[..], center: g_center[..] }
    let want_gv_dets = [16]f64{ 0.24374864117326617f64, 0.05105601217575662f64, 0.18386220235165907f64, 0.05245568717742258f64, 0.02427641728155826f64, 0.03154676010448309f64, 1.4872024056287958f64, 0.06481088339595041f64, 0.06160902458223038f64, 0.035463341921495965f64, 0.38340045099630643f64, 0.06832390281814818f64, 0.6757902126974653f64, 0.461459360668309f64, 30.72472653022017f64, 0.03779902266763283f64 }
    let want_gv_pooled = [9]f64{ 0.9313684511111111f64, 0.5290227554444445f64, 0.309236365f64, 0.5290227554444445f64, 1.4028520570555558f64, 0.275882355f64, 0.309236365f64, 0.275882355f64, 0.5406056945277777f64 }
    let (gv_one_sided, gv_one_sided_error) = chart.generalized_variance(gv_one[..], gv_two[..], 6usize, 3usize, 0.0027f64, false, bounds, &g_storage)
    if gv_one_sided_error != ok || gv_one_sided.phase_one_count != 12usize || gv_one_sided.phase_two_count != 4usize { os.exit(13) }
    if !all_close(gv_one_sided.determinants, want_gv_dets[..], 1e-08f64) || !all_close(gv_one_sided.pooled_covariance, want_gv_pooled[..], 1e-09f64) { os.exit(14) }
    if !close(gv_one_sided.b1, 0.48f64, 1e-12f64) || !close(gv_one_sided.b2, 0.5760000000000001f64, 1e-12f64) || !close(gv_one_sided.b3, 0.9505555555555555f64, 1e-12f64) { os.exit(15) }
    if !close(gv_one_sided.center_value, 0.22232240276921078f64, 1e-09f64) || !close(gv_one_sided.upper_limit, 1.2003111188484756f64, 1e-08f64) || !close(gv_one_sided.lower_limit, 0.0f64, 1e-08f64) { os.exit(16) }
    if gv_one_sided.signals.coords.len != 2usize { os.exit(17) }
    let (gv_two_sided, gv_two_sided_error) = chart.generalized_variance(gv_one[..], gv_two[..], 6usize, 3usize, 0.0027f64, true, bounds, &g_storage)
    if gv_two_sided_error != ok || gv_two_sided.phase_one_count != 12usize || gv_two_sided.phase_two_count != 4usize { os.exit(18) }
    if !all_close(gv_two_sided.determinants, want_gv_dets[..], 1e-08f64) || !all_close(gv_two_sided.pooled_covariance, want_gv_pooled[..], 1e-09f64) { os.exit(19) }
    if !close(gv_two_sided.b1, 0.48f64, 1e-12f64) || !close(gv_two_sided.b2, 0.5760000000000001f64, 1e-12f64) || !close(gv_two_sided.b3, 0.9505555555555555f64, 1e-12f64) { os.exit(20) }
    if !close(gv_two_sided.center_value, 0.22232240276921078f64, 1e-09f64) || !close(gv_two_sided.upper_limit, 1.2768820666329117f64, 1e-08f64) || !close(gv_two_sided.lower_limit, 0.0f64, 1e-08f64) { os.exit(21) }
    if gv_two_sided.signals.coords.len != 2usize { os.exit(22) }
    let want_mw_smoothed = [36]f64{ 4.894373333333333f64, 9.756266666666663f64, -2.2304946666666665f64, 4.5596586666666665f64, 9.43797333333333f64, -2.3204757333333332f64, 4.523526933333333f64, 9.630858666666665f64, -2.3076605866666666f64, 4.723561546666667f64, 9.771746933333333f64, -2.0094884693333332f64, 4.788169237333333f64, 9.491437546666665f64, -1.9076907754666668f64, 5.328995389866667f64, 8.644450037333332f64, -1.6807726203733333f64, 5.330116311893333f64, 9.486020029866665f64, -1.7572180962986668f64, 5.089613049514667f64, 9.519776023893332f64, -1.6919744770389333f64, 5.005070439611734f64, 9.613980819114666f64, -1.4342195816311465f64, 5.785736351689387f64, 10.212664655291732f64, -2.2851756653049176f64, 6.03006908135151f64, 10.713471724233386f64, -1.8585005322439339f64, 5.776415265081208f64, 10.77587737938671f64, -1.5335004257951472f64 }
    let want_mw_scores = [12]f64{ 1.253250753309712f64, 2.249541923898424f64, 3.0466723537063967f64, 1.2390122012804134f64, 1.04439223492588f64, 19.801049643995967f64, 4.888648502083397f64, 3.1782588269193583f64, 6.60031958245533f64, 9.778323027854016f64, 10.82453270180522f64, 8.137548121587741f64 }
    var m_means: [3]f64 = zero
    var m_covariance: [9]f64 = zero
    var m_factor: [9]f64 = zero
    var m_state: [3]f64 = zero
    var m_residual: [3]f64 = zero
    var m_smoothed: [36]f64 = zero
    var m_scores: [12]f64 = zero
    var m_points: [12]chart.Coord = zero
    var m_segments: [11]chart.Segment = zero
    var m_signals: [12]chart.Coord = zero
    var m_upper: [1]chart.Segment = zero
    var m_storage = chart.MewmaStorage { means: m_means[..], covariance: m_covariance[..], factor: m_factor[..], state: m_state[..], residual: m_residual[..], smoothed: m_smoothed[..], scores: m_scores[..], points: m_points[..], segments: m_segments[..], signals: m_signals[..], upper: m_upper[..] }
    let (mewma, mewma_error) = chart.mewma(hot_monitored[..], 3usize, hot_historical[..], 0.2f64, 11.5f64, bounds, &m_storage)
    if mewma_error != ok || !mewma.phase_two || mewma.historical_count != 30usize { os.exit(23) }
    if !all_close(mewma.smoothed, want_mw_smoothed[..], 1e-09f64) || !all_close(mewma.scores, want_mw_scores[..], 1e-08f64) { os.exit(24) }
    if mewma.signals.coords.len != 1usize { os.exit(25) }
    let anom_values = [28]f64{ 9.294f64, 10.566f64, 9.836f64, 10.093f64, 10.801f64, 10.566f64, 11.106f64, 10.415f64, 9.823f64, 10.809f64, 11.485f64, 10.654f64, 10.118f64, 9.834f64, 10.073f64, 9.603f64, 9.328f64, 9.585f64, 9.109f64, 9.537f64, 9.565f64, 10.986f64, 10.075f64, 11.461f64, 11.322f64, 10.575f64, 10.924f64, 10.92f64 }
    let anom_ids = [28]usize{ 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 2usize, 2usize, 2usize, 2usize, 2usize, 3usize, 3usize, 3usize, 3usize, 3usize, 3usize, 3usize, 3usize }
    var a_points: [4]chart.Coord = zero
    var a_signals: [4]chart.Coord = zero
    var a_upper: [4]chart.Segment = zero
    var a_lower: [4]chart.Segment = zero
    var a_center: [1]chart.Segment = zero
    var a_means: [4]f64 = zero
    var a_counts: [4]usize = zero
    var a_upper_limits: [4]f64 = zero
    var a_lower_limits: [4]f64 = zero
    var a_storage = chart.AnomStorage { points: a_points[..], signals: a_signals[..], upper: a_upper[..], lower: a_lower[..], center: a_center[..], means: a_means[..], counts: a_counts[..], upper_limits: a_upper_limits[..], lower_limits: a_lower_limits[..] }
    let (anom, anom_error) = chart.anom(anom_values[..], anom_ids[..], 4usize, 3.0f64, bounds, &a_storage)
    if anom_error != ok || !close(anom.grand_mean, 10.302249999999999f64, 1e-09f64) || !close(anom.pooled_sd, 0.5514014165943195f64, 1e-09f64) { os.exit(26) }
    if !close(anom.means[0], 10.192666666666668f64, 1e-09f64) || !close(anom.upper_limits[0], 10.900862569474892f64, 1e-09f64) || !close(anom.lower_limits[0], 9.703637430525106f64, 1e-09f64) || anom.counts[0] != 6usize || !close(anom.means[1], 10.479666666666667f64, 1e-09f64) || !close(anom.upper_limits[1], 10.756469382261724f64, 1e-09f64) || !close(anom.lower_limits[1], 9.848030617738274f64, 1e-09f64) || anom.counts[1] != 9usize || !close(anom.means[2], 9.4324f64, 1e-09f64) || !close(anom.upper_limits[2], 10.972734947631189f64, 1e-09f64) || !close(anom.lower_limits[2], 9.63176505236881f64, 1e-09f64) || anom.counts[2] != 5usize || !close(anom.means[3], 10.7285f64, 1e-09f64) || !close(anom.upper_limits[3], 10.79653806125578f64, 1e-09f64) || !close(anom.lower_limits[3], 9.807961938744217f64, 1e-09f64) || anom.counts[3] != 8usize { os.exit(27) }
    if anom.signals.coords.len != 1usize { os.exit(28) }
    let (written, write_error) = os.write(os.stdout(), "gfx chart spc multivariate reference ok\n")
    os.exit(0)
    ret ok
}
