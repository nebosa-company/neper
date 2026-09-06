// Spec section 9 rule 4 recurses in index or declaration order. Where a value is
// one contiguous run of canonical bytes it is hashed in a single pass; where it is
// not -- a nested slice is a pointer, a tagged union payload is padded -- one hash
// per component is folded, `acc = H(acc || h)` from zero, using that same pass.

use e.algo.hash

error Failed

type Node = union enum u8 {
    Nil,
    Lit: i64,
    Name: str,
}

fn digest[T: type](v: T) -> u64 {
    ret T.hash(v)
}

fn main() -> err {
    // The packed fast path must be untouched: still one xxHash64 pass over the run.
    if digest[str]("abc") != hash.xxhash64("abc", 0u64) { ret Failed }
    var values: [4]u32 = zero
    values[0usize] = 1u32
    values[1usize] = 2u32
    values[2usize] = 3u32
    values[3usize] = 4u32
    var raw: [16]u8 = zero
    raw[0usize] = 1u8
    raw[4usize] = 2u8
    raw[8usize] = 3u8
    raw[12usize] = 4u8
    if digest[[]u32](values[0usize..4usize]) != hash.xxhash64(raw[0usize..16usize], 0u64) { ret Failed }

    // A slice of slices: bytes are not contiguous, so this is the folded path.
    var backing: [8]i64 = zero
    backing[0usize] = 1i64
    backing[1usize] = 2i64
    backing[2usize] = 3i64
    backing[3usize] = 1i64
    backing[4usize] = 2i64
    backing[5usize] = 3i64
    backing[6usize] = 9i64
    backing[7usize] = 9i64
    var rows_a: [2][]i64 = zero
    var rows_b: [2][]i64 = zero
    rows_a[0usize] = backing[0usize..2usize]
    rows_a[1usize] = backing[2usize..3usize]
    rows_b[0usize] = backing[3usize..5usize]
    rows_b[1usize] = backing[5usize..6usize]
    // Equal contents through different storage must hash equally.
    if digest[[2][]i64](rows_a) != digest[[2][]i64](rows_b) { ret Failed }
    // Deterministic across repeated calls.
    if digest[[2][]i64](rows_a) != digest[[2][]i64](rows_a) { ret Failed }
    rows_b[1usize] = backing[6usize..7usize]
    if digest[[2][]i64](rows_a) == digest[[2][]i64](rows_b) { ret Failed }
    // Regrouping the same flat bytes must not collide: [[1],[2,3]] vs [[1,2],[3]].
    var split_a: [2][]i64 = zero
    var split_b: [2][]i64 = zero
    split_a[0usize] = backing[0usize..1usize]
    split_a[1usize] = backing[1usize..3usize]
    split_b[0usize] = backing[0usize..2usize]
    split_b[1usize] = backing[2usize..3usize]
    if digest[[2][]i64](split_a) == digest[[2][]i64](split_b) { ret Failed }

    // A slice of slices, where the outer length varies. `rows_b` was perturbed
    // above, so restore it first.
    rows_b[1usize] = backing[5usize..6usize]
    var one: [1][]i64 = zero
    one[0usize] = backing[0usize..2usize]
    if digest[[][]i64](one[0usize..1usize]) == digest[[][]i64](rows_a[0usize..2usize]) { ret Failed }
    if digest[[][]i64](rows_a[0usize..2usize]) != digest[[][]i64](rows_b[0usize..2usize]) { ret Failed }

    // Tagged unions: tag before the live payload, and a void arm is its tag alone.
    let nil_a: Node = .Nil
    let nil_b: Node = .Nil
    let lit4 = Node{ Lit: 4i64 }
    let lit9 = Node{ Lit: 9i64 }
    let name = Node{ Name: "abc" }
    if digest[Node](nil_a) != digest[Node](nil_b) { ret Failed }
    if digest[Node](lit4) != digest[Node](Node{ Lit: 4i64 }) { ret Failed }
    if digest[Node](lit4) == digest[Node](lit9) { ret Failed }
    if digest[Node](lit4) == digest[Node](nil_a) { ret Failed }
    if digest[Node](name) != digest[Node](Node{ Name: "abc" }) { ret Failed }
    if digest[Node](name) == digest[Node](Node{ Name: "abd" }) { ret Failed }
    if digest[Node](name) == digest[Node](lit4) { ret Failed }

    // A sequence of tagged unions folds the union path inside the sequence path.
    var nodes: [3]Node = zero
    nodes[0usize] = lit4
    nodes[1usize] = name
    nodes[2usize] = lit9
    if digest[[]Node](nodes[0usize..2usize]) != digest[[]Node](nodes[0usize..2usize]) { ret Failed }
    if digest[[]Node](nodes[0usize..2usize]) == digest[[]Node](nodes[1usize..3usize]) { ret Failed }

    ret ok
}
