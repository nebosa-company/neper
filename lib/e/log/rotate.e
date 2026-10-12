// A size-rotated file sink, the policy of Python's `RotatingFileHandler`: records are appended
// to `path`; when the next write would bring the file to `max_bytes` or more, the file is
// rotated first. Rotation shifts `path.N-1` to `path.N` for N from `keep` down to 2, moves
// `path` to `path.1` and starts a fresh `path`; the oldest backup (`path.keep`) is dropped.
// With `keep == 0` the file is simply truncated. A single record larger than `max_bytes` is
// written whole into a freshly rotated file. `max_bytes == 0` never rotates.
//
// `writer` adapts a `Rotator` to an `io.Writer` so it can sit under `log.jsonl_sink`; each
// `write` is one record (the caller supplies the newline). The rotator opens the file in
// append mode, so an existing log continues and its size is counted from disk.

use e.io
use e.mem
use e.os

type Rotator = struct { arena: *mem.Arena, path: str, max_bytes: u64, keep: u32, file: os.File, size: u64, is_open: bool }
error Closed

fn backup_name(a: *mem.Arena, path: str, index: u32) -> (str, err) {
    let (buf, alloc_error) = mem.alloc[u8](a, path.len + 12usize)
    if alloc_error != ok { ret ("", alloc_error) }
    var n = 0usize
    while n < path.len {
        buf[n] = path[n]
        n += 1usize
    }
    buf[n] = 46u8
    n += 1usize
    var digits: [10]u8 = zero
    var count = 0usize
    var v = index
    if v == 0u32 {
        digits[0usize] = 48u8
        count = 1usize
    }
    while v > 0u32 {
        digits[count] = u8(48u32 + v % 10u32)
        count += 1usize
        v = v / 10u32
    }
    while count > 0usize {
        count -= 1usize
        buf[n] = digits[count]
        n += 1usize
    }
    ret (buf[0usize..n], ok)
}

fn open_current(r: *Rotator, truncate: bool) -> err {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.append = !truncate
    flags.truncate = truncate
    let (f, open_error) = os.open(r.arena, r.path, flags)
    if open_error != ok { ret open_error }
    r.file = f
    r.is_open = true
    r.size = 0u64
    if !truncate {
        let (info, stat_error) = os.stat(r.arena, r.path)
        if stat_error == ok { r.size = info.size }
    }
    ret ok
}

fn open(a: *mem.Arena, path: str, max_bytes: u64, keep: u32) -> (Rotator, err) {
    var r: Rotator = zero
    r.arena = a
    r.path = path
    r.max_bytes = max_bytes
    r.keep = keep
    let open_error = open_current(&r, false)
    if open_error != ok { ret (r, open_error) }
    ret (r, ok)
}

fn close(r: *Rotator) -> err {
    if !r.is_open { ret ok }
    r.is_open = false
    ret os.close(r.file)
}

// Removes `name` if it exists; a missing file is not an error.
fn remove_if_present(a: *mem.Arena, name: str) -> err {
    let (info, stat_error) = os.stat(a, name)
    if stat_error != ok { ret ok }
    ret os.remove_file(a, name)
}

fn rotate(r: *Rotator) -> err {
    if r.is_open {
        let closed = os.close(r.file)
        r.is_open = false
        if closed != ok { ret closed }
    }
    if r.keep == 0u32 {
        ret open_current(r, true)
    }
    let mark = mem.mark(r.arena)
    var i = r.keep
    while i >= 1u32 {
        let (dst, dst_error) = backup_name(r.arena, r.path, i)
        if dst_error != ok {
            mem.reset(r.arena, mark)
            ret dst_error
        }
        var src = r.path
        if i > 1u32 {
            let (older, older_error) = backup_name(r.arena, r.path, i - 1u32)
            if older_error != ok {
                mem.reset(r.arena, mark)
                ret older_error
            }
            src = older
        }
        let (info, stat_error) = os.stat(r.arena, src)
        if stat_error == ok {
            let removed = remove_if_present(r.arena, dst)
            if removed != ok {
                mem.reset(r.arena, mark)
                ret removed
            }
            let moved = os.rename(r.arena, src, dst)
            if moved != ok {
                mem.reset(r.arena, mark)
                ret moved
            }
        }
        i -= 1u32
    }
    mem.reset(r.arena, mark)
    ret open_current(r, true)
}

// One record. Rotates first when `size + len >= max_bytes` (and there is something to rotate).
fn write(r: *Rotator, record: []const u8) -> err {
    if !r.is_open { ret Closed }
    if r.max_bytes > 0u64 && r.size > 0u64 && r.size + u64(record.len) >= r.max_bytes {
        try rotate(r)
    }
    var sent = 0usize
    while sent < record.len {
        let (count, write_error) = os.write(r.file, record[sent..record.len])
        if write_error != ok { ret write_error }
        if count == 0usize { ret io.NoProgress }
        sent += count
    }
    r.size += u64(record.len)
    ret ok
}

fn writer_write(ctx: *void, src: []const u8) -> (usize, err) {
    let r = mem.cast[*Rotator](ctx)
    let written = write(r, src)
    if written != ok { ret (0usize, written) }
    ret (src.len, ok)
}

fn writer_flush(ctx: *void) -> err { ret ok }

fn writer(r: *Rotator) -> io.Writer {
    ret io.writer_with_flush(mem.cast[*void](r), writer_write, writer_flush)
}
