use ops

error Failed

type Order = struct { cmp: fn(i64, i64) -> i32, tag: i64 }

fn add(a: i64, b: i64) -> i64 { ret a + b }
fn sub(a: i64, b: i64) -> i64 { ret a - b }

fn apply(f: fn(i64, i64) -> i64, a: i64, b: i64) -> i64 { ret f(a, b) }

fn compare_with(o: *const Order, a: i64, b: i64) -> i32 {
    let f = o.cmp
    ret f(a, b)
}

fn main() -> err {
    // A function passed as an argument and called through the parameter.
    if apply(add, 2i64, 3i64) != 5i64 { ret Failed }
    if apply(sub, 9i64, 4i64) != 5i64 { ret Failed }

    // A function value held in a mutable binding, then replaced.
    var chosen = add
    if chosen(10i64, 1i64) != 11i64 { ret Failed }
    chosen = sub
    if chosen(10i64, 1i64) != 9i64 { ret Failed }

    // A function value in a struct field, from another module.
    let up = Order { cmp: ops.ascending, tag: 1i64 }
    let down = Order { cmp: ops.descending, tag: 2i64 }
    if compare_with(&up, 1i64, 2i64) != 0i32 - 1i32 { ret Failed }
    if compare_with(&up, 2i64, 1i64) != 1i32 { ret Failed }
    if compare_with(&up, 2i64, 2i64) != 0i32 { ret Failed }
    if compare_with(&down, 1i64, 2i64) != 1i32 { ret Failed }
    if compare_with(&down, 2i64, 1i64) != 0i32 - 1i32 { ret Failed }
    ret ok
}
