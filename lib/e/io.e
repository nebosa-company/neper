// Byte streams over the fixed `e.os` surface.
//
// A `Reader` and a `Writer` are a context and a callback, so a stream is a value and
// costs no allocation. The callbacks each constructor installs are declarations of
// their own (D94): the language has no visibility mechanism, so a helper is a public
// symbol whether or not the surface names it, and this one names them.

use e.mem
use e.os
use e.str

error End
error TooSmall
error NoProgress

type Reader = struct {
    ctx: *void,
    read: fn(*void, []u8) -> (usize, err),
}

type DetailReader = struct {
    ctx: *void,
    read: fn(*void, []u8, *os.ErrorDetail) -> (usize, err),
}

type Writer = struct {
    ctx: *void,
    write: fn(*void, []const u8) -> (usize, err),
    flush: fn(*void) -> err,
}

type DetailWriter = struct {
    ctx: *void,
    write: fn(*void, []const u8, *os.ErrorDetail) -> (usize, err),
    flush: fn(*void, *os.ErrorDetail) -> err,
}

type SliceReader = struct {
    data: []const u8,
    off: usize,
}

type SliceWriter = struct {
    data: []u8,
    off: usize,
}

type BufferedReader = struct {
    state: *void,
}

type BufferedWriter = struct {
    state: *void,
}

type Seeker = struct {
    ctx: *void,
    seek: fn(*void, i64, os.SeekWhence) -> (u64, err),
}

type LimitedReader = struct {
    source: Reader,
    remaining: u64,
}

type CountingWriter = struct {
    sink: Writer,
    count: u64,
}

type TeeWriter = struct {
    left: Writer,
    right: Writer,
}

type MemoryWriter = struct {
    arena: *mem.Arena,
    start: usize,
    len: usize,
}

// The buffered adapters hold their state behind a `*void` so the surface does not fix
// its layout. `BufferState` is that layout; it is one type for both directions, and
// which half is live is decided by the constructor that allocated it.
type BufferState = struct {
    source: Reader,
    sink: Writer,
    buffer: []u8,
    off: usize,
    len: usize,
}

fn no_flush(ctx: *void) -> err {
    ret ok
}

fn no_flush_detail(ctx: *void, detail: *os.ErrorDetail) -> err {
    ret ok
}

fn reader(ctx: *void, read_fn: fn(*void, []u8) -> (usize, err)) -> Reader {
    ret Reader { ctx: ctx, read: read_fn }
}

fn detail_reader(ctx: *void, read_fn: fn(*void, []u8, *os.ErrorDetail) -> (usize, err)) -> DetailReader {
    ret DetailReader { ctx: ctx, read: read_fn }
}

fn writer(ctx: *void, write_fn: fn(*void, []const u8) -> (usize, err)) -> Writer {
    ret Writer { ctx: ctx, write: write_fn, flush: no_flush }
}

fn detail_writer(ctx: *void, write_fn: fn(*void, []const u8, *os.ErrorDetail) -> (usize, err)) -> DetailWriter {
    ret DetailWriter { ctx: ctx, write: write_fn, flush: no_flush_detail }
}

fn writer_with_flush(ctx: *void, write_fn: fn(*void, []const u8) -> (usize, err), flush_fn: fn(*void) -> err) -> Writer {
    ret Writer { ctx: ctx, write: write_fn, flush: flush_fn }
}

fn detail_writer_with_flush(ctx: *void, write_fn: fn(*void, []const u8, *os.ErrorDetail) -> (usize, err), flush_fn: fn(*void, *os.ErrorDetail) -> err) -> DetailWriter {
    ret DetailWriter { ctx: ctx, write: write_fn, flush: flush_fn }
}

fn file_read(ctx: *void, dst: []u8) -> (usize, err) {
    var file = mem.cast[*os.File](ctx)
    let (count, read_error) = os.read(*file, dst)
    if read_error != ok { ret (count, read_error) }
    // A host read that takes nothing from a non-empty request has reached the end -- that is
    // what `read(2)` and `ReadFile` both mean by zero, on a file, a pipe and a socket alike.
    // Saying so here is what makes `End` the answer whatever the source is: `slice_read` says
    // it already, and without this a file said `NoProgress` instead, so every loop written
    // against the `Reader` contract ended in an error on a file and in an end on a slice.
    if count == 0usize && dst.len != 0usize { ret (0usize, End) }
    ret (count, ok)
}

