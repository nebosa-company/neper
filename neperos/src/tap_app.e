// A NeperOS app the launcher starts on a tap (C112, D2178): program 2 of the tap-launch archive. It
// prints a line and exits with code 5, which the launcher reaps before returning Home.
use e.mem
use e.os

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    say("tap app ran\n")
    os.exit(5i32)
    ret ok
}
