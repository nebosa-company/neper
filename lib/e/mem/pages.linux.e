// `e.mem.pages` on Linux (D5932). What a program may have is `MemAvailable`, capped by the
// cgroup's room when it runs under one, and `MADV_POPULATE_WRITE` then backs the pages now, so
// that a machine short of memory answers here and not in the OOM killer. Where the kernel is
// older than 5.14 the pages are written one by one.
//
// ponytail: a cgroup is read at its root, which is the process's own inside a container; a
// process in a nested cgroup on a bare host sees the machine's limit. A strict overcommit
// setting is not consulted: the populate is what asks.
use e.mem
use e.os

const SYS_MADVISE: usize = 28usize
const MADV_DONTNEED: usize = 4usize
const MADV_POPULATE_WRITE: usize = 23usize
const ENOMEM: isize = 12isize
const UNLIMITED: usize = 18446744073709551615usize

fn discard(bytes: []u8) -> err {
    if bytes.len == 0usize { ret ok }
    let page = os.page_size()
    let start = (mem.address_of(&bytes[0usize]) + page - 1usize) & ~(page - 1usize)
    let end = (mem.address_of(&bytes[0usize]) + bytes.len) & ~(page - 1usize)
    if end <= start { ret ok }
    let result = os.syscall(SYS_MADVISE, start, end - start, MADV_DONTNEED, 0usize, 0usize, 0usize)
    if result < 0isize { ret os.Unsupported }
    ret ok
}

// The digits at the start of `text`, or `UNLIMITED` when it does not start with one.
fn leading_number(text: str) -> usize {
    if text.len == 0usize || text[0usize] < 48u8 || text[0usize] > 57u8 { ret UNLIMITED }
    var value = 0usize
    var at = 0usize
    while at < text.len && text[at] >= 48u8 && text[at] <= 57u8 {
        value = value * 10usize + usize(text[at] - 48u8)
        at += 1usize
    }
    ret value
}

// The first `buffer.len` bytes of a kernel file, or nothing when it cannot be read.
fn small_file(a: *mem.Arena, path: str, buffer: []u8) -> str {
    var flags: os.OpenFlags = zero
    flags.read = true
    let (f, open_error) = os.open(a, path, flags)
    if open_error != ok { ret "" }
    var filled = 0usize
    while filled < buffer.len {
        let (got, read_error) = os.read(f, buffer[filled..buffer.len])
        if read_error != ok || got == 0usize { break }
        filled += got
    }
    let closed = os.close(f)
    ret buffer[0usize..filled]
}

// The kibibytes after `MemAvailable:` in /proc/meminfo, as bytes.
fn memory_available(text: str) -> usize {
    let label = "MemAvailable:"
    var at = 0usize
    while at + label.len < text.len {
        var same = true
        var offset = 0usize
        while offset < label.len && same {
            same = text[at + offset] == label[offset]
            offset += 1usize
        }
        if same {
            var digits = at + label.len
            while digits < text.len && text[digits] == 32u8 { digits += 1usize }
            let kib = leading_number(text[digits..text.len])
            if kib == UNLIMITED { ret UNLIMITED }
            ret kib * 1024usize
        }
        at += 1usize
    }
    ret UNLIMITED
}

fn available() -> usize {
    var storage: [8192]u8 = zero
    var scratch = mem.arena_from(storage[0usize..1024usize])
    var room = memory_available(small_file(&scratch, "/proc/meminfo", storage[1024usize..8192usize]))
    let limit = leading_number(small_file(&scratch, "/sys/fs/cgroup/memory.max", storage[1024usize..1088usize]))
    if limit != UNLIMITED {
        let used = leading_number(small_file(&scratch, "/sys/fs/cgroup/memory.current", storage[1024usize..1088usize]))
        var left = 0usize
        if used != UNLIMITED && used < limit { left = limit - used }
        if left < room { room = left }
    }
    ret room
}

fn ensure(a: *mem.Arena, n: usize) -> err {
    if n == 0usize { ret ok }
    let s = mem.stats(a)
    if n > s.capacity - s.used { ret mem.Exhausted }
    if n > available() { ret mem.Exhausted }
    let bytes = mem.view(a, s.used, n)
    let page = os.page_size()
    let start = mem.address_of(&bytes[0usize]) & ~(page - 1usize)
    let end = (mem.address_of(&bytes[0usize]) + n + page - 1usize) & ~(page - 1usize)
    let result = os.syscall(SYS_MADVISE, start, end - start, MADV_POPULATE_WRITE, 0usize, 0usize, 0usize)
    if result == 0isize { ret ok }
    if result == 0isize - ENOMEM { ret mem.Exhausted }
    var at = 0usize
    while at < n {
        bytes[at] = 0u8
        at += page
    }
    ret ok
}

fn reserve(capacity: usize) -> ([]u8, err) {
    var size = capacity
    var last: err = ok
    while size >= 1048576usize {
        let (base, reserve_error) = os.reserve(size)
        last = reserve_error
        if reserve_error == ok {
            let commit_error = os.commit(base, size)
            if commit_error != ok { ret (zero, commit_error) }
            var held: mem.Arena = zero
            held.base = base
            held.cap = size
            ret (mem.view(&held, 0usize, size), ok)
        }
        size = size / 2usize
    }
    ret (zero, last)
}

fn release(bytes: []u8) -> err {
    if bytes.len == 0usize { ret ok }
    ret os.release(&bytes[0usize], bytes.len)
}
