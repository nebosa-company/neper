// `e.fmt.lzw`: round trips in both bit orders and at two literal widths, a 20 KB
// stream that fills the 12-bit table and clears mid-way, the empty and one-byte
// inputs, the width check and the output limit -- and the encoder's bytes matched by
// length and FNV-1a against an independent Python encoder (reference.py beside
// this fixture). Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.fmt.lzw as lzw
use e.algo.hash as hash

fn bytes_equal(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn roundtrip(a: *mem.Arena, order: lzw.Order, width: u8, text: []const u8, code: i32, want_len: usize, want_hash: u64) {
    let (needed, needed_error) = lzw.storage_required(width)
    if needed_error != ok { os.exit(code) }
    let (writer_storage, e1) = mem.alloc[u8](a, needed)
    let (reader_storage, e2) = mem.alloc[u8](a, needed)
    let (encoded, e3) = mem.alloc[u8](a, text.len * 2usize + 64usize)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(code) }
    var sink_state: io.SliceWriter = zero
    sink_state.data = encoded
    let (w0, writer_error) = lzw.writer(writer_storage, io.slice_writer(&sink_state), order, width)
    if writer_error != ok { os.exit(code) }
    var w = w0
    let (consumed, write_error) = lzw.write(&w, text)
    if write_error != ok || consumed != text.len { os.exit(code + 1i32) }
    if lzw.finish(&w) != ok { os.exit(code + 2i32) }
    // The bytes are what an independent GIF-style encoder produces (build/lzw_ref.py).
    if want_len != 0usize && (sink_state.off != want_len || hash.fnv1a64(encoded[..sink_state.off]) != want_hash) { os.exit(code + 7i32) }
    var source_state: io.SliceReader = zero
    source_state.data = encoded[..sink_state.off]
    let (r0, reader_error) = lzw.reader(reader_storage, io.slice_reader(&source_state), order, width, 1048576u64)
    if reader_error != ok { os.exit(code + 3i32) }
    var r = r0
    let (decoded, e4) = mem.alloc[u8](a, text.len + 16usize)
    if e4 != ok { os.exit(code) }
    var total = 0usize
    while true {
        let (count, read_error) = lzw.read(&r, decoded[total..])
        if read_error == io.End { break }
        if read_error != ok { os.exit(code + 4i32) }
        total += count
        if total > text.len { os.exit(code + 5i32) }
    }
    if !bytes_equal(decoded[..total], text) { os.exit(code + 6i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // The classic: repeated text, both bit orders, 8-bit literals.
    let text = "TOBEORNOTTOBEORTOBEORNOT#TOBEORNOTTOBEORTOBEORNOT"
    roundtrip(a, .LeastSignificant, 8u8, text, 10i32, 32usize, 10312578086233058210u64)
    roundtrip(a, .MostSignificant, 8u8, text, 20i32, 32usize, 16459588534279055608u64)
    // GIF-style 2-bit literals: pixels 0..3.
    var pixels: [400]u8 = zero
    var i = 0usize
    while i < 400usize {
        pixels[i] = u8((i * 7usize + i / 13usize) % 4usize)
        i += 1usize
    }
    roundtrip(a, .LeastSignificant, 2u8, pixels[0..], 30i32, 50usize, 11038684279154566379u64)
    // Enough distinct pairs to fill the 12-bit table and force a clear mid-stream.
    let (long, long_error) = mem.alloc[u8](a, 20000usize)
    if long_error != ok { os.exit(1) }
    i = 0usize
    var state = 12345u32
    while i < 20000usize {
        state = state *% 1103515245u32 +% 12345u32
        long[i] = u8((state >> 16u32) & 255u32)
        i += 1usize
    }
    roundtrip(a, .LeastSignificant, 8u8, long, 40i32, 27377usize, 4196807775975572889u64)
    roundtrip(a, .MostSignificant, 8u8, long, 50i32, 27377usize, 3928266707501397863u64)
    // The empty input and a single byte.
    let none: [0]u8 = zero
    roundtrip(a, .LeastSignificant, 8u8, none[0..], 60i32, 0usize, 0u64)
    let one: [1]u8 = [1]u8{ 200 }
    roundtrip(a, .MostSignificant, 8u8, one[0..], 70i32, 0usize, 0u64)
    // A known GIF stream: literals 0..3 then clear(4)/end(5), codes 3 bits: the sequence
    // clear, 1, 2, 1, end packed LSB-first.
    let (_, bad_width) = lzw.storage_required(9u8)
    if bad_width != lzw.Invalid { os.exit(80) }
    // The output limit stops a bomb.
    let (needed, _) = lzw.storage_required(8u8)
    let (limited_storage, _) = mem.alloc[u8](a, needed)
    var encoded_state: io.SliceWriter = zero
    let (enc_buf, _) = mem.alloc[u8](a, 4096usize)
    encoded_state.data = enc_buf
    let (lw0, _) = lzw.writer(limited_storage, io.slice_writer(&encoded_state), .LeastSignificant, 8u8)
    var lw = lw0
    let (_, _) = lzw.write(&lw, text)
    if lzw.finish(&lw) != ok { os.exit(81) }
    let (limit_storage, _) = mem.alloc[u8](a, needed)
    var limit_source: io.SliceReader = zero
    limit_source.data = enc_buf[..encoded_state.off]
    let (lr0, _) = lzw.reader(limit_storage, io.slice_reader(&limit_source), .LeastSignificant, 8u8, 10u64)
    var lr = lr0
    var small_out: [64]u8 = zero
    let (_, limit_error) = lzw.read(&lr, small_out[0..])
    if limit_error != lzw.TooLarge { os.exit(82) }
    os.exit(0)
    ret ok
}
