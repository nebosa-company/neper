use e.io
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    try io.printf["{}"](a, 1i64)
    ret ok
}
