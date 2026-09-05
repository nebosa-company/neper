use e.mem
use e.io

fn main(a: *mem.Arena, args: []str) -> err {
    var storage: [32]u8 = zero
    var arena = mem.arena_from(storage[..])
    let beginning = mem.mark(&arena)
    let (prefix, prefix_error) = mem.alloc[u8](&arena, 3usize)
    if prefix_error != ok { ret prefix_error }
    let saved = mem.mark(&arena)
    let before = mem.stats(&arena)
    let (wide, wide_error) = mem.alloc[u64](&arena, 1usize)
    if wide_error != ok { ret wide_error }
    let peak = mem.stats(&arena)
    mem.reset(&arena, saved)
    let after = mem.stats(&arena)
    let (word, word_error) = mem.alloc[u16](&arena, 1usize)
    if word_error != ok { ret word_error }

    if beginning == 0usize && before.used == 3usize && before.capacity == 32usize && peak.used == 16usize && peak.capacity == 32usize && after.used == 3usize && after.capacity == 32usize && arena.off == 6usize && prefix.len == 3usize && wide.len == 1usize && word.len == 1usize {
        try io.print("arena scope ok\n")
    } else {
        try io.print("arena scope failed\n")
    }
    ret ok
}
