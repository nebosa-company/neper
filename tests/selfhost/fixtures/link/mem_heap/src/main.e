// (D5933) `e.mem.heap` frees one object at a time. Two gibibytes go through a heap that never
// holds more than a few mebibytes live, in sizes from a few bytes to a mebibyte and in no
// stack order, and the process stays small. A large block handed back gives its pages to the
// operating system.
use e.mem
use e.mem.heap
use e.os

const MIB: usize = 1048576usize
const SLOTS: usize = 64usize

error WrongBytes
error TooLarge
error NotReturned
error StaysFull
error FreedTheWrongOne

// The next size, from a small fixed-seed generator: mostly small, sometimes a mebibyte.
fn next(state: *u64) -> usize {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    let picked = *state >> 33u32
    if picked % 64u64 == 0u64 { ret MIB }
    if picked % 8u64 == 0u64 { ret 8192usize + usize(picked % 65536u64) }
    ret 1usize + usize(picked % 4096u64)
}

fn check(block: *const heap.Block) -> bool {
    let held = heap.bytes(block)
    let tag = u8(held.len % 251usize)
    ret held[0usize] == tag && held[held.len - 1usize] == tag
}

fn stamp(block: *const heap.Block) {
    let held = heap.bytes(block)
    let tag = u8(held.len % 251usize)
    held[0usize] = tag
    held[held.len - 1usize] = tag
}

// Puts a block in a slot, freeing what the slot held. A slice of blocks is the
// program's to keep track of, as `filled` does here.
fn put(slots: []heap.Block, filled: []bool, slot: usize, block: own heap.Block) -> bool {
    var intact = true
    if filled[slot] {
        intact = check(&slots[slot])
        heap.free(slots[slot])
    }
    slots[slot] = block
    filled[slot] = true
    ret intact
}

// Blocks live as long as a pseudo-random slot keeps them, so frees come in no stack order.
fn churn(h: heap.Heap) -> err {
    var slots: [64]heap.Block = zero
    var filled: [64]bool = zero
    var state = 42u64
    var moved = 0usize
    while moved < 2048usize * MIB {
        let size = next(&state)
        let slot = usize((state >> 20u32) % u64(SLOTS))
        let (block, alloc_error) = heap.alloc(h, size)
        if alloc_error != ok { ret alloc_error }
        stamp(&block)
        if !put(slots[..], filled[..], slot, block) { ret WrongBytes }
        moved += size
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (h, open_error) = heap.open(8usize * 1024usize * MIB)
    if open_error != ok { ret open_error }

    // Two live blocks: freeing one leaves the other.
    let (first, first_error) = heap.alloc(h, 64usize)
    if first_error != ok { ret first_error }
    defer heap.free(first)
    let (second, second_error) = heap.alloc(h, 64usize)
    if second_error != ok { ret second_error }
    let first_bytes = heap.bytes(&first)
    let second_bytes = heap.bytes(&second)
    first_bytes[0usize] = 1u8
    second_bytes[0usize] = 2u8
    heap.free(second)
    if first_bytes[0usize] != 1u8 { ret FreedTheWrongOne }

    let churned = churn(h)
    if churned != ok { ret churned }
    let (peak, peak_error) = os.peak_memory()
    if peak_error != ok { ret peak_error }
    if peak > 256usize * MIB { ret TooLarge }

    // A large block goes back to the operating system when it is freed, which reading what
    // the freed bytes held shows: through an arena over them, since the checker ends the block.
    let (large, large_error) = heap.alloc(h, 16usize * MIB)
    if large_error != ok { ret large_error }
    let large_bytes = heap.bytes(&large)
    large_bytes[8usize * MIB] = 7u8
    var spy = mem.arena_from(large_bytes)
    heap.free(large)
    let seen = mem.view(&spy, 8usize * MIB, 1usize)
    if seen[0usize] != 0u8 { ret NotReturned }

    // And more than it holds is an error, not a surprise.
    let (none, none_error) = heap.alloc(h, 64usize * 1024usize * MIB)
    if none_error == ok {
        heap.free(none)
        ret StaysFull
    }
    if none_error != mem.Exhausted { ret StaysFull }
    ret ok
}
