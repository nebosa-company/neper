use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    let s = "benchmark harness"
    var count = 0i32
    for c in s {
        if c == 97u8 || c == 101u8 || c == 105u8 || c == 111u8 || c == 117u8 { count += 1i32 }
    }
    try io.printf["{}\n"](count)
    ret ok
}
