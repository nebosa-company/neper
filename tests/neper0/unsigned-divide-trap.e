use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    let divisor = 0usize
    let invalid = 1usize / divisor
    try io.print("unreachable\n")
    ret ok
}
