use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    var total = 0i32
    for i in 1i32..101i32 { total += i }
    try io.printf["{}\n"](total)
    ret ok
}
