// e.gpu's `.Gl` device used from a thread that did not open it (L180, D5897), built with `--gpu glsl`: the GL context lives
// on the device's own thread, so a launch and a download from another thread, and then from the opening one again, answer
// as the CPU backend does. A host without an OpenGL compute device exits 0 having printed why.

use e.gpu
use e.io
use e.mem
use e.os
use e.thread
use x.khronos.compute

@gpu(64)
fn scale(n: u32, k: u32, out: []u32) {
    let i = gpu.gid.x
    if i >= n { ret }
    out[usize(i)] = i *% k +% 17u32
}

const N: usize = 1000usize

type Job = struct { queue: *gpu.Queue, factor: u32, result: []u32, failed: bool }

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
    let (found, found_error) = gpu.devices(a, .Gl, 4usize)
    if found_error != ok || found.len == 0usize {
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
