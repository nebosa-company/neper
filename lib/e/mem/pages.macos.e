// `e.mem.pages` on macOS (D5932). A fresh mapping over a range is what lets its pages go, since
// madvise here keeps them counted. The kernel compresses and swaps rather than refuse, so the
// honest limit is the machine's memory: `ensure` answers against that and writes the pages.
//
// ponytail: `ensure` knows the physical memory, not what is free of it; a host_statistics call
// would answer closer, and compression makes any such number a guess.
use e.mem
use e.os

const SYS_MMAP: usize = 197usize
const SYS_SYSCTL: usize = 202usize
const PROT_READ_WRITE: usize = 3usize
const MAP_FIXED_PRIVATE_ANON: usize = 4114usize
const CTL_HW: u32 = 6u32
const HW_MEMSIZE: u32 = 24u32

fn discard(bytes: []u8) -> err {
    if bytes.len == 0usize { ret ok }
    let page = os.page_size()
    let start = (mem.address_of(&bytes[0usize]) + page - 1usize) & ~(page - 1usize)
    let end = (mem.address_of(&bytes[0usize]) + bytes.len) & ~(page - 1usize)
    if end <= start { ret ok }
    let result = os.syscall(SYS_MMAP, start, end - start, PROT_READ_WRITE, MAP_FIXED_PRIVATE_ANON, 18446744073709551615usize, 0usize)
    if result < 0isize { ret os.Unsupported }
    ret ok
}

fn machine_memory() -> usize {
    var name = [2]u32{ CTL_HW, HW_MEMSIZE }
    var size = 0usize
    var length = 8usize
    let result = os.syscall(SYS_SYSCTL, mem.address_of(&name[0usize]), 2usize, mem.address_of(&size), mem.address_of(&length), 0usize, 0usize)
    if result < 0isize { ret 18446744073709551615usize }
    ret size
}

fn ensure(a: *mem.Arena, n: usize) -> err {
    if n == 0usize { ret ok }
    let s = mem.stats(a)
    if n > s.capacity - s.used { ret mem.Exhausted }
    if n > machine_memory() { ret mem.Exhausted }
    let bytes = mem.view(a, s.used, n)
    let page = os.page_size()
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
