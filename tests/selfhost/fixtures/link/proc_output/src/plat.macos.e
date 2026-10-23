use e.mem
use e.os

// The BSD `sigaction` call's struct: handler, trampoline, the u32 mask, the u32 flags.
type SignalAction = struct { handler: usize, trampoline: usize, mask: u32, flags: u32 }

fn ignore_gentle_termination() -> bool {
    var action: SignalAction = zero
    action.handler = 1usize // SIG_IGN
    ret os.syscall(
        46usize, // sigaction
        15usize, // SIGTERM
        mem.address_of(&action),
        0usize,
        0usize,
        0usize,
        0usize,
    ) == 0isize
}
