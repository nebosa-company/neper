// Win32 ABI layouts use target-sized ULONG_PTR/SIZE_T even though Neper's usize is 64-bit
// on x86. Both public declarations must therefore select the 32-bit fields on that target.
use e.io
use e.mem
use e.os
use e.proc.sys.host as host

fn main(a: *mem.Arena) -> err {
    var expected = 568usize
    var counter_expected = 72usize
    when target.arch == .X86 {
        expected = 556usize
        counter_expected = 40usize
    }
    if mem.size_of[host.ProcessEntry]() != expected { os.exit(1i32) }
    if mem.size_of[host.MemoryCounters]() != counter_expected { os.exit(2i32) }
    if mem.size_of[os.MemoryCounters]() != counter_expected { os.exit(3i32) }
    // Toolhelp reports normal exhaustion with ERROR_NO_MORE_FILES, but another
    // failed enumeration must not become a successful empty process list.
    if !host.toolhelp_finished(0i32, 18u32) || host.toolhelp_finished(0i32, 5u32) || !host.toolhelp_finished(1i32, 5u32) { os.exit(4i32) }
    var invalid: host.ProcessEntry = zero
    invalid.size = u32(mem.size_of[host.ProcessEntry]())
    let first = host.raw_first(0usize, &invalid)
    if first != 0i32 || host.toolhelp_finished(first, host.raw_last_error()) { os.exit(5i32) }
    when target.arch == .X86 {
        try io.print("proc entry layout ok\n")
        ret ok
    }
    let (entries, process_error) = host.processes(a, 1024usize)
    if process_error != ok || entries.len == 0usize { os.exit(2i32) }
    try io.print("proc entry layout ok\n")
    ret ok
}
