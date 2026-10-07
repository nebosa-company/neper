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
// USER_BASE is the top gigabyte of the 39-bit space (index 511): the identity map puts
// physical RAM wherever the device tree says it is -- gigabyte 1 (0x40000000) under QEMU's
// virt, gigabyte 2 (0x80000000) under crosvm -- and `create` overwrites the user gigabyte's
// level-1 entry, so the user VA must never land on a gigabyte that holds RAM or the kernel's
// own code would vanish from the space. 0x7FC0000000 holds neither RAM nor a device on any
// target (no such machine has 508 GB of RAM), so it is safe everywhere.
const USER_BASE: usize = 548682072064usize
const PAGE: usize = 4096usize
// (D2168) The EL0 window is laid out around the program image, not at fixed offsets: the image
// (page-aligned) sits at the bottom, then the in-window arena, the argument area, and the stack at
// the top, each sized by the constants below. A 512 KB program used to clobber the arena and a
// larger one overran the region into kernel memory; now `create` sizes the whole window to the
// image so e.ui programs (hundreds of KB) fit. The window stays within one level-3 table's 2 MB
// reach (L3_PAGES), which also leaves the entries above it for thread stacks (map_stack).
const ARENA_SIZE: usize = 65536usize
const ARG_SIZE: usize = 131072usize
const STACK_SIZE: usize = 524288usize
const L3_PAGES: usize = 512usize

// The user gigabyte's level-1 index (VA bits 38:30), derived from USER_BASE so the two can
// never drift, and the page bits a leaf carries: a valid page, Normal memory (MAIR index 2),
// EL0-and-EL1 read/write, inner shareable, the access flag, privileged-execute-never so the
// kernel never runs user code, and non-global (D2147) so the entry is tagged by the space's
// ASID: the scheduler switches address spaces by ASID without flushing the TLB, which keeps a
// thread's USER_BASE pages apart only when they are non-global. Left global, a stale USER_BASE
// entry from one thread serves another on hardware that keeps global entries across a TTBR0
// write (real cores; QEMU happens to hide it), so a thread reads another's memory.
const L1_USER_INDEX: usize = USER_BASE >> 30usize
const TABLE: usize = 3usize
const PAGE_VALID: usize = 3usize
const ATTR_NORMAL: usize = 8usize
const AP_EL0_RW: usize = 64usize
const NOT_GLOBAL: usize = 1usize << 11usize
const SHARE_INNER: usize = 768usize
const ACCESS_FLAG: usize = 1024usize
const PRIVILEGED_EXECUTE_NEVER: usize = 1usize << 53usize
// The 48-bit, page-aligned table address inside TTBR0, without its ASID.
const TABLE_MASK: usize = 281474976706560usize
// (D2137) Device memory (MAIR index 1) and the user-execute-never bit, for mapping a device's
// MMIO into an EL0 driver; a gigabyte and a 2 MB block, the granules a map is split through.
const ATTR_DEVICE: usize = 1usize << 2usize
const USER_EXECUTE_NEVER: usize = 1usize << 54usize
const GIGABYTE: usize = 1073741824usize
const BLOCK_2MB: usize = 2097152usize
// A driver thread's device and DMA addresses: the kernel leaves them in a small area just below
// the arena, which the program reads at USER_BASE + AUX_OFF (D2137).
const AUX_OFF: usize = 262080usize

type Space = struct {
    ttbr: usize,
    entry: usize,
    stack_top: usize,
    region_phys: usize,
    arena_addr: usize,
    arena_size: usize,
    arg_off: usize,
    size: usize,
}

