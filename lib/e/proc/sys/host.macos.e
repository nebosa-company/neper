// `e.proc.sys`'s host half on macOS: sysctlbyname and the Mach host statistics for the
// CPU and memory figures, statfs for the volume, clock_gettime(CLOCK_MONOTONIC) for
// uptime, getrusage(RUSAGE_SELF) for this process's resident peak, and
// proc_listpids/proc_pidinfo for the process table. The declarations match
// host.linux.e and host.windows.e; `e.proc.sys.format` needs no change.
//
// USER_HZ is the Mach tick base (100) the host_cpu_load_info counters use here; memory
// page counts come from HOST_VM_INFO64 with hw.pagesize. A sandbox that hides other
// processes gets a shorter table, not a failure.
use e.mem
use e.os
use e.proc.sys.format as format
use e.str

const USER_HZ: u64 = 100u64
const HOST_VM_INFO64: i32 = 4i32
const HOST_CPU_LOAD_INFO: i32 = 3i32
const PROC_ALL_PIDS: u32 = 1u32
const PROC_PIDTBSDINFO: i32 = 3i32
const PROC_PIDTASKINFO: i32 = 4i32
const PROC_PIDTBSDINFO_SIZE: usize = 136usize
const PROC_PIDTASKINFO_SIZE: usize = 96usize

@import("c", "sysctlbyname")
extern fn raw_sysctl(name: *const u8, oldp: usize, oldlenp: *usize, newp: usize, newlen: usize) -> i32

@import("c", "mach_host_self")
extern fn raw_mach_host_self() -> u32

@import("c", "host_statistics64")
extern fn raw_host_statistics64(host: u32, flavor: i32, info: usize, count: *u32) -> i32

@import("c", "statfs")
extern fn raw_statfs(path: *const u8, info: usize) -> i32

@import("c", "clock_gettime")
extern fn raw_clock_gettime(clock: i32, at: usize) -> i32

@import("c", "getpid")
extern fn raw_getpid() -> i32

@import("c", "getrusage")
extern fn raw_getrusage(who: i32, usage: usize) -> i32

@import("c", "proc_listpids")
extern fn raw_proc_listpids(kind: u32, typeinfo: u32, buffer: usize, size: u32) -> i32

@import("c", "proc_pidinfo")
extern fn raw_proc_pidinfo(pid: i32, flavor: i32, arg: u64, buffer: usize, size: i32) -> i32

fn cstr(a: *mem.Arena, text: str) -> ([]u8, err) {
    let (buf, e) = mem.alloc[u8](a, text.len + 1usize)
    if e != ok { ret (buf, e) }
    var i = 0usize
    while i < text.len {
        buf[i] = text[i]
        i += 1usize
    }
    buf[text.len] = 0u8
    ret (buf, ok)
}

fn sysctl_u64(a: *mem.Arena, name: str) -> (u64, err) {
    let (key, ke) = cstr(a, name)
    if ke != ok { ret (0u64, ke) }
    var value: [8]u8 = zero
    var length = 8usize
    let status = raw_sysctl(&key[0usize], mem.address_of(&value[0usize]), &length, 0usize, 0usize)
    if status != 0i32 { ret (0u64, os.from_errno(isize(status))) }
    if length >= 8usize { ret (read_u64(value[0usize..8usize], 0usize), ok) }
    ret (0u64, format.Malformed)
}

fn read_u64(b: []const u8, at: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        v = v | (u64(b[at + i]) << u32(i * 8usize))
        i += 1usize
    }
    ret v
}

fn read_u32(b: []const u8, at: usize) -> u32 {
    ret u32(b[at]) | (u32(b[at + 1usize]) << 8u32) | (u32(b[at + 2usize]) << 16u32) | (u32(b[at + 3usize]) << 24u32)
}

fn read_i32(b: []const u8, at: usize) -> i32 { ret i32(read_u32(b, at)) }

fn cpu_count(a: *mem.Arena) -> (u32, err) {
    let (n, e) = sysctl_u64(a, "hw.logicalcpu")
    if e != ok { ret (0u32, e) }
    if n == 0u64 { ret (0u32, format.Malformed) }
    ret (u32(n), ok)
}

