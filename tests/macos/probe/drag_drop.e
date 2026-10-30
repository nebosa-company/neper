// Drag and drop on a Mac. The drop: a window is a drop target, and `performDragOperation:` is sent to its view by hand with a
// stand-in for the dragging info (a class made here that answers `draggingPasteboard`, the general pasteboard holding some
// text, and `draggingLocation`); the queued drop must carry that text and the point in pixels. The drag: a text item is dragged
// from the window and a mouse up posted two seconds later ends it, `Cancelled`.
use e.mem
use e.os
use e.os.shell

type Point = struct { x: f64, y: f64 }
type Imp = union { function: fn(usize, usize) -> usize, bits: usize }
type PointImp = union { function: extern fn(usize, usize) -> Point, bits: usize }

@import("/usr/lib/libobjc.A.dylib", "objc_allocateClassPair")
extern fn class_pair(superclass: usize, name: *const u8, extra: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "class_addMethod")
extern fn class_method(class: usize, selector: usize, implementation: usize, types: *const u8) -> u8

@import("/usr/lib/libobjc.A.dylib", "objc_registerClassPair")
extern fn class_register(class: usize)

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

@cc(c)
fn info_pasteboard(this: usize, command: usize) -> usize {
    ret os.msg0(os.cocoa_class("NSPasteboard\x00"), os.cocoa_sel("generalPasteboard\x00"))
}

@cc(c)
fn info_location(this: usize, command: usize) -> Point {
    ret Point { x: 50.0f64, y: 30.0f64 }
}

fn same(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena) -> err {
    var options: os.WindowOptions = zero
    options.title = "Neper: drag and drop"
    options.width = 400u32
    options.height = 300u32
    options.visible = true
    let (window, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(2i32) }
    let (storage_bytes, storage_error) = mem.alloc[u8](a, 65536usize)
    if storage_error != ok { os.exit(3i32) }
    var storage = mem.arena_from(storage_bytes)
    if shell.drop_target_register(a, window, &storage) != ok { os.exit(4i32) }
    if shell.drop_target_register(a, window, &storage) != shell.Invalid { os.exit(5i32) }
    // The stand-in dragging info.
    let name = "FakeDraggingInfo\x00"
    let class = class_pair(os.cocoa_class("NSObject\x00"), &name[0usize], 0usize)
    var pasteboard: Imp = zero
    pasteboard.function = info_pasteboard
    var location: PointImp = zero
    location.function = info_location
    let types = "@@:\x00"
    let point_types = "{CGPoint=dd}@:\x00"
    let one = class_method(class, os.cocoa_sel("draggingPasteboard\x00"), pasteboard.bits, &types[0usize])
    let two = class_method(class, os.cocoa_sel("draggingLocation\x00"), location.bits, &point_types[0usize])
    class_register(class)
    let info = os.msg0(os.msg0(class, os.cocoa_sel("alloc\x00")), os.cocoa_sel("init\x00"))
    if shell.clipboard_write(a, zero) == ok { os.exit(6i32) }
    var texts: [1]shell.Content = zero
    texts[0usize] = shell.Content { kind: .Text, mime: "", text: "dropped words", paths: zero, image: zero, bytes: zero }
    if shell.clipboard_write(a, texts[..]) != ok { os.exit(7i32) }
    let (handle, view, native_error) = os.window_native(window)
    if native_error != ok { os.exit(8i32) }
    let accepted = os.msg1(view, os.cocoa_sel("performDragOperation:\x00"), info)
    let (landed, any) = shell.drop_poll()
    if !any { os.exit(9i32) }
    if landed.items.len != 1usize || landed.items[0usize].kind != .Text || !same(landed.items[0usize].text, "dropped words") { os.exit(10i32) }
    if landed.x != 50i32 { os.exit(11i32) }
    say("drop ok\n")
    if shell.drop_target_unregister(a, window) != ok { os.exit(12i32) }
    if shell.drop_target_unregister(a, window) != shell.NotFound { os.exit(13i32) }
    if shell.drag_cancel_after(2.0f64) != ok { os.exit(14i32) }
    let (result, drag_error) = shell.drag_start(a, texts[..], false)
    if drag_error != ok { os.exit(15i32) }
    if result != .Cancelled { os.exit(16i32) }
    say("drag ok\n")
    ret ok
}
