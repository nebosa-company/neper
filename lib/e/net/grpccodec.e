// gRPC message compression (L164), the part `e.net.grpc` and `e.net.grpcserver` only report: a message carrying the
// compressed flag is a body in the call's `grpc-encoding`, and `inflate` undoes it. `gzip` is RFC 1952, `deflate` is the
// zlib stream (RFC 1950) every gRPC implementation means by that name, `identity` (or no encoding) is the payload as it is.
// An unknown encoding is `Unsupported`; a body that does not check out is the codec's own error (`Invalid`,
// `Checksum` or `TooLarge` past `limit`).
//
// The send side is `compress` (the compressed body of a message in `gzip` or `deflate`), `compress_message` (what a sender
// does with one message: compressed and flagged when an encoding is chosen and the message is at least `threshold`
// bytes long, as it is otherwise) and `choose_encoding` (the first encoding of a peer's `grpc-accept-encoding` list this
// codec writes; identity when there is none).
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

// The body of a message compressed into `encoding` (`gzip` or `deflate`, the zlib stream), at the balanced level.
fn compress(a: *mem.Arena, encoding: str, payload: []const u8) -> ([]const u8, err) {
    if encoding.len == 0usize || str.eq(encoding, "identity") { ret (payload, ok) }
    // the worst case is stored blocks: five bytes per 65535, the stream's own header and trailer
    let capacity = payload.len + payload.len / 4usize + 128usize
    let (out, out_error) = mem.alloc[u8](a, capacity)
    if out_error != ok { ret (zero, out_error) }
    var sink_state = io.SliceWriter { data: out, off: 0usize }
    if str.eq(encoding, "gzip") {
        let (storage, storage_error) = aligned(a, gzip.storage_required(.Balanced))
        if storage_error != ok { ret (zero, storage_error) }
        let (made, writer_error) = gzip.writer(storage, io.slice_writer(&sink_state), .Balanced)
        if writer_error != ok { ret (zero, writer_error) }
        var w = made
        let (count, write_error) = gzip.write(&w, payload)
        if write_error != ok { ret (zero, write_error) }
        let finish_error = gzip.finish(&w)
        if finish_error != ok { ret (zero, finish_error) }
        ret (out[0usize..sink_state.off], ok)
    }
    if str.eq(encoding, "deflate") {
        let (storage, storage_error) = aligned(a, zlib.storage_required(.Balanced))
        if storage_error != ok { ret (zero, storage_error) }
        let (made, writer_error) = zlib.writer(storage, io.slice_writer(&sink_state), .Balanced)
        if writer_error != ok { ret (zero, writer_error) }
        var w = made
        let (count, write_error) = zlib.write(&w, payload)
        if write_error != ok { ret (zero, write_error) }
        let finish_error = zlib.finish(&w)
        if finish_error != ok { ret (zero, finish_error) }
        ret (out[0usize..sink_state.off], ok)
    }
    ret (zero, Unsupported)
}

type Prepared = struct { body: []const u8, compressed: bool }

// What goes on the wire for one message: `encoding` at or above `threshold` bytes is compressed and flagged; below it,
// or with identity or no encoding, the message is sent as it is and the flag is clear.
fn compress_message(a: *mem.Arena, encoding: str, payload: []const u8, threshold: usize) -> (Prepared, err) {
    if encoding.len == 0usize || str.eq(encoding, "identity") || payload.len < threshold { ret (Prepared { body: payload, compressed: false }, ok) }
    let (body, body_error) = compress(a, encoding, payload)
    if body_error != ok { ret (Prepared { body: zero, compressed: false }, body_error) }
    ret (Prepared { body: body, compressed: true }, ok)
}

// The first encoding in a comma-separated `grpc-accept-encoding` list that `compress` writes (`gzip` or `deflate`), with
// spaces around names ignored; `identity` when the list names none.
fn choose_encoding(accept: str) -> str {
    var start = 0usize
    var at = 0usize
    while at <= accept.len {
        if at == accept.len || accept[at] == 44u8 {
            let name = str.trim(accept[start..at])
            if str.eq(name, "gzip") || str.eq(name, "deflate") { ret name }
            start = at + 1usize
        }
        at += 1usize
    }
    ret "identity"
}
