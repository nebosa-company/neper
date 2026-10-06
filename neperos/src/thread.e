// The threads and the round-robin scheduler (D2127). Each thread is an EL0 context -- the
// register frame the vectors save and restore, and the address space it runs in. The
// scheduler keeps no run queue beyond the table: it scans from the one that just ran for
// the next ready one, so every ready thread gets a turn. A switch is a frame copy and a
// TTBR0 write; distinct ASIDs mean no TLB flush.
use e.os
use a64
use vm

const MAX_THREADS: usize = 8usize
// No thread is current: the kernel is idle, or the last one exited.
const NONE: usize = 8usize

const FREE: u8 = 0u8
const READY: u8 = 1u8
const RUNNING: u8 = 2u8
const EXITED: u8 = 3u8

type Thread = struct { state: u8, name: str, ttbr: usize, frame: a64.Frame }

var threads: [8]Thread = zero
var current: usize = 8usize
var live: usize = 0usize
// The kernel's own context, captured when the first timer tick leaves the idle loop, so the
// last thread to finish returns the kernel there rather than nowhere.
var idle_frame: a64.Frame = zero

fn running() -> usize {
    ret live
}

fn current_name() -> str {
    if current == NONE { ret "" }
    ret threads[current].name
}

// A ready thread built to enter `space.entry` at EL0 with its stack, arena and argument
// table in the registers the runtime reads, interrupts unmasked so the timer preempts it.
fn add(space: vm.Space, name: str, arg_table: usize, arg_count: usize) -> err {
    var slot = 0usize
    while slot < MAX_THREADS && threads[slot].state != FREE { slot += 1usize }
    if slot == MAX_THREADS { ret vm.NoSpace }
    var frame: a64.Frame = zero
    frame.x[0usize] = u64(arg_table)
    frame.x[1usize] = u64(arg_count)
    frame.x[2usize] = u64(space.arena_addr)
    frame.x[3usize] = u64(space.arena_size)
    frame.sp_el0 = u64(space.stack_top)
    frame.elr = u64(space.entry)
    frame.spsr = 0u64
    threads[slot] = Thread { state: READY, name: name, ttbr: space.ttbr, frame: frame }
    live += 1usize
    ret ok
}

// The next ready thread after `base` loaded into the live exception frame and made current,
// its address space installed. False when none is ready.
fn run_next(base: usize, frame: *a64.Frame) -> bool {
    var found = NONE
    var step = 1usize
    while step <= MAX_THREADS && found == NONE {
        let index = (base + step) % MAX_THREADS
        if threads[index].state == READY { found = index }
        step += 1usize
    }
    if found == NONE {
        current = NONE
        ret false
    }
    threads[found].state = RUNNING
    current = found
    *frame = threads[found].frame
    os.msr(a64.TTBR0_EL1, threads[found].ttbr)
    os.barrier()
    ret true
}

// A timer tick: the running thread saved and set ready, then the next ready one run. From
// idle (no current) it starts the first thread. Always finds one -- the preempted thread
// is ready again -- so it need not report.
fn on_timer(frame: *a64.Frame) {
    if current == NONE {
        idle_frame = *frame
        let started = run_next(MAX_THREADS - 1usize, frame)
        ret
    }
    threads[current].frame = *frame
    if threads[current].state == RUNNING { threads[current].state = READY }
    let switched = run_next(current, frame)
}

// The current thread gave up the rest of its slice.
fn on_yield(frame: *a64.Frame) {
    if current == NONE { ret }
    threads[current].frame = *frame
    if threads[current].state == RUNNING { threads[current].state = READY }
    let switched = run_next(current, frame)
}

// The current thread ended (it exited, or it was killed for a fault). The next ready thread
// is run; when none is left the kernel returns to its idle context, where the boot loop
// sees `running()` reach zero and powers off. True when a thread runs next.
fn finish_current(frame: *a64.Frame) -> bool {
    let gone = current
    threads[gone].state = EXITED
    if live != 0usize { live -= 1usize }
    if run_next(gone, frame) { ret true }
    *frame = idle_frame
    current = NONE
    ret false
}
