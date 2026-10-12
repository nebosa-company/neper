// gRPC message compression (L164), the part `e.net.grpc` and `e.net.grpcserver` only report: a message carrying the
// compressed flag is a body in the call's `grpc-encoding`, and `inflate` undoes it. `gzip` is RFC 1952, `deflate` is the
// zlib stream (RFC 1950) every gRPC implementation means by that name, `identity` (or no encoding) is the payload as it is.
// An unknown encoding is `Unsupported`; a body that does not check out is the codec's own error (`Invalid`,
// `Checksum` or `TooLarge` past `limit`).
//
// Memory: the answer and the codec's state are allocated from the arena, which is retained.
use e.fmt.gzip as gzip
use e.fmt.zlib as zlib
use e.io
use e.mem
use e.str

error Unsupported

// Whether `encoding` is one `inflate` reads.
fn supported(encoding: str) -> bool {
    ret encoding.len == 0usize || str.eq(encoding, "identity") || str.eq(encoding, "gzip") || str.eq(encoding, "deflate")
}

fn aligned(a: *mem.Arena, bytes: usize) -> ([]u8, err) {
    let words = bytes / 8usize + 1usize
    let (taken, taken_error) = mem.alloc[u64](a, words)
    if taken_error != ok { ret (zero, taken_error) }
    ret (mem.view(a, a.off - words * 8usize, words * 8usize), ok)
}

// The body of a compressed message in `encoding`, at most `limit` bytes.
fn inflate(a: *mem.Arena, encoding: str, payload: []const u8, limit: usize) -> ([]const u8, err) {
    if encoding.len == 0usize || str.eq(encoding, "identity") { ret (payload, ok) }
    let (out, out_error) = mem.alloc[u8](a, limit + 1usize)
    if out_error != ok { ret (zero, out_error) }
    var source_state = io.SliceReader { data: payload, off: 0usize }
    var total = 0usize
    if str.eq(encoding, "gzip") {
        let (storage, storage_error) = aligned(a, gzip.storage_required(.Fast))
        if storage_error != ok { ret (zero, storage_error) }
        let (made, reader_error) = gzip.reader(storage, io.slice_reader(&source_state), u64(limit))
        if reader_error != ok { ret (zero, reader_error) }
        var r = made
        while true {
            let (count, read_error) = gzip.read(&r, out[total..limit + 1usize])
            if read_error == io.End { break }
            if read_error != ok { ret (zero, read_error) }
            total += count
            if total > limit { ret (zero, io.TooSmall) }
        }
        ret (out[0usize..total], ok)
    }
    if str.eq(encoding, "deflate") {
        let (storage, storage_error) = aligned(a, zlib.storage_required(.Fast))
        if storage_error != ok { ret (zero, storage_error) }
        let (made, reader_error) = zlib.reader(storage, io.slice_reader(&source_state), u64(limit))
        if reader_error != ok { ret (zero, reader_error) }
        var r = made
        while true {
            let (count, read_error) = zlib.read(&r, out[total..limit + 1usize])
            if read_error == io.End { break }
            if read_error != ok { ret (zero, read_error) }
            total += count
            if total > limit { ret (zero, io.TooSmall) }
        }
        ret (out[0usize..total], ok)
    }
    ret (zero, Unsupported)
}
