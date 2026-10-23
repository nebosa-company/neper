// The public window verbs on a Mac: open a window, draw a Bgra8 buffer into it with `os.window_present`, read its
// metrics and the monitors, then poll events for a few seconds (none arrive on a CI runner, but a Paint and a Focus
// should). Run by the macos-probe workflow, which screenshots the screen while it is open.
use e.mem
use e.os

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn number(label: str, value: i64) {
    say(label)
    var digits: [24]u8 = zero
    var count = 0usize
    var rest = value
    var negative = false
    if rest < 0i64 {
        negative = true
        rest = 0i64 - rest
    }
    if rest == 0i64 {
        digits[0usize] = 48u8
        count = 1usize
    }
    while rest > 0i64 {
        digits[count] = u8(48i64 + rest % 10i64)
        rest = rest / 10i64
        count += 1usize
    }
    var out: [26]u8 = zero
    var at = 0usize
    if negative {
        out[0usize] = 45u8
        at = 1usize
    }
    while count > 0usize {
        count -= 1usize
        out[at] = digits[count]
        at += 1usize
    }
    out[at] = 10u8
    at += 1usize
    let (written, write_error) = os.write(os.stdout(), out[0usize..at])
}

fn main(a: *mem.Arena) -> err {
    var options: os.WindowOptions = zero
    options.title = "Neper: os.window_open"
    options.width = 480u32
    options.height = 320u32
    options.resizable = true
    options.visible = true
    let (window, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(2i32) }
    say("window opened\n")

    let (metrics, metrics_error) = os.window_metrics(window)
    if metrics_error != ok { os.exit(3i32) }
    number("width: ", i64(metrics.width))
    number("height: ", i64(metrics.height))
    number("scale: ", i64(metrics.scale_percent))
    if metrics.visible { say("visible: yes\n") } else { say("visible: no\n") }

    let width = 480usize
    let height = 320usize
    let (pixels, pixel_error) = mem.alloc[u32](a, width * height)
    if pixel_error != ok { os.exit(4i32) }
    var y = 0usize
    while y < height {
        var x = 0usize
        while x < width {
            // A blue-to-orange diagonal, a white frame, and a red square in the top-left corner.
            let level = u32((x + y) * 255usize / (width + height))
            var color = 0xff000000u32 | ((255u32 - level) << 16u32) | ((level / 2u32 + 80u32) << 8u32) | level
            if x < 4usize || y < 4usize || x + 4usize >= width || y + 4usize >= height { color = 0xffffffffu32 }
            if x >= 16usize && x < 80usize && y >= 16usize && y < 80usize { color = 0xffff0000u32 }
            pixels[y * width + x] = color
            x += 1usize
        }
        y += 1usize
    }
    let present_error = os.window_present(window, pixels[0usize..width * height], u32(width), u32(height))
    if present_error != ok { os.exit(5i32) }
    say("frame presented\n")
    let titled = os.window_title(window, "Neper: window_present worked")

    let (screens, screens_error) = os.monitors(a, 4usize)
    if screens_error != ok { os.exit(6i32) }
    number("monitors: ", i64(screens.len))
    number("monitor width: ", i64(screens[0usize].width))
    number("monitor height: ", i64(screens[0usize].height))

    var paints = 0i64
    var focuses = 0i64
    var others = 0i64
    var turns = 0usize
    while turns < 60usize {
        let (event, got, poll_error) = os.window_poll(100000000i64)
        if poll_error != ok { os.exit(7i32) }
        if got {
            if event.kind == .Paint { paints += 1i64 } else { if event.kind == .Focus { focuses += 1i64 } else { others += 1i64 } }
        }
        turns += 1usize
    }
    number("paint events: ", paints)
    number("focus events: ", focuses)
    number("other events: ", others)
    let closed = os.window_close(window)
    say("done\n")
    ret ok
}
