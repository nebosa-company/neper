// neper-0 memory surface. The compiler owns alloc, mark, reset, view, cast, bitcast,
// address_of, size_of, align_of, stats, Stats and Exhausted as intrinsics -- each of
// them needs to know something about a type or an arena that no source can say. This
// file holds the public `Arena` representation and the two that are ordinary code.
type Arena = struct { base: *u8, cap: usize, off: usize }

fn arena_from(buf: []u8) -> Arena {
    ret Arena { base: &buf[0], cap: buf.len, off: 0usize }
}

// Element by element, and as much of it as fits: the fence gives these no way to report
// a length, so a mismatch copies the shorter of the two rather than trapping on a
// question the caller cannot ask about.
fn copy[T: type](dst: []T, src: []const T) {
    var count = src.len
    if dst.len < count { count = dst.len }
    var at = 0usize
    while at < count {
        dst[at] = src[at]
        at += 1usize
    }
}

fn eq[T: type](x: []const T, y: []const T) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        if x[at] != y[at] { ret false }
        at += 1usize
    }
    ret true
}

// ---- Allocators over caller storage (algos 679, 680, 682) ------------------
//
// Three allocators that own nothing: the caller hands in a `[]u8`, and every free
// block links to the next through its own first eight bytes, written a byte at a time
// so the storage owes no alignment to the link. Each hands out and takes back `[]u8`
// views into that storage. `mark`/`reset` (algo 683) are the arena intrinsics above.

const NONE: usize = 18446744073709551615usize

error Invalid
error Full

fn get_link(storage: []u8, at: usize) -> usize {
    var value = 0usize
    var byte = 0usize
    while byte < 8usize {
        value = value | (usize(storage[at + byte]) << u32(byte * 8usize))
        byte += 1usize
    }
    ret value
}

fn put_link(storage: []u8, at: usize, value: usize) {
    var rest = value
    var byte = 0usize
    while byte < 8usize {
        storage[at + byte] = u8(rest & 255usize)
        rest = rest >> 8u32
        byte += 1usize
    }
}

fn is_power_of_two(x: usize) -> bool {
    if x == 0usize { ret false }
    ret (x & (x - 1usize)) == 0usize
}

// ---- Pool -------------------------------------------------------------------
//
// Fixed-size slots, a LIFO free list threaded through them. Answers are offsets into
// the storage (the buddy's convention too): the module cannot subtract addresses, as
// `address_of` is an intrinsic reachable only as `mem.address_of` from outside it,
// so a slot is named by where it is and `pool_slot` gives its bytes. Slot 0 starts
// at the storage's first byte, and every slot is `size` past it, `size` rounded up to
// `align`; the storage's own alignment is the caller's promise.

type Pool = struct { storage: []u8, size: usize, head: usize, free_count: usize }

fn pool(storage: []u8, object_size: usize, align: usize) -> (Pool, err) {
    if !is_power_of_two(align) || storage.len == 0usize { ret (zero, Invalid) }
    var size = object_size
    if size < 8usize { size = 8usize }
    size = (size + align - 1usize) & ~(align - 1usize)
    if size > storage.len { ret (zero, Invalid) }
    var p = Pool { storage: storage, size: size, head: NONE, free_count: 0usize }
    let count = storage.len / size
    pool_thread(&p, 0usize, count * size)
    ret (p, ok)
}

// Pushes every whole slot of `[lo, hi)` onto the free list, last first, so the lowest
// comes out first.
fn pool_thread(p: *Pool, lo: usize, hi: usize) {
    var count = (hi - lo) / p.size
    while count > 0usize {
        count -= 1usize
        let at = lo + count * p.size
        put_link(p.storage, at, p.head)
        p.head = at
        p.free_count += 1usize
    }
}

fn pool_alloc(p: *Pool) -> (usize, err) {
    if p.head == NONE { ret (0usize, Full) }
    let at = p.head
    p.head = get_link(p.storage, at)
    p.free_count -= 1usize
    ret (at, ok)
}

// The bytes of the slot at `offset`.
fn pool_slot(p: *Pool, offset: usize) -> []u8 {
    ret p.storage[offset..offset + p.size]
}

// `Invalid` for an offset that is not a slot of this pool; a double free is not caught.
fn pool_free(p: *Pool, offset: usize) -> err {
    if offset + p.size > p.storage.len || offset % p.size != 0usize { ret Invalid }
    put_link(p.storage, offset, p.head)
    p.head = offset
    p.free_count += 1usize
    ret ok
}

fn pool_free_count(p: *Pool) -> usize { ret p.free_count }

// ---- Slab -------------------------------------------------------------------
//
// Nine size classes, 16 to 4096 by doubling, each a `Pool` over the whole storage
// that is fed one page at a time as it runs dry. Pages are carved from the start of
// the storage in order and never returned, so the slab is exhausted when every page
// is out even if a class has slots free. Answers are offsets, as the pool's are.
//
// ponytail: a slot is aligned to its class only as far as the storage is; align the
// storage to 4096 and make the page size a multiple of it if a class needs its own.

const CLASS_COUNT: usize = 9usize

type Slab = struct { storage: []u8, page_size: usize, next_page: usize, classes: [9]Pool }

fn slab(storage: []u8, page_size: usize) -> (Slab, err) {
    if page_size < 4096usize || storage.len < page_size { ret (zero, Invalid) }
    var s: Slab = zero
    s.storage = storage
    s.page_size = page_size
    var class = 0usize
    while class < CLASS_COUNT {
        s.classes[class] = Pool { storage: storage, size: 16usize << u32(class), head: NONE, free_count: 0usize }
        class += 1usize
    }
    ret (s, ok)
}

