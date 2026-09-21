// Audio effects over caller `[]f64` mono storage at a caller sample rate:
// dynamics (a feed-forward compressor with a log-domain gain computer and
// smoothed detector, a look-ahead peak limiter, a noise gate), a parametric
// equaliser of cascaded peaking biquads, an NLMS acoustic echo canceller,
// three reverbs (Schroeder/Freeverb combs and allpasses, a four-line feedback
// delay network with a Householder matrix, direct convolution), a phase
// vocoder time stretch and the pitch shift built on it, and TD-PSOLA over
// caller pitch marks.
//
// Times are seconds, levels are dB, frequencies are Hz. Scratch is caller
// storage sized as each function says; nothing allocates.

use e.dsp
use e.math

error Invalid
error TooSmall

fn abs(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn db_to_gain(db: f64) -> f64 { ret math.exp[f64](db * 0.11512925464970229f64) }

fn gain_to_db(g: f64) -> f64 { ret 20.0f64 * math.log10[f64](g) }

// The one-pole smoothing coefficient of a time constant in seconds (`0` for none).
fn coefficient(seconds: f64, sample_rate: f64) -> f64 {
    if seconds <= 0.0f64 { ret 0.0f64 }
    ret math.exp[f64](0.0f64 - 1.0f64 / (seconds * sample_rate))
}

// --- dynamics -------------------------------------------------------------------------

// The static curve: the gain in dB (at most 0) applied to a level of
// `level_db` by a compressor of `threshold_db`, `ratio` and a soft knee
// `knee_db` wide (Giannoulis, Massberg and Reiss 2012).
fn compressor_gain(level_db: f64, threshold_db: f64, ratio: f64, knee_db: f64) -> f64 {
    let over = level_db - threshold_db
    if 2.0f64 * over <= 0.0f64 - knee_db { ret 0.0f64 }
    if 2.0f64 * abs(over) <= knee_db {
        let edge = over + knee_db / 2.0f64
        ret (1.0f64 / ratio - 1.0f64) * edge * edge / (2.0f64 * knee_db)
    }
    ret (1.0f64 / ratio - 1.0f64) * over
}

// Feed-forward compressor: the level of every sample in dB drives the static
// curve, the gain reduction is smoothed in the log domain with `attack` when
// it grows and `release` when it shrinks, then `makeup_db` is added.
fn compressor(x: []const f64, threshold_db: f64, ratio: f64, attack: f64, release: f64, knee_db: f64, makeup_db: f64, sample_rate: f64, out: []f64) -> err {
    if ratio <= 0.0f64 || knee_db < 0.0f64 || sample_rate <= 0.0f64 { ret Invalid }
    if out.len < x.len { ret TooSmall }
    let a = coefficient(attack, sample_rate)
    let r = coefficient(release, sample_rate)
    var reduction = 0.0f64
    var n = 0usize
    while n < x.len {
        var level = abs(x[n])
        if level < 1.0e-12f64 { level = 1.0e-12f64 }
        let wanted = 0.0f64 - compressor_gain(gain_to_db(level), threshold_db, ratio, knee_db)
        if wanted > reduction { reduction = a * reduction + (1.0f64 - a) * wanted } else { reduction = r * reduction + (1.0f64 - r) * wanted }
        out[n] = x[n] * db_to_gain(makeup_db - reduction)
        n += 1usize
    }
    ret ok
}

// Look-ahead peak limiter: the output is `x` delayed by `lookahead` samples
// (zeros first) times a gain that drops at once to keep the loudest sample of
// the last `lookahead + 1` under `ceiling` and recovers with `release`; no
// output sample exceeds `ceiling` in magnitude.
// ponytail: the peak search is O(lookahead) per sample; a monotonic deque
// makes it O(1) if the look-ahead grows long.
fn limiter(x: []const f64, ceiling: f64, lookahead: usize, release: f64, sample_rate: f64, out: []f64) -> err {
    if ceiling <= 0.0f64 || sample_rate <= 0.0f64 { ret Invalid }
    if out.len < x.len { ret TooSmall }
    let r = coefficient(release, sample_rate)
    var gain = 1.0f64
    var n = 0usize
    while n < x.len {
        var peak = 0.0f64
        var j = 0usize
        while j <= lookahead && j <= n {
            let v = abs(x[n - j])
            if v > peak { peak = v }
            j += 1usize
        }
        var wanted = 1.0f64
        if peak > ceiling { wanted = ceiling / peak }
        if wanted < gain { gain = wanted } else { gain = r * gain + (1.0f64 - r) * wanted }
        if n >= lookahead { out[n] = x[n - lookahead] * gain } else { out[n] = 0.0f64 }
        n += 1usize
    }
    ret ok
}

// Noise gate: a peak envelope (instant rise, `release` fall) above
// `threshold_db` opens the gate, whose gain moves between 0 and 1 with
// `attack` and `release`.
fn gate(x: []const f64, threshold_db: f64, attack: f64, release: f64, sample_rate: f64, out: []f64) -> err {
    if sample_rate <= 0.0f64 { ret Invalid }
    if out.len < x.len { ret TooSmall }
    let a = coefficient(attack, sample_rate)
    let r = coefficient(release, sample_rate)
    let threshold = db_to_gain(threshold_db)
    var envelope = 0.0f64
    var gain = 0.0f64
    var n = 0usize
    while n < x.len {
        let level = abs(x[n])
        if level > envelope { envelope = level } else { envelope = r * envelope }
        var wanted = 0.0f64
        if envelope > threshold { wanted = 1.0f64 }
        if wanted > gain { gain = a * gain + (1.0f64 - a) * wanted } else { gain = r * gain + (1.0f64 - r) * wanted }
        out[n] = x[n] * gain
        n += 1usize
    }
    ret ok
}

// --- equaliser and echo -------------------------------------------------------------

// Cascaded peaking biquads, one per `(frequency_hz, gain_db, q)` triple of
// `bands`; `scratch.len >= x.len + 2`.
fn equalizer(x: []const f64, bands: []const f64, sample_rate: f64, out: []f64, scratch: []f64) -> err {
    if bands.len % 3usize != 0usize || sample_rate <= 0.0f64 { ret Invalid }
    if out.len < x.len || scratch.len < x.len + 2usize { ret TooSmall }
    var n = 0usize
    while n < x.len {
        out[n] = x[n]
        n += 1usize
    }
    var state = scratch[x.len..x.len + 2usize]
    var section: [6]f64 = zero
    var band = 0usize
    while band < bands.len {
        let frequency = bands[band] / (sample_rate / 2.0f64)
        if frequency <= 0.0f64 || frequency >= 1.0f64 || bands[band + 2usize] <= 0.0f64 { ret Invalid }
        let design_error = dsp.biquad_peak(frequency, bands[band + 2usize], bands[band + 1usize], section[..])
        if design_error != ok { ret design_error }
        n = 0usize
        while n < x.len {
            scratch[n] = out[n]
            n += 1usize
        }
        let filter_error = dsp.biquad(scratch[..x.len], section[..], out, state)
        if filter_error != ok { ret filter_error }
        band += 3usize
    }
    ret ok
}

// NLMS acoustic echo cancellation: `w` (the taps, zeroed by the caller and
// left holding the echo path estimate) tracks `mic` from `reference`; `out`
// is the residual `mic - estimated echo`.
fn echo_cancel(mic: []const f64, reference: []const f64, mu: f64, w: []f64, out: []f64) -> err {
    if mu <= 0.0f64 { ret Invalid }
    if mic.len < reference.len { ret TooSmall }
    ret dsp.nlms(reference, mic, mu, 1.0e-6f64, w, out)
}

// --- reverbs ---------------------------------------------------------------------------

fn comb_delay(i: usize) -> usize {
    if i == 0usize { ret 1116usize }
    if i == 1usize { ret 1188usize }
    if i == 2usize { ret 1277usize }
    ret 1356usize
}

// Freeverb's allpass over a circular buffer: `y = -x + delayed; buffer = x + delayed / 2`.
fn allpass_step(buffer: []f64, n: usize, input: f64) -> f64 {
    let at = n % buffer.len
    let delayed = buffer[at]
    buffer[at] = input + delayed * 0.5f64
    ret delayed - input
}

// Schroeder reverb with Freeverb's first four low-pass feedback combs (1116,
// 1188, 1277 and 1356 samples, `feedback` gain, `damp` in the loop) in
// parallel into its first two allpasses (556 and 441) in series; the wet
// signal only; `scratch.len >= 5934`, cleared by the call.
// ponytail: the delays are Freeverb's 44.1 kHz constants at any sample rate.
fn reverb_schroeder(x: []const f64, feedback: f64, damp: f64, out: []f64, scratch: []f64) -> err {
    if feedback < 0.0f64 || feedback >= 1.0f64 || damp < 0.0f64 || damp > 1.0f64 { ret Invalid }
    if out.len < x.len || scratch.len < 5934usize { ret TooSmall }
    dsp.clear(scratch[..5934usize])
    var store: [4]f64 = zero
    var n = 0usize
    while n < x.len {
        var sum = 0.0f64
        var offset = 0usize
        var i = 0usize
        while i < 4usize {
            let d = comb_delay(i)
            let at = offset + n % d
            let delayed = scratch[at]
            store[i] = delayed * (1.0f64 - damp) + store[i] * damp
            scratch[at] = x[n] + feedback * store[i]
            sum += delayed
            offset += d
            i += 1usize
        }
        let first = allpass_step(scratch[4937usize..5493usize], n, sum)
        out[n] = allpass_step(scratch[5493usize..5934usize], n, first)
        n += 1usize
    }
    ret ok
}

// A four-line feedback delay network: the delayed outputs are summed for the
// output and fed back through the Householder matrix `I - 11^T / 2` times
// `feedback` plus the input; `delays` has four positive lengths and
// `scratch.len >= delays[0] + ... + delays[3]`, cleared by the call.
fn reverb_fdn(x: []const f64, delays: []const usize, feedback: f64, out: []f64, scratch: []f64) -> err {
    if delays.len < 4usize || feedback < 0.0f64 || feedback >= 1.0f64 { ret Invalid }
    var total = 0usize
    var i = 0usize
    while i < 4usize {
        if delays[i] == 0usize { ret Invalid }
        total += delays[i]
        i += 1usize
    }
    if out.len < x.len || scratch.len < total { ret TooSmall }
    dsp.clear(scratch[..total])
    var n = 0usize
    while n < x.len {
        var v: [4]f64 = zero
        var sum = 0.0f64
        var offset = 0usize
        i = 0usize
        while i < 4usize {
            v[i] = scratch[offset + n % delays[i]]
            sum += v[i]
            offset += delays[i]
            i += 1usize
        }
        offset = 0usize
        i = 0usize
        while i < 4usize {
            scratch[offset + n % delays[i]] = x[n] + feedback * (v[i] - 0.5f64 * sum)
            offset += delays[i]
            i += 1usize
        }
        out[n] = sum
        n += 1usize
    }
    ret ok
}

// The full linear convolution of `x` with `impulse` (`x.len + impulse.len - 1`
// samples, answered); `out` at least that long.
// ponytail: direct O(n m); `fft.convolve` when the impulse runs to seconds.
fn reverb_convolution(x: []const f64, impulse: []const f64, out: []f64) -> (usize, err) {
    if x.len == 0usize || impulse.len == 0usize { ret (0usize, Invalid) }
    let n = x.len + impulse.len - 1usize
    if out.len < n { ret (0usize, TooSmall) }
    dsp.clear(out[..n])
    var i = 0usize
    while i < x.len {
        var j = 0usize
        while j < impulse.len {
            out[i + j] += x[i] * impulse[j]
            j += 1usize
        }
        i += 1usize
    }
    ret (n, ok)
}

// --- time and pitch -----------------------------------------------------------------

fn wrap_phase(p: f64) -> f64 { ret p - 6.283185307179586f64 * math.round[f64](p / 6.283185307179586f64) }

fn synthesis_hop(hop: usize, ratio: f64) -> usize { ret usize(math.round[f64](f64(hop) * ratio)) }

// The output length of `time_stretch`.
fn time_stretch_len(x_len: usize, ratio: f64, frame: usize, hop: usize) -> usize {
    if hop == 0usize || frame == 0usize || x_len < frame { ret 0usize }
    ret ((x_len - frame) / hop) * synthesis_hop(hop, ratio) + frame
}

// The scratch `time_stretch` needs for these arguments.
fn time_stretch_scratch(x_len: usize, ratio: f64, frame: usize, hop: usize) -> usize {
    if hop == 0usize || frame == 0usize || x_len < frame { ret 0usize }
    let frames = (x_len - frame) / hop + 1usize
    ret (2usize * frames + 5usize) * frame + time_stretch_len(x_len, ratio, frame, hop)
}

// Phase vocoder time stretch by `ratio` (2 is twice as long, the pitch
// unchanged): a Hann STFT every `hop` samples (`frame` a power of two) is
// resynthesised every `round(hop * ratio)` samples with the phase of every
// bin advanced by its measured instantaneous frequency; answers the output
// length `time_stretch_len`; `scratch.len >= time_stretch_scratch`.
// ponytail: no phase locking across bins (Laroche and Dolson 1999), so
// transients smear a little; add identity phase locking if that matters.
fn time_stretch(x: []const f64, ratio: f64, frame: usize, hop: usize, out: []f64, scratch: []f64) -> (usize, err) {
    if hop == 0usize || frame < 2usize || x.len < frame || ratio <= 0.0f64 { ret (0usize, Invalid) }
    let hop_s = synthesis_hop(hop, ratio)
    if hop_s == 0usize { ret (0usize, Invalid) }
    let frames = (x.len - frame) / hop + 1usize
    let n_out = (frames - 1usize) * hop_s + frame
    if out.len < n_out || scratch.len < (2usize * frames + 5usize) * frame + n_out { ret (0usize, TooSmall) }
    var win = scratch[..frame]
    var re = scratch[frame..(frames + 1usize) * frame]
    var im = scratch[(frames + 1usize) * frame..(2usize * frames + 1usize) * frame]
    var previous = scratch[(2usize * frames + 1usize) * frame..(2usize * frames + 2usize) * frame]
    var accumulated = scratch[(2usize * frames + 2usize) * frame..(2usize * frames + 3usize) * frame]
    var rest = scratch[(2usize * frames + 3usize) * frame..(2usize * frames + 5usize) * frame + n_out]
    let window_error = dsp.window(.Hann, frame, win)
    if window_error != ok { ret (0usize, window_error) }
    let (_, stft_error) = dsp.stft(x, frame, hop, win, re, im)
    if stft_error != ok { ret (0usize, stft_error) }
    let two_pi = 6.283185307179586f64
    let stretch = f64(hop_s) / f64(hop)
    var t = 0usize
    while t < frames {
        var k = 0usize
        while k < frame {
            let at = t * frame + k
            let magnitude = math.sqrt[f64](re[at] * re[at] + im[at] * im[at])
            let phase = math.atan2[f64](im[at], re[at])
            if t == 0usize {
                accumulated[k] = phase
            } else {
                let expected = two_pi * f64(k) * f64(hop) / f64(frame)
                let deviation = wrap_phase(phase - previous[k] - expected)
                accumulated[k] = wrap_phase(accumulated[k] + (expected + deviation) * stretch)
            }
            previous[k] = phase
            re[at] = magnitude * math.cos[f64](accumulated[k])
            im[at] = magnitude * math.sin[f64](accumulated[k])
            k += 1usize
        }
        t += 1usize
    }
    let istft_error = dsp.istft(re, im, frames, frame, hop_s, win, out, rest)
    if istft_error != ok { ret (0usize, istft_error) }
    ret (n_out, ok)
}

// Pitch shift by `semitones`: `time_stretch` by the frequency ratio and a
// windowed-sinc resample back to `x.len` samples into `out`; `scratch.len >=
// time_stretch_scratch + time_stretch_len` for `ratio = 2^(semitones / 12)`.
fn pitch_shift(x: []const f64, semitones: f64, frame: usize, hop: usize, out: []f64, scratch: []f64) -> err {
    let ratio = math.exp2[f64](semitones / 12.0f64)
    let n_stretched = time_stretch_len(x.len, ratio, frame, hop)
    if n_stretched == 0usize { ret Invalid }
    if out.len < x.len || scratch.len < n_stretched + time_stretch_scratch(x.len, ratio, frame, hop) { ret TooSmall }
    let (_, stretch_error) = time_stretch(x, ratio, frame, hop, scratch[..n_stretched], scratch[n_stretched..])
    if stretch_error != ok { ret stretch_error }
    ret dsp.resample_sinc(scratch[..n_stretched], 1.0f64 / ratio, 16usize, out[..x.len])
}

// TD-PSOLA: a Hann grain two periods wide around every analysis mark is
// overlap-added at synthesis marks spaced `period / ratio` (the nearest
// analysis mark supplies each grain, so the duration is kept and the pitch
// moves by `ratio`); `marks` ascending, the period of a mark the distance to
// the next; `out.len >= x.len`, cleared by the call.
fn psola(x: []const f64, marks: []const usize, ratio: f64, out: []f64) -> err {
    if marks.len < 2usize || ratio <= 0.0f64 { ret Invalid }
    if out.len < x.len { ret TooSmall }
    var j = 0usize
    while j + 1usize < marks.len {
        if marks[j + 1usize] <= marks[j] { ret Invalid }
        j += 1usize
    }
    dsp.clear(out[..x.len])
    var t = f64(marks[0usize])
    j = 0usize
    while t < f64(x.len) {
        while j + 1usize < marks.len && abs(f64(marks[j + 1usize]) - t) < abs(f64(marks[j]) - t) { j += 1usize }
        var period = 0usize
        if j + 1usize < marks.len { period = marks[j + 1usize] - marks[j] } else { period = marks[j] - marks[j - 1usize] }
        let centre = i64(math.round[f64](t))
        var i = 0i64 - i64(period)
        while i <= i64(period) {
            let source = i64(marks[j]) + i
            let destination = centre + i
            if source >= 0i64 && source < i64(x.len) && destination >= 0i64 && destination < i64(x.len) {
                let w = 0.5f64 + 0.5f64 * math.cos[f64](3.141592653589793f64 * f64(i) / f64(period))
                out[usize(destination)] += x[usize(source)] * w
            }
            i += 1i64
        }
        t += f64(period) / ratio
    }
    ret ok
}
