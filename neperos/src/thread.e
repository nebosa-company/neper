// The threads and the round-robin scheduler (D2127). Each thread is an EL0 context -- the
// register frame the vectors save and restore, and the address space it runs in. The
// scheduler keeps no run queue beyond the table: it scans from the one that just ran for
// the next ready one, so every ready thread gets a turn. A switch is a frame copy and a
// TTBR0 write; distinct ASIDs mean no TLB flush.
use e.os
use a64
use vm

const MAX_THREADS: usize = 24usize
// No thread is current: the kernel is idle, or the last one exited.
const NONE: usize = 24usize

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
const CAP_NOTIFICATION: u8 = 4u8
// A device: its `object` is the device's MMIO base. The console server holds the one for
// the UART, and reaches it only through the capability (D2128).
const CAP_DEVICE: u8 = 5u8
// Untyped memory: its `object` is how many more objects its holder may retype from it. The
// kernel reserves the object pools at boot and allocates no memory afterward; retype assigns
// a pre-reserved slot and caps it, and an exhausted untyped refuses (D2128).
const CAP_UNTYPED: u8 = 6u8
const RIGHT_SEND: u8 = 1u8
const RIGHT_RECV: u8 = 2u8
const RIGHT_WRITE: u8 = 4u8
const RIGHT_GRANT: u8 = 8u8
type Cap = struct { kind: u8, rights: u8, object: usize, parent: usize }

// (D2151) A process (C105) is a thread with a parent that may reap it: `parent` is the thread
// that launched it (NONE for a boot thread), `exit_code` what it passed to exit or the fault
// sentinel, and `waiting_child` the child it is blocked reaping (NONE otherwise).
// (D2157) `detached` marks a thread (from os.thread_detach) whose slot is freed the moment it
// exits rather than kept for a join -- a thread nobody will reap.
type Thread = struct { state: u8, name: str, ttbr: usize, caps: [8]Cap, frame: a64.Frame, parent: usize, exit_code: usize, waiting_child: usize, detached: usize, window: usize }

// The exit code of a process the kernel killed for a fault, which its parent's reap returns.
const FAULT_CODE: usize = 18446744073709551615usize

// A synchronous IPC endpoint: a queue of threads blocked on it, all senders or all
// receivers, since a sender and a receiver rendezvous rather than both waiting.
const ENDPOINTS: usize = 12usize
const EP_EMPTY: u8 = 0u8
const EP_SENDERS: u8 = 1u8
const EP_RECEIVERS: u8 = 2u8
type Endpoint = struct { kind: u8, waiters: [24]usize, count: usize }
// Endpoints 0 to 3 are the ones the kernel binds at boot; retype hands out the rest.
const FIRST_RETYPED_ENDPOINT: usize = 4usize

// A notification carries asynchronous signals, the kernel's way of handing an interrupt to
// a user-mode driver (D2128): the handler of a bound interrupt signals it, and a thread
// waiting on it wakes with the pending bits. Unlike an endpoint it does not block the
// signaller -- an interrupt cannot wait.
const NOTIFICATIONS: usize = 2usize
type Notification = struct { pending: usize, waiters: [24]usize, count: usize }

var threads: [24]Thread = zero
var endpoints: [12]Endpoint = zero
var notifications: [2]Notification = zero
var current: usize = 24usize
// The next boot-reserved endpoint retype will hand out.
var next_endpoint: usize = 4usize
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
    // The parent is whatever thread is current: none at boot (where `current` is NONE), the
    // launcher under the `launch` system call, so a later `reap` on this child finds its parent.
    threads[slot] = Thread { state: READY, name: name, ttbr: space.ttbr, caps: empty, frame: frame, parent: current, exit_code: 0usize, waiting_child: NONE, detached: 0usize, window: space.size }
    live += 1usize
    ret slot
}

