// neper-0 memory surface. The compiler owns arena_from, alloc, mark, reset, stats,
// Stats, and Exhausted as fixed bootstrap intrinsics. This source fixes the public
// Arena representation.
type Arena = struct {
    base: *u8,
    cap: usize,
    off: usize,
}

fn arena_from(buf: []u8) -> Arena {
    ret Arena { base: &buf[0], cap: buf.len, off: 0usize }
}
