// A NeperOS filesystem client (D2153, C106): an EL0 process with no block capability. It holds only
// the two endpoints the kernel granted it -- requests out on slot 1, replies in on slot 2 -- and
// drives the filesystem server over IPC (fsproto.e). Its argument chooses the scenario: a name
// beginning `w` writes (mkdir, write, open, close, then lists), anything else reads back what a
// previous boot wrote and then removes it. The last request is quit, so the server exits and, with
// every process gone, the kernel powers off. Writing on one boot and reading on the next over the
// same disk image proves the filesystem persists through the server.
use e.mem
use e.os
use fsproto

const REQ: usize = 1usize
const REP: usize = 2usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

// Report a one-word result reply as ok or err after `label`.
fn report(label: str) {
    let result = os.recv(REP, fsproto.NO_SLOT)
    say(label)
    if result == fsproto.RESULT_OK { say(" ok\n") } else { say(" err\n") }
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 0usize { ret mem.Exhausted }
    let write_mode = args[0usize].len != 0usize && args[0usize][0usize] == 119u8
    var buffer: [512]u8 = zero
    let buffer_addr = mem.address_of(&buffer[0usize])
    if write_mode {
        let mkdir_op = os.send(REQ, fsproto.OP_MKDIR, fsproto.NO_SLOT)
        fsproto.send_str(REQ, "/docs")
        report("fs client mkdir /docs")
        let write_op = os.send(REQ, fsproto.OP_WRITE, fsproto.NO_SLOT)
        fsproto.send_str(REQ, "/docs/greeting")
        fsproto.send_str(REQ, "hello neperos fs\n")
        report("fs client write /docs/greeting")
        let open_op = os.send(REQ, fsproto.OP_OPEN, fsproto.NO_SLOT)
        fsproto.send_str(REQ, "/docs/greeting")
        let open_result = os.recv(REP, fsproto.NO_SLOT)
        let open_size = os.recv(REP, fsproto.NO_SLOT)
        say("fs client open /docs/greeting size ")
        say_num(open_size)
        say("\n")
        let close_op = os.send(REQ, fsproto.OP_CLOSE, fsproto.NO_SLOT)
        fsproto.send_str(REQ, "/docs/greeting")
        report("fs client close /docs/greeting")
        list("/docs")
        list("/")
    } else {
        let read_op = os.send(REQ, fsproto.OP_READ, fsproto.NO_SLOT)
        fsproto.send_str(REQ, "/docs/greeting")
        let read_result = os.recv(REP, fsproto.NO_SLOT)
        let count = fsproto.recv_bytes(REP, buffer_addr, 512usize)
        say("fs client read: ")
        say(buffer[0usize..count])
        let remove_op = os.send(REQ, fsproto.OP_REMOVE, fsproto.NO_SLOT)
        fsproto.send_str(REQ, "/docs/greeting")
        report("fs client remove /docs/greeting")
        list("/docs")
    }
    let quit_op = os.send(REQ, fsproto.OP_QUIT, fsproto.NO_SLOT)
    ret ok
}

fn say_num(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    say(digits[at..20usize])
}

// Ask the server to list `path` and print the newline-separated names it returns.
fn list(path: str) {
    var names: [512]u8 = zero
    let names_addr = mem.address_of(&names[0usize])
    let list_op = os.send(REQ, fsproto.OP_LIST, fsproto.NO_SLOT)
    fsproto.send_str(REQ, path)
    let result = os.recv(REP, fsproto.NO_SLOT)
    let count = fsproto.recv_bytes(REP, names_addr, 512usize)
    say("fs client list ")
    say(path)
    say(":\n")
    say(names[0usize..count])
}
