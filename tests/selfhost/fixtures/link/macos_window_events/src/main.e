// The window verbs on a Mac (D5202): synthetic NSEvents posted into a real window, and what `os.window_poll` makes of them
// -- pointer positions flipped to the top and in pixels, the button numbering, keys as X11 keysyms, text, modifiers -- then
// the clipboard, a resize, the cursor and a close. A CI runner has no one at the keyboard, so AppKit's own factories make
// the events. macOS only: it is not named by the Windows or Linux suites, and the corpus runs it on a Mac.
use e.mem
use e.os

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

// The factory's last two arguments, a BOOL and an unsigned short, are on the stack: Apple's arm64 packs them into one
// slot (the BOOL at 0, the key code at 2), where x64 gives each an eightbyte.
@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_key_packed(receiver: usize, selector: usize, kind: usize, at: CgPoint, flags: usize, stamp: f64, window_number: usize, context: usize, characters: usize, plain: usize, packed: u32) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_key_split(receiver: usize, selector: usize, kind: usize, at: CgPoint, flags: usize, stamp: f64, window_number: usize, context: usize, characters: usize, plain: usize, repeated: u32, code: u32) -> usize

@import("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", "CFStringCreateWithBytes")
extern fn cf_string_create(allocator: usize, bytes: *const u8, count: usize, encoding: u32, external: i32) -> usize

fn sel(name: str) -> usize { ret objc_sel_register(&name[0usize]) }
fn class_of(name: str) -> usize { ret objc_get_class(&name[0usize]) }

fn point(x: f64, y: f64) -> CgPoint {
    var p: CgPoint = zero
    p.x = x
    p.y = y
    ret p
}

fn post_mouse(app: usize, window_id: usize, kind: usize, x: f64, y: f64) {
    let event = msg_mouse(class_of("NSEvent\x00"), sel("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:\x00"), kind, point(x, y), 0usize, 1.0f64, window_id, 0usize, 0usize, 1usize, 1.0f32)
    let posted = msg2(app, sel("postEvent:atStart:\x00"), event, 0usize)
}

fn post_key(app: usize, window_id: usize, kind: usize, flags: usize, characters: str, code: u32) {
    let chars = cf_string_create(0usize, &characters[0usize], characters.len, 134217984u32, 0i32)
    var event = 0usize
    let factory = sel("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:\x00")
    when target.arch == .X64 {
        event = msg_key_split(class_of("NSEvent\x00"), factory, kind, point(0.0f64, 0.0f64), flags, 1.0f64, window_id, 0usize, chars, chars, 0u32, code)
    } else {
        event = msg_key_packed(class_of("NSEvent\x00"), factory, kind, point(0.0f64, 0.0f64), flags, 1.0f64, window_id, 0usize, chars, chars, code << 16u32)
    }
    let posted = msg2(app, sel("postEvent:atStart:\x00"), event, 0usize)
}

// The next event, waiting a little: a program that is told one is coming. `code` is the exit if none comes.
fn next(code: i32) -> os.WindowEvent {
    var tries = 0usize
    while tries < 20usize {
        let (event, got, poll_error) = os.window_poll(50000000i64)
        if poll_error != ok { os.exit(code) }
        if got { ret event }
        tries += 1usize
    }
    os.exit(code)
    var none: os.WindowEvent = zero
    ret none
}

