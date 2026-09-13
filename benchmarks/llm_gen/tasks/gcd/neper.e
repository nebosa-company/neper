use e.mem
use e.io

fn gcd(x: i32, y: i32) -> i32 {
    var p = x
    var q = y
    while q != 0i32 {
        let r = p % q
        p = q
        q = r
    }
    ret p
}

fn main(a: *mem.Arena, args: []str) -> err {
    try io.printf["{}\n"](gcd(1071i32, 462i32))
    ret ok
}
