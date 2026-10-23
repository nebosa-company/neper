// `screen_capture` and `power_inhibit` on a Mac: the main display's size and how many of its pixels are not black, then
// a caffeinate child taken and released.
use e.mem
use e.os
use e.os.shell

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn number(value: usize) {
    if value >= 10usize { number(value / 10usize) }
    var one: [1]u8 = zero
    one[0usize] = u8(48usize + value % 10usize)
    let (written, write_error) = os.write(os.stdout(), one[..])
}

fn main(a: *mem.Arena) -> err {
    let (image, capture_error) = shell.screen_capture(a)
    if capture_error != ok { os.exit(2i32) }
    var lit = 0usize
    var at = 0usize
    while at < image.pixels.len {
        if image.pixels[at] & 16777215u32 != 0u32 { lit += 1usize }
        at += 1usize
    }
    say("capture ")
    number(usize(image.width))
    say("x")
    number(usize(image.height))
    say(" lit ")
    number(lit)
    say("\n")
    if shell.power_inhibit(a, true) != ok { os.exit(3i32) }
    if shell.power_release(a) != ok { os.exit(4i32) }
    if shell.power_release(a) != shell.NotFound { os.exit(5i32) }
    say("power ok\n")
    ret ok
}
