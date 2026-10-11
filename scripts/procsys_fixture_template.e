// `e.proc.sys`: the /proc text parsers of `e.proc.sys.format` against an independent regex reader
// (scripts/gen_procsys_test.py: canned files and real WSL2 ones), then the live host half by
// shape and self-consistency only -- a figure a host owns is never compared to a constant.
// Every check has its own exit code.
use e.io
use e.mem
use e.os
use e.proc.sys as sys
use e.proc.sys.format as format
use e.str

fn nib(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn token_end(v: str, from: usize) -> usize {
    var i = from
    while v[i] != 32u8 && v[i] != 59u8 { i += 1usize }
    ret i
}

fn number(v: str, from: usize, end: usize) -> u64 {
    var out = 0u64
    var i = from
    while i < end {
        out = out * 10u64 + u64(v[i] - 48u8)
        i += 1usize
    }
    ret out
}

fn unhex(a: *mem.Arena, v: str, from: usize, end: usize) -> str {
    if end - from == 1usize && v[from] == 45u8 { ret "" }
    let count = (end - from) / 2usize
    let (buf, e) = mem.alloc[u8](a, count + 1usize)
    if e != ok { os.exit(80i32) }
    var k = 0usize
    while k < count {
        buf[k] = (nib(v[from + 2usize * k]) << 4u8) | nib(v[from + 2usize * k + 1usize])
        k += 1usize
    }
    ret buf[0usize..count]
}

// 0 when every record of the chunk agrees, else 1 + its index.
fn run_chunk(a: *mem.Arena, v: str) -> u32 {
    var i = 0usize
    var seen = 0u32
    while i < v.len {
        let kind = v[i]
        i += 2usize
        var e = token_end(v, i)
        let src = unhex(a, v, i, e)
        i = e + 1usize
        // the expectation: ERR or a run of numbers (and a hex name for a stat line)
        e = token_end(v, i)
        let failed = v[i] == 69u8
        if kind == 109u8 {
            let (m, me) = format.parse_meminfo(src)
            if failed {
                if me == ok { ret seen + 1u32 }
                i = e + 1usize
            } else {
                var want: [4]u64 = zero
                var k = 0usize
                while k < 4usize {
                    e = token_end(v, i)
                    want[k] = number(v, i, e)
                    i = e + 1usize
                    k += 1usize
                }
                if me != ok || m.total != want[0] || m.available != want[1] || m.swap_total != want[2] || m.swap_free != want[3] { ret seen + 1u32 }
            }
        }
        if kind == 99u8 {
            let (t, ce) = format.parse_cpu_times(src, 100u64)
            let cpus = format.count_cpus(src)
            if failed {
                if ce == ok { ret seen + 1u32 }
                i = e + 1usize
            } else {
                var want: [5]u64 = zero
                var k = 0usize
                while k < 5usize {
                    e = token_end(v, i)
                    want[k] = number(v, i, e)
                    i = e + 1usize
                    k += 1usize
                }
                if ce != ok || t.user_ms != want[0] || t.system_ms != want[1] || t.idle_ms != want[2] || t.iowait_ms != want[3] || u64(cpus) != want[4] { ret seen + 1u32 }
            }
        }
        if kind == 117u8 {
            let (ms, ue) = format.parse_uptime_ms(src)
            if failed {
                if ue == ok { ret seen + 1u32 }
                i = e + 1usize
            } else {
                let want = number(v, i, e)
                i = e + 1usize
                if ue != ok || ms != want { ret seen + 1u32 }
            }
        }
        if kind == 115u8 {
            let (p, se) = format.parse_stat(src)
            if failed {
                if se == ok { ret seen + 1u32 }
                i = e + 1usize
            } else {
                var want: [4]u64 = zero
                var k = 0usize
                while k < 4usize {
                    e = token_end(v, i)
                    want[k] = number(v, i, e)
                    i = e + 1usize
                    k += 1usize
                }
                e = token_end(v, i)
                let name = unhex(a, v, i, e)
                i = e + 1usize
                if se != ok || u64(p.pid) != want[0] || u64(p.parent) != want[1] || u64(p.threads) != want[2] || u64(p.state) != want[3] || !str.eq(p.name, name) { ret seen + 1u32 }
            }
        }
        seen += 1u32
    }
    ret 0u32
}

@CHUNKS@
fn main(a: *mem.Arena, args: []str) -> err {
@CALLS@
    // the live host: shape and self-consistency
    let (cpus, e1) = sys.cpu_count(a)
    if e1 != ok || cpus == 0u32 || cpus > 4096u32 { os.exit(101i32) }
    let (t, e2) = sys.cpu_times(a)
    if e2 != ok || t.user_ms + t.system_ms + t.idle_ms == 0u64 { os.exit(102i32) }
    let (m, e3) = sys.memory(a)
    if e3 != ok || m.total == 0u64 || m.available > m.total || m.swap_free > m.swap_total { os.exit(103i32) }
    let (up, e4) = sys.uptime_ms(a)
    if e4 != ok || up == 0u64 { os.exit(104i32) }
    let (boot, e5) = sys.boot_time(a)
    // after 2001-09-09 and not in the future
    let (now_ns, e6) = os.clock(.Wall)
    if e5 != ok || e6 != ok || boot < 1000000000i64 || boot > now_ns / 1000000000i64 { os.exit(105i32) }
    let (d, e7) = sys.disk_usage(a, ".")
    if e7 != ok || d.total == 0u64 || d.free > d.total || d.used > d.total { os.exit(106i32) }
    let (rss, e8) = sys.self_memory(a)
    if e8 != ok || rss < 65536u64 || rss > m.total { os.exit(107i32) }
    let me = sys.process_id()
    if me == 0u32 { os.exit(108i32) }
    let (list, e9) = sys.processes(a, 8192usize)
    if e9 != ok || list.len == 0usize { os.exit(109i32) }
    var found = false
    var k = 0usize
    while k < list.len {
        if list[k].pid == me {
            found = true
            if list[k].name.len == 0usize || list[k].threads == 0u32 { os.exit(110i32) }
        }
        if list[k].name.len == 0usize { os.exit(111i32) }
        k += 1usize
    }
    if !found { os.exit(112i32) }
    let (_, e10) = sys.disk_usage(a, "no-such-volume-xyz/none")
    if e10 == ok { os.exit(113i32) }
    try io.print("proc sys ok")
    ret ok
}
