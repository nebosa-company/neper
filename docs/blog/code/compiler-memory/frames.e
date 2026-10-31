// Ten thousand frames, one mebibyte of scratch each. The arena hands the same memory back.
use e.io
use e.mem
use e.os

const MIB: usize = 1048576usize
const PAGE: usize = 4096usize
const FRAMES: usize = 10000usize

fn draw(a: *mem.Arena) -> err {
    let (scratch, scratch_error) = mem.alloc[u8](a, MIB)
    if scratch_error != ok { ret scratch_error }
    var at = 0usize
    while at < MIB {
        scratch[at] = 1u8
        at += PAGE
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let start = mem.mark(a)
    var frame = 0usize
    while frame < FRAMES {
        try draw(a)
        mem.reset(a, start)
        frame += 1usize
    }
    let (peak, peak_error) = os.peak_memory()
    if peak_error != ok { ret peak_error }
    try io.printf["allocated {} MiB in total, used now {} MiB, peak RAM {} MiB\n"](FRAMES, mem.stats(a).used / MIB, peak / MIB)
    ret ok
}
