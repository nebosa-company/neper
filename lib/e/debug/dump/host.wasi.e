// `e.debug.dump`'s host half on WebAssembly (C182): there is no process to dump and no debugger to
// ask. A minidump is `Unsupported`, as on Linux; a core is `NotFound`, which is what Linux answers when
// `gcore` is not installed (the tool that would write it is not here), and a caller that treats a missing
// tool as "skip" (the fixture does) skips. The declarations are the Linux and Windows variants'.

use e.mem
use e.os

error Unsupported
error NotFound
error Failed

fn process_id() -> u32 { ret 1u32 }

fn image_base() -> u64 { ret 0u64 }

fn write_minidump(a: *mem.Arena, pid: u32, path: str, flags: u32) -> err { ret Unsupported }

fn write_core(a: *mem.Arena, pid: u32, path: str) -> err { ret NotFound }