fn user_page_bits() -> usize {
    ret PAGE_VALID | ATTR_NORMAL | AP_EL0_RW | NOT_GLOBAL | SHARE_INNER | ACCESS_FLAG | PRIVILEGED_EXECUTE_NEVER
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
    // The window, laid out from the page-aligned image: image | arena | args | stack. The stack
    // grows down from the top, so stack_top is the whole window size. A window past one level-3
    // table's 2 MB reach is refused (NoSpace) rather than silently overrun as the old fixed region
    // was -- that overrun scribbled over kernel memory for any program above ~256 KB (D2168).
    let image_bytes = (image_len + PAGE - 1usize) & ~(PAGE - 1usize)
    let arena_off = image_bytes
    let arg_off = arena_off + ARENA_SIZE
    let window = arg_off + ARG_SIZE + STACK_SIZE
    let pages = window / PAGE
    if pages > L3_PAGES { ret (zero, NoSpace) }
    let (region, region_error) = mem.alloc[u8](a, window + PAGE)
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
    while page_at < pages {
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
        stack_top: USER_BASE + window,
        region_phys: region_phys,
        arena_addr: USER_BASE + arena_off,
        arena_size: ARENA_SIZE,
        arg_off: arg_off,
        size: window,
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

// The leaf bits for an identity EL0 page: Device memory (nGnRE) or Normal, read/write at EL0,
// never executable. Device is not inner-shareable; Normal is, like the user region.
fn el0_page_bits(device: bool) -> usize {
    if device { ret PAGE_VALID | ATTR_DEVICE | AP_EL0_RW | NOT_GLOBAL | ACCESS_FLAG | PRIVILEGED_EXECUTE_NEVER | USER_EXECUTE_NEVER }
    ret user_page_bits()
}

// A fresh level-2 table for gigabyte `gig`, reflecting its current mapping in `l1` so that
// splitting it loses nothing: an existing table is copied entry for entry; a 1 GB block is
// synthesised as 512 identity 2 MB blocks carrying the block's own attributes (so the untouched
// remainder keeps the kernel's privileged device or RAM mapping). The kernel's own tables are
// never written -- only this space's copy.
fn clone_l2(a: *mem.Arena, l1: usize, gig: usize) -> (usize, err) {
    let (l2, l2_error) = page_of(a)
    if l2_error != ok { ret (0usize, l2_error) }
    let entry = usize(os.load64(l1 + gig * 8usize))
    if (entry & 3usize) == TABLE {
        let src = entry & TABLE_MASK
        var i = 0usize
        while i < 512usize {
            os.store64(l2 + i * 8usize, u64(os.load64(src + i * 8usize)))
            i += 1usize
        }
    } else {
        let attrs = entry & ~TABLE_MASK
        let base = gig * GIGABYTE
        var i = 0usize
        while i < 512usize {
            os.store64(l2 + i * 8usize, u64((base + i * BLOCK_2MB) | attrs))
            i += 1usize
        }
    }
    ret (l2, ok)
}

// A fresh level-3 table for the 2 MB block at `block_index` of level-2 table `l2`, reflecting
// its current mapping: a table is copied; a 2 MB block is synthesised as 512 identity 4 KB pages
// carrying the block's attributes (as pages, not blocks); an invalid block stays unmapped.
fn clone_l3(a: *mem.Arena, l2: usize, block_index: usize) -> (usize, err) {
    let (l3, l3_error) = page_of(a)
    if l3_error != ok { ret (0usize, l3_error) }
    let entry = usize(os.load64(l2 + block_index * 8usize))
    if (entry & 1usize) == 0usize { ret (l3, ok) }
    if (entry & 3usize) == TABLE {
        let src = entry & TABLE_MASK
        var i = 0usize
        while i < 512usize {
            os.store64(l3 + i * 8usize, u64(os.load64(src + i * 8usize)))
            i += 1usize
        }
        ret (l3, ok)
    }
    let attrs = (entry & ~TABLE_MASK & ~3usize) | PAGE_VALID
    let base = entry & TABLE_MASK
    var i = 0usize
    while i < 512usize {
        os.store64(l3 + i * 8usize, u64((base + i * PAGE) | attrs))
        i += 1usize
    }
    ret (l3, ok)
}

// Map the physical range [pa, pa+len) into the EL0 space rooted at `ttbr` at identity virtual
// addresses, read/write at EL0, as Device or Normal memory (D2137). This is how a user-mode
// driver is handed its device's MMIO and an identity DMA pool and nothing else: the pages it is
// not given stay privileged, so a stray access faults. The range must lie within one gigabyte.
// Splitting copies the current mapping into fresh tables first, so earlier EL0 mappings in the
// same gigabyte survive and only this space's tables change.
fn map_range_el0(a: *mem.Arena, ttbr: usize, pa: usize, len: usize, device: bool) -> err {
    let l1 = ttbr & TABLE_MASK
    let first = pa & ~(PAGE - 1usize)
    let last = (pa + len - 1usize) & ~(PAGE - 1usize)
    if (first >> 30usize) != (last >> 30usize) { ret NoSpace }
    let gig = first >> 30usize
    let (l2, l2_error) = clone_l2(a, l1, gig)
    if l2_error != ok { ret l2_error }
    os.store64(l1 + gig * 8usize, u64(l2 | TABLE))
    let bits = el0_page_bits(device)
    var page = first
    var current_block = 18446744073709551615usize
    var l3 = 0usize
    while page <= last {
        let block_index = (page >> 21usize) & 511usize
        if block_index != current_block {
            let (fresh, l3_error) = clone_l3(a, l2, block_index)
            if l3_error != ok { ret l3_error }
            os.store64(l2 + block_index * 8usize, u64(fresh | TABLE))
            l3 = fresh
            current_block = block_index
        }
        os.store64(l3 + ((page >> 12usize) & 511usize) * 8usize, u64(page | bits))
        page += PAGE
    }
    os.barrier()
    os.tlb_flush()
    ret ok
}

// A word the kernel leaves for a driver thread at `slot` of its aux area, read at
// USER_BASE + AUX_OFF + slot*8 (D2137): a device or DMA address the kernel mapped for it.
fn put_aux(space: Space, slot: usize, value: usize) {
    os.store64(space.region_phys + AUX_OFF + slot * 8usize, u64(value))
}

// (D2162, C110) A shared surface frame: a fixed window near the top of the user gigabyte's level-3
// table (above the 512 KB program window and the thread-stack region), mapped to the SAME physical
// pages in two spaces so an app and the compositor share one surface. 256 KB = a 256x256 BGRA frame.
const SHARED_FRAME_OFFSET: usize = 1835008usize
const SHARED_FRAME_PAGES: usize = 64usize
const SHARED_FRAME_VA: usize = USER_BASE + SHARED_FRAME_OFFSET

// Map `pages` physical pages at `phys` into the address space `ttbr` at the shared-frame VA,
// EL0-RW. Mapping the same `phys` into two spaces gives them a shared surface at SHARED_FRAME_VA.
fn map_phys_at(ttbr: usize, phys: usize, pages: usize) -> err {
    let l1 = ttbr & TABLE_MASK
    let l2 = usize(os.load64(l1 + L1_USER_INDEX * 8usize)) & TABLE_MASK
    let l3 = usize(os.load64(l2)) & TABLE_MASK
    let first = SHARED_FRAME_OFFSET >> 12usize
    let bits = user_page_bits()
    var i = 0usize
    while i < pages {
        os.store64(l3 + (first + i) * 8usize, u64((phys + i * PAGE) | bits))
        i += 1usize
    }
    os.barrier()
    os.tlb_flush()
    ret ok
}

// (D2157) A fresh stack of `pages` pages in the address space `ttbr`, for a thread of
// os.thread_create. The program window fills the level-3 table's low entries (D2168: a variable
// number now, sized to the image); the free entries above it sit in the same 2 MB reach, so a run
// of `pages` of them is backed by new physical pages mapped EL0-RW and the stack's top VA comes
// back. The scan skips the mapped window (non-zero entries), so it works whatever the window size.
// NoSpace when no run that long is free. The stack grows down from the top.
fn map_stack(a: *mem.Arena, ttbr: usize, pages: usize) -> (usize, usize, err) {
    let l1 = ttbr & TABLE_MASK
    let l2 = usize(os.load64(l1 + L1_USER_INDEX * 8usize)) & TABLE_MASK
    let l3 = usize(os.load64(l2)) & TABLE_MASK
    var found = 512usize
    var run_start = 0usize
    var run = 0usize
    var scan = 0usize
    while scan < 512usize && found == 512usize {
        if usize(os.load64(l3 + scan * 8usize)) == 0usize {
            if run == 0usize { run_start = scan }
            run += 1usize
            if run == pages { found = run_start }
        } else {
            run = 0usize
        }
        scan += 1usize
    }
    if found == 512usize { ret (0usize, 0usize, NoSpace) }
    let (bytes, bytes_error) = mem.alloc[u8](a, pages * PAGE + PAGE)
    if bytes_error != ok { ret (0usize, 0usize, bytes_error) }
    let base = (mem.address_of(&bytes[0usize]) + PAGE - 1usize) & ~(PAGE - 1usize)
    let bits = user_page_bits()
    var i = 0usize
    while i < pages {
        os.store64(l3 + (found + i) * 8usize, u64((base + i * PAGE) | bits))
        i += 1usize
    }
    os.barrier()
    os.tlb_flush()
    let stack_va = USER_BASE + found * PAGE
    ret (stack_va, stack_va + pages * PAGE, ok)
}

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
