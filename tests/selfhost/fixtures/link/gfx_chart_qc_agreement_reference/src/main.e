// The QC and agreement extensions against numpy and scipy (L097, D2265;
// scripts/qc_agreement_reference.py writes this file): the Levey-Jennings Westgard rules and lines, Lin's
// concordance correlation (definition, r * Cb, Fisher-z interval) and its agreement plot, the symmetry plot,
// and the Box-Cox profile (scipy's boxcox_llf at every grid lambda, the maximiser, the interpolated interval).
// Every check has its own exit code.
use e.algo.stat
use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem
use e.os

fn zero_f64() -> f64 { ret 0.0f64 }

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn closed(got: f64, want: f64) -> bool {
    ret abs64(got - want) <= 1e-9f64 * (1.0f64 + abs64(want))
}

fn same(a: f32, b: f32) -> bool { ret abs64(f64(a) - f64(b)) <= 0.001f64 }

fn closef(got: f32, want: f64) -> bool {
    ret abs64(f64(got) - want) <= 0.0006f64 * (1.0f64 + abs64(want))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(14.0, 22.0, 300.0, 170.0)
    let qc_values = [44]f64{ 100.855f64, 100.0929f64, 97.5967f64, 100.306f64, 99.4279f64, 109.0f64, 98.8527f64, 100.1349f64, 99.8973f64, 99.9542f64, 104.6f64, 105.2f64, 101.0f64, 100.7454f64, 101.0057f64, 105.0f64, 95.2f64, 100.1033f64, 98.5902f64, 98.5706f64, 102.6f64, 103.2f64, 102.4f64, 103.8f64, 99.4622f64, 98.7278f64, 99.7084f64, 100.3984f64, 100.2368f64, 100.5773f64, 100.8f64, 101.2f64, 100.6f64, 101.6f64, 101.0f64, 100.4f64, 101.4f64, 101.8f64, 100.7f64, 100.9f64, 99.511f64, 100.5689f64, 101.3412f64, 99.6337f64 }
    var qc_points: [44]chart.Coord = zero
    var qc_trace: [43]chart.Segment = zero
    var qc_limits: [7]chart.Segment = zero
    var qc_signals: [44]chart.Coord = zero
    var qc_flags: [44]u8 = zero
    let (qc, qc_error) = chart.levey_jennings(qc_values[..], 100.0, 2.0, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])
    if qc_error != ok || qc.flagged != 8usize || qc.signals.coords.len != 8usize || qc.trace.segments.len != 43usize || qc.limits.segments.len != 7usize { os.exit(1) }
    if qc_flags[0] != 0u8 || qc_flags[1] != 0u8 || qc_flags[2] != 0u8 || qc_flags[3] != 0u8 || qc_flags[4] != 0u8 || qc_flags[5] != 1u8 || qc_flags[6] != 0u8 || qc_flags[7] != 0u8 || qc_flags[8] != 0u8 || qc_flags[9] != 0u8 || qc_flags[10] != 0u8 || qc_flags[11] != 2u8 { os.exit(2) }
    if qc_flags[12] != 0u8 || qc_flags[13] != 0u8 || qc_flags[14] != 0u8 || qc_flags[15] != 0u8 || qc_flags[16] != 4u8 || qc_flags[17] != 0u8 || qc_flags[18] != 0u8 || qc_flags[19] != 0u8 || qc_flags[20] != 0u8 || qc_flags[21] != 0u8 || qc_flags[22] != 0u8 || qc_flags[23] != 8u8 { os.exit(3) }
    if qc_flags[24] != 0u8 || qc_flags[25] != 0u8 || qc_flags[26] != 0u8 || qc_flags[27] != 0u8 || qc_flags[28] != 0u8 || qc_flags[29] != 0u8 || qc_flags[30] != 0u8 || qc_flags[31] != 0u8 || qc_flags[32] != 0u8 || qc_flags[33] != 0u8 || qc_flags[34] != 0u8 || qc_flags[35] != 0u8 { os.exit(4) }
    if qc_flags[36] != 16u8 || qc_flags[37] != 16u8 || qc_flags[38] != 16u8 || qc_flags[39] != 16u8 || qc_flags[40] != 0u8 || qc_flags[41] != 0u8 || qc_flags[42] != 0u8 || qc_flags[43] != 0u8 { os.exit(5) }
    if !closef(qc.y_limit, 4.5) { os.exit(6) }
    if !closef(qc_points[0].x, 14.0000) || !closef(qc_points[0].y, 98.9250) || !closef(qc_points[1].x, 20.9767) || !closef(qc_points[1].y, 106.1226) || !closef(qc_points[2].x, 27.9535) || !closef(qc_points[2].y, 129.6978) || !closef(qc_points[3].x, 34.9302) || !closef(qc_points[3].y, 104.1100) || !closef(qc_points[4].x, 41.9070) || !closef(qc_points[4].y, 112.4032) || !closef(qc_points[5].x, 48.8837) || !closef(qc_points[5].y, 22.0000) { os.exit(7) }
    if !closef(qc_points[6].x, 55.8605) || !closef(qc_points[6].y, 117.8356) || !closef(qc_points[7].x, 62.8372) || !closef(qc_points[7].y, 105.7259) || !closef(qc_points[8].x, 69.8140) || !closef(qc_points[8].y, 107.9699) || !closef(qc_points[9].x, 76.7907) || !closef(qc_points[9].y, 107.4326) || !closef(qc_points[10].x, 83.7674) || !closef(qc_points[10].y, 63.5556) || !closef(qc_points[11].x, 90.7442) || !closef(qc_points[11].y, 57.8889) { os.exit(8) }
    if !closef(qc_points[12].x, 97.7209) || !closef(qc_points[12].y, 97.5556) || !closef(qc_points[13].x, 104.6977) || !closef(qc_points[13].y, 99.9601) || !closef(qc_points[14].x, 111.6744) || !closef(qc_points[14].y, 97.5017) || !closef(qc_points[15].x, 118.6512) || !closef(qc_points[15].y, 59.7778) || !closef(qc_points[16].x, 125.6279) || !closef(qc_points[16].y, 152.3333) || !closef(qc_points[17].x, 132.6047) || !closef(qc_points[17].y, 106.0244) { os.exit(9) }
    if !closef(qc_points[18].x, 139.5814) || !closef(qc_points[18].y, 120.3148) || !closef(qc_points[19].x, 146.5581) || !closef(qc_points[19].y, 120.4999) || !closef(qc_points[20].x, 153.5349) || !closef(qc_points[20].y, 82.4444) || !closef(qc_points[21].x, 160.5116) || !closef(qc_points[21].y, 76.7778) || !closef(qc_points[22].x, 167.4884) || !closef(qc_points[22].y, 84.3333) || !closef(qc_points[23].x, 174.4651) || !closef(qc_points[23].y, 71.1111) { os.exit(10) }
    if !closef(qc_points[24].x, 181.4419) || !closef(qc_points[24].y, 112.0792) || !closef(qc_points[25].x, 188.4186) || !closef(qc_points[25].y, 119.0152) || !closef(qc_points[26].x, 195.3953) || !closef(qc_points[26].y, 109.7540) || !closef(qc_points[27].x, 202.3721) || !closef(qc_points[27].y, 103.2373) || !closef(qc_points[28].x, 209.3488) || !closef(qc_points[28].y, 104.7636) || !closef(qc_points[29].x, 216.3256) || !closef(qc_points[29].y, 101.5477) { os.exit(11) }
    if !closef(qc_points[30].x, 223.3023) || !closef(qc_points[30].y, 99.4444) || !closef(qc_points[31].x, 230.2791) || !closef(qc_points[31].y, 95.6667) || !closef(qc_points[32].x, 237.2558) || !closef(qc_points[32].y, 101.3333) || !closef(qc_points[33].x, 244.2326) || !closef(qc_points[33].y, 91.8889) || !closef(qc_points[34].x, 251.2093) || !closef(qc_points[34].y, 97.5556) || !closef(qc_points[35].x, 258.1860) || !closef(qc_points[35].y, 103.2222) { os.exit(12) }
    if !closef(qc_points[36].x, 265.1628) || !closef(qc_points[36].y, 93.7778) || !closef(qc_points[37].x, 272.1395) || !closef(qc_points[37].y, 90.0000) || !closef(qc_points[38].x, 279.1163) || !closef(qc_points[38].y, 100.3889) || !closef(qc_points[39].x, 286.0930) || !closef(qc_points[39].y, 98.5000) || !closef(qc_points[40].x, 293.0698) || !closef(qc_points[40].y, 111.6183) || !closef(qc_points[41].x, 300.0465) || !closef(qc_points[41].y, 101.6271) { os.exit(13) }
    if !closef(qc_points[42].x, 307.0233) || !closef(qc_points[42].y, 94.3331) || !closef(qc_points[43].x, 314.0000) || !closef(qc_points[43].y, 110.4595) { os.exit(14) }
    if !closef(qc_limits[0].from.y, 163.6667) || !closef(qc_limits[0].to.y, 163.6667) || !closef(qc_limits[0].from.x, 14.0) || !closef(qc_limits[0].to.x, 314.0) || !closef(qc_limits[1].from.y, 144.7778) || !closef(qc_limits[1].to.y, 144.7778) || !closef(qc_limits[1].from.x, 14.0) || !closef(qc_limits[1].to.x, 314.0) || !closef(qc_limits[2].from.y, 125.8889) || !closef(qc_limits[2].to.y, 125.8889) || !closef(qc_limits[2].from.x, 14.0) || !closef(qc_limits[2].to.x, 314.0) { os.exit(15) }
    if !closef(qc_limits[3].from.y, 107.0000) || !closef(qc_limits[3].to.y, 107.0000) || !closef(qc_limits[3].from.x, 14.0) || !closef(qc_limits[3].to.x, 314.0) || !closef(qc_limits[4].from.y, 88.1111) || !closef(qc_limits[4].to.y, 88.1111) || !closef(qc_limits[4].from.x, 14.0) || !closef(qc_limits[4].to.x, 314.0) || !closef(qc_limits[5].from.y, 69.2222) || !closef(qc_limits[5].to.y, 69.2222) || !closef(qc_limits[5].from.x, 14.0) || !closef(qc_limits[5].to.x, 314.0) { os.exit(16) }
    if !closef(qc_limits[6].from.y, 50.3333) || !closef(qc_limits[6].to.y, 50.3333) || !closef(qc_limits[6].from.x, 14.0) || !closef(qc_limits[6].to.x, 314.0) { os.exit(17) }
    if !closef(qc_limits[3].from.y, 107.0) || !same(qc_limits[1].from.y - qc_limits[0].from.y, qc_limits[6].from.y - qc_limits[5].from.y) { os.exit(18) }
    if !closef(qc_signals[0].x, 48.8837) || !closef(qc_signals[0].y, 22.0000) || !closef(qc_signals[1].x, 90.7442) || !closef(qc_signals[1].y, 57.8889) || !closef(qc_signals[2].x, 125.6279) || !closef(qc_signals[2].y, 152.3333) || !closef(qc_signals[3].x, 174.4651) || !closef(qc_signals[3].y, 71.1111) || !closef(qc_signals[4].x, 265.1628) || !closef(qc_signals[4].y, 93.7778) || !closef(qc_signals[5].x, 272.1395) || !closef(qc_signals[5].y, 90.0000) { os.exit(19) }
    if !closef(qc_signals[6].x, 279.1163) || !closef(qc_signals[6].y, 100.3889) || !closef(qc_signals[7].x, 286.0930) || !closef(qc_signals[7].y, 98.5000) { os.exit(20) }
    let calm_values = [12]f64{ 100.2f64, 99.4f64, 100.4f64, 99.0f64, 100.8f64, 99.8f64, 100.6f64, 99.6f64, 100.0f64, 101.0f64, 99.2f64, 100.4f64 }
    let (calm, calm_error) = chart.levey_jennings(calm_values[..], 100.0, 2.0, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])
    if calm_error != ok || calm.flagged != 0usize || calm.signals.coords.len != 0usize || !closef(calm.y_limit, 4.0) { os.exit(21) }
    let nan = 0.0f64 / zero_f64()
    let (_, qc_one) = chart.levey_jennings(qc_values[..1usize], 100.0, 2.0, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])
    let (_, qc_none) = chart.levey_jennings(qc_values[..0usize], 100.0, 2.0, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])
    let (_, qc_sd_zero) = chart.levey_jennings(qc_values[..], 100.0, 0.0, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])
    let (_, qc_sd_nan) = chart.levey_jennings(qc_values[..], 100.0, nan, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])
    var qc_nan_values = qc_values
    qc_nan_values[3usize] = nan
    let (_, qc_value_nan) = chart.levey_jennings(qc_nan_values[..], 100.0, 2.0, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])
    let (_, qc_points_room) = chart.levey_jennings(qc_values[..], 100.0, 2.0, bounds, qc_points[..43usize], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])
    let (_, qc_trace_room) = chart.levey_jennings(qc_values[..], 100.0, 2.0, bounds, qc_points[..], qc_trace[..42usize], qc_limits[..], qc_signals[..], qc_flags[..])
    let (_, qc_limit_room) = chart.levey_jennings(qc_values[..], 100.0, 2.0, bounds, qc_points[..], qc_trace[..], qc_limits[..6usize], qc_signals[..], qc_flags[..])
    let (_, qc_signal_room) = chart.levey_jennings(qc_values[..], 100.0, 2.0, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..43usize], qc_flags[..])
    let (_, qc_flag_room) = chart.levey_jennings(qc_values[..], 100.0, 2.0, bounds, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..43usize])
    let (_, qc_bounds) = chart.levey_jennings(qc_values[..], 100.0, 2.0, geometry.Rect { x: 0.0, y: 0.0, width: 0.0, height: 5.0 }, qc_points[..], qc_trace[..], qc_limits[..], qc_signals[..], qc_flags[..])
    if qc_one != chart.Invalid || qc_none != chart.Empty || qc_sd_zero != chart.Invalid || qc_sd_nan != chart.Invalid || qc_value_nan != chart.Invalid || qc_bounds != chart.Invalid { os.exit(22) }
    if qc_points_room != chart.TooLarge || qc_trace_room != chart.TooLarge || qc_limit_room != chart.TooLarge || qc_signal_room != chart.TooLarge || qc_flag_room != chart.TooLarge { os.exit(23) }
    let cc_x = [30]f64{ 14.037f64, 24.962f64, 40.508f64, 37.649f64, 20.861f64, 52.552f64, 48.012f64, 58.313f64, 32.06f64, 46.098f64, 15.183f64, 9.613f64, 30.556f64, 43.324f64, 57.528f64, 37.441f64, 28.084f64, 50.824f64, 29.458f64, 48.426f64, 43.621f64, 40.412f64, 25.95f64, 25.01f64, 34.901f64, 36.848f64, 50.003f64, 33.404f64, 14.464f64, 13.68f64 }
    let cc_y = [30]f64{ 22.344f64, 30.041f64, 50.938f64, 45.741f64, 22.696f64, 56.882f64, 52.4f64, 63.296f64, 30.508f64, 50.24f64, 19.555f64, 10.37f64, 36.92f64, 50.749f64, 65.485f64, 48.087f64, 28.329f64, 59.197f64, 41.122f64, 55.402f64, 50.975f64, 53.083f64, 35.733f64, 26.795f64, 45.183f64, 43.818f64, 53.498f64, 35.875f64, 19.759f64, 18.949f64 }
    let (cc, cc_error) = stat.concordance_cc(cc_x[..], cc_y[..], 1.959963984540054)
    if cc_error != ok || !closed(cc.ccc, 0.889204120973554) || !closed(cc.pearson, 0.9732125354302047) || !closed(cc.bias_correction, 0.9136792721031741) { os.exit(24) }
    if !closed(cc.lower, 0.8161138341275869) || !closed(cc.upper, 0.9342938667419702) || !closed(cc.ccc, cc.pearson * cc.bias_correction) { os.exit(25) }
    var shifted: [30]f64 = zero
    var fill = 0usize
    while fill < 30 {
        shifted[fill] = cc_x[fill] + 15.0
        fill += 1usize
    }
    let (shift_cc, shift_error) = stat.concordance_cc(cc_x[..], shifted[..], 1.959963984540054)
    if shift_error != ok || !closed(shift_cc.ccc, 0.6184476590455669) || !closed(shift_cc.pearson, 1.0) || !closed(shift_cc.bias_correction, 0.6184476590455669) { os.exit(26) }
    let (same_cc, same_error) = stat.concordance_cc(cc_x[..], cc_x[..], 1.959963984540054)
    if same_error != ok || !closed(same_cc.ccc, 1.0) || !closed(same_cc.lower, 1.0) || !closed(same_cc.upper, 1.0) || !closed(same_cc.bias_correction, 1.0) { os.exit(27) }
    var cc_points: [30]chart.Coord = zero
    var cc_diagonal: [1]chart.Segment = zero
    let (cc_plot, cc_plot_error) = chart.concordance_plot(cc_x[..], cc_y[..], bounds, cc_points[..], cc_diagonal[..])
    if cc_plot_error != ok || cc_plot.coords.len != 30usize { os.exit(28) }
    if !closef(cc_points[0].x, 37.7543) || !closef(cc_points[0].y, 153.2638) || !closef(cc_points[1].x, 96.4152) || !closef(cc_points[1].y, 129.8444) || !closef(cc_points[2].x, 179.8881) || !closef(cc_points[2].y, 66.2617) || !closef(cc_points[3].x, 164.5369) || !closef(cc_points[3].y, 82.0745) || !closef(cc_points[4].x, 74.3952) || !closef(cc_points[4].y, 152.1928) || !closef(cc_points[5].x, 244.5573) || !closef(cc_points[5].y, 48.1761) { os.exit(29) }
    if !closef(cc_points[6].x, 220.1802) || !closef(cc_points[6].y, 61.8133) || !closef(cc_points[7].x, 275.4905) || !closef(cc_points[7].y, 28.6604) || !closef(cc_points[8].x, 134.5273) || !closef(cc_points[8].y, 128.4234) || !closef(cc_points[9].x, 209.9031) || !closef(cc_points[9].y, 68.3855) || !closef(cc_points[10].x, 43.9076) || !closef(cc_points[10].y, 161.7498) || !closef(cc_points[11].x, 14.0000) || !closef(cc_points[11].y, 189.6967) { os.exit(30) }
    if !closef(cc_points[12].x, 126.4517) || !closef(cc_points[12].y, 108.9138) || !closef(cc_points[13].x, 195.0084) || !closef(cc_points[13].y, 66.8368) || !closef(cc_points[14].x, 271.2756) || !closef(cc_points[14].y, 22.0000) || !closef(cc_points[15].x, 163.4201) || !closef(cc_points[15].y, 74.9364) || !closef(cc_points[16].x, 113.1785) || !closef(cc_points[16].y, 135.0534) || !closef(cc_points[17].x, 235.2790) || !closef(cc_points[17].y, 41.1323) { os.exit(31) }
    if !closef(cc_points[18].x, 120.5561) || !closef(cc_points[18].y, 96.1285) || !closef(cc_points[19].x, 222.4031) || !closef(cc_points[19].y, 52.6792) || !closef(cc_points[20].x, 196.6031) || !closef(cc_points[20].y, 66.1491) || !closef(cc_points[21].x, 179.3726) || !closef(cc_points[21].y, 59.7352) || !closef(cc_points[22].x, 101.7201) || !closef(cc_points[22].y, 112.5255) || !closef(cc_points[23].x, 96.6729) || !closef(cc_points[23].y, 139.7209) { os.exit(32) }
    if !closef(cc_points[24].x, 149.7818) || !closef(cc_points[24].y, 83.7723) || !closef(cc_points[25].x, 160.2360) || !closef(cc_points[25].y, 87.9255) || !closef(cc_points[26].x, 230.8707) || !closef(cc_points[26].y, 58.4725) || !closef(cc_points[27].x, 141.7438) || !closef(cc_points[27].y, 112.0934) || !closef(cc_points[28].x, 40.0470) || !closef(cc_points[28].y, 161.1291) || !closef(cc_points[29].x, 35.8374) || !closef(cc_points[29].y, 163.5936) { os.exit(33) }
    if !closef(cc_diagonal[0].from.x, 14.0) || !closef(cc_diagonal[0].from.y, 192.0) || !closef(cc_diagonal[0].to.x, 314.0) || !closef(cc_diagonal[0].to.y, 22.0) { os.exit(34) }
    let cc_two = [2]f64{ 1.0, 2.0 }
    let (_, cc_small) = stat.concordance_cc(cc_two[..], cc_two[..], 1.959963984540054)
    let cc_flat = [4]f64{ 5.0, 5.0, 5.0, 5.0 }
    let cc_four = [4]f64{ 1.0, 2.0, 3.0, 4.0 }
    let (_, cc_constant) = stat.concordance_cc(cc_flat[..], cc_four[..], 1.959963984540054)
    let cc_down = [4]f64{ 4.0, 3.0, 2.0, 1.0 }
    let (_, cc_negative) = stat.concordance_cc(cc_four[..], cc_down[..], 1.959963984540054)
    let (_, cc_shape) = stat.concordance_cc(cc_x[..], cc_y[..29usize], 1.959963984540054)
    let (_, cc_z_zero) = stat.concordance_cc(cc_x[..], cc_y[..], 0.0)
    let (_, cc_z_nan) = stat.concordance_cc(cc_x[..], cc_y[..], nan)
    var cc_nan_x = cc_x
    cc_nan_x[4usize] = nan
    let (_, cc_nan) = stat.concordance_cc(cc_nan_x[..], cc_y[..], 1.959963984540054)
    if cc_small != stat.Invalid || cc_constant != stat.Invalid || cc_negative != stat.Invalid || cc_shape != stat.Invalid || cc_z_zero != stat.Invalid || cc_z_nan != stat.Invalid || cc_nan != stat.Invalid { os.exit(35) }
    let (_, plot_flat) = chart.concordance_plot(cc_flat[..], cc_flat[..], bounds, cc_points[..], cc_diagonal[..])
    let (_, plot_none) = chart.concordance_plot(cc_x[..0usize], cc_y[..0usize], bounds, cc_points[..], cc_diagonal[..])
    let (_, plot_shape) = chart.concordance_plot(cc_x[..], cc_y[..29usize], bounds, cc_points[..], cc_diagonal[..])
    let (_, plot_room) = chart.concordance_plot(cc_x[..], cc_y[..], bounds, cc_points[..29usize], cc_diagonal[..])
    let (_, plot_line_room) = chart.concordance_plot(cc_x[..], cc_y[..], bounds, cc_points[..], cc_diagonal[..0usize])
    if plot_flat != chart.Invalid || plot_none != chart.Empty || plot_shape != chart.Invalid || plot_room != chart.TooLarge || plot_line_room != chart.TooLarge { os.exit(36) }
    let sym_odd = [21]f64{ 1.279f64, 4.905f64, 4.936f64, 5.257f64, 6.334f64, 7.126f64, 9.668f64, 11.024f64, 11.038f64, 11.175f64, 11.395f64, 15.71f64, 15.842f64, 16.034f64, 19.151f64, 19.257f64, 19.344f64, 20.563f64, 20.575f64, 21.195f64, 34.754f64 }
    var sym_odd_points: [10]chart.Coord = zero
    var sym_odd_diagonal: [1]chart.Segment = zero
    let (sym_odd_plot, sym_odd_error) = chart.symmetry_plot(sym_odd[..], bounds, sym_odd_points[..], sym_odd_diagonal[..])
    if sym_odd_error != ok || sym_odd_plot.coords.len != 10usize || !closef(sym_odd_plot.x_max, 23.358999999999998) { os.exit(37) }
    if !closef(sym_odd_points[0].x, 143.9199) || !closef(sym_odd_points[0].y, 22.0000) || !closef(sym_odd_points[1].x, 97.3512) || !closef(sym_odd_points[1].y, 120.6785) || !closef(sym_odd_points[2].x, 96.9530) || !closef(sym_odd_points[2].y, 125.1906) || !closef(sym_odd_points[3].x, 92.8304) || !closef(sym_odd_points[3].y, 125.2780) || !closef(sym_odd_points[4].x, 78.9985) || !closef(sym_odd_points[4].y, 134.1495) || !closef(sym_odd_points[5].x, 68.8268) || !closef(sym_odd_points[5].y, 134.7827) { os.exit(38) }
    if !closef(sym_odd_points[6].x, 36.1799) || !closef(sym_odd_points[6].y, 135.5541) || !closef(sym_odd_points[7].x, 18.7648) || !closef(sym_odd_points[7].y, 158.2387) || !closef(sym_odd_points[8].x, 18.5850) || !closef(sym_odd_points[8].y, 159.6360) || !closef(sym_odd_points[9].x, 16.8255) || !closef(sym_odd_points[9].y, 160.5967) { os.exit(39) }
    if !closef(sym_odd_diagonal[0].from.x, 14.0) || !closef(sym_odd_diagonal[0].from.y, 192.0) || !closef(sym_odd_diagonal[0].to.x, 314.0) || !closef(sym_odd_diagonal[0].to.y, 22.0) { os.exit(40) }
    let sym_even = [20]f64{ 2.365f64, 3.496f64, 4.555f64, 5.63f64, 5.877f64, 5.939f64, 7.26f64, 8.109f64, 8.25f64, 9.372f64, 9.516f64, 10.093f64, 10.239f64, 10.632f64, 12.57f64, 12.964f64, 15.659f64, 16.398f64, 22.905f64, 25.106f64 }
    var sym_even_points: [10]chart.Coord = zero
    var sym_even_diagonal: [1]chart.Segment = zero
    let (sym_even_plot, sym_even_error) = chart.symmetry_plot(sym_even[..], bounds, sym_even_points[..], sym_even_diagonal[..])
    if sym_even_error != ok || sym_even_plot.coords.len != 10usize || !closef(sym_even_plot.x_max, 15.662000000000003) { os.exit(41) }
    if !closef(sym_even_points[0].x, 149.5957) || !closef(sym_even_points[0].y, 22.0000) || !closef(sym_even_points[1].x, 127.9318) || !closef(sym_even_points[1].y, 45.8903) || !closef(sym_even_points[2].x, 107.6470) || !closef(sym_even_points[2].y, 116.5192) || !closef(sym_even_points[3].x, 87.0558) || !closef(sym_even_points[3].y, 124.5405) || !closef(sym_even_points[4].x, 82.3246) || !closef(sym_even_points[4].y, 153.7929) || !closef(sym_even_points[5].x, 81.1370) || !closef(sym_even_points[5].y, 158.0695) { os.exit(42) }
    if !closef(sym_even_points[6].x, 55.8337) || !closef(sym_even_points[6].y, 179.1051) || !closef(sym_even_points[7].x, 39.5714) || !closef(sym_even_points[7].y, 183.3708) || !closef(sym_even_points[8].x, 36.8706) || !closef(sym_even_points[8].y, 184.9556) || !closef(sym_even_points[9].x, 15.3791) || !closef(sym_even_points[9].y, 191.2185) { os.exit(43) }
    if !closef(sym_even_diagonal[0].from.x, 14.0) || !closef(sym_even_diagonal[0].from.y, 192.0) || !closef(sym_even_diagonal[0].to.x, 314.0) || !closef(sym_even_diagonal[0].to.y, 22.0) { os.exit(44) }
    let sym_flat = [5]f64{ 2.0, 2.0, 2.0, 2.0, 2.0 }
    let (_, sym_constant) = chart.symmetry_plot(sym_flat[..], bounds, sym_odd_points[..], sym_odd_diagonal[..])
    let sym_down = [5]f64{ 5.0, 4.0, 3.0, 2.0, 1.0 }
    let (_, sym_unsorted) = chart.symmetry_plot(sym_down[..], bounds, sym_odd_points[..], sym_odd_diagonal[..])
    let (_, sym_few) = chart.symmetry_plot(sym_odd[..3usize], bounds, sym_odd_points[..], sym_odd_diagonal[..])
    let (_, sym_none) = chart.symmetry_plot(sym_odd[..0usize], bounds, sym_odd_points[..], sym_odd_diagonal[..])
    var sym_nan_data = sym_odd
    sym_nan_data[2usize] = nan
    let (_, sym_nan) = chart.symmetry_plot(sym_nan_data[..], bounds, sym_odd_points[..], sym_odd_diagonal[..])
    let (_, sym_room) = chart.symmetry_plot(sym_odd[..], bounds, sym_odd_points[..9usize], sym_odd_diagonal[..])
    let (_, sym_line_room) = chart.symmetry_plot(sym_odd[..], bounds, sym_odd_points[..], sym_odd_diagonal[..0usize])
    if sym_constant != chart.Invalid || sym_unsorted != chart.Invalid || sym_few != chart.Invalid || sym_none != chart.Empty || sym_nan != chart.Invalid || sym_room != chart.TooLarge || sym_line_room != chart.TooLarge { os.exit(45) }
    let bc_values = [40]f64{ 4.2268f64, 1.4126f64, 1.7555f64, 1.6063f64, 2.5376f64, 1.9893f64, 1.9453f64, 3.2507f64, 1.6827f64, 1.6462f64, 4.4703f64, 2.4873f64, 3.28f64, 5.0673f64, 2.4496f64, 4.0456f64, 2.2827f64, 3.3355f64, 5.4862f64, 3.1992f64, 3.564f64, 1.6707f64, 2.9816f64, 3.9484f64, 5.2791f64, 5.0155f64, 4.165f64, 2.124f64, 4.6906f64, 1.0963f64, 7.5526f64, 4.3285f64, 6.4007f64, 2.7023f64, 2.26f64, 3.4808f64, 1.8628f64, 3.2649f64, 1.2358f64, 4.447f64 }
    let bc_grid = [41]f64{ -2.0f64, -1.9f64, -1.8f64, -1.7f64, -1.6f64, -1.5f64, -1.4f64, -1.3f64, -1.2f64, -1.1f64, -1.0f64, -0.9f64, -0.8f64, -0.7f64, -0.6f64, -0.5f64, -0.4f64, -0.3f64, -0.2f64, -0.1f64, 0.0f64, 0.1f64, 0.2f64, 0.3f64, 0.4f64, 0.5f64, 0.6f64, 0.7f64, 0.8f64, 0.9f64, 1.0f64, 1.1f64, 1.2f64, 1.3f64, 1.4f64, 1.5f64, 1.6f64, 1.7f64, 1.8f64, 1.9f64, 2.0f64 }
    var bc_llf: [41]f64 = zero
    var bc_points: [41]chart.Coord = zero
    var bc_segments: [40]chart.Segment = zero
    let (bc, bc_error) = chart.box_cox_profile(bc_values[..], bc_grid[..], 1.920729410347062, bounds, bc_llf[..], bc_points[..], bc_segments[..])
    if bc_error != ok || !bc.bracketed || !closed(bc.lambda_hat, 0.1) || !closed(bc.max_llf, -12.615110260853445) { os.exit(46) }
    if !closed(bc_llf[0], -32.083311863386356) || !closed(bc_llf[1], -30.382512100665494) || !closed(bc_llf[2], -28.75001097175793) || !closed(bc_llf[3], -27.18754317739564) || !closed(bc_llf[4], -25.69679376839653) || !closed(bc_llf[5], -24.27939149080511) || !closed(bc_llf[6], -22.936902637940932) || !closed(bc_llf[7], -21.670825483425702) || !closed(bc_llf[8], -20.48258534768955) || !closed(bc_llf[9], -19.373530325881745) || !closed(bc_llf[10], -18.344927678696763) || !closed(bc_llf[11], -17.397960860734386) { os.exit(47) }
    if !closed(bc_llf[12], -16.53372713512696) || !closed(bc_llf[13], -15.753235699791155) || !closed(bc_llf[14], -15.057406231231944) || !closed(bc_llf[15], -14.447067737607185) || !closed(bc_llf[16], -13.922957604758444) || !closed(bc_llf[17], -13.485720717805762) || !closed(bc_llf[18], -13.135908546985554) || !closed(bc_llf[19], -12.873978099567836) || !closed(bc_llf[20], -12.700290659389054) || !closed(bc_llf[21], -12.615110260853445) || !closed(bc_llf[22], -12.618601873907757) || !closed(bc_llf[23], -12.710829308906622) { os.exit(48) }
    if !closed(bc_llf[24], -12.89175288367652) || !closed(bc_llf[25], -13.161226927551068) || !closed(bc_llf[26], -13.518997226783679) || !closed(bc_llf[27], -13.964698540734675) || !closed(bc_llf[28], -14.497852336990785) || !closed(bc_llf[29], -15.117864904838306) || !closed(bc_llf[30], -15.824026009424381) || !closed(bc_llf[31], -16.61550824313879) || !closed(bc_llf[32], -17.491367216386926) || !closed(bc_llf[33], -18.450542707687667) || !closed(bc_llf[34], -19.49186086408972) || !closed(bc_llf[35], -20.614037508841008) { os.exit(49) }
    if !closed(bc_llf[36], -21.815682575957812) || !closed(bc_llf[37], -23.095305652876565) || !closed(bc_llf[38], -24.451322574808806) || !closed(bc_llf[39], -25.88206297970565) || !closed(bc_llf[40], -27.38577870256107) { os.exit(50) }
    if !closed(bc.lower, -0.5145447050318115) || !closed(bc.upper, 0.8061268651926851) { os.exit(51) }
    if bc.lower > bc.lambda_hat || bc.upper < bc.lambda_hat { os.exit(52) }
    if !closef(bc_points[0].x, 14.0000) || !closef(bc_points[0].y, 192.0000) || !closef(bc_points[1].x, 21.5000) || !closef(bc_points[1].y, 177.1483) || !closef(bc_points[2].x, 29.0000) || !closef(bc_points[2].y, 162.8930) || !closef(bc_points[3].x, 36.5000) || !closef(bc_points[3].y, 149.2492) || !closef(bc_points[4].x, 44.0000) || !closef(bc_points[4].y, 136.2317) || !closef(bc_points[5].x, 51.5000) || !closef(bc_points[5].y, 123.8547) { os.exit(53) }
    if !closef(bc_points[6].x, 59.0000) || !closef(bc_points[6].y, 112.1318) || !closef(bc_points[7].x, 66.5000) || !closef(bc_points[7].y, 101.0762) || !closef(bc_points[8].x, 74.0000) || !closef(bc_points[8].y, 90.7003) || !closef(bc_points[9].x, 81.5000) || !closef(bc_points[9].y, 81.0158) || !closef(bc_points[10].x, 89.0000) || !closef(bc_points[10].y, 72.0338) || !closef(bc_points[11].x, 96.5000) || !closef(bc_points[11].y, 63.7648) { os.exit(54) }
    if !closef(bc_points[12].x, 104.0000) || !closef(bc_points[12].y, 56.2181) || !closef(bc_points[13].x, 111.5000) || !closef(bc_points[13].y, 49.4027) || !closef(bc_points[14].x, 119.0000) || !closef(bc_points[14].y, 43.3266) || !closef(bc_points[15].x, 126.5000) || !closef(bc_points[15].y, 37.9970) || !closef(bc_points[16].x, 134.0000) || !closef(bc_points[16].y, 33.4204) || !closef(bc_points[17].x, 141.5000) || !closef(bc_points[17].y, 29.6023) { os.exit(55) }
    if !closef(bc_points[18].x, 149.0000) || !closef(bc_points[18].y, 26.5477) || !closef(bc_points[19].x, 156.5000) || !closef(bc_points[19].y, 24.2605) || !closef(bc_points[20].x, 164.0000) || !closef(bc_points[20].y, 22.7438) || !closef(bc_points[21].x, 171.5000) || !closef(bc_points[21].y, 22.0000) || !closef(bc_points[22].x, 179.0000) || !closef(bc_points[22].y, 22.0305) || !closef(bc_points[23].x, 186.5000) || !closef(bc_points[23].y, 22.8358) { os.exit(56) }
    if !closef(bc_points[24].x, 194.0000) || !closef(bc_points[24].y, 24.4157) || !closef(bc_points[25].x, 201.5000) || !closef(bc_points[25].y, 26.7688) || !closef(bc_points[26].x, 209.0000) || !closef(bc_points[26].y, 29.8929) || !closef(bc_points[27].x, 216.5000) || !closef(bc_points[27].y, 33.7849) || !closef(bc_points[28].x, 224.0000) || !closef(bc_points[28].y, 38.4405) || !closef(bc_points[29].x, 231.5000) || !closef(bc_points[29].y, 43.8545) { os.exit(57) }
    if !closef(bc_points[30].x, 239.0000) || !closef(bc_points[30].y, 50.0209) || !closef(bc_points[31].x, 246.5000) || !closef(bc_points[31].y, 56.9322) || !closef(bc_points[32].x, 254.0000) || !closef(bc_points[32].y, 64.5804) || !closef(bc_points[33].x, 261.5000) || !closef(bc_points[33].y, 72.9561) || !closef(bc_points[34].x, 269.0000) || !closef(bc_points[34].y, 82.0491) || !closef(bc_points[35].x, 276.5000) || !closef(bc_points[35].y, 91.8481) { os.exit(58) }
    if !closef(bc_points[36].x, 284.0000) || !closef(bc_points[36].y, 102.3411) || !closef(bc_points[37].x, 291.5000) || !closef(bc_points[37].y, 113.5150) || !closef(bc_points[38].x, 299.0000) || !closef(bc_points[38].y, 125.3560) || !closef(bc_points[39].x, 306.5000) || !closef(bc_points[39].y, 137.8495) || !closef(bc_points[40].x, 314.0000) || !closef(bc_points[40].y, 150.9803) { os.exit(59) }
    if bc.curve.segments.len != 40usize || !closef(bc.curve.y_max, -12.615110260853445) || !closef(bc.curve.y_min, -32.083311863386356) { os.exit(60) }
    let (zero_llf, zero_error) = stat.box_cox_llf(bc_values[..], 0.0)
    if zero_error != ok || !closed(zero_llf, -12.700290659389054) { os.exit(61) }
    let bc_narrow = [5]f64{ 0.1f64, 0.15f64, 0.2f64, 0.25f64, 0.3f64 }
    let (bc_narrow_profile, bc_narrow_error) = chart.box_cox_profile(bc_values[..], bc_narrow[..], 1.920729410347062, bounds, bc_llf[..], bc_points[..], bc_segments[..])
    if bc_narrow_error != ok || bc_narrow_profile.bracketed || !closed(bc_narrow_profile.lambda_hat, 0.15) || !closed(bc_narrow_profile.lower, 0.1) || !closed(bc_narrow_profile.upper, 0.3) { os.exit(62) }
    let bc_negative = [4]f64{ 1.0, 2.0, -3.0, 4.0 }
    let (_, bc_non_positive) = chart.box_cox_profile(bc_negative[..], bc_grid[..], 1.920729410347062, bounds, bc_llf[..], bc_points[..], bc_segments[..])
    let bc_flat = [4]f64{ 3.0, 3.0, 3.0, 3.0 }
    let (_, bc_constant) = chart.box_cox_profile(bc_flat[..], bc_grid[..], 1.920729410347062, bounds, bc_llf[..], bc_points[..], bc_segments[..])
    let (_, bc_two) = chart.box_cox_profile(bc_values[..2usize], bc_grid[..], 1.920729410347062, bounds, bc_llf[..], bc_points[..], bc_segments[..])
    let bc_back = [3]f64{ 1.0, 0.5, 0.0 }
    let (_, bc_order) = chart.box_cox_profile(bc_values[..], bc_back[..], 1.920729410347062, bounds, bc_llf[..], bc_points[..], bc_segments[..])
    let (_, bc_two_grid) = chart.box_cox_profile(bc_values[..], bc_grid[..2usize], 1.920729410347062, bounds, bc_llf[..], bc_points[..], bc_segments[..])
    let (_, bc_drop) = chart.box_cox_profile(bc_values[..], bc_grid[..], 0.0, bounds, bc_llf[..], bc_points[..], bc_segments[..])
    let (_, bc_none) = chart.box_cox_profile(bc_values[..0usize], bc_grid[..], 1.920729410347062, bounds, bc_llf[..], bc_points[..], bc_segments[..])
    let (_, bc_llf_room) = chart.box_cox_profile(bc_values[..], bc_grid[..], 1.920729410347062, bounds, bc_llf[..10usize], bc_points[..], bc_segments[..])
    let (_, bc_points_room) = chart.box_cox_profile(bc_values[..], bc_grid[..], 1.920729410347062, bounds, bc_llf[..], bc_points[..10usize], bc_segments[..])
    let (_, bc_segments_room) = chart.box_cox_profile(bc_values[..], bc_grid[..], 1.920729410347062, bounds, bc_llf[..], bc_points[..], bc_segments[..10usize])
    if bc_non_positive != chart.Invalid || bc_constant != chart.Invalid || bc_two != chart.Invalid || bc_order != chart.Invalid || bc_two_grid != chart.Invalid || bc_drop != chart.Invalid || bc_none != chart.Empty { os.exit(63) }
    if bc_llf_room != chart.TooLarge || bc_points_room != chart.TooLarge || bc_segments_room != chart.TooLarge { os.exit(64) }
    let (_, llf_two_error) = stat.box_cox_llf(bc_values[..2usize], 0.5)
    let (_, llf_nan_error) = stat.box_cox_llf(bc_values[..], nan)
    if llf_two_error != stat.Invalid || llf_nan_error != stat.Invalid { os.exit(65) }
    try io.print("gfx chart qc agreement reference ok\n")
    os.exit(0)
    ret ok
}