fn file_read_detail(ctx: *void, dst: []u8, detail: *os.ErrorDetail) -> (usize, err) {
    var file = mem.cast[*os.File](ctx)
    let (count, read_error) = os.read_detail(*file, dst, detail)
    if read_error != ok { ret (count, read_error) }
    if count == 0usize && dst.len != 0usize { ret (0usize, End) }
    ret (count, ok)
}

fn file_write(ctx: *void, src: []const u8) -> (usize, err) {
    var file = mem.cast[*os.File](ctx)
    let (count, write_error) = os.write(*file, src)
    ret (count, write_error)
}

fn file_write_detail(ctx: *void, src: []const u8, detail: *os.ErrorDetail) -> (usize, err) {
    var file = mem.cast[*os.File](ctx)
    let (count, write_error) = os.write_detail(*file, src, detail)
    ret (count, write_error)
}

fn file_seek(ctx: *void, off: i64, whence: os.SeekWhence) -> (u64, err) {
    var file = mem.cast[*os.File](ctx)
    let (position, seek_error) = os.seek(*file, off, whence)
    ret (position, seek_error)
}

fn file_reader(file: *os.File) -> Reader {
    ret Reader { ctx: mem.cast[*void](file), read: file_read }
}

fn file_detail_reader(file: *os.File) -> DetailReader {
    ret DetailReader { ctx: mem.cast[*void](file), read: file_read_detail }
}

fn file_writer(file: *os.File) -> Writer {
    ret Writer { ctx: mem.cast[*void](file), write: file_write, flush: no_flush }
}

fn file_detail_writer(file: *os.File) -> DetailWriter {
    ret DetailWriter { ctx: mem.cast[*void](file), write: file_write_detail, flush: no_flush_detail }
}

fn file_seeker(file: *os.File) -> Seeker {
    ret Seeker { ctx: mem.cast[*void](file), seek: file_seek }
}

fn slice_read(ctx: *void, dst: []u8) -> (usize, err) {
    var state = mem.cast[*SliceReader](ctx)
    if state.off >= state.data.len { ret (0usize, End) }
    var take = state.data.len - state.off
    if take > dst.len { take = dst.len }
    var at = 0usize
    while at < take {
        dst[at] = state.data[state.off + at]
        at += 1usize
    }
    state.off += take
    ret (take, ok)
}

fn slice_read_detail(ctx: *void, dst: []u8, detail: *os.ErrorDetail) -> (usize, err) {
    let (count, read_error) = slice_read(ctx, dst)
    ret (count, read_error)
}

fn slice_write(ctx: *void, src: []const u8) -> (usize, err) {
    var state = mem.cast[*SliceWriter](ctx)
    if state.off >= state.data.len { ret (0usize, TooSmall) }
    var take = state.data.len - state.off
    if take > src.len { take = src.len }
    var at = 0usize
    while at < take {
        state.data[state.off + at] = src[at]
        at += 1usize
    }
    state.off += take
    ret (take, ok)
}

fn slice_write_detail(ctx: *void, src: []const u8, detail: *os.ErrorDetail) -> (usize, err) {
    let (count, write_error) = slice_write(ctx, src)
    if write_error != ok {
        detail.kind = .Invalid
        detail.native_code = 0i32
        detail.operation = "write"
        detail.subject = "capacity"
    }
    ret (count, write_error)
}

fn slice_reader(state: *SliceReader) -> Reader {
    ret Reader { ctx: mem.cast[*void](state), read: slice_read }
}

fn slice_detail_reader(state: *SliceReader) -> DetailReader {
    ret DetailReader { ctx: mem.cast[*void](state), read: slice_read_detail }
}

fn slice_writer(state: *SliceWriter) -> Writer {
    ret Writer { ctx: mem.cast[*void](state), write: slice_write, flush: no_flush }
}

fn slice_detail_writer(state: *SliceWriter) -> DetailWriter {
    ret DetailWriter { ctx: mem.cast[*void](state), write: slice_write_detail, flush: no_flush_detail }
}

fn limited_read(ctx: *void, dst: []u8) -> (usize, err) {
    var state = mem.cast[*LimitedReader](ctx)
    if state.remaining == 0u64 { ret (0usize, End) }
    var take = dst.len
    if u64(take) > state.remaining { take = usize(state.remaining) }
    let (count, read_error) = read(&state.source, dst[0usize..take])
    if read_error != ok { ret (count, read_error) }
    state.remaining -= u64(count)
    ret (count, ok)
}

