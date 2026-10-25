// `e.proc.sys`'s host half on WebAssembly (C182): a module sees no process table, memory accounting or disks,
// so each reader answers `Unsupported`, except the one CPU, the monotonic clock and the process id.

use e.mem
use e.os
use e.proc.sys.format as format

fn cpu_count(a: *mem.Arena) -> (u32, err) { ret (1u32, ok) }
fn cpu_times(a: *mem.Arena) -> (format.CpuTimes, err) {
    var none: format.CpuTimes = zero
    ret (none, os.Unsupported)
}
fn memory(a: *mem.Arena) -> (format.MemoryInfo, err) {
    var none: format.MemoryInfo = zero
    ret (none, os.Unsupported)
}
fn uptime_ms(a: *mem.Arena) -> (u64, err) {
    let (nanoseconds, clock_error) = os.clock(.Monotonic)
    if clock_error != ok { ret (0u64, clock_error) }
    ret (u64(nanoseconds) / 1000000u64, ok)
}
fn disk_usage(a: *mem.Arena, path: str) -> (u64, u64, u64, err) { ret (0u64, 0u64, 0u64, os.Unsupported) }
fn process_id() -> u32 { ret 1u32 }
fn self_memory(a: *mem.Arena) -> (u64, err) { ret (0u64, os.Unsupported) }
fn processes(a: *mem.Arena, limit: usize) -> ([]format.ProcessInfo, err) {
    var none: []format.ProcessInfo = zero
    ret (none, os.Unsupported)
}
