use e.mem

// Returning a fixed array cannot hide a deferred-region pointer in a later
// comptime element behind earlier live elements (D707).
fn borrowed(a: *mem.Arena) -> ([3usize]*u8, err) {
    var first = 1u8
    var second = 2u8
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let pointers = [3usize]*u8{ &first, &second, &scratch[0usize] }
    defer mem.reset(a, checkpoint)
    ret (pointers, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let pointers = try borrowed(a)
    if *pointers[2usize] != 0u8 { ret mem.Exhausted }
    ret ok
}
