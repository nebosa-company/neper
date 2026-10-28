// The text formats `e.proc.sys.host` reads on Linux, as pure parsers over a string already in
// memory: `/proc/meminfo`, the `cpu` lines of `/proc/stat`, `/proc/uptime` and
// `/proc/<pid>/stat`. They live apart from the host half so every platform can check them
// against canned files, and so the Linux variant needs nothing but a reader.
use e.str

type CpuTimes = struct { user_ms: u64, system_ms: u64, idle_ms: u64, iowait_ms: u64 }
type MemoryInfo = struct { total: u64, available: u64, swap_total: u64, swap_free: u64 }
type ProcessInfo = struct { pid: u32, parent: u32, threads: u32, state: u8, name: str }
error Malformed

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

// A decimal at `at` (leading blanks skipped): the value, the index after it, and whether
// there was one.
fn read_number(src: str, at: usize) -> (u64, usize, bool) {
    var i = at
    while i < src.len && (src[i] == 32u8 || src[i] == 9u8) { i += 1usize }
    if i >= src.len || !is_digit(src[i]) { ret (0u64, at, false) }
    var v = 0u64
    while i < src.len && is_digit(src[i]) {
        let digit = u64(src[i] - 48u8)
        if v > (18446744073709551615u64 - digit) / 10u64 { ret (18446744073709551615u64, i, false) }
        v = v * 10u64 + digit
        i += 1usize
    }
    ret (v, i, true)
}

fn line_end(src: str, from: usize) -> usize {
    var i = from
    while i < src.len && src[i] != 10u8 { i += 1usize }
    ret i
}

// The kilobyte count of a `Key:   123 kB` line, in bytes.
fn meminfo_field(src: str, key: str) -> (u64, bool) {
    var at = 0usize
    while at < src.len {
        let end = line_end(src, at)
        if end - at > key.len && str.starts_with(src[at..end], key) {
            let (v, next, found) = read_number(src[0usize..end], at + key.len)
            if !found {
                // A numeric overflow reached a digit, unlike an absent value. `u64` max
                // cannot be a valid whole-kilobyte byte count, so it is an overflow marker.
                if next != at + key.len { ret (18446744073709551615u64, true) }
            } else {
                if v > 18446744073709551615u64 / 1024u64 { ret (18446744073709551615u64, true) }
                ret (v * 1024u64, true)
            }
        }
        at = end + 1usize
    }
    ret (0u64, false)
}

// `available` is MemAvailable where the kernel has it, else free plus buffers and cache.
fn parse_meminfo(src: str) -> (MemoryInfo, err) {
    var m: MemoryInfo = zero
    let (total, has_total) = meminfo_field(src, "MemTotal:")
    if !has_total || total == 18446744073709551615u64 { ret (m, Malformed) }
    m.total = total
    let (avail, has_avail) = meminfo_field(src, "MemAvailable:")
    if has_avail {
        if avail == 18446744073709551615u64 { ret (m, Malformed) }
        m.available = avail
    } else {
        let (free, _) = meminfo_field(src, "MemFree:")
        let (buffers, _) = meminfo_field(src, "Buffers:")
        let (cached, _) = meminfo_field(src, "Cached:")
        if free == 18446744073709551615u64 || buffers == 18446744073709551615u64 || cached == 18446744073709551615u64 { ret (m, Malformed) }
        if free > 18446744073709551615u64 - buffers { ret (m, Malformed) }
        let free_cache = free + buffers
        if free_cache > 18446744073709551615u64 - cached { ret (m, Malformed) }
        m.available = free_cache + cached
    }
    let (swap_total, _) = meminfo_field(src, "SwapTotal:")
    let (swap_free, _) = meminfo_field(src, "SwapFree:")
    if swap_total == 18446744073709551615u64 || swap_free == 18446744073709551615u64 { ret (m, Malformed) }
    m.swap_total = swap_total
    m.swap_free = swap_free
    ret (m, ok)
}

