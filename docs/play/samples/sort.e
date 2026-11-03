// e.algo.sort sorts in place; the comparison is a function you pass, checked at compile time.

use e.algo.sort
use e.io
use e.mem

type Count = struct { calls: i64 }

fn descending(ctx: *Count, a: i32, b: i32) -> i32 {
    ctx.calls += 1i64
    if a > b { ret 0i32 - 1i32 }
    if a < b { ret 1i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var xs = [_]i32{ 5i32, 3i32, 9i32, 1i32, 7i32, 2i32 }
    sort.in_place[i32](xs[0..])
    for i in 0usize..xs.len { try io.printf["{} "](xs[i]) }
    try io.print("\n")

    var count = Count{ calls: 0i64 }
    sort.in_place_by[i32, Count](xs[0..], &count, descending)
    for i in 0usize..xs.len { try io.printf["{} "](xs[i]) }
    try io.printf["\ncomparisons: {}\n"](count.calls)
    ret ok
}
