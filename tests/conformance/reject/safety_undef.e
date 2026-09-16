use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var f: os.File = undef
    ret os.close(f)
}
