// Minimal PCM RIFF/WAVE decode, conversion, streaming and seek.

use e.audio
use e.fmt.wav
use e.mem
use e.os

fn main(a: *mem.Arena) -> err {
    var file: [48]u8 = [48]u8{
        82, 73, 70, 70, 40, 0, 0, 0, 87, 65, 86, 69,
        102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
        2, 0, 0, 0, 4, 0, 0, 0, 2, 0, 16, 0,
        100, 97, 116, 97, 4, 0, 0, 0, 232, 3, 24, 252,
    }
    let (opened, open_error) = wav.open(a, file[0..])
    if open_error != ok || wav.frame_count(opened) != 2usize || wav.format(opened).rate != 2u32 || wav.format(opened).channels != 1u8 || wav.format(opened).sample != audio.SampleFormat.I16 { os.exit(1i32) }
    var decoder = opened
    let target_format = audio.Format { rate: 2u32, channels: 1u8, sample: .I32 }
    var first_bytes: [4]u8 = zero
    let (first_view, first_view_error) = audio.view(first_bytes[0..], target_format)
    var first = first_view
    let (first_count, first_error) = wav.decode_into(&decoder, &first)
    let (first_sample, first_sample_error) = audio.sample_i32(first, 0usize, 0u8)
    if first_view_error != ok || first_error != ok || first_count != 1usize || first_sample_error != ok || first_sample != 65536000i32 { os.exit(2i32) }
    var second_bytes: [8]u8 = zero
    let (second_view, second_view_error) = audio.view(second_bytes[0..], target_format)
    var second = second_view
    let (second_count, second_error) = wav.decode_into(&decoder, &second)
    let (second_sample, second_sample_error) = audio.sample_i32(second, 0usize, 0u8)
    if second_view_error != ok || second_error != ok || second_count != 1usize || second_sample_error != ok || second_sample != -65536000i32 { os.exit(3i32) }
    let (eof_count, eof_error) = wav.decode_into(&decoder, &second)
    if eof_error != ok || eof_count != 0usize { os.exit(4i32) }
    if wav.seek(&decoder, 0usize) != ok || wav.seek(&decoder, 3usize) != wav.Invalid { os.exit(5i32) }
    let (again_count, again_error) = wav.decode_into(&decoder, &second)
    let (again_second, again_second_error) = audio.sample_i32(second, 1usize, 0u8)
    if again_error != ok || again_count != 2usize || again_second_error != ok || again_second != -65536000i32 { os.exit(6i32) }
    file[0] = 0u8
    let (_, invalid_error) = wav.open(a, file[0..])
    if invalid_error != wav.Invalid { os.exit(7i32) }
    ret ok
}
