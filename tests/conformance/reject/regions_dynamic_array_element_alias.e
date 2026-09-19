use e.mem

// A runtime element may name any pointer in the fixed array, so one dangling
// candidate makes the dereference unsafe even when another stays live (D711).
fn main(a: *mem.Arena, args: []str) -> err {
    var stable = 1u8
    let checkpoint = mem.mark(a)
    let scratch = try mem.alloc[u8](a, 8usize)
    let pointers = [2usize]*u8{ &stable, &scratch[0usize] }
    mem.reset(a, checkpoint)
    let which = args.len % 2usize
    if *pointers[which] != 0u8 { ret mem.Exhausted }
    ret ok
}
