// A `const` whose call never returns is stopped at the step budget (D218).
const FOREVER = spin(1i64)

fn spin(x: i64) -> i64 {
    var n = x
    while n > 0i64 { n += 1i64 }
    ret n
}

fn main() {}
