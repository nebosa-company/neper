use e.mem
use e.io

fn fib(n: i32) -> i32 {
    if n < 2i32 { ret n }
    ret fib(n - 1i32) + fib(n - 2i32)
}

fn main(a: *mem.Arena, args: []str) -> err {
    try io.printf["{}\n"](fib(20i32))
    ret ok
}
