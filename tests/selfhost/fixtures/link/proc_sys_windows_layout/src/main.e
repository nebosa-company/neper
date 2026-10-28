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
    when target.arch == .X86 {
        try io.print("proc entry layout ok\n")
        ret ok
    }
    let (entries, process_error) = host.processes(a, 1024usize)
    if process_error != ok || entries.len == 0usize { os.exit(2i32) }
    try io.print("proc entry layout ok\n")
    ret ok
}
