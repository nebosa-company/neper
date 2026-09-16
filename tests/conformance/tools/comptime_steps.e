// A compile-time step budget (D474, H24): `TOTAL` is settled by the interpreter
// running `sum_to` over a hundred iterations, so a `--comptime-steps` budget under
// the steps taken is E-COMPTIME-0002 and exit 1, and one over it builds.
fn sum_to(n: i64) -> i64 {
    var total = 0i64
    var i = 0i64
    while i < n {
        total = total + i
        i = i + 1i64
    }
    ret total
}

const TOTAL: i64 = sum_to(100i64)

fn main() -> i32 {
    if TOTAL != 4950i64 { ret 1i32 }
    ret 0i32
}
