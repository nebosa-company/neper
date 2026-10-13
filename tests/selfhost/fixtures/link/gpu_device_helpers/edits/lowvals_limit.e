const OFFSET: u32 = 11u32
const LIMIT: u32 = 41u32

fn bump(x: u32) -> u32 {
    ret x + OFFSET
}

// Control flow in a helper two modules away: an early return and a loop.
fn cap(x: u32) -> u32 {
    if x > LIMIT { ret LIMIT }
    ret x
}

fn sum_to(n: u32) -> u32 {
    var total = 0u32
    var k = 0u32
    while k < n {
        total = total + k
        k = k + 1u32
    }
    ret total
}
