// Reservations (C184, D5640): three regions reserved and committed, an arena over each written at
// both ends, the program's own arena grown past them afterwards, and every mark read back, so no
// region overlaps another or the root. On wasm32-wasi a reservation is address above the root
// arena and releasing the latest gives its address back; natively it is the host's mapping. The
// process's peak memory answers on both.
use e.mem
use e.os

const REGION: usize = 67108864usize

error Overlap

fn region(size: usize) -> (mem.Arena, err) {
    var none: mem.Arena = zero
    let (base, reserve_error) = os.reserve(size)
    if reserve_error != ok { ret (none, reserve_error) }
    try os.commit(base, size)
    var arena: mem.Arena = zero
    arena.base = base
    arena.cap = size
    ret (arena, ok)
}

// A byte at the region's start and one at its end, both `mark`.
fn stamp(arena: *mem.Arena, mark: u8) -> ([]u8, []u8, err) {
    var none: []u8 = zero
    let (head, head_error) = mem.alloc[u8](arena, 1usize)
    if head_error != ok { ret (none, none, head_error) }
    let (gap, gap_error) = mem.alloc[u8](arena, arena.cap - 2usize)
    if gap_error != ok { ret (none, none, gap_error) }
    let (tail, tail_error) = mem.alloc[u8](arena, 1usize)
    if tail_error != ok { ret (none, none, tail_error) }
    head[0usize] = mark
    tail[0usize] = mark
    ret (head, tail, ok)
}

fn main(a: *mem.Arena) -> err {
    var first = try region(REGION)
    var second = try region(REGION)
    var third = try region(REGION)
    let (h1, t1) = try stamp(&first, 17u8)
    let (h2, t2) = try stamp(&second, 34u8)
    let (h3, t3) = try stamp(&third, 51u8)
    // The root grows past where the regions were placed.
    let (grown, grown_error) = mem.alloc[u8](a, REGION)
    if grown_error != ok { ret grown_error }
    grown[0usize] = 85u8
    grown[REGION - 1usize] = 85u8
    if h1[0usize] != 17u8 || t1[0usize] != 17u8 { ret Overlap }
    if h2[0usize] != 34u8 || t2[0usize] != 34u8 { ret Overlap }
    if h3[0usize] != 51u8 || t3[0usize] != 51u8 { ret Overlap }
    // The latest given back, then a fourth: still clear of the other two.
    let base = third.base
    try os.release(base, REGION)
    var fourth = try region(REGION)
    let (h4, t4) = try stamp(&fourth, 68u8)
    if h1[0usize] != 17u8 || t1[0usize] != 17u8 || h2[0usize] != 34u8 || t2[0usize] != 34u8 { ret Overlap }
    if h4[0usize] != 68u8 || t4[0usize] != 68u8 || grown[0usize] != 85u8 { ret Overlap }
    // The process's peak, which on wasm32-wasi is the size the memory grew to.
    let (peak, peak_error) = os.peak_memory()
    if peak_error != ok { ret peak_error }
    if peak == 0usize { ret Overlap }
    let (written, write_error) = os.write(os.stdout(), "reservations kept apart\n")
    ret write_error
}
