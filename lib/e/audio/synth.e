// Sound synthesis primitives over caller storage: an ADSR envelope state
// machine (per-stage durations, linear segments), PolyBLEP anti-aliased saw and
// square oscillators, a wavetable read with linear or Catmull-Rom cubic
// interpolation and an additive band-limited saw to fill one, and
// Karplus-Strong plucked strings from a PCG noise burst.
//
// A phase is a fraction of a cycle in `[0, 1)` and an increment is cycles per
// sample (`frequency / sample_rate`); the caller accumulates the phase.

use e.algo.rand
use e.math

error Invalid
error TooSmall

type Stage = enum u8 { Idle, Attack, Decay, Sustain, Release }
type Adsr = struct { attack: f64, decay: f64, sustain: f64, release: f64, stage: Stage, level: f64, stage_start: f64, stage_elapsed: f64 }
type Waveform = enum u8 { Saw, Square, Triangle }
type Interpolation = enum u8 { Linear, Cubic }

fn fract(x: f64) -> f64 { ret x - math.floor[f64](x) }

// --- envelope ------------------------------------------------------------------------

// The per-sample step that crosses the unit range in `seconds` (`1`, at once, when 0).
fn rate(seconds: f64, sample_rate: f64) -> f64 {
    if seconds <= 0.0f64 || sample_rate <= 0.0f64 { ret 1.0f64 }
    ret 1.0f64 / (seconds * sample_rate)
}

// The number of whole samples a stage owns. A positive fractional duration rounds
// up because a stage can only finish on a sample boundary; zero remains one
// immediate sample, matching `rate`. Snap products that are within floating-point
// noise of a whole sample first, so `0.07 * 100` remains seven samples.
fn duration_samples(seconds: f64, sample_rate: f64) -> f64 {
    if seconds <= 0.0f64 || sample_rate <= 0.0f64 { ret 1.0f64 }
    let samples = seconds * sample_rate
    let rounded = math.round[f64](samples)
    let tolerance = math.max[f64](1.0f64, math.abs[f64](samples)) * 1.0e-14f64
    if math.abs[f64](samples - rounded) <= tolerance {
        if rounded < 1.0f64 { ret 1.0f64 }
        ret rounded
    }
    let duration = math.ceil[f64](samples)
    if duration < 1.0f64 { ret 1.0f64 }
    ret duration
}

// An idle envelope whose attack, decay and release take that many seconds at
// `sample_rate` and whose sustain level is `sustain`.
fn adsr(attack: f64, decay: f64, sustain: f64, release: f64, sample_rate: f64) -> Adsr {
    ret Adsr { attack: duration_samples(attack, sample_rate), decay: duration_samples(decay, sample_rate), sustain: sustain, release: duration_samples(release, sample_rate), stage: .Idle, level: 0.0f64, stage_start: 0.0f64, stage_elapsed: 0.0f64 }
}

// A note on restarts the attack from the current level; a note off releases
// unless the envelope is idle.
fn adsr_gate(e: *Adsr, on: bool) {
    if on {
        e.stage = .Attack
        e.stage_start = e.level
        e.stage_elapsed = 0.0f64
    } else if e.stage != .Idle && e.stage != .Release {
        e.stage = .Release
        e.stage_start = e.level
        e.stage_elapsed = 0.0f64
    }
}

// Advance a finite stage once and answer its fraction, clamped exactly at one
// so accumulated floating-point rounding cannot add an extra sample.
fn stage_fraction(e: *Adsr, duration: f64) -> f64 {
    e.stage_elapsed += 1.0f64
    if e.stage_elapsed >= duration { ret 1.0f64 }
    ret e.stage_elapsed / duration
}

// The next envelope value: attack rises to 1, decay falls to the sustain
// level and holds there, release falls to 0 and idles.
fn adsr_next(e: *Adsr) -> f64 {
    if e.stage == .Attack {
        let fraction = stage_fraction(e, e.attack)
        e.level = e.stage_start + (1.0f64 - e.stage_start) * fraction
        if fraction >= 1.0f64 {
            e.level = 1.0f64
            e.stage = .Decay
            e.stage_start = 1.0f64
            e.stage_elapsed = 0.0f64
        }
    } else if e.stage == .Decay {
        let fraction = stage_fraction(e, e.decay)
        e.level = 1.0f64 + (e.sustain - 1.0f64) * fraction
        if fraction >= 1.0f64 {
            e.level = e.sustain
            e.stage = .Sustain
            e.stage_elapsed = 0.0f64
        }
    } else if e.stage == .Sustain {
        e.level = e.sustain
    } else if e.stage == .Release {
        let fraction = stage_fraction(e, e.release)
        e.level = e.stage_start * (1.0f64 - fraction)
        if fraction >= 1.0f64 {
            e.level = 0.0f64
            e.stage = .Idle
            e.stage_start = 0.0f64
            e.stage_elapsed = 0.0f64
        }
    }
    ret e.level
}

