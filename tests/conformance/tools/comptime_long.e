// Four constants of eight hundred thousand iterations each (D496, H16): some six
// seconds of interpretation, so a build under `--deadline 50` that cancels inside
// the evaluation ends in milliseconds, and one that could only stop between phases
// would end after the sixth second. Never built to the end by the suites.
fn sum_to(n: i64) -> i64 {
    var total = 0i64
    var i = 0i64
    while i < n {
        total = total + i
        i = i + 1i64
    }
    ret total
}

const A: i64 = sum_to(800000i64)
const B: i64 = sum_to(800000i64)
const C: i64 = sum_to(800000i64)
const D: i64 = sum_to(800000i64)

fn main() -> i32 {
    if A + B + C + D != 4i64 * 319999600000i64 { ret 1i32 }
    ret 0i32
}
