// A NeperOS program (D2127): the kernel runs it at EL0, once per thread it starts. It
// prints its name and a round number three times, spinning between rounds long enough for
// the timer to hand the processor to another thread, so two of them interleave. If the
// kernel gave it a second argument, it reads that argument's first byte -- the kernel's
// isolation check: for the thread the kernel marks hostile, that argument points into
// kernel memory the thread may not read, so the read must fault and the kernel must end the
// thread before this line prints.
use e.mem
use e.os

// Spins long enough to span several 10 ms timer slices under QEMU.
const SPIN: usize = 30000000usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 0usize { ret mem.Exhausted }
    let name = args[0usize]
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
