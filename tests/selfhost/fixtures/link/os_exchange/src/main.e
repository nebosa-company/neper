// `e.os.shell`'s data exchange (D890, widget plan native-data-exchange-api): the
// clipboard written as several representations and read back one by one where the
// host types its clipboard, as text alone where it does not; the sequence changes
// with the clipboard; an empty offer is refused; a drop target and a drag are
// what the record says -- registered on no window they are refused either way.

use e.io
use e.mem
use e.os
use e.os.shell

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let caps = shell.capabilities()
    if caps.clipboard_typed && !caps.clipboard_text { os.exit(1i32) }
    var nothing: [1]shell.Content = zero
    if shell.clipboard_write(a, nothing[0usize..0usize]) != shell.Invalid { os.exit(2i32) }
    let (nowhere, drag_error) = shell.drag_start(a, nothing[0usize..0usize], false)
    if drag_error != shell.Invalid && drag_error != shell.Unsupported { os.exit(3i32) }
    var no_window: os.Window = zero
    if shell.drop_target_register(a, no_window, a) != shell.Invalid && shell.drop_target_register(a, no_window, a) != shell.Unsupported { os.exit(4i32) }
    let (no_drop, has_drop) = shell.drop_poll()
    if has_drop { os.exit(5i32) }
    var text_only: [1]shell.Content = zero
    text_only[0usize] = shell.Content { kind: .Text, mime: "", text: "neper exchange", paths: zero, image: zero, bytes: zero }
    if !caps.clipboard_text {
        // A host without a clipboard says so, and says so again at every verb.
        if shell.clipboard_write(a, text_only[..]) != shell.Unsupported || shell.clipboard_has(a, .Text, "") { os.exit(18i32) }
        let (no_text, no_text_error) = shell.clipboard_read(a, .Text, "")
        if no_text_error != shell.Unsupported { os.exit(19i32) }
        try io.print("os exchange ok\n")
        ret ok
    }
    // Text alone first, on every host with a clipboard.
    let before = shell.clipboard_sequence()
    if shell.clipboard_write(a, text_only[..]) != ok { os.exit(6i32) }
    if !shell.clipboard_has(a, .Text, "") { os.exit(7i32) }
    let (read_text, text_error) = shell.clipboard_read(a, .Text, "")
    if text_error != ok || !same(read_text.text, "neper exchange") { os.exit(8i32) }
    if shell.clipboard_sequence() == before && caps.clipboard_typed { os.exit(9i32) }
    if !caps.clipboard_typed {
        let (no_files, files_error) = shell.clipboard_read(a, .Files, "")
        if files_error != shell.Unsupported { os.exit(10i32) }
        try io.print("os exchange ok\n")
        ret ok
    }
    // Three representations at once, each read back by its kind.
    var paths: [2]str = zero
    paths[0usize] = "C:/neper/one.txt"
    paths[1usize] = "C:/neper/two.txt"
    var pixels: [6]u32 = zero
    pixels[0usize] = 4294901760u32
    pixels[1usize] = 4278255360u32
    pixels[2usize] = 4278190335u32
    pixels[3usize] = 4294967295u32
    pixels[4usize] = 4278190080u32
    pixels[5usize] = 4286611584u32
    var items: [4]shell.Content = zero
    items[0usize] = shell.Content { kind: .Text, mime: "", text: "typed", paths: zero, image: zero, bytes: zero }
    items[1usize] = shell.Content { kind: .Files, mime: "", text: "", paths: paths[..], image: zero, bytes: zero }
    items[2usize] = shell.Content { kind: .Image, mime: "", text: "", paths: zero, image: shell.Icon { width: 3u32, height: 2u32, pixels: pixels[..] }, bytes: zero }
    items[3usize] = shell.Content { kind: .Bytes, mime: "application/x-neper-test", text: "", paths: zero, image: zero, bytes: "\x01\x02\x03neper" }
    if shell.clipboard_write(a, items[..]) != ok { os.exit(11i32) }
    if !shell.clipboard_has(a, .Files, "") || !shell.clipboard_has(a, .Image, "") || !shell.clipboard_has(a, .Bytes, "application/x-neper-test") || shell.clipboard_has(a, .Bytes, "application/x-neper-other") { os.exit(12i32) }
    let (files, files_error) = shell.clipboard_read(a, .Files, "")
    if files_error != ok || files.paths.len != 2usize || !same(files.paths[0usize], "C:/neper/one.txt") || !same(files.paths[1usize], "C:/neper/two.txt") { os.exit(13i32) }
    let (image, image_error) = shell.clipboard_read(a, .Image, "")
    if image_error != ok || image.image.width != 3u32 || image.image.height != 2u32 || image.image.pixels[0usize] != 4294901760u32 || image.image.pixels[5usize] != 4286611584u32 { os.exit(14i32) }
    let (bytes, bytes_error) = shell.clipboard_read(a, .Bytes, "application/x-neper-test")
    if bytes_error != ok || bytes.bytes.len != 8usize || bytes.bytes[0usize] != 1u8 || bytes.bytes[7usize] != 114u8 { os.exit(15i32) }
    let (other, other_error) = shell.clipboard_read(a, .Bytes, "application/x-neper-other")
    if other_error != shell.NotFound { os.exit(16i32) }
    let (unnamed, unnamed_error) = shell.clipboard_read(a, .Bytes, "")
    if unnamed_error != shell.Invalid { os.exit(17i32) }
    try io.print("os exchange ok\n")
    ret ok
}
