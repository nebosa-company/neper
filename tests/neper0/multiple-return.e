use e.mem
use e.io

type Pair = struct {
    left: i64,
    right: i64,
}

fn divmod(value: i64, divisor: i64) -> (i64, i64) {
    ret (value / divisor, value % divisor)
}

fn make_pair(seed: i64) -> (Pair, bool) {
    ret (Pair{ left: seed, right: seed + 1i64 }, true)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (quotient, remainder) = divmod(17i64, 5i64)
    let (pair, found) = make_pair(20i64)
    let (_, discarded_remainder) = divmod(23i64, 7i64)
    var next_quotient = 0i64
    var next_remainder = 0i64
    (next_quotient, next_remainder) = divmod(29i64, 6i64)
    if quotient == 3i64 && remainder == 2i64 && pair.left == 20i64 && pair.right == 21i64 && found && discarded_remainder == 2i64 && next_quotient == 4i64 && next_remainder == 5i64 {
        try io.print("multiple return ok\n")
    } else {
        try io.print("multiple return failed\n")
    }
    ret ok
}
