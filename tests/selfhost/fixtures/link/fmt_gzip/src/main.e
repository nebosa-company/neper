// `e.fmt.gzip`: Python's gzip of a 2280-byte text (with an FNAME field) read back
// through the reader in 100-byte pulls, the text written through the writer at
// Balanced and read back, and the refusals: a flipped CRC byte and a wrong ISIZE
// (Checksum), a bad magic byte and a reserved flag (Invalid), an output limit below
// the size, storage too small, a truncated member. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.algo.hash as hash
use e.algo.deflate as deflate
use e.fmt.gzip as gzip

error SinkFailed

type FailingSink = struct { data: []u8, off: usize, writes: usize, fail_write: usize, fail_flush: bool }

fn failing_write(ctx: *void, src: []const u8) -> (usize, err) {
    let sink = mem.cast[*FailingSink](ctx)
    sink.writes += 1usize
    var count = src.len
    if sink.fail_write != 0usize && sink.writes == sink.fail_write {
        if count > 1usize { count = 1usize }
        if count > 0usize { mem.copy[u8](sink.data[sink.off..sink.off + count], src[..count]) }
        sink.off += count
        ret (count, SinkFailed)
    }
    mem.copy[u8](sink.data[sink.off..sink.off + count], src)
    sink.off += count
    ret (count, ok)
}

fn failing_flush(ctx: *void) -> err {
    let sink = mem.cast[*FailingSink](ctx)
    if sink.fail_flush { ret SinkFailed }
    ret ok
}

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

// Deliberately returns its final bytes with io.End, which io.Reader permits.
type EndingReader = struct {
    data: []const u8,
    off: usize,
}

fn ending_read(ctx: *void, dst: []u8) -> (usize, err) {
    var state = mem.cast[*EndingReader](ctx)
    if dst.len == 0usize { ret (0usize, ok) }
    if state.off >= state.data.len { ret (0usize, io.End) }
    var take = state.data.len - state.off
    if take > dst.len { take = dst.len }
    mem.copy[u8](dst[..take], state.data[state.off..state.off + take])
    state.off += take
    if state.off == state.data.len { ret (take, io.End) }
    ret (take, ok)
}

fn drain(r: *gzip.Reader, out: []u8) -> (usize, err) {
    var total = 0usize
    while true {
        let (count, read_error) = gzip.read(r, out[total..])
        total += count
        if read_error == io.End { ret (total, ok) }
        if read_error != ok { ret (total, read_error) }
    }
}

// Reads everything through a gzip reader over `framed` in 100-byte pulls.
fn inflate(storage: []u8, framed: []const u8, out: []u8, limit: u64) -> (usize, err) {
    var source_state = io.SliceReader { data: framed, off: 0usize }
    let (r0, reader_error) = gzip.reader(storage, io.slice_reader(&source_state), limit)
    if reader_error != ok { ret (0usize, reader_error) }
    var r = r0
    var total = 0usize
    while true {
        var end = total + 100usize
        if end > out.len { end = out.len }
        let (count, read_error) = gzip.read(&r, out[total..end])
        if read_error == io.End { break }
        if read_error != ok { ret (total, read_error) }
        total += count
    }
    ret (total, ok)
}

