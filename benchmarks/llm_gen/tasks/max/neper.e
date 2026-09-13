use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [_]i32{ 3i32, 9i32, 2i32, 7i32 }
    var best = values[0usize]
    for value in values { if value > best { best = value } }
    try io.printf["{}\n"](best)
    ret ok
}