// (D2157) The current thread's address space (its TTBR0), so a new thread of os.thread_create can
// be built in the same space.
fn current_ttbr() -> usize {
    if current == NONE { ret 0usize }
    ret threads[current].ttbr
}

// (D2168) The current thread's EL0 window size in bytes, so a syscall that reads a user slice can
// bound the pointer to what is actually mapped (the window is sized to the program, not fixed).
fn current_window() -> usize {
    if current == NONE { ret 0usize }
    ret threads[current].window
}

// (D2162) A thread's address space, so the compositor boot can map a shared surface frame into both
// the compositor's and an app's space.
fn ttbr_of(index: usize) -> usize {
    if index >= MAX_THREADS { ret 0usize }
    ret threads[index].ttbr
}

// (D2157) A new thread in an existing address space (`ttbr`), for os.thread_create: it enters at
// `elr` with `arg0`/`arg1` in x0/x1 on the stack ending at `stack_top`, its parent the caller so a
// join reaps it. An empty capability space -- a spawned thread prints nothing of its own. The
// index comes back, or MAX_THREADS when the table is full.
fn add_in_space(ttbr: usize, name: str, elr: usize, arg0: usize, arg1: usize, stack_top: usize) -> usize {
    var slot = 0usize
    while slot < MAX_THREADS && threads[slot].state != FREE { slot += 1usize }
    if slot == MAX_THREADS { ret MAX_THREADS }
    var frame: a64.Frame = zero
    frame.x[0usize] = u64(arg0)
    frame.x[1usize] = u64(arg1)
    frame.sp_el0 = u64(stack_top)
    frame.elr = u64(elr)
    frame.spsr = 0u64
    var empty: [8]Cap = zero
    // A spawned thread shares the creating thread's address space, so it shares its window size too.
    var inherited = 0usize
    if current != NONE { inherited = threads[current].window }
    threads[slot] = Thread { state: READY, name: name, ttbr: ttbr, caps: empty, frame: frame, parent: current, exit_code: 0usize, waiting_child: NONE, detached: 0usize, window: inherited }
    live += 1usize
    ret slot
}

