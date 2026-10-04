use e.io
use e.mem
use e.sync
use e.thread

// Returning from main ends the whole program even while another thread is
// blocked (D2113): the Linux startup stub leaves by exit_group, not by the
// single-thread exit that used to keep this process alive forever.
type Blocked = struct { gate: *sync.Mutex }

fn wait_forever(b: *Blocked) {
    sync.mutex_lock(b.gate)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Arena storage, so the detached thread never points into this frame.
    let gates = try mem.alloc[sync.Mutex](a, 1usize)
    gates[0usize] = sync.mutex()
    sync.mutex_lock(&gates[0usize])
    let contexts = try mem.alloc[Blocked](a, 1usize)
    contexts[0usize] = Blocked { gate: &gates[0usize] }
    let (worker, spawn_error) = thread.spawn[Blocked](wait_forever, &contexts[0usize], 65536usize)
    if spawn_error != ok { ret spawn_error }
    // Never joined on purpose: the thread is detached and stays blocked.
    try thread.detach(worker)
    try io.print("main returns with a thread still blocked\n")
    ret ok
}
