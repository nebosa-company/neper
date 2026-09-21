// `e.dsp` against SciPy, NumPy and Python replicas over one LCG signal:
// smoothing, filters and delay lines, windows and windowed sinc, the four IIR
// designs (butter/cheby1/bessel/ellip coefficients to 1e-9), Parks-McClellan
// (remez to 1e-6), STFT round trip, cepstrum and denoising, MFCC and CQT, LPC
// and DTW, the adaptive filters and both resamplers. Each check exits with its
// own code; arrays are compared through a cosine-weighted digest.

use e.dsp
use e.io
use e.math
use e.mem
use e.os

fn digest(xs: []const f64) -> f64 {
    var d = 0.0f64
    var i = 0usize
    while i < xs.len {
        d += xs[i] * math.cos[f64](f64(i))
        i += 1usize
    }
    ret d
}

fn near(x: f64, want: f64, tol: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < tol
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [64]f64 = zero
    var state = 12345u64
    var i = 0usize
    while i < 64usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        x[i] = f64(state >> 33u32) / 1073741824.0f64 - 1.0f64
        i += 1usize
    }
    var out: [128]f64 = zero
    var scratch: [128]f64 = zero

    // 1: smoothing.
    if dsp.moving_average(x[..], 5usize, out[..]) != ok || !near(digest(out[..60usize]), -0.6713703880082709f64, 1.0e-9f64) { os.exit(1i32) }
    if dsp.ema(x[..], 0.3f64, out[..]) != ok || !near(digest(out[..64usize]), -0.3966679145813195f64, 1.0e-9f64) { os.exit(1i32) }
    if dsp.savitzky_golay(x[..], 7usize, 2usize, out[..], scratch[..]) != ok || !near(digest(out[..64usize]), 0.22405410105783835f64, 1.0e-9f64) { os.exit(1i32) }
    if dsp.zero_crossings(x[..]) != 31usize || dsp.moving_average(x[..], 0usize, out[..]) != dsp.Invalid { os.exit(1i32) }

    // 2: filters and delay lines.
    var taps: [4]f64 = zero
    taps[0usize] = 0.1f64
    taps[1usize] = 0.2f64
    taps[2usize] = 0.3f64
    taps[3usize] = 0.4f64
    if dsp.fir(x[..], taps[..], out[..]) != ok || !near(digest(out[..64usize]), 0.35575773055682464f64, 1.0e-9f64) { os.exit(2i32) }
    if dsp.one_pole(x[..], 0.8f64, out[..]) != ok || !near(digest(out[..64usize]), 0.027048391458389463f64, 1.0e-9f64) { os.exit(2i32) }
    if dsp.comb(x[..], 3usize, 0.5f64, out[..], true) != ok || !near(digest(out[..64usize]), 0.8566220847099503f64, 1.0e-9f64) { os.exit(2i32) }
    if dsp.comb(x[..], 3usize, 0.5f64, out[..], false) != ok || !near(digest(out[..64usize]), 0.6151226235810784f64, 1.0e-9f64) { os.exit(2i32) }
    var section: [6]f64 = zero
    if dsp.biquad_lowpass(0.2f64, 0.707f64, section[..]) != ok || dsp.biquad(x[..], section[..], out[..], scratch[..2usize]) != ok { os.exit(2i32) }
    if !near(digest(out[..64usize]), 0.20164901440908806f64, 1.0e-9f64) { os.exit(2i32) }
    if dsp.biquad_peak(0.5f64, 1.0f64, 6.0f64, section[..]) != ok || !near(digest(section[..]), 0.42686390851238154f64, 1.0e-9f64) { os.exit(2i32) }

    // 3: windows and the windowed sinc.
    if dsp.window(.Hann, 8usize, out[..]) != ok || !near(digest(out[..8usize]), -1.36076155786124f64, 1.0e-9f64) { os.exit(3i32) }
    if dsp.window(.Hamming, 9usize, out[..]) != ok || !near(digest(out[..9usize]), -0.6247710818366455f64, 1.0e-9f64) { os.exit(3i32) }
    if dsp.window(.Blackman, 7usize, out[..]) != ok || !near(digest(out[..7usize]), -1.556845100896143f64, 1.0e-9f64) { os.exit(3i32) }
    if dsp.design_windowed_sinc(11usize, 0.3f64, .Hamming, out[..]) != ok || !near(digest(out[..11usize]), 0.1305567399543801f64, 1.0e-9f64) { os.exit(3i32) }

    // 4: Butterworth and the IIR run.
    var b: [8]f64 = zero
    var den: [8]f64 = zero
    if dsp.design_butterworth(4usize, 0.3f64, b[..], den[..], scratch[..]) != ok { os.exit(4i32) }
    if !near(digest(b[..5usize]), -0.07331062690594391f64, 1.0e-9f64) || !near(digest(den[..5usize]), 0.05041740446820749f64, 1.0e-9f64) { os.exit(4i32) }
    if dsp.iir(x[..], b[..5usize], den[..5usize], out[..], scratch[..4usize]) != ok || !near(digest(out[..64usize]), 0.4778193074124202f64, 1.0e-9f64) { os.exit(4i32) }
    if dsp.design_butterworth(4usize, 1.5f64, b[..], den[..], scratch[..]) != dsp.Invalid { os.exit(4i32) }

    // 5: Chebyshev I.
    if dsp.design_chebyshev(4usize, 1.0f64, 0.3f64, b[..], den[..], scratch[..]) != ok { os.exit(5i32) }
    if !near(digest(b[..5usize]), -0.03302881989917669f64, 1.0e-9f64) || !near(digest(den[..5usize]), -0.10111433542171694f64, 1.0e-9f64) { os.exit(5i32) }
    if dsp.design_chebyshev(3usize, 0.5f64, 0.25f64, b[..], den[..], scratch[..]) != ok { os.exit(5i32) }
    if !near(digest(b[..4usize]), 0.010611975652360578f64, 1.0e-9f64) || !near(digest(den[..4usize]), -0.07811885375758998f64, 1.0e-9f64) { os.exit(5i32) }

    // 6: Bessel.
    if dsp.design_bessel(5usize, 0.3f64, b[..], den[..], scratch[..]) != ok { os.exit(6i32) }
    if !near(digest(b[..6usize]), -0.07752234314463076f64, 1.0e-9f64) || !near(digest(den[..6usize]), -0.011463095811690093f64, 1.0e-9f64) { os.exit(6i32) }

    // 7: elliptic (even, odd and first order).
    if dsp.design_elliptic(4usize, 1.0f64, 40.0f64, 0.3f64, b[..], den[..], scratch[..]) != ok { os.exit(7i32) }
    if !near(digest(b[..5usize]), -0.02160760178336151f64, 1.0e-9f64) || !near(digest(den[..5usize]), -0.0783083367873289f64, 1.0e-9f64) { os.exit(7i32) }
    if dsp.design_elliptic(3usize, 0.5f64, 30.0f64, 0.4f64, b[..], den[..], scratch[..]) != ok { os.exit(7i32) }
    if !near(digest(b[..4usize]), 0.034550698720958256f64, 1.0e-9f64) || !near(digest(den[..4usize]), 0.4992808001741553f64, 1.0e-9f64) { os.exit(7i32) }
    if dsp.design_elliptic(1usize, 1.0f64, 40.0f64, 0.3f64, b[..], den[..], scratch[..]) != ok { os.exit(7i32) }
    if !near(digest(b[..2usize]), 0.7706641291416458f64, 1.0e-9f64) || !near(digest(den[..2usize]), 1.0003598802997995f64, 1.0e-9f64) { os.exit(7i32) }

    // 8: Parks-McClellan against remez.
    var big: [1200]f64 = zero
    var bands: [6]f64 = zero
    var desired: [3]f64 = zero
    var weights: [3]f64 = zero
    bands[1usize] = 0.4f64
    bands[2usize] = 0.6f64
    bands[3usize] = 1.0f64
    desired[0usize] = 1.0f64
    weights[0usize] = 1.0f64
    weights[1usize] = 1.0f64
    if dsp.design_parks_mcclellan(15usize, bands[..4usize], desired[..2usize], weights[..2usize], out[..], big[..]) != ok { os.exit(8i32) }
    if !near(digest(out[..15usize]), 0.7608973066871224f64, 1.0e-6f64) { os.exit(8i32) }
    bands[1usize] = 0.2f64
    bands[2usize] = 0.3f64
    bands[3usize] = 0.6f64
    bands[4usize] = 0.7f64
    bands[5usize] = 1.0f64
    desired[0usize] = 0.0f64
    desired[1usize] = 1.0f64
    weights[0usize] = 2.0f64
    weights[2usize] = 3.0f64
    if dsp.design_parks_mcclellan(21usize, bands[..], desired[..], weights[..], out[..], big[..]) != ok { os.exit(8i32) }
    if !near(digest(out[..21usize]), -0.8503014445889969f64, 1.0e-6f64) { os.exit(8i32) }

    // 9: STFT round trip, cepstrum, spectral subtraction, Wiener.
    var win: [16]f64 = zero
    var re: [112]f64 = zero
    var im: [112]f64 = zero
    if dsp.window(.Hann, 16usize, win[..]) != ok { os.exit(9i32) }
    let (frames, stft_error) = dsp.stft(x[..], 16usize, 8usize, win[..], re[..], im[..])
    if stft_error != ok || frames != 7usize { os.exit(9i32) }
    if !near(digest(re[..]), -2.6771200924902607f64, 1.0e-8f64) || !near(digest(im[..]), 3.6719634496590605f64, 1.0e-8f64) { os.exit(9i32) }
    if dsp.istft(re[..], im[..], 7usize, 16usize, 8usize, win[..], out[..], big[..]) != ok { os.exit(9i32) }
    i = 1usize
    while i < 63usize {
        if !near(out[i], x[i], 1.0e-9f64) { os.exit(9i32) }
        i += 1usize
    }
    if dsp.cepstrum(x[..16usize], out[..], scratch[..]) != ok || !near(digest(out[..16usize]), 0.5512607011298066f64, 1.0e-9f64) { os.exit(9i32) }
    var magnitude: [16]f64 = zero
    var noise: [16]f64 = zero
    if dsp.window(.Rectangular, 16usize, big[..16usize]) != ok { os.exit(9i32) }
    let (_, first_error) = dsp.stft(x[..16usize], 16usize, 16usize, big[..16usize], re[..16usize], im[..16usize])
    let (_, second_error) = dsp.stft(x[16usize..32usize], 16usize, 16usize, big[..16usize], re[16usize..32usize], im[16usize..32usize])
    if first_error != ok || second_error != ok { os.exit(9i32) }
    i = 0usize
    while i < 16usize {
        magnitude[i] = math.sqrt[f64](re[i] * re[i] + im[i] * im[i])
        noise[i] = math.sqrt[f64](re[16usize + i] * re[16usize + i] + im[16usize + i] * im[16usize + i])
        i += 1usize
    }
    if dsp.spectral_subtract(magnitude[..], noise[..], 0.5f64, 0.1f64, out[..]) != ok || !near(digest(out[..16usize]), 0.7995332781229832f64, 1.0e-9f64) { os.exit(9i32) }
    if dsp.wiener(x[..], 0.05f64, 16usize, out[..], scratch[..]) != ok || !near(digest(out[..64usize]), 0.015416041370459377f64, 1.0e-9f64) { os.exit(9i32) }

    // 10: MFCC and CQT.
    let (mel_frames, mfcc_error) = dsp.mfcc(x[..], 8000.0f64, 32usize, 16usize, 6usize, 4usize, out[..], big[..])
    if mfcc_error != ok || mel_frames != 3usize || !near(digest(out[..12usize]), 5.153441009829327f64, 1.0e-6f64) { os.exit(10i32) }
    if dsp.cqt(x[..], 8000.0f64, 800.0f64, 4usize, 6usize, re[..], im[..]) != ok { os.exit(10i32) }
    if !near(digest(re[..6usize]), -0.05881112089956119f64, 1.0e-9f64) || !near(digest(im[..6usize]), -0.015473974604131234f64, 1.0e-9f64) { os.exit(10i32) }
    if dsp.cqt(x[..], 8000.0f64, 100.0f64, 4usize, 1usize, re[..], im[..]) != dsp.Invalid { os.exit(10i32) }

    // 11: LPC and DTW.
    let (power, lpc_error) = dsp.lpc(x[..], 4usize, out[..], scratch[..])
    if lpc_error != ok || !near(digest(out[..5usize]), 1.0704717452651376f64, 1.0e-9f64) || !near(power, 23.09862265617159f64, 1.0e-8f64) { os.exit(11i32) }
    let (distance, dtw_error) = dsp.dtw(x[..10usize], x[10usize..22usize], big[..])
    if dtw_error != ok || !near(distance, 5.803094143047929f64, 1.0e-9f64) { os.exit(11i32) }
    var path_a: [24]usize = zero
    var path_b: [24]usize = zero
    let (steps, path_error) = dsp.dtw_path(big[..], 10usize, 12usize, path_a[..], path_b[..])
    if path_error != ok || steps != 14usize { os.exit(11i32) }
    i = 0usize
    while i < steps {
        out[i] = f64(path_a[i] * 100usize + path_b[i])
        i += 1usize
    }
    if !near(digest(out[..14usize]), 769.8108431449775f64, 1.0e-9f64) || path_a[0usize] != 0usize || path_b[13usize] != 11usize { os.exit(11i32) }

    // 12: adaptive filters and resampling.
    var d: [64]f64 = zero
    i = 2usize
    while i < 64usize {
        d[i] = 0.9f64 * x[i - 2usize]
        i += 1usize
    }
    var w: [4]f64 = zero
    if dsp.lms(x[..], d[..], 0.05f64, w[..], out[..]) != ok || !near(digest(out[..64usize]), 0.9839632132119839f64, 1.0e-9f64) { os.exit(12i32) }
    i = 0usize
    while i < 4usize {
        w[i] = 0.0f64
        i += 1usize
    }
    if dsp.nlms(x[..], d[..], 0.5f64, 0.001f64, w[..], out[..]) != ok || !near(digest(out[..64usize]), 0.6344357026068166f64, 1.0e-9f64) { os.exit(12i32) }
    i = 0usize
    while i < 4usize {
        w[i] = 0.0f64
        i += 1usize
    }
    if dsp.rls(x[..], d[..], 0.99f64, 1.0f64, w[..], scratch[..16usize], scratch[16usize..24usize], out[..]) != ok || !near(digest(out[..64usize]), 0.6195554253295702f64, 1.0e-9f64) { os.exit(12i32) }
    var taps15: [15]f64 = zero
    if dsp.design_windowed_sinc(15usize, 1.0f64 / 3.0f64, .Hamming, taps15[..]) != ok || !near(digest(taps15[..]), 0.41915786647357584f64, 1.0e-9f64) { os.exit(12i32) }
    let (resampled, poly_error) = dsp.resample_polyphase(x[..], 3usize, 2usize, taps15[..], out[..])
    if poly_error != ok || resampled != 96usize || !near(digest(out[..96usize]), 1.3415902801838204f64, 1.0e-9f64) { os.exit(12i32) }
    if dsp.resample_sinc(x[..], 1.5f64, 4usize, out[..96usize]) != ok || !near(digest(out[..96usize]), 1.417640258162624f64, 1.0e-9f64) { os.exit(12i32) }

    try io.print("dsp ok\n")
    ret ok
}
