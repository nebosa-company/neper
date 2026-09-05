use e.mem

fn main(a: *mem.Arena, args: []str) -> err {
    var storage: [4]u8 = zero
    var arena = mem.arena_from(storage[..])
    mem.reset(&arena, 1usize)
    ret ok
}
