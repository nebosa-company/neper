use e.atomic
use e.io
use e.mem
use e.os
use e.sync
use x.khronos.context

type Race = struct {
    ready: sync.Semaphore,
    start: sync.Semaphore,
    entered: sync.Semaphore,
    release: sync.Semaphore,
    dlopen_calls: Atomic[u32],
    publications: Atomic[u32],
    open_ready: Atomic[u32],
    close_ready: Atomic[u32],
    initialized: Atomic[u32],
    completed: Atomic[u32],
    failures: Atomic[u32],
    partial_observers: Atomic[u32],
}
type Caller = struct { race: *Race }

fn increment(value: *Atomic[u32]) {
    while true {
        let current = atomic.load(value, .Acquire)
        let (changed, seen) = atomic.cas(value, current, current + 1u32, .AcqRel, .Acquire)
        if changed { ret }
    }
}

// Simulate dlopen/dlsym while the shared production state machine holds its lease.
fn initialize_fake(race: *Race) -> err {
    increment(&race.dlopen_calls)
    atomic.store(&race.open_ready, 1u32, .Release)
    let notified = sync.semaphore_post(&race.entered, 1u32)
    sync.semaphore_wait(&race.release)
    atomic.store(&race.close_ready, 1u32, .Release)
    atomic.store(&race.initialized, 1u32, .Release)
    ret ok
}

fn call_loader(c: *Caller) {
    let ready = sync.semaphore_post(&c.race.ready, 1u32)
    sync.semaphore_wait(&c.race.start)
    let owner = context.test_begin_xlib_load()
    var result = os.Unsupported
    if owner {
        result = initialize_fake(c.race)
        increment(&c.race.publications)
        context.test_finish_xlib_load(result)
    } else {
        result = ok
    }
    if result != ok {
        increment(&c.race.failures)
    } else if atomic.load(&c.race.initialized, .Acquire) == 0u32 || atomic.load(&c.race.open_ready, .Acquire) == 0u32 || atomic.load(&c.race.close_ready, .Acquire) == 0u32 {
        increment(&c.race.partial_observers)
    }
    increment(&c.race.completed)
}

fn check_loader_race() -> err {
    var race: Race = zero
    race.ready = sync.semaphore(0u32)
    race.start = sync.semaphore(0u32)
    race.entered = sync.semaphore(0u32)
    race.release = sync.semaphore(0u32)
    var first = Caller { race: &race }
    var second = Caller { race: &race }
    let (first_thread, first_error) = os.thread_create[Caller](call_loader, &first, 1048576usize)
    if first_error != ok { ret first_error }
    let (second_thread, second_error) = os.thread_create[Caller](call_loader, &second, 1048576usize)
    if second_error != ok {
        let started = sync.semaphore_post(&race.start, 1u32)
        let released = sync.semaphore_post(&race.release, 1u32)
        let joined = os.thread_join(first_thread)
        ret second_error
    }
    sync.semaphore_wait(&race.ready)
    sync.semaphore_wait(&race.ready)
    let started = sync.semaphore_post(&race.start, 2u32)
    sync.semaphore_wait(&race.entered)
    let waiter_error = context.test_wait_for_xlib_waiter(1000000000i64)
    let no_early_return = atomic.load(&race.completed, .Acquire) == 0u32
    let one_initializer = atomic.load(&race.dlopen_calls, .Acquire) == 1u32
    let partial_table_held = atomic.load(&race.open_ready, .Acquire) == 1u32 && atomic.load(&race.close_ready, .Acquire) == 0u32
    let released = sync.semaphore_post(&race.release, 1u32)
    let first_join = os.thread_join(first_thread)
    let second_join = os.thread_join(second_thread)
    if first_join != ok || second_join != ok { ret os.Failed }
    if waiter_error != ok || !no_early_return || !one_initializer || !partial_table_held { ret os.Failed }
    if atomic.load(&race.failures, .Acquire) != 0u32 { ret os.Failed }
    if atomic.load(&race.partial_observers, .Acquire) != 0u32 { ret os.Failed }
    if atomic.load(&race.completed, .Acquire) != 2u32 { ret os.Failed }
    if atomic.load(&race.publications, .Acquire) != 1u32 { ret os.Failed }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let result = check_loader_race()
    if result != ok { os.exit(1i32) }
    let printed = io.print("xlib loader race ok\n")
    ret ok
}
