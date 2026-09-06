fn choose(flag: bool) -> i64 {
    if flag {
        ret 1i64
    } else {
        ret 2i64
    }
}

fn count() -> i64 {
    var value: i64 = 0i64
    while value < 3i64 {
        value = value + 1i64
    }
    ret value
}

fn main() -> i64 {
    if false && true { ret 1i64 }
    if !(true || false) { ret 2i64 }
    if !(true && (false || true)) { ret 3i64 }
    ret choose(false) - 2i64 + count() - 3i64
}
