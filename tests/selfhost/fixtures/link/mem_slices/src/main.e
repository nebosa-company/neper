// `e.mem`'s last four: `copy` and `eq` over slices, and `size_of` and `align_of` over types.
//
// The two halves are opposites. `copy` and `eq` are ordinary generic code, so they are the first
// of `e.mem` that is not an intrinsic. `size_of` and `align_of` cannot be written at all -- only
// the compiler knows a layout -- and they answer with a constant, so nothing of them survives to
// run time.

use e.mem
use e.os

type Pair = struct { low: u32, high: u32 }

// A byte before an eight-byte field: the padding between them is what makes the size larger than
// the sum of the parts, and what makes a hand-written guess wrong.
type Padded = struct { flag: u8, value: u64 }

fn main(a: *mem.Arena) -> err {
    // --- `copy`, at equal lengths.
    var source: [4]u8 = zero
    source[0usize] = 1u8
    source[1usize] = 2u8
    source[2usize] = 3u8
    source[3usize] = 4u8
    var destination: [4]u8 = zero
    mem.copy[u8](destination[..], source[..])
    var at = 0usize
    while at < 4usize {
        if destination[at] != source[at] { os.exit(10i32) }
        at += 1usize
    }

    // --- `eq` answers on content, and a single differing byte is enough.
    if !mem.eq[u8](destination[..], source[..]) { os.exit(11i32) }
    destination[2usize] = 9u8
    if mem.eq[u8](destination[..], source[..]) { os.exit(12i32) }
    // Different lengths are never equal, whatever the shared prefix says.
    if mem.eq[u8](source[0usize..3usize], source[..]) { os.exit(13i32) }
    // Two empty slices are equal, which is the one case a loop alone would not answer.
    if !mem.eq[u8](source[0usize..0usize], destination[0usize..0usize]) { os.exit(14i32) }

    // --- A short destination takes what fits and no more. The fence gives `copy` no way to
    // report a length, so the alternative to this is a trap on a question the caller cannot ask.
    var narrow: [2]u8 = zero
    mem.copy[u8](narrow[..], source[..])
    if narrow[0usize] != 1u8 { os.exit(15i32) }
    if narrow[1usize] != 2u8 { os.exit(16i32) }
    // And a short source leaves the rest of the destination alone.
    var wide: [4]u8 = zero
    wide[3usize] = 7u8
    mem.copy[u8](wide[..], source[0usize..2usize])
    if wide[0usize] != 1u8 { os.exit(17i32) }
    if wide[3usize] != 7u8 { os.exit(18i32) }

    // --- Neither is limited to bytes: the element type is whatever it is handed.
    var counters: [3]u32 = zero
    counters[0usize] = 1000000u32
    counters[1usize] = 2000000u32
    counters[2usize] = 3000000u32
    var mirror: [3]u32 = zero
    mem.copy[u32](mirror[..], counters[..])
    if !mem.eq[u32](mirror[..], counters[..]) { os.exit(20i32) }
    mirror[1usize] = 0u32
    if mem.eq[u32](mirror[..], counters[..]) { os.exit(21i32) }

    // --- `size_of` and `align_of` on the scalars, where the answers are not a matter of opinion.
    if mem.size_of[u8]() != 1usize { os.exit(30i32) }
    if mem.align_of[u8]() != 1usize { os.exit(31i32) }
    if mem.size_of[u16]() != 2usize { os.exit(32i32) }
    if mem.align_of[u16]() != 2usize { os.exit(33i32) }
    if mem.size_of[u32]() != 4usize { os.exit(34i32) }
    if mem.align_of[u32]() != 4usize { os.exit(35i32) }
    if mem.size_of[u64]() != 8usize { os.exit(36i32) }
    if mem.align_of[u64]() != 8usize { os.exit(37i32) }
    if mem.size_of[usize]() != 8usize { os.exit(38i32) }
    if mem.size_of[i32]() != 4usize { os.exit(39i32) }
    if mem.size_of[bool]() != 1usize { os.exit(40i32) }

    // --- A pointer is a machine word.
    if mem.size_of[*u8]() != 8usize { os.exit(41i32) }
    if mem.align_of[*u8]() != 8usize { os.exit(42i32) }

    // --- An array is its element repeated, with no padding of its own.
    if mem.size_of[[4]u8]() != 4usize { os.exit(43i32) }
    if mem.align_of[[4]u8]() != 1usize { os.exit(44i32) }
    if mem.size_of[[3]u32]() != 12usize { os.exit(45i32) }
    if mem.align_of[[3]u32]() != 4usize { os.exit(46i32) }

    // --- A struct is where the answer stops being obvious. Two words need no padding; a byte
    // before a word needs seven, and then the whole is rounded to the widest member.
    if mem.size_of[Pair]() != 8usize { os.exit(50i32) }
    if mem.align_of[Pair]() != 4usize { os.exit(51i32) }
    if mem.size_of[Padded]() != 16usize { os.exit(52i32) }
    if mem.align_of[Padded]() != 8usize { os.exit(53i32) }

    // --- What must hold for any type at all, whatever the layout rules are.
    if mem.size_of[Padded]() < mem.align_of[Padded]() { os.exit(60i32) }
    let alignment = mem.align_of[Padded]()
    if alignment == 0usize { os.exit(61i32) }
    if alignment & (alignment - 1usize) != 0usize { os.exit(62i32) }
    // A struct's size is a whole number of its own alignment, or an array of them would not be
    // addressable.
    if mem.size_of[Padded]() % alignment != 0usize { os.exit(63i32) }

    // Not checked here, because it does not work: an array length is evaluated by the checker,
    // and the checker cannot reach a layout -- which is the same reason the type rather than the
    // size is what travels to lowering. `mem.size_of[u32]()` is a constant in the code that comes
    // out, but not one that can stand in `[N]u8`.
    ret ok
}
