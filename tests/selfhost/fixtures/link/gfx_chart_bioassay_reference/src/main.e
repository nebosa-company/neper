// The bioassay plots of e.gfx.chart against numpy and scipy (L095, D2263;
// scripts/chart_bioassay_reference.py writes this file): the parallel-line assay (common slope, F statistic
// for parallelism, relative potency with Fieller limits from the full covariance matrix), the Schild plot
// (regression, pA2, pKB at unit slope) and standard-curve readback (LL.4 inversion, in-range flags, guide
// segments). Every check has its own exit code.
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
    ret abs64(got - want) <= 1e-8f64 * (1.0f64 + abs64(want))
}

fn same(a: f32, b: f32) -> bool { ret abs64(f64(a) - f64(b)) <= 0.001f64 }

fn closef(got: f32, want: f64) -> bool {
    ret abs64(f64(got) - want) <= 0.0006f64 * (1.0f64 + abs64(want))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let pl_dose_s = [12]f64{ 1.0f64, 1.0f64, 1.0f64, 2.0f64, 2.0f64, 2.0f64, 4.0f64, 4.0f64, 4.0f64, 8.0f64, 8.0f64, 8.0f64 }
    let pl_resp_s = [12]f64{ 20.936f64, 17.696f64, 16.588f64, 30.258f64, 31.359f64, 31.897f64, 43.226f64, 43.254f64, 43.953f64, 56.497f64, 55.327f64, 57.832f64 }
    let pl_dose_t = [12]f64{ 1.5f64, 1.5f64, 1.5f64, 3.0f64, 3.0f64, 3.0f64, 6.0f64, 6.0f64, 6.0f64, 12.0f64, 12.0f64, 12.0f64 }
    let pl_resp_t = [12]f64{ 31.877f64, 29.251f64, 27.843f64, 43.817f64, 42.248f64, 43.086f64, 55.447f64, 55.785f64, 52.301f64, 68.137f64, 67.677f64, 65.735f64 }
    let bounds = geometry.rect(16.0, 24.0, 280.0, 160.0)
    var pl_points: [24]chart.Coord = zero
    var pl_lines: [2]chart.Segment = zero
    let (pl, pl_error) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..], pl_lines[..])
    if pl_error != ok || pl.residual_df != 21usize { os.exit(1) }
    if !closed(pl.slope, 41.653822478197384) || !closed(pl.intercept_standard, 18.593341666666678) || !closed(pl.intercept_test, 22.456884288665744) { os.exit(2) }
    if !closed(pl.log_potency, 0.09275361520593549) || !closed(pl.potency, 1.2380939893485954) { os.exit(3) }
    if !closed(pl.potency_lower, 1.157782909848646) || !closed(pl.potency_upper, 1.326706978073063) { os.exit(4) }
    if !closed(pl.parallelism_f, 0.2923249483520413) || pl.parallel != true { os.exit(5) }
    if !closef(pl_points[0].x, 16.0000) || !closef(pl_points[0].y, 170.5045) || !closef(pl_points[1].x, 16.0000) || !closef(pl_points[1].y, 180.5609) || !closef(pl_points[2].x, 16.0000) || !closef(pl_points[2].y, 184.0000) || !closef(pl_points[3].x, 94.1040) || !closef(pl_points[3].y, 141.5705) || !closef(pl_points[4].x, 94.1040) || !closef(pl_points[4].y, 138.1531) || !closef(pl_points[5].x, 94.1040) || !closef(pl_points[5].y, 136.4833) { os.exit(6) }
    if !closef(pl_points[6].x, 172.2080) || !closef(pl_points[6].y, 101.3198) || !closef(pl_points[7].x, 172.2080) || !closef(pl_points[7].y, 101.2329) || !closef(pl_points[8].x, 172.2080) || !closef(pl_points[8].y, 99.0633) || !closef(pl_points[9].x, 250.3121) || !closef(pl_points[9].y, 60.1287) || !closef(pl_points[10].x, 250.3121) || !closef(pl_points[10].y, 63.7602) || !closef(pl_points[11].x, 250.3121) || !closef(pl_points[11].y, 55.9851) { os.exit(7) }
    if !closef(pl_points[12].x, 61.6879) || !closef(pl_points[12].y, 136.5453) || !closef(pl_points[13].x, 61.6879) || !closef(pl_points[13].y, 144.6960) || !closef(pl_points[14].x, 61.6879) || !closef(pl_points[14].y, 149.0662) || !closef(pl_points[15].x, 139.7920) || !closef(pl_points[15].y, 99.4855) || !closef(pl_points[16].x, 139.7920) || !closef(pl_points[16].y, 104.3554) || !closef(pl_points[17].x, 139.7920) || !closef(pl_points[17].y, 101.7544) { os.exit(8) }
    if !closef(pl_points[18].x, 217.8960) || !closef(pl_points[18].y, 63.3878) || !closef(pl_points[19].x, 217.8960) || !closef(pl_points[19].y, 62.3387) || !closef(pl_points[20].x, 217.8960) || !closef(pl_points[20].y, 73.1525) || !closef(pl_points[21].x, 296.0000) || !closef(pl_points[21].y, 24.0000) || !closef(pl_points[22].x, 296.0000) || !closef(pl_points[22].y, 25.4278) || !closef(pl_points[23].x, 296.0000) || !closef(pl_points[23].y, 31.4554) { os.exit(9) }
    if !closef(pl_lines[0].from.x, 16.0000) || !closef(pl_lines[0].to.x, 296.0000) || !closef(pl_lines[0].from.y, 177.7757) || !closef(pl_lines[0].to.y, 38.2517) || !closef(pl_lines[1].from.x, 16.0000) || !closef(pl_lines[1].to.x, 296.0000) || !closef(pl_lines[1].from.y, 165.7839) || !closef(pl_lines[1].to.y, 26.2599) { os.exit(10) }
    if pl.observations.coords.len != 24usize || pl.lines.segments.len != 2usize || !closef(pl.lines.segments[0].to.x - pl.lines.segments[0].from.x, 280.0) || !same(pl.lines.segments[0].from.y - pl.lines.segments[0].to.y, pl.lines.segments[1].from.y - pl.lines.segments[1].to.y) { os.exit(11) }
    if (pl.intercept_test > pl.intercept_standard) != true { os.exit(12) }
    let pl_resp_bad = [12]f64{ 62.121f64, 62.495f64, 62.184f64, 67.22f64, 66.079f64, 65.605f64, 72.658f64, 72.533f64, 72.066f64, 76.616f64, 76.308f64, 76.628f64 }
    let (pl_bad, pl_bad_error) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..], pl_dose_t[..], pl_resp_bad[..], 0.05, bounds, pl_points[..], pl_lines[..])
    if pl_bad_error != ok && pl_bad_error != chart.Invalid { os.exit(13) }
    if pl_bad_error == ok && (pl_bad.parallel || !closed(pl_bad.parallelism_f, 463.3519421995519)) { os.exit(14) }
    let flat_dose = [3]f64{ 1.0, 2.0, 4.0 }
    let flat_resp = [3]f64{ 5.0, 5.0, 5.0 }
    let (_, pl_flat) = chart.parallel_line_assay(flat_dose[..], flat_resp[..], flat_dose[..], flat_resp[..], 0.05, bounds, pl_points[..], pl_lines[..])
    let neg_dose = [3]f64{ 1.0, -2.0, 4.0 }
    let (_, pl_nonpositive) = chart.parallel_line_assay(neg_dose[..], flat_resp[..], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..], pl_lines[..])
    let (_, pl_few) = chart.parallel_line_assay(pl_dose_s[..2usize], pl_resp_s[..2usize], pl_dose_t[..2usize], pl_resp_t[..2usize], 0.05, bounds, pl_points[..], pl_lines[..])
    let (_, pl_alpha) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..], pl_dose_t[..], pl_resp_t[..], 1.5, bounds, pl_points[..], pl_lines[..])
    let (_, pl_shape) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..11usize], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..], pl_lines[..])
    let (_, pl_none) = chart.parallel_line_assay(pl_dose_s[..0usize], pl_resp_s[..0usize], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..], pl_lines[..])
    let (_, pl_room) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..23usize], pl_lines[..])
    let (_, pl_line_room) = chart.parallel_line_assay(pl_dose_s[..], pl_resp_s[..], pl_dose_t[..], pl_resp_t[..], 0.05, bounds, pl_points[..], pl_lines[..1usize])
    if pl_flat != chart.Invalid { os.exit(15) }
    if pl_nonpositive != chart.Invalid { os.exit(16) }
    if pl_few != chart.Invalid { os.exit(17) }
    if pl_alpha != chart.Invalid { os.exit(18) }
    if pl_shape != chart.Invalid { os.exit(19) }
    if pl_none != chart.Empty { os.exit(20) }
    if pl_room != chart.TooLarge { os.exit(21) }
    if pl_line_room != chart.TooLarge { os.exit(22) }
    let sc_b = [6]f64{ 1e-08f64, 3e-08f64, 1e-07f64, 3e-07f64, 1e-06f64, 3e-06f64 }
    let sc_dr = [6]f64{ 1.5307f64, 2.586f64, 5.6901f64, 16.0822f64, 59.9977f64, 136.4075f64 }
    var sc_points: [6]chart.Coord = zero
    var sc_line: [1]chart.Segment = zero
    let (schild, schild_error) = chart.schild_plot(sc_b[..], sc_dr[..], bounds, sc_points[..], sc_line[..])
    if schild_error != ok { os.exit(23) }
    if !closed(schild.slope, 0.9899516156159471) || !closed(schild.intercept, 7.639710642472136) || !closed(schild.r_squared, 0.9980568882952279) { os.exit(24) }
    if !closed(schild.pa2, 7.717256603211576) || !closed(schild.pkb_unit, 7.707652184277895) { os.exit(25) }
    if !closef(sc_points[0].x, 16.0000) || !closef(sc_points[0].y, 183.6900) || !closef(sc_points[1].x, 69.9311) || !closef(sc_points[1].y, 152.6682) || !closef(sc_points[2].x, 129.0344) || !closef(sc_points[2].y, 121.9449) || !closef(sc_points[3].x, 182.9656) || !closef(sc_points[3].y, 88.8463) || !closef(sc_points[4].x, 242.0689) || !closef(sc_points[4].y, 50.1961) || !closef(sc_points[5].x, 296.0000) || !closef(sc_points[5].y, 26.6546) { os.exit(26) }
    if !closef(sc_line[0].from.x, 16.0) || !closef(sc_line[0].to.x, 296.0) || !closef(sc_line[0].from.y, 184.0000) || !closef(sc_line[0].to.y, 24.0000) { os.exit(27) }
    let sc_low = [3]f64{ 1e-8, 1e-7, 1e-6 }
    let sc_bad_ratio = [3]f64{ 1.0, 2.0, 3.0 }
    let (_, sc_ratio_one) = chart.schild_plot(sc_low[..], sc_bad_ratio[..], bounds, sc_points[..], sc_line[..])
    let sc_bad_conc = [3]f64{ 1e-8, 0.0, 1e-6 }
    let sc_two = [3]f64{ 2.0, 3.0, 5.0 }
    let (_, sc_conc_zero) = chart.schild_plot(sc_bad_conc[..], sc_two[..], bounds, sc_points[..], sc_line[..])
    let sc_same = [3]f64{ 1e-7, 1e-7, 1e-7 }
    let (_, sc_same_conc) = chart.schild_plot(sc_same[..], sc_two[..], bounds, sc_points[..], sc_line[..])
    let (_, sc_two_points) = chart.schild_plot(sc_b[..2usize], sc_dr[..2usize], bounds, sc_points[..], sc_line[..])
    let (_, sc_shape) = chart.schild_plot(sc_b[..], sc_dr[..5usize], bounds, sc_points[..], sc_line[..])
    let (_, sc_none) = chart.schild_plot(sc_b[..0usize], sc_dr[..0usize], bounds, sc_points[..], sc_line[..])
    let (_, sc_room) = chart.schild_plot(sc_b[..], sc_dr[..], bounds, sc_points[..5usize], sc_line[..])
    let (_, sc_line_room) = chart.schild_plot(sc_b[..], sc_dr[..], bounds, sc_points[..], sc_line[..0usize])
    if sc_ratio_one != chart.Invalid { os.exit(28) }
    if sc_conc_zero != chart.Invalid { os.exit(29) }
    if sc_same_conc != chart.Invalid { os.exit(30) }
    if sc_two_points != chart.Invalid { os.exit(31) }
    if sc_shape != chart.Invalid { os.exit(32) }
    if sc_none != chart.Empty { os.exit(33) }
    if sc_room != chart.TooLarge { os.exit(34) }
    if sc_line_room != chart.TooLarge { os.exit(35) }
    let rb_signals = [10]f64{ 1.5f64, 0.3f64, 2.3f64, 0.05f64, 2.45f64, 1.0f64, 0.08f64, 2.4f64, 2.55f64, 0.2f64 }
    var rb_conc: [10]f64 = zero
    var rb_flags: [10]bool = zero
    var rb_guides: [20]chart.Segment = zero
    let (rb, rb_read, rb_error) = chart.standard_curve_readback(0.08, 2.4, 1.2e-09, 1.3, rb_signals[..], 1e-11, 1e-06, 0.0, 2.6, bounds, rb_conc[..], rb_flags[..], rb_guides[..])
    if rb_error != ok || rb_read != 5usize || rb.segments.len != 10usize { os.exit(36) }
    if !closed(rb_conc[0], 8.449641751472799e-10) || rb_flags[0] != true || !closed(rb_conc[1], 6.805670976013835e-09) || rb_flags[1] != true || !closed(rb_conc[2], 1.1054143850073508e-10) || rb_flags[2] != true || !closed(rb_conc[3], 0.0) || rb_flags[3] != false || !closed(rb_conc[4], 0.0) || rb_flags[4] != false || !closed(rb_conc[5], 1.6574595745667131e-09) || rb_flags[5] != true { os.exit(37) }
    if !closed(rb_conc[6], 0.0) || rb_flags[6] != false || !closed(rb_conc[7], 0.0) || rb_flags[7] != false || !closed(rb_conc[8], 0.0) || rb_flags[8] != false || !closed(rb_conc[9], 1.124360103050872e-08) || rb_flags[9] != true { os.exit(38) }
    if !closef(rb_guides[0].from.x, 16.0000) || !closef(rb_guides[0].from.y, 91.6923) || !closef(rb_guides[0].to.x, 123.9029) || !closef(rb_guides[0].to.y, 91.6923) || !closef(rb_guides[1].from.x, 123.9029) || !closef(rb_guides[1].from.y, 91.6923) || !closef(rb_guides[1].to.x, 123.9029) || !closef(rb_guides[1].to.y, 184.0000) || !closef(rb_guides[2].from.x, 16.0000) || !closef(rb_guides[2].from.y, 165.5385) || !closef(rb_guides[2].to.x, 174.6408) || !closef(rb_guides[2].to.y, 165.5385) { os.exit(39) }
    if !closef(rb_guides[3].from.x, 174.6408) || !closef(rb_guides[3].from.y, 165.5385) || !closef(rb_guides[3].to.x, 174.6408) || !closef(rb_guides[3].to.y, 184.0000) || !closef(rb_guides[4].from.x, 16.0000) || !closef(rb_guides[4].from.y, 42.4615) || !closef(rb_guides[4].to.x, 74.4374) || !closef(rb_guides[4].to.y, 42.4615) || !closef(rb_guides[5].from.x, 74.4374) || !closef(rb_guides[5].from.y, 42.4615) || !closef(rb_guides[5].to.x, 74.4374) || !closef(rb_guides[5].to.y, 184.0000) { os.exit(40) }
    if !closef(rb_guides[6].from.x, 16.0000) || !closef(rb_guides[6].from.y, 122.4615) || !closef(rb_guides[6].to.x, 140.2888) || !closef(rb_guides[6].to.y, 122.4615) || !closef(rb_guides[7].from.x, 140.2888) || !closef(rb_guides[7].from.y, 122.4615) || !closef(rb_guides[7].to.x, 140.2888) || !closef(rb_guides[7].to.y, 184.0000) || !closef(rb_guides[8].from.x, 16.0000) || !closef(rb_guides[8].from.y, 171.6923) || !closef(rb_guides[8].to.x, 186.8507) || !closef(rb_guides[8].to.y, 171.6923) { os.exit(41) }
    if !closef(rb_guides[9].from.x, 186.8507) || !closef(rb_guides[9].from.y, 171.6923) || !closef(rb_guides[9].to.x, 186.8507) || !closef(rb_guides[9].to.y, 184.0000) { os.exit(42) }
    if rb_conc[3] != 0.0f64 || rb_flags[3] || rb_conc[4] != 0.0f64 || rb_flags[4] || rb_conc[6] != 0.0f64 || rb_flags[6] || rb_conc[7] != 0.0f64 || rb_flags[7] || rb_conc[8] != 0.0f64 || rb_flags[8] { os.exit(43) }
    let (_, _, rb_inverted) = chart.standard_curve_readback(2.4, 0.08, 1.2e-09, 1.3, rb_signals[..], 1e-11, 1e-06, 0.0, 2.6, bounds, rb_conc[..], rb_flags[..], rb_guides[..])
    let (_, _, rb_ec50) = chart.standard_curve_readback(0.08, 2.4, 0.0, 1.3, rb_signals[..], 1e-11, 1e-06, 0.0, 2.6, bounds, rb_conc[..], rb_flags[..], rb_guides[..])
    let (_, _, rb_slope) = chart.standard_curve_readback(0.08, 2.4, 1.2e-09, 0.0, rb_signals[..], 1e-11, 1e-06, 0.0, 2.6, bounds, rb_conc[..], rb_flags[..], rb_guides[..])
    let (_, _, rb_domain) = chart.standard_curve_readback(0.08, 2.4, 1.2e-09, 1.3, rb_signals[..], 1e-06, 1e-11, 0.0, 2.6, bounds, rb_conc[..], rb_flags[..], rb_guides[..])
    let (_, _, rb_dose_zero) = chart.standard_curve_readback(0.08, 2.4, 1.2e-09, 1.3, rb_signals[..], 0.0, 1e-06, 0.0, 2.6, bounds, rb_conc[..], rb_flags[..], rb_guides[..])
    let (_, _, rb_none) = chart.standard_curve_readback(0.08, 2.4, 1.2e-09, 1.3, rb_signals[..0usize], 1e-11, 1e-06, 0.0, 2.6, bounds, rb_conc[..], rb_flags[..], rb_guides[..])
    let (_, _, rb_conc_room) = chart.standard_curve_readback(0.08, 2.4, 1.2e-09, 1.3, rb_signals[..], 1e-11, 1e-06, 0.0, 2.6, bounds, rb_conc[..3usize], rb_flags[..], rb_guides[..])
    let (_, _, rb_flags_room) = chart.standard_curve_readback(0.08, 2.4, 1.2e-09, 1.3, rb_signals[..], 1e-11, 1e-06, 0.0, 2.6, bounds, rb_conc[..], rb_flags[..3usize], rb_guides[..])
    let (_, _, rb_guide_room) = chart.standard_curve_readback(0.08, 2.4, 1.2e-09, 1.3, rb_signals[..], 1e-11, 1e-06, 0.0, 2.6, bounds, rb_conc[..], rb_flags[..], rb_guides[..19usize])
    let nan = 0.0f64 / zero_f64()
    var rb_nan_signals = rb_signals
    rb_nan_signals[2usize] = nan
    let (_, _, rb_nan) = chart.standard_curve_readback(0.08, 2.4, 1.2e-09, 1.3, rb_nan_signals[..], 1e-11, 1e-06, 0.0, 2.6, bounds, rb_conc[..], rb_flags[..], rb_guides[..])
    if rb_inverted != chart.Invalid { os.exit(44) }
    if rb_ec50 != chart.Invalid { os.exit(45) }
    if rb_slope != chart.Invalid { os.exit(46) }
    if rb_domain != chart.Invalid { os.exit(47) }
    if rb_dose_zero != chart.Invalid { os.exit(48) }
    if rb_none != chart.Empty { os.exit(49) }
    if rb_conc_room != chart.TooLarge { os.exit(50) }
    if rb_flags_room != chart.TooLarge { os.exit(51) }
    if rb_guide_room != chart.TooLarge { os.exit(52) }
    if rb_nan != chart.Invalid { os.exit(53) }
    let neg_signal = [1]f64{ 1.0 }
    var neg_conc: [1]f64 = zero
    var neg_flag: [1]bool = zero
    var neg_guide: [2]chart.Segment = zero
    let (_, neg_read, neg_error) = chart.standard_curve_readback(0.08, 2.4, 1.2e-09, -1.3, neg_signal[..], 1e-11, 1e-06, 0.0, 2.6, bounds, neg_conc[..], neg_flag[..], neg_guide[..])
    if neg_error != ok || !closed(neg_conc[0], 8.687994700422419e-10) { os.exit(54) }
    try io.print("gfx chart bioassay reference ok\n")
    os.exit(0)
    ret ok
}
