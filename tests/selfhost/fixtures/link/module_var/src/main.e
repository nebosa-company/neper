// Spec section 5's `var` at module scope: mutable static storage.
//
// What makes it storage rather than a value is that every function reaching it reaches the same
// bytes, so the interesting checks are across calls rather than within one. A per-use copy would
// pass a test that only ever read it back in the function that wrote it.

use e.os

var counter: usize = 0usize
// No initialiser, which is how a non-integer one is spelled: section 5 zero-initialises, and for
// a `bool` that is already `false`. An integer initialiser is carried; anything else is refused
// rather than quietly zeroed.
var flag: bool
var narrow: u8 = 0u8
var seeded: u32 = 7u32
var signed: i64 = -3i64

fn bump() {
    counter += 1usize
}

fn observed() -> usize {
    ret counter
}

fn raise() {
    flag = true
}

fn main() -> err {
    // --- Zero-initialised without an initialiser being written for it, which is what section 5
    // says and what an image gives for free.
    if counter != 0usize { os.exit(10i32) }
    if flag { os.exit(11i32) }
    if narrow != 0u8 { os.exit(12i32) }

    // --- An initialiser is compile-time and its bits are in the image.
    if seeded != 7u32 { os.exit(13i32) }
    if signed != -3i64 { os.exit(14i32) }

    // --- One variable, one address: a function that writes and another that reads agree.
    bump()
    if observed() != 1usize { os.exit(20i32) }
    bump()
    bump()
    if observed() != 3usize { os.exit(21i32) }
    if counter != 3usize { os.exit(22i32) }

    // --- Written here, read there.
    counter = 100usize
    if observed() != 100usize { os.exit(23i32) }

    // --- A bool is a byte and keeps its own storage rather than sharing a word with a neighbour.
    raise()
    if !flag { os.exit(30i32) }
    if counter != 100usize { os.exit(31i32) }
    if narrow != 0u8 { os.exit(32i32) }

    // --- Narrow widths are stored at their own width: writing 255 to a u8 leaves the u32 beside
    // it alone, which is what says the layout gave each one its own space.
    narrow = 255u8
    if narrow != 255u8 { os.exit(40i32) }
    if seeded != 7u32 { os.exit(41i32) }
    seeded = 4000000000u32
    if seeded != 4000000000u32 { os.exit(42i32) }
    if narrow != 255u8 { os.exit(43i32) }
    if counter != 100usize { os.exit(44i32) }
    ret ok
}
