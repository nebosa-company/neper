// A 2 GiB spike and a reset: the memory goes back with nothing asked for.
use e.io
use e.mem
use e.proc.sys

const MIB: usize = 1048576usize
const PAGE: usize = 4096usize

fn resident() -> u64 {
    var storage: [16384]u8 = zero
    var scratch = mem.arena_from(storage[..])
    let (bytes, memory_error) = sys.self_memory(&scratch)
    if memory_error != ok { ret 0u64 }
    ret bytes / 1048576u64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let start = mem.mark(a)
    let (block, block_error) = mem.alloc[u8](a, 2048usize * MIB)
    if block_error != ok { ret block_error }
    var at = 0usize
    while at < block.len {
        block[at] = 1u8
        at += PAGE
    }
    try io.printf["after the spike: {} MiB in RAM\n"](resident())
    mem.reset(a, start)
    try io.printf["after mem.reset: {} MiB in RAM\n"](resident())
    ret ok
}
