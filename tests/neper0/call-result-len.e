// `.len` on a call result, which the bootstrap used to get wrong.
//
// A `str` or slice `.len` is read out of an address, and the bootstrap asked for the
// address of whatever the base was without checking that the base had one. A call
// result does not: the value arrives as (rax = pointer, rdx = length), so the length is
// already in a register and there is nothing to dereference. Asking anyway read
// whatever `r10` happened to hold, which made the answer depend on the surrounding
// code -- correct in a small function, wrong in a large one, and different between
// builds. It cost a whole session's tail to find, so it is pinned here.
//
// This is a bootstrap code-generation test: the point is to build it with the
// bootstrap and run it. The self-hosted back end was always right.

use e.mem

error Failed

type Item = struct { library: str, symbol: str }

fn literal() -> str {
    ret "libc.so.6"
}

fn from_field(items: []Item, index: usize) -> str {
    ret items[index].library
}

fn identity(bytes: []u8) -> []u8 {
    ret bytes
}

fn main(a: *mem.Arena, args: []str) -> err {
    // A literal returned by value.
    if literal().len != 9usize { ret Failed }

    // A str read out of a struct behind a slice.
    var items: [2]Item = zero
    items[0usize] = Item { library: "libc.so.6", symbol: "abs" }
    items[1usize] = Item { library: "de", symbol: "q" }
    if from_field(items[..], 0usize).len != 9usize { ret Failed }
    if from_field(items[..], 1usize).len != 2usize { ret Failed }

    // A slice returned by value.
    var buf: [9]u8 = zero
    if identity(buf[..]).len != 9usize { ret Failed }

    // Accumulated, which is how it first showed up.
    var total = 0usize
    var at = 0usize
    while at < 2usize {
        total += from_field(items[..], at).len + 1usize
        at += 1usize
    }
    if total != 13usize { ret Failed }

    // And the place forms, which always worked and must keep working.
    let bound = literal()
    if bound.len != 9usize { ret Failed }
    if items[0usize].library.len != 9usize { ret Failed }
    if buf[..].len != 9usize { ret Failed }
    ret ok
}
