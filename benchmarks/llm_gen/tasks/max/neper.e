use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [_]i32{ 3, 9, 2, 7 }
    var best = values[0]
    for value in values { if value > best { best = value } }
    try io.printf["{}\n"](best)
    ret ok
}
