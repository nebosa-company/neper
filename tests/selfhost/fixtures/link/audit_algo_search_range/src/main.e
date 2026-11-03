use e.algo.search
use e.mem

type Ctx = struct {}

fn score(ctx: *Ctx, x: i64) -> i64 { ret 0i64 }

fn main(a: *mem.Arena) -> err {
    var ctx: Ctx = zero
    let lo = 0i64 - 9223372036854775807i64 - 1i64
    let hi = 9223372036854775807i64
    let _ = search.ternary_max(lo, hi, &ctx, score)
    ret ok
}