// (D2157) `detach(t)` (system call 15): give up the right to join thread `t`. A thread already
// exited is freed now; one still running is marked so it frees itself on exit. x0 is 0, or all-ones
// for a thread that is not the caller's.
fn detach(frame: *a64.Frame) {
    let t = usize(frame.x[0usize])
    if current == NONE || t >= MAX_THREADS || threads[t].parent != current {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    if threads[t].state == EXITED {
        threads[t].state = FREE
    } else {
        threads[t].detached = 1usize
    }
    frame.x[0usize] = 0u64
}

// A capability placed in a thread's space by the kernel (the root of a derivation: no
// parent). `object` is the endpoint index for an endpoint, the page's user VA for a frame.
fn grant(thread_index: usize, cap_slot: usize, kind: u8, rights: u8, object: usize) {
    threads[thread_index].caps[cap_slot] = Cap { kind: kind, rights: rights, object: object, parent: NONE }
}

// The device base the current thread's capability in `cap_slot` names, if it is a device
// capability with the write right.
fn device_base(cap_slot: usize) -> (usize, bool) {
    if current == NONE || cap_slot >= CAPS { ret (0usize, false) }
    let cap = threads[current].caps[cap_slot]
    if cap.kind != CAP_DEVICE || (cap.rights & RIGHT_WRITE) == 0u8 { ret (0usize, false) }
    ret (cap.object, true)
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

// The current thread ended (it exited with `code`, or was killed for a fault with FAULT_CODE).
// Its code is recorded; a parent blocked reaping it is handed the code and made ready, and the
// finished slot freed (D2151). The next ready thread is run; when none is left the kernel returns
// to its idle context, where the boot loop sees `running()` reach zero and powers off. True when
// a thread runs next.
fn finish_current(frame: *a64.Frame, code: usize) -> bool {
    let gone = current
    threads[gone].exit_code = code
    threads[gone].state = EXITED
    if live != 0usize { live -= 1usize }
    // (D2157) A detached thread is reaped by no one, so free its slot at once; otherwise record the
    // code and wake a parent blocked joining it.
    if threads[gone].detached != 0usize {
        threads[gone].state = FREE
    } else {
        wake_reaper(gone)
    }
    if run_next(gone, frame) { ret true }
    *frame = idle_frame
    current = NONE
    ret false
}

// (D2151) If a thread is blocked reaping the just-finished `child`, hand it the child's exit
// code in x0, make it ready, and free the child's slot -- the child has been reaped. A finished
// child whose parent is not yet waiting stays EXITED until a later reap collects it.
fn wake_reaper(child: usize) {
    let parent = threads[child].parent
    if parent >= MAX_THREADS { ret }
    if threads[parent].state == BLOCKED && threads[parent].waiting_child == child {
        threads[parent].frame.x[0usize] = u64(threads[child].exit_code)
        threads[parent].waiting_child = NONE
        threads[parent].state = READY
        threads[child].state = FREE
    }
}

// (D2151) `reap(child) -> code` (system call 12): block until the launched `child` exits and
// return its exit code. A child already exited is collected at once and its slot freed; one not
// yet exited blocks the caller until it does. An index that is not the caller's child gives the
// all-ones sentinel.
fn reap(frame: *a64.Frame) {
    let child = usize(frame.x[0usize])
    if current == NONE || child >= MAX_THREADS || threads[child].parent != current {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    if threads[child].state == EXITED {
        frame.x[0usize] = u64(threads[child].exit_code)
        threads[child].state = FREE
        ret
    }
    threads[current].waiting_child = child
    block_current(frame)
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

// Transfer a capability from a sender to a receiver's destination slot, if the sender's
// endpoint capability (in `sender_ep_slot`) has the grant right, the grant slot holds a
// capability, and the destination slot is valid. The copy is a fresh root in the receiver's
// space (no parent), so the receiver's revoke of it does not reach the sender.
fn transfer_cap(sender: usize, sender_ep_slot: usize, sender_grant_slot: usize, receiver: usize, receiver_dest_slot: usize) {
    if sender_ep_slot >= CAPS || sender_grant_slot >= CAPS || receiver_dest_slot >= CAPS { ret }
    if (threads[sender].caps[sender_ep_slot].rights & RIGHT_GRANT) == 0u8 { ret }
    let granted = threads[sender].caps[sender_grant_slot]
    if granted.kind == CAP_NULL { ret }
    threads[receiver].caps[receiver_dest_slot] = Cap { kind: granted.kind, rights: granted.rights, object: granted.object, parent: NONE }
}

// Synchronous send of one word (x1) over the endpoint capability in slot x0, optionally
// granting the capability in slot x2 when the endpoint capability has the grant right. A
// waiting receiver takes the word and the granted capability and both run on; otherwise the
// sender blocks with them in its saved frame until a receiver arrives. x0 becomes 0, or
// all-ones without a send capability.
fn ipc_send(frame: *a64.Frame) {
    let ep_slot = usize(frame.x[0usize])
    let (ep_id, allowed) = resolve_endpoint(ep_slot, RIGHT_SEND)
    if !allowed {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    if endpoints[ep_id].kind == EP_RECEIVERS && endpoints[ep_id].count != 0usize {
        let receiver = ep_dequeue(ep_id)
        threads[receiver].frame.x[0usize] = frame.x[1usize]
        transfer_cap(current, ep_slot, usize(frame.x[2usize]), receiver, usize(threads[receiver].frame.x[1usize]))
        threads[receiver].state = READY
        frame.x[0usize] = 0u64
        ret
    }
    ep_enqueue(ep_id, current, true)
    block_current(frame)
}

// Synchronous receive over the endpoint capability in slot x0, into x0, with any granted
// capability placed in slot x1. A waiting sender's word and grant are taken and the sender
// runs on; otherwise the receiver blocks until a sender arrives. Without a receive
// capability, x0 is all-ones.
fn ipc_recv(frame: *a64.Frame) {
    let (ep_id, allowed) = resolve_endpoint(usize(frame.x[0usize]), RIGHT_RECV)
    if !allowed {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    let dest = usize(frame.x[1usize])
    if endpoints[ep_id].kind == EP_SENDERS && endpoints[ep_id].count != 0usize {
        let sender = ep_dequeue(ep_id)
        frame.x[0usize] = threads[sender].frame.x[1usize]
        transfer_cap(sender, usize(threads[sender].frame.x[0usize]), usize(threads[sender].frame.x[2usize]), current, dest)
        threads[sender].frame.x[0usize] = 0u64
        threads[sender].state = READY
        ret
    }
    ep_enqueue(ep_id, current, false)
    block_current(frame)
}

// Retype memory from an untyped capability (slot x0) into an object of kind x1, capability
// into slot x2. The untyped's remaining budget bounds how many; each retype assigns one of
// the object slots the kernel reserved at boot, so nothing is allocated now. x0 is 0, or
// all-ones when the untyped is empty, the kind is unsupported, or no slot is left. Only
// endpoints are retypeable here.
fn retype(frame: *a64.Frame) {
    let untyped_slot = usize(frame.x[0usize])
    let kind = u8(frame.x[1usize])
    let dest = usize(frame.x[2usize])
    if current == NONE || untyped_slot >= CAPS || dest >= CAPS {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    if threads[current].caps[untyped_slot].kind != CAP_UNTYPED || threads[current].caps[untyped_slot].object == 0usize {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    if kind != CAP_ENDPOINT || next_endpoint >= ENDPOINTS {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    let ep = next_endpoint
    next_endpoint += 1usize
    endpoints[ep] = Endpoint { kind: EP_EMPTY, waiters: zero, count: 0usize }
    threads[current].caps[dest] = Cap { kind: CAP_ENDPOINT, rights: RIGHT_SEND | RIGHT_RECV, object: ep, parent: NONE }
    threads[current].caps[untyped_slot].object -= 1usize
    frame.x[0usize] = 0u64
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

// Signal a notification (an interrupt arriving): set its pending bits and wake every thread
// waiting on it with those bits. The signaller never blocks. Called from the kernel's
// interrupt handler, so it touches no `current`.
fn signal_notification(nid: usize, bits: usize) {
    if nid >= NOTIFICATIONS { ret }
    notifications[nid].pending = notifications[nid].pending | bits
    if notifications[nid].count == 0usize { ret }
    var i = 0usize
    while i < notifications[nid].count {
        let waiter = notifications[nid].waiters[i]
        threads[waiter].frame.x[0usize] = u64(notifications[nid].pending)
        threads[waiter].state = READY
        i += 1usize
    }
    notifications[nid].count = 0usize
    notifications[nid].pending = 0usize
}

// Wait on the notification capability in slot x0 for its next signal, returning the pending
// bits in x0. Pending bits already set return at once; otherwise the thread blocks. Without
// a notification capability bearing the receive right, x0 is all-ones.
fn notify_wait(frame: *a64.Frame) {
    let slot = usize(frame.x[0usize])
    if current == NONE || slot >= CAPS {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    let cap = threads[current].caps[slot]
    if cap.kind != CAP_NOTIFICATION || (cap.rights & RIGHT_RECV) == 0u8 || cap.object >= NOTIFICATIONS {
        frame.x[0usize] = 18446744073709551615u64
        ret
    }
    let nid = cap.object
    if notifications[nid].pending != 0usize {
        frame.x[0usize] = u64(notifications[nid].pending)
        notifications[nid].pending = 0usize
        ret
    }
    notifications[nid].waiters[notifications[nid].count] = current
    notifications[nid].count += 1usize
    block_current(frame)
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
