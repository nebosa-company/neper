use e.mem

// The deferred reset runs before a returned region value reaches its caller (D675).
fn borrowed(a: *mem.Arena) -> ([]u8, err) {
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    defer mem.reset(a, checkpoint)
    ret (scratch, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bytes = try borrowed(a)
    if bytes.len == 0usize { ret mem.Exhausted }
    ret ok
}
