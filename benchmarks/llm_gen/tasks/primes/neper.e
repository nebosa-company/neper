use e.mem
use e.io

fn is_prime(n: i32) -> bool {
    if n < 2i32 { ret false }
    var d = 2i32
    while d * d <= n {
        if n % d == 0i32 { ret false }
        d += 1i32
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var count = 0i32
    for n in 0i32..100i32 { if is_prime(n) { count += 1i32 } }
    try io.printf["{}\n"](count)
    ret ok
}
