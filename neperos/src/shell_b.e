// A NeperOS shell program (D2151, C105): program 2 of the initrd archive. It prints a line and
// then stores to address 0, which has no EL0 mapping, so the kernel kills it -- its parent `init`
// reaps the fault sentinel, and A having exited cleanly shows a fault in one process does not
// stop another.
use e.mem
use e.os

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    say("el0 prog B faulting\n")
    os.store8(0usize, 0u8)
    ret ok
}
