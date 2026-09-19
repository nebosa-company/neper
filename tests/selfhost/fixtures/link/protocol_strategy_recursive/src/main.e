// A function-typed strategy forwarded through a recursively specialized generic.
// A comptime `if` removes the recursive arm at N == 0, so the chain is finite and its
// specialization count is a predictable budget boundary.

error Failed

fn increment(value: i64) -> i64 { ret value + 1i64 }
fn decrement(value: i64) -> i64 { ret value - 1i64 }

fn apply_many[N: usize, F: fn(i64) -> i64](value: i64) -> i64 {
    if N == 0usize {
        ret value
    } else {
        ret apply_many[N - 1usize, F](F(value))
    }
}

fn main() -> err {
    if apply_many[32usize, increment](0i64) != 32i64 { ret Failed }
    if apply_many[32usize, decrement](0i64) != 0i64 - 32i64 { ret Failed }
    ret ok
}
