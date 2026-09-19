use e.mem

// Separate comptime-indexed assignments retain each fixed-array element's owner,
// including a later pointer into the deferred-reset region (D709).
fn borrowed(a: *mem.Arena) -> ([3usize]*u8, err) {
    var first = 1u8
    var second = 2u8
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    var pointers: [3usize]*u8 = zero
    pointers[0usize] = &first
    pointers[1usize] = &second
    pointers[2usize] = &scratch[0usize]
    defer mem.reset(a, checkpoint)
    ret (pointers, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let pointers = try borrowed(a)
    if *pointers[2usize] != 0u8 { ret mem.Exhausted }
    ret ok
}
