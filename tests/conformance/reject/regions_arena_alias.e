use e.mem

// Arena marks and allocations use the underlying local identity (D673).
fn main(a: *mem.Arena, args: []str) -> err {
    var buffer: [64]u8 = zero
    var arena = mem.arena_from(buffer[..])
    let pointer = &arena
    let checkpoint = mem.mark(pointer)
    let scratch = try mem.alloc[u8](&arena, 8usize)
    mem.reset(pointer, checkpoint)
    scratch[0usize] = 1u8
    ret ok
}