fn limited_reader(state: *LimitedReader, source: Reader, limit: u64) -> Reader {
    state.source = source
    state.remaining = limit
    ret Reader { ctx: mem.cast[*void](state), read: limited_read }
}

fn counting_write(ctx: *void, src: []const u8) -> (usize, err) {
    var state = mem.cast[*CountingWriter](ctx)
    let (count, write_error) = write(&state.sink, src)
    state.count += u64(count)
    ret (count, write_error)
}

// An adapter that owns no buffer forwards the flush to what it wraps, because the
// bytes it did not keep are the wrapped sink's to deal with.
fn forwarding_flush(ctx: *void) -> err {
    var state = mem.cast[*CountingWriter](ctx)
    ret flush(&state.sink)
}

fn counting_writer(state: *CountingWriter, sink: Writer) -> Writer {
    state.sink = sink
    state.count = 0u64
    ret Writer { ctx: mem.cast[*void](state), write: counting_write, flush: forwarding_flush }
}

// Left before right, stopping on the first error: what reaches the right sink is
// whatever the left one accepted, so this is duplication and not a transaction.
fn tee_write(ctx: *void, src: []const u8) -> (usize, err) {
    var state = mem.cast[*TeeWriter](ctx)
    let (count, left_error) = write(&state.left, src)
    if left_error != ok { ret (count, left_error) }
    let (right_count, right_error) = write(&state.right, src[0usize..count])
    if right_error != ok { ret (right_count, right_error) }
    if right_count != count { ret (right_count, NoProgress) }
    ret (count, ok)
}

fn tee_writer(state: *TeeWriter, left: Writer, right: Writer) -> Writer {
    state.left = left
    state.right = right
    ret Writer { ctx: mem.cast[*void](state), write: tee_write, flush: no_flush }
}

fn memory_write(ctx: *void, src: []const u8) -> (usize, err) {
    var state = mem.cast[*MemoryWriter](ctx)
    let (claim, claim_error) = mem.alloc[u8](state.arena, src.len)
    if claim_error != ok { ret (0usize, claim_error) }
    var at = 0usize
    while at < src.len {
        claim[at] = src[at]
        at += 1usize
    }
    state.len += src.len
    ret (src.len, ok)
}

fn memory_writer(a: *mem.Arena, capacity: usize) -> (MemoryWriter, Writer, err) {
    var state: MemoryWriter = zero
    state.arena = a
    state.start = mem.mark(a)
    state.len = 0usize
    var sink: Writer = zero
    if capacity > 0usize {
        // Reserve and give it straight back, so the caller learns now rather than on
        // the first write whether the arena can hold what it asked for.
        let (claim, claim_error) = mem.alloc[u8](a, capacity)
        if claim_error != ok { ret (state, sink, claim_error) }
        mem.reset(a, state.start)
    }
    ret (state, sink, ok)
}

fn memory_bytes(w: *const MemoryWriter) -> []const u8 {
    ret mem.view(w.arena, w.start, w.len)
}

fn read(r: *Reader, dst: []u8) -> (usize, err) {
    if dst.len == 0usize { ret (0usize, ok) }
    let (count, read_error) = r.read(r.ctx, dst)
    if read_error != ok { ret (count, read_error) }
    // A callback that reports neither progress nor an end would spin a caller
    // forever, so it is an error here rather than in every loop below.
    if count == 0usize { ret (0usize, NoProgress) }
    ret (count, ok)
}

fn read_detail(r: *DetailReader, dst: []u8, detail: *os.ErrorDetail) -> (usize, err) {
    if dst.len == 0usize { ret (0usize, ok) }
    let (count, read_error) = r.read(r.ctx, dst, detail)
    if read_error != ok { ret (count, read_error) }
    if count == 0usize {
        detail.kind = .Invalid
        detail.native_code = 0i32
        detail.operation = "read"
        detail.subject = "no progress"
        ret (0usize, NoProgress)
    }
    ret (count, ok)
}

fn read_exact_detail(r: *DetailReader, dst: []u8, detail: *os.ErrorDetail) -> (usize, err) {
    var filled = 0usize
    while filled < dst.len {
        let (count, read_error) = read_detail(r, dst[filled..], detail)
        filled += count
        if read_error != ok { ret (filled, read_error) }
    }
    ret (filled, ok)
}

