// `e.os.window_present` on NeperOS must reject a logical frame shorter than its dimensions
// before the shared-frame blit indexes it. This runs without a compositor: a valid return must
// therefore be `Unsupported`, not a read from the one-pixel source or a frame-ready signal.
use e.mem
use e.os

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var pixels: [1]u32 = zero
    let present_error = os.window_present(os.Window { raw: 1usize }, pixels[0usize..1usize], 2u32, 1u32)
    if present_error != os.Unsupported {
        say("window present short frame accepted\n")
        os.exit(1i32)
    }
    say("window present short frame refused\n")
    ret ok
}
