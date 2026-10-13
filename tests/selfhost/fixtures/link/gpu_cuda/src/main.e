// `e.gpu.cuda`: the driver's device list, whatever this machine has. With no driver the answer is an error from the
// module's own set and nothing is invented; with one, every device has a name, a non-zero memory size, and a key that
// is either valid (not all zero) or marked invalid. Each check has its own exit code.

use e.gpu.cuda
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    let (list, list_error) = cuda.devices(a, 16usize)
    if list_error != ok {
        // No loader, no device or a failed query: the list is empty.
        if list.len != 0usize { os.exit(1i32) }
        ret ok
    }
    if list.len == 0usize { os.exit(2i32) }
    if list.len > 16usize { os.exit(3i32) }
    var at = 0usize
    while at < list.len {
        let device = list[at]
        if device.name.len == 0usize { os.exit(10i32) }
        if device.memory_bytes == 0u64 { os.exit(11i32) }
        var any = false
        var i = 0usize
        while i < 16usize {
            if device.uuid[i] != 0u8 { any = true }
            i += 1usize
        }
        if device.uuid_valid && !any { os.exit(12i32) }
        at += 1usize
    }
    ret ok
}
