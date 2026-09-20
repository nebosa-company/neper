// A source at a point in the world becomes a gain and a pan on a mixer voice. Integer
// throughout, so a positioned mix stays as reproducible as an unpositioned one.
//
// Positions and distances are Q16 fixed point (`e.math.fixed`), angles are turns as
// `fixed` counts them: `facing` 0 looks along +x and a quarter turn looks along +y. Every
// gain and pan is Q16 too, `fixed.ONE` being unity, so it drops straight into a mixer
// voice's gain slot. Nothing here is a float or a table.
//
// `pan` is the sine of the source's bearing relative to `facing`: 0 dead ahead or dead
// behind, `ONE` a quarter turn past `facing` in the direction angles grow, `-ONE` a quarter
// turn before it. With y down, as on a screen, positive is the listener's right. The mixer
// has one gain per voice and no pan (D767), so `place` and `trigger` apply the gain and
// leave the pan to the caller, who reads it with `pan` and routes it however its output
// is laid out.
//
// `attenuate` is `ONE` at or inside `min_distance`, 0 at or beyond `max_distance` and
// linear between; a source whose range is inside out (`max <= min`) is either full or
// silent. A placed voice carries `s.gain` scaled by that attenuation.
//
// A `Cue` is one sound event: `variants` is a table of clips shared by every cue, and
// `first_variant`/`variant_count` is this cue's window into it; `trigger` draws one
// uniformly from the caller's PCG64 and plays it at `c.gain` over the placed source gain.
// `cooldown` is how many `step_cues` ticks the cue refuses to fire again after it fires,
// `remaining` is the count still to serve, 0 meaning ready; a cooldown of 0 fires every
// tick. A refused trigger takes nothing from the generator, so a replay that skips the
// same triggers draws the same variants. `id` is the caller's tag and is never read.
//
// `Unknown` is the one answer for a cue or voice that cannot be played as asked: a
// window that is empty or runs past the table, a cue still cooling, or a voice that is
// not playing.

use e.audio
use e.algo.rand
use e.audio.mixer
use e.math.fixed
use e.mem

type Listener = struct { x: fixed.Fx, y: fixed.Fx, facing: fixed.Fx }
type Source = struct { x: fixed.Fx, y: fixed.Fx, gain: i32, min_distance: fixed.Fx, max_distance: fixed.Fx }
type Cue = struct { id: u16, first_variant: u16, variant_count: u16, gain: i32, cooldown: u16, remaining: u16 }
error Unknown

fn pan(l: Listener, s: Source) -> i32 {
    let bearing = fixed.atan2(s.y - l.y, s.x - l.x)
    ret fixed.sin(bearing - l.facing)
}

fn attenuate(l: Listener, s: Source) -> i32 {
    let distance = fixed.length(s.x - l.x, s.y - l.y)
    if distance <= s.min_distance { ret fixed.ONE }
    if distance >= s.max_distance { ret 0i32 }
    // Strictly inside (min, max) here, so the range is positive and the division holds.
    let (t, t_error) = fixed.div(distance - s.min_distance, s.max_distance - s.min_distance)
    if t_error != ok { ret 0i32 }
    ret fixed.ONE - t
}

fn place(m: *mixer.Mixer, voice: usize, l: Listener, s: Source) -> err {
    if mixer.set_gain(m, voice, fixed.mul(s.gain, attenuate(l, s))) != ok { ret Unknown }
    ret ok
}

fn trigger(m: *mixer.Mixer, c: *Cue, variants: []const audio.Frames, state: *rand.Pcg64, l: Listener, s: Source) -> (usize, err) {
    if c.remaining != 0u16 { ret (0usize, Unknown) }
    let first = usize(c.first_variant)
    let count = usize(c.variant_count)
    if count == 0usize || first + count > variants.len { ret (0usize, Unknown) }
    let pick = first + usize(rand.pcg64_bounded(state, u64(count)))
    let gain = fixed.mul(c.gain, fixed.mul(s.gain, attenuate(l, s)))
    let (slot, play_error) = mixer.play(m, variants[pick], gain, false)
    if play_error != ok { ret (0usize, play_error) }
    c.remaining = c.cooldown
    ret (slot, ok)
}

fn step_cues(cues: []Cue) -> err {
    var at = 0usize
    while at < cues.len {
        if cues[at].remaining != 0u16 { cues[at].remaining -= 1u16 }
        at += 1usize
    }
    ret ok
}