fn read_exact(r: *Reader, dst: []u8) -> err {
    var filled = 0usize
    while filled < dst.len {
        let (count, read_error) = read(r, dst[filled..])
        if read_error != ok { ret read_error }
        filled += count
    }
    ret ok
}

fn write(w: *Writer, src: []const u8) -> (usize, err) {
    if src.len == 0usize { ret (0usize, ok) }
    let (count, write_error) = w.write(w.ctx, src)
    if write_error != ok { ret (count, write_error) }
    if count == 0usize { ret (0usize, NoProgress) }
    ret (count, ok)
}

// The counted form is the primitive for adapters that must retain an unwritten
// suffix after a short write plus an error.
fn write_all_progress(w: *Writer, src: []const u8) -> (usize, err) {
    var written = 0usize
    while written < src.len {
        let (count, write_error) = write(w, src[written..])
        written += count
        if write_error != ok { ret (written, write_error) }
    }
    ret (written, ok)
}

fn write_detail(w: *DetailWriter, src: []const u8, detail: *os.ErrorDetail) -> (usize, err) {
    if src.len == 0usize { ret (0usize, ok) }
    let (count, write_error) = w.write(w.ctx, src, detail)
    if write_error != ok { ret (count, write_error) }
    if count == 0usize {
        detail.kind = .Invalid
        detail.native_code = 0i32
        detail.operation = "write"
        detail.subject = "no progress"
        ret (0usize, NoProgress)
    }
    ret (count, ok)
}

fn write_all_detail(w: *DetailWriter, src: []const u8, detail: *os.ErrorDetail) -> (usize, err) {
    var written = 0usize
    while written < src.len {
        let (count, write_error) = write_detail(w, src[written..], detail)
        written += count
        if write_error != ok { ret (written, write_error) }
    }
    ret (written, ok)
}

fn write_all(w: *Writer, src: []const u8) -> err {
    let (written, write_error) = write_all_progress(w, src)
    ret write_error
}

fn flush(w: *Writer) -> err {
    ret w.flush(w.ctx)
}

fn flush_detail(w: *DetailWriter, detail: *os.ErrorDetail) -> err {
    ret w.flush(w.ctx, detail)
}

fn seek(s: *Seeker, off: i64, whence: os.SeekWhence) -> (u64, err) {
    let (position, seek_error) = s.seek(s.ctx, off, whence)
    ret (position, seek_error)
}

// `limit` is a hard maximum: crossing it is `TooSmall` and keeps no partial result,
// which is why the claim is released before returning.
fn read_all(a: *mem.Arena, r: *Reader, limit: usize) -> ([]u8, err) {
    let start = mem.mark(a)
    var filled = 0usize
    var reserved = 0usize
    while true {
        if filled == reserved {
            var grow = reserved
            if grow == 0usize { grow = 512usize }
            if reserved + grow > limit { grow = limit - reserved }
            if grow == 0usize {
                mem.reset(a, start)
                ret (zero, TooSmall)
            }
            let (extra, extra_error) = mem.alloc[u8](a, grow)
            if extra_error != ok {
                mem.reset(a, start)
                ret (zero, extra_error)
            }
            reserved += extra.len
        }
        let window = mem.view(a, start + filled, reserved - filled)
        let (count, read_error) = read(r, window)
        if read_error == End { break }
        if read_error != ok {
            mem.reset(a, start)
            ret (zero, read_error)
        }
        filled += count
    }
    mem.reset(a, start + filled)
    ret (mem.view(a, start, filled), ok)
}

// One byte at a time, because a `Reader` cannot give back what it has already handed
// over and the delimiter is only known once it arrives.
fn read_until(a: *mem.Arena, r: *Reader, delimiter: u8, limit: usize) -> ([]u8, err) {
    let start = mem.mark(a)
    var filled = 0usize
    while true {
        if filled == limit {
            mem.reset(a, start)
            ret (zero, TooSmall)
        }
        let (claim, claim_error) = mem.alloc[u8](a, 1usize)
        if claim_error != ok {
            mem.reset(a, start)
            ret (zero, claim_error)
        }
        let (count, read_error) = read(r, claim)
        if read_error == End { break }
        if read_error != ok {
            mem.reset(a, start)
            ret (zero, read_error)
        }
        filled += count
        if claim[0usize] == delimiter { break }
    }
    mem.reset(a, start + filled)
    ret (mem.view(a, start, filled), ok)
}

