use e.mem

// Registering a deferred reset does not run it immediately (D675).
fn main(a: *mem.Arena, args: []str) -> err {
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    defer mem.reset(a, checkpoint)
    scratch[0usize] = 1u8
    if scratch[0usize] != 1u8 { ret mem.Exhausted }
    ret ok
}
