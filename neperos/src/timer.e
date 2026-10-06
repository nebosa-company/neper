// The Arm generic timer, virtual counter (D2127): the virtual timer PPI (INTID 27) fires
// each time the counter passes the deadline the kernel sets, which drives preemption. The
// frequency is CNTFRQ_EL0; a tick is a fraction of a second of it.
use e.os
use a64

// The virtual timer's PPI.
const INTID: usize = 27usize
// CNTV_CTL_EL0: ENABLE with IMASK clear, so the timer asserts its interrupt.
const ENABLE: usize = 1usize

fn frequency() -> usize {
    ret os.mrs(a64.CNTFRQ_EL0)
}

// The timer armed to fire `ticks_per_second`-th of a second from now, counting the whole
// frequency into a slice so a fast or slow counter keeps the same wall-clock slice.
fn arm(ticks_per_second: usize) {
    os.msr(a64.CNTV_TVAL_EL0, frequency() / ticks_per_second)
    os.msr(a64.CNTV_CTL_EL0, ENABLE)
}

// The next slice; called from the interrupt once the timer has fired.
fn rearm(ticks_per_second: usize) {
    os.msr(a64.CNTV_TVAL_EL0, frequency() / ticks_per_second)
}

fn stop() {
    os.msr(a64.CNTV_CTL_EL0, 0usize)
}
