use e.mem
use e.os

// Linux x64 `struct sigaction`: handler, flags, restorer, then the kernel's u64 mask.
type SignalAction = struct { handler: usize, flags: usize, restorer: usize, mask: u64 }

fn ignore_gentle_termination() -> bool {
    var action: SignalAction = zero
    action.handler = 1usize // SIG_IGN
    ret os.syscall(
        13usize, // rt_sigaction
        15usize, // SIGTERM
        mem.address_of(&action),
        0usize,
        8usize,
        0usize,
        0usize,
    ) == 0isize
}
