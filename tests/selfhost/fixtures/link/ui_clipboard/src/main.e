// `e.ui.app`'s system clipboard and sharing (D893, widget plan P4-06): an offer goes
// to the clipboard as its representations and comes back by type, a monitor sees
// the change once and no more, and sharing is what the predicates say -- nothing,
// on either host. A host without a clipboard says so at every verb.

use e.io
use e.mem
use e.os
use e.os.shell
use e.ui.app

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
    var items: [2]shell.Content = zero
    items[0usize] = shell.Content { kind: .Text, mime: "", text: "clipboard offer", paths: zero, image: zero, bytes: zero }
    items[1usize] = shell.Content { kind: .Bytes, mime: "application/x-neper-clip", text: "", paths: zero, image: zero, bytes: "clip" }
    let (offer, offer_error) = app.offer_of(a, items[..])
    if offer_error != ok { os.exit(1i32) }
    if app.share_supported() || app.share_target_supported() { os.exit(2i32) }
    if app.share(a, offer) != shell.Unsupported { os.exit(3i32) }
    let (no_share, has_share) = app.share_target_take()
    if has_share { os.exit(4i32) }
    let text_type = app.ContentType { kind: .Text, mime: "" }
    let clip_type = app.ContentType { kind: .Bytes, mime: "application/x-neper-clip" }
    let other_type = app.ContentType { kind: .Bytes, mime: "application/x-neper-other" }
    var monitor = app.clipboard_monitor()
    if !app.clipboard_supported() {
        if app.clipboard_offer(a, offer) != shell.Unsupported || app.clipboard_holds(a, text_type) || app.clipboard_changed(&monitor) { os.exit(5i32) }
        let (nothing, take_error) = app.clipboard_take(a, text_type)
        if take_error != shell.Unsupported { os.exit(6i32) }
        try io.print("ui clipboard ok\n")
        ret ok
    }
    if app.clipboard_changed(&monitor) { os.exit(7i32) }
    if app.clipboard_offer(a, offer) != ok { os.exit(8i32) }
    if !app.clipboard_changed(&monitor) || app.clipboard_changed(&monitor) { os.exit(9i32) }
    if !app.clipboard_holds(a, text_type) || !app.clipboard_holds(a, clip_type) || app.clipboard_holds(a, other_type) { os.exit(10i32) }
    let (text, text_error) = app.clipboard_take(a, text_type)
    if text_error != ok || !same(text.text, "clipboard offer") { os.exit(11i32) }
    let (clip, clip_error) = app.clipboard_take(a, clip_type)
    if clip_error != ok || clip.bytes.len != 4usize || clip.bytes[0usize] != 99u8 { os.exit(12i32) }
    let (other, other_error) = app.clipboard_take(a, other_type)
    if other_error != shell.NotFound { os.exit(13i32) }
    try io.print("ui clipboard ok\n")
    ret ok
}
