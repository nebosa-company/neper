use e.mem

// A pointer derived from region storage cannot escape its deferred reset (D681).
fn borrowed(a: *mem.Arena) -> (*u8, err) {
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    defer mem.reset(a, checkpoint)
    ret (&scratch[0usize], ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let byte = try borrowed(a)
    if *byte != 0u8 { ret mem.Exhausted }
    ret ok
}