// The aggregate `cpu ` line of `/proc/stat`: user (+nice), system (+irq +softirq), idle and
// iowait, from clock ticks of `1 / hz` second to milliseconds.
fn parse_cpu_times(src: str, hz: u64) -> (CpuTimes, err) {
    var t: CpuTimes = zero
    if hz == 0u64 { ret (t, Malformed) }
    var at = 0usize
    while at < src.len {
        let end = line_end(src, at)
        if str.starts_with(src[at..end], "cpu ") {
            var f: [8]u64 = zero
            var i = at + 4usize
            var k = 0usize
            while k < 8usize {
                let (v, next, found) = read_number(src[0usize..end], i)
                if !found {
                    if next != i { ret (t, Malformed) }
                    break
                }
                f[k] = v
                i = next
                k += 1usize
            }
            if k < 4usize { ret (t, Malformed) }
            if f[0] > 18446744073709551615u64 - f[1] || f[2] > 18446744073709551615u64 - f[5] { ret (t, Malformed) }
            let system_ticks = f[2] + f[5]
            if system_ticks > 18446744073709551615u64 - f[6] { ret (t, Malformed) }
            var ticks: [4]u64 = zero
            ticks[0usize] = f[0] + f[1]
            ticks[1usize] = system_ticks + f[6]
            ticks[2usize] = f[3]
            ticks[3usize] = f[4]
            var milliseconds: [4]u64 = zero
            var field = 0usize
            while field < 4usize {
                // Divide first, then compute the remaining `base * 1000 / hz`
                // bit by bit so no intermediate product can overflow.
                let seconds = ticks[field] / hz
                if seconds > 18446744073709551615u64 / 1000u64 { ret (t, Malformed) }
                let whole = seconds * 1000u64
                let base = ticks[field] % hz
                var remainder = 0u64
                var fraction = 0u64
                var bit = 512u64
                while bit != 0u64 {
                    var carry = 0u64
                    if remainder >= hz - remainder {
                        remainder -= hz - remainder
                        carry = 1u64
                    } else {
                        remainder += remainder
                    }
                    if (1000u64 & bit) != 0u64 {
                        if remainder >= hz - base {
                            remainder -= hz - base
                            carry += 1u64
                        } else {
                            remainder += base
                        }
                    }
                    fraction = fraction * 2u64 + carry
                    bit >>= 1u64
                }
                if fraction > 18446744073709551615u64 - whole { ret (t, Malformed) }
                milliseconds[field] = whole + fraction
                field += 1usize
            }
            t.user_ms = milliseconds[0usize]
            t.system_ms = milliseconds[1usize]
            t.idle_ms = milliseconds[2usize]
            t.iowait_ms = milliseconds[3usize]
            ret (t, ok)
        }
        at = end + 1usize
    }
    ret (t, Malformed)
}

// Lines of `/proc/stat` named `cpu` followed by a number.
fn count_cpus(src: str) -> u32 {
    var n = 0u32
    var at = 0usize
    while at < src.len {
        let end = line_end(src, at)
        if end - at > 3usize && src[at] == 99u8 && src[at + 1usize] == 112u8 && src[at + 2usize] == 117u8 && is_digit(src[at + 3usize]) { n += 1u32 }
        at = end + 1usize
    }
    ret n
}

// `/proc/uptime`: seconds with a fraction, as whole milliseconds.
fn parse_uptime_ms(src: str) -> (u64, err) {
    let (whole, next, found) = read_number(src, 0usize)
    if !found { ret (0u64, Malformed) }
    if whole > 18446744073709551615u64 / 1000u64 { ret (0u64, Malformed) }
    var ms = whole * 1000u64
    if next < src.len && src[next] == 46u8 {
        var scale = 100u64
        var i = next + 1usize
        while i < src.len && is_digit(src[i]) && scale > 0u64 {
            let fractional = u64(src[i] - 48u8) * scale
            if ms > 18446744073709551615u64 - fractional { ret (0u64, Malformed) }
            ms += fractional
            scale = scale / 10u64
            i += 1usize
        }
    }
    ret (ms, ok)
}

// `/proc/<pid>/stat`: `pid (comm) S ppid ...`, the name running to the LAST `)` because a
// command may hold parentheses and spaces itself; thread count is field 20.
fn parse_stat(src: str) -> (ProcessInfo, err) {
    var p: ProcessInfo = zero
    let (pid, after_pid, found) = read_number(src, 0usize)
    if !found { ret (p, Malformed) }
    var open = after_pid
    while open < src.len && src[open] != 40u8 { open += 1usize }
    var close = src.len
    while close > open && src[close - 1usize] != 41u8 { close -= 1usize }
    if open >= src.len || close <= open + 1usize { ret (p, Malformed) }
    close -= 1usize
    p.pid = u32(pid)
    p.name = src[open + 1usize..close]
    var i = close + 1usize
    while i < src.len && src[i] == 32u8 { i += 1usize }
    if i >= src.len { ret (p, Malformed) }
    p.state = src[i]
    i += 1usize
    let (ppid, next, has_ppid) = read_number(src, i)
    if !has_ppid { ret (p, Malformed) }
    p.parent = u32(ppid)
    i = next
    // pgrp .. nice are fields 5..19; num_threads is the 20th.
    var field = 5usize
    while field <= 20usize {
        let (v, n2, got) = read_number(src, i)
        var step = i
        if got {
            step = n2
        } else {
            if n2 != i { ret (p, Malformed) }
            // a negative value (priority, nice): skip a sign and its digits
            while step < src.len && (src[step] == 32u8 || src[step] == 45u8) { step += 1usize }
            while step < src.len && is_digit(src[step]) { step += 1usize }
        }
        if step == i { ret (p, Malformed) }
        if field == 20usize { p.threads = u32(v) }
        i = step
        field += 1usize
    }
    ret (p, ok)
}
