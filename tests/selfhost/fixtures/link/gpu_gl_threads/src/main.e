// e.gpu's `.Gl` device used from a thread that did not open it (L180, D5897), built with `--gpu glsl`: the GL context lives
// on the device's own thread, so a launch and a download from another thread, and then from the opening one again, answer
// as the CPU backend does. A host without an OpenGL compute device exits 0 having printed why.

use e.atomic
use e.gpu
use e.io
use e.mem
use e.os
use e.sync
use e.thread
use x.khronos.compute

error Failed

@gpu(64)
fn scale(n: u32, k: u32, out: []u32) {
    let i = gpu.gid.x
    if i >= n { ret }
    out[usize(i)] = i *% k +% 17u32
}

const N: usize = 1000usize

type Job = struct { queue: *gpu.Queue, factor: u32, result: []u32, failed: bool }

// This bypasses context creation so the claim race is checked even on a host without GL.
// Both threads wait behind one gate and keep their claims until the main thread observes them.
type SlotRace = struct { gate: sync.Semaphore, ready: sync.Semaphore, release: sync.Semaphore, abort: Atomic[u32], slots: [2]Atomic[u32] }
type SlotClaim = struct { race: *SlotRace, index: usize }

fn claim_slot(c: *SlotClaim) {
    sync.semaphore_wait(&c.race.gate)
    if atomic.load(&c.race.abort, .Acquire) != 0u32 { ret }
    let at = compute.reserve_worker()
    atomic.store(&c.race.slots[c.index], u32(at) + 1u32, .Release)
    let ready_error = sync.semaphore_post(&c.race.ready, 1u32)
    sync.semaphore_wait(&c.race.release)
    compute.release_worker(at)
}

fn check_worker_slots() -> err {
    var race: SlotRace = zero
    race.gate = sync.semaphore(0u32)
    race.ready = sync.semaphore(0u32)
    race.release = sync.semaphore(0u32)
    var left = SlotClaim { race: &race, index: 0usize }
    var right = SlotClaim { race: &race, index: 1usize }
    let (first, first_error) = os.thread_create[SlotClaim](claim_slot, &left, 1048576usize)
    if first_error != ok { ret first_error }
    let (second, second_error) = os.thread_create[SlotClaim](claim_slot, &right, 1048576usize)
    if second_error != ok {
        atomic.store(&race.abort, 1u32, .Release)
        let opened = sync.semaphore_post(&race.gate, 1u32)
        let joined = os.thread_join(first)
        ret second_error
    }
    let opened = sync.semaphore_post(&race.gate, 2u32)
    sync.semaphore_wait(&race.ready)
    sync.semaphore_wait(&race.ready)
    let first_slot = atomic.load(&race.slots[0usize], .Acquire)
    let second_slot = atomic.load(&race.slots[1usize], .Acquire)
    let released = sync.semaphore_post(&race.release, 2u32)
    if os.thread_join(first) != ok || os.thread_join(second) != ok { ret Failed }
    if first_slot == 0u32 || first_slot == second_slot { ret Failed }
    // Both claims must be reusable: this is also the release path used after a failed open.
    let recycled = compute.reserve_worker()
    if recycled != 0usize { ret Failed }
    compute.release_worker(recycled)
    ret ok
}

fn launch_and_read(job: *Job) {
    let (buffer, buffer_error) = gpu.alloc[u32](job.queue, N)
    if buffer_error != ok {
        job.failed = true
        ret
    }
    if gpu.launch[scale](job.queue, gpu.grid1(N), u32(N), job.factor, buffer) != ok || gpu.download(job.queue, buffer, job.result) != ok { job.failed = true }
    let released = gpu.release(job.queue, buffer)
}

fn main(a: *mem.Arena, args: []str) -> err {
    compute.install()
    if check_worker_slots() != ok { os.exit(1i32) }
    let (found, found_error) = gpu.devices(a, .Gl, 4usize)
    if found_error == gpu.Unsupported {
        let printed = io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    if found_error != ok { os.exit(12i32) }
    if found.len == 0usize {
        let printed = io.print("no OpenGL compute device; nothing checked\n")
        ret ok
    }
    let (device, open_error) = gpu.open(a, .Gl, 0u32)
    if open_error != ok { os.exit(2i32) }
    let (queue, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(3i32) }
    let (first, first_error) = mem.alloc[u32](a, N)
    let (second, second_error) = mem.alloc[u32](a, N)
    if first_error != ok || second_error != ok { os.exit(4i32) }
    // From a thread of its own.
    var job = Job { queue: queue, factor: 2654435761u32, result: first, failed: false }
    let (worker, spawn_error) = thread.spawn[Job](launch_and_read, &job, 1048576usize)
    if spawn_error != ok { os.exit(5i32) }
    if thread.join(worker) != ok { os.exit(6i32) }
    if job.failed { os.exit(7i32) }
    // Then from the thread that opened the device.
    var again = Job { queue: queue, factor: 40503u32, result: second, failed: false }
    launch_and_read(&again)
    if again.failed { os.exit(8i32) }
    var k = 0usize
    while k < N {
        if first[k] != u32(k) *% 2654435761u32 +% 17u32 { os.exit(9i32) }
        if second[k] != u32(k) *% 40503u32 +% 17u32 { os.exit(10i32) }
        k += 1usize
    }
    if gpu.close(device) != ok { os.exit(11i32) }
    let named = io.print("launches from another thread and from the opening one answer on ")
    let device_name = io.print(found[0usize].name)
    let ended = io.print("\n")
    ret ok
}