// host_cpu_load_info: four natural_t counters user, system, idle, nice, in Mach ticks.
fn cpu_times(a: *mem.Arena) -> (format.CpuTimes, err) {
    var t: format.CpuTimes = zero
    var info: [16]u8 = zero
    var count = 4u32
    let status = raw_host_statistics64(raw_mach_host_self(), HOST_CPU_LOAD_INFO, mem.address_of(&info[0usize]), &count)
    if status != 0i32 { ret (t, os.from_errno(isize(status))) }
    let tick_ms = 1000u64 / USER_HZ
    t.user_ms = u64(read_u32(info[0usize..16usize], 0usize)) * tick_ms
    t.system_ms = u64(read_u32(info[0usize..16usize], 4usize)) * tick_ms
    t.idle_ms = u64(read_u32(info[0usize..16usize], 8usize)) * tick_ms
    t.iowait_ms = 0u64
    ret (t, ok)
}

// vm_statistics64 begins with the page counts; free + inactive is the caller's headroom.
fn memory(a: *mem.Arena) -> (format.MemoryInfo, err) {
    var m: format.MemoryInfo = zero
    let (total, te) = sysctl_u64(a, "hw.memsize")
    if te != ok { ret (m, te) }
    m.total = total
    let (page, pe) = sysctl_u64(a, "hw.pagesize")
    if pe != ok { ret (m, pe) }
    var stats: [128]u8 = zero
    var count = 32u32
    let status = raw_host_statistics64(raw_mach_host_self(), HOST_VM_INFO64, mem.address_of(&stats[0usize]), &count)
    if status == 0i32 {
        let free_pages = u64(read_u32(stats[0usize..128usize], 0usize))
        let inactive = u64(read_u32(stats[0usize..128usize], 8usize))
        m.available = (free_pages + inactive) * page
    }
    // vm.swapusage: xsw_usage { total u64, avail u64, ... }.
    let (swap_key, ske) = cstr(a, "vm.swapusage")
    if ske == ok {
        var swap: [32]u8 = zero
        var swap_len = 32usize
        if raw_sysctl(&swap_key[0usize], mem.address_of(&swap[0usize]), &swap_len, 0usize, 0usize) == 0i32 && swap_len >= 16usize {
            m.swap_total = read_u64(swap[0usize..32usize], 0usize)
            m.swap_free = read_u64(swap[0usize..32usize], 8usize)
        }
    }
    ret (m, ok)
}

fn uptime_ms(a: *mem.Arena) -> (u64, err) {
    var at: [16]u8 = zero
    // CLOCK_MONOTONIC on Darwin counts from boot.
    let status = raw_clock_gettime(6i32, mem.address_of(&at[0usize]))
    if status != 0i32 { ret (0u64, os.from_errno(isize(status))) }
    let seconds = read_u64(at[0usize..16usize], 0usize)
    let nanos = u64(read_u32(at[0usize..16usize], 8usize))
    ret (seconds * 1000u64 + nanos / 1000000u64, ok)
}

fn le64(b: []const u8, at: usize) -> u64 { ret read_u64(b, at) }

// macOS `struct statfs`: int32 f_bsize at 0, int32 f_iosize at 4, then uint64
// f_blocks/f_bfree/f_bavail at 8/16/24.
fn disk_usage(a: *mem.Arena, path: str) -> (u64, u64, u64, err) {
    var index = 0usize
    while index < path.len {
        if path[index] == 0u8 { ret (0u64, 0u64, 0u64, os.Failed) }
        index += 1usize
    }
    let (z, ze) = cstr(a, path)
    if ze != ok { ret (0u64, 0u64, 0u64, ze) }
    var info: [128]u8 = zero
    let status = raw_statfs(&z[0usize], mem.address_of(&info[0usize]))
    if status != 0i32 { ret (0u64, 0u64, 0u64, os.from_errno(isize(status))) }
    let unit = u64(read_u32(info[0usize..128usize], 0usize))
    let blocks = le64(info[0usize..128usize], 8usize)
    let free_all = le64(info[0usize..128usize], 16usize)
    let free_user = le64(info[0usize..128usize], 24usize)
    ret (blocks * unit, free_user * unit, (blocks - free_all) * unit, ok)
}

