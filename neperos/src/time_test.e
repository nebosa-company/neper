// A NeperOS program that reads the clock through e.time (C107, D2155): it takes two monotonic
// readings around a busy spin and reports that time advanced, then reads the wall clock. e.time
// reaches the portable `os.clock` intrinsic, lowered on NeperOS to a kernel system call that reads
// the virtual counter (monotonic) or the PL031 RTC (wall). Started as program 0 of a one-program
// archive on the shell boot.
use e.mem
use e.io
use e.time

fn say(text: str) {
    let print_error = io.print(text)
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

fn main(a: *mem.Arena, args: []str) -> err {
    let (start, start_error) = time.monotonic()
    if start_error != ok {
        say("time monotonic failed\n")
        ret ok
    }
    var spin = 0usize
    while spin < 5000000usize { spin += 1usize }
    let (finish, finish_error) = time.monotonic()
    if finish_error != ok {
        say("time monotonic failed\n")
        ret ok
    }
    if finish.nanos > start.nanos {
        say("time monotonic advanced ")
        say_num(usize(finish.nanos - start.nanos))
        say(" ns\n")
    } else {
        say("time monotonic stuck\n")
    }
    let (wall, wall_error) = time.now()
    if wall_error == ok && wall.nanos > 0i64 {
        say("time wall seconds ")
        say_num(usize(wall.nanos / 1000000000i64))
        say("\n")
        // Calendar breadth (D2186): convert the wall timestamp to a civil date through e.time's
        // days_from_civil/civil_from_days math (floor division), proving the calendar path -- not
        // just the raw clock read -- runs on NeperOS. The RTC gives a real 21st-century date.
        let wall_date = time.to_date(wall)
        say("time date ")
        say_num(usize(wall_date.year))
        say("-")
        say_num(usize(wall_date.month))
        say("-")
        say_num(usize(wall_date.day))
        say("\n")
    } else {
        say("time wall absent\n")
    }
    ret ok
}
