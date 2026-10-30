// `e.mem.pages` on Windows (D5932). A commit is a promise from the system: the pages are charged
// against RAM plus pagefile, and no later touch of them can fail. So `ensure` is stronger here
// than anywhere else, and it is the one honest answer the commit-on-touch handler cannot give
// (D340), since by then the program has already written.
use e.mem
use e.os

const MEM_DECOMMIT: u32 = 16384u32

@import("kernel32.dll", "VirtualFree")
extern fn raw_virtual_free(address: *u8, size: usize, kind: u32) -> i32

fn discard(bytes: []u8) -> err {
    if bytes.len == 0usize { ret ok }
    let page = os.page_size()
    let base = mem.address_of(&bytes[0usize])
    let start = ((base + page - 1usize) & ~(page - 1usize)) - base
    let end = ((base + bytes.len) & ~(page - 1usize)) - base
    if base + end <= base + start { ret ok }
    if raw_virtual_free(&bytes[start], end - start, MEM_DECOMMIT) == 0i32 { ret os.Unsupported }
    ret ok
}

fn ensure(a: *mem.Arena, n: usize) -> err {
    if n == 0usize { ret ok }
    let s = mem.stats(a)
    if n > s.capacity - s.used { ret mem.Exhausted }
    let bytes = mem.view(a, s.used, n)
    if os.commit(&bytes[0usize], n) != ok { ret mem.Exhausted }
    ret ok
}

fn reserve(capacity: usize) -> ([]u8, err) {
    var size = capacity
    var last: err = ok
    while size >= 1048576usize {
        let (base, reserve_error) = os.reserve(size)
        last = reserve_error
        if reserve_error == ok {
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
