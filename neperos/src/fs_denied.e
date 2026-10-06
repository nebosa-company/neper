// A NeperOS client the kernel granted no filesystem capability (D2153, C106): it holds only its
// console, no endpoint. When it tries to send a request on the slot a real client's request
// endpoint would occupy, the kernel finds no endpoint capability there and refuses the send with
// the all-ones sentinel -- the send never reaches the server. This is the capability gate: without
// the endpoint capability a client cannot talk to the filesystem at all.
use e.mem
use e.os
use fsproto

const REQ: usize = 1usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let status = os.send(REQ, fsproto.OP_READ, fsproto.NO_SLOT)
    if status == 18446744073709551615usize { say("fs denied\n") } else { say("fs denied leaked\n") }
    ret ok
}
