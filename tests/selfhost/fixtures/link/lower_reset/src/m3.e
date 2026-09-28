// Six functions over the same literals, the same small function and the same trap
// message as m2's, interned again after m2's rows were rolled back.
use m1

fn other() -> str {
    ret "beta"
}

fn name() -> str {
    ret "alpha"
}

fn bump(x: i64) -> i64 {
    ret m1.step(x)
}

fn share(x: i64, d: i64) -> i64 {
    ret x / d
}

fn size() -> usize {
    ret other().len + name().len
}

fn check() -> i64 {
    if size() != 9usize { ret 1i64 }
    if bump(4i64) != 7i64 { ret 1i64 }
    if share(9i64, 3i64) != 3i64 { ret 1i64 }
    ret 0i64
}
