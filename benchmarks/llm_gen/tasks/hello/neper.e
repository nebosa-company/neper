use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    try io.print("hello\n")
    ret ok
}
