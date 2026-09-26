// Schedule perturbation over a program's own threads (D1557, H04): four workers
// that reach a tally only through a data guard, and an atomic counter, each spin a
// seeded pseudo-random 0..63 steps (`thread.perturb_point`) before every step, so
// every seed meets the workers at different points. Under six seeds the program the
// rules accept answers the same: 4 x 3000 on the tally and on the counter. Evidence
// over the runs made, not a proof of every schedule.
use e.atomic
use e.mem
use e.sync
use e.thread

type Tally = struct { hits: i64 }

type Shared = struct { lock: sync.Mutex, tally: Tally, count: Atomic[u64] }

type Worker = struct { pool: *Shared, jitter: thread.Perturb }

fn work(w: *Worker) {
    var step = 0usize
    while step < 3000usize {
        thread.perturb_point(&w.jitter)
        let g = sync.data_guard[Tally](&w.pool.lock, &w.pool.tally)
        if step < 3000usize {
            let t = sync.data_of[Tally](&g)
            t.hits = t.hits + 1i64
        }
        sync.data_release(g)
        thread.perturb_point(&w.jitter)
        let before = atomic.add(&w.pool.count, 1u64, .Relaxed)
        step += 1usize
    }
}

fn round(a: *mem.Arena, seed: u64) -> err {
    let (storage, storage_error) = mem.alloc[Shared](a, 1usize)
    if storage_error != ok { ret storage_error }
    var fresh: Shared = zero
    fresh.lock = sync.mutex()
    storage[0usize] = fresh
    let (workers, workers_error) = mem.alloc[Worker](a, 4usize)
    if workers_error != ok { ret workers_error }
    var at = 0usize
    while at < 4usize {
        workers[at] = Worker { pool: &storage[0usize], jitter: thread.perturb(seed * 16u64 + u64(at) + 1u64, 64u32) }
        at += 1usize
    }
    let (group, started) = thread.spawn_all[Worker](a, work, workers, 262144usize)
    if started != ok { ret started }
    try thread.join_all(group)
    if storage[0usize].tally.hits != 12000i64 { ret mem.Exhausted }
    if atomic.load(&storage[0usize].count, .Relaxed) != 12000u64 { ret mem.Exhausted }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var seed = 1u64
    while seed <= 6u64 {
        try round(a, seed)
        seed += 1u64
    }
    ret ok
}