fn process_id() -> u32 {
    let pid = raw_getpid()
    if pid <= 0i32 { ret 0u32 }
    ret u32(pid)
}

// getrusage(RUSAGE_SELF): ru_maxrss is the 8-byte word after the two timevals, and
// Darwin reports it in bytes where Linux counts kilobytes.
fn self_memory(a: *mem.Arena) -> (u64, err) {
    var usage: [144]u8 = zero
    let status = raw_getrusage(0i32, mem.address_of(&usage[0usize]))
    if status != 0i32 { ret (0u64, os.from_errno(isize(status))) }
    ret (le64(usage[0usize..144usize], 32usize), ok)
}

fn all_digits(s: str) -> bool {
    if s.len == 0usize { ret false }
    var i = 0usize
    while i < s.len {
        if !format.is_digit(s[i]) { ret false }
        i += 1usize
    }
    ret true
}

// proc_listpids(PROC_ALL_PIDS) and proc_pidinfo: PROC_PIDTBSDINFO gives pid/ppid and
// the 16-byte comm, PROC_PIDTASKINFO the thread count. Unreadable rows are skipped.
fn processes(a: *mem.Arena, limit: usize) -> ([]format.ProcessInfo, err) {
    var empty: []format.ProcessInfo = zero
    if limit == 18446744073709551615usize { ret (empty, os.OutOfMemory) }
    let capacity = limit + 1usize
    let (out, out_error) = mem.alloc[format.ProcessInfo](a, capacity)
    if out_error != ok { ret (empty, out_error) }
    // One i32 pid per entry, plus room for the kernel's own extra count.
    let bytes = u32(capacity * 4usize + 4096usize)
    let (pids, pids_error) = mem.alloc[u8](a, usize(bytes))
    if pids_error != ok { ret (empty, pids_error) }
    let listed = raw_proc_listpids(PROC_ALL_PIDS, 0u32, mem.address_of(&pids[0usize]), bytes)
    if listed <= 0i32 { ret (empty, ok) }
    var count = usize(listed) / 4usize
    if count > limit { count = limit }
    let (names, names_error) = mem.alloc[u8](a, count * 17usize)
    if names_error != ok { ret (empty, names_error) }
    var n = 0usize
    var i = 0usize
    while i < count {
        let pid = read_i32(pids[0usize..usize(bytes)], i * 4usize)
        i += 1usize
        if pid <= 0i32 { continue }
        var info: [PROC_PIDTBSDINFO_SIZE]u8 = zero
        let got = raw_proc_pidinfo(pid, PROC_PIDTBSDINFO, 0u64, mem.address_of(&info[0usize]), i32(PROC_PIDTBSDINFO_SIZE))
        if got != i32(PROC_PIDTBSDINFO_SIZE) { continue }
        let ppid = read_u32(info[0usize..PROC_PIDTBSDINFO_SIZE], 16usize)
        let status = read_u32(info[0usize..PROC_PIDTBSDINFO_SIZE], 4usize)
        var name_len = 0usize
        while name_len < 16usize && info[48usize + name_len] != 0u8 { name_len += 1usize }
        var threads = 1u32
        var task: [PROC_PIDTASKINFO_SIZE]u8 = zero
        let task_got = raw_proc_pidinfo(pid, PROC_PIDTASKINFO, 0u64, mem.address_of(&task[0usize]), i32(PROC_PIDTASKINFO_SIZE))
        if task_got == i32(PROC_PIDTASKINFO_SIZE) { threads = u32(read_i32(task[0usize..PROC_PIDTASKINFO_SIZE], 88usize)) }
        let name_at = n * 17usize
        var k = 0usize
        while k < name_len {
            names[name_at + k] = info[48usize + k]
            k += 1usize
        }
        out[n] = format.ProcessInfo { pid: u32(pid), parent: ppid, threads: threads, state: u8(status), name: names[name_at..name_at + name_len] }
        n += 1usize
        if n >= limit { break }
    }
    ret (out[0usize..n], ok)
}

