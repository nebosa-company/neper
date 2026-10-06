// The aarch64 machine as NeperOS reaches it (D2126): system registers by their
// `op0:op1:CRn:CRm:op2` number -- the one `os.mrs` and `os.msr` take, and the only ones
// the runtime's table lets through, each written as `op0 << 14 | op1 << 11 | CRn << 7 |
// CRm << 3 | op2` -- and the frame an exception arrives with.

const MIDR_EL1: usize = (3usize << 14usize)
const MPIDR_EL1: usize = (3usize << 14usize) | 5usize
const ID_AA64PFR0_EL1: usize = (3usize << 14usize) | (4usize << 3usize)
const ID_AA64MMFR0_EL1: usize = (3usize << 14usize) | (7usize << 3usize)
const SCTLR_EL1: usize = (3usize << 14usize) | (1usize << 7usize)
const CPACR_EL1: usize = (3usize << 14usize) | (1usize << 7usize) | 2usize
const TTBR0_EL1: usize = (3usize << 14usize) | (2usize << 7usize)
const TTBR1_EL1: usize = (3usize << 14usize) | (2usize << 7usize) | 1usize
const TCR_EL1: usize = (3usize << 14usize) | (2usize << 7usize) | 2usize
const SPSR_EL1: usize = (3usize << 14usize) | (4usize << 7usize)
const ELR_EL1: usize = (3usize << 14usize) | (4usize << 7usize) | 1usize
const SP_EL0: usize = (3usize << 14usize) | (4usize << 7usize) | (1usize << 3usize)
const CURRENT_EL: usize = (3usize << 14usize) | (4usize << 7usize) | (2usize << 3usize) | 2usize
const ESR_EL1: usize = (3usize << 14usize) | (5usize << 7usize) | (2usize << 3usize)
const FAR_EL1: usize = (3usize << 14usize) | (6usize << 7usize)
const MAIR_EL1: usize = (3usize << 14usize) | (10usize << 7usize) | (2usize << 3usize)
const VBAR_EL1: usize = (3usize << 14usize) | (12usize << 7usize)
const DAIF: usize = (3usize << 14usize) | (3usize << 11usize) | (4usize << 7usize) | (2usize << 3usize) | 1usize
const CNTFRQ_EL0: usize = (3usize << 14usize) | (3usize << 11usize) | (14usize << 7usize)
const CNTVCT_EL0: usize = (3usize << 14usize) | (3usize << 11usize) | (14usize << 7usize) | 2usize

// What the runtime's vectors save, in its order: x0-x30, SP_EL0, ELR_EL1, SPSR_EL1,
// ESR_EL1, FAR_EL1, the vector's number (0-15) and a word that keeps the frame 16-byte
// aligned. A handler may change any of it; the return restores it.
type Frame = struct { x: [31]u64, sp_el0: u64, elr: u64, spsr: u64, esr: u64, far: u64, kind: u64, pad: u64 }

// ESR_EL1's exception class: a data abort taken without a change of level.
const EC_DATA_ABORT_SAME: u64 = 37u64

fn exception_class(esr: u64) -> u64 {
    ret (esr >> 26u64) & 63u64
}
