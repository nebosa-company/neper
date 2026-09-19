use e.mem

// A derived slice cannot escape across its region's deferred reset (D680).
fn borrowed(a: *mem.Arena) -> ([]u8, err) {
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    defer mem.reset(a, checkpoint)
    ret (scratch[1usize..], ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bytes = try borrowed(a)
    if bytes.len == 0usize { ret mem.Exhausted }
    ret ok
}
