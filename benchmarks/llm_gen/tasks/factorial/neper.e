use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    var f = 1i64
    for i in 1i64..11i64 { f = f * i }
    try io.printf["{}\n"](f)
    ret ok
}
