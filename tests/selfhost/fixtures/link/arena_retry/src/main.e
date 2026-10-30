// (D5930) A ceiling the host will not reserve is halved until it will. Built with
// `--arena 1048576g`, a pebibyte no 47-bit address space holds, the program still starts,
// with less than it asked for, and allocates; before this it exited 111 ahead of `main`.
// Under `ulimit -v` the same program runs on what that limit leaves.
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    let capacity = mem.stats(a).capacity
    if capacity >= 1125899906842624usize { ret mem.Exhausted }
    if capacity < 1048576usize { ret mem.Exhausted }
    let (block, block_error) = mem.alloc[u8](a, 65536usize)
    if block_error != ok { ret block_error }
    block[65535] = 7u8
    if block[65535] != 7u8 { ret mem.Exhausted }
    ret ok
}
