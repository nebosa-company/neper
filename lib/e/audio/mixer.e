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
