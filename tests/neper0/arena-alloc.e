use e.mem
use e.io

type Pair = struct {
    tag: u8,
    value: u64,
}

fn main(a: *mem.Arena, args: []str) -> err {
    var storage: [64]u8 = zero
    var arena = mem.arena_from(storage[..])
    let (bytes, bytes_error) = mem.alloc[u8](&arena, 3usize)
    if bytes_error != ok { ret bytes_error }
    let (wide, wide_error) = mem.alloc[u64](&arena, 1usize)
    if wide_error != ok { ret wide_error }
    let (pairs, pairs_error) = mem.alloc[Pair](&arena, 2usize)
    if pairs_error != ok { ret pairs_error }
    bytes[0usize] = 7u8
    wide[0usize] = 19u64
    pairs[1usize] = Pair{ tag: 5u8, value: 23u64 }

    let before_empty = arena.off
    let (empty, empty_error) = mem.alloc[Pair](&arena, 0usize)
    if empty_error != ok { ret empty_error }
    let before_failure = arena.off
    let (too_large, exhausted) = mem.alloc[Pair](&arena, 2usize)
    let (overflowed, overflow_error) = mem.alloc[Pair](&arena, 1152921504606846976usize)

    var compound_storage: [64]u8 = zero
    var compound_arena = mem.arena_from(compound_storage[..])
    let (words, words_error) = mem.alloc[u16](&compound_arena, 1usize)
    if words_error != ok { ret words_error }
    let (rows, rows_error) = mem.alloc[[3]u16](&compound_arena, 1usize)
    if rows_error != ok { ret rows_error }
    let (pointers, pointers_error) = mem.alloc[*u8](&compound_arena, 1usize)
    if pointers_error != ok { ret pointers_error }
    let (tail, tail_error) = mem.alloc[u8](&compound_arena, 1usize)
    if tail_error != ok { ret tail_error }

    if bytes.len == 3usize && wide.len == 1usize && pairs.len == 2usize && bytes[0usize] == 7u8 && wide[0usize] == 19u64 && pairs[1usize].tag == 5u8 && pairs[1usize].value == 23u64 && before_empty == 48usize && empty.len == 0usize && arena.off == before_failure && too_large.len == 0usize && exhausted == mem.Exhausted && overflowed.len == 0usize && overflow_error == mem.Exhausted && words.len == 1usize && rows.len == 1usize && pointers.len == 1usize && tail.len == 1usize && compound_arena.off == 17usize {
        try io.print("arena alloc ok\n")
    } else {
        try io.print("arena alloc failed\n")
    }
    ret ok
}
