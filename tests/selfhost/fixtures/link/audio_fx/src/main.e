// `e.audio.fx` against numpy replicas (scratchpad audio/fx_ref.py) over one
// LCG noise signal: the compressor static curve at ten levels exact and the
// smoothed compressor, the limiter never above its ceiling, the gate, the
// cascaded-biquad equaliser, NLMS echo cancellation by more than 20 dB, the
// three reverb impulse responses to 1e-9, phase vocoder time stretch (length
// and an FFT peak still at 440 Hz), pitch shift by seven semitones (the peak
// at 660 Hz) and TD-PSOLA moving a pulse train by 1.5. Each check exits with
// its own code.

use e.audio.fx as fx
use e.io
use e.math
use e.math.fft
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

// The strongest FFT bin of `y` (a power of two) among bins `1 .. limit`.
fn peak_bin(y: []const f64, limit: usize, re: []f64, im: []f64) -> usize {
    var i = 0usize
    while i < y.len {
        re[i] = y[i]
        im[i] = 0.0f64
        i += 1usize
    }
    if fft.fft(re[..y.len], im[..y.len]) != ok { ret 0usize }
    var best = 1usize
    var k = 2usize
    while k < limit {
        if re[k] * re[k] + im[k] * im[k] > re[best] * re[best] + im[best] * im[best] { best = k }
        k += 1usize
    }
    ret best
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sr = 8192.0f64
    let (scratch, scratch_error) = mem.alloc[f64](a, 100000usize)
    if scratch_error != ok { ret scratch_error }
    let (big, big_error) = mem.alloc[f64](a, 8192usize)
    if big_error != ok { ret big_error }
    var noise: [2048]f64 = zero
    var x: [2048]f64 = zero
    var out: [2048]f64 = zero
    var state = 7u64
    var i = 0usize
    while i < 2048usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        noise[i] = f64(state >> 33u32) / 1073741824.0f64 - 1.0f64
        x[i] = noise[i]
        if i < 1024usize { x[i] = noise[i] * 0.05f64 }
        i += 1usize
    }

    // 1: the compressor static curve and the smoothed compressor.
    var curve: [10]f64 = zero
    curve[2usize] = -0.0625f64
    curve[3usize] = -1.5625f64
    curve[4usize] = -4.5f64
    curve[5usize] = -7.5f64
    curve[6usize] = -10.5f64
    curve[7usize] = -13.5f64
    curve[8usize] = -16.5f64
    curve[9usize] = -19.5f64
    i = 0usize
    while i < 10usize {
        if !near(fx.compressor_gain(-30.0f64 + 4.0f64 * f64(i), -20.0f64, 4.0f64, 6.0f64), curve[i], 1.0e-12f64) { os.exit(1i32) }
        i += 1usize
    }
    if fx.compressor(x[..], -20.0f64, 4.0f64, 0.005f64, 0.05f64, 6.0f64, 3.0f64, sr, out[..]) != ok || !near(digest(out[..]), -0.08600932288545753f64, 1.0e-9f64) { os.exit(1i32) }
    if fx.compressor(x[..], -20.0f64, 0.0f64, 0.005f64, 0.05f64, 6.0f64, 3.0f64, sr, out[..]) != fx.Invalid { os.exit(1i32) }

    // 2: the limiter never exceeds its ceiling; the gate.
    var loud: [2048]f64 = zero
    i = 0usize
    while i < 2048usize {
        loud[i] = 2.0f64 * noise[i]
        i += 1usize
    }
    if fx.limiter(loud[..], 0.5f64, 16usize, 0.01f64, sr, out[..]) != ok || !near(digest(out[..]), -0.17573639522733114f64, 1.0e-9f64) { os.exit(2i32) }
    i = 0usize
    while i < 2048usize {
        if out[i] > 0.5f64 + 1.0e-12f64 || out[i] < -0.5f64 - 1.0e-12f64 { os.exit(2i32) }
        i += 1usize
    }
    if fx.gate(x[..], -20.0f64, 0.001f64, 0.01f64, sr, out[..]) != ok || !near(digest(out[..]), 0.26121090303668937f64, 1.0e-9f64) { os.exit(2i32) }

    // 3: the equaliser.
    var bands: [6]f64 = zero
    bands[0usize] = 500.0f64
    bands[1usize] = 6.0f64
    bands[2usize] = 1.0f64
    bands[3usize] = 2000.0f64
    bands[4usize] = -3.0f64
    bands[5usize] = 2.0f64
    if fx.equalizer(noise[..], bands[..], sr, out[..], scratch) != ok || !near(digest(out[..]), -0.14129681897485383f64, 1.0e-9f64) { os.exit(3i32) }
    if fx.equalizer(noise[..], bands[..5usize], sr, out[..], scratch) != fx.Invalid { os.exit(3i32) }
    if fx.equalizer(noise[..], bands[..], sr, out[..], scratch[..2000usize]) != fx.TooSmall { os.exit(3i32) }

    // 4: echo cancellation of a four-tap echo path.
    var path: [4]f64 = zero
    path[0usize] = 0.5f64
    path[1usize] = 0.3f64
    path[2usize] = -0.2f64
    path[3usize] = 0.1f64
    let (echo_len, echo_error) = fx.reverb_convolution(noise[..], path[..], big)
    if echo_error != ok || echo_len != 2051usize { os.exit(4i32) }
    var w: [8]f64 = zero
    if fx.echo_cancel(big[..2048usize], noise[..], 0.5f64, w[..], out[..]) != ok || !near(digest(out[..]), 0.00500058919880445f64, 1.0e-9f64) { os.exit(4i32) }
    var echo_energy = 0.0f64
    var residual_energy = 0.0f64
    i = 1024usize
    while i < 2048usize {
        echo_energy += big[i] * big[i]
        residual_energy += out[i] * out[i]
        i += 1usize
    }
    if !(echo_energy > 100.0f64 * residual_energy) { os.exit(4i32) }
    i = 0usize
    while i < 4usize {
        if !near(w[i], path[i], 1.0e-9f64) { os.exit(4i32) }
        i += 1usize
    }

    // 5: reverb impulse responses.
    var impulse: [4096]f64 = zero
    impulse[0usize] = 1.0f64
    if fx.reverb_schroeder(impulse[..], 0.84f64, 0.2f64, big, scratch) != ok || !near(digest(big[..4096usize]), 1.5202180663436755f64, 1.0e-9f64) { os.exit(5i32) }
    var delays: [4]usize = zero
    delays[0usize] = 149usize
    delays[1usize] = 211usize
    delays[2usize] = 263usize
    delays[3usize] = 293usize
    if fx.reverb_fdn(impulse[..], delays[..], 0.7f64, big, scratch) != ok || !near(digest(big[..4096usize]), 1.4848240306256348f64, 1.0e-9f64) { os.exit(5i32) }
    let (conv_len, conv_error) = fx.reverb_convolution(noise[..64usize], noise[..8usize], out[..])
    if conv_error != ok || conv_len != 71usize || !near(digest(out[..71usize]), -15.575576712381912f64, 1.0e-9f64) { os.exit(5i32) }
    if fx.reverb_schroeder(impulse[..], 1.0f64, 0.2f64, big, scratch) != fx.Invalid { os.exit(5i32) }

    // 6: phase vocoder time stretch and pitch shift of a 440 Hz tone.
    var tone: [4096]f64 = zero
    i = 0usize
    while i < 4096usize {
        tone[i] = math.sin[f64](6.283185307179586f64 * 440.0f64 * f64(i) / sr)
        i += 1usize
    }
    if fx.time_stretch_len(4096usize, 1.5f64, 512usize, 128usize) != 5888usize || fx.time_stretch_scratch(4096usize, 1.5f64, 512usize, 128usize) != 38144usize { os.exit(6i32) }
    let (stretched, stretch_error) = fx.time_stretch(tone[..], 1.5f64, 512usize, 128usize, big, scratch)
    if stretch_error != ok || stretched != 5888usize || !near(digest(big[..5888usize]), -1.2413258465343076f64, 1.0e-6f64) { os.exit(6i32) }
    if peak_bin(big[1024usize..5120usize], 2048usize, scratch[..4096usize], scratch[4096usize..8192usize]) != 220usize { os.exit(6i32) }
    var shifted: [4096]f64 = zero
    if fx.pitch_shift(tone[..], 7.0f64, 512usize, 128usize, shifted[..], scratch) != ok || !near(digest(shifted[..]), 0.7207760963348742f64, 1.0e-6f64) { os.exit(6i32) }
    if peak_bin(shifted[..], 2048usize, scratch[..4096usize], scratch[4096usize..8192usize]) != 330usize { os.exit(6i32) }
    let (_, stretch_room) = fx.time_stretch(tone[..], 1.5f64, 512usize, 128usize, big, scratch[..1000usize])
    if stretch_room != fx.TooSmall { os.exit(6i32) }

    // 7: TD-PSOLA of a period-80 pulse train by 1.5.
    var pulses: [4096]f64 = zero
    var marks: [51]usize = zero
    i = 0usize
    while i < 51usize {
        marks[i] = 40usize + 80usize * i
        pulses[marks[i]] = 1.0f64
        i += 1usize
    }
    if fx.psola(pulses[..], marks[..], 1.5f64, big) != ok || !near(digest(big[..4096usize]), -1.0064309788619994f64, 1.0e-9f64) { os.exit(7i32) }
    if peak_bin(big[..4096usize], 150usize, scratch[..4096usize], scratch[4096usize..8192usize]) != 77usize { os.exit(7i32) }
    if fx.psola(pulses[..], marks[..1usize], 1.5f64, big) != fx.Invalid { os.exit(7i32) }

    try io.print("audio fx ok\n")
    ret ok
}
