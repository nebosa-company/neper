// neper-0 memory surface. The compiler owns alloc, mark, reset, view, cast, bitcast,
// address_of, size_of, align_of, stats, Stats and Exhausted as intrinsics -- each of
// them needs to know something about a type or an arena that no source can say. This
// file holds the public `Arena` representation and the two that are ordinary code.
// The fields the other way round (D552): the runtime reads `base` at 0, `cap` at 8
// and `off` at 16, so this library is refused at the build, E-LINK-0002.
type Arena = struct {
    off: usize,
    cap: usize,
    base: *u8,
}

fn arena_from(buf: []u8) -> Arena {
    ret Arena { base: &buf[0], cap: buf.len, off: 0usize }
}

// Element by element, and as much of it as fits: the fence gives these no way to report
// a length, so a mismatch copies the shorter of the two rather than trapping on a
// question the caller cannot ask about.
fn copy[T: type](dst: []T, src: []const T) {
    var count = src.len
    if dst.len < count { count = dst.len }
    var at = 0usize
    while at < count {
        dst[at] = src[at]
        at += 1usize
    }
}

fn eq[T: type](x: []const T, y: []const T) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        if x[at] != y[at] { ret false }
        at += 1usize
    }
    ret true
}
