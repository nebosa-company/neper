// `mem.address_of` read back as a number. Where the arena lands is not knowable from
// inside the program, so what is checked is what an address has to satisfy whatever it
// is: distances that follow the element size, alignment, and the same answer for the
// same place reached two ways.

use e.mem
use e.os

error Failed

type Pair = struct { low: u32, high: u32 }

fn main(a: *mem.Arena) -> err {
    let (bytes, bytes_error) = mem.alloc[u8](a, 64usize)
    if bytes_error != ok { ret bytes_error }
    let first = mem.address_of(&bytes[0usize])
    if first == 0usize { os.exit(10i32) }
    // One byte per index.
    if mem.address_of(&bytes[7usize]) - first != 7usize { os.exit(11i32) }
    if mem.address_of(&bytes[63usize]) - first != 63usize { os.exit(12i32) }
    // Asking twice gives the same answer: the address is a property of the place, not
    // of the expression that reached it.
    if mem.address_of(&bytes[7usize]) != mem.address_of(&bytes[7usize]) { os.exit(13i32) }

    // Four bytes per index, and the arena's own alignment.
    let (words, words_error) = mem.alloc[u32](a, 8usize)
    if words_error != ok { ret words_error }
    let word_first = mem.address_of(&words[0usize])
    if mem.address_of(&words[3usize]) - word_first != 12usize { os.exit(20i32) }
    if word_first % 4usize != 0usize { os.exit(21i32) }

    // A field's address is the struct's plus its offset, which is what makes an
    // address usable for anything a system call would want.
    let (pairs, pairs_error) = mem.alloc[Pair](a, 2usize)
    if pairs_error != ok { ret pairs_error }
    let pair_first = mem.address_of(&pairs[0usize])
    if mem.address_of(&pairs[0usize].low) != pair_first { os.exit(30i32) }
    if mem.address_of(&pairs[0usize].high) - pair_first != 4usize { os.exit(31i32) }
    if mem.address_of(&pairs[1usize]) - pair_first != 8usize { os.exit(32i32) }

    // A local, not an allocation: `&v` is a place like any other.
    var value = 9u64
    let held = &value
    if mem.address_of(held) == 0usize { os.exit(40i32) }
    if mem.address_of(held) != mem.address_of(&value) { os.exit(41i32) }
    if mem.address_of(held) % 8usize != 0usize { os.exit(42i32) }

    // A `const` pointer has an address too. Reading it out cannot cast the qualifier
    // away, because a `usize` is a number and nothing comes back through it.
    let readable: *const u64 = &value
    if mem.address_of(readable) != mem.address_of(held) { os.exit(43i32) }

    // Two allocations do not overlap, and the arena hands them out in order.
    if first >= word_first { os.exit(50i32) }
    if word_first - first < 64usize { os.exit(51i32) }
    ret ok
}
