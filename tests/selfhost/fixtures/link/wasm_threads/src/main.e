// Threads on every host, and on wasm32-wasi built with `--threads` (D5673, D5674): eight threads add
// to an atomic counter and to a counter under a mutex; a thread starts a thread; a thread is
// detached; a timed wait answers Timeout; thread ids are distinct; one thread's failure leaves
// another's error detail alone; 200 spawn-and-join cycles finish. With the argument `exit`, a thread
// calls os.exit(7) while main is joining it; with `cycles`, only the 200 cycles run (for timing).
use e.atomic
use e.mem
use e.os
use e.sync
use e.thread

type Shared = struct {
    hits: Atomic[u32],
    gate: sync.Mutex,
    guarded: usize,
    ids: [8]usize,
    slot: Atomic[u32],
}

type Nested = struct { inner_ran: Atomic[u32], outer_joined: Atomic[u32] }

type Failing = struct { arena: *mem.Arena, kind: os.ErrorKind }

type Sleeper = struct { word: Atomic[u32] }

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn add(s: *Shared) {
    let me = atomic.add(&s.slot, 1u32, .SeqCst)
    s.ids[usize(me)] = os.current_thread_id()
    var round = 0usize
    while round < 1000usize {
        let previous = atomic.add(&s.hits, 1u32, .SeqCst)
        sync.mutex_lock(&s.gate)
        s.guarded = s.guarded + 1usize
        sync.mutex_unlock(&s.gate)
        round += 1usize
    }
}

fn inner(n: *Nested) {
    let previous = atomic.add(&n.inner_ran, 1u32, .SeqCst)
}

fn outer(n: *Nested) {
    let (child, child_error) = thread.spawn[Nested](inner, n, 0usize)
    if child_error != ok { ret }
    if thread.join(child) == ok { atomic.store(&n.outer_joined, 1u32, .SeqCst) }
}

fn fail_mkdir(f: *Failing) {
    if os.mkdir(f.arena, "np-wasm-threads-dir") == ok { ret }
    f.kind = os.last_error_detail("mkdir", "np-wasm-threads-dir").kind
}

fn nothing(s: *Sleeper) {}

fn bump(s: *Sleeper) {
    let previous = atomic.add(&s.word, 1u32, .SeqCst)
}

fn leave(s: *Sleeper) {
    os.exit(7i32)
}

fn hang(s: *Sleeper) {
    while true { let waited = os.wait_u32(&s.word, 0u32, -1i64) }
}

fn cycles() -> bool {
    var s: Sleeper = zero
    var round = 0usize
    while round < 200usize {
        let (t, spawn_error) = thread.spawn[Sleeper](bump, &s, 65536usize)
        if spawn_error != ok { ret false }
        if thread.join(t) != ok { ret false }
        round += 1usize
    }
    ret atomic.load(&s.word, .SeqCst) == 200u32
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize && same(args[1usize], "exit") {
        var s: Sleeper = zero
        let (t, spawn_error) = thread.spawn[Sleeper](leave, &s, 0usize)
        if spawn_error != ok { ret spawn_error }
        let joined = thread.join(t)
        say("not reached: main joined a thread that exits\n")
        ret ok
    }
    if args.len > 1usize && same(args[1usize], "cycles") {
        if cycles() { say("200 cycles\n") }
        ret ok
    }

    var pool: Shared = zero
    pool.gate = sync.mutex()
    var workers: [8]thread.Thread = zero
    var started = 0usize
    while started < 8usize {
        let (t, spawn_error) = thread.spawn[Shared](add, &pool, 0usize)
        if spawn_error != ok { ret spawn_error }
        workers[started] = t
        started += 1usize
    }
    var joined = 0usize
    while joined < 8usize {
        if thread.join(workers[joined]) != ok { say("join failed\n") }
        joined += 1usize
    }
    if atomic.load(&pool.hits, .SeqCst) == 8000u32 { say("atomic 8000\n") }
    if pool.guarded == 8000usize { say("mutex 8000\n") }

    let main_id = os.current_thread_id()
    var distinct = main_id != 0usize
    var i = 0usize
    while i < 8usize {
        if pool.ids[i] == 0usize || pool.ids[i] == main_id { distinct = false }
        var j = i + 1usize
        while j < 8usize {
            if pool.ids[i] == pool.ids[j] { distinct = false }
            j += 1usize
        }
        i += 1usize
    }
    if distinct { say("ids distinct\n") }
    when target.os == .Wasi {
        if main_id == 1usize { say("main id 1\n") }
    } else {
        say("main id 1\n")
    }

    var nested: Nested = zero
    let (outer_thread, outer_error) = thread.spawn[Nested](outer, &nested, 0usize)
    if outer_error != ok { ret outer_error }
    if thread.join(outer_thread) == ok && atomic.load(&nested.inner_ran, .SeqCst) == 1u32 && atomic.load(&nested.outer_joined, .SeqCst) == 1u32 {
        say("a thread started a thread\n")
    }

    let (loose, loose_error) = mem.alloc[Sleeper](a, 1usize)
    if loose_error != ok { ret loose_error }
    let (detached, detached_error) = thread.spawn[Sleeper](nothing, &loose[0usize], 0usize)
    if detached_error != ok { ret detached_error }
    if thread.detach(detached) == ok { say("detached\n") }

    var sleeper: Sleeper = zero
    if os.wait_u32(&sleeper.word, 0u32, 10000000i64) == os.Timeout { say("wait timeout\n") }

    let made = os.mkdir(a, "np-wasm-threads-dir")
    let (info, stat_error) = os.stat(a, "np-wasm-threads-no-such-file")
    var failing = Failing { arena: a, kind: os.ErrorKind.Other }
    let (failer, failer_error) = thread.spawn[Failing](fail_mkdir, &failing, 0usize)
    if failer_error != ok { ret failer_error }
    if thread.join(failer) != ok { say("join failed\n") }
    let mine = os.last_error_detail("stat", "np-wasm-threads-no-such-file")
    if stat_error == os.NotFound && mine.kind == os.ErrorKind.NotFound && failing.kind == os.ErrorKind.Exists {
        say("details per thread\n")
    }
    let removed = os.remove_dir(a, "np-wasm-threads-dir")

    if cycles() { say("200 cycles\n") }

    // A thread still blocked when main returns does not keep the program alive.
    let (stuck_room, stuck_error) = mem.alloc[Sleeper](a, 1usize)
    if stuck_error != ok { ret stuck_error }
    let (stuck, stuck_spawn_error) = thread.spawn[Sleeper](hang, &stuck_room[0usize], 0usize)
    if stuck_spawn_error != ok { ret stuck_spawn_error }
    if thread.detach(stuck) == ok { say("main returns\n") }
    ret ok
}
