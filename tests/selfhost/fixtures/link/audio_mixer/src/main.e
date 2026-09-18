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
    ret ok
}
