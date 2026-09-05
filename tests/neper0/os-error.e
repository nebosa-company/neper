use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let flags = os.OpenFlags{ read: true, write: false, create: false, truncate: false, append: false }
    let (_, failure) = os.open(a, args[1usize], flags)
    ret failure
}
