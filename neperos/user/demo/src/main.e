// A NeperOS program (D2127, D2128): the kernel runs it at EL0 under one of a few names.
// `S` sends three words over endpoint 0 and `R` receives three and prints each, proving
// synchronous IPC (D2128). Any other name prints its name and a round number three times,
// spinning between rounds so threads interleave under the timer. If the kernel gave the
// thread a second argument, it reads that argument's first byte -- the kernel's isolation
// check: for the hostile thread that argument points into kernel memory it may not read, so
// the read must fault and the kernel must end the thread before this line prints.
use e.mem
use e.os

// Spins long enough to span several 10 ms timer slices under QEMU.
const SPIN: usize = 30000000usize
// The capability slot holding the endpoint the sender and receiver rendezvous on.
const CHANNEL: usize = 1usize
// A slot index past the capability space: "no capability to grant" or "nowhere to receive
// one". Also the console-capability slot G grants and the slot H receives it into.
const NO_SLOT: usize = 99usize
const CONSOLE_SLOT: usize = 0usize
const RECEIVED_SLOT: usize = 5usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn one_char(name: str) -> u8 {
    if name.len == 0usize { ret 0u8 }
    ret name[0usize]
}

// A tag byte, a one-digit number and a space, in one write.
fn say_tag(tag: u8, number: usize) {
    var line: [3]u8 = zero
    line[0usize] = tag
    line[1usize] = u8(number) + 48u8
    line[2usize] = 32u8
    say(line[0usize..3usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 0usize { ret mem.Exhausted }
    let name = args[0usize]
    if one_char(name) == 83u8 {
        var word = 7usize
        while word < 10usize {
            let status = os.send(CHANNEL, word, NO_SLOT)
            word += 1usize
        }
        ret ok
    }
    if one_char(name) == 82u8 {
        var taken = 0usize
        while taken < 3usize {
            say_tag(82u8, os.recv(CHANNEL, NO_SLOT))
            taken += 1usize
        }
        ret ok
    }
    if one_char(name) == 71u8 {
        // G grants its console capability (slot 0) to H over the grant endpoint.
        let status = os.send(CHANNEL, 0usize, CONSOLE_SLOT)
        ret ok
    }
    if one_char(name) == 72u8 {
        // H holds no console capability until it receives one from G; only then may it print.
        let got = os.recv(CHANNEL, RECEIVED_SLOT)
        say("H got console\n")
        ret ok
    }
    if one_char(name) == 68u8 {
        // D is a driver: three times it waits on the notification the timer signals and
        // prints, so a hardware interrupt drives an EL0 thread.
        var seen = 0usize
        while seen < 3usize {
            let bits = os.notify_wait(3usize)
            say_tag(68u8, seen)
            seen += 1usize
        }
        ret ok
    }
    if one_char(name) == 75u8 {
        // K is the console server: it holds the UART device capability (slot 4) and prints
        // for clients. It receives a line a byte at a time until a zero, then writes the
        // whole line to the device in one call -- no other thread reaches the UART.
        var line: [64]u8 = zero
        var length = 0usize
        var open = true
        while open {
            let byte = os.recv(CHANNEL, NO_SLOT)
            if byte == 0usize { open = false } else {
                if length < 64usize {
                    line[length] = u8(byte)
                    length += 1usize
                }
            }
        }
        let written = os.device_write(4usize, mem.address_of(&line[0usize]), length)
        ret ok
    }
    if one_char(name) == 80u8 {
        // P has no console capability; it asks the server to print by sending a line byte by
        // byte over the endpoint, then a zero to end it.
        let message = "console server up\n"
        var at = 0usize
        while at < message.len {
            let sent = os.send(CHANNEL, usize(message[at]), NO_SLOT)
            at += 1usize
        }
        let done = os.send(CHANNEL, 0usize, NO_SLOT)
        ret ok
    }
    if one_char(name) == 85u8 {
        // U retypes endpoints from its untyped capability (slot 5, budget two): the first two
        // succeed and the third is refused, since the kernel allocates nothing beyond the
        // budget.
        let first = os.retype(5usize, 1usize, 6usize)
        let second = os.retype(5usize, 1usize, 7usize)
        let third = os.retype(5usize, 1usize, 3usize)
        if first == 0usize && second == 0usize && third == 18446744073709551615usize { say("U retype ok\n") } else { say("U retype wrong\n") }
        ret ok
    }
    if one_char(name) == 78u8 {
        // No console capability: this write is refused by the kernel.
        say("N should not print\n")
        ret ok
    }
    if one_char(name) == 87u8 {
        // Write through a writable frame capability, then derive a read-only copy, re-protect
        // the page through it, and write again: the second store must fault. The thread is
        // killed before the line below prints.
        let (buffer, buffer_error) = mem.alloc[u8](a, 8usize)
        if buffer_error != ok { ret buffer_error }
        buffer[0usize] = 1u8
        let derived = os.cap_derive(2usize, 3usize, 4usize)
        let protected = os.frame_protect(3usize)
        buffer[0usize] = 2u8
        say("W wrote after protect\n")
        ret ok
    }
    if one_char(name) == 86u8 {
        // Derive a two-link chain from the endpoint capability in slot 1, then revoke the
        // root's derivations. The derived slots must be gone: a receive on one now fails
        // rather than blocking, since the capability it named is revoked.
        let d1 = os.cap_derive(1usize, 2usize, 0usize)
        let d2 = os.cap_derive(2usize, 3usize, 0usize)
        let revoked = os.cap_revoke(1usize)
        let after = os.recv(2usize, NO_SLOT)
        if after == 18446744073709551615usize { say("V revoke ok\n") } else { say("V revoke leaked\n") }
        ret ok
    }
    if one_char(name) == 90u8 {
        // Z proves the EL0 raw-memory intrinsics (D2134): a store, a barrier and a load on its
        // own stack round-trip at EL0, the access a user-mode driver will make to the device
        // MMIO and virtqueue rings the kernel maps into its space.
        var cell: [2]u32 = zero
        let addr = mem.address_of(&cell[0usize])
        os.store32(addr, 1515870810u32)
        os.barrier()
        if os.load32(addr) == 1515870810u32 { say("Z mem ok\n") } else { say("Z mem bad\n") }
        ret ok
    }
    var round = 0usize
    while round < 3usize {
        // One write a round, so a token is never split across a preemption: the name, the
        // round digit, a space.
        var line: [8]u8 = zero
        var at = 0usize
        while at < name.len && at < 6usize {
            line[at] = name[at]
            at += 1usize
        }
        line[at] = u8(round) + 48u8
        line[at + 1usize] = 32u8
        say(line[0usize..at + 2usize])
        var spin = 0usize
        while spin < SPIN { spin += 1usize }
        round += 1usize
    }
    if args.len > 1usize && args[1usize].len != 0usize {
        let first = args[1usize][0usize]
        say(args[0usize])
        if first == 0u8 { say(" read zero from protected memory\n") } else { say(" read protected memory\n") }
    }
    ret ok
}