fn copy(dst: *Writer, src: *Reader, scratch: []u8) -> (u64, err) {
    if scratch.len == 0usize { ret (0u64, TooSmall) }
    var moved = 0u64
    while true {
        let (count, read_error) = read(src, scratch)
        if read_error == End { ret (moved, ok) }
        if read_error != ok { ret (moved, read_error) }
        let write_error = write_all(dst, scratch[0usize..count])
        if write_error != ok { ret (moved, write_error) }
        moved += u64(count)
    }
    ret (moved, ok)
}

fn buffered_read(ctx: *void, dst: []u8) -> (usize, err) {
    var state = mem.cast[*BufferState](ctx)
    if state.off == state.len {
        state.off = 0usize
        state.len = 0usize
        let (count, read_error) = read(&state.source, state.buffer)
        if read_error != ok { ret (0usize, read_error) }
        state.len = count
    }
    var take = state.len - state.off
    if take > dst.len { take = dst.len }
    var at = 0usize
    while at < take {
        dst[at] = state.buffer[state.off + at]
        at += 1usize
    }
    state.off += take
    ret (take, ok)
}

fn buffered_write(ctx: *void, src: []const u8) -> (usize, err) {
    var state = mem.cast[*BufferState](ctx)
    if state.len == state.buffer.len {
        let flush_error = buffered_writer_flush(ctx)
        if flush_error != ok { ret (0usize, flush_error) }
    }
    var take = state.buffer.len - state.len
    if take > src.len { take = src.len }
    var at = 0usize
    while at < take {
        state.buffer[state.len + at] = src[at]
        at += 1usize
    }
    state.len += take
    ret (take, ok)
}

// Buffered bytes go before the wrapped sink's own flush, so what the sink is asked to
// flush is everything written to the adapter and not merely what reached it early.
fn buffered_writer_flush(ctx: *void) -> err {
    var state = mem.cast[*BufferState](ctx)
    if state.len > 0usize {
        let (written, write_error) = write_all_progress(&state.sink, state.buffer[0usize..state.len])
        if written > 0usize {
            var at = written
            while at < state.len {
                state.buffer[at - written] = state.buffer[at]
                at += 1usize
            }
            state.len -= written
        }
        if write_error != ok { ret write_error }
        state.len = 0usize
    }
    ret flush(&state.sink)
}

fn buffered_reader(a: *mem.Arena, source: Reader, capacity: usize) -> (BufferedReader, err) {
    var handle: BufferedReader = zero
    if capacity == 0usize { ret (handle, TooSmall) }
    let (state, state_error) = mem.alloc[BufferState](a, 1usize)
    if state_error != ok { ret (handle, state_error) }
    let (buffer, buffer_error) = mem.alloc[u8](a, capacity)
    if buffer_error != ok { ret (handle, buffer_error) }
    state[0usize].source = source
    state[0usize].buffer = buffer
    state[0usize].off = 0usize
    state[0usize].len = 0usize
    handle.state = mem.cast[*void](&state[0usize])
    ret (handle, ok)
}

fn buffered_writer(a: *mem.Arena, sink: Writer, capacity: usize) -> (BufferedWriter, err) {
    var handle: BufferedWriter = zero
    if capacity == 0usize { ret (handle, TooSmall) }
    let (state, state_error) = mem.alloc[BufferState](a, 1usize)
    if state_error != ok { ret (handle, state_error) }
    let (buffer, buffer_error) = mem.alloc[u8](a, capacity)
    if buffer_error != ok { ret (handle, buffer_error) }
    state[0usize].sink = sink
    state[0usize].buffer = buffer
    state[0usize].off = 0usize
    state[0usize].len = 0usize
    handle.state = mem.cast[*void](&state[0usize])
    ret (handle, ok)
}

fn buffered_source(buffer: *BufferedReader) -> Reader {
    ret Reader { ctx: buffer.state, read: buffered_read }
}

fn buffered_sink(buffer: *BufferedWriter) -> Writer {
    ret Writer { ctx: buffer.state, write: buffered_write, flush: buffered_writer_flush }
}

fn print(s: str) -> err {
    var output = os.stdout()
    var writer_value = file_writer(&output)
    ret write_all(&writer_value, s)
}
