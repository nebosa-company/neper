// `e.proc.sys`'s host half on Linux: everything is a `/proc` file read whole and handed to
// `e.proc.sys.format`, except the volume sizes, which are one `statfs`. The Windows variant
// has the same declarations.
//
// ponytail: `statfs` is syscall 137 as on x86-64 (the aarch64 number is 43); USER_HZ is 100;
// /proc is assumed mounted. A container's cgroup limits are not applied to memory.

use e.mem
use e.os
use e.proc.sys.format as format
use e.str

const SYS_STATFS: usize = 137usize
const USER_HZ: u64 = 100u64

// A file read whole, at most `cap` bytes.
fn read_small(a: *mem.Arena, path: str, cap: usize) -> (str, err) {
    var flags: os.OpenFlags = zero
    flags.read = true
    let (f, open_error) = os.open(a, path, flags)
    if open_error != ok { ret ("", open_error) }
    let (buf, alloc_error) = mem.alloc[u8](a, cap)
    if alloc_error != ok {
        let closed = os.close(f)
        ret ("", alloc_error)
    }
    var n = 0usize
    while n < cap {
        let (got, read_error) = os.read(f, buf[n..cap])
        if read_error != ok {
            let closed = os.close(f)
            ret ("", read_error)
        }
        if got == 0usize { break }
        n += got
    }
    let closed = os.close(f)
    ret (buf[0usize..n], ok)
}

fn cpu_count(a: *mem.Arena) -> (u32, err) {
    let (src, e) = read_small(a, "/proc/stat", 262144usize)
    if e != ok { ret (0u32, e) }
    let n = format.count_cpus(src)
    if n == 0u32 { ret (0u32, format.Malformed) }
    ret (n, ok)
}

fn cpu_times(a: *mem.Arena) -> (format.CpuTimes, err) {
    var t: format.CpuTimes = zero
    let (src, e) = read_small(a, "/proc/stat", 262144usize)
    if e != ok { ret (t, e) }
    let (parsed, pe) = format.parse_cpu_times(src, USER_HZ)
    ret (parsed, pe)
}

fn memory(a: *mem.Arena) -> (format.MemoryInfo, err) {
    var m: format.MemoryInfo = zero
    let (src, e) = read_small(a, "/proc/meminfo", 16384usize)
    if e != ok { ret (m, e) }
    let (parsed, pe) = format.parse_meminfo(src)
    ret (parsed, pe)
}

fn uptime_ms(a: *mem.Arena) -> (u64, err) {
    let (src, e) = read_small(a, "/proc/uptime", 256usize)
    if e != ok { ret (0u64, e) }
    let (ms, pe) = format.parse_uptime_ms(src)
    ret (ms, pe)
}

fn le64(b: []const u8, at: usize) -> u64 {
    var v = 0u64
    var i = 8usize
    while i > 0usize {
        i -= 1usize
        v = (v << 8u64) | u64(b[at + i])
    }
    ret v
}

// (total, free to an unprivileged caller, used) of the filesystem holding `path`.
fn disk_usage(a: *mem.Arena, path: str) -> (u64, u64, u64, err) {
    let (z, ze) = mem.alloc[u8](a, path.len + 1usize)
    if ze != ok { ret (0u64, 0u64, 0u64, ze) }
    var i = 0usize
    while i < path.len {
        z[i] = path[i]
        i += 1usize
    }
    z[path.len] = 0u8
    var info: [128]u8 = zero
    let r = os.syscall(SYS_STATFS, mem.address_of(&z[0usize]), mem.address_of(&info[0usize]), 0usize, 0usize, 0usize, 0usize)
    if r != 0isize { ret (0u64, 0u64, 0u64, os.NotFound) }
    let unit = le64(info[0usize..128usize], 8usize)
    let blocks = le64(info[0usize..128usize], 16usize)
    let free_all = le64(info[0usize..128usize], 24usize)
    let free_user = le64(info[0usize..128usize], 32usize)
    ret (blocks * unit, free_user * unit, (blocks - free_all) * unit, ok)
}

fn process_id() -> u32 {
    ret u32(os.syscall(39usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize))
}

fn self_memory(a: *mem.Arena) -> (u64, err) {
    let (src, e) = read_small(a, "/proc/self/statm", 256usize)
    if e != ok { ret (0u64, e) }
    let (size, next, found) = format.read_number(src, 0usize)
    if !found { ret (0u64, format.Malformed) }
    let (resident, _, has) = format.read_number(src, next)
    if !has { ret (0u64, format.Malformed) }
    ret (resident * u64(os.page_size()), ok)
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

// Up to `limit` processes: every numeric directory of /proc whose stat file parses.
fn processes(a: *mem.Arena, limit: usize) -> ([]format.ProcessInfo, err) {
    let (out, oe) = mem.alloc[format.ProcessInfo](a, limit + 1usize)
    if oe != ok { ret (out, oe) }
    let (entries, re) = os.readdir(a, "/proc")
    if re != ok { ret (out[0usize..0usize], re) }
    var n = 0usize
    var i = 0usize
    while i < entries.len && n < limit {
        let name = entries[i].name
        i += 1usize
        if !all_digits(name) { continue }
        let (b0, be) = str.builder(a, name.len + 24usize)
        if be != ok { ret (out[0usize..n], be) }
        var b = b0
        try str.push(&b, "/proc/")
        try str.push(&b, name)
        try str.push(&b, "/stat")
        let path = str.done(&b)
        let (src, fe) = read_small(a, path, 2048usize)
        if fe != ok { continue }
        let (p, pe) = format.parse_stat(src)
        if pe != ok { continue }
        out[n] = p
        n += 1usize
    }
    ret (out[0usize..n], ok)
}
