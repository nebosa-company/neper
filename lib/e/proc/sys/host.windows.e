// `e.proc.sys`'s host half on Windows: logical processor count, system times, physical
// memory, uptime, volume sizes, a process snapshot and this process's working set, all
// from kernel32. The Linux variant has the same declarations.
//
// ponytail: swap is the pagefile's size and free space as GlobalMemoryStatusEx reports it
// (commit limit less physical), not a per-file perf-counter walk; iowait is always zero.

use e.mem
use e.os
use e.proc.sys.format as format
use e.text.utf8 as utf8

type SystemTimes = struct { idle: u64, kernel: u64, user: u64 }
type MemoryStatus = struct { length: u32, load: u32, total_phys: u64, avail_phys: u64, total_page: u64, avail_page: u64, total_virtual: u64, avail_virtual: u64, avail_extended: u64 }
type ProcessEntry = struct { size: u32, usage: u32, pid: u32, pad0: u32, heap: usize, module: u32, threads: u32, parent: u32, priority: i32, flags: u32, exe: [260]u16, tail: u32 }
type MemoryCounters = struct { size: u32, page_faults: u32, peak_working_set: usize, working_set: usize, quota_peak_paged: usize, quota_paged: usize, quota_peak_nonpaged: usize, quota_nonpaged: usize, pagefile: usize, peak_pagefile: usize }

const SNAPSHOT_PROCESSES: u32 = 2u32
const ALL_GROUPS: u16 = 65535u16
const ENTRY_SIZE: u32 = 568u32

@import("kernel32.dll", "GetActiveProcessorCount")
extern fn raw_processor_count(group: u16) -> u32

@import("kernel32.dll", "GetSystemTimes")
extern fn raw_system_times(idle: *u64, kernel: *u64, user: *u64) -> i32

@import("kernel32.dll", "GlobalMemoryStatusEx")
extern fn raw_memory_status(status: *MemoryStatus) -> i32

@import("kernel32.dll", "GetTickCount64")
extern fn raw_tick_count() -> u64

@import("kernel32.dll", "GetDiskFreeSpaceExW")
extern fn raw_disk_free(path: *u16, caller_free: *u64, total: *u64, total_free: *u64) -> i32

@import("kernel32.dll", "GetCurrentProcessId")
extern fn raw_process_id() -> u32

@import("kernel32.dll", "GetCurrentProcess")
extern fn raw_current_process() -> usize

@import("kernel32.dll", "K32GetProcessMemoryInfo")
extern fn raw_process_memory(process: usize, counters: *MemoryCounters, size: u32) -> i32

@import("kernel32.dll", "CreateToolhelp32Snapshot")
extern fn raw_snapshot(flags: u32, pid: u32) -> usize

@import("kernel32.dll", "Process32FirstW")
extern fn raw_first(snapshot: usize, entry: *ProcessEntry) -> i32

@import("kernel32.dll", "Process32NextW")
extern fn raw_next(snapshot: usize, entry: *ProcessEntry) -> i32

@import("kernel32.dll", "CloseHandle")
extern fn raw_close_handle(handle: usize) -> i32

fn cpu_count(a: *mem.Arena) -> (u32, err) {
    let n = raw_processor_count(ALL_GROUPS)
    if n == 0u32 { ret (0u32, os.Failed) }
    ret (n, ok)
}

fn cpu_times(a: *mem.Arena) -> (format.CpuTimes, err) {
    var t: format.CpuTimes = zero
    var idle = 0u64
    var kernel = 0u64
    var user = 0u64
    if raw_system_times(&idle, &kernel, &user) == 0i32 { ret (t, os.Failed) }
    // FILETIME ticks are 100 ns; the kernel time includes the idle time.
    t.user_ms = user / 10000u64
    t.idle_ms = idle / 10000u64
    t.system_ms = (kernel - idle) / 10000u64
    ret (t, ok)
}

fn memory(a: *mem.Arena) -> (format.MemoryInfo, err) {
    var m: format.MemoryInfo = zero
    var s: MemoryStatus = zero
    s.length = 64u32
    if raw_memory_status(&s) == 0i32 { ret (m, os.Failed) }
    m.total = s.total_phys
    m.available = s.avail_phys
    if s.total_page > s.total_phys {
        m.swap_total = s.total_page - s.total_phys
        m.swap_free = 0u64
        if s.avail_page > s.avail_phys { m.swap_free = s.avail_page - s.avail_phys }
    }
    ret (m, ok)
}

