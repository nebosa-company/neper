// Positioned voices: pan at the four bearings, linear attenuation over a source's range,
// placement on a live mixer voice, and cues that draw a variant and respect a cooldown.

use e.algo.rand
use e.audio
use e.audio.mixer
use e.audio.spatial
use e.io
use e.math.fixed
use e.mem
use e.os

fn at(x: fixed.Fx, y: fixed.Fx, gain: i32, min: fixed.Fx, max: fixed.Fx) -> spatial.Source {
    ret spatial.Source { x: x, y: y, gain: gain, min_distance: min, max_distance: max }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let unused = a
    let one = fixed.ONE
    let origin = spatial.Listener { x: 0i32, y: 0i32, facing: 0i32 }

    // pan: ahead and behind are centred, a quarter turn either way is fully panned, and
    // facing turns the frame with the listener.
    if spatial.pan(origin, at(one, 0i32, one, one, one)) != 0i32 { os.exit(1i32) }
    if spatial.pan(origin, at(0i32, one, one, one, one)) != one { os.exit(2i32) }
    if spatial.pan(origin, at(-one, 0i32, one, one, one)) != 0i32 { os.exit(3i32) }
    if spatial.pan(origin, at(0i32, -one, one, one, one)) != -one { os.exit(4i32) }
    let turned = spatial.Listener { x: 0i32, y: 0i32, facing: fixed.QUARTER }
    if spatial.pan(turned, at(0i32, one, one, one, one)) != 0i32 { os.exit(5i32) }
    if spatial.pan(turned, at(-one, 0i32, one, one, one)) != one { os.exit(6i32) }

    // attenuate: unity inside min, silent beyond max, half way at the midpoint.
    if spatial.attenuate(origin, at(one / 2i32, 0i32, one, one, 3i32 * one)) != one { os.exit(7i32) }
    if spatial.attenuate(origin, at(one, 0i32, one, one, 3i32 * one)) != one { os.exit(8i32) }
    if spatial.attenuate(origin, at(0i32, 2i32 * one, one, one, 3i32 * one)) != fixed.HALF { os.exit(9i32) }
    if spatial.attenuate(origin, at(3i32 * one, 0i32, one, one, 3i32 * one)) != 0i32 { os.exit(10i32) }
    if spatial.attenuate(origin, at(0i32, 4i32 * one, one, one, 3i32 * one)) != 0i32 { os.exit(11i32) }
    if spatial.attenuate(origin, at(2i32 * one, 0i32, one, one, one)) != 0i32 { os.exit(12i32) }

    // place: the voice carries the source gain scaled by attenuation; a slot that is not
    // playing, or does not exist, is Unknown.
    let format = audio.Format { rate: 48000u32, channels: 1u8, sample: .I16 }
    var short_bytes: [2]u8 = [2]u8{ 1, 0 }
    var mid_bytes: [4]u8 = [4]u8{ 1, 0, 2, 0 }
    var long_bytes: [6]u8 = [6]u8{ 1, 0, 2, 0, 3, 0 }
    let (short, short_error) = audio.view(short_bytes[0..], format)
    let (mid, mid_error) = audio.view(mid_bytes[0..], format)
    let (long, long_error) = audio.view(long_bytes[0..], format)
    if short_error != ok || mid_error != ok || long_error != ok { os.exit(13i32) }
    var slots: [3]mixer.Voice = zero
    var mixed: mixer.Mixer = zero
    if mixer.init(&mixed, format, slots[0..]) != ok { os.exit(14i32) }
    let (voice, play_error) = mixer.play(&mixed, short, one, false)
    if play_error != ok { os.exit(15i32) }
    let half_way = at(0i32, 2i32 * one, fixed.HALF, one, 3i32 * one)
    if spatial.place(&mixed, voice, origin, half_way) != ok || mixed.voices[voice].gain != 16384i32 { os.exit(16i32) }
    if spatial.place(&mixed, 1usize, origin, half_way) != spatial.Unknown { os.exit(17i32) }
    if spatial.place(&mixed, 5usize, origin, half_way) != spatial.Unknown { os.exit(18i32) }

    // trigger: a cue draws from its window of the table, plays at the cue gain over the
    // placed gain, and then refuses until `cooldown` steps have passed; a refused trigger
    // leaves the generator alone, so two generators seeded alike pick alike.
    var variants: [3]audio.Frames = [3]audio.Frames{ short, mid, long }
    var gen = rand.pcg64(42u64, 7u64)
    var twin = rand.pcg64(42u64, 7u64)
    var cue = spatial.Cue { id: 1u16, first_variant: 1u16, variant_count: 2u16, gain: fixed.HALF, cooldown: 2u16, remaining: 0u16 }
    let (first, first_error) = spatial.trigger(&mixed, &cue, variants[0..], &gen, origin, half_way)
    if first_error != ok || first != 1usize || cue.remaining != 2u16 || mixer.active(mixed) != 2usize { os.exit(19i32) }
    let picked = mixed.voices[first].source.count
    if picked != 2usize && picked != 3usize { os.exit(20i32) }
    if mixed.voices[first].gain != 8192i32 { os.exit(21i32) }
    let before = gen.state
    let (_, cooling_error) = spatial.trigger(&mixed, &cue, variants[0..], &gen, origin, half_way)
    if cooling_error != spatial.Unknown || cue.remaining != 2u16 || gen.state != before || mixer.active(mixed) != 2usize { os.exit(22i32) }
    var twin_slots: [1]mixer.Voice = zero
    var twin_mixer: mixer.Mixer = zero
    if mixer.init(&twin_mixer, format, twin_slots[0..]) != ok { os.exit(23i32) }
    var twin_cue = cue
    twin_cue.remaining = 0u16
    let (twin_voice, twin_error) = spatial.trigger(&twin_mixer, &twin_cue, variants[0..], &twin, origin, half_way)
    if twin_error != ok || twin_voice != 0usize || twin_mixer.voices[0].source.count != picked { os.exit(24i32) }

    // step_cues counts every cooling cue down by one and leaves a ready one ready.
    var idle = spatial.Cue { id: 2u16, first_variant: 0u16, variant_count: 1u16, gain: one, cooldown: 0u16, remaining: 0u16 }
    var cues: [2]spatial.Cue = [2]spatial.Cue{ cue, idle }
    if spatial.step_cues(cues[0..]) != ok || cues[0].remaining != 1u16 || cues[1].remaining != 0u16 { os.exit(25i32) }
    let (_, still_error) = spatial.trigger(&mixed, &cues[0], variants[0..], &gen, origin, half_way)
    if still_error != spatial.Unknown { os.exit(26i32) }
    if spatial.step_cues(cues[0..]) != ok || cues[0].remaining != 0u16 { os.exit(27i32) }
    let (again, again_error) = spatial.trigger(&mixed, &cues[0], variants[0..], &gen, origin, half_way)
    if again_error != ok || again != 2usize || cues[0].remaining != 2u16 || mixer.active(mixed) != 3usize { os.exit(28i32) }

    // A cooldown of 0 fires every tick; a full mixer answers the mixer's own error.
    let (_, full_error) = spatial.trigger(&mixed, &cues[1], variants[0..], &gen, origin, half_way)
    if full_error != mixer.Full || cues[1].remaining != 0u16 { os.exit(29i32) }
    if mixer.stop(&mixed, again) != ok { os.exit(30i32) }
    let (idle_one, idle_one_error) = spatial.trigger(&mixed, &cues[1], variants[0..], &gen, origin, half_way)
    if idle_one_error != ok || idle_one != again || mixed.voices[again].source.count != 1usize { os.exit(31i32) }
    if mixer.stop(&mixed, again) != ok { os.exit(32i32) }
    let (_, idle_two_error) = spatial.trigger(&mixed, &cues[1], variants[0..], &gen, origin, half_way)
    if idle_two_error != ok { os.exit(33i32) }

    // A window that is empty or runs past the table is Unknown before anything plays.
    var empty = spatial.Cue { id: 3u16, first_variant: 0u16, variant_count: 0u16, gain: one, cooldown: 0u16, remaining: 0u16 }
    var past = spatial.Cue { id: 4u16, first_variant: 2u16, variant_count: 2u16, gain: one, cooldown: 0u16, remaining: 0u16 }
    let quiet = gen.state
    let (_, empty_error) = spatial.trigger(&twin_mixer, &empty, variants[0..], &gen, origin, half_way)
    let (_, past_error) = spatial.trigger(&twin_mixer, &past, variants[0..], &gen, origin, half_way)
    if empty_error != spatial.Unknown || past_error != spatial.Unknown || gen.state != quiet { os.exit(34i32) }

    try io.print("audio spatial ok\n")
    ret ok
}
