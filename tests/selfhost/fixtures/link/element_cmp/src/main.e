// Spec section 9 rule 4: a sequence recurses into its element, and an element
// whose own module declares `fn <t>_cmp` is compared by calling it.

use shapes

error Failed

fn order[T: type](a: T, b: T) -> i32 {
    ret T.cmp(a, b)
}

fn main() -> err {
    var points: [4]shapes.Point = zero
    points[0usize] = shapes.Point { x: 1i64, y: 0i64 }
    points[1usize] = shapes.Point { x: 2i64, y: 0i64 }
    points[2usize] = shapes.Point { x: 1i64, y: 0i64 }
    points[3usize] = shapes.Point { x: 3i64, y: 0i64 }
    let left = points[0usize..2usize]
    let right = points[2usize..4usize]
    if order[[]shapes.Point](left, right) != 0i32 - 1i32 { ret Failed }
    if order[[]shapes.Point](right, left) != 1i32 { ret Failed }
    if order[[]shapes.Point](left, left) != 0i32 { ret Failed }
    let prefix = points[0usize..1usize]
    if order[[]shapes.Point](prefix, left) != 0i32 - 1i32 { ret Failed }

    var tags: [4]shapes.Tag = zero
    tags[0usize] = shapes.Tag { id: 1i64 }
    tags[1usize] = shapes.Tag { id: 2i64 }
    tags[2usize] = shapes.Tag { id: 1i64 }
    tags[3usize] = shapes.Tag { id: 3i64 }
    let low = tags[0usize..2usize]
    let high = tags[2usize..4usize]
    // tag_cmp reverses, so the sequence with the larger id orders first.
    if order[[]shapes.Tag](low, high) != 1i32 { ret Failed }
    if order[[]shapes.Tag](high, low) != 0i32 - 1i32 { ret Failed }
    if order[[]shapes.Tag](low, low) != 0i32 { ret Failed }

    var fixed_a: [2]shapes.Point = zero
    var fixed_b: [2]shapes.Point = zero
    fixed_a[0usize] = shapes.Point { x: 5i64, y: 0i64 }
    fixed_b[0usize] = shapes.Point { x: 5i64, y: 0i64 }
    fixed_a[1usize] = shapes.Point { x: 6i64, y: 0i64 }
    fixed_b[1usize] = shapes.Point { x: 7i64, y: 0i64 }
    if order[[2]shapes.Point](fixed_a, fixed_b) != 0i32 - 1i32 { ret Failed }
    if order[[2]shapes.Point](fixed_b, fixed_a) != 1i32 { ret Failed }

    var rows_a: [2][]shapes.Point = zero
    var rows_b: [2][]shapes.Point = zero
    rows_a[0usize] = points[0usize..1usize]
    rows_a[1usize] = points[0usize..2usize]
    rows_b[0usize] = points[0usize..1usize]
    rows_b[1usize] = points[2usize..4usize]
    if order[[2][]shapes.Point](rows_a, rows_b) != 0i32 - 1i32 { ret Failed }
    if order[[2][]shapes.Point](rows_b, rows_a) != 1i32 { ret Failed }

    ret ok
}
