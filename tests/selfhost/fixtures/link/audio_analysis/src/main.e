// `e.audio.analysis` against numpy replicas (scratchpad audio/analysis_ref.py):
// YIN, pYIN, autocorrelation and HPS pitch of a 220 Hz tone with harmonics
// all within 0.5 Hz; spectral flux onsets, tempo and beats of a 120 BPM click
// train exact; chroma of a C major chord peaks at C, E and G; a -23 LUFS
// calibrated 1 kHz sine reads -23.0 +- 0.1 after BS.1770; voice activity flags.
// Each check exits with its own code.

use e.audio.analysis as analysis
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
    let sr = 8192.0f64
    let two_pi = 6.283185307179586f64
    let (scratch, scratch_error) = mem.alloc[f64](a, 100000usize)
    if scratch_error != ok { ret scratch_error }
    var x: [4096]f64 = zero
    var i = 0usize
    while i < 4096usize {
        let t = f64(i) / sr
        x[i] = math.sin[f64](two_pi * 220.0f64 * t) + 0.5f64 * math.sin[f64](two_pi * 440.0f64 * t) + 0.25f64 * math.sin[f64](two_pi * 660.0f64 * t)
        i += 1usize
    }

    // 1: YIN and pYIN.
    let (yin_f0, yin_confidence, yin_error) = analysis.pitch_yin(x[..], sr, 0.1f64, scratch)
    if yin_error != ok || !near(yin_f0, 220.0771382309434f64, 1.0e-6f64) || !near(yin_confidence, 0.9984578213987664f64, 1.0e-9f64) { os.exit(1i32) }
    if !near(yin_f0, 220.0f64, 0.5f64) { os.exit(1i32) }
    var thresholds: [4]f64 = zero
    thresholds[0usize] = 0.05f64
    thresholds[1usize] = 0.1f64
    thresholds[2usize] = 0.2f64
    thresholds[3usize] = 0.3f64
    let (pyin_f0, voiced, pyin_error) = analysis.pitch_pyin(x[..], sr, thresholds[..], scratch)
    if pyin_error != ok || !near(pyin_f0, 220.0771382309434f64, 1.0e-6f64) || voiced != 1.0f64 { os.exit(1i32) }
    let (_, _, short_error) = analysis.pitch_yin(x[..4usize], sr, 0.1f64, scratch)
    if short_error != analysis.Invalid { os.exit(1i32) }

    // 2: autocorrelation and harmonic product spectrum.
    let (acf_f0, acf_error) = analysis.pitch_autocorrelation(x[..], sr, 80.0f64, 1000.0f64, scratch)
    if acf_error != ok || !near(acf_f0, 220.01034391844564f64, 1.0e-6f64) || !near(acf_f0, 220.0f64, 0.5f64) { os.exit(2i32) }
    let (hps_f0, hps_error) = analysis.pitch_hps(x[..], sr, 3usize, scratch)
    if hps_error != ok || !near(hps_f0, 219.99999514793356f64, 1.0e-6f64) || !near(hps_f0, 220.0f64, 0.5f64) { os.exit(2i32) }
    let (_, room_error) = analysis.pitch_hps(x[..], sr, 3usize, scratch[..100usize])
    if room_error != analysis.TooSmall { os.exit(2i32) }

    // 3: onsets, tempo and beats of a click train at 120 BPM.
    let (clicks, clicks_error) = mem.alloc[f64](a, 16384usize)
    if clicks_error != ok { ret clicks_error }
    i = 0usize
    while i < 16384usize {
        clicks[i] = 0.0f64
        if i % 4096usize == 128usize { clicks[i] = 1.0f64 }
        i += 1usize
    }
    var envelope: [127]f64 = zero
    let (frames, strength_error) = analysis.onset_strength(clicks, 256usize, 128usize, scratch, envelope[..])
    if strength_error != ok || frames != 127usize || !near(digest(envelope[..]), 263.87885502424666f64, 1.0e-9f64) { os.exit(3i32) }
    var marks: [8]usize = zero
    let (onset_count, onsets_error) = analysis.onsets(clicks, 256usize, 128usize, 0.1f64, scratch, marks[..])
    if onsets_error != ok || onset_count != 4usize || marks[0usize] != 0usize || marks[1usize] != 32usize || marks[2usize] != 64usize || marks[3usize] != 96usize { os.exit(3i32) }
    let (bpm, tempo_error) = analysis.tempo(envelope[..], 128usize, sr)
    if tempo_error != ok || !near(bpm, 120.0f64, 1.0e-9f64) { os.exit(3i32) }
    let (beat_count, beats_error) = analysis.beats(envelope[..], bpm, 128usize, sr, 100.0f64, scratch, marks[..])
    if beats_error != ok || beat_count != 4usize || marks[0usize] != 0usize || marks[1usize] != 32usize || marks[2usize] != 64usize || marks[3usize] != 96usize { os.exit(3i32) }
    let (_, beats_room) = analysis.beats(envelope[..], bpm, 128usize, sr, 100.0f64, scratch, marks[..2usize])
    if beats_room != analysis.TooSmall { os.exit(3i32) }

    // 4: chroma of a C major chord.
    var chord: [2048]f64 = zero
    i = 0usize
    while i < 2048usize {
        let t = f64(i) / sr
        chord[i] = math.sin[f64](two_pi * 261.63f64 * t) + math.sin[f64](two_pi * 329.63f64 * t) + math.sin[f64](two_pi * 392.0f64 * t)
        i += 1usize
    }
    var classes: [36]f64 = zero
    let (chroma_frames, chroma_error) = analysis.chroma(chord[..], sr, 1024usize, 512usize, scratch, classes[..])
    if chroma_error != ok || chroma_frames != 3usize || !near(digest(classes[..]), 234911.709508163f64, 1.0e-2f64) { os.exit(4i32) }
    var c = 0usize
    while c < 12usize {
        let chord_tone = c == 0usize || c == 4usize || c == 7usize
        if !chord_tone && classes[c] > classes[0usize] { os.exit(4i32) }
        if !chord_tone && classes[c] > classes[4usize] { os.exit(4i32) }
        if !chord_tone && classes[c] > classes[7usize] { os.exit(4i32) }
        c += 1usize
    }

    // 5: integrated loudness of a -23 LUFS calibrated 1 kHz sine at 48 kHz.
    let (tone, tone_error) = mem.alloc[f64](a, 48000usize)
    if tone_error != ok { ret tone_error }
    i = 0usize
    while i < 48000usize {
        tone[i] = 0.1f64 * math.sin[f64](two_pi * 1000.0f64 * f64(i) / 48000.0f64)
        i += 1usize
    }
    let (lufs, lufs_error) = analysis.loudness_lufs(tone, 48000.0f64, scratch)
    if lufs_error != ok || !near(lufs, -23.00363837508022f64, 1.0e-6f64) || !near(lufs, -23.0f64, 0.1f64) { os.exit(5i32) }
    var quiet: [4096]f64 = zero
    let (silence_lufs, silence_error) = analysis.loudness_lufs(quiet[..], sr, scratch)
    if silence_error != ok || silence_lufs > -1000.0f64 { os.exit(5i32) }

    // 6: voice activity: tone, noise, silence.
    var voice: [3072]f64 = zero
    var state = 99u64
    i = 0usize
    while i < 1024usize {
        voice[i] = 0.5f64 * math.sin[f64](two_pi * 200.0f64 * f64(i) / sr)
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        voice[1024usize + i] = 0.5f64 * (f64(state >> 33u32) / 1073741824.0f64 - 1.0f64)
        i += 1usize
    }
    var flags: [12]bool = zero
    let (voice_frames, voice_error) = analysis.voice_activity(voice[..], 256usize, 0.01f64, 0.2f64, 0.3f64, scratch, flags[..])
    if voice_error != ok || voice_frames != 12usize { os.exit(6i32) }
    i = 0usize
    while i < 12usize {
        if flags[i] != (i < 4usize) { os.exit(6i32) }
        i += 1usize
    }

    try io.print("audio analysis ok\n")
    ret ok
}
