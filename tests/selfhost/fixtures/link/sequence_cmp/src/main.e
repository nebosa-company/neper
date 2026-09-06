// Spec section 9 rule 4: arrays, slices and `str` recurse in index order, and
// where the common prefix matches the shorter sequence orders first.

error Failed

type Level = enum u8 {
    None = 0u8,
    Low = 1u8,
    High = 9u8,
}

fn order[T: type](a: T, b: T) -> i32 {
    ret T.cmp(a, b)
}

fn main() -> err {
    var storage: [6]i64 = zero
    storage[0usize] = 1i64
    storage[1usize] = 2i64
    storage[2usize] = 3i64
    storage[3usize] = 1i64
    storage[4usize] = 2i64
    storage[5usize] = 4i64
    let left = storage[0usize..3usize]
    let right = storage[3usize..6usize]
    // Common prefix 1,2; the third element decides.
    if order[[]i64](left, right) != 0i32 - 1i32 { ret Failed }
    if order[[]i64](right, left) != 1i32 { ret Failed }
    if order[[]i64](left, left) != 0i32 { ret Failed }
    // A prefix orders before what extends it.
    let short = storage[0usize..2usize]
    if order[[]i64](short, left) != 0i32 - 1i32 { ret Failed }
    if order[[]i64](left, short) != 1i32 { ret Failed }
    let empty = storage[0usize..0usize]
    if order[[]i64](empty, short) != 0i32 - 1i32 { ret Failed }
    if order[[]i64](empty, empty) != 0i32 { ret Failed }

    var bytes: [4]u8 = zero
    bytes[0usize] = 200u8
    bytes[1usize] = 1u8
    bytes[2usize] = 3u8
    bytes[3usize] = 1u8
    let high = bytes[0usize..2usize]
    let low = bytes[2usize..4usize]
    // 200 above 3 requires an unsigned element comparison.
    if order[[]u8](high, low) != 1i32 { ret Failed }
    if order[[]u8](low, high) != 0i32 - 1i32 { ret Failed }

    var levels: [4]Level = zero
    levels[0usize] = Level.Low
    levels[1usize] = Level.High
    levels[2usize] = Level.Low
    levels[3usize] = Level.Low
    let ascending = levels[0usize..2usize]
    let flat = levels[2usize..4usize]
    if order[[]Level](flat, ascending) != 0i32 - 1i32 { ret Failed }
    if order[[]Level](ascending, flat) != 1i32 { ret Failed }

    var fixed_a: [3]i32 = zero
    var fixed_b: [3]i32 = zero
    fixed_a[0usize] = 5i32
    fixed_a[1usize] = 7i32
    fixed_a[2usize] = 9i32
    fixed_b[0usize] = 5i32
    fixed_b[1usize] = 7i32
    fixed_b[2usize] = 9i32
    if order[[3]i32](fixed_a, fixed_b) != 0i32 { ret Failed }
    fixed_b[2usize] = 10i32
    if order[[3]i32](fixed_a, fixed_b) != 0i32 - 1i32 { ret Failed }
    if order[[3]i32](fixed_b, fixed_a) != 1i32 { ret Failed }

    if order[str]("abc", "abd") != 0i32 - 1i32 { ret Failed }
    if order[str]("abd", "abc") != 1i32 { ret Failed }
    if order[str]("ab", "abc") != 0i32 - 1i32 { ret Failed }
    if order[str]("abc", "abc") != 0i32 { ret Failed }

    // Nesting: the element comparison is the same emitter one level down.
    var grid_a: [2][3]i32 = zero
    var grid_b: [2][3]i32 = zero
    grid_a[1usize][2usize] = 4i32
    grid_b[1usize][2usize] = 4i32
    if order[[2][3]i32](grid_a, grid_b) != 0i32 { ret Failed }
    grid_b[1usize][2usize] = 5i32
    if order[[2][3]i32](grid_a, grid_b) != 0i32 - 1i32 { ret Failed }
    if order[[2][3]i32](grid_b, grid_a) != 1i32 { ret Failed }
    grid_b[1usize][2usize] = 4i32
    grid_b[0usize][0usize] = 0i32 - 1i32
    if order[[2][3]i32](grid_b, grid_a) != 0i32 - 1i32 { ret Failed }

    var rows_a: [2][]i64 = zero
    var rows_b: [2][]i64 = zero
    rows_a[0usize] = storage[0usize..2usize]
    rows_a[1usize] = storage[0usize..3usize]
    rows_b[0usize] = storage[0usize..2usize]
    rows_b[1usize] = storage[3usize..6usize]
    // Rows differ only at the third element of the second row: 3 against 4.
    if order[[2][]i64](rows_a, rows_b) != 0i32 - 1i32 { ret Failed }
    if order[[2][]i64](rows_b, rows_a) != 1i32 { ret Failed }
    if order[[2][]i64](rows_a, rows_a) != 0i32 { ret Failed }
    rows_b[1usize] = storage[0usize..2usize]
    // Now the second row of rows_b is a proper prefix of rows_a's.
    if order[[2][]i64](rows_b, rows_a) != 0i32 - 1i32 { ret Failed }

    ret ok
}
