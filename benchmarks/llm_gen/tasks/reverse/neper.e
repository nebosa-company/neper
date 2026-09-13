use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    let s = "neper"
    var out: [5]u8 = zero
    for i in 0usize..s.len { out[i] = s[s.len - 1usize - i] }
    try io.print(out[..])
    try io.print("\n")
    ret ok
}
