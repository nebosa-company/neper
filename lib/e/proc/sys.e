// System and process information in the shape of psutil: logical processors, cumulative CPU
// times, physical and swap memory, uptime and boot time, volume usage, the process table
// and this process's resident memory. The per-OS readers are `e.proc.sys.host` (kernel32 on
// Windows, `/proc` and `statfs` on Linux); the Linux text formats are the pure parsers of
// `e.proc.sys.format`. Every figure is a snapshot -- two calls are two readings.
//
// Not here: per-process CPU and memory of another process, open files, connections, network
// interface addresses and counters, sensors, battery, per-CPU times.
use e.mem
use e.os
use e.proc.sys.format as format
use e.proc.sys.host as host

type CpuTimes = struct { user_ms: u64, system_ms: u64, idle_ms: u64, iowait_ms: u64 }
type MemoryInfo = struct { total: u64, available: u64, swap_total: u64, swap_free: u64 }
type DiskUsage = struct { total: u64, free: u64, used: u64 }
type ProcessInfo = struct { pid: u32, parent: u32, threads: u32, state: u8, name: str }

fn cpu_count(a: *mem.Arena) -> (u32, err) {
    let (n, e) = host.cpu_count(a)
    ret (n, e)
}

fn cpu_times(a: *mem.Arena) -> (CpuTimes, err) {
    var out: CpuTimes = zero
    let (t, e) = host.cpu_times(a)
    if e != ok { ret (out, e) }
    out.user_ms = t.user_ms
    out.system_ms = t.system_ms
    out.idle_ms = t.idle_ms
    out.iowait_ms = t.iowait_ms
    ret (out, ok)
}

fn memory(a: *mem.Arena) -> (MemoryInfo, err) {
    var out: MemoryInfo = zero
    let (m, e) = host.memory(a)
    if e != ok { ret (out, e) }
    out.total = m.total
    out.available = m.available
    out.swap_total = m.swap_total
    out.swap_free = m.swap_free
    ret (out, ok)
}

// Milliseconds since the machine started.
fn uptime_ms(a: *mem.Arena) -> (u64, err) {
    let (ms, e) = host.uptime_ms(a)
    ret (ms, e)
}

// Unix time of the last boot, in seconds: the wall clock less the uptime.
fn boot_time(a: *mem.Arena) -> (i64, err) {
    let (up, e) = host.uptime_ms(a)
    if e != ok { ret (0i64, e) }
    let (now, ce) = os.clock(.Wall)
    if ce != ok { ret (0i64, ce) }
    ret ((now - i64(up) * 1000000i64) / 1000000000i64, ok)
}

fn disk_usage(a: *mem.Arena, path: str) -> (DiskUsage, err) {
    var out: DiskUsage = zero
    let (total, free, used, e) = host.disk_usage(a, path)
    if e != ok { ret (out, e) }
    out.total = total
    out.free = free
    out.used = used
    ret (out, ok)
}

fn process_id() -> u32 {
    ret host.process_id()
}

// Resident (Linux) or working-set (Windows) bytes of this process.
fn self_memory(a: *mem.Arena) -> (u64, err) {
    let (n, e) = host.self_memory(a)
    ret (n, e)
}

// Up to `limit` entries of the process table; names borrow from `a`.
fn processes(a: *mem.Arena, limit: usize) -> ([]ProcessInfo, err) {
    let (raw, e) = host.processes(a, limit)
    if e != ok { ret (zero, e) }
    let (out, oe) = mem.alloc[ProcessInfo](a, raw.len + 1usize)
    if oe != ok { ret (zero, oe) }
    var i = 0usize
    while i < raw.len {
        out[i] = ProcessInfo{ pid: raw[i].pid, parent: raw[i].parent, threads: raw[i].threads, state: raw[i].state, name: raw[i].name }
        i += 1usize
    }
    ret (out[0usize..raw.len], ok)
}
