// The estimators behind the SPC, capability and measurement-system charts against independent numpy and
// scipy computations on seeded data (L071, D2255; scripts/stat_spc_reference.py writes this file):
// individuals and moving-range limits, X-bar/R and X-bar/S limits, normal, batch and lognormal capability with
// their ppm, P, nP, C and U limits, Laney P-prime and U-prime, G and T chart limits, the Nelson run-rule flags,
// Gage linearity and attribute agreement. Every check has its own exit code.
use e.algo.stat
use e.mem
use e.os

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn close(got: f64, want: f64, tolerance: f64) -> bool {
    ret abs64(got - want) <= tolerance * (1.0f64 + abs64(want))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let imr_x = [40]f64{ 9.995f64, 9.337f64, 11.158f64, 9.963f64, 10.025f64, 10.698f64, 10.96f64, 10.374f64, 10.732f64, 10.296f64, 10.516f64, 10.214f64, 10.099f64, 9.553f64, 10.303f64, 9.843f64, 9.755f64, 10.508f64, 10.351f64, 10.339f64, 10.955f64, 9.446f64, 10.813f64, 9.713f64, 9.911f64, 10.695f64, 11.034f64, 10.426f64, 10.731f64, 11.134f64, 10.171f64, 10.614f64, 9.321f64, 10.376f64, 10.38f64, 10.664f64, 10.659f64, 10.529f64, 9.652f64, 10.476f64 }
    var moving: [39]f64 = zero
    let (individuals, mr, imr_error) = stat.imr_limits(imr_x[..], moving[..])
    if imr_error != ok || !close(individuals.center, 10.317975f64, 1e-09f64) || !close(individuals.lower, 8.77944526732133f64, 1e-09f64) || !close(individuals.upper, 11.85650473267867f64, 1e-09f64) { os.exit(1) }
    if !close(mr.center, 0.5784871794871798f64, 1e-09f64) || !close(mr.upper, 1.8899176153846162f64, 1e-09f64) || mr.lower != 0.0f64 || !close(moving[38], 0.8240000000000016f64, 1e-09f64) { os.exit(2) }
    var moving2: [39]f64 = zero
    let (capability, capability_error) = stat.normal_capability_individuals(imr_x[..], 8.5f64, 11.5f64, moving2[..])
    if capability_error != ok || !close(capability.within_sigma, 0.5128432442262233f64, 1e-09f64) || !close(capability.overall_sigma, 0.48792088931584937f64, 1e-09f64) || !close(capability.mean, 10.317975f64, 1e-09f64) { os.exit(3) }
    if !close(capability.cp, 0.9749567838305034f64, 1e-09f64) || !close(capability.cpk, 0.7682821949381669f64, 1e-09f64) || !close(capability.pp, 1.0247562892851085f64, 1e-09f64) || !close(capability.ppk, 0.8075250352281532f64, 1e-09f64) { os.exit(4) }
    let (performance, performance_error) = stat.normal_capability_performance(imr_x[..], 8.5f64, 11.5f64, capability)
    if performance_error != ok || !close(performance.observed_below_ppm, 0.0f64, 1e-09f64) || !close(performance.observed_above_ppm, 0.0f64, 1e-09f64) { os.exit(5) }
    if !close(performance.within_below_ppm, 196.38541422576293f64, 1e-07f64) || !close(performance.within_above_ppm, 10587.583520764143f64, 1e-07f64) || !close(performance.overall_below_ppm, 97.28561581907023f64, 1e-07f64) || !close(performance.overall_above_ppm, 7705.469891429333f64, 1e-07f64) { os.exit(6) }
    let batch_x = [40]f64{ 10.272f64, 9.988f64, 10.675f64, 10.048f64, 10.036f64, 9.951f64, 10.695f64, 10.335f64, 10.183f64, 10.848f64, 9.657f64, 9.726f64, 9.987f64, 10.863f64, 10.104f64, 11.127f64, 10.9f64, 10.518f64, 10.214f64, 10.998f64, 10.655f64, 10.249f64, 10.51f64, 10.745f64, 10.575f64, 10.337f64, 10.514f64, 10.885f64, 10.303f64, 10.772f64, 10.543f64, 10.113f64, 10.522f64, 9.918f64, 10.06f64, 10.387f64, 10.722f64, 10.141f64, 10.806f64, 10.468f64 }
    var batch_means: [8]f64 = zero
    var batch_spreads: [8]f64 = zero
    let (batch, batch_error) = stat.batch_capability(batch_x[..], 5usize, 9.0f64, 11.5f64, batch_means[..], batch_spreads[..])
    if batch_error != ok || !close(batch.within_sigma, 0.3249137193163747f64, 1e-09f64) || !close(batch.between_sigma, 0.17383550722285876f64, 1e-09f64) || !close(batch.between_within_sigma, 0.3684938379015699f64, 1e-09f64) || !close(batch.overall_sigma, 0.36426411592942576f64, 1e-09f64) { os.exit(7) }
    if !close(batch.cp, 1.1307289941113328f64, 1e-09f64) || !close(batch.cpk, 0.9871264118591923f64, 1e-09f64) || !close(batch.pp, 1.1438586686024095f64, 1e-09f64) || !close(batch.ppk, 0.9985886176899023f64, 1e-09f64) { os.exit(8) }
    if !close(batch.observed_ppm, 0.0f64, 1e-09f64) || !close(batch.expected_bw_ppm, 1597.2431670063647f64, 1e-07f64) || !close(batch.expected_overall_ppm, 1423.7868375331336f64, 1e-07f64) { os.exit(9) }
    if !close(batch_means[3], 10.7514f64, 1e-09f64) || !close(batch_spreads[3], 0.3765777476166109f64, 1e-09f64) { os.exit(10) }
    let logn_x = [30]f64{ 4.749f64, 4.851f64, 3.49f64, 4.906f64, 3.616f64, 3.908f64, 4.512f64, 3.924f64, 4.039f64, 4.008f64, 6.077f64, 3.032f64, 4.653f64, 3.907f64, 4.511f64, 5.656f64, 4.428f64, 4.598f64, 4.027f64, 4.463f64, 4.18f64, 3.461f64, 2.91f64, 3.339f64, 4.734f64, 7.124f64, 6.026f64, 4.423f64, 4.8f64, 5.604f64 }
    let (lognormal, lognormal_error) = stat.lognormal_capability(logn_x[..], 2.0f64, 9.0f64)
    if lognormal_error != ok || !close(lognormal.log_mean, 1.4759536791761307f64, 1e-09f64) || !close(lognormal.log_sigma, 0.2005028435265878f64, 1e-09f64) || !close(lognormal.median, 4.375206327093759f64, 1e-09f64) { os.exit(11) }
    if !close(lognormal.pp, 1.2502544189411335f64, 1e-09f64) || !close(lognormal.ppl, 1.3014054810854938f64, 1e-09f64) || !close(lognormal.ppu, 1.1991033567967733f64, 1e-09f64) || !close(lognormal.ppk, 1.1991033567967733f64, 1e-09f64) { os.exit(12) }
    if !close(lognormal.expected_below_ppm, 47.26557631266269f64, 1e-07f64) || !close(lognormal.expected_above_ppm, 160.76255665900186f64, 1e-07f64) { os.exit(13) }
    let xr_2 = [24]f64{ 47.746f64, 48.317f64, 49.706f64, 45.903f64, 48.504f64, 46.556f64, 55.382f64, 51.744f64, 51.981f64, 53.621f64, 50.584f64, 48.648f64, 47.46f64, 53.083f64, 49.347f64, 52.466f64, 49.428f64, 50.728f64, 48.314f64, 51.471f64, 53.162f64, 50.285f64, 49.333f64, 49.338f64 }
    var xr_means_2: [12]f64 = zero
    var xr_ranges_2: [12]f64 = zero
    let (xr_mean_2, xr_range_2, xr_error_2) = stat.xbar_r_limits(xr_2[..], 2usize, xr_means_2[..], xr_ranges_2[..])
    if xr_error_2 != ok || !close(xr_mean_2.center, 50.12945833333333f64, 1e-09f64) || !close(xr_mean_2.upper, 54.77094360336923f64, 0.0006f64) || !close(xr_mean_2.lower, 45.48797306329743f64, 0.0006f64) { os.exit(14) }
    if !close(xr_range_2.center, 2.468083333333334f64, 1e-09f64) || !close(xr_range_2.upper, 8.067219193262414f64, 0.0006f64) || !close(xr_range_2.lower, 0.0f64, 0.0006f64) { os.exit(15) }
    var xs_means_2: [12]f64 = zero
    var xs_devs_2: [12]f64 = zero
    let (xs_mean_2, xs_dev_2, xs_error_2) = stat.xbar_s_limits(xr_2[..], 2usize, xs_means_2[..], xs_devs_2[..])
    if xs_error_2 != ok || !close(xs_mean_2.upper, 54.76938393394248f64, 1e-09f64) || !close(xs_mean_2.lower, 45.489532732724186f64, 1e-09f64) || !close(xs_dev_2.center, 1.7451984615334986f64, 1e-09f64) { os.exit(16) }
    if !close(xs_dev_2.upper, 5.700746480092536f64, 1e-09f64) || !close(xs_dev_2.lower, 0.0f64, 1e-09f64) { os.exit(17) }
    let xr_5 = [60]f64{ 52.097f64, 50.899f64, 50.268f64, 47.756f64, 49.47f64, 50.402f64, 51.881f64, 51.961f64, 51.23f64, 50.544f64, 48.437f64, 46.039f64, 52.487f64, 52.289f64, 52.634f64, 50.09f64, 51.608f64, 54.301f64, 52.692f64, 49.678f64, 49.549f64, 47.774f64, 45.983f64, 51.216f64, 49.072f64, 51.646f64, 50.305f64, 53.314f64, 49.051f64, 47.83f64, 50.6f64, 53.389f64, 47.599f64, 48.228f64, 48.453f64, 49.41f64, 50.094f64, 51.23f64, 51.569f64, 47.381f64, 50.6f64, 48.463f64, 48.576f64, 49.024f64, 50.504f64, 48.228f64, 48.717f64, 48.098f64, 49.666f64, 50.553f64, 46.94f64, 50.144f64, 48.705f64, 50.17f64, 50.521f64, 48.375f64, 45.877f64, 52.444f64, 48.787f64, 52.682f64 }
    var xr_means_5: [12]f64 = zero
    var xr_ranges_5: [12]f64 = zero
    let (xr_mean_5, xr_range_5, xr_error_5) = stat.xbar_r_limits(xr_5[..], 5usize, xr_means_5[..], xr_ranges_5[..])
    if xr_error_5 != ok || !close(xr_mean_5.center, 49.958833333333324f64, 1e-09f64) || !close(xr_mean_5.upper, 52.49632827314827f64, 0.0006f64) || !close(xr_mean_5.lower, 47.421338393518376f64, 0.0006f64) { os.exit(18) }
    if !close(xr_range_5.center, 4.399250000000001f64, 1e-09f64) || !close(xr_range_5.upper, 9.3015956577816f64, 0.0006f64) || !close(xr_range_5.lower, 0.0f64, 0.0006f64) { os.exit(19) }
    var xs_means_5: [12]f64 = zero
    var xs_devs_5: [12]f64 = zero
    let (xs_mean_5, xs_dev_5, xs_error_5) = stat.xbar_s_limits(xr_5[..], 5usize, xs_means_5[..], xs_devs_5[..])
    if xs_error_5 != ok || !close(xs_mean_5.upper, 52.56022858823216f64, 1e-09f64) || !close(xs_mean_5.lower, 47.35743807843449f64, 1e-09f64) || !close(xs_dev_5.center, 1.8225996942609f64, 1e-09f64) { os.exit(20) }
    if !close(xs_dev_5.upper, 3.8074068766772178f64, 1e-09f64) || !close(xs_dev_5.lower, 0.0f64, 1e-09f64) { os.exit(21) }
    let xr_9 = [108]f64{ 49.528f64, 48.081f64, 51.355f64, 48.616f64, 49.971f64, 50.58f64, 51.852f64, 50.593f64, 49.442f64, 48.953f64, 49.63f64, 46.912f64, 52.501f64, 46.668f64, 52.326f64, 52.857f64, 50.2f64, 47.165f64, 51.184f64, 51.145f64, 48.086f64, 47.836f64, 50.961f64, 50.155f64, 53.832f64, 49.363f64, 52.214f64, 55.616f64, 49.615f64, 51.348f64, 49.666f64, 47.832f64, 48.583f64, 51.638f64, 48.741f64, 45.667f64, 52.343f64, 49.539f64, 51.791f64, 47.233f64, 49.434f64, 51.027f64, 50.834f64, 50.098f64, 47.058f64, 51.812f64, 50.029f64, 45.853f64, 49.521f64, 50.224f64, 47.836f64, 47.875f64, 49.867f64, 51.079f64, 47.888f64, 49.005f64, 51.815f64, 49.081f64, 51.467f64, 51.896f64, 46.337f64, 49.08f64, 47.623f64, 47.971f64, 51.44f64, 48.567f64, 50.013f64, 52.233f64, 45.573f64, 50.511f64, 50.264f64, 52.392f64, 48.909f64, 52.161f64, 51.094f64, 52.348f64, 49.739f64, 50.588f64, 47.319f64, 54.667f64, 48.903f64, 50.089f64, 52.15f64, 49.109f64, 52.942f64, 49.691f64, 49.901f64, 49.453f64, 50.092f64, 51.75f64, 46.969f64, 49.15f64, 50.624f64, 47.554f64, 52.588f64, 50.337f64, 48.191f64, 51.244f64, 50.573f64, 49.417f64, 51.474f64, 53.278f64, 47.314f64, 50.342f64, 48.092f64, 54.279f64, 46.468f64, 50.927f64 }
    var xr_means_9: [12]f64 = zero
    var xr_ranges_9: [12]f64 = zero
    let (xr_mean_9, xr_range_9, xr_error_9) = stat.xbar_r_limits(xr_9[..], 9usize, xr_means_9[..], xr_ranges_9[..])
    if xr_error_9 != ok || !close(xr_mean_9.center, 49.972657407407404f64, 1e-09f64) || !close(xr_mean_9.upper, 52.05284820426487f64, 0.0006f64) || !close(xr_mean_9.lower, 47.89246661054994f64, 0.0006f64) { os.exit(22) }
    if !close(xr_range_9.center, 6.178166666666667f64, 1e-09f64) || !close(xr_range_9.upper, 11.220549158249158f64, 0.0006f64) || !close(xr_range_9.lower, 1.1357841750841748f64, 0.0006f64) { os.exit(23) }
    var xs_means_9: [12]f64 = zero
    var xs_devs_9: [12]f64 = zero
    let (xs_mean_9, xs_dev_9, xs_error_9) = stat.xbar_s_limits(xr_9[..], 9usize, xs_means_9[..], xs_devs_9[..])
    if xs_error_9 != ok || !close(xs_mean_9.upper, 52.06757180181593f64, 1e-09f64) || !close(xs_mean_9.lower, 47.87774301299888f64, 1e-09f64) || !close(xs_dev_9.center, 2.030622937484964f64, 1e-09f64) { os.exit(24) }
    if !close(xs_dev_9.upper, 3.575657322519754f64, 1e-09f64) || !close(xs_dev_9.lower, 0.4855885524501737f64, 1e-09f64) { os.exit(25) }
    let p_counts = [12]usize{ 4usize, 9usize, 3usize, 12usize, 6usize, 14usize, 2usize, 9usize, 5usize, 7usize, 4usize, 13usize }
    let p_sizes = [12]usize{ 50usize, 80usize, 60usize, 100usize, 75usize, 90usize, 55usize, 120usize, 70usize, 85usize, 65usize, 110usize }
    var p_out: [12]stat.AttributeControlPoint = zero
    let p_error = stat.attribute_control(.P, p_counts[..], p_sizes[..], p_out[..])
    if p_error != ok || !close(p_out[0].value, 0.08f64, 1e-09f64) || !close(p_out[0].upper, 0.2140901121336196f64, 1e-09f64) || !close(p_out[0].lower, 0.0f64, 1e-09f64) || !close(p_out[1].value, 0.1125f64, 1e-09f64) || !close(p_out[1].upper, 0.18845089833691345f64, 1e-09f64) || !close(p_out[1].lower, 0.0f64, 1e-09f64) || !close(p_out[2].value, 0.05f64, 1e-09f64) || !close(p_out[2].upper, 0.20342347108292283f64, 1e-09f64) || !close(p_out[2].lower, 0.0f64, 1e-09f64) || !close(p_out[3].value, 0.12f64, 1e-09f64) || !close(p_out[3].upper, 0.17823311513257056f64, 1e-09f64) || !close(p_out[3].lower, 0.005100218200762743f64, 1e-09f64) || !close(p_out[4].value, 0.08f64, 1e-09f64) || !close(p_out[4].upper, 0.19162499131582567f64, 1e-09f64) || !close(p_out[4].lower, 0.0f64, 1e-09f64) || !close(p_out[5].value, 0.15555555555555556f64, 1e-09f64) || !close(p_out[5].upper, 0.18291571536794843f64, 1e-09f64) || !close(p_out[5].lower, 0.00041761796538490603f64, 1e-09f64) { os.exit(26) }
    if !close(p_out[6].value, 0.03636363636363636f64, 1e-09f64) || !close(p_out[6].upper, 0.2083928419659542f64, 1e-09f64) || !close(p_out[6].lower, 0.0f64, 1e-09f64) || !close(p_out[7].value, 0.075f64, 1e-09f64) || !close(p_out[7].upper, 0.1706906609131401f64, 1e-09f64) || !close(p_out[7].lower, 0.012642672420193221f64, 1e-09f64) || !close(p_out[8].value, 0.07142857142857142f64, 1e-09f64) || !close(p_out[8].upper, 0.19513336248158647f64, 1e-09f64) || !close(p_out[8].lower, 0.0f64, 1e-09f64) || !close(p_out[9].value, 0.08235294117647059f64, 1e-09f64) || !close(p_out[9].upper, 0.18556116315388488f64, 1e-09f64) || !close(p_out[9].lower, 0.0f64, 1e-09f64) || !close(p_out[10].value, 0.06153846153846154f64, 1e-09f64) || !close(p_out[10].upper, 0.1990391312646545f64, 1e-09f64) || !close(p_out[10].lower, 0.0f64, 1e-09f64) || !close(p_out[11].value, 0.11818181818181818f64, 1e-09f64) || !close(p_out[11].upper, 0.17420453676276254f64, 1e-09f64) || !close(p_out[11].lower, 0.009128796570570766f64, 1e-09f64) { os.exit(27) }
    let np_counts = [12]usize{ 3usize, 5usize, 2usize, 8usize, 4usize, 6usize, 1usize, 7usize, 5usize, 4usize, 9usize, 3usize }
    let np_sizes = [12]usize{ 60usize, 60usize, 60usize, 60usize, 60usize, 60usize, 60usize, 60usize, 60usize, 60usize, 60usize, 60usize }
    var np_out: [12]stat.AttributeControlPoint = zero
    let np_error = stat.attribute_control(.Np, np_counts[..], np_sizes[..], np_out[..])
    if np_error != ok || !close(np_out[0].center, 4.75f64, 1e-09f64) || !close(np_out[0].upper, 11.024203136654089f64, 1e-09f64) || !close(np_out[0].lower, 0.0f64, 1e-09f64) || !close(np_out[4].value, 4.0f64, 1e-09f64) { os.exit(28) }
    let c_counts = [10]usize{ 6usize, 9usize, 4usize, 11usize, 7usize, 5usize, 8usize, 12usize, 6usize, 3usize }
    let c_sizes = [10]usize{ 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize }
    var c_out: [10]stat.AttributeControlPoint = zero
    let c_error = stat.attribute_control(.C, c_counts[..], c_sizes[..], c_out[..])
    if c_error != ok || !close(c_out[0].center, 7.1f64, 1e-09f64) || !close(c_out[0].upper, 15.093747556684537f64, 1e-09f64) || !close(c_out[0].lower, 0.0f64, 1e-09f64) { os.exit(29) }
    let u_counts = [8]usize{ 5usize, 9usize, 4usize, 14usize, 7usize, 3usize, 11usize, 6usize }
    let u_sizes = [8]usize{ 20usize, 35usize, 25usize, 40usize, 30usize, 22usize, 38usize, 28usize }
    var u_out: [8]stat.AttributeControlPoint = zero
    let u_error = stat.attribute_control(.U, u_counts[..], u_sizes[..], u_out[..])
    if u_error != ok || !close(u_out[1].center, 0.24789915966386555f64, 1e-09f64) || !close(u_out[1].upper, 0.500377868071683f64, 1e-09f64) || !close(u_out[1].value, 0.2571428571428571f64, 1e-09f64) { os.exit(30) }
    var laney_p: [12]stat.AttributeControlPoint = zero
    let (sigma_p, laney_error_p) = stat.laney_control(.P, p_counts[..], p_sizes[..], laney_p[..])
    if laney_error_p != ok || !close(sigma_p, 1.2551857995031384f64, 1e-09f64) || !close(laney_p[0].lower, 0.0f64, 1e-09f64) || !close(laney_p[0].upper, 0.24533083694303282f64, 1e-09f64) || !close(laney_p[1].lower, 0.0f64, 1e-09f64) || !close(laney_p[1].upper, 0.21314885987498233f64, 1e-09f64) || !close(laney_p[2].lower, 0.0f64, 1e-09f64) || !close(laney_p[2].upper, 0.231942220567801f64, 1e-09f64) || !close(laney_p[3].lower, 0.0f64, 1e-09f64) || !close(laney_p[3].upper, 0.2003236434944895f64, 1e-09f64) || !close(laney_p[4].lower, 0.0f64, 1e-09f64) || !close(laney_p[4].upper, 0.21713293630841557f64, 1e-09f64) { os.exit(31) }
    if !close(laney_p[5].lower, 0.0f64, 1e-09f64) || !close(laney_p[5].upper, 0.2062011768146858f64, 1e-09f64) || !close(laney_p[6].lower, 0.0f64, 1e-09f64) || !close(laney_p[6].upper, 0.23817970433264635f64, 1e-09f64) || !close(laney_p[7].lower, 0.0f64, 1e-09f64) || !close(laney_p[7].upper, 0.19085646206485785f64, 1e-09f64) || !close(laney_p[8].lower, 0.0f64, 1e-09f64) || !close(laney_p[8].upper, 0.2215365939750648f64, 1e-09f64) || !close(laney_p[9].lower, 0.0f64, 1e-09f64) || !close(laney_p[9].upper, 0.20952170530892025f64, 1e-09f64) || !close(laney_p[10].lower, 0.0f64, 1e-09f64) || !close(laney_p[10].upper, 0.22643905948771448f64, 1e-09f64) || !close(laney_p[11].lower, 0.0f64, 1e-09f64) || !close(laney_p[11].upper, 0.19526702913252098f64, 1e-09f64) { os.exit(32) }
    var laney_u: [8]stat.AttributeControlPoint = zero
    let (sigma_u, laney_error_u) = stat.laney_control(.U, u_counts[..], u_sizes[..], laney_u[..])
    if laney_error_u != ok || !close(sigma_u, 1.0192818109680444f64, 1e-09f64) || !close(laney_u[0].lower, 0.0f64, 1e-09f64) || !close(laney_u[0].upper, 0.5883371816396907f64, 1e-09f64) || !close(laney_u[1].lower, 0.0f64, 1e-09f64) || !close(laney_u[1].upper, 0.5052461148006585f64, 1e-09f64) || !close(laney_u[2].lower, 0.0f64, 1e-09f64) || !close(laney_u[2].upper, 0.5523961833692705f64, 1e-09f64) || !close(laney_u[3].lower, 0.007173125751024634f64, 1e-09f64) || !close(laney_u[3].upper, 0.4886251935767065f64, 1e-09f64) || !close(laney_u[4].lower, 0.0f64, 1e-09f64) || !close(laney_u[4].upper, 0.5258656406249249f64, 1e-09f64) { os.exit(33) }
    if !close(laney_u[5].lower, 0.0f64, 1e-09f64) || !close(laney_u[5].upper, 0.5724940775745837f64, 1e-09f64) || !close(laney_u[6].lower, 0.0009194600859741275f64, 1e-09f64) || !close(laney_u[6].upper, 0.494878859241757f64, 1e-09f64) || !close(laney_u[7].lower, 0.0f64, 1e-09f64) || !close(laney_u[7].upper, 0.5356218024080944f64, 1e-09f64) { os.exit(34) }
    let phase_starts = [12]bool{ true, false, false, false, false, false, true, false, false, false, false, false }
    var phased: [12]stat.AttributeControlPoint = zero
    var phased_sigma: [12]f64 = zero
    let phased_error = stat.laney_control_phased(.P, p_counts[..], p_sizes[..], phase_starts[..], phased[..], phased_sigma[..])
    if phased_error != ok || !close(phased_sigma[0], 1.3690332163127379f64, 1e-09f64) || !close(phased[0].upper, 0.2839198995482324f64, 1e-09f64) || !close(phased[0].lower, 0.0f64, 1e-09f64) || !close(phased[2].upper, 0.26837386075279607f64, 1e-09f64) || !close(phased[2].lower, 0.0f64, 1e-09f64) || !close(phased[4].upper, 0.2511782296900557f64, 1e-09f64) || !close(phased[4].lower, 0.0f64, 1e-09f64) || !close(phased_sigma[6], 0.727035935572886f64, 1e-09f64) || !close(phased[6].upper, 0.15863358977041975f64, 1e-09f64) || !close(phased[6].lower, 0.0f64, 1e-09f64) || !close(phased[8].upper, 0.14961125158748678f64, 1e-09f64) || !close(phased[8].lower, 0.008804589996671636f64, 1e-09f64) || !close(phased[10].upper, 0.15226890997194506f64, 1e-09f64) || !close(phased[10].lower, 0.006146931612213358f64, 1e-09f64) { os.exit(35) }
    let gaps = [12]usize{ 3usize, 0usize, 5usize, 12usize, 1usize, 7usize, 2usize, 0usize, 9usize, 4usize, 6usize, 15usize }
    let (g_limits, g_error) = stat.g_control_limits(gaps[..])
    if g_error != ok || !close(g_limits.center, 3.036287943522134f64, 1e-08f64) || !close(g_limits.lower, 0.0f64, 1e-08f64) || !close(g_limits.upper, 37.47136308354743f64, 1e-08f64) { os.exit(36) }
    let intervals = [15]f64{ 5.438f64, 0.696f64, 2.029f64, 1.806f64, 5.112f64, 2.365f64, 6.715f64, 1.178f64, 6.406f64, 5.73f64, 0.063f64, 0.091f64, 1.298f64, 2.218f64, 0.312f64 }
    let (t_limits, t_error) = stat.t_exponential_control_limits(intervals[..])
    if t_error != ok || !close(t_limits.center, 1.9157201776315764f64, 1e-09f64) || !close(t_limits.lower, 0.0037336507817089504f64, 1e-09f64) || !close(t_limits.upper, 18.26222496743666f64, 1e-09f64) { os.exit(37) }
    let series = [140]f64{ -0.247f64, 1.504f64, 1.056f64, -0.032f64, -0.889f64, -0.491f64, 1.026f64, 0.789f64, 0.529f64, 0.247f64, 0.638f64, 0.669f64, 0.719f64, 1.267f64, 0.791f64, 1.107f64, 1.027f64, 0.886f64, 0.92f64, -0.327f64, 1.493f64, 2.217f64, 1.551f64, -0.437f64, 1.619f64, -0.133f64, -1.0f64, -1.453f64, 0.551f64, -0.974f64, -0.5f64, -0.167f64, 0.167f64, 0.5f64, 0.833f64, 1.167f64, 1.5f64, -0.976f64, -1.095f64, 0.843f64, -1.787f64, 0.883f64, -0.309f64, 0.292f64, 0.739f64, 1.98f64, -2.126f64, 0.604f64, -0.708f64, 0.508f64, 0.6f64, -0.6f64, 0.6f64, -0.6f64, 0.6f64, -0.6f64, 0.6f64, -0.6f64, 0.6f64, -0.6f64, 0.6f64, -0.6f64, 0.6f64, -0.6f64, 0.6f64, -0.6f64, -1.556f64, -0.273f64, 0.766f64, 0.944f64, 0.416f64, 1.884f64, 0.396f64, -0.068f64, -1.348f64, 0.637f64, 0.907f64, 2.798f64, 2.449f64, 1.635f64, 3.4f64, -2.09f64, 0.135f64, -0.083f64, -0.667f64, -0.1f64, -0.231f64, -2.095f64, 1.361f64, 0.63f64, 2.3f64, 0.2f64, 2.6f64, -0.545f64, -0.873f64, -0.469f64, 1.128f64, 0.512f64, 0.769f64, 1.35f64, 0.43f64, -0.848f64, -0.752f64, -0.392f64, -0.155f64, -0.717f64, 0.317f64, 0.808f64, 0.313f64, 0.754f64, -0.072f64, -0.581f64, -0.851f64, 0.386f64, -0.225f64, 0.772f64, 0.732f64, 1.718f64, 0.242f64, 0.353f64, 1.4f64, -1.6f64, 1.4f64, -1.6f64, 1.4f64, -1.6f64, 1.4f64, -1.6f64, 1.693f64, -1.25f64, 0.047f64, -1.292f64, -0.695f64, -0.233f64, -1.105f64, -0.4f64, -0.592f64, -1.338f64, -0.287f64, 0.917f64 }
    let centers = [140]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let sigmas = [140]f64{ 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64 }
    var signals: [140]stat.ControlSignal = zero
    let signal_error = stat.control_run_rules(series[..], centers[..], sigmas[..], signals[..])
    if signal_error != ok { os.exit(38) }
    let want_beyond3 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var beyond3_ok = true
    var beyond3_i = 0usize
    while beyond3_i < 140usize {
        if signals[beyond3_i].beyond3 != want_beyond3[beyond3_i] { beyond3_ok = false }
        beyond3_i += 1usize
    }
    if !beyond3_ok { os.exit(39) }
    let want_same_side9 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var same_side9_ok = true
    var same_side9_i = 0usize
    while same_side9_i < 140usize {
        if signals[same_side9_i].same_side9 != want_same_side9[same_side9_i] { same_side9_ok = false }
        same_side9_i += 1usize
    }
    if !same_side9_ok { os.exit(40) }
    let want_trend6 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var trend6_ok = true
    var trend6_i = 0usize
    while trend6_i < 140usize {
        if signals[trend6_i].trend6 != want_trend6[trend6_i] { trend6_ok = false }
        trend6_i += 1usize
    }
    if !trend6_ok { os.exit(41) }
    let want_alternating14 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false }
    var alternating14_ok = true
    var alternating14_i = 0usize
    while alternating14_i < 140usize {
        if signals[alternating14_i].alternating14 != want_alternating14[alternating14_i] { alternating14_ok = false }
        alternating14_i += 1usize
    }
    if !alternating14_ok { os.exit(42) }
    let want_two_of_three2 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var two_of_three2_ok = true
    var two_of_three2_i = 0usize
    while two_of_three2_i < 140usize {
        if signals[two_of_three2_i].two_of_three2 != want_two_of_three2[two_of_three2_i] { two_of_three2_ok = false }
        two_of_three2_i += 1usize
    }
    if !two_of_three2_ok { os.exit(43) }
    let want_four_of_five1 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var four_of_five1_ok = true
    var four_of_five1_i = 0usize
    while four_of_five1_i < 140usize {
        if signals[four_of_five1_i].four_of_five1 != want_four_of_five1[four_of_five1_i] { four_of_five1_ok = false }
        four_of_five1_i += 1usize
    }
    if !four_of_five1_ok { os.exit(44) }
    let want_within1_15 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var within1_15_ok = true
    var within1_15_i = 0usize
    while within1_15_i < 140usize {
        if signals[within1_15_i].within1_15 != want_within1_15[within1_15_i] { within1_15_ok = false }
        within1_15_i += 1usize
    }
    if !within1_15_ok { os.exit(45) }
    let want_outside1_8 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, false, false }
    var outside1_8_ok = true
    var outside1_8_i = 0usize
    while outside1_8_i < 140usize {
        if signals[outside1_8_i].outside1_8 != want_outside1_8[outside1_8_i] { outside1_8_ok = false }
        outside1_8_i += 1usize
    }
    if !outside1_8_ok { os.exit(46) }
    let run_starts = [140]bool{ true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var phased_signals: [140]stat.ControlSignal = zero
    let phased_signal_error = stat.control_run_rules_phased(series[..], centers[..], sigmas[..], run_starts[..], phased_signals[..])
    if phased_signal_error != ok { os.exit(47) }
    let pwant_same_side9 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var psame_side9_ok = true
    var psame_side9_i = 0usize
    while psame_side9_i < 140usize {
        if phased_signals[psame_side9_i].same_side9 != pwant_same_side9[psame_side9_i] { psame_side9_ok = false }
        psame_side9_i += 1usize
    }
    if !psame_side9_ok { os.exit(48) }
    let pwant_trend6 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var ptrend6_ok = true
    var ptrend6_i = 0usize
    while ptrend6_i < 140usize {
        if phased_signals[ptrend6_i].trend6 != pwant_trend6[ptrend6_i] { ptrend6_ok = false }
        ptrend6_i += 1usize
    }
    if !ptrend6_ok { os.exit(49) }
    let pwant_four_of_five1 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var pfour_of_five1_ok = true
    var pfour_of_five1_i = 0usize
    while pfour_of_five1_i < 140usize {
        if phased_signals[pfour_of_five1_i].four_of_five1 != pwant_four_of_five1[pfour_of_five1_i] { pfour_of_five1_ok = false }
        pfour_of_five1_i += 1usize
    }
    if !pfour_of_five1_ok { os.exit(50) }
    let pwant_within1_15 = [140]bool{ false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, true, true, true, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false }
    var pwithin1_15_ok = true
    var pwithin1_15_i = 0usize
    while pwithin1_15_i < 140usize {
        if phased_signals[pwithin1_15_i].within1_15 != pwant_within1_15[pwithin1_15_i] { pwithin1_15_ok = false }
        pwithin1_15_i += 1usize
    }
    if !pwithin1_15_ok { os.exit(51) }
    let gl_references = [5]f64{ 2.0f64, 4.0f64, 6.0f64, 8.0f64, 10.0f64 }
    let gl_measurements = [15]f64{ 2.0964f64, 2.1044f64, 2.119f64, 4.112f64, 4.1084f64, 4.1735f64, 6.1333f64, 6.1464f64, 6.1766f64, 8.1835f64, 8.1524f64, 8.2277f64, 10.3274f64, 10.2225f64, 10.2483f64 }
    var gl_biases: [15]f64 = zero
    var gl_means: [5]f64 = zero
    var gl_fitted: [5]f64 = zero
    var gl_lower: [5]f64 = zero
    var gl_upper: [5]f64 = zero
    let (linearity, linearity_error) = stat.gage_linearity(gl_references[..], gl_measurements[..], 3usize, 2.1603686564627913f64, gl_biases[..], gl_means[..], gl_fitted[..], gl_lower[..], gl_upper[..])
    if linearity_error != ok || !close(linearity.slope, 0.018775000000000062f64, 1e-09f64) || !close(linearity.intercept, 0.056136666666666404f64, 1e-09f64) || !close(linearity.average_bias, 0.16878666666666678f64, 1e-09f64) { os.exit(52) }
    if !close(linearity.residual_sigma, 0.035734687235162425f64, 1e-09f64) || !close(linearity.slope_standard_error, 0.0032621157140150622f64, 1e-09f64) || !close(linearity.slope_p, 6.648973169279468e-05f64, 1e-07f64) || !close(linearity.linearity, 0.1502000000000005f64, 1e-09f64) { os.exit(53) }
    if !close(gl_fitted[0], 0.09368666666666653f64, 1e-09f64) || !close(gl_lower[0], 0.0591617331547321f64, 1e-09f64) || !close(gl_upper[0], 0.12821160017860095f64, 1e-09f64) || !close(gl_means[0], 0.1066000000000001f64, 1e-09f64) || !close(gl_fitted[1], 0.13123666666666667f64, 1e-09f64) || !close(gl_lower[1], 0.10682385206036316f64, 1e-09f64) || !close(gl_upper[1], 0.15564948127297018f64, 1e-09f64) || !close(gl_means[1], 0.13129999999999983f64, 1e-09f64) || !close(gl_fitted[2], 0.16878666666666678f64, 1e-09f64) || !close(gl_lower[2], 0.1488536870097975f64, 1e-09f64) || !close(gl_upper[2], 0.18871964632353605f64, 1e-09f64) || !close(gl_means[2], 0.1520999999999999f64, 1e-09f64) || !close(gl_fitted[3], 0.2063366666666669f64, 1e-09f64) || !close(gl_lower[3], 0.18192385206036338f64, 1e-09f64) || !close(gl_upper[3], 0.2307494812729704f64, 1e-09f64) || !close(gl_means[3], 0.187866666666667f64, 1e-09f64) || !close(gl_fitted[4], 0.24388666666666703f64, 1e-09f64) || !close(gl_lower[4], 0.2093617331547326f64, 1e-09f64) || !close(gl_upper[4], 0.27841160017860145f64, 1e-09f64) || !close(gl_means[4], 0.2660666666666671f64, 1e-09f64) { os.exit(54) }
    let aa_standard = [12]usize{ 0usize, 2usize, 1usize, 2usize, 2usize, 1usize, 1usize, 0usize, 2usize, 0usize, 1usize, 0usize }
    let aa_ratings = [108]usize{ 2usize, 2usize, 2usize, 2usize, 2usize, 2usize, 1usize, 1usize, 1usize, 2usize, 2usize, 2usize, 2usize, 2usize, 2usize, 1usize, 1usize, 0usize, 2usize, 1usize, 1usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 2usize, 2usize, 2usize, 1usize, 1usize, 1usize, 2usize, 2usize, 2usize, 2usize, 2usize, 2usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 2usize, 2usize, 2usize, 2usize, 2usize, 2usize, 0usize, 0usize, 0usize, 2usize, 2usize, 2usize, 1usize, 1usize, 1usize, 0usize, 0usize, 0usize, 2usize, 2usize, 2usize, 0usize, 1usize, 1usize, 2usize, 2usize, 2usize, 0usize, 2usize, 2usize, 1usize, 1usize, 1usize, 1usize, 1usize, 1usize, 2usize, 2usize, 2usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize }
    var aa_within: [3]stat.AttributeAgreementRate = zero
    var aa_standard_rates: [3]stat.AttributeAgreementRate = zero
    let (agreement, agreement_error) = stat.attribute_agreement(aa_standard[..], aa_ratings[..], 3usize, 3usize, 3usize, 0.95f64, aa_within[..], aa_standard_rates[..])
    if agreement_error != ok || aa_within[0].matched != 10usize || !close(aa_within[0].confidence.low, 0.515862251314033f64, 1e-07f64) || !close(aa_within[0].confidence.high, 0.9791374745399076f64, 1e-07f64) || aa_standard_rates[0].matched != 8usize || !close(aa_standard_rates[0].confidence.low, 0.34887550641881554f64, 1e-07f64) || !close(aa_standard_rates[0].confidence.high, 0.9007539088504167f64, 1e-07f64) || aa_within[1].matched != 12usize || !close(aa_within[1].confidence.low, 0.7353515306029488f64, 1e-07f64) || !close(aa_within[1].confidence.high, 1.0f64, 1e-07f64) || aa_standard_rates[1].matched != 9usize || !close(aa_standard_rates[1].confidence.low, 0.4281415381218109f64, 1e-07f64) || !close(aa_standard_rates[1].confidence.high, 0.9451393554720072f64, 1e-07f64) { os.exit(55) }
    if aa_within[2].matched != 10usize || !close(aa_within[2].confidence.low, 0.515862251314033f64, 1e-07f64) || !close(aa_within[2].confidence.high, 0.9791374745399076f64, 1e-07f64) || aa_standard_rates[2].matched != 7usize || !close(aa_standard_rates[2].confidence.low, 0.27666968568210587f64, 1e-07f64) || !close(aa_standard_rates[2].confidence.high, 0.8483477701915698f64, 1e-07f64) || agreement.between_matched != 3usize || agreement.all_vs_standard_matched != 3usize || !close(agreement.pooled_rating_fraction, 0.7407407407407407f64, 1e-09f64) || !close(agreement.pooled_rating_kappa, 0.611111111111111f64, 1e-09f64) { os.exit(56) }
    let (written, write_error) = os.write(os.stdout(), "algo stat spc reference ok\n")
    os.exit(0)
    ret ok
}
