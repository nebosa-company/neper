// The window verbs' event side on a Mac: synthetic NSEvents posted into a real window, and what `os.window_poll` makes of
// them (pointer, buttons, keys as X11 keysyms, text), then the clipboard, a resize, the cursor and a close. A CI runner
// has no one at the keyboard, so the events are made here, with AppKit's own factories.
use e.mem
use e.os

type CgRect = struct { x: f64, y: f64, w: f64, h: f64 }
type CgPoint = struct { x: f64, y: f64 }
type CgSize = struct { w: f64, h: f64 }

@import("/usr/lib/libobjc.A.dylib", "objc_getClass")
extern fn objc_get_class(name: *const u8) -> usize

@import("/usr/lib/libobjc.A.dylib", "sel_registerName")
extern fn objc_sel_register(name: *const u8) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg0(receiver: usize, selector: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg2(receiver: usize, selector: usize, a: usize, b: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_size(receiver: usize, selector: usize, size: CgSize) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_mouse(receiver: usize, selector: usize, kind: usize, at: CgPoint, flags: usize, stamp: f64, window_number: usize, context: usize, event_number: usize, clicks: usize, pressure: f32) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_key_packed(receiver: usize, selector: usize, kind: usize, at: CgPoint, flags: usize, stamp: f64, window_number: usize, context: usize, characters: usize, plain: usize, packed: u32) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_key_split(receiver: usize, selector: usize, kind: usize, at: CgPoint, flags: usize, stamp: f64, window_number: usize, context: usize, characters: usize, plain: usize, repeated: u32, code: u32) -> usize

@import("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", "CFStringCreateWithBytes")
extern fn cf_string_create(allocator: usize, bytes: *const u8, count: usize, encoding: u32, external: i32) -> usize

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

fn sel(name: str) -> usize { ret objc_sel_register(&name[0usize]) }
fn class_of(name: str) -> usize { ret objc_get_class(&name[0usize]) }

fn text_of(text: str) -> usize {
    ret cf_string_create(0usize, &text[0usize], text.len, 134217984u32, 0i32)
}

// One line per event the program gets: kind (Close 0, Resize 1, Focus 2, Blur 3, PointerMove 4, PointerDown 5,
// PointerUp 6, Scroll 7, KeyDown 8, KeyUp 9, Text 10, Paint 11), then the fields that mean something to it.
fn drain(label: str) {
    say("--- ")
    say(label)
    say("\n")
    var quiet = 0usize
    while quiet < 2usize {
        let (event, got, poll_error) = os.window_poll(60000000i64)
        if poll_error != ok {
            say("poll error\n")
            ret
        }
        if !got {
            quiet += 1usize
        } else {
            quiet = 0usize
            var kind = 0i64
            if event.kind == .Resize { kind = 1i64 }
            if event.kind == .Focus { kind = 2i64 }
            if event.kind == .Blur { kind = 3i64 }
            if event.kind == .PointerMove { kind = 4i64 }
            if event.kind == .PointerDown { kind = 5i64 }
            if event.kind == .PointerUp { kind = 6i64 }
            if event.kind == .Scroll { kind = 7i64 }
            if event.kind == .KeyDown { kind = 8i64 }
            if event.kind == .KeyUp { kind = 9i64 }
            if event.kind == .Text { kind = 10i64 }
            if event.kind == .Paint { kind = 11i64 }
            number("event kind: ", kind)
            if kind == 1i64 {
                number("  width: ", i64(event.width))
                number("  height: ", i64(event.height))
            }
            if kind >= 4i64 && kind <= 7i64 {
                number("  x: ", i64(event.x))
                number("  y: ", i64(event.y))
                number("  button: ", i64(event.button))
                number("  delta: ", i64(event.delta))
            }
            if kind == 8i64 || kind == 9i64 {
                number("  key: ", i64(event.key))
                number("  modifiers: ", i64(event.modifiers))
                if event.repeat { number("  repeat: ", 1i64) } else { number("  repeat: ", 0i64) }
            }
            if kind == 10i64 { number("  codepoint: ", i64(event.codepoint)) }
        }
    }
}

fn point(x: f64, y: f64) -> CgPoint {
    var p: CgPoint = zero
    p.x = x
    p.y = y
    ret p
}

fn post_mouse(app: usize, window_id: usize, kind: usize, x: f64, y: f64, flags: usize) {
    let event = msg_mouse(class_of("NSEvent\x00"), sel("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:\x00"), kind, point(x, y), flags, 1.0f64, window_id, 0usize, 0usize, 1usize, 1.0f32)
    let posted = msg2(app, sel("postEvent:atStart:\x00"), event, 0usize)
}

fn post_key(app: usize, window_id: usize, kind: usize, flags: usize, characters: str, code: u32) {
    let chars = text_of(characters)
    var event = 0usize
    let factory = sel("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:\x00")
    when target.arch == .X64 {
        event = msg_key_split(class_of("NSEvent\x00"), factory, kind, point(0.0f64, 0.0f64), flags, 1.0f64, window_id, 0usize, chars, chars, 0u32, code)
    } else {
        event = msg_key_packed(class_of("NSEvent\x00"), factory, kind, point(0.0f64, 0.0f64), flags, 1.0f64, window_id, 0usize, chars, chars, code << 16u32)
    }
    let posted = msg2(app, sel("postEvent:atStart:\x00"), event, 0usize)
}

fn main(a: *mem.Arena) -> err {
    var options: os.WindowOptions = zero
    options.title = "Neper: events"
    options.width = 480u32
    options.height = 320u32
    options.resizable = true
    options.visible = true
    let (window, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(2i32) }
    let (view, handle, native_error) = os.window_native(window)
    if native_error != ok { os.exit(3i32) }
    let window_id = msg0(handle, sel("windowNumber\x00"))
    let app = msg0(class_of("NSApplication\x00"), sel("sharedApplication\x00"))
    drain("opened")

    post_mouse(app, window_id, 5usize, 100.0f64, 220.0f64, 0usize)
    drain("mouse moved to (100, 220) from the bottom: y should be 100 from the top")
    post_mouse(app, window_id, 1usize, 100.0f64, 220.0f64, 0usize)
    post_mouse(app, window_id, 2usize, 100.0f64, 220.0f64, 0usize)
    drain("left down and up: button 0")
    post_mouse(app, window_id, 3usize, 40.0f64, 40.0f64, 0usize)
    drain("right down at (40, 40): button 1, y 280")

    post_key(app, window_id, 10usize, 0usize, "a", 0u32)
    post_key(app, window_id, 11usize, 0usize, "a", 0u32)
    drain("a down and up: key 97, text 97")
    post_key(app, window_id, 10usize, 0usize, "\r", 36u32)
    drain("return: key 65293, no text")
    post_key(app, window_id, 10usize, 131072usize, "A", 0u32)
    drain("shift a: key 97, modifiers 1, text 65")
    post_key(app, window_id, 10usize, 0usize, "\xEF\x9C\x82", 123u32)
    drain("left arrow: key 65361, no text")
    post_key(app, window_id, 10usize, 1048576usize, "c", 8u32)
    drain("command c: key 99, modifiers 8, no text")

    let copied = os.set_clipboard_text("h\xC3\xA9llo Neper")
    let (back, clipboard_error) = os.clipboard_text(a)
    say("--- clipboard\n")
    if copied != ok { say("set failed\n") }
    if clipboard_error != ok { say("get failed\n") }
    number("length: ", i64(back.len))
    say("text: ")
    say(back)
    say("\n")

    let sized = msg_size(handle, sel("setContentSize:\x00"), CgSize { w: 600.0f64, h: 400.0f64 })
    drain("resized to 600 x 400: a Resize then a Paint")
    let shaped = os.window_cursor(window, .Hand)
    let hidden = os.window_cursor(window, .Hidden)
    let arrow = os.window_cursor(window, .Arrow)
    if shaped != ok || hidden != ok || arrow != ok { say("cursor failed\n") } else { say("cursors ok\n") }

    let closed = msg0(handle, sel("close\x00"))
    drain("closed by the user: a Close")
    let released = os.window_close(window)
    say("done\n")
    ret ok
}
