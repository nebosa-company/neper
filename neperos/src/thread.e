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
// Waiting to rendezvous on an endpoint (D2128): not runnable until a partner arrives.
const BLOCKED: u8 = 4u8

// A capability is the only handle to a kernel object (D2128): without one in its own
// capability space, a thread cannot name an endpoint, the console or a frame. `object` is
// the kernel index the capability grants, and `parent` the slot it was derived from (or
// NONE), so a revoke walks the derivations. Rights are ANDed down on each derivation.
const CAPS: usize = 8usize
const CAP_NULL: u8 = 0u8
const CAP_ENDPOINT: u8 = 1u8
const CAP_CONSOLE: u8 = 2u8
const CAP_FRAME: u8 = 3u8
const RIGHT_SEND: u8 = 1u8
const RIGHT_RECV: u8 = 2u8
const RIGHT_WRITE: u8 = 4u8
const RIGHT_GRANT: u8 = 8u8
type Cap = struct { kind: u8, rights: u8, object: usize, parent: usize }

type Thread = struct { state: u8, name: str, ttbr: usize, caps: [8]Cap, frame: a64.Frame }

// A synchronous IPC endpoint: a queue of threads blocked on it, all senders or all
// receivers, since a sender and a receiver rendezvous rather than both waiting.
const ENDPOINTS: usize = 4usize
const EP_EMPTY: u8 = 0u8
const EP_SENDERS: u8 = 1u8
const EP_RECEIVERS: u8 = 2u8
type Endpoint = struct { kind: u8, waiters: [8]usize, count: usize }

var threads: [8]Thread = zero
var endpoints: [4]Endpoint = zero
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
// Its capability space is empty; the kernel grants what it should hold. The thread's index
// comes back so the kernel can, or MAX_THREADS when the table is full.
fn add(space: vm.Space, name: str, arg_table: usize, arg_count: usize) -> usize {
    var slot = 0usize
    while slot < MAX_THREADS && threads[slot].state != FREE { slot += 1usize }
    if slot == MAX_THREADS { ret MAX_THREADS }
    var frame: a64.Frame = zero
    frame.x[0usize] = u64(arg_table)
    frame.x[1usize] = u64(arg_count)
    frame.x[2usize] = u64(space.arena_addr)
    frame.x[3usize] = u64(space.arena_size)
    frame.sp_el0 = u64(space.stack_top)
    frame.elr = u64(space.entry)
    frame.spsr = 0u64
    var empty: [8]Cap = zero
    threads[slot] = Thread { state: READY, name: name, ttbr: space.ttbr, caps: empty, frame: frame }
    live += 1usize
    ret slot
}

// A capability placed in a thread's space by the kernel (the root of a derivation: no
// parent). `object` is the endpoint index for an endpoint, the page's user VA for a frame.
fn grant(thread_index: usize, cap_slot: usize, kind: u8, rights: u8, object: usize) {
    threads[thread_index].caps[cap_slot] = Cap { kind: kind, rights: rights, object: object, parent: NONE }
}

