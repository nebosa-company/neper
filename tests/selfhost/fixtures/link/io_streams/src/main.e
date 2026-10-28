// `e.io`'s streams. A `Reader` and a `Writer` are a context and a callback, so every
// adapter here is a value the caller owns, and the callbacks the constructors install
// are ordinary declarations (D94).

use e.mem
use e.os
use e.io
use e.str
use e.test.support

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

    // Flushing a tee flushes both wrapped sinks in the same left-before-right order.
    var tee_flush_left_bytes: [4]u8 = zero
    var tee_flush_right_bytes: [4]u8 = zero
    var tee_flush_left_state = io.SliceWriter { data: tee_flush_left_bytes[..], off: 0usize }
    var tee_flush_right_state = io.SliceWriter { data: tee_flush_right_bytes[..], off: 0usize }
    let (tee_flush_left_handle, tee_flush_left_error) = io.buffered_writer(a, io.slice_writer(&tee_flush_left_state), 4usize)
    if tee_flush_left_error != ok { ret tee_flush_left_error }
    let (tee_flush_right_handle, tee_flush_right_error) = io.buffered_writer(a, io.slice_writer(&tee_flush_right_state), 4usize)
    if tee_flush_right_error != ok { ret tee_flush_right_error }
    var tee_flush_left = tee_flush_left_handle
    var tee_flush_right = tee_flush_right_handle
    var tee_flush_state: io.TeeWriter = zero
    var tee_flush_writer = io.tee_writer(&tee_flush_state, io.buffered_sink(&tee_flush_left), io.buffered_sink(&tee_flush_right))
    if io.write_all(&tee_flush_writer, "x") != ok { ret Failed }
    if tee_flush_left_state.off != 0usize || tee_flush_right_state.off != 0usize { ret Failed }
    if io.flush(&tee_flush_writer) != ok { ret Failed }
    if tee_flush_left_state.off != 1usize || tee_flush_right_state.off != 1usize { ret Failed }
    if !str.eq(tee_flush_left_bytes[0usize..1usize], "x") || !str.eq(tee_flush_right_bytes[0usize..1usize], "x") { ret Failed }

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

    // A hard limit allows an input that ends exactly at it: the helper probes once
    // for EOF rather than rejecting the full buffer before asking the source.
    var exact_all_source = io.SliceReader { data: "four", off: 0usize }
    var exact_all = io.slice_reader(&exact_all_source)
    let (exact_all_bytes, exact_all_error) = io.read_all(a, &exact_all, 4usize)
    if exact_all_error != ok || !str.eq(exact_all_bytes, "four") { ret Failed }

    var empty_all_source = io.SliceReader { data: "", off: 0usize }
    var empty_all = io.slice_reader(&empty_all_source)
    let (empty_all_bytes, empty_all_error) = io.read_all(a, &empty_all, 0usize)
    if empty_all_error != ok || empty_all_bytes.len != 0usize { ret Failed }

    var exact_detail_source = io.SliceReader { data: "detail", off: 0usize }
    var exact_detail = io.slice_detail_reader(&exact_detail_source)
    var exact_detail_error_info: os.ErrorDetail = zero
    let (exact_detail_bytes, exact_detail_error) = io.read_all_detail(a, &exact_detail, 6usize, &exact_detail_error_info)
    if exact_detail_error != ok || !str.eq(exact_detail_bytes, "detail") { ret Failed }

    // `read_until` stops after the delimiter and keeps it.
    var line_source = io.SliceReader { data: "first\nsecond\n", off: 0usize }
    var lines = io.slice_reader(&line_source)
    let (line, line_error) = io.read_until(a, &lines, 10u8, 64usize)
    if line_error != ok { ret line_error }
    if !str.eq(line, "first\n") { ret Failed }

    var exact_until_source = io.SliceReader { data: "edge", off: 0usize }
    var exact_until = io.slice_reader(&exact_until_source)
    let (exact_until_bytes, exact_until_error) = io.read_until(a, &exact_until, 10u8, 4usize)
    if exact_until_error != ok || !str.eq(exact_until_bytes, "edge") { ret Failed }

    var empty_until_source = io.SliceReader { data: "", off: 0usize }
    var empty_until = io.slice_reader(&empty_until_source)
    let (empty_until_bytes, empty_until_error) = io.read_until(a, &empty_until, 10u8, 0usize)
    if empty_until_error != ok || empty_until_bytes.len != 0usize { ret Failed }

    // A callback may carry its final bytes with End. Every aggregation helper keeps
    // that payload, including when the delimiter is the final byte.
    let final_all_steps: [1]support.ReadStep = [1]support.ReadStep{ support.ReadStep { bytes: "all end", failure: io.End } }
    var (final_all_script, final_all_script_error) = support.scripted_reader(a, final_all_steps[..])
    if final_all_script_error != ok { ret final_all_script_error }
    var final_all = support.reader(&final_all_script)
    let (final_all_bytes, final_all_error) = io.read_all(a, &final_all, 64usize)
    if final_all_error != ok || !str.eq(final_all_bytes, "all end") { ret Failed }

    let final_until_steps: [1]support.ReadStep = [1]support.ReadStep{ support.ReadStep { bytes: "last\n", failure: io.End } }
    var (final_until_script, final_until_script_error) = support.scripted_reader(a, final_until_steps[..])
    if final_until_script_error != ok { ret final_until_script_error }
    var final_until = support.reader(&final_until_script)
    let (final_until_bytes, final_until_error) = io.read_until(a, &final_until, 10u8, 64usize)
    if final_until_error != ok || !str.eq(final_until_bytes, "last\n") { ret Failed }

    let final_copy_steps: [1]support.ReadStep = [1]support.ReadStep{ support.ReadStep { bytes: "end copy", failure: io.End } }
    var (final_copy_script, final_copy_script_error) = support.scripted_reader(a, final_copy_steps[..])
    if final_copy_script_error != ok { ret final_copy_script_error }
    var final_copy_from = support.reader(&final_copy_script)
    var final_copy_bytes: [16]u8 = zero
    var final_copy_sink_state = io.SliceWriter { data: final_copy_bytes[..], off: 0usize }
    var final_copy_sink = io.slice_writer(&final_copy_sink_state)
    let (final_copy_count, final_copy_error) = io.copy(&final_copy_sink, &final_copy_from, scratch[..])
    if final_copy_error != ok || final_copy_count != 8u64 || !str.eq(final_copy_bytes[0usize..8usize], "end copy") { ret Failed }

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

    // A failed flush keeps only the unwritten suffix. Retrying therefore cannot
    // duplicate the prefix that the sink accepted with the first error.
    let flush_steps: [2]support.WriteStep = [2]support.WriteStep{ support.WriteStep { max_bytes: 2usize, failure: Failed }, support.WriteStep { max_bytes: 4usize, failure: ok } }
    var (scripted, scripted_error) = support.scripted_writer(a, flush_steps[..], 8usize)
    if scripted_error != ok { ret scripted_error }
    var (retry_handle, retry_handle_error) = io.buffered_writer(a, support.writer(&scripted), 4usize)
    if retry_handle_error != ok { ret retry_handle_error }
    var retry_sink = io.buffered_sink(&retry_handle)
    if io.write_all(&retry_sink, "held") != ok { ret Failed }
    if io.flush(&retry_sink) != Failed { ret Failed }
    if !str.eq(support.captured(&scripted), "he") { ret Failed }
    if io.flush(&retry_sink) != ok { ret Failed }
    if !str.eq(support.captured(&scripted), "held") { ret Failed }

    // `memory_writer` returns a ready-to-use sink with stable state behind the handle.
    var (memory, memory_sink, memory_error) = io.memory_writer(a, 0usize)
    if memory_error != ok { ret memory_error }
    let memory_write_error = io.write_all(&memory_sink, "direct")
    if memory_write_error != ok { ret Failed }
    if !str.eq(io.memory_bytes(&memory), "direct") { ret Failed }

    // Detail streams compose without changing success provenance.
    var detail_source_state = io.SliceReader { data: "detail copy", off: 0usize }
    var detail_sink_bytes: [16]u8 = zero
    var detail_sink_state = io.SliceWriter { data: detail_sink_bytes[..], off: 0usize }
    var detail_source = io.slice_detail_reader(&detail_source_state)
    var detail_sink = io.slice_detail_writer(&detail_sink_state)
    var detail: os.ErrorDetail = zero
    detail.native_code = 77i32
    let (detail_moved, detail_copy_error) = io.copy_detail(&detail_sink, &detail_source, scratch[..], &detail)
    if detail_copy_error != ok || detail_moved != 11u64 { ret Failed }
    if !str.eq(detail_sink_bytes[0usize..11usize], "detail copy") || detail.native_code != 77i32 { ret Failed }

    // A failed constructor names its allocation step and restores the arena mark.
    var tiny_bytes: [1]u8 = zero
    var tiny = mem.arena_from(tiny_bytes[..])
    var allocation_detail: os.ErrorDetail = zero
    var empty_source_state = io.SliceReader { data: "", off: 0usize }
    let (tiny_reader, tiny_error) = io.buffered_detail_reader(&tiny, io.slice_detail_reader(&empty_source_state), 4usize, &allocation_detail)
    if tiny_error == ok || allocation_detail.kind != .OutOfMemory { ret Failed }
    if !str.eq(allocation_detail.operation, "buffered_reader") || !str.eq(allocation_detail.subject, "state") { ret Failed }
    if mem.mark(&tiny) != 0usize { ret Failed }

    var one_step_bytes: [512]u8 = zero
    var one_step = mem.arena_from(one_step_bytes[..])
    var buffer_allocation_detail: os.ErrorDetail = zero
    let (large_reader, large_error) = io.buffered_detail_reader(&one_step, io.slice_detail_reader(&empty_source_state), 1024usize, &buffer_allocation_detail)
    if large_error == ok || buffer_allocation_detail.kind != .OutOfMemory { ret Failed }
    if !str.eq(buffer_allocation_detail.operation, "buffered_reader") || !str.eq(buffer_allocation_detail.subject, "buffer") { ret Failed }
    if mem.mark(&one_step) != 0usize { ret Failed }

    // Plain buffered constructors roll back their state allocation when the byte
    // buffer cannot fit, just as their detail forms do.
    var plain_reader_bytes: [128]u8 = zero
    var plain_reader_arena = mem.arena_from(plain_reader_bytes[..])
    var plain_source_state = io.SliceReader { data: "", off: 0usize }
    let (_, plain_reader_error) = io.buffered_reader(&plain_reader_arena, io.slice_reader(&plain_source_state), 1024usize)
    if plain_reader_error != mem.Exhausted || mem.mark(&plain_reader_arena) != 0usize { ret Failed }

    var plain_writer_bytes: [128]u8 = zero
    var plain_writer_arena = mem.arena_from(plain_writer_bytes[..])
    var plain_sink_bytes: [1]u8 = zero
    var plain_sink_state = io.SliceWriter { data: plain_sink_bytes[..], off: 0usize }
    let (_, plain_writer_error) = io.buffered_writer(&plain_writer_arena, io.slice_writer(&plain_sink_state), 1024usize)
    if plain_writer_error != mem.Exhausted || mem.mark(&plain_writer_arena) != 0usize { ret Failed }
    ret ok
}
