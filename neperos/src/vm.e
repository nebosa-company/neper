// A user address space (D2127): its own first-level table, a copy of the kernel's identity
// map so the kernel still runs when a trap enters it, plus one gigabyte at USER_BASE mapped
// to the thread's own pages with EL0 access. The kernel's pages stay privileged-only in the
// copy, so an EL0 load or store into them faults -- that is the isolation stage 1 proves.
// Nothing here forges a pointer: the kernel owns these physical pages (allocated from its
// arena, identity-mapped) and writes the program, arena and arguments into them by address.
use e.mem
use e.os
use a64

error NoSpace

// The user gigabyte and the layout inside it. 512 KB is 128 4 KB pages, one L3 table.
const USER_BASE: usize = 2147483648usize
const USER_PAGES: usize = 128usize
const USER_SIZE: usize = 524288usize
const PAGE: usize = 4096usize
// The arena the program allocates from, then the argument area, then the stack at the top.
const ARENA_OFF: usize = 262144usize
const ARENA_SIZE: usize = 65536usize
const ARG_OFF: usize = 327680usize
const ARG_SIZE: usize = 131072usize
const STACK_TOP: usize = 524288usize

// The user gigabyte's level-1 index (VA bits 38:30) and the page bits a leaf carries:
// a valid page, Normal memory (MAIR index 2), EL0-and-EL1 read/write, inner shareable,
// the access flag, and privileged-execute-never so the kernel never runs user code.
const L1_USER_INDEX: usize = 2usize
const TABLE: usize = 3usize
const PAGE_VALID: usize = 3usize
const ATTR_NORMAL: usize = 8usize
const AP_EL0_RW: usize = 64usize
const SHARE_INNER: usize = 768usize
const ACCESS_FLAG: usize = 1024usize
const PRIVILEGED_EXECUTE_NEVER: usize = 1usize << 53usize
// The 48-bit, page-aligned table address inside TTBR0, without its ASID.
const TABLE_MASK: usize = 281474976706560usize

type Space = struct {
    ttbr: usize,
    entry: usize,
    stack_top: usize,
    region_phys: usize,
    arena_addr: usize,
    arena_size: usize,
}

fn user_page_bits() -> usize {
    ret PAGE_VALID | ATTR_NORMAL | AP_EL0_RW | SHARE_INNER | ACCESS_FLAG | PRIVILEGED_EXECUTE_NEVER
}

// A zeroed, 4 KB-aligned page. A translation table base must be aligned to its size, and
// the arena allocator makes no such promise, so this over-allocates and aligns up.
fn page_of(a: *mem.Arena) -> (usize, err) {
    let (bytes, bytes_error) = mem.alloc[u8](a, PAGE + PAGE)
    if bytes_error != ok { ret (0usize, bytes_error) }
    let at = (mem.address_of(&bytes[0usize]) + PAGE - 1usize) & ~(PAGE - 1usize)
    var i = 0usize
    while i < PAGE {
        os.store64(at + i, 0u64)
        i += 8usize
    }
    ret (at, ok)
}

// A fresh address space over a copy of the kernel's first-level table, the user gigabyte
// mapped to its own pages, and the program image at [image_addr, image_addr+image_len)
// copied into them by address. `asid` tags its TLB entries so no flush is needed when the
// scheduler switches to it.
fn create(a: *mem.Arena, image_addr: usize, image_len: usize, asid: usize) -> (Space, err) {
    let (region, region_error) = mem.alloc[u8](a, USER_SIZE + PAGE)
    if region_error != ok { ret (zero, region_error) }
    let region_phys = (mem.address_of(&region[0usize]) + PAGE - 1usize) & ~(PAGE - 1usize)
    let (l1, l1_error) = page_of(a)
    if l1_error != ok { ret (zero, l1_error) }
    let (l2, l2_error) = page_of(a)
    if l2_error != ok { ret (zero, l2_error) }
    let (l3, l3_error) = page_of(a)
    if l3_error != ok { ret (zero, l3_error) }
    let kernel_l1 = os.mrs(a64.TTBR0_EL1) & TABLE_MASK
    var entry_at = 0usize
    while entry_at < 512usize {
        os.store64(l1 + entry_at * 8usize, u64(os.load64(kernel_l1 + entry_at * 8usize)))
        entry_at += 1usize
    }
    os.store64(l1 + L1_USER_INDEX * 8usize, u64(l2 | TABLE))
    os.store64(l2, u64(l3 | TABLE))
    let bits = user_page_bits()
    var page_at = 0usize
    while page_at < USER_PAGES {
        os.store64(l3 + page_at * 8usize, u64((region_phys + page_at * PAGE) | bits))
        page_at += 1usize
    }
    var copied = 0usize
    while copied < image_len {
        os.store8(region_phys + copied, os.load8(image_addr + copied))
        copied += 1usize
    }
    ret (Space {
        ttbr: l1 | (asid << 48usize),
        entry: USER_BASE,
        stack_top: USER_BASE + STACK_TOP,
        region_phys: region_phys,
        arena_addr: USER_BASE + ARENA_OFF,
        arena_size: ARENA_SIZE,
    }, ok)
}

// A byte written where the user will read it: `offset` into the region, by its address.
fn put_byte(space: Space, offset: usize, value: u8) {
    os.store8(space.region_phys + offset, value)
}

fn put_word(space: Space, offset: usize, value: usize) {
    os.store64(space.region_phys + offset, u64(value))
}

// The user virtual address of an offset into the region.
fn address(offset: usize) -> usize {
    ret USER_BASE + offset
}

// AP[1] in a page descriptor: with it set the page is read-only at EL0; clear, read/write.
const AP_READONLY: usize = 128usize

// Re-protect the page at user VA `va` in the address space rooted at `ttbr`: writable clears
// AP[1], read-only sets it, so an EL0 store into a read-only page faults. The walk follows
// the three table levels the map uses; a flush makes the change take effect.
fn protect(ttbr: usize, va: usize, writable: bool) {
    let l1 = ttbr & TABLE_MASK
    let l1_entry = usize(os.load64(l1 + ((va >> 30usize) & 511usize) * 8usize))
    let l2 = l1_entry & TABLE_MASK
    let l2_entry = usize(os.load64(l2 + ((va >> 21usize) & 511usize) * 8usize))
    let l3 = l2_entry & TABLE_MASK
    let slot = l3 + ((va >> 12usize) & 511usize) * 8usize
    var entry = usize(os.load64(slot))
    if writable { entry = entry & ~AP_READONLY } else { entry = entry | AP_READONLY }
    os.store64(slot, u64(entry))
    os.barrier()
    os.tlb_flush()
}
