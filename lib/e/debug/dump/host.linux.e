// `e.debug.dump`'s host half on Linux: an ELF core of a live process through gdb's
// `gcore`, and the two facts about this process a caller checks a dump against. The
// Windows variant has the same declarations.
//
// ponytail: `write_core` runs gdb's `gcore` rather than writing PT_NOTE/PT_LOAD itself
// from /proc/<pid>/maps and /proc/<pid>/mem; a missing gcore is `NotFound`. Writing the
// core in-process is the upgrade when a host without gdb needs one.
// ponytail: `image_base` answers zero here; a static neper executable is found by name
// among the core's NT_FILE mappings instead.

use e.mem
use e.os
use e.proc
use e.str

error Unsupported
error NotFound
error Failed

const SYS_GETPID: usize = 39usize
const SYS_PRCTL: usize = 157usize
// PR_SET_PTRACER, and PR_SET_PTRACER_ANY: under Yama's ptrace_scope 1 only an ancestor
// may attach, and gcore's gdb is this process's grandchild.
const PR_SET_PTRACER: usize = 1499557217usize

fn process_id() -> u32 {
    ret u32(os.syscall(SYS_GETPID, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize))
}

fn image_base() -> u64 {
    ret 0u64
}

fn write_minidump(a: *mem.Arena, pid: u32, path: str, flags: u32) -> err {
    ret Unsupported
}

fn write_core(a: *mem.Arena, pid: u32, path: str) -> err {
    var at = 0usize
    while at < path.len {
        // The path is quoted for the shell with single quotes.
        if path[at] == 39u8 { ret Failed }
        at += 1usize
    }
    var id = pid
    let own = process_id()
    if id == 0u32 { id = own }
    let (b0, builder_error) = str.builder(a, path.len * 2usize + 160usize)
    if builder_error != ok { ret builder_error }
    var b = b0
    try str.push(&b, "command -v gcore >/dev/null 2>&1 || exit 127; gcore -o '")
    try str.push(&b, path)
    try str.push(&b, "' ")
    try str.push_u32(&b, id)
    try str.push(&b, " >/dev/null 2>&1 && mv '")
    try str.push(&b, path)
    try str.push(&b, ".")
    try str.push_u32(&b, id)
    try str.push(&b, "' '")
    try str.push(&b, path)
    try str.push(&b, "'")
    let script = str.done(&b)
    var args: [2]str = zero
    args[0usize] = "-c"
    args[1usize] = script
    var command: proc.Command = zero
    command.program = "/bin/sh"
    command.args = args[..]
    command.inherit_env = true
    if id == own { let allowed = os.syscall(SYS_PRCTL, PR_SET_PTRACER, ~0usize, 0usize, 0usize, 0usize, 0usize) }
    var streams: proc.Streams = zero
    let (child0, spawn_error) = proc.spawn(a, command, streams)
    if spawn_error != ok { ret spawn_error }
    var child = child0
    let (status, wait_error) = proc.wait(&child)
    if id == own { let reset = os.syscall(SYS_PRCTL, PR_SET_PTRACER, 0usize, 0usize, 0usize, 0usize, 0usize) }
    if wait_error != ok { ret wait_error }
    if status == 127i32 { ret NotFound }
    if status != 0i32 { ret Failed }
    ret ok
}
