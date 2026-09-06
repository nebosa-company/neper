// Spec section 9 rule 4: a tagged union recurses in declaration order, the tag
// before the live payload.

error Failed

// Declaration order sets the tags: Nil = 0, Lit = 1, Name = 2, Row = 3.
type Node = union enum u8 {
    Nil,
    Lit: i64,
    Name: str,
    Row: []i64,
}

fn order[T: type](a: T, b: T) -> i32 {
    ret T.cmp(a, b)
}

fn main() -> err {
    let nil_node: Node = .Nil
    let lit_low = Node{ Lit: 4i64 }
    let lit_high = Node{ Lit: 9i64 }
    let name_a = Node{ Name: "abc" }
    let name_b = Node{ Name: "abd" }

    // The tag decides outright where the two differ.
    if order[Node](nil_node, lit_low) != 0i32 - 1i32 { ret Failed }
    if order[Node](lit_low, nil_node) != 1i32 { ret Failed }
    if order[Node](lit_high, name_a) != 0i32 - 1i32 { ret Failed }
    if order[Node](name_a, lit_high) != 1i32 { ret Failed }

    // A void arm carries nothing, so two of them are equal.
    let other_nil: Node = .Nil
    if order[Node](nil_node, other_nil) != 0i32 { ret Failed }

    // Matching tags fall through to the live payload.
    if order[Node](lit_low, lit_high) != 0i32 - 1i32 { ret Failed }
    if order[Node](lit_high, lit_low) != 1i32 { ret Failed }
    if order[Node](lit_low, lit_low) != 0i32 { ret Failed }
    if order[Node](name_a, name_b) != 0i32 - 1i32 { ret Failed }
    if order[Node](name_b, name_a) != 1i32 { ret Failed }
    if order[Node](name_a, name_a) != 0i32 { ret Failed }

    // A payload that is itself a sequence recurses one level further.
    var backing: [6]i64 = zero
    backing[0usize] = 1i64
    backing[1usize] = 2i64
    backing[2usize] = 3i64
    backing[3usize] = 1i64
    backing[4usize] = 2i64
    backing[5usize] = 7i64
    let row_low = Node{ Row: backing[0usize..3usize] }
    let row_high = Node{ Row: backing[3usize..6usize] }
    if order[Node](row_low, row_high) != 0i32 - 1i32 { ret Failed }
    if order[Node](row_high, row_low) != 1i32 { ret Failed }
    if order[Node](row_low, row_low) != 0i32 { ret Failed }
    if order[Node](name_b, row_low) != 0i32 - 1i32 { ret Failed }

    // And a sequence of tagged unions goes the other way round.
    var nodes: [4]Node = zero
    nodes[0usize] = lit_low
    nodes[1usize] = name_a
    nodes[2usize] = lit_low
    nodes[3usize] = name_b
    let left = nodes[0usize..2usize]
    let right = nodes[2usize..4usize]
    if order[[]Node](left, right) != 0i32 - 1i32 { ret Failed }
    if order[[]Node](right, left) != 1i32 { ret Failed }
    if order[[]Node](left, left) != 0i32 { ret Failed }

    ret ok
}
