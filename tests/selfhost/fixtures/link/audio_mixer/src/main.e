// Caller-owned mixer voice lifecycle.

use e.audio
use e.audio.mixer
use e.mem
use e.os

fn main(a: *mem.Arena) -> err {
    let unused = a
    let format = audio.Format { rate: 48000u32, channels: 1u8, sample: .I16 }
    var samples: [4]u8 = [4]u8{ 1, 0, 2, 0 }
    let (source, source_error) = audio.view(samples[0..], format)
    if source_error != ok { os.exit(1i32) }
    var slots: [2]mixer.Voice = zero
    var mixed: mixer.Mixer = zero
    if mixer.init(&mixed, format, slots[0..]) != ok || mixed.master != 65536i32 || mixer.active(mixed) != 0usize { os.exit(2i32) }
    let (first, first_error) = mixer.play(&mixed, source, 65536i32, false)
    let (second, second_error) = mixer.play(&mixed, source, 32768i32, true)
    if first_error != ok || second_error != ok || first != 0usize || second != 1usize || mixer.active(mixed) != 2usize { os.exit(3i32) }
    let (_, full_error) = mixer.play(&mixed, source, 1i32, false)
    if full_error != mixer.Full { os.exit(4i32) }
    if mixer.set_gain(&mixed, first, 1234i32) != ok || mixed.voices[first].gain != 1234i32 { os.exit(5i32) }
    if mixer.stop(&mixed, first) != ok || mixer.stop(&mixed, first) != ok || mixer.active(mixed) != 1usize { os.exit(6i32) }
    let (reused, reused_error) = mixer.play(&mixed, source, 9i32, false)
    if reused_error != ok || reused != first || mixer.active(mixed) != 2usize { os.exit(7i32) }
    let wrong = audio.Format { rate: 44100u32, channels: 1u8, sample: .I16 }
    var wrong_bytes: [2]u8 = zero
    let (wrong_source, wrong_error) = audio.view(wrong_bytes[0..], wrong)
    let (_, unsupported) = mixer.play(&mixed, wrong_source, 1i32, false)
    if wrong_error != ok || unsupported != mixer.Unsupported { os.exit(8i32) }

    var mix_slots: [2]mixer.Voice = zero
    var sum: mixer.Mixer = zero
    if mixer.init(&sum, format, mix_slots[0..]) != ok { os.exit(9i32) }
    var wave_bytes: [4]u8 = [4]u8{ 232, 3, 24, 252 }
    let (wave, wave_error) = audio.view(wave_bytes[0..], format)
    let (_, wave_one_error) = mixer.play(&sum, wave, 65536i32, false)
    let (_, wave_two_error) = mixer.play(&sum, wave, 32768i32, false)
    var out_bytes: [4]u8 = zero
    let (out_view, out_error) = audio.view(out_bytes[0..], format)
    var out = out_view
    let (written, mix_error) = mixer.mix_into(&sum, &out)
    let (positive, positive_error) = audio.sample_i32(out, 0usize, 0u8)
    let (negative, negative_error) = audio.sample_i32(out, 1usize, 0u8)
    if wave_error != ok || wave_one_error != ok || wave_two_error != ok || out_error != ok || mix_error != ok || written != 2usize || positive_error != ok || negative_error != ok || positive != 98304000i32 || negative != -98304000i32 || mixer.active(sum) != 0usize { os.exit(10i32) }

    var loop_slots: [1]mixer.Voice = zero
    var looping: mixer.Mixer = zero
    if mixer.init(&looping, format, loop_slots[0..]) != ok { os.exit(11i32) }
    let (_, loop_error) = mixer.play(&looping, wave, 65536i32, true)
    var loop_bytes: [6]u8 = zero
    let (loop_view, loop_view_error) = audio.view(loop_bytes[0..], format)
    var loop_out = loop_view
    let (loop_written, loop_mix_error) = mixer.mix_into(&looping, &loop_out)
    let (looped, looped_error) = audio.sample_i32(loop_out, 2usize, 0u8)
    if loop_error != ok || loop_view_error != ok || loop_mix_error != ok || loop_written != 3usize || looped_error != ok || looped != 65536000i32 || mixer.active(looping) != 1usize || looping.voices[0].position != 1usize { os.exit(12i32) }

    var loud_slots: [2]mixer.Voice = zero
    var loud: mixer.Mixer = zero
    if mixer.init(&loud, format, loud_slots[0..]) != ok { os.exit(13i32) }
    var loud_bytes: [2]u8 = [2]u8{ 255, 127 }
    let (loud_source, loud_source_error) = audio.view(loud_bytes[0..], format)
    let (_, loud_one_error) = mixer.play(&loud, loud_source, 65536i32, false)
    let (_, loud_two_error) = mixer.play(&loud, loud_source, 65536i32, false)
    var clipped_bytes: [2]u8 = zero
    let (clipped_view, clipped_view_error) = audio.view(clipped_bytes[0..], format)
    var clipped = clipped_view
    let (_, clipped_mix_error) = mixer.mix_into(&loud, &clipped)
    let (clipped_sample, clipped_sample_error) = audio.sample_i32(clipped, 0usize, 0u8)
    if loud_source_error != ok || loud_one_error != ok || loud_two_error != ok || clipped_view_error != ok || clipped_mix_error != ok || clipped_sample_error != ok || clipped_sample != 2147418112i32 { os.exit(14i32) }
    ret ok
}
