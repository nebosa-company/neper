use e.io
use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    var total = 0i32
    for i in 1i32..101 { total += i }
    try io.printf["{}\n"](total)
    ret ok
}