// --- oscillators --------------------------------------------------------------------

// The polynomial band-limited step correction around a discontinuity at phase
// 0 for a phase `t` and increment `dt` (Valimaki and Huovilainen 2007).
fn polyblep(t: f64, dt: f64) -> f64 {
    if t < dt {
        let u = t / dt
        ret u + u - u * u - 1.0f64
    }
    if t > 1.0f64 - dt {
        let u = (t - 1.0f64) / dt
        ret u * u + u + u + 1.0f64
    }
    ret 0.0f64
}

// The trivial waveform at `phase` in [-1, 1]: a rising saw, a square high in
// the first half cycle, a triangle peaking mid-cycle.
fn oscillator_naive(kind: Waveform, phase: f64) -> f64 {
    let t = fract(phase)
    if kind == .Saw { ret 2.0f64 * t - 1.0f64 }
    if kind == .Square {
        if t < 0.5f64 { ret 1.0f64 }
        ret -1.0f64
    }
    ret 1.0f64 - 4.0f64 * math.abs[f64](t - 0.5f64)
}

// The waveform at `phase` with its steps smoothed by PolyBLEP for an
// `increment` of cycles per sample: the saw's one step and the square's two.
// ponytail: the triangle has no step, only a slope break, and is answered
// naive; PolyBLAMP would smooth the break as well.
fn oscillator_polyblep(kind: Waveform, phase: f64, increment: f64) -> f64 {
    let t = fract(phase)
    if kind == .Saw { ret 2.0f64 * t - 1.0f64 - polyblep(t, increment) }
    if kind == .Square {
        var v = -1.0f64
        if t < 0.5f64 { v = 1.0f64 }
        ret v + polyblep(t, increment) - polyblep(fract(t + 0.5f64), increment)
    }
    ret oscillator_naive(kind, t)
}

// --- wavetable ------------------------------------------------------------------------

// Fills `table` with one cycle of a band-limited saw: the first `harmonics`
// terms of `(2 / pi) sum (-1)^(h + 1) sin(2 pi h t) / h`.
fn wavetable_build(table: []f64, harmonics: usize) -> err {
    let n = table.len
    if n == 0usize || harmonics == 0usize { ret Invalid }
    var i = 0usize
    while i < n {
        let t = f64(i) / f64(n)
        var sum = 0.0f64
        var h = 1usize
        while h <= harmonics {
            var term = math.sin[f64](6.283185307179586f64 * f64(h) * t) / f64(h)
            if h % 2usize == 0usize { term = 0.0f64 - term }
            sum += term
            h += 1usize
        }
        table[i] = 0.6366197723675814f64 * sum
        i += 1usize
    }
    ret ok
}

// The table read at `phase` (wrapping), linearly or by the Catmull-Rom cubic
// through the four neighbouring entries.
fn wavetable(table: []const f64, phase: f64, interpolation: Interpolation) -> f64 {
    let n = table.len
    if n == 0usize { ret 0.0f64 }
    let p = fract(phase) * f64(n)
    var i1 = usize(p)
    let f = p - f64(i1)
    i1 = i1 % n
    let i2 = (i1 + 1usize) % n
    let y1 = table[i1]
    let y2 = table[i2]
    if interpolation == .Linear { ret y1 + (y2 - y1) * f }
    let y0 = table[(i1 + n - 1usize) % n]
    let y3 = table[(i1 + 2usize) % n]
    let c1 = 0.5f64 * (y2 - y0)
    let c2 = y0 - 2.5f64 * y1 + 2.0f64 * y2 - 0.5f64 * y3
    let c3 = 0.5f64 * (y3 - y0) + 1.5f64 * (y1 - y2)
    ret ((c3 * f + c2) * f + c1) * f + y1
}

// --- plucked string --------------------------------------------------------------------

// Karplus-Strong: `round(sample_rate / frequency)` samples of uniform noise in
// [-1, 1) from `r` start `out`, and every later sample is `decay / 2` times
// the sum of the two samples one period earlier (the averaging filter).
fn karplus_strong(frequency: f64, sample_rate: f64, decay: f64, r: *rand.Pcg64, out: []f64) -> err {
    if !(frequency > 0.0f64) || !(sample_rate > 0.0f64) || frequency == math.inf64() || sample_rate == math.inf64() { ret Invalid }
    let period_float = math.round[f64](sample_rate / frequency)
    if period_float < 2.0f64 { ret Invalid }
    // The caller's output length is already a representable usize bound. Test it
    // before narrowing a tiny frequency's enormous (or infinite) period.
    if period_float > f64(out.len) || period_float >= f64(0usize -% 1usize) { ret TooSmall }
    let period = usize(period_float)
    var i = 0usize
    while i < period {
        out[i] = 2.0f64 * rand.pcg64_f64(r) - 1.0f64
        i += 1usize
    }
    while i < out.len {
        out[i] = decay * 0.5f64 * (out[i - period] + out[i - period + 1usize])
        i += 1usize
    }
    ret ok
}
