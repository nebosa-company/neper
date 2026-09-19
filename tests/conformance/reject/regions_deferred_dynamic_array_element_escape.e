use e.mem

// A runtime-indexed pointer return may select the region element, so the
// deferred reset forbids the escape even when another candidate is live (D712).
fn borrowed(a: *mem.Arena, which: usize) -> (*u8, err) {
    var stable = 1u8
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let pointers = [2usize]*u8{ &stable, &scratch[0usize] }
    defer mem.reset(a, checkpoint)
    ret (pointers[which], ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let pointer = try borrowed(a, args.len % 2usize)
    if *pointer != 0u8 { ret mem.Exhausted }
    ret ok
}
