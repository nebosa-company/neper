// The unified shell's wallpaper loader (C112, D2196). A filesystem client: it builds the small
// wallpaper image, encodes it to PNG, stores it in the C106 server through e.fs (fs.write_file),
// reads the PNG bytes back (fs.read_file) and hands them to the shell over endpoint slot 3 (a length
// word, then one word per byte), then tells the filesystem server to quit. The shell cannot be the fs
// client itself: e.fs fixes the request/reply endpoints at slots 1 and 2, the compositor frame signal
// and the routed input already hold those in the shell.
// Program 6 of a `compositor bigarena unified` archive; slot 1 fs request (send), slot 2 fs reply
// (receive), slot 3 the shell (send).
use e.mem
use e.os
use e.fs
use e.io
use e.gfx.image
use e.fmt.png

const TO_SHELL: usize = 3usize
const NO_SLOT: usize = 99usize

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

// A 4x4 RGBA8 gradient, the wallpaper's source image before it becomes a PNG on disk. Small on
// purpose: the C106 server stores a file in one 512-byte block, so the encoded PNG must fit, and
// DrawImage scales the little image to cover the 256x256 surface.
fn make_wallpaper(a: *mem.Arena) -> (image.ConstImage, err) {
    let (pixels, pixels_error) = mem.alloc[u8](a, 4usize * 4usize * 4usize)
    if pixels_error != ok { ret (zero, pixels_error) }
    var y = 0usize
    while y < 4usize {
        var x = 0usize
        while x < 4usize {
            let p = (y * 4usize + x) * 4usize
            pixels[p] = u8(x * 64usize)
            pixels[p + 1usize] = u8(y * 64usize)
            pixels[p + 2usize] = 128u8
            pixels[p + 3usize] = 255u8
            x += 1usize
        }
        y += 1usize
    }
    let (made, made_error) = image.make_const(pixels, 4u32, 4u32, 16usize, image.Format.Rgba8, image.Alpha.Straight)
    ret (made, made_error)
}

// Tell the shell there is no wallpaper (a length no PNG here reaches), and stop the server.
fn give_up(why: str) {
    say(why)
    let none = os.send(TO_SHELL, 65535usize, NO_SLOT)
    let quit = os.send(1usize, 0usize, NO_SLOT)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (source, source_error) = make_wallpaper(a)
    if source_error != ok { ret source_error }
    let (buffer, buffer_error) = mem.alloc[u8](a, 65536usize)
    if buffer_error != ok { ret buffer_error }
    var sink = io.SliceWriter { data: buffer, off: 0usize }
    var encoder = io.slice_writer(&sink)
    if png.encode(&encoder, source, png.EncodeOptions { compression: .Fast, interlace: false }) != ok {
        give_up("wall loader encode failed\n")
        ret ok
    }
    let encoded = buffer[0usize..sink.off]
    if fs.write_file(a, "/wall.png", encoded) != ok {
        give_up("wall loader store failed\n")
        ret ok
    }
    let (wall_bytes, read_error) = fs.read_file(a, "/wall.png", 65536usize)
    if read_error != ok {
        give_up("wall loader read failed\n")
        ret ok
    }
    say("wall loader from fs ")
    say_num(wall_bytes.len)
    say("\n")
    let header = os.send(TO_SHELL, wall_bytes.len, NO_SLOT)
    var i = 0usize
    while i < wall_bytes.len {
        let sent = os.send(TO_SHELL, usize(wall_bytes[i]), NO_SLOT)
        i += 1usize
    }
    let quit = os.send(1usize, 0usize, NO_SLOT)
    say("wall loader done\n")
    ret ok
}
