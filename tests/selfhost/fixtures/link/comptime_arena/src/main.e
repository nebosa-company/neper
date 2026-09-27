// The arena as interpreter memory (D1572, C066): `mem.arena_from` over a local array,
// `mem.alloc` from it (the offset rounded to the element's alignment, the memory
// filled with 0xCD), `mem.mark` and `mem.reset`, `Exhausted` past the end, and
// `try mem.alloc` in a function answering an `err` -- all at compile time.
use e.mem

error Wrong

fn arena_answer() -> u32 {
    var backing: [256]u8 = zero
    var arena = mem.arena_from(backing[..])
    let (values, alloc_error) = mem.alloc[u32](&arena, 8usize)
    if alloc_error != ok { ret 0u32 }
    for i in 0usize..8usize {
        values[i] = u32(i * i)
    }
    var sum = 0u32
    for i in 0usize..values.len {
        sum += values[i]
    }
    let used = mem.mark(&arena)
    let (more, more_error) = mem.alloc[u64](&arena, 2usize)
    if more_error != ok { ret 0u32 }
    let fill = more[0usize]
    mem.reset(&arena, used)
    let (huge, huge_error) = mem.alloc[u8](&arena, 1000usize)
    var answer = sum + u32(used)
    if huge_error == mem.Exhausted && huge.len == 0usize { answer += 1000u32 }
    if fill == 14829735431805717965u64 { answer += 10000u32 }
    if mem.mark(&arena) == 32usize { answer += 100000u32 }
    ret answer
}

fn table() -> (u32, err) {
    var backing: [64]u8 = zero
    var arena = mem.arena_from(backing[..])
    let cells = try mem.alloc[u16](&arena, 4usize)
    cells[3usize] = 9u16
    ret (u32(cells[3usize]), ok)
}

fn table_value() -> u32 {
    let (value, failed) = table()
    if failed != ok { ret 0u32 }
    ret value
}

const ARENA = arena_answer()
const TABLE = table_value()

fn main() -> err {
    if ARENA != 111172u32 { ret Wrong }
    if TABLE != 9u32 { ret Wrong }
    ret ok
}