fn uptime_ms(a: *mem.Arena) -> (u64, err) {
    ret (raw_tick_count(), ok)
}

// UTF-8 to NUL-terminated UTF-16 (BMP and surrogate pairs).
fn widen(a: *mem.Arena, s: str) -> ([]u16, err) {
    let (units, units_error) = mem.alloc[u16](a, s.len + 1usize)
    if units_error != ok { ret (units, units_error) }
    var at = 0usize
    var off = 0usize
    while off < s.len {
        let (d, d_error) = utf8.decode(s, off)
        if d_error != ok { ret (units, os.Failed) }
        off += usize(d.width)
        if d.scalar < 65536u32 {
            units[at] = u16(d.scalar)
            at += 1usize
        } else {
            let v = d.scalar - 65536u32
            units[at] = u16(55296u32 + (v >> 10u32))
            units[at + 1usize] = u16(56320u32 + (v & 1023u32))
            at += 2usize
        }
    }
    units[at] = 0u16
    ret (units[0usize..at + 1usize], ok)
}

// (total, free to the caller, used) of the volume holding `path`.
fn disk_usage(a: *mem.Arena, path: str) -> (u64, u64, u64, err) {
    let (wide, we) = widen(a, path)
    if we != ok { ret (0u64, 0u64, 0u64, we) }
    var caller = 0u64
    var total = 0u64
    var free = 0u64
    if raw_disk_free(&wide[0usize], &caller, &total, &free) == 0i32 { ret (0u64, 0u64, 0u64, os.NotFound) }
    ret (total, caller, total - free, ok)
}

fn process_id() -> u32 {
    ret raw_process_id()
}

fn self_memory(a: *mem.Arena) -> (u64, err) {
    var c: MemoryCounters = zero
    c.size = 72u32
    if raw_process_memory(raw_current_process(), &c, 72u32) == 0i32 { ret (0u64, os.Failed) }
    ret (u64(c.working_set), ok)
}

fn narrow(a: *mem.Arena, units: []const u16) -> (str, err) {
    var n = 0usize
    while n < units.len && units[n] != 0u16 { n += 1usize }
    let (out, oe) = mem.alloc[u8](a, n * 3usize + 1usize)
    if oe != ok { ret ("", oe) }
    var at = 0usize
    var i = 0usize
    while i < n {
        var scalar = u32(units[i])
        if scalar >= 55296u32 && scalar < 56320u32 && i + 1usize < n {
            let low = u32(units[i + 1usize])
            if low >= 56320u32 && low < 57344u32 {
                scalar = 65536u32 + ((scalar - 55296u32) << 10u32) + (low - 56320u32)
                i += 1usize
            }
        }
        if scalar >= 55296u32 && scalar < 57344u32 { scalar = 65533u32 }
        let (w, we) = utf8.encode(scalar, out[at..])
        if we != ok { ret ("", we) }
        at += usize(w)
        i += 1usize
    }
    ret (out[0usize..at], ok)
}

// Up to `limit` running processes, the parent and thread counts the snapshot carries.
fn processes(a: *mem.Arena, limit: usize) -> ([]format.ProcessInfo, err) {
    let (out, oe) = mem.alloc[format.ProcessInfo](a, limit + 1usize)
    if oe != ok { ret (out, oe) }
    let snap = raw_snapshot(SNAPSHOT_PROCESSES, 0u32)
    if snap == 0usize || snap == ~0usize { ret (out[0usize..0usize], os.Failed) }
    var entry: ProcessEntry = zero
    entry.size = ENTRY_SIZE
    var n = 0usize
    var more = raw_first(snap, &entry)
    while more != 0i32 && n < limit {
        let (name, ne) = narrow(a, entry.exe[0usize..260usize])
        if ne != ok {
            let c = raw_close_handle(snap)
            ret (out[0usize..n], ne)
        }
        var p: format.ProcessInfo = zero
        p.pid = entry.pid
        p.parent = entry.parent
        p.threads = entry.threads
        p.state = 82u8
        p.name = name
        out[n] = p
        n += 1usize
        more = raw_next(snap, &entry)
    }
    let closed = raw_close_handle(snap)
    ret (out[0usize..n], ok)
}
