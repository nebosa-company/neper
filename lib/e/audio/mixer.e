// Deterministic in-memory PCM mixing. Voice slots are supplied by the caller, and gain
// is Q16: 65536 is unity.

use e.audio
use e.mem

type Voice = struct { source: audio.Frames, position: usize, gain: i32, loops: bool, playing: bool }
type Mixer = struct { format: audio.Format, voices: []Voice, count: usize, master: i32 }
error Full
error Unsupported

fn init(m: *Mixer, f: audio.Format, voices: []Voice) -> err {
    if f.rate == 0u32 || f.channels == 0u8 || voices.len == 0usize { ret Unsupported }
    m.format = f
    m.voices = voices
    m.count = 0usize
    m.master = 65536i32
    var at = 0usize
    while at < voices.len {
        m.voices[at].position = 0usize
        m.voices[at].gain = 0i32
        m.voices[at].loops = false
        m.voices[at].playing = false
        at += 1usize
    }
    ret ok
}

fn source_supported(m: Mixer, source: audio.Frames) -> bool {
    if source.format.rate != m.format.rate || source.format.channels != m.format.channels { ret false }
    ret source.count <= audio.frames_in(source.format, source.bytes.len)
}

fn play(m: *Mixer, source: audio.Frames, gain: i32, loops: bool) -> (usize, err) {
    if !source_supported(*m, source) { ret (0usize, Unsupported) }
    var slot = 0usize
    while slot < m.voices.len {
        if !m.voices[slot].playing {
            m.voices[slot] = Voice { source: source, position: 0usize, gain: gain, loops: loops, playing: source.count != 0usize }
            if source.count != 0usize { m.count += 1usize }
            ret (slot, ok)
        }
        slot += 1usize
    }
    ret (0usize, Full)
}

fn stop(m: *Mixer, voice: usize) -> err {
    if voice >= m.voices.len { ret Unsupported }
    if m.voices[voice].playing {
        m.voices[voice].playing = false
        m.count -= 1usize
    }
    ret ok
}

fn set_gain(m: *Mixer, voice: usize, gain: i32) -> err {
    if voice >= m.voices.len || !m.voices[voice].playing { ret Unsupported }
    m.voices[voice].gain = gain
    ret ok
}

fn active(m: Mixer) -> usize {
    ret m.count
}

fn clip_i32(value: i64) -> i32 {
    if value < -2147483648i64 { ret (-2147483647i32 - 1i32) }
    if value > 2147483647i64 { ret 2147483647i32 }
    ret i32(value)
}

fn output_supported(m: Mixer, out: audio.Frames) -> bool {
    if out.format.rate != m.format.rate || out.format.channels != m.format.channels || out.format.sample != m.format.sample { ret false }
    ret out.count <= audio.frames_in(out.format, out.bytes.len)
}

fn mix_into(m: *Mixer, out: *audio.Frames) -> (usize, err) {
    if !output_supported(*m, *out) { ret (0usize, Unsupported) }
    let clear_error = audio.silence(out)
    if clear_error != ok { ret (0usize, clear_error) }
    var frame = 0usize
    while frame < out.count {
        var channel = 0u8
        while channel < out.format.channels {
            var sum = 0i64
            var voice = 0usize
            while voice < m.voices.len {
                if m.voices[voice].playing {
                    let (sample, sample_error) = audio.sample_i32(m.voices[voice].source, m.voices[voice].position, channel)
                    if sample_error != ok { ret (frame, sample_error) }
                    let scaled = clip_i32((i64(sample) * i64(m.voices[voice].gain)) / 65536i64)
                    sum = i64(clip_i32(sum + i64(scaled)))
                }
                voice += 1usize
            }
            let mastered = clip_i32((sum * i64(m.master)) / 65536i64)
            let write_error = audio.set_sample_i32(out, frame, channel, mastered)
            if write_error != ok { ret (frame, write_error) }
            channel += 1u8
        }
        var voice = 0usize
        while voice < m.voices.len {
            if m.voices[voice].playing {
                m.voices[voice].position += 1usize
                if m.voices[voice].position == m.voices[voice].source.count {
                    if m.voices[voice].loops {
                        m.voices[voice].position = 0usize
                    } else {
                        m.voices[voice].playing = false
                        m.count -= 1usize
                    }
                }
            }
            voice += 1usize
        }
        frame += 1usize
    }
    ret (out.count, ok)
}

fn resample(a: *mem.Arena, src: audio.Frames, rate: u32) -> (audio.Frames, err) {
    if rate == 0u32 || src.format.rate == 0u32 || src.format.channels == 0u8 || src.count > audio.frames_in(src.format, src.bytes.len) { ret (zero, Unsupported) }
    let quotient = src.count / usize(src.format.rate)
    let remainder = src.count % usize(src.format.rate)
    if quotient != 0usize && usize(rate) > 18446744073709551615usize / quotient { ret (zero, mem.Exhausted) }
    var count = quotient * usize(rate)
    let tail = (remainder * usize(rate)) / usize(src.format.rate)
    if count > 18446744073709551615usize - tail { ret (zero, mem.Exhausted) }
    count += tail
    let format = audio.Format { rate: rate, channels: src.format.channels, sample: src.format.sample }
    let width = audio.frame_bytes(format)
    if count != 0usize && width > 18446744073709551615usize / count { ret (zero, mem.Exhausted) }
    let checkpoint = a.off
    let (bytes, allocation_error) = mem.alloc[u8](a, count * width)
    if allocation_error != ok { ret (zero, allocation_error) }
    var out = audio.Frames { bytes: bytes, format: format, count: count }
    var source_frame = 0usize
    var phase = 0u64
    var frame = 0usize
    while frame < count {
        var channel = 0u8
        while channel < format.channels {
            let (sample, sample_error) = audio.sample_i32(src, source_frame, channel)
            if sample_error != ok {
                a.off = checkpoint
                ret (zero, sample_error)
            }
            let write_error = audio.set_sample_i32(&out, frame, channel, sample)
            if write_error != ok {
                a.off = checkpoint
                ret (zero, write_error)
            }
            channel += 1u8
        }
        phase += u64(src.format.rate)
        while phase >= u64(rate) {
            phase -= u64(rate)
            source_frame += 1usize
        }
        frame += 1usize
    }
    ret (out, ok)
}
