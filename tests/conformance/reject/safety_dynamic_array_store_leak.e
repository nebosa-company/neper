use e.mem
use e.os

// A resource stored in one runtime-selected slot remains an exit obligation.
fn main(a: *mem.Arena, args: []str) -> err {
    var files: [2]os.File = zero
    let i = args.len % 2usize
    files[i] = try os.dup(os.stdout())
    ret ok
}
