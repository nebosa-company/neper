// `e.gpu.cuda`: the driver's device list, whatever this machine has. With no driver the answer is an error from the
// module's own set and nothing is invented; with one, every device has a name, a non-zero memory size, and a key that
// is either valid (not all zero) or marked invalid. Each check has its own exit code.

use e.atomic
use e.gpu.cuda
use e.mem
use e.os
use e.sync

type LoaderRace = struct {
    gate: sync.Semaphore,
    ready: sync.Semaphore,
    release: sync.Semaphore,
    done: sync.Semaphore,
    abort: Atomic[u32],
    answers: [2]Atomic[u32],
}

type LoaderTask = struct { race: *LoaderRace, index: usize }

// Both workers stop immediately before their first call to `cuda.devices`. A machine without a
// driver still takes this path and answers `NoLoader`, while a machine with one races the loader
// and cuInit publication that must be process-wide.
fn enumerate_on_thread(task: *LoaderTask) {
    sync.semaphore_wait(&task.race.gate)
    if atomic.load(&task.race.abort, .Acquire) != 0u32 { ret }
    let waiting = sync.semaphore_post(&task.race.ready, 1u32)
    sync.semaphore_wait(&task.race.release)
    var storage: [4096]u8 = zero
    var a = mem.arena_from(storage[..])
    let (list, list_error) = cuda.devices(&a, 1usize)
    var answer = 0u32
    if list_error == ok && list.len == 1usize { answer = 1u32 }
    if list_error == cuda.NoLoader && list.len == 0usize { answer = 2u32 }
    if list_error == cuda.NoDevice && list.len == 0usize { answer = 3u32 }
    if list_error == cuda.Failed && list.len == 0usize { answer = 4u32 }
    atomic.store(&task.race.answers[task.index], answer, .Release)
    let completed = sync.semaphore_post(&task.race.done, 1u32)
}

fn concurrent_first_enumeration() -> bool {
    var race: LoaderRace = zero
    race.gate = sync.semaphore(0u32)
    race.ready = sync.semaphore(0u32)
    race.release = sync.semaphore(0u32)
    race.done = sync.semaphore(0u32)
    var left = LoaderTask { race: &race, index: 0usize }
    var right = LoaderTask { race: &race, index: 1usize }
    let (first, first_error) = os.thread_create[LoaderTask](enumerate_on_thread, &left, 1048576usize)
    if first_error != ok { ret false }
    let (second, second_error) = os.thread_create[LoaderTask](enumerate_on_thread, &right, 1048576usize)
    if second_error != ok {
        atomic.store(&race.abort, 1u32, .Release)
        let opened = sync.semaphore_post(&race.gate, 1u32)
        let joined = os.thread_join(first)
        ret false
    }
    let opened = sync.semaphore_post(&race.gate, 2u32)
    sync.semaphore_wait(&race.ready)
    sync.semaphore_wait(&race.ready)
    let released = sync.semaphore_post(&race.release, 2u32)
    sync.semaphore_wait(&race.done)
    sync.semaphore_wait(&race.done)
    if os.thread_join(first) != ok || os.thread_join(second) != ok { ret false }
    let left_answer = atomic.load(&race.answers[0usize], .Acquire)
    let right_answer = atomic.load(&race.answers[1usize], .Acquire)
    ret left_answer != 0u32 && left_answer == right_answer
}

fn main(a: *mem.Arena, args: []str) -> err {
    if !concurrent_first_enumeration() { os.exit(20i32) }
    let (list, list_error) = cuda.devices(a, 16usize)
    if list_error != ok {
        // No loader, no device or a failed query: the list is empty.
        if list.len != 0usize { os.exit(1i32) }
        ret ok
    }
    if list.len == 0usize { os.exit(2i32) }
    if list.len > 16usize { os.exit(3i32) }
    var at = 0usize
    while at < list.len {
        let device = list[at]
        if device.name.len == 0usize { os.exit(10i32) }
        if device.memory_bytes == 0u64 { os.exit(11i32) }
        var any = false
        var i = 0usize
        while i < 16usize {
            if device.uuid[i] != 0u8 { any = true }
            i += 1usize
        }
        if device.uuid_valid && !any { os.exit(12i32) }
        at += 1usize
    }
    ret ok
}
