use e.mem

// A slice allocated after a mark is gone at the reset (D354): E-SAFETY-0013.
fn main(a: *mem.Arena, args: []str) -> err {
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 16usize)
    scratch[0usize] = 1u8
    mem.reset(a, checkpoint)
    if scratch[0usize] != 1u8 { ret mem.Exhausted }
    ret ok
}
