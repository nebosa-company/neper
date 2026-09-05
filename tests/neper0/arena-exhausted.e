use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    var storage: [1]u8 = zero
    var arena = mem.arena_from(storage[..])
    let (values, allocation_error) = mem.alloc[u64](&arena, 1usize)
    ret allocation_error
}
