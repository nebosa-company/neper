use e.io
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    try io.print("hello\n")
    ret ok
}
