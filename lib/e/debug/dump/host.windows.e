// `e.debug.dump`'s host half on Windows: a minidump through dbghelp's MiniDumpWriteDump,
// and the two facts about this process a caller checks a dump against. The Linux
// variant has the same declarations.

use e.mem
use e.os

error Unsupported
error NotFound
error Failed

// PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, what MiniDumpWriteDump needs of another process.
const DUMP_ACCESS: u32 = 1040u32

@import("dbghelp.dll", "MiniDumpWriteDump")
extern fn raw_write_dump(process: usize, pid: u32, file: usize, kind: u32, exception: usize, user_streams: usize, callback: usize) -> i32

@import("kernel32.dll", "GetCurrentProcess")
extern fn raw_current_process() -> usize

@import("kernel32.dll", "GetCurrentProcessId")
extern fn raw_current_process_id() -> u32

@import("kernel32.dll", "OpenProcess")
extern fn raw_open_process(access: u32, inherit: i32, pid: u32) -> usize

@import("kernel32.dll", "CloseHandle")
extern fn raw_close_handle(handle: usize) -> i32

// A null name asks for the running image.
@import("kernel32.dll", "GetModuleHandleW")
extern fn raw_module_handle(name: usize) -> usize

fn process_id() -> u32 {
    ret raw_current_process_id()
}

// Where this process's executable is loaded.
fn image_base() -> u64 {
    ret u64(raw_module_handle(0usize))
}

// Unsafe for one read: the file's handle, lent to dbghelp for the length of the call.
@unsafe
fn write_minidump(a: *mem.Arena, pid: u32, path: str, flags: u32) -> err {
    var process = raw_current_process()
    var id = raw_current_process_id()
    var opened = false
    if pid != 0u32 && pid != id {
        process = raw_open_process(DUMP_ACCESS, 0i32, pid)
        if process == 0usize { ret NotFound }
        id = pid
        opened = true
    }
    var how: os.OpenFlags = zero
    how.read = true
    how.write = true
    how.create = true
    how.truncate = true
    let (file, open_error) = os.open(a, path, how)
    if open_error != ok {
        if opened { let closed = raw_close_handle(process) }
        ret open_error
    }
    let written = raw_write_dump(process, id, file.raw, flags, 0usize, 0usize, 0usize)
    let close_error = os.close(file)
    if opened { let closed = raw_close_handle(process) }
    if written == 0i32 { ret Failed }
    ret close_error
}

fn write_core(a: *mem.Arena, pid: u32, path: str) -> err {
    ret Unsupported
}
