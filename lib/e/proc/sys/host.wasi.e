// `e.proc.sys`'s host half on WebAssembly (C182, D5877): the runner answers the /proc texts through
// neper_host `sys_text` (a Linux runner reads the real files, any other composes the same shapes from Node's os
// module), so `e.proc.sys.format` parses them as on Linux. A host without the import (a page) answers ENOSYS and
// each reader says `Unsupported`; the one CPU, the monotonic clock and the memory the module holds stand regardless.
//
// ponytail: the volume is the first preopen's (the module's own directory); the process table is the runner's
// process on a non-Linux host.

use e.mem
use e.os
use e.proc.sys.format as format

@import("neper_host", "sys_text")
extern fn host_sys_text(kind: u32, out: u32, cap: u32, count: u32) -> u32

@import("neper_host", "sys_disk")
extern fn host_sys_disk(dirfd: u32, path: u32, path_len: u32, out: u32, cap: u32, count: u32) -> u32

@import("wasm", "memory.size")
extern fn wasm_memory_size() -> u32

const TEXT_STAT: u32 = 1u32
const TEXT_MEMINFO: u32 = 2u32
const TEXT_UPTIME: u32 = 3u32
const TEXT_PID: u32 = 4u32
const TEXT_PROCESSES: u32 = 5u32
const USER_HZ: u64 = 100u64

fn text(a: *mem.Arena, kind: u32, cap: usize) -> (str, err) {
    let (buf, alloc_error) = mem.alloc[u8](a, cap)
    if alloc_error != ok { ret ("", alloc_error) }
    var count: [1]u32 = zero
    let status = host_sys_text(kind, u32(mem.address_of(&buf[0usize])), u32(cap), u32(mem.address_of(&count[0usize])))
    if status != 0u32 { ret ("", os.Unsupported) }
    ret (buf[0usize..usize(count[0usize])], ok)
}

fn cpu_count(a: *mem.Arena) -> (u32, err) {
    let (src, e) = text(a, TEXT_STAT, 65536usize)
    if e != ok { ret (1u32, ok) }
    let n = format.count_cpus(src)
    if n == 0u32 { ret (1u32, ok) }
    ret (n, ok)
}

fn cpu_times(a: *mem.Arena) -> (format.CpuTimes, err) {
    var none: format.CpuTimes = zero
    let (src, e) = text(a, TEXT_STAT, 65536usize)
    if e != ok { ret (none, e) }
    let (parsed, pe) = format.parse_cpu_times(src, USER_HZ)
    ret (parsed, pe)
}

fn memory(a: *mem.Arena) -> (format.MemoryInfo, err) {
    var none: format.MemoryInfo = zero
    let (src, e) = text(a, TEXT_MEMINFO, 16384usize)
    if e != ok { ret (none, e) }
    let (parsed, pe) = format.parse_meminfo(src)
    ret (parsed, pe)
}

fn uptime_ms(a: *mem.Arena) -> (u64, err) {
    let (src, e) = text(a, TEXT_UPTIME, 256usize)
    if e == ok {
        let (ms, pe) = format.parse_uptime_ms(src)
        ret (ms, pe)
    }
    let (nanoseconds, clock_error) = os.clock(.Monotonic)
    if clock_error != ok { ret (0u64, clock_error) }
    ret (u64(nanoseconds) / 1000000u64, ok)
}

fn disk_usage(a: *mem.Arena, path: str) -> (u64, u64, u64, err) {
    let (_, stat_error) = os.stat(a, path)
    if stat_error != ok { ret (0u64, 0u64, 0u64, stat_error) }
    let (buf, alloc_error) = mem.alloc[u8](a, 96usize)
    if alloc_error != ok { ret (0u64, 0u64, 0u64, alloc_error) }
    var relative = "."
    if path.len > 0usize && path[0usize] != 47u8 { relative = path }
    var count: [1]u32 = zero
    let status = host_sys_disk(3u32, address_of_str(relative), u32(relative.len), u32(mem.address_of(&buf[0usize])), 96u32, u32(mem.address_of(&count[0usize])))
    if status != 0u32 { ret (0u64, 0u64, 0u64, os.Unsupported) }
    // "total free used", decimal
    let reply = buf[0usize..usize(count[0usize])]
    let (total, n1, h1) = format.read_number(reply, 0usize)
    let (free, n2, h2) = format.read_number(reply, n1)
    let (used, n3, h3) = format.read_number(reply, n2)
    if !h1 || !h2 || !h3 { ret (0u64, 0u64, 0u64, format.Malformed) }
    ret (total, free, used, ok)
}

fn process_id() -> u32 {
    var stack: [32]u8 = zero
    var count: [1]u32 = zero
    if host_sys_text(TEXT_PID, u32(mem.address_of(&stack[0usize])), 32u32, u32(mem.address_of(&count[0usize]))) != 0u32 { ret 1u32 }
    let (pid, _, found) = format.read_number(stack[0usize..usize(count[0usize])], 0usize)
    if !found { ret 1u32 }
    ret u32(pid)
}

// The memory the module holds: it never shrinks (os.peak_memory says the same).
fn self_memory(a: *mem.Arena) -> (u64, err) { ret (u64(wasm_memory_size()) * 65536u64, ok) }

fn processes(a: *mem.Arena, limit: usize) -> ([]format.ProcessInfo, err) {
    var none: []format.ProcessInfo = zero
    let (src, e) = text(a, TEXT_PROCESSES, 60000usize)
    if e != ok { ret (none, e) }
    let (out, oe) = mem.alloc[format.ProcessInfo](a, limit + 1usize)
    if oe != ok { ret (none, oe) }
    var n = 0usize
    var at = 0usize
    while at < src.len && n < limit {
        var end = at
        while end < src.len && src[end] != 10u8 { end += 1usize }
        let (p, pe) = format.parse_stat(src[at..end])
        at = end + 1usize
        if pe != ok { continue }
        out[n] = p
        n += 1usize
    }
    ret (out[0usize..n], ok)
}

fn address_of_str(value: str) -> u32 {
    let bytes: []const u8 = value
    ret u32(mem.address_of(&bytes[0usize]))
}
