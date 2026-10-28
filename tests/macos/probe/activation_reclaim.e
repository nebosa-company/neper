// Finder and URL activation payloads share a 16 KiB buffer.  Polling each
// payload must reclaim that buffer, rather than permanently exhausting it after
// a few normal-sized opens.
use e.mem
use e.os
use e.os.shell

fn main(a: *mem.Arena) -> err {
    if os.cocoa_start() != ok { os.exit(2i32) }
    let (payload, payload_error) = mem.alloc[u8](a, 2048usize)
    if payload_error != ok { os.exit(3i32) }
    var byte = 0usize
    while byte < payload.len {
        payload[byte] = 120u8
        byte += 1usize
    }
    var sent = 0usize
    while sent < 9usize {
        let text = os.cocoa_text(payload[0usize..payload.len])
        shell.act_push(.Url, text)
        os.cf_release(text)
        let (activation, got) = shell.activation_poll()
        if !got || activation.kind != .Url || activation.payload.len != payload.len { os.exit(4i32) }
        sent += 1usize
    }
    ret ok
}
