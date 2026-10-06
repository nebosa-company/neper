// The GICv3 interrupt controller (Arm IHI 0069), found at /intc@8000000 in the device tree
// (D2127). One core, affinity 0, so the first redistributor frame is this CPU's. The
// distributor routes shared interrupts (SPIs) and the redistributor the private ones
// (PPIs, SGIs); the CPU interface is reached through system registers. NeperOS enables the
// one PPI stage 1 needs, the virtual timer, and acknowledges and ends an interrupt by its
// INTID.
use e.os
use a64
use fdt

error NoController

// Distributor registers.
const GICD_CTLR: usize = 0usize
const GICD_IGROUPR: usize = 128usize
const GICD_ISENABLER: usize = 256usize
const GICD_IPRIORITYR: usize = 1024usize
// GICD_CTLR: affinity routing for the non-secure state, and group 1 non-secure enabled.
const GICD_ARE_NS: u32 = 16u32
const GICD_ENABLE_G1NS: u32 = 2u32
const GICD_RWP: u32 = 2147483648u32

// Redistributor: the RD frame, then the SGI frame 64 KB on.
const GICR_CTLR: usize = 0usize
const GICR_WAKER: usize = 20usize
const GICR_SGI: usize = 65536usize
const GICR_IGROUPR0: usize = 65536usize + 128usize
const GICR_ISENABLER0: usize = 65536usize + 256usize
const GICR_IPRIORITYR: usize = 65536usize + 1024usize
// GICR_WAKER: the core is awake once ProcessorSleep is clear and ChildrenAsleep follows.
const GICR_PROCESSOR_SLEEP: u32 = 2u32
const GICR_CHILDREN_ASLEEP: u32 = 4u32

const ICC_SRE_ENABLE: usize = 1usize
const ICC_IGRPEN1_ENABLE: usize = 1usize
// Every priority below 0xF0 is allowed through; interrupts use 0x80.
const PRIORITY_MASK: usize = 240usize
const PRIORITY: u32 = 128u32
// An acknowledged INTID of 1023 is the spurious one: no interrupt was pending.
const SPURIOUS: usize = 1023usize

type Controller = struct { distributor: usize, redistributor: usize }

fn find(t: fdt.Tree) -> (Controller, err) {
    let (node, node_error) = fdt.find_path(t, "/intc")
    if node_error != ok { ret (zero, NoController) }
    let (distributor, distributor_size, distributor_error) = fdt.region_n(t, node, 0usize)
    if distributor_error != ok { ret (zero, distributor_error) }
    let (redistributor, redistributor_size, redistributor_error) = fdt.region_n(t, node, 1usize)
    if redistributor_error != ok { ret (zero, redistributor_error) }
    ret (Controller { distributor: usize(distributor), redistributor: usize(redistributor) }, ok)
}

fn wait_distributor(gic: Controller) {
    while (os.load32(gic.distributor + GICD_CTLR) & GICD_RWP) != 0u32 {}
}

// The distributor on with affinity routing, this core's redistributor woken, the CPU
// interface's system-register access and group 1 enabled, and the priority mask opened.
fn enable(gic: Controller) {
    os.store32(gic.distributor + GICD_CTLR, GICD_ARE_NS | GICD_ENABLE_G1NS)
    wait_distributor(gic)
    let waker = os.load32(gic.redistributor + GICR_WAKER) & ~GICR_PROCESSOR_SLEEP
    os.store32(gic.redistributor + GICR_WAKER, waker)
    while (os.load32(gic.redistributor + GICR_WAKER) & GICR_CHILDREN_ASLEEP) != 0u32 {}
    os.msr(a64.ICC_SRE_EL1, os.mrs(a64.ICC_SRE_EL1) | ICC_SRE_ENABLE)
    os.barrier()
    os.msr(a64.ICC_PMR_EL1, PRIORITY_MASK)
    os.msr(a64.ICC_BPR1_EL1, 0usize)
    os.msr(a64.ICC_CTLR_EL1, 0usize)
    os.msr(a64.ICC_IGRPEN1_EL1, ICC_IGRPEN1_ENABLE)
    os.barrier()
}

// A private interrupt (a PPI, INTID 16 to 31) enabled in this core's redistributor, as
// group 1 at the common priority. The byte and bit registers are the SGI frame's.
fn enable_private(gic: Controller, intid: usize) {
    let sgi = gic.redistributor
    os.store32(sgi + GICR_IGROUPR0, os.load32(sgi + GICR_IGROUPR0) | u32(1usize << intid))
    let priority_at = sgi + GICR_IPRIORITYR + intid
    os.store8(priority_at, u8(PRIORITY))
    os.store32(sgi + GICR_ISENABLER0, u32(1usize << intid))
    os.barrier()
}

// The pending interrupt's INTID acknowledged; 1023 when none was pending.
fn acknowledge() -> usize {
    ret os.mrs(a64.ICC_IAR1_EL1)
}

fn is_spurious(intid: usize) -> bool {
    ret intid >= SPURIOUS
}

// The interrupt ended: its priority restored so another may preempt.
fn finish(intid: usize) {
    os.msr(a64.ICC_EOIR1_EL1, intid)
}
