// The first translation tables (D2126): an identity map of the 39-bit address space with
// 4 KB granules, so the kernel keeps running at the addresses it was loaded at. A level 1
// table maps each gigabyte as Device memory, except a gigabyte holding RAM, which gets a
// level 2 table of 2 MB blocks: Normal write-back memory where the device tree's RAM is,
// Device memory elsewhere. Device memory is never executable, RAM never at EL0.
use e.mem
use e.os
use a64

// SCTLR_EL1.M still reads clear after `enable`.
error NotEnabled

const PAGE: usize = 4096usize
const GIGABYTE: usize = 1073741824usize
const BLOCK: usize = 2097152usize
// The 39-bit space is 512 gigabytes, one level 1 table.
const GIGABYTES: usize = 512usize

// MAIR_EL1: attribute 1 Device-nGnRE, attribute 2 Normal inner and outer write-back.
const MAIR: usize = (4usize << 8usize) | (255usize << 16usize)
const DESCRIPTOR_BLOCK: usize = 1usize
const DESCRIPTOR_TABLE: usize = 3usize
const ACCESS_FLAG: usize = 1024usize
const INNER_SHAREABLE: usize = 768usize
const PRIVILEGED_EXECUTE_NEVER: usize = 1usize << 53usize
const USER_EXECUTE_NEVER: usize = 1usize << 54usize
const DEVICE: usize = (1usize << 2usize) | ACCESS_FLAG | PRIVILEGED_EXECUTE_NEVER | USER_EXECUTE_NEVER | DESCRIPTOR_BLOCK
const NORMAL: usize = (2usize << 2usize) | ACCESS_FLAG | INNER_SHAREABLE | USER_EXECUTE_NEVER | DESCRIPTOR_BLOCK

// TCR_EL1: T0SZ 25 (39 bits), walks inner and outer write-back write-allocate and inner
// shareable, 4 KB granule, TTBR1 walks off (EPD1); IPS is the CPU's physical range.
const TCR: usize = 25usize | (1usize << 8usize) | (1usize << 10usize) | (3usize << 12usize) | (1usize << 23usize)

// SCTLR_EL1: the MMU (M), the data cache (C) and the instruction cache (I) on; the
// alignment check (A) off, as Normal memory allows unaligned access.
const SCTLR_M: usize = 1usize
const SCTLR_A: usize = 2usize
const SCTLR_C: usize = 4usize
const SCTLR_I: usize = 4096usize

fn overlaps(start: usize, end: usize, ram_start: usize, ram_end: usize) -> bool {
    ret start < ram_end && ram_start < end
}

// The tables from the arena, the map written, and translation turned on.
fn enable(a: *mem.Arena, ram_start: usize, ram_size: usize) -> err {
    let ram_end = ram_start + ram_size
    var tables_needed = 1usize
    var gigabyte = 0usize
    while gigabyte < GIGABYTES {
        if overlaps(gigabyte * GIGABYTE, (gigabyte + 1usize) * GIGABYTE, ram_start, ram_end) { tables_needed += 1usize }
        gigabyte += 1usize
    }
    let (storage, storage_error) = mem.alloc[u8](a, (tables_needed + 1usize) * PAGE)
    if storage_error != ok { ret storage_error }
    let level1 = (mem.address_of(&storage[0usize]) + PAGE - 1usize) & ~(PAGE - 1usize)
    var next_table = level1 + PAGE
    gigabyte = 0usize
    while gigabyte < GIGABYTES {
        let start = gigabyte * GIGABYTE
        if overlaps(start, start + GIGABYTE, ram_start, ram_end) {
            var block = 0usize
            while block < 512usize {
                let address = start + block * BLOCK
                var descriptor = address | DEVICE
                if overlaps(address, address + BLOCK, ram_start, ram_end) { descriptor = address | NORMAL }
                os.store64(next_table + block * 8usize, u64(descriptor))
                block += 1usize
            }
            os.store64(level1 + gigabyte * 8usize, u64(next_table | DESCRIPTOR_TABLE))
            next_table += PAGE
        } else {
            os.store64(level1 + gigabyte * 8usize, u64(start | DEVICE))
        }
        gigabyte += 1usize
    }
    var physical_range = os.mrs(a64.ID_AA64MMFR0_EL1) & 15usize
    if physical_range > 5usize { physical_range = 5usize }
    os.msr(a64.MAIR_EL1, MAIR)
    os.msr(a64.TCR_EL1, TCR | (physical_range << 32usize))
    os.msr(a64.TTBR0_EL1, level1)
    os.barrier()
    os.tlb_flush()
    let control = (os.mrs(a64.SCTLR_EL1) | SCTLR_M | SCTLR_C | SCTLR_I) & ~SCTLR_A
    os.msr(a64.SCTLR_EL1, control)
    os.barrier()
    ret ok
}

fn enabled() -> bool {
    ret (os.mrs(a64.SCTLR_EL1) & SCTLR_M) != 0usize
}