// The class whose slot holds `size` bytes, or `CLASS_COUNT` when none does.
fn slab_class(size: usize) -> usize {
    if size == 0usize { ret CLASS_COUNT }
    var class = 0usize
    while class < CLASS_COUNT {
        if size <= 16usize << u32(class) { ret class }
        class += 1usize
    }
    ret CLASS_COUNT
}

fn slab_alloc(s: *Slab, size: usize) -> (usize, err) {
    let class = slab_class(size)
    if class == CLASS_COUNT { ret (0usize, Invalid) }
    if s.classes[class].head == NONE {
        if s.next_page + s.page_size > s.storage.len { ret (0usize, Full) }
        pool_thread(&s.classes[class], s.next_page, s.next_page + s.page_size)
        s.next_page += s.page_size
    }
    let (at, alloc_error) = pool_alloc(&s.classes[class])
    ret (at, alloc_error)
}

// The bytes of the slot at `offset` that `slab_alloc(s, size)` answered: the whole
// class slot, not just `size` of it.
fn slab_slot(s: *Slab, offset: usize, size: usize) -> []u8 {
    let class = slab_class(size)
    if class == CLASS_COUNT { ret s.storage[0usize..0usize] }
    ret pool_slot(&s.classes[class], offset)
}

// `size` is what was asked of `slab_alloc`, which names the class the slot returns to.
fn slab_free(s: *Slab, offset: usize, size: usize) -> err {
    let class = slab_class(size)
    if class == CLASS_COUNT { ret Invalid }
    ret pool_free(&s.classes[class], offset)
}

// ---- Buddy ------------------------------------------------------------------
//
// Order k is a block of `min_block << k` bytes; the arena is the largest such block
// that fits the storage, split on demand and merged with its buddy (the block at
// `offset ^ block_size`) on free. Answers are offsets into the storage, since a
// buddy's identity is its offset. One free list per order, threaded through the
// free blocks; a merge removes the buddy by walking its list, so a free is linear in
// the free blocks of one order.

const MAX_ORDERS: usize = 32usize

type Buddy = struct { storage: []u8, min_block: usize, orders: usize, total: usize, heads: [32]usize }

fn buddy(storage: []u8, min_block: usize) -> (Buddy, err) {
    if !is_power_of_two(min_block) || min_block < 8usize || storage.len < min_block { ret (zero, Invalid) }
    var b: Buddy = zero
    b.storage = storage
    b.min_block = min_block
    var order = 0usize
    while order < MAX_ORDERS {
        b.heads[order] = NONE
        order += 1usize
    }
    var top = 0usize
    while top + 1usize < MAX_ORDERS && (min_block << u32(top + 1usize)) <= storage.len {
        top += 1usize
    }
    b.orders = top + 1usize
    b.total = min_block << u32(top)
    put_link(storage, 0usize, NONE)
    b.heads[top] = 0usize
    ret (b, ok)
}

// The order of the smallest block holding `size`, or `orders` when none does.
fn buddy_order(b: *Buddy, size: usize) -> usize {
    if size == 0usize || size > b.total { ret b.orders }
    var order = 0usize
    while (b.min_block << u32(order)) < size {
        order += 1usize
    }
    ret order
}

fn buddy_push(b: *Buddy, order: usize, at: usize) {
    put_link(b.storage, at, b.heads[order])
    b.heads[order] = at
}

// Unlinks the block at `at` from `order`'s list; false when it is not free there.
fn buddy_remove(b: *Buddy, order: usize, at: usize) -> bool {
    if b.heads[order] == at {
        b.heads[order] = get_link(b.storage, at)
        ret true
    }
    var current = b.heads[order]
    while current != NONE {
        let following = get_link(b.storage, current)
        if following == at {
            put_link(b.storage, current, get_link(b.storage, at))
            ret true
        }
        current = following
    }
    ret false
}

fn buddy_alloc(b: *Buddy, size: usize) -> (usize, err) {
    let wanted = buddy_order(b, size)
    if wanted == b.orders { ret (0usize, Invalid) }
    var order = wanted
    while order < b.orders && b.heads[order] == NONE {
        order += 1usize
    }
    if order == b.orders { ret (0usize, Full) }
    let at = b.heads[order]
    b.heads[order] = get_link(b.storage, at)
    while order > wanted {
        order -= 1usize
        buddy_push(b, order, at + (b.min_block << u32(order)))
    }
    ret (at, ok)
}

// `size` is what was asked of `buddy_alloc`; the block merges upward as long as its
// buddy is free. `Invalid` for an offset that is not a block of that size.
fn buddy_free(b: *Buddy, offset: usize, size: usize) -> err {
    var order = buddy_order(b, size)
    if order == b.orders { ret Invalid }
    if offset % (b.min_block << u32(order)) != 0usize || offset >= b.total { ret Invalid }
    var at = offset
    var merging = true
    while merging && order + 1usize < b.orders {
        let partner = at ^ (b.min_block << u32(order))
        if buddy_remove(b, order, partner) {
            if partner < at { at = partner }
            order += 1usize
        } else {
            merging = false
        }
    }
    buddy_push(b, order, at)
    ret ok
}

// The largest block a `buddy_alloc` could answer with right now, in bytes; 0 when none.
fn buddy_largest_free(b: *Buddy) -> usize {
    var order = b.orders
    while order > 0usize {
        order -= 1usize
        if b.heads[order] != NONE { ret b.min_block << u32(order) }
    }
    ret 0usize
}
