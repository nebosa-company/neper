use e.algo.search
use e.mem
use e.os

fn main(a: *mem.Arena) -> err {
    var values: [2]i64 = zero
    values[0usize] = 0i64 - 9223372036854775807i64 - 1i64
    values[1usize] = 9223372036854775807i64
    let (at, found) = search.interpolation(values[..], 0i64)
    if found || at != 1usize { os.exit(3i32) }
    ret ok
}
