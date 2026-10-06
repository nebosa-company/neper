// The NeperOS shell init (D2151, C105): program 0 of the initrd archive, the first process the
// kernel runs on `-append shell`. It launches the other two programs from the archive, waits for
// both, and reports their exit codes -- A exits 7, B is killed by a fault -- proving process
// loading, the launch/reap/exit system calls, and that a fault in one process does not stop
// another. Built separately as an `aarch64 neperos` image.
use e.mem
use e.os

// The exit code the kernel gives a process it killed for a fault (thread.FAULT_CODE).
const FAULT_CODE: usize = 18446744073709551615usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
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

fn report(label: str, code: usize) {
    say(label)
    if code == FAULT_CODE {
        say("killed\n")
    } else {
        say("code ")
        say_num(code)
        say("\n")
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    say("shell init up\n")
    let a_child = os.launch(1usize)
    let b_child = os.launch(2usize)
    let a_code = os.reap(a_child)
    let b_code = os.reap(b_child)
    report("shell child A ", a_code)
    report("shell child B ", b_code)
    say("shell init done\n")
    ret ok
}
