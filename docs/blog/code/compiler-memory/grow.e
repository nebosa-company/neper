// Grows past the old 1 GiB default, one block at a time, with no flag.
use e.io
use e.mem
use e.os

const MIB: usize = 1048576usize
const PAGE: usize = 4096usize
const BLOCK: usize = 268435456usize
const BLOCKS: usize = 6usize

fn report(a: *mem.Arena, label: str) -> err {
    let (peak, peak_error) = os.peak_memory()
    if peak_error != ok { ret peak_error }
    let s = mem.stats(a)
    try io.printf["{}: ceiling {} MiB, used {} MiB, peak RAM {} MiB\n"](label, s.capacity / MIB, s.used / MIB, peak / MIB)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    try report(a, "start")
    let (first, first_error) = mem.alloc[u8](a, PAGE)
    if first_error != ok { ret first_error }
    first[0usize] = 42u8
    var grown = 0usize
    while grown < BLOCKS {
        let (block, block_error) = mem.alloc[u8](a, BLOCK)
        if block_error != ok { ret block_error }
        var at = 0usize
        while at < BLOCK {
            block[at] = 1u8
            at += PAGE
        }
        grown += 1usize
        try report(a, "grew")
    }
    // Nothing moved: the first allocation is where it was, with what it held.
    try io.printf["first byte is still {}\n"](first[0usize])
    ret ok
}