// Nothing more is waiting.
fn quiet(code: i32) {
    let (event, got, poll_error) = os.window_poll(80000000i64)
    if got { os.exit(code) }
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
    let (handle, view, native_error) = os.window_native(window)
    if native_error != ok { os.exit(3i32) }
    let window_id = msg0(handle, sel("windowNumber\x00"))
    let app = msg0(class_of("NSApplication\x00"), sel("sharedApplication\x00"))

    // What opening a visible window says: a Paint, and the window taking focus.
    var painted = false
    var focused = false
    var opening = 0usize
    while opening < 4usize && !(painted && focused) {
        let first = next(10i32)
        if first.kind == .Paint { painted = true }
        if first.kind == .Focus { focused = true }
        opening += 1usize
    }
    if !painted || !focused { os.exit(11i32) }
    quiet(12i32)

    post_mouse(app, window_id, 5usize, 100.0f64, 220.0f64)
    var event = next(20i32)
    if event.kind != .PointerMove || event.x != 100i32 || event.y != 100i32 { os.exit(21i32) }
    post_mouse(app, window_id, 1usize, 100.0f64, 220.0f64)
    post_mouse(app, window_id, 2usize, 100.0f64, 220.0f64)
    event = next(22i32)
    if event.kind != .PointerDown || event.button != 0u8 || event.x != 100i32 || event.y != 100i32 { os.exit(23i32) }
    event = next(24i32)
    if event.kind != .PointerUp || event.button != 0u8 { os.exit(25i32) }
    post_mouse(app, window_id, 3usize, 40.0f64, 40.0f64)
    event = next(26i32)
    if event.kind != .PointerDown || event.button != 1u8 || event.x != 40i32 || event.y != 280i32 { os.exit(27i32) }
    quiet(28i32)

    post_key(app, window_id, 10usize, 0usize, "a", 0u32)
    post_key(app, window_id, 11usize, 0usize, "a", 0u32)
    event = next(30i32)
    if event.kind != .KeyDown || event.key != 97u32 || event.modifiers != 0u8 || event.repeat { os.exit(31i32) }
    event = next(32i32)
    if event.kind != .Text || event.codepoint != 97u32 { os.exit(33i32) }
    event = next(34i32)
    if event.kind != .KeyUp || event.key != 97u32 { os.exit(35i32) }
    post_key(app, window_id, 10usize, 0usize, "\r", 36u32)
    event = next(36i32)
    if event.kind != .KeyDown || event.key != 65293u32 { os.exit(37i32) }
    quiet(38i32)
    post_key(app, window_id, 10usize, 131072usize, "A", 0u32)
    event = next(40i32)
    if event.kind != .KeyDown || event.key != 97u32 || event.modifiers != 1u8 { os.exit(41i32) }
    event = next(42i32)
    if event.kind != .Text || event.codepoint != 65u32 { os.exit(43i32) }
    post_key(app, window_id, 10usize, 0usize, "\xEF\x9C\x82", 123u32)
    event = next(44i32)
    if event.kind != .KeyDown || event.key != 65361u32 { os.exit(45i32) }
    quiet(46i32)
    post_key(app, window_id, 10usize, 1048576usize, "c", 8u32)
    event = next(47i32)
    if event.kind != .KeyDown || event.key != 99u32 || event.modifiers != 8u8 { os.exit(48i32) }
    quiet(49i32)

    let copied = os.set_clipboard_text("h\xC3\xA9llo Neper")
    if copied != ok { os.exit(50i32) }
    let (back, clipboard_error) = os.clipboard_text(a)
    if clipboard_error != ok || back.len != 12usize { os.exit(51i32) }
    if back[0usize] != 104u8 || back[1usize] != 195u8 || back[2usize] != 169u8 || back[11usize] != 114u8 { os.exit(52i32) }

    let sized = msg_size(handle, sel("setContentSize:\x00"), CgSize { w: 600.0f64, h: 400.0f64 })
    event = next(60i32)
    if event.kind != .Resize || event.width != 600u32 || event.height != 400u32 { os.exit(61i32) }
    event = next(62i32)
    if event.kind != .Paint { os.exit(63i32) }
    let (metrics, metrics_error) = os.window_metrics(window)
    if metrics_error != ok || metrics.width != 600u32 || metrics.height != 400u32 { os.exit(64i32) }
    if os.window_cursor(window, .Hand) != ok || os.window_cursor(window, .Hidden) != ok || os.window_cursor(window, .Arrow) != ok { os.exit(65i32) }

    let closed = msg0(handle, sel("close\x00"))
    event = next(70i32)
    if event.kind != .Close { os.exit(71i32) }
    if os.window_close(window) != ok { os.exit(72i32) }
    let (gone, gone_error) = os.window_metrics(window)
    if gone_error == ok { os.exit(73i32) }
    ret ok
}
