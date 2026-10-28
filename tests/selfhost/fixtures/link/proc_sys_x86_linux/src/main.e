// Linux i386 must use its own getpid/statfs syscall numbers and `struct statfs`
// layout. Both public calls fail under the x86-64 ABI assumptions this fixture guards.
use e.mem
use e.proc.sys as sys

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    when target.arch == .X86 && target.os == .Linux {
        let pid = sys.process_id()
        // Linux limits pid_max to 4,194,304. An x64 syscall number on i386 becomes
        // a negative errno cast to u32, which is far outside this range.
        if pid == 0u32 || pid > 4194304u32 { ret Failed }
        let (disk, disk_error) = sys.disk_usage(a, ".")
        if disk_error != ok || disk.total == 0u64 || disk.free > disk.total || disk.used > disk.total { ret Failed }
    }
    ret ok
}