// Whether the current thread holds a capability of `kind` with `right` in its space.
fn current_holds(kind: u8, right: u8) -> bool {
    if current == NONE { ret false }
    var slot = 0usize
    while slot < CAPS {
        let cap = threads[current].caps[slot]
        if cap.kind == kind && (cap.rights & right) != 0u8 { ret true }
        slot += 1usize
    }
    ret false
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

// The current thread is set blocked and the next ready one run; with none ready the kernel
// idles until an interrupt or a rendezvous readies someone.
fn block_current(frame: *a64.Frame) {
    threads[current].frame = *frame
    threads[current].state = BLOCKED
    let gone = current
    if run_next(gone, frame) { ret }
    *frame = idle_frame
    current = NONE
}

fn ep_enqueue(ep_id: usize, who: usize, senders: bool) {
    if senders { endpoints[ep_id].kind = EP_SENDERS } else { endpoints[ep_id].kind = EP_RECEIVERS }
    endpoints[ep_id].waiters[endpoints[ep_id].count] = who
    endpoints[ep_id].count += 1usize
}

fn ep_dequeue(ep_id: usize) -> usize {
    let who = endpoints[ep_id].waiters[0usize]
    var i = 1usize
    while i < endpoints[ep_id].count {
        endpoints[ep_id].waiters[i - 1usize] = endpoints[ep_id].waiters[i]
        i += 1usize
    }
    endpoints[ep_id].count -= 1usize
    if endpoints[ep_id].count == 0usize { endpoints[ep_id].kind = EP_EMPTY }
    ret who
}

// The endpoint a capability slot names, if the current thread holds an endpoint capability
// there with `right`. An invalid slot or a capability without the right gives false.
fn resolve_endpoint(cap_slot: usize, right: u8) -> (usize, bool) {
    if current == NONE || cap_slot >= CAPS { ret (0usize, false) }
    let cap = threads[current].caps[cap_slot]
    if cap.kind != CAP_ENDPOINT || (cap.rights & right) == 0u8 { ret (0usize, false) }
    if cap.object >= ENDPOINTS { ret (0usize, false) }
    ret (cap.object, true)
}

// Synchronous send of one word (x1) over the endpoint capability in slot x0. A waiting
// receiver takes it and both run on; otherwise the sender blocks with the word in its saved
// frame until a receiver arrives. x0 becomes 0 on success, or all-ones without a send
// capability.
fn ipc_send(frame: *a64.Frame) {
    let (ep_id, allowed) = resolve_endpoint(usize(frame.x[0usize]), RIGHT_SEND)
    if !allowed {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    if endpoints[ep_id].kind == EP_RECEIVERS && endpoints[ep_id].count != 0usize {
        let receiver = ep_dequeue(ep_id)
        threads[receiver].frame.x[0usize] = frame.x[1usize]
        threads[receiver].state = READY
        frame.x[0usize] = 0u64
        ret
    }
    ep_enqueue(ep_id, current, true)
    block_current(frame)
}

// Synchronous receive over the endpoint capability in slot x0, into x0. A waiting sender's
// word is taken and the sender runs on; otherwise the receiver blocks until a sender
// arrives. Without a receive capability, x0 is all-ones.
fn ipc_recv(frame: *a64.Frame) {
    let (ep_id, allowed) = resolve_endpoint(usize(frame.x[0usize]), RIGHT_RECV)
    if !allowed {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    if endpoints[ep_id].kind == EP_SENDERS && endpoints[ep_id].count != 0usize {
        let sender = ep_dequeue(ep_id)
        frame.x[0usize] = threads[sender].frame.x[1usize]
        threads[sender].frame.x[0usize] = 0u64
        threads[sender].state = READY
        ret
    }
    ep_enqueue(ep_id, current, false)
    block_current(frame)
}

// Re-protect the page a frame capability (slot x0) names according to its write right: with
// the right the page is writable, without it read-only, so a store through a frame capability
// derived without the write right faults. x0 is 0, or all-ones without a frame capability.
fn frame_protect(frame: *a64.Frame) {
    let slot = usize(frame.x[0usize])
    if current == NONE || slot >= CAPS {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    let cap = threads[current].caps[slot]
    if cap.kind != CAP_FRAME {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    vm.protect(threads[current].ttbr, cap.object, (cap.rights & RIGHT_WRITE) != 0u8)
    frame.x[0usize] = 0u64
}

// Is the capability in `slot` derived, directly or through a chain, from `ancestor`? The
// chain is at most CAPS long, so a corrupt cycle cannot loop forever.
fn derived_from(slot: usize, ancestor: usize) -> bool {
    var parent = threads[current].caps[slot].parent
    var steps = 0usize
    while parent != NONE && steps < CAPS {
        if parent == ancestor { ret true }
        parent = threads[current].caps[parent].parent
        steps += 1usize
    }
    ret false
}

// Derive a weaker capability (x0 source slot, x1 destination slot, x2 rights to drop) into
// the current thread's space: a copy of the source with those rights cleared and the source
// recorded as its parent, so a revoke of the source reaches it. x0 is 0, or all-ones for a
// bad slot or an empty source.
fn cap_derive(frame: *a64.Frame) {
    let src = usize(frame.x[0usize])
    let dst = usize(frame.x[1usize])
    let drop = u8(frame.x[2usize])
    if current == NONE || src >= CAPS || dst >= CAPS || src == dst {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    let source = threads[current].caps[src]
    if source.kind == CAP_NULL {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    threads[current].caps[dst] = Cap { kind: source.kind, rights: source.rights & ~drop, object: source.object, parent: src }
    frame.x[0usize] = 0u64
}

// Revoke every capability derived from the one in slot x0, directly or transitively, in the
// current thread's space. The slot itself is kept; its derivations are nulled. x0 is 0, or
// all-ones for a bad slot.
fn cap_revoke(frame: *a64.Frame) {
    let slot = usize(frame.x[0usize])
    if current == NONE || slot >= CAPS {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    var i = 0usize
    while i < CAPS {
        if i != slot && derived_from(i, slot) {
            threads[current].caps[i] = Cap { kind: CAP_NULL, rights: 0u8, object: 0usize, parent: NONE }
        }
        i += 1usize
    }
    frame.x[0usize] = 0u64
}
