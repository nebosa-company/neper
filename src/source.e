// Arena-backed source loading for the self-hosted compiler.

use e.mem
use e.os

// A file longer than the size its end was at when the read began.
error Grew

fn load(a: *mem.Arena, path: str) -> (str, err) {
    let flags = os.OpenFlags{ read: true, write: false, create: false, truncate: false, append: false }
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret ("", open_error) }
    // The file's size from a seek to its end (D324), so the buffer is one allocation of
    // that size: growing from four kibibytes by doubling allocated and copied twice
    // the file, which a worker's arena has no room for. What cannot seek -- a pipe --
    // is read the growing way.
    // The file is this function's to close (D345): the readers borrow it, and the
    // close's own error stands only where the read succeeded.
    var text = ""
    var read_error = ok
    var sized = false
    let (size, size_error) = os.seek(file, 0i64, .End)
    if size_error == ok {
        let (start, start_error) = os.seek(file, 0i64, .Start)
        if start_error == ok {
            let (sized_text, sized_error) = read_sized(a, file, usize(size))
            text = sized_text
            read_error = sized_error
            sized = true
        }
    }
    if !sized {
        let (all_text, all_error) = read_all(a, file)
        text = all_text
        read_error = all_error
    }
    let close_error = os.close(file)
    if read_error != ok { ret ("", read_error) }
    if close_error != ok { ret ("", close_error) }
    ret (text, ok)
}

// The first `limit` bytes of a file and its whole size (D370, H18): what `run --json`
// holds of a child's output, which is bounded by the harness and not by the child.
fn load_prefix(a: *mem.Arena, path: str, limit: usize) -> (str, usize, err) {
    let flags = os.OpenFlags{ read: true, write: false, create: false, truncate: false, append: false }
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret ("", 0usize, open_error) }
    var text = ""
    var total = 0usize
    var read_error = ok
    let (size, size_error) = os.seek(file, 0i64, .End)
    if size_error == ok {
        total = usize(size)
        let (start, start_error) = os.seek(file, 0i64, .Start)
        read_error = start_error
        if start_error == ok {
            var wanted = total
            if wanted > limit { wanted = limit }
            let (buffer, allocation_error) = mem.alloc[u8](a, wanted)
            read_error = allocation_error
            var used = 0usize
            while read_error == ok && used < wanted {
                let (count, chunk_error) = os.read(file, buffer[used..wanted])
                read_error = chunk_error
                if count == 0usize { break }
                used += count
            }
            if read_error == ok { text = buffer[..used] }
        }
    } else {
        read_error = size_error
    }
    let close_error = os.close(file)
    if read_error != ok { ret ("", 0usize, read_error) }
    if close_error != ok { ret ("", 0usize, close_error) }
    ret (text, total, ok)
}

fn read_sized(a: *mem.Arena, file: os.File, size: usize) -> (str, err) {
    let (buffer, allocation_error) = mem.alloc[u8](a, size + 1usize)
    if allocation_error != ok { ret ("", allocation_error) }
    var used = 0usize
    while used < size {
        let (count, read_error) = os.read(file, buffer[used..size])
        if read_error != ok { ret ("", read_error) }
        if count == 0usize { break }
        used += count
    }
    // A file that grew past its size as it was read is read to its new end.
    let (extra, extra_error) = os.read(file, buffer[used..size + 1usize])
    if extra_error != ok { ret ("", extra_error) }
    if extra != 0usize { ret ("", Grew) }
    ret (buffer[..used], ok)
}

// The whole of standard input, for a `-` operand (D289). The handle is not closed.
fn load_stdin(a: *mem.Arena) -> (str, err) {
    var capacity = 4096usize
    let (initial, allocation_error) = mem.alloc[u8](a, capacity)
    if allocation_error != ok { ret ("", allocation_error) }
    var buffer = initial
    var used = 0usize
    let file = os.stdin()
    while true {
        if used == capacity {
            capacity = capacity + capacity
            let (grown, grow_error) = mem.alloc[u8](a, capacity)
            if grow_error != ok { ret ("", grow_error) }
            var i = 0usize
            while i < used {
                grown[i] = buffer[i]
                i += 1usize
            }
            buffer = grown
        }
        let (count, read_error) = os.read(file, buffer[used..])
        if read_error != ok { ret ("", read_error) }
        if count == 0usize { break }
        used += count
    }
    ret (buffer[..used], ok)
}

// Every byte of an open file, which is closed after.
fn read_all(a: *mem.Arena, file: os.File) -> (str, err) {
    var capacity = 4096usize
    let (initial, allocation_error) = mem.alloc[u8](a, capacity)
    if allocation_error != ok {
        ret ("", allocation_error)
    }
    var buffer = initial
    var used = 0usize
    while true {
        if used == capacity {
            capacity = capacity + capacity
            let (grown, grow_error) = mem.alloc[u8](a, capacity)
            if grow_error != ok {
                ret ("", grow_error)
            }
            var i = 0usize
            while i < used {
                grown[i] = buffer[i]
                i += 1usize
            }
            buffer = grown
        }
        let (count, read_error) = os.read(file, buffer[used..])
        if read_error != ok {
            ret ("", read_error)
        }
        if count == 0usize { break }
        used += count
    }
    ret (buffer[..used], ok)
}

// Whether the file at `path` is exactly `bytes` (D332): the size from a seek to its
// end, the way `load` sizes its buffer, and only when that matches the bytes a chunk
// at a time, stopping at the first that differs. A file that cannot be opened, cannot
// seek, or reads short is not a match -- the caller writes, as it did before.
fn matches(a: *mem.Arena, path: str, bytes: []const u8) -> bool {
    let flags = os.OpenFlags{ read: true, write: false, create: false, truncate: false, append: false }
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret false }
    var equal = false
    let (size, size_error) = os.seek(file, 0i64, .End)
    if size_error == ok && usize(size) == bytes.len {
        let (start, start_error) = os.seek(file, 0i64, .Start)
        if start_error == ok { equal = same_bytes(a, file, bytes) }
    }
    let close_error = os.close(file)
    if close_error != ok { ret false }
    ret equal
}

fn same_bytes(a: *mem.Arena, file: os.File, bytes: []const u8) -> bool {
    let checkpoint = mem.mark(a)
    let (chunk, chunk_error) = mem.alloc[u8](a, 65536usize)
    if chunk_error != ok { ret false }
    var at = 0usize
    var equal = true
    while equal && at < bytes.len {
        var wanted = bytes.len - at
        if wanted > chunk.len { wanted = chunk.len }
        let (count, read_error) = os.read(file, chunk[0usize..wanted])
        if read_error != ok || count == 0usize {
            equal = false
        } else {
            var i = 0usize
            while i < count {
                if chunk[i] != bytes[at + i] { equal = false }
                i += 1usize
            }
            at += count
        }
    }
    mem.reset(a, checkpoint)
    ret equal
}
