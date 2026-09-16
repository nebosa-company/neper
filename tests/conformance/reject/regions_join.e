use e.mem

// A region reset on one path and not the other is gone on both (D354).
fn main(a: *mem.Arena, args: []str) -> err {
    let checkpoint = mem.mark(a)
    let name = try mem.alloc[u8](a, 8usize)
    if args.len > 1usize { mem.reset(a, checkpoint) }
    name[0usize] = 2u8
    ret ok
}
