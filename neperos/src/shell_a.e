// A NeperOS shell program (D2151, C105): program 1 of the initrd archive. It prints a line and
// exits with code 7, which its parent `init` reaps and reports. Built separately as an
// `aarch64 neperos` image and placed in the archive by the fixture.
use e.mem
use e.os

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    say("el0 prog A exit 7\n")
    os.exit(7i32)
    ret ok
}
