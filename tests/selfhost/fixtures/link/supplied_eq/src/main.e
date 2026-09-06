// Spec section 9 rule 4 supplies `eq` for the same shapes as `cmp` and adds
// pointers. A slice compares over its contents, a tagged union by tag then live
// payload, and a component with its own `fn <t>_eq` by calling it.

use shapes

error Failed

type Level = enum u8 {
    None = 0u8,
    Low = 1u8,
    High = 9u8,
}

type Node = union enum u8 {
    Nil,
    Lit: i64,
    Name: str,
    Row: []i64,
}

fn same[T: type](a: T, b: T) -> bool {
    ret T.eq(a, b)
}

fn main() -> err {
    // Scalars.
    if !same[i64](5i64, 5i64) { ret Failed }
    if same[i64](5i64, 6i64) { ret Failed }
    if !same[bool](true, true) { ret Failed }
    if same[bool](true, false) { ret Failed }
    if !same[Level](Level.High, Level.High) { ret Failed }
    if same[Level](Level.High, Level.Low) { ret Failed }

    // Pointers: rule 4 supplies `eq` here even though it supplies no `cmp`.
    var a = 1i64
    var b = 1i64
    if !same[*i64](&a, &a) { ret Failed }
    if same[*i64](&a, &b) { ret Failed }

    // Slices are equal over their contents, and unequal lengths are unequal.
    var storage: [6]i64 = zero
    storage[0usize] = 1i64
    storage[1usize] = 2i64
    storage[2usize] = 3i64
    storage[3usize] = 1i64
    storage[4usize] = 2i64
    storage[5usize] = 4i64
    if !same[[]i64](storage[0usize..2usize], storage[3usize..5usize]) { ret Failed }
    if same[[]i64](storage[0usize..3usize], storage[3usize..6usize]) { ret Failed }
    if same[[]i64](storage[0usize..2usize], storage[0usize..3usize]) { ret Failed }
    if !same[[]i64](storage[0usize..0usize], storage[3usize..3usize]) { ret Failed }

    // str is a slice like any other.
    if !same[str]("abc", "abc") { ret Failed }
    if same[str]("abc", "abd") { ret Failed }
    if same[str]("ab", "abc") { ret Failed }

    // Fixed arrays, and nesting.
    var x: [2][2]i32 = zero
    var y: [2][2]i32 = zero
    x[1usize][1usize] = 7i32
    y[1usize][1usize] = 7i32
    if !same[[2][2]i32](x, y) { ret Failed }
    y[1usize][1usize] = 8i32
    if same[[2][2]i32](x, y) { ret Failed }

    // Tagged unions: tag first, then the live payload; two void arms are equal.
    let nil_a: Node = .Nil
    let nil_b: Node = .Nil
    let lit4 = Node{ Lit: 4i64 }
    let lit9 = Node{ Lit: 9i64 }
    let name = Node{ Name: "abc" }
    if !same[Node](nil_a, nil_b) { ret Failed }
    if same[Node](nil_a, lit4) { ret Failed }
    if !same[Node](lit4, lit4) { ret Failed }
    if same[Node](lit4, lit9) { ret Failed }
    if same[Node](lit4, name) { ret Failed }
    if !same[Node](name, Node{ Name: "abc" }) { ret Failed }
    if same[Node](name, Node{ Name: "abd" }) { ret Failed }
    let row = Node{ Row: storage[0usize..2usize] }
    if !same[Node](row, Node{ Row: storage[3usize..5usize] }) { ret Failed }
    if same[Node](row, Node{ Row: storage[3usize..6usize] }) { ret Failed }

    // A component's own `eq` wins, and this one ignores `tag` deliberately.
    let p = shapes.Pair { key: 1i64, tag: 10i64 }
    let q = shapes.Pair { key: 1i64, tag: 99i64 }
    let r = shapes.Pair { key: 2i64, tag: 10i64 }
    if !same[shapes.Pair](p, q) { ret Failed }
    if same[shapes.Pair](p, r) { ret Failed }

    var pairs: [4]shapes.Pair = zero
    pairs[0usize] = p
    pairs[1usize] = r
    pairs[2usize] = q
    pairs[3usize] = r
    // Elements 0 and 2 differ in `tag` only, so the declared eq calls them equal.
    if !same[[]shapes.Pair](pairs[0usize..2usize], pairs[2usize..4usize]) { ret Failed }
    pairs[3usize] = p
    if same[[]shapes.Pair](pairs[0usize..2usize], pairs[2usize..4usize]) { ret Failed }

    ret ok
}
