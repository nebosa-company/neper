// PROCESSENTRY32W uses a target-sized ULONG_PTR and has target-specific natural padding.
use e.io
use e.mem
use e.os
use e.proc.sys.host as host

fn main(a: *mem.Arena) -> err {
    var expected = 568usize
    when target.arch == .X86 {
        expected = 556usize
    }
    if mem.size_of[host.ProcessEntry]() != expected { os.exit(1i32) }
    when target.arch == .X86 {
        try io.print("proc entry layout ok\n")
        ret ok
    }
    let (entries, process_error) = host.processes(a, 1024usize)
    if process_error != ok || entries.len == 0usize { os.exit(2i32) }
    try io.print("proc entry layout ok\n")
    ret ok
}
