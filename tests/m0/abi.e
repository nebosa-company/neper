use e.mem
use e.io

fn eighth(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) -> i64 {
    ret h
}

fn echo(s: []const u8) -> err {
    try io.print(s)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    if eighth(1, 2, 3, 4, 5, 6, 7, 8) == 8 {
        try echo("abi ok")
    } else {
        try io.print("abi bad")
    }
    ret ok
}
