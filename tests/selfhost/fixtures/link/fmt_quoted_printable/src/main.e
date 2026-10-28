// `e.fmt.quoted_printable`: encoding with escapes, soft breaks at the line limit and a
// trailing space escaped before a break and at the end; strict decoding back, including
// one-byte reads across an escape and the three rejections. Every check has its own exit
// code.
use e.os
use e.mem
use e.io
use e.fmt.quoted_printable as qp

fn bytes_equal(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Encode: "héllo = wörld \r\nline two   " with a 20-byte line limit.
    let text: [26]u8 = [26]u8{ 104, 195, 169, 108, 108, 111, 32, 61, 32, 119, 195, 182, 114, 108, 100, 32, 13, 10, 108, 105, 110, 101, 32, 116, 119, 111 }
    var out_storage: [256]u8 = zero
    var sink_state: io.SliceWriter = zero
    sink_state.data = out_storage[0..]
    let sink = io.slice_writer(&sink_state)
    var writer_storage: [256]u8 = zero
    let (w0, writer_error) = qp.writer(writer_storage[0..], sink, 20u8)
    if writer_error != ok { os.exit(1) }
    var w = w0
    let (consumed, write_error) = qp.write(&w, text[0..])
    if write_error != ok || consumed != text.len { os.exit(2) }
    let (consumed2, write_error2) = qp.write(&w, "  ")
    if write_error2 != ok || consumed2 != 2usize { os.exit(3) }
    if qp.finish(&w) != ok { os.exit(4) }
    let encoded = out_storage[..sink_state.off]
    // Expected: h=C3=A9llo =3D w=C3=\r\nB6rld=20\r\nline two =20
    let want: [45]u8 = [45]u8{ 104, 61, 67, 51, 61, 65, 57, 108, 108, 111, 32, 61, 51, 68, 32, 119, 61, 67, 51, 61, 13, 10, 61, 66, 54, 114, 108, 100, 61, 50, 48, 13, 10, 108, 105, 110, 101, 32, 116, 119, 111, 32, 61, 50, 48 }
    if !bytes_equal(encoded, want[0..]) { os.exit(5) }
    // A hard CRLF is one stream token, even when it crosses two writes. A final
    // unmatched CR is ordinary data and is escaped at finish.
    let hard: [4]u8 = [4]u8{ 65u8, 13u8, 10u8, 66u8 }
    var whole_out: [32]u8 = zero
    var whole_sink_state: io.SliceWriter = zero
    whole_sink_state.data = whole_out[..]
    var whole_storage: [128]u8 = zero
    let (whole_writer_value, whole_writer_error) = qp.writer(whole_storage[..], io.slice_writer(&whole_sink_state), 20u8)
    if whole_writer_error != ok { os.exit(13) }
    var whole_writer = whole_writer_value
    let (whole_count, whole_write_error) = qp.write(&whole_writer, hard[..])
    if whole_write_error != ok || whole_count != hard.len || qp.finish(&whole_writer) != ok { os.exit(14) }

    var split_out: [32]u8 = zero
    var split_sink_state: io.SliceWriter = zero
    split_sink_state.data = split_out[..]
    var split_storage: [128]u8 = zero
    let (split_writer_value, split_writer_error) = qp.writer(split_storage[..], io.slice_writer(&split_sink_state), 20u8)
    if split_writer_error != ok { os.exit(15) }
    var split_writer = split_writer_value
    let (first_count, first_write_error) = qp.write(&split_writer, hard[0usize..2usize])
    let (second_count, second_write_error) = qp.write(&split_writer, hard[2usize..])
    if first_write_error != ok || first_count != 2usize || second_write_error != ok || second_count != 2usize || qp.finish(&split_writer) != ok { os.exit(16) }
    if !bytes_equal(whole_out[..whole_sink_state.off], hard[..]) || !bytes_equal(split_out[..split_sink_state.off], whole_out[..whole_sink_state.off]) { os.exit(17) }

    var literal_out: [16]u8 = zero
    var literal_sink_state: io.SliceWriter = zero
    literal_sink_state.data = literal_out[..]
    var literal_storage: [128]u8 = zero
    let (literal_writer_value, literal_writer_error) = qp.writer(literal_storage[..], io.slice_writer(&literal_sink_state), 20u8)
    if literal_writer_error != ok { os.exit(18) }
    var literal_writer = literal_writer_value
    let (literal_first_count, literal_first_error) = qp.write(&literal_writer, "M\r")
    let (literal_second_count, literal_second_error) = qp.write(&literal_writer, "N")
    let literal_want: [5]u8 = [5]u8{ 77u8, 61u8, 48u8, 68u8, 78u8 }
    if literal_first_error != ok || literal_first_count != 2usize || literal_second_error != ok || literal_second_count != 1usize || qp.finish(&literal_writer) != ok || !bytes_equal(literal_out[..literal_sink_state.off], literal_want[..]) { os.exit(19) }

    var trailing_out: [16]u8 = zero
    var trailing_sink_state: io.SliceWriter = zero
    trailing_sink_state.data = trailing_out[..]
    var trailing_storage: [128]u8 = zero
    let (trailing_writer_value, trailing_writer_error) = qp.writer(trailing_storage[..], io.slice_writer(&trailing_sink_state), 20u8)
    if trailing_writer_error != ok { os.exit(20) }
    var trailing_writer = trailing_writer_value
    let (trailing_count, trailing_write_error) = qp.write(&trailing_writer, "Z\r")
    let trailing_want: [4]u8 = [4]u8{ 90u8, 61u8, 48u8, 68u8 }
    if trailing_write_error != ok || trailing_count != 2usize || qp.finish(&trailing_writer) != ok || !bytes_equal(trailing_out[..trailing_sink_state.off], trailing_want[..]) { os.exit(21) }
    // Decode it back.
    var source_state: io.SliceReader = zero
    source_state.data = encoded
    let source = io.slice_reader(&source_state)
    var reader_storage: [64]u8 = zero
    var r = qp.reader(reader_storage[0..], source)
    var decoded: [64]u8 = zero
    var total = 0usize
    while true {
        let (count, read_error) = qp.read(&r, decoded[total..])
        if read_error == io.End { break }
        if read_error != ok { os.exit(6) }
        total += count
    }
    if !bytes_equal(decoded[..total], "h\xc3\xa9llo = w\xc3\xb6rld \r\nline two  ") { os.exit(7) }
    // Strict decoding: lower-case hex, a bare CR and a byte above 126 are invalid.
    var bad_state: io.SliceReader = zero
    bad_state.data = "a=c3b"
    var bad_storage: [64]u8 = zero
    var bad = qp.reader(bad_storage[0..], io.slice_reader(&bad_state))
    var sink2: [8]u8 = zero
    let (_, bad_error) = qp.read(&bad, sink2[0..])
    if bad_error != qp.Invalid { os.exit(8) }
    var bare_state: io.SliceReader = zero
    bare_state.data = "a\rb"
    var bare = qp.reader(bad_storage[0..], io.slice_reader(&bare_state))
    let (_, bare_error) = qp.read(&bare, sink2[0..])
    if bare_error != qp.Invalid { os.exit(9) }
    // Small reads across an escape: one output byte at a time.
    var small_state: io.SliceReader = zero
    small_state.data = "x=41=\r\ny"
    var small = qp.reader(bad_storage[0..], io.slice_reader(&small_state))
    var one: [1]u8 = zero
    var got: [8]u8 = zero
    var n = 0usize
    while true {
        let (count, read_error) = qp.read(&small, one[0..])
        if read_error == io.End { break }
        if read_error != ok { os.exit(10) }
        got[n] = one[0]
        n += count
    }
    if n != 3usize || got[0] != 120u8 || got[1] != 65u8 || got[2] != 121u8 { os.exit(11) }
    let (_, limit_error) = qp.writer(writer_storage[0..], sink, 77u8)
    if limit_error != qp.Invalid { os.exit(12) }
    os.exit(0)
    ret ok
}