// Storage the module casts to its state struct: taken as u64s so it is 8-aligned.
fn aligned(a: *mem.Arena, bytes: usize) -> ([]u8, err) {
    let words = bytes / 8usize + 1usize
    let (taken, taken_error) = mem.alloc[u64](a, words)
    if taken_error != ok { ret (zero, taken_error) }
    ret (mem.view(a, a.off - words * 8usize, words * 8usize), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let framed: [91]u8 = [91]u8{ 31, 139, 8, 8, 0, 0, 0, 0, 2, 255, 110, 97, 109, 101, 46, 116, 120, 116, 0, 203, 72, 205, 201, 201, 87, 200, 64, 39, 117, 20, 210, 171, 50, 11, 20, 210, 138, 18, 115, 51, 243, 210, 21, 242, 203, 82, 139, 20, 242, 82, 11, 128, 100, 74, 106, 90, 78, 98, 73, 42, 87, 198, 168, 198, 81, 141, 163, 26, 71, 53, 142, 106, 28, 213, 56, 170, 113, 84, 227, 224, 214, 8, 0, 204, 37, 229, 225, 232, 8, 0, 0 }
    let line = "hello hello hello hello, gzip framing over neper deflate\n"
    let (text, t_error) = mem.alloc[u8](a, 2280usize)
    if t_error != ok { os.exit(1) }
    var i = 0usize
    while i < 40usize {
        mem.copy[u8](text[i * line.len..(i + 1usize) * line.len], line)
        i += 1usize
    }
    let needed = gzip.storage_required(.Balanced)
    let (storage, s_error) = aligned(a, needed)
    if s_error != ok { os.exit(2) }
    let (out, o_error) = mem.alloc[u8](a, 4096usize)
    if o_error != ok { os.exit(3) }
    let (n1, e1) = inflate(storage, framed[0..], out, 1000000u64)
    if e1 != ok { os.exit(4) }
    if !same(out[..n1], text) { os.exit(5) }
    // A limit is checked before the caller's bytes are exposed. The probe read
    // sees the next decoded byte privately, leaving the sentinel intact.
    var bounded_source = io.SliceReader { data: framed[..], off: 0usize }
    let (bounded0, bounded_error) = gzip.reader(storage, io.slice_reader(&bounded_source), 1u64)
    if bounded_error != ok { os.exit(33) }
    var bounded = bounded0
    var bounded_out: [8]u8 = zero
    var bounded_at = 0usize
    while bounded_at < bounded_out.len {
        bounded_out[bounded_at] = 170u8
        bounded_at += 1usize
    }
    let (bounded_count, bounded_read_error) = gzip.read(&bounded, bounded_out[..])
    if bounded_count != 1usize || bounded_read_error != ok || bounded_out[0usize] != text[0usize] || bounded_out[1usize] != 170u8 { os.exit(34) }
    let (overflow_count, overflow_error) = gzip.read(&bounded, bounded_out[..])
    if overflow_count != 0usize || overflow_error != deflate.TooLarge || bounded_out[1usize] != 170u8 { os.exit(35) }
    let (repeat_overflow_count, repeat_overflow_error) = gzip.read(&bounded, bounded_out[..])
    if repeat_overflow_count != 0usize || repeat_overflow_error != deflate.TooLarge || bounded_out[1usize] != 170u8 { os.exit(36) }
    // A valid stream whose output exactly fills the limit still reaches its trailer.
    var exact_source = io.SliceReader { data: framed[..], off: 0usize }
    let (exact0, exact_open_error) = gzip.reader(storage, io.slice_reader(&exact_source), u64(text.len))
    if exact_open_error != ok { os.exit(37) }
    var exact = exact0
    let (exact_count, exact_read_error) = gzip.read(&exact, out)
    if exact_count != text.len || exact_read_error != ok || !same(out[..exact_count], text) { os.exit(38) }
    let (exact_end_count, exact_end_error) = gzip.read(&exact, out)
    if exact_end_count != 0usize || exact_end_error != io.End { os.exit(39) }
    // Write and read back.
    let (packed, p_error) = mem.alloc[u8](a, 4096usize)
    if p_error != ok { os.exit(6) }
    var sink_state = io.SliceWriter { data: packed, off: 0usize }
    let (w0, w_error) = gzip.writer(storage, io.slice_writer(&sink_state), .Balanced)
    if w_error != ok { os.exit(7) }
    var w = w0
    let (c1, e2) = gzip.write(&w, text[..1000])
    if e2 != ok || c1 != 1000usize { os.exit(8) }
    let (c2, e3) = gzip.write(&w, text[1000..])
    if e3 != ok || c2 != 1280usize { os.exit(9) }
    if gzip.finish(&w) != ok { os.exit(10) }
    if packed[0] != 31u8 || packed[1] != 139u8 || packed[2] != 8u8 || sink_state.off >= text.len { os.exit(11) }
    let (n2, e4) = inflate(storage, packed[..sink_state.off], out, 1000000u64)
    if e4 != ok || !same(out[..n2], text) { os.exit(12) }
    // Refusals.
    var flipped = framed
    flipped[84] = flipped[84] ^ 1u8
    let (n3, e5) = inflate(storage, flipped[0..], out, 1000000u64)
    if e5 != gzip.Checksum { os.exit(13) }
    var wrong_size = framed
    wrong_size[88] = 9u8
    let (n3b, e5b) = inflate(storage, wrong_size[0..], out, 1000000u64)
    if e5b != gzip.Checksum { os.exit(18) }
    var bad_header = framed
    bad_header[1] = 140u8
    let (n4, e6) = inflate(storage, bad_header[0..], out, 1000000u64)
    if e6 != gzip.Invalid { os.exit(14) }
    var reserved = framed
    reserved[3] = reserved[3] | 32u8
    let (n4b, e6b) = inflate(storage, reserved[0..], out, 1000000u64)
    if e6b != gzip.Invalid { os.exit(19) }
    // FHCRC covers the complete header, excluding the field itself. A bad header
    // checksum must be rejected before compressed data is accepted.
    let (fhcrc, fhcrc_error) = mem.alloc[u8](a, framed.len + 2usize)
    if fhcrc_error != ok { os.exit(20) }
    mem.copy[u8](fhcrc[..19usize], framed[..19usize])
    fhcrc[3usize] = fhcrc[3usize] | 2u8
    let header_crc = hash.crc32(fhcrc[..19usize]) & 65535u32
    fhcrc[19usize] = u8(header_crc & 255u32)
    fhcrc[20usize] = u8(header_crc >> 8u32)
    mem.copy[u8](fhcrc[21usize..], framed[19usize..])
    let (_, good_fhcrc) = inflate(storage, fhcrc, out, 1000000u64)
    if good_fhcrc != ok { os.exit(21) }
    fhcrc[19usize] = fhcrc[19usize] ^ 1u8
    let (_, bad_fhcrc) = inflate(storage, fhcrc, out, 1000000u64)
    if bad_fhcrc != gzip.Checksum { os.exit(22) }
    let (n5, e7) = inflate(storage, framed[0..], out, 2000u64)
    if e7 == ok || e7 == gzip.Checksum || e7 == gzip.Invalid { os.exit(15) }
    let (n6, e8) = inflate(storage[..100], framed[0..], out, 1000000u64)
    if e8 != io.TooSmall { os.exit(16) }
    let (n7, e9) = inflate(storage, framed[0..80], out, 1000000u64)
    if e9 != gzip.Invalid { os.exit(17) }
    // A private refill can contain later members and enclosing bytes. They must
    // survive a final read that returns both bytes and io.End.
    var joined: [183]u8 = zero
    mem.copy[u8](joined[..91usize], framed[..])
    mem.copy[u8](joined[91usize..182usize], framed[..])
    joined[182usize] = 33u8
    var ending = EndingReader { data: joined[..], off: 0usize }
    let (first0, first_error) = gzip.reader(storage, io.Reader { ctx: mem.cast[*void](&ending), read: ending_read }, 1000000u64)
    if first_error != ok { os.exit(23) }
    var first = first0
    let (first_count, first_read_error) = drain(&first, out)
    if first_read_error != ok || !same(out[..first_count], text) { os.exit(24) }
    if ending.off != joined.len { os.exit(25) }
    let (second_source, remaining_error) = gzip.remaining(&first)
    if remaining_error != ok { os.exit(26) }
    let (storage2, storage2_error) = aligned(a, needed)
    if storage2_error != ok { os.exit(27) }
    let (second0, second_error) = gzip.reader(storage2, second_source, 1000000u64)
    if second_error != ok { os.exit(28) }
    var second = second0
    let (second_count, second_read_error) = drain(&second, out)
    if second_read_error != ok || !same(out[..second_count], text) { os.exit(29) }
    var (suffix_source, suffix_error) = gzip.remaining(&second)
    if suffix_error != ok { os.exit(30) }
    var suffix: [2]u8 = zero
    let (suffix_count, suffix_read_error) = io.read(&suffix_source, suffix[..])
    if suffix_read_error != ok || suffix_count != 1usize || suffix[0usize] != 33u8 { os.exit(31) }
    let (end_count, end_error) = io.read(&suffix_source, suffix[..])
    if end_count != 0usize || end_error != io.End { os.exit(32) }

    // A partial sink write after the encoder has consumed input poisons the
    // writer: retrying either write or finish must not report success.
    let (failure_input, failure_input_error) = mem.alloc[u8](a, 32768usize)
    if failure_input_error != ok { os.exit(40) }
    var failure_at = 0usize
    while failure_at < failure_input.len {
        failure_input[failure_at] = 65u8
        failure_at += 1usize
    }
    let (failure_bytes, failure_bytes_error) = mem.alloc[u8](a, 4096usize)
    if failure_bytes_error != ok { os.exit(41) }
    var failed_sink = FailingSink { data: failure_bytes, off: 0usize, writes: 0usize, fail_write: 2usize, fail_flush: false }
    let (failed_storage, failed_storage_error) = aligned(a, needed)
    if failed_storage_error != ok { os.exit(42) }
    let (failed_writer0, failed_writer_error) = gzip.writer(failed_storage, io.Writer { ctx: mem.cast[*void](&failed_sink), write: failing_write, flush: failing_flush }, .Fast)
    if failed_writer_error != ok { os.exit(43) }
    var failed_writer = failed_writer0
    let (_, failed_write_error) = gzip.write(&failed_writer, failure_input)
    if failed_write_error != SinkFailed { os.exit(44) }
    let failed_off = failed_sink.off
    let (retry_count, retry_error) = gzip.write(&failed_writer, "retry")
    if retry_count != 0usize || retry_error != gzip.Invalid || gzip.finish(&failed_writer) != gzip.Invalid || failed_sink.off != failed_off { os.exit(45) }

    // A short trailer write is also terminal: a later finish cannot append it.
    var trailer_sink = FailingSink { data: failure_bytes, off: 0usize, writes: 0usize, fail_write: 3usize, fail_flush: false }
    let (trailer_storage, trailer_storage_error) = aligned(a, needed)
    if trailer_storage_error != ok { os.exit(46) }
    let (trailer_writer0, trailer_writer_error) = gzip.writer(trailer_storage, io.Writer { ctx: mem.cast[*void](&trailer_sink), write: failing_write, flush: failing_flush }, .Balanced)
    if trailer_writer_error != ok { os.exit(47) }
    var trailer_writer = trailer_writer0
    let (_, trailer_write_error) = gzip.write(&trailer_writer, "trailer")
    if trailer_write_error != ok || gzip.finish(&trailer_writer) != SinkFailed || trailer_sink.writes != 3usize { os.exit(48) }
    let trailer_off = trailer_sink.off
    let (after_trailer_count, after_trailer_error) = gzip.write(&trailer_writer, "retry")
    if after_trailer_count != 0usize || after_trailer_error != gzip.Invalid || gzip.finish(&trailer_writer) != gzip.Invalid || trailer_sink.off != trailer_off { os.exit(49) }

    // A failed final flush is equally terminal and cannot turn into a later ok.
    var flush_sink = FailingSink { data: failure_bytes, off: 0usize, writes: 0usize, fail_write: 0usize, fail_flush: true }
    let (flush_storage, flush_storage_error) = aligned(a, needed)
    if flush_storage_error != ok { os.exit(50) }
    let (flush_writer0, flush_writer_error) = gzip.writer(flush_storage, io.Writer { ctx: mem.cast[*void](&flush_sink), write: failing_write, flush: failing_flush }, .Balanced)
    if flush_writer_error != ok { os.exit(51) }
    var flush_writer = flush_writer0
    let (_, flush_write_error) = gzip.write(&flush_writer, "flush")
    if flush_write_error != ok || gzip.finish(&flush_writer) != SinkFailed { os.exit(52) }
    let flush_off = flush_sink.off
    let (after_flush_count, after_flush_error) = gzip.write(&flush_writer, "retry")
    if after_flush_count != 0usize || after_flush_error != gzip.Invalid || gzip.finish(&flush_writer) != gzip.Invalid || flush_sink.off != flush_off { os.exit(53) }
    ret ok
}
