use e.io
use e.mem
use e.os
use e.fs.mmap as mmap
use e.debug.dump

// Print what a crash dump says: the process, the crash if there was one, each
// thread's instruction pointer and the first few modules.
fn summarize(a: *mem.Arena, path: str) -> err {
    let (info, stat_error) = os.stat(a, path)
    if stat_error != ok { ret stat_error }
    // Map it rather than read it: a Linux core holds every mapping, reservations included.
    let mapping = try mmap.open(a, path, false, 0u64, usize(info.size))
    let (d, parse_error) = dump.parse(a, mmap.bytes(mapping))
    if parse_error != ok { ret parse_error }
    if d.kind == .Minidump {
        try io.printf["minidump of pid {}\n"](d.pid)
    } else {
        try io.printf["core of pid {} ({})\n"](d.pid, d.process_name)
    }
    if d.has_crash {
        try io.printf["crashed in thread {} at {x}, code {x}\n"](d.crash_thread, d.crash_registers.rip, d.code)
    }
    var t = 0usize
    while t < d.threads.len {
        try io.printf["thread {}: rip {x} rsp {x}\n"](d.threads[t].id, d.threads[t].registers.rip, d.threads[t].registers.rsp)
        t += 1usize
    }
    var m = 0usize
    while m < d.modules.len && m < 3usize {
        try io.printf["module {x} {}\n"](d.modules[m].base, d.modules[m].name)
        m += 1usize
    }
    try mmap.close(mapping)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len > 1usize { ret summarize(a, args[1usize]) }
    // No argument: dump this very process -- a minidump on Windows, a core on Linux.
    let path = "self.dmp"
    var written = dump.write_minidump(a, 0u32, path, dump.DATA_SEGMENTS)
    if written == dump.Unsupported { written = dump.write_core(a, 0u32, path) }
    if written != ok { ret written }
    ret summarize(a, path)
}
