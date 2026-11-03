use e.mem
use e.io

// main has one signature (spec §13): the root arena and the arguments arrive as
// parameters. ok exits 0; any other err prints "error: <module>.<Name>" and exits 1.
fn main(a: *mem.Arena, args: []str) -> err {
    try io.print("hello, neper\n")
    ret ok
}
