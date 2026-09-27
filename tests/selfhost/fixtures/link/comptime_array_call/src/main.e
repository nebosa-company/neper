// An array across a comptime call (D1569, C066): returned by value from one
// function, passed by value to two more, one of which changes its own copy; the
// constant is settled at compile time, and the caller's array is unchanged.
error Wrong

fn squares() -> [5]u32 {
    var t: [5]u32 = zero
    for i in 0usize..5usize {
        t[i] = u32(i) * u32(i)
    }
    ret t
}

fn total(t: [5]u32) -> u32 {
    var sum = 0u32
    for i in 0usize..t.len {
        sum += t[i]
    }
    ret sum
}

fn bumped(t: [5]u32) -> u32 {
    var copy = t
    copy[0usize] = 100u32
    ret copy[0usize] + t[0usize]
}

fn array_calls() -> u32 {
    let t = squares()
    ret total(t) * 1000u32 + bumped(t)
}

const RESULT = array_calls()

fn main() -> err {
    if RESULT != 30100u32 { ret Wrong }
    ret ok
}
