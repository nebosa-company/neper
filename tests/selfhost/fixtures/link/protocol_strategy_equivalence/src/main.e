// Compare implicit dispatch with an explicit function-typed strategy on every pair
// in one finite domain. A second strategy proves the function identity is behavior,
// not merely another spelling of the implicit call.

use ordering

error Failed

fn implicit[T: type](a: T, b: T) -> i32 { ret T.cmp(a, b) }

fn explicit[T: type, F: fn(T, T) -> i32](a: T, b: T) -> i32 {
    ret F(a, b)
}

fn main() -> err {
    var values: [4]ordering.Item = zero
    values[0usize] = ordering.Item { key: 2i64, payload: 90i64 }
    values[1usize] = ordering.Item { key: 1i64, payload: 70i64 }
    values[2usize] = ordering.Item { key: 2i64, payload: 10i64 }
    values[3usize] = ordering.Item { key: 4i64, payload: 30i64 }
    var a = 0usize
    while a < values.len {
        var b = 0usize
        while b < values.len {
            let selected = implicit[ordering.Item](values[a], values[b])
            if explicit[ordering.Item, ordering.item_cmp](values[a], values[b]) != selected { ret Failed }
            if explicit[ordering.Item, ordering.reverse_cmp](values[a], values[b]) != 0i32 - selected { ret Failed }
            b += 1usize
        }
        a += 1usize
    }
    ret ok
}
