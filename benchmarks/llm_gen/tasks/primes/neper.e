use e.mem
use e.io

fn is_prime(n: i32) -> bool {
    if n < 2 { ret false }
    var d = 2i32
    while d * d <= n {
        if n % d == 0 { ret false }
        d += 1
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var count = 0i32
    for n in 0i32..100 { if is_prime(n) { count += 1 } }
    try io.printf["{}\n"](count)
    ret ok
}
