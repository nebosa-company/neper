// Audio analysis over caller `[]f64` mono storage at a caller sample rate:
// pitch by YIN, a reduced probabilistic YIN, normalised autocorrelation and
// the harmonic product spectrum; onset strength by spectral flux and onset
// picking over an adaptive threshold; tempo from the autocorrelation of the
// onset envelope; dynamic programming beat tracking (Ellis 2007); pitch class
// chroma; integrated loudness after ITU-R BS.1770-4; and voice activity flags
// from energy, zero crossings and spectral flatness.
//
// FFT frames are powers of two. Scratch is caller storage sized as each
// function says; nothing allocates.

use e.dsp
use e.math
use e.math.fft

error Invalid
error TooSmall

fn abs(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

// The offset in [-0.5, 0.5] of the extremum of the parabola through three
// equally spaced samples (`0` when they are collinear).
fn parabolic(ym: f64, y0: f64, yp: f64) -> f64 {
    let denominator = ym - 2.0f64 * y0 + yp
    if denominator == 0.0f64 { ret 0.0f64 }
    ret 0.5f64 * (ym - yp) / denominator
}

fn magnitudes(re: []f64, im: []const f64, count: usize) {
    var k = 0usize
    while k < count {
        re[k] = math.sqrt[f64](re[k] * re[k] + im[k] * im[k])
        k += 1usize
    }
}

// --- pitch ----------------------------------------------------------------------

// The cumulative mean normalised difference function of `x` into `out`
// (`x.len / 2` entries, `out[0] = 1`); answers the entry count.
fn yin_difference(x: []const f64, out: []f64) -> (usize, err) {
    let w = x.len / 2usize
    if w < 3usize { ret (0usize, Invalid) }
    if out.len < w { ret (0usize, TooSmall) }
    out[0usize] = 1.0f64
    var running = 0.0f64
    var tau = 1usize
    while tau < w {
        var d = 0.0f64
        var j = 0usize
        while j < w {
            let diff = x[j] - x[j + tau]
            d += diff * diff
            j += 1usize
        }
        running += d
        if running > 0.0f64 { out[tau] = d * f64(tau) / running } else { out[tau] = 1.0f64 }
        tau += 1usize
    }
    ret (w, ok)
}

// The first lag whose difference dips below `threshold`, walked down to its
// local minimum, or the global minimum when none does; answers (lag, value).
fn yin_pick(cmnd: []const f64, threshold: f64) -> (usize, f64) {
    var tau = 2usize
    while tau < cmnd.len {
        if cmnd[tau] < threshold {
            while tau + 1usize < cmnd.len && cmnd[tau + 1usize] < cmnd[tau] { tau += 1usize }
            ret (tau, cmnd[tau])
        }
        tau += 1usize
    }
    var best = 2usize
    tau = 3usize
    while tau < cmnd.len {
        if cmnd[tau] < cmnd[best] { best = tau }
        tau += 1usize
    }
    ret (best, cmnd[best])
}

fn yin_frequency(cmnd: []const f64, tau: usize, sample_rate: f64) -> f64 {
    var shift = 0.0f64
    if tau + 1usize < cmnd.len { shift = parabolic(cmnd[tau - 1usize], cmnd[tau], cmnd[tau + 1usize]) }
    ret sample_rate / (f64(tau) + shift)
}

// YIN (de Cheveigne and Kawahara 2002): the first dip of the cumulative mean
// normalised difference below `threshold`, parabolically refined; answers
// (f0, confidence = 1 - dip depth); `scratch.len >= x.len / 2`.
fn pitch_yin(x: []const f64, sample_rate: f64, threshold: f64, scratch: []f64) -> (f64, f64, err) {
    let (w, difference_error) = yin_difference(x, scratch)
    if difference_error != ok { ret (0.0f64, 0.0f64, difference_error) }
    let cmnd = scratch[..w]
    let (tau, value) = yin_pick(cmnd, threshold)
    ret (yin_frequency(cmnd, tau, sample_rate), 1.0f64 - value, ok)
}

// Probabilistic YIN, reduced to one frame: every entry of `thresholds` picks a
// YIN candidate, the answer is the mean f0 of the candidates that dipped below
// their threshold and the fraction of thresholds that did (the voicing
// probability); with no dip the global minimum answers with probability 0.
// `scratch.len >= x.len / 2`.
// ponytail: no Viterbi over frames (Mauch and Dixon 2014 smooth the candidate
// distributions with an HMM); the per-frame candidate mean is the estimate.
fn pitch_pyin(x: []const f64, sample_rate: f64, thresholds: []const f64, scratch: []f64) -> (f64, f64, err) {
    if thresholds.len == 0usize { ret (0.0f64, 0.0f64, Invalid) }
    let (w, difference_error) = yin_difference(x, scratch)
    if difference_error != ok { ret (0.0f64, 0.0f64, difference_error) }
    let cmnd = scratch[..w]
    var voiced = 0usize
    var sum = 0.0f64
    var i = 0usize
    while i < thresholds.len {
        let (tau, value) = yin_pick(cmnd, thresholds[i])
        if value < thresholds[i] {
            voiced += 1usize
            sum += yin_frequency(cmnd, tau, sample_rate)
        }
        i += 1usize
    }
    if voiced == 0usize {
        let (tau, _) = yin_pick(cmnd, 0.0f64)
        ret (yin_frequency(cmnd, tau, sample_rate), 0.0f64, ok)
    }
    ret (sum / f64(voiced), f64(voiced) / f64(thresholds.len), ok)
}

fn autocorrelation_lag(x: []const f64, tau: usize) -> f64 {
    var sum = 0.0f64
    var j = 0usize
    while j + tau < x.len {
        sum += x[j] * x[j + tau]
        j += 1usize
    }
    ret sum
}

// The lag of the largest normalised autocorrelation between the periods of
// `f_max` and `f_min`, parabolically refined; `scratch.len >= sample_rate / f_min + 2`.
fn pitch_autocorrelation(x: []const f64, sample_rate: f64, f_min: f64, f_max: f64, scratch: []f64) -> (f64, err) {
    if f_min <= 0.0f64 || f_max <= f_min || sample_rate <= 0.0f64 { ret (0.0f64, Invalid) }
    let lo = usize(sample_rate / f_max)
    let hi = usize(sample_rate / f_min)
    if lo < 2usize || hi + 2usize > x.len { ret (0.0f64, Invalid) }
    if scratch.len < hi + 2usize { ret (0.0f64, TooSmall) }
    let r0 = autocorrelation_lag(x, 0usize)
    if r0 <= 0.0f64 { ret (0.0f64, Invalid) }
    var tau = lo - 1usize
    while tau <= hi + 1usize {
        scratch[tau] = autocorrelation_lag(x, tau) / r0
        tau += 1usize
    }
    var best = lo
    tau = lo + 1usize
    while tau <= hi {
        if scratch[tau] > scratch[best] { best = tau }
        tau += 1usize
    }
    let shift = parabolic(scratch[best - 1usize], scratch[best], scratch[best + 1usize])
    ret (sample_rate / (f64(best) + shift), ok)
}

// Harmonic product spectrum: the product of the first `harmonics` decimated
// magnitude spectra of the Hann-windowed FFT of `x` (a power of two) peaks at
// f0, refined by a parabola through the log product; `scratch.len >= 3 * x.len`.
fn pitch_hps(x: []const f64, sample_rate: f64, harmonics: usize, scratch: []f64) -> (f64, err) {
    let n = x.len
    if harmonics == 0usize || n < 4usize * harmonics { ret (0.0f64, Invalid) }
    if scratch.len < 3usize * n { ret (0.0f64, TooSmall) }
    var re = scratch[..n]
    var im = scratch[n..2usize * n]
    var win = scratch[2usize * n..3usize * n]
    let window_error = dsp.window(.Hann, n, win)
    if window_error != ok { ret (0.0f64, window_error) }
    var i = 0usize
    while i < n {
        re[i] = x[i] * win[i]
        im[i] = 0.0f64
        i += 1usize
    }
    let fft_error = fft.fft(re, im)
    if fft_error != ok { ret (0.0f64, fft_error) }
    let half = n / 2usize + 1usize
    magnitudes(re, im, half)
    let count = half / harmonics
    var k = 0usize
    while k < count {
        var product = 1.0f64
        var h = 1usize
        while h <= harmonics {
            product = product * re[k * h]
            h += 1usize
        }
        im[k] = math.log[f64](product + 1.0e-300f64)
        k += 1usize
    }
    var best = 1usize
    k = 2usize
    while k < count {
        if im[k] > im[best] { best = k }
        k += 1usize
    }
    var shift = 0.0f64
    if best + 1usize < count { shift = parabolic(im[best - 1usize], im[best], im[best + 1usize]) }
    ret ((f64(best) + shift) * sample_rate / f64(n), ok)
}

// --- onsets, tempo and beats ------------------------------------------------------

fn frame_count(n: usize, frame: usize, hop: usize) -> usize { ret (n - frame) / hop + 1usize }

// Spectral flux: the half-wave rectified magnitude increase summed over the
// bins up to Nyquist of every Hann-windowed STFT frame (`frame` a power of
// two), the first frame against silence; answers the frame count
// `(x.len - frame) / hop + 1`; `scratch.len >= (2 * frames + 1) * frame`.
fn onset_strength(x: []const f64, frame: usize, hop: usize, scratch: []f64, out: []f64) -> (usize, err) {
    if hop == 0usize || frame == 0usize || x.len < frame { ret (0usize, Invalid) }
    let frames = frame_count(x.len, frame, hop)
    if out.len < frames || scratch.len < (2usize * frames + 1usize) * frame { ret (0usize, TooSmall) }
    var win = scratch[..frame]
    var re = scratch[frame..(frames + 1usize) * frame]
    var im = scratch[(frames + 1usize) * frame..(2usize * frames + 1usize) * frame]
    let window_error = dsp.window(.Hann, frame, win)
    if window_error != ok { ret (0usize, window_error) }
    let (_, stft_error) = dsp.stft(x, frame, hop, win, re, im)
    if stft_error != ok { ret (0usize, stft_error) }
    let half = frame / 2usize + 1usize
    var f = 0usize
    while f < frames {
        magnitudes(re[f * frame..(f + 1usize) * frame], im[f * frame..(f + 1usize) * frame], half)
        var flux = 0.0f64
        var k = 0usize
        while k < half {
            var rise = re[f * frame + k]
            if f > 0usize { rise -= re[(f - 1usize) * frame + k] }
            if rise > 0.0f64 { flux += rise }
            k += 1usize
        }
        out[f] = flux
        f += 1usize
    }
    ret (frames, ok)
}

// Frames where `envelope` peaks (rises into and does not fall out of) and
// exceeds the mean of its seven-frame neighbourhood by more than `threshold`.
fn onsets_pick(envelope: []const f64, threshold: f64, out: []usize) -> (usize, err) {
    let n = envelope.len
    var count = 0usize
    var t = 0usize
    while t < n {
        var lo = 0usize
        if t >= 3usize { lo = t - 3usize }
        var hi = t + 4usize
        if hi > n { hi = n }
        var sum = 0.0f64
        var j = lo
        while j < hi {
            sum += envelope[j]
            j += 1usize
        }
        let mean = sum / f64(hi - lo)
        var peak = t == 0usize || envelope[t] > envelope[t - 1usize]
        if t + 1usize < n && envelope[t] < envelope[t + 1usize] { peak = false }
        if peak && envelope[t] > mean + threshold {
            if count >= out.len { ret (count, TooSmall) }
            out[count] = t
            count += 1usize
        }
        t += 1usize
    }
    ret (count, ok)
}

// Onset frames of `x`: `onset_strength` followed by `onsets_pick`;
// `scratch.len >= (2 * frames + 1) * frame + frames`; answers the onset count.
fn onsets(x: []const f64, frame: usize, hop: usize, threshold: f64, scratch: []f64, out: []usize) -> (usize, err) {
    if hop == 0usize || frame == 0usize || x.len < frame { ret (0usize, Invalid) }
    let frames = frame_count(x.len, frame, hop)
    if scratch.len < frames { ret (0usize, TooSmall) }
    let (_, strength_error) = onset_strength(x, frame, hop, scratch[frames..], scratch[..frames])
    if strength_error != ok { ret (0usize, strength_error) }
    let (count, pick_error) = onsets_pick(scratch[..frames], threshold, out)
    ret (count, pick_error)
}

// The tempo in beats per minute: the lag between 40 and 200 BPM whose
// autocorrelation of the mean-removed onset envelope is largest.
fn tempo(envelope: []const f64, hop: usize, sample_rate: f64) -> (f64, err) {
    let n = envelope.len
    if hop == 0usize || sample_rate <= 0.0f64 || n < 2usize { ret (0.0f64, Invalid) }
    let frames_per_second = sample_rate / f64(hop)
    var lo = usize(math.ceil[f64](60.0f64 * frames_per_second / 200.0f64))
    if lo < 1usize { lo = 1usize }
    var hi = usize(60.0f64 * frames_per_second / 40.0f64)
    if hi >= n { hi = n - 1usize }
    if lo > hi { ret (0.0f64, Invalid) }
    var mean = 0.0f64
    var t = 0usize
    while t < n {
        mean += envelope[t]
        t += 1usize
    }
    mean = mean / f64(n)
    var best = lo
    var best_value = 0.0f64
    var lag = lo
    while lag <= hi {
        var sum = 0.0f64
        t = 0usize
        while t + lag < n {
            sum += (envelope[t] - mean) * (envelope[t + lag] - mean)
            t += 1usize
        }
        if lag == lo || sum > best_value {
            best = lag
            best_value = sum
        }
        lag += 1usize
    }
    ret (60.0f64 * frames_per_second / f64(best), ok)
}

// Beat frames by dynamic programming (Ellis 2007): the score of a beat at `t`
// is the envelope there plus the best score of a beat between half and twice
// the period earlier, less `tightness` times the squared log of the interval
// over the period; the best final score is traced back. `scratch.len >= 2 *
// envelope.len`; answers the beat count, ascending in `out`.
fn beats(envelope: []const f64, bpm: f64, hop: usize, sample_rate: f64, tightness: f64, scratch: []f64, out: []usize) -> (usize, err) {
    let n = envelope.len
    if bpm <= 0.0f64 || hop == 0usize || sample_rate <= 0.0f64 || n == 0usize { ret (0usize, Invalid) }
    if scratch.len < 2usize * n { ret (0usize, TooSmall) }
    var score = scratch[..n]
    var link = scratch[n..2usize * n]
    let period = 60.0f64 * sample_rate / (bpm * f64(hop))
    let lo = usize(math.round[f64](period / 2.0f64))
    let hi = usize(math.round[f64](period * 2.0f64))
    var t = 0usize
    while t < n {
        var best = 0.0f64
        var best_prev = 0.0f64 - 1.0f64
        var delta = lo
        while delta <= hi && delta <= t {
            let ratio = math.log[f64](f64(delta) / period)
            let candidate = score[t - delta] - tightness * ratio * ratio
            if best_prev < 0.0f64 || candidate > best {
                best = candidate
                best_prev = f64(t - delta)
            }
            delta += 1usize
        }
        score[t] = envelope[t]
        if best_prev >= 0.0f64 { score[t] += best }
        link[t] = best_prev
        t += 1usize
    }
    var end = 0usize
    t = 1usize
    while t < n {
        if score[t] > score[end] { end = t }
        t += 1usize
    }
    var count = 0usize
    var at = f64(end)
    while at >= 0.0f64 {
        if count >= out.len { ret (count, TooSmall) }
        out[count] = usize(at)
        count += 1usize
        at = link[usize(at)]
    }
    var i = 0usize
    while i + 1usize < count - i {
        let swap = out[i]
        out[i] = out[count - 1usize - i]
        out[count - 1usize - i] = swap
        i += 1usize
    }
    ret (count, ok)
}

// --- chroma ---------------------------------------------------------------------------

// Pitch class energy per Hann-windowed STFT frame (`frame` a power of two):
// the power of every bin from A0 up to Nyquist is added to the equal-tempered
// pitch class nearest its centre (C = 0); `out` holds `12 * frames`, frame
// major; `scratch.len >= (2 * frames + 1) * frame`; answers the frame count.
fn chroma(x: []const f64, sample_rate: f64, frame: usize, hop: usize, scratch: []f64, out: []f64) -> (usize, err) {
    if hop == 0usize || frame == 0usize || x.len < frame || sample_rate <= 0.0f64 { ret (0usize, Invalid) }
    let frames = frame_count(x.len, frame, hop)
    if out.len < 12usize * frames || scratch.len < (2usize * frames + 1usize) * frame { ret (0usize, TooSmall) }
    var win = scratch[..frame]
    var re = scratch[frame..(frames + 1usize) * frame]
    var im = scratch[(frames + 1usize) * frame..(2usize * frames + 1usize) * frame]
    let window_error = dsp.window(.Hann, frame, win)
    if window_error != ok { ret (0usize, window_error) }
    let (_, stft_error) = dsp.stft(x, frame, hop, win, re, im)
    if stft_error != ok { ret (0usize, stft_error) }
    var f = 0usize
    while f < frames {
        var c = 0usize
        while c < 12usize {
            out[f * 12usize + c] = 0.0f64
            c += 1usize
        }
        var k = 1usize
        while k <= frame / 2usize {
            let hz = f64(k) * sample_rate / f64(frame)
            if hz >= 27.5f64 {
                let midi = 69.0f64 + 12.0f64 * math.log2[f64](hz / 440.0f64)
                let class = usize(math.round[f64](midi)) % 12usize
                let a = re[f * frame + k]
                let b = im[f * frame + k]
                out[f * 12usize + class] += a * a + b * b
            }
            k += 1usize
        }
        f += 1usize
    }
    ret (frames, ok)
}

// --- loudness -------------------------------------------------------------------------

fn block_loudness(z: f64) -> f64 { ret -0.691f64 + 10.0f64 * math.log10[f64](z) }

// Integrated loudness of a mono signal after ITU-R BS.1770-4: K-weighting
// (the high shelf and the high-pass as tabulated for 48 kHz), 400 ms blocks
// every 100 ms, blocks below -70 LUFS dropped, then blocks more than 10 LU
// below the mean of the rest dropped; answers the mean loudness of what
// remains, `-inf` for silence; `scratch.len >= 2 * x.len + 4`.
// ponytail: the filter coefficients are the specification's 48 kHz table;
// another rate needs the Annex 1 redesign, which is not done here.
fn loudness_lufs(x: []const f64, sample_rate: f64, scratch: []f64) -> (f64, err) {
    let n = x.len
    let block = usize(0.4f64 * sample_rate)
    let hop = usize(0.1f64 * sample_rate)
    if sample_rate <= 0.0f64 || block == 0usize || hop == 0usize || n < block { ret (0.0f64, Invalid) }
    if scratch.len < 2usize * n + 4usize { ret (0.0f64, TooSmall) }
    var shelf: [6]f64 = zero
    shelf[0usize] = 1.53512485958697f64
    shelf[1usize] = -2.69169618940638f64
    shelf[2usize] = 1.19839281085285f64
    shelf[3usize] = 1.0f64
    shelf[4usize] = -1.69065929318241f64
    shelf[5usize] = 0.73248077421585f64
    var highpass: [6]f64 = zero
    highpass[0usize] = 1.0f64
    highpass[1usize] = -2.0f64
    highpass[2usize] = 1.0f64
    highpass[3usize] = 1.0f64
    highpass[4usize] = -1.99004745483398f64
    highpass[5usize] = 0.99007225036621f64
    var first = scratch[..n]
    var second = scratch[n..2usize * n]
    var state = scratch[2usize * n..2usize * n + 4usize]
    let shelf_error = dsp.biquad(x, shelf[..], first, state[..2usize])
    if shelf_error != ok { ret (0.0f64, shelf_error) }
    let highpass_error = dsp.biquad(first, highpass[..], second, state[2usize..4usize])
    if highpass_error != ok { ret (0.0f64, highpass_error) }
    // Block powers overwrite `first`, which the second stage no longer needs.
    let blocks = (n - block) / hop + 1usize
    var j = 0usize
    while j < blocks {
        var sum = 0.0f64
        var i = 0usize
        while i < block {
            let s = second[j * hop + i]
            sum += s * s
            i += 1usize
        }
        first[j] = sum / f64(block)
        j += 1usize
    }
    var gated_sum = 0.0f64
    var gated = 0usize
    j = 0usize
    while j < blocks {
        if block_loudness(first[j]) > -70.0f64 {
            gated_sum += first[j]
            gated += 1usize
        }
        j += 1usize
    }
    if gated == 0usize { ret (0.0f64 - math.inf64(), ok) }
    let relative = block_loudness(gated_sum / f64(gated)) - 10.0f64
    gated_sum = 0.0f64
    gated = 0usize
    j = 0usize
    while j < blocks {
        let l = block_loudness(first[j])
        if l > -70.0f64 && l > relative {
            gated_sum += first[j]
            gated += 1usize
        }
        j += 1usize
    }
    if gated == 0usize { ret (0.0f64 - math.inf64(), ok) }
    ret (block_loudness(gated_sum / f64(gated)), ok)
}

// --- voice activity ---------------------------------------------------------------

// One flag per non-overlapping frame of `frame` samples (a power of two):
// active when the mean square exceeds `energy`, the zero-crossing fraction is
// below `zcr` and the spectral flatness (geometric over arithmetic mean of
// the power spectrum up to Nyquist) is below `flatness`; `scratch.len >= 2 *
// frame`; answers the frame count `x.len / frame`.
fn voice_activity(x: []const f64, frame: usize, energy: f64, zcr: f64, flatness: f64, scratch: []f64, out: []bool) -> (usize, err) {
    if frame < 2usize { ret (0usize, Invalid) }
    let frames = x.len / frame
    if out.len < frames || scratch.len < 2usize * frame { ret (0usize, TooSmall) }
    var re = scratch[..frame]
    var im = scratch[frame..2usize * frame]
    let half = frame / 2usize + 1usize
    var f = 0usize
    while f < frames {
        let block = x[f * frame..(f + 1usize) * frame]
        var power = 0.0f64
        var crossings = 0usize
        var i = 0usize
        while i < frame {
            power += block[i] * block[i]
            if i > 0usize && ((block[i] >= 0.0f64) != (block[i - 1usize] >= 0.0f64)) { crossings += 1usize }
            re[i] = block[i]
            im[i] = 0.0f64
            i += 1usize
        }
        power = power / f64(frame)
        let fft_error = fft.fft(re, im)
        if fft_error != ok { ret (0usize, fft_error) }
        var log_sum = 0.0f64
        var sum = 0.0f64
        var k = 0usize
        while k < half {
            let p = re[k] * re[k] + im[k] * im[k]
            log_sum += math.log[f64](p + 1.0e-20f64)
            sum += p
            k += 1usize
        }
        var flat = 1.0f64
        if sum > 0.0f64 { flat = math.exp[f64](log_sum / f64(half)) / (sum / f64(half)) }
        let rate = f64(crossings) / f64(frame)
        out[f] = power > energy && rate < zcr && flat < flatness
        f += 1usize
    }
    ret (frames, ok)
}
