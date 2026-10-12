use e.io
use e.mem

fn fib(n: i32) -> i32 {
    if n < 2 { ret n }
    ret fib(n - 1) + fib(n - 2)
}

fn main(a: *mem.Arena, args: []str) -> err {
    try io.printf["{}\n"](fib(20))
    ret ok
}
