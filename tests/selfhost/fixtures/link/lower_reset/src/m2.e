// Four functions: two string literals, a call of m1's small function, and a trap site.
use m1

fn name() -> str {
    ret "alpha"
}

fn other() -> str {
    ret "beta"
}

fn twice(x: i64, d: i64) -> i64 {
    ret m1.step(m1.step(x)) / d
}

fn check() -> i64 {
    if name().len != 5usize { ret 1i64 }
    if other().len != 4usize { ret 1i64 }
    if twice(3i64, 3i64) != 3i64 { ret 1i64 }
    ret 0i64
}
