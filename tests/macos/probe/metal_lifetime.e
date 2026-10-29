// Repeated capability probes must leave no extra Metal.framework loader references.
// On machines with a device, repeatedly open, allocate, release and close.
use e.mem
use e.os
use e.gpu.metal as metal

fn main(a: *mem.Arena) -> err {
    var probes = 0usize
    var found = false
    while probes < 32usize {
        if metal.available() { found = true }
        probes += 1usize
    }
    if !found { ret ok }
    var opened = 0usize
    while opened < 32usize {
        let (context, open_error) = metal.open(a)
        if open_error != ok { os.exit(2i32) }
        let (allocation, buffer_error) = metal.buffer(context, 64usize)
        if buffer_error != ok { os.exit(3i32) }
        allocation.bytes[0usize] = 23u8
        if allocation.bytes[0usize] != 23u8 { os.exit(4i32) }
        metal.free(allocation)
        metal.close(context)
        opened += 1usize
    }
    ret ok
}
