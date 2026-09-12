// `e.fmt.gzip`: Python's gzip of a 2280-byte text (with an FNAME field) read back
// through the reader in 100-byte pulls, the text written through the writer at
// Balanced and read back, and the refusals: a flipped CRC byte and a wrong ISIZE
// (Checksum), a bad magic byte and a reserved flag (Invalid), an output limit below
// the size, storage too small, a truncated member. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.fmt.gzip as gzip

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
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
    let (storage, s_error) = mem.alloc[u8](a, needed)
    if s_error != ok { os.exit(2) }
    let (out, o_error) = mem.alloc[u8](a, 4096usize)
    if o_error != ok { os.exit(3) }
    let (n1, e1) = inflate(storage, framed[0..], out, 1000000u64)
    if e1 != ok { os.exit(4) }
    if !same(out[..n1], text) { os.exit(5) }
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
    let (n5, e7) = inflate(storage, framed[0..], out, 2000u64)
    if e7 == ok || e7 == gzip.Checksum || e7 == gzip.Invalid { os.exit(15) }
    let (n6, e8) = inflate(storage[..100], framed[0..], out, 1000000u64)
    if e8 != io.TooSmall { os.exit(16) }
    let (n7, e9) = inflate(storage, framed[0..80], out, 1000000u64)
    if e9 != gzip.Invalid { os.exit(17) }
    ret ok
}
