// Asks for 16 GiB and writes to 1,000 places in it. Only those pages cost RAM.
use e.io
use e.mem
use e.os

const MIB: usize = 1048576usize
const SIZE: usize = 17179869184usize
const WRITES: usize = 1000usize

fn main(a: *mem.Arena, args: []str) -> err {
    let (table, table_error) = mem.alloc[u8](a, SIZE)
    if table_error != ok { ret table_error }
    var n = 0usize
    while n < WRITES {
        table[n * (SIZE / WRITES)] = 1u8
        n += 1usize
    }
    let (peak, peak_error) = os.peak_memory()
    if peak_error != ok { ret peak_error }
    try io.printf["allocated {} MiB, wrote {} places, peak RAM {} MiB\n"](mem.stats(a).used / MIB, WRITES, peak / MIB)
    ret ok
}
