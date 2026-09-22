// `e.ui.app`'s typed data exchange model (D891, widget plan P4-04): a content type
// names its MIME and reads back from one; an offer produces its representations
// through its provider only when materialised, in order; an offer over items in
// hand answers those items; a provider answering the wrong type is refused. Pure,
// so the same on every host.

use e.io
use e.mem
use e.os
use e.os.shell
use e.ui.app

type Log = struct { calls: usize }

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn provide(ctx: *void, a: *mem.Arena, t: app.ContentType, out: *shell.Content) -> err {
    let log = mem.cast[*Log](ctx)
    log.calls += 1usize
    if t.kind == .Text {
        *out = shell.Content { kind: .Text, mime: "", text: "lazy text", paths: zero, image: zero, bytes: zero }
        ret ok
    }
    *out = shell.Content { kind: .Bytes, mime: t.mime, text: "", paths: zero, image: zero, bytes: "lazy bytes" }
    ret ok
}

fn provide_wrong(ctx: *void, a: *mem.Arena, t: app.ContentType, out: *shell.Content) -> err {
    *out = shell.Content { kind: .Files, mime: "", text: "", paths: zero, image: zero, bytes: zero }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Names both ways.
    if !same(app.content_type_name(app.ContentType { kind: .Text, mime: "" }), "text/plain;charset=utf-8") { os.exit(1i32) }
    if !same(app.content_type_name(app.ContentType { kind: .Files, mime: "" }), "text/uri-list") { os.exit(2i32) }
    if !same(app.content_type_name(app.ContentType { kind: .Bytes, mime: "application/x-neper" }), "application/x-neper") { os.exit(3i32) }
    if app.content_type_of("text/plain").kind != .Text || app.content_type_of("image/bmp").kind != .Image { os.exit(4i32) }
    let custom = app.content_type_of("application/x-neper")
    if custom.kind != .Bytes || !same(custom.mime, "application/x-neper") { os.exit(5i32) }
    // A lazy offer: nothing is produced until it is materialised, then everything, in order.
    var log = Log { calls: 0usize }
    var types: [2]app.ContentType = zero
    types[0usize] = app.ContentType { kind: .Text, mime: "" }
    types[1usize] = app.ContentType { kind: .Bytes, mime: "application/x-neper" }
    let offer = app.DataOffer { types: types[..], provider: app.DataProvider { ctx: mem.cast[*void](&log), provide: provide } }
    if log.calls != 0usize { os.exit(6i32) }
    let (items, materialize_error) = app.offer_materialize(a, offer)
    if materialize_error != ok || log.calls != 2usize || items.len != 2usize { os.exit(7i32) }
    if items[0usize].kind != .Text || !same(items[0usize].text, "lazy text") || items[1usize].kind != .Bytes || !same(items[1usize].mime, "application/x-neper") || items[1usize].bytes.len != 10usize { os.exit(8i32) }
    // A provider answering the wrong type is refused; an empty offer too.
    let wrong = app.DataOffer { types: types[..], provider: app.DataProvider { ctx: mem.cast[*void](&log), provide: provide_wrong } }
    let (nothing, wrong_error) = app.offer_materialize(a, wrong)
    if wrong_error != shell.Invalid { os.exit(9i32) }
    let empty = app.DataOffer { types: types[0usize..0usize], provider: app.DataProvider { ctx: mem.cast[*void](&log), provide: provide } }
    let (still_nothing, empty_error) = app.offer_materialize(a, empty)
    if empty_error != shell.Invalid { os.exit(10i32) }
    // An offer over items in hand answers those items, by type.
    let (held, held_error) = app.offer_of(a, items)
    if held_error != ok || held.types.len != 2usize || held.types[1usize].kind != .Bytes { os.exit(11i32) }
    let (again, again_error) = app.offer_materialize(a, held)
    if again_error != ok || again.len != 2usize || !same(again[0usize].text, "lazy text") || again[1usize].bytes.len != 10usize { os.exit(12i32) }
    if log.calls != 2usize { os.exit(13i32) }
    try io.print("ui exchange model ok\n")
    ret ok
}
