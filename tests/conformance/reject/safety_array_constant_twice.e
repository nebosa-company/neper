use e.mem
use e.os

const SLOT: usize = 1usize + 0usize

// Equivalent comptime index expressions cannot name two ownership identities.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    files[SLOT] = try os.dup(os.stdout())
    try os.close(files[SLOT])
    ret os.close(files[2usize - 1usize])
}
