// `e.io`'s streams. A `Reader` and a `Writer` are a context and a callback, so every
// adapter here is a value the caller owns, and the callbacks the constructors install
// are ordinary declarations (D94).

use e.mem
use e.os
use e.io
use e.str

error Failed

fn main(a: *mem.Arena) -> err {
    var source = "hello world"
    var reader_state = io.SliceReader { data: source, off: 0usize }
    var r = io.slice_reader(&reader_state)

    // A short read takes what is there and says how much.
    var window: [5]u8 = zero
    let (first, first_error) = io.read(&r, window[..])
    if first_error != ok { ret first_error }
    if first != 5usize { ret Failed }
    if !str.eq(window[0usize..5usize], "hello") { ret Failed }

    // `read_exact` loops until the request is filled.
    var rest: [6]u8 = zero
    let exact_error = io.read_exact(&r, rest[..])
    if exact_error != ok { ret exact_error }
    if !str.eq(rest[0usize..6usize], " world") { ret Failed }

    // Past the end is `End`, not a zero-length success -- a callback that made no
    // progress and did not say why would spin a caller forever.
    var spare: [1]u8 = zero
    let (after, after_error) = io.read(&r, spare[..])
    if after_error != io.End { ret Failed }

    // A file says the same thing. The host reports its end as a read that took nothing
    // rather than as a failure, so without `file_read` turning that into `End` a loop
    // written against this contract ended in `NoProgress` on a file and in `End` on a
    // slice -- the same `Reader`, two answers to the same question.
    let removed_before = os.remove_file(a, "np-io-eof.txt")
    var make: os.OpenFlags = zero
    make.write = true
    make.create = true
    make.truncate = true
    let (made, made_error) = os.open(a, "np-io-eof.txt", make)
    if made_error != ok { ret made_error }
    let (put, put_error) = os.write(made, "abc")
    let made_close = os.close(made)
    if put_error != ok { ret put_error }
    if put != 3usize { ret Failed }
    if made_close != ok { ret Failed }
    var take: os.OpenFlags = zero
    take.read = true
    let (opened, opened_error) = os.open(a, "np-io-eof.txt", take)
    if opened_error != ok { ret opened_error }
    var opened_file = opened
    defer let _ = os.close(opened_file)
    var from_file = io.file_reader(&opened_file)
    var file_window: [8]u8 = zero
    let (from_file_count, from_file_error) = io.read(&from_file, file_window[..])
    if from_file_error != ok { ret from_file_error }
    if from_file_count != 3usize { ret Failed }
    let (past, past_error) = io.read(&from_file, file_window[..])
    if past_error != io.End { ret Failed }
    if past != 0usize { ret Failed }
    if os.remove_file(a, "np-io-eof.txt") != ok { ret Failed }

    // Writing into a fixed slice, and the sink reporting what it could take.
    var buffer: [4]u8 = zero
    var writer_state = io.SliceWriter { data: buffer[..], off: 0usize }
    var w = io.slice_writer(&writer_state)
    let (wrote, write_error) = io.write(&w, "abcdefgh")
    if write_error != ok { ret write_error }
    if wrote != 4usize { ret Failed }
    if !str.eq(buffer[0usize..4usize], "abcd") { ret Failed }
    // Full: the next write has nowhere to go.
    let (again, again_error) = io.write(&w, "z")
    if again_error != io.TooSmall { ret Failed }

    // `limited_reader` stops at its limit even though the source has more.
    var limited_source = io.SliceReader { data: "abcdefgh", off: 0usize }
    var inner = io.slice_reader(&limited_source)
    var limit_state: io.LimitedReader = zero
    var limited = io.limited_reader(&limit_state, inner, 3u64)
    var three: [8]u8 = zero
    let (taken, taken_error) = io.read(&limited, three[..])
    if taken_error != ok { ret taken_error }
    if taken != 3usize { ret Failed }
    if !str.eq(three[0usize..3usize], "abc") { ret Failed }
    let (over, over_error) = io.read(&limited, three[..])
    if over_error != io.End { ret Failed }

    // `counting_writer` passes bytes through and counts them.
    var sink_buffer: [16]u8 = zero
    var sink_state = io.SliceWriter { data: sink_buffer[..], off: 0usize }
    var sink = io.slice_writer(&sink_state)
    var counter_state: io.CountingWriter = zero
    var counted = io.counting_writer(&counter_state, sink)
    let counted_error = io.write_all(&counted, "four")
    if counted_error != ok { ret counted_error }
    if counter_state.count != 4u64 { ret Failed }
    if !str.eq(sink_buffer[0usize..4usize], "four") { ret Failed }

    // `tee_writer` writes each input to the left sink before the right one.
    var left_buffer: [8]u8 = zero
    var right_buffer: [8]u8 = zero
    var left_state = io.SliceWriter { data: left_buffer[..], off: 0usize }
    var right_state = io.SliceWriter { data: right_buffer[..], off: 0usize }
    var tee_state: io.TeeWriter = zero
    var both = io.tee_writer(&tee_state, io.slice_writer(&left_state), io.slice_writer(&right_state))
    let tee_error = io.write_all(&both, "twice")
    if tee_error != ok { ret tee_error }
    if !str.eq(left_buffer[0usize..5usize], "twice") { ret Failed }
    if !str.eq(right_buffer[0usize..5usize], "twice") { ret Failed }

    // `copy` moves a whole stream through a scratch buffer smaller than it.
    var copy_source = io.SliceReader { data: "0123456789", off: 0usize }
    var copy_from = io.slice_reader(&copy_source)
    var copy_buffer: [16]u8 = zero
    var copy_state = io.SliceWriter { data: copy_buffer[..], off: 0usize }
    var copy_to = io.slice_writer(&copy_state)
    var scratch: [3]u8 = zero
    let (moved, copy_error) = io.copy(&copy_to, &copy_from, scratch[..])
    if copy_error != ok { ret copy_error }
    if moved != 10u64 { ret Failed }
    if !str.eq(copy_buffer[0usize..10usize], "0123456789") { ret Failed }

    // `read_all` grows its own claim; `limit` is a hard maximum and keeps no partial
    // result when it is crossed.
    var all_source = io.SliceReader { data: "the whole thing", off: 0usize }
    var all_from = io.slice_reader(&all_source)
    let (everything, all_error) = io.read_all(a, &all_from, 1024usize)
    if all_error != ok { ret all_error }
    if !str.eq(everything, "the whole thing") { ret Failed }
    var small_source = io.SliceReader { data: "too long for this", off: 0usize }
    var small_from = io.slice_reader(&small_source)
    let (nothing, small_error) = io.read_all(a, &small_from, 4usize)
    if small_error != io.TooSmall { ret Failed }

    // `read_until` stops after the delimiter and keeps it.
    var line_source = io.SliceReader { data: "first\nsecond\n", off: 0usize }
    var lines = io.slice_reader(&line_source)
    let (line, line_error) = io.read_until(a, &lines, 10u8, 64usize)
    if line_error != ok { ret line_error }
    if !str.eq(line, "first\n") { ret Failed }

    // A buffered source reads through a buffer of its own and hands back the same
    // bytes the unbuffered one would.
    var buffered_source_state = io.SliceReader { data: "buffered bytes", off: 0usize }
    var under = io.slice_reader(&buffered_source_state)
    var (handle, handle_error) = io.buffered_reader(a, under, 4usize)
    if handle_error != ok { ret handle_error }
    var buffered = io.buffered_source(&handle)
    let (drained, drained_error) = io.read_all(a, &buffered, 1024usize)
    if drained_error != ok { ret drained_error }
    if !str.eq(drained, "buffered bytes") { ret Failed }

    // A buffered sink holds bytes back until it is flushed.
    var flushed_buffer: [32]u8 = zero
    var flushed_state = io.SliceWriter { data: flushed_buffer[..], off: 0usize }
    var (sink_handle, sink_handle_error) = io.buffered_writer(a, io.slice_writer(&flushed_state), 16usize)
    if sink_handle_error != ok { ret sink_handle_error }
    var buffered_sink = io.buffered_sink(&sink_handle)
    let buffered_write_error = io.write_all(&buffered_sink, "held")
    if buffered_write_error != ok { ret buffered_write_error }
    if flushed_state.off != 0usize { ret Failed }
    let flush_error = io.flush(&buffered_sink)
    if flush_error != ok { ret flush_error }
    if flushed_state.off != 4usize { ret Failed }
    if !str.eq(flushed_buffer[0usize..4usize], "held") { ret Failed }
    ret ok
}
