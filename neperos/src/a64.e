// The aarch64 machine as NeperOS reaches it (D2126): system registers by their
// `op0:op1:CRn:CRm:op2` number -- the one `os.mrs` and `os.msr` take, and the only ones
// the runtime's table lets through, each written as `op0 << 14 | op1 << 11 | CRn << 7 |
// CRm << 3 | op2` -- and the frame an exception arrives with.
use e.os

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
const CNTV_TVAL_EL0: usize = (3usize << 14usize) | (3usize << 11usize) | (14usize << 7usize) | (3usize << 3usize)
const CNTV_CTL_EL0: usize = (3usize << 14usize) | (3usize << 11usize) | (14usize << 7usize) | (3usize << 3usize) | 1usize
const TPIDR_EL0: usize = (3usize << 14usize) | (3usize << 11usize) | (13usize << 7usize) | 2usize
const TPIDR_EL1: usize = (3usize << 14usize) | (13usize << 7usize) | 4usize

// The GICv3 CPU interface, all op0 3 op1 0 (D2127).
const ICC_PMR_EL1: usize = (3usize << 14usize) | (4usize << 7usize) | (6usize << 3usize)
const ICC_BPR1_EL1: usize = (3usize << 14usize) | (12usize << 7usize) | (12usize << 3usize) | 3usize
const ICC_CTLR_EL1: usize = (3usize << 14usize) | (12usize << 7usize) | (12usize << 3usize) | 4usize
const ICC_SRE_EL1: usize = (3usize << 14usize) | (12usize << 7usize) | (12usize << 3usize) | 5usize
const ICC_IGRPEN1_EL1: usize = (3usize << 14usize) | (12usize << 7usize) | (12usize << 3usize) | 7usize
const ICC_IAR1_EL1: usize = (3usize << 14usize) | (12usize << 7usize) | (12usize << 3usize)
const ICC_EOIR1_EL1: usize = (3usize << 14usize) | (12usize << 7usize) | (12usize << 3usize) | 1usize

// What the runtime's vectors save, in its order: x0-x30, SP_EL0, ELR_EL1, SPSR_EL1,
// ESR_EL1, FAR_EL1, the vector's number (0-15) and a word that keeps the frame 16-byte
// aligned. A handler may change any of it; the return restores it.
type Frame = struct { x: [31]u64, sp_el0: u64, elr: u64, spsr: u64, esr: u64, far: u64, kind: u64, pad: u64 }

// ESR_EL1's exception class: a data abort from a lower EL (an EL0 thread), one taken
// without a change of level (the kernel itself), and an SVC from AArch64.
const EC_DATA_ABORT_LOWER: u64 = 36u64
const EC_DATA_ABORT_SAME: u64 = 37u64
const EC_SVC: u64 = 21u64

fn exception_class(esr: u64) -> u64 {
    ret (esr >> 26u64) & 63u64
}

// The vector's number in the frame (runtime order): an IRQ from the kernel (current EL with
// its own stack) is 5, from an EL0 thread 9; a synchronous exception from an EL0 thread is 8.
const VECTOR_IRQ_SAME: u64 = 5u64
const VECTOR_SYNC_LOWER: u64 = 8u64
const VECTOR_IRQ_LOWER: u64 = 9u64

fn is_irq(kind: u64) -> bool {
    ret kind == VECTOR_IRQ_SAME || kind == VECTOR_IRQ_LOWER
}

// DAIF's IRQ mask is bit 7; clearing it lets interrupts reach the core.
const DAIF_IRQ: usize = 128usize

fn enable_irq() {
    os.msr(DAIF, os.mrs(DAIF) & ~DAIF_IRQ)
}

fn disable_irq() {
    os.msr(DAIF, os.mrs(DAIF) | DAIF_IRQ)
}
