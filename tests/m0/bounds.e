use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    try io.print(args[99])
    ret ok
}
