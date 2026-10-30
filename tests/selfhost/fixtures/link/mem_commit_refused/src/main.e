// (D5934) Run on Windows under a job that limits the process's commit, which the suite does.
// `pages.ensure` answers `mem.Exhausted` while the program can still act on it, and a program
// that writes on regardless dies saying it is out of memory, with 137, after asking for two
// seconds: not as an access violation, which is what a refused commit used to be called.
use e.io
use e.mem
use e.mem.pages

const MIB: usize = 1048576usize

error NoLimitInForce

fn main(a: *mem.Arena, args: []str) -> err {
    if pages.ensure(a, 512usize * MIB) != mem.Exhausted { ret NoLimitInForce }
    try io.printf["refused in time\n"]()
    let (block, block_error) = mem.alloc[u8](a, 512usize * MIB)
    if block_error != ok { ret block_error }
    var at = 0usize
    while at < block.len {
        block[at] = 1u8
        at += 4096usize
    }
    ret ok
}
