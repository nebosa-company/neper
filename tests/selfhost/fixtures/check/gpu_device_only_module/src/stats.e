// No `use e.gpu`: `info.gpu.barrier_count` reads a field, not a builtin.
type Counters = struct { barrier_count: u32 }
type Info = struct { gpu: Counters }

fn count() -> u32 {
    let info = Info { gpu: Counters { barrier_count: 2u32 } }
    ret info.gpu.barrier_count
}
