// `e.mem.heap`: objects freed one at a time, for what an arena's stack of lifetimes does not fit
// (D5933). It is not global and nothing reaches it unless it is passed, so D3 stands: a function
// that takes no heap allocates from none. An eighth of its range is a `Slab` for sizes up to
// 4 KiB and the rest is a `Buddy` above that, and the range is only addresses until it is
// written, so a large one costs nothing at rest. A freed block of a mebibyte or more goes back
// to the operating system.
//
// A `Block` is a resource owed to `free`, so the checker refuses a block never freed, freed
// twice, or used after it was freed (D348), at no cost when the program runs. Blocks are
// independent of each other: freeing one ends that binding and leaves the rest alone. An array
// of blocks is untracked, as every array of resources is.
//
// ponytail: small blocks' pages are kept for the next small block and never go back. A single
// thread's, as an arena is.
use e.mem
use e.mem.pages
use e.os

const SMALL_LIMIT: usize = 4096usize
const SLAB_PAGE: usize = 65536usize
const LARGE_MINIMUM: usize = 8192usize
const RETURN_LIMIT: usize = 1048576usize

type State = struct { storage: []u8, owned: bool, large_base: usize, small: mem.Slab, large: mem.Buddy }

type Heap = struct { state: *State }

type Block = resource(free) struct { state: *State, bytes: []u8 }

// A heap over `storage`, which the caller keeps and which stays only addresses until written.
fn over(storage: []u8) -> (Heap, err) {
    let header = (mem.size_of[State]() + 4095usize) & ~4095usize
    if storage.len < header + 8usize * SLAB_PAGE { ret (zero, mem.Invalid) }
    let usable = storage.len - header
    let large_base = header + usable / 8usize
    let (slab, slab_error) = mem.slab(storage[header..large_base], SLAB_PAGE)
    if slab_error != ok { ret (zero, slab_error) }
    let (buddy, buddy_error) = mem.buddy(storage[large_base..storage.len], LARGE_MINIMUM)
    if buddy_error != ok { ret (zero, buddy_error) }
    var front = mem.arena_from(storage[0usize..header])
    let (states, state_error) = mem.alloc[State](&front, 1usize)
    if state_error != ok { ret (zero, state_error) }
    let state = &states[0usize]
    state.storage = storage
    state.owned = false
    state.large_base = large_base
    state.small = slab
    state.large = buddy
    ret (Heap { state: state }, ok)
}

// A heap over a range of its own, of up to `capacity` bytes: less where the host gives less.
fn open(capacity: usize) -> (Heap, err) {
    let (storage, reserve_error) = pages.reserve(capacity)
    if reserve_error != ok { ret (zero, reserve_error) }
    let (h, over_error) = over(storage)
    if over_error != ok {
        let released = pages.release(storage)
        ret (zero, over_error)
    }
    h.state.owned = true
    ret (h, ok)
}

// Gives the range back, every block in it with it.
fn close(h: Heap) -> err {
    if !h.state.owned { ret ok }
    ret pages.release(h.state.storage)
}

// `size` bytes, or `mem.Exhausted` when the heap has no room for them.
fn alloc(h: Heap, size: usize) -> (Block, err) {
    if size == 0usize { ret (Block { state: h.state, bytes: zero }, mem.Invalid) }
    if size <= SMALL_LIMIT {
        let (at, small_error) = mem.slab_alloc(&h.state.small, size)
        if small_error == mem.Full { ret (Block { state: h.state, bytes: zero }, mem.Exhausted) }
        if small_error != ok { ret (Block { state: h.state, bytes: zero }, small_error) }
        let slot = mem.slab_slot(&h.state.small, at, size)
        ret (Block { state: h.state, bytes: slot[0usize..size] }, ok)
    }
    let (at, large_error) = mem.buddy_alloc(&h.state.large, size)
    if large_error == mem.Full || large_error == mem.Invalid { ret (Block { state: h.state, bytes: zero }, mem.Exhausted) }
    if large_error != ok { ret (Block { state: h.state, bytes: zero }, large_error) }
    let start = h.state.large_base + at
    ret (Block { state: h.state, bytes: h.state.storage[start..start + size] }, ok)
}

// The block's bytes, for as long as the block lives.
fn bytes(block: *const Block) -> []u8 { ret block.bytes }

// Frees a block. One that `alloc` refused has nothing to give back.
fn free(block: own Block) {
    let state = block.state
    let held = block.bytes
    if held.len == 0usize { ret }
    let start = mem.address_of(&held[0usize]) - mem.address_of(&state.storage[0usize])
    if held.len <= SMALL_LIMIT {
        let slab_base = mem.address_of(&state.small.storage[0usize]) - mem.address_of(&state.storage[0usize])
        let small_freed = mem.slab_free(&state.small, start - slab_base, held.len)
        ret
    }
    if held.len >= RETURN_LIMIT {
        let discarded = pages.discard(held[SMALL_LIMIT..held.len])
    }
    let large_freed = mem.buddy_free(&state.large, start - state.large_base, held.len)
}
