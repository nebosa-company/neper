// Interleaved little-endian PCM views convert through signed i32 full scale.

use e.audio
use e.mem
use e.os

fn main(a: *mem.Arena) -> err {
    let format = audio.Format { rate: 48000u32, channels: 2u8, sample: .I16 }
    var bytes: [8]u8 = [8]u8{ 0, 128, 255, 127, 0, 0, 0, 64 }
    let (created, view_error) = audio.view(bytes[0..], format)
    if view_error != ok || created.count != 2usize || audio.frame_bytes(format) != 4usize || audio.frames_in(format, 9usize) != 2usize { os.exit(1i32) }
    var frames = created
    let (minimum, minimum_error) = audio.sample_i32(frames, 0usize, 0u8)
    let (maximum, maximum_error) = audio.sample_i32(frames, 0usize, 1u8)
    if minimum_error != ok || maximum_error != ok || minimum != (-2147483647i32 - 1i32) || maximum != 2147418112i32 { os.exit(2i32) }
    let (floats, float_error) = audio.convert(a, frames, .F32)
    let (float_minimum, float_minimum_error) = audio.sample_i32(floats, 0usize, 0u8)
    let (float_maximum, float_maximum_error) = audio.sample_i32(floats, 0usize, 1u8)
    if float_error != ok || float_minimum_error != ok || float_maximum_error != ok || float_minimum != (-2147483647i32 - 1i32) || float_maximum < 2147417984i32 { os.exit(3i32) }
    if audio.set_sample_i32(&frames, 1usize, 0u8, 1073741824i32) != ok { os.exit(4i32) }
    let (changed, changed_error) = audio.sample_i32(frames, 1usize, 0u8)
    if changed_error != ok || changed != 1073741824i32 { os.exit(5i32) }
    if audio.set_sample_i32(&frames, 2usize, 0u8, 0i32) != audio.Truncated { os.exit(6i32) }
    // A public Frames value can claim more frames than its backing storage has.
    // Its frame offset must be checked before it overflows integer arithmetic.
    let forged_format = audio.Format { rate: 48000u32, channels: 1u8, sample: .I32 }
    var forged_bytes: [4]u8 = [4]u8{ 1u8, 2u8, 3u8, 4u8 }
    var forged = audio.Frames { bytes: forged_bytes[..], format: forged_format, count: 0usize -% 1usize }
    let overflow_frame = (0usize -% 1usize) / 4usize + 1usize
    let (_, overflow_read_error) = audio.sample_i32(forged, overflow_frame, 0u8)
    if overflow_read_error != audio.Truncated { os.exit(6i32) }
    if audio.set_sample_i32(&forged, overflow_frame, 0u8, 0i32) != audio.Truncated { os.exit(6i32) }
    if forged_bytes[0usize] != 1u8 || forged_bytes[1usize] != 2u8 || forged_bytes[2usize] != 3u8 || forged_bytes[3usize] != 4u8 { os.exit(6i32) }
    var short: [7]u8 = zero
    let (_, short_error) = audio.view(short[0..], format)
    if short_error != audio.Truncated { os.exit(7i32) }
    let nan_format = audio.Format { rate: 48000u32, channels: 1u8, sample: .F32 }
    var nan_bytes: [4]u8 = [4]u8{ 0u8, 0u8, 192u8, 127u8 }
    let (nan_frames, nan_view_error) = audio.view(nan_bytes[..], nan_format)
    if nan_view_error != ok { os.exit(8i32) }
    let before_convert = mem.mark(a)
    let (_, nan_convert_error) = audio.convert(a, nan_frames, .I16)
    if nan_convert_error != audio.Unsupported || mem.mark(a) != before_convert { os.exit(8i32) }
    if audio.silence(&frames) != ok { os.exit(8i32) }
    var at = 0usize
    while at < bytes.len {
        if bytes[at] != 0u8 { os.exit(9i32) }
        at += 1usize
    }

    // Every i16 code survives the exact power-of-two F32 representation.
    let mono_format = audio.Format { rate: 48000u32, channels: 1u8, sample: .I16 }
    var roundtrip_bytes: [2]u8 = zero
    let (roundtrip_view, roundtrip_view_error) = audio.view(roundtrip_bytes[..], mono_format)
    if roundtrip_view_error != ok { os.exit(10i32) }
    var roundtrip = roundtrip_view
    var input = -32768i32
    while input <= 32767i32 {
        if audio.set_sample_i32(&roundtrip, 0usize, 0u8, input * 65536i32) != ok { os.exit(10i32) }
        let roundtrip_mark = mem.mark(a)
        let (as_float, as_float_error) = audio.convert(a, roundtrip, .F32)
        if as_float_error != ok {
            mem.reset(a, roundtrip_mark)
            os.exit(10i32)
        }
        let (as_i16, as_i16_error) = audio.convert(a, as_float, .I16)
        let (roundtrip_value, roundtrip_value_error) = audio.sample_i32(as_i16, 0usize, 0u8)
        mem.reset(a, roundtrip_mark)
        if as_i16_error != ok || roundtrip_value_error != ok || roundtrip_value != input * 65536i32 { os.exit(10i32) }
        input += 1i32
    }
    if audio.set_sample_i32(&roundtrip, 0usize, 0u8, 32768i32) != ok { os.exit(10i32) }
    let (positive_half, positive_half_error) = audio.sample_i32(roundtrip, 0usize, 0u8)
    if audio.set_sample_i32(&roundtrip, 0usize, 0u8, -32768i32) != ok { os.exit(10i32) }
    let (negative_half, negative_half_error) = audio.sample_i32(roundtrip, 0usize, 0u8)
    if positive_half_error != ok || negative_half_error != ok || positive_half != 65536i32 || negative_half != -65536i32 { os.exit(10i32) }
    ret ok
}
