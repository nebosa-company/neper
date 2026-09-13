use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    let s = "benchmark harness"
    var count = 0i32
    for c in s {
        if c == 97 || c == 101 || c == 105 || c == 111 || c == 117 { count += 1 }
    }
    try io.printf["{}\n"](count)
    ret ok
}
