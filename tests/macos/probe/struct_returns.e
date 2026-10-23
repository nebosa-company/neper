// What an Objective-C call can hand back to Neper on each Mac architecture: a double, a two-double struct (NSPoint, in
// registers on both), a four-double struct (NSRect: registers on arm64, objc_msgSend_stret on x64), a BOOL and a C
// string (read back with strlen and memcpy). The numbers decide how the window verbs read sizes and events.
use e.mem
use e.os

type CGRect = struct { x: f64, y: f64, w: f64, h: f64 }
type CGPoint = struct { x: f64, y: f64 }

@import("/usr/lib/libobjc.A.dylib", "objc_getClass")
extern fn objc_get_class(name: *const u8) -> usize

@import("/usr/lib/libobjc.A.dylib", "sel_registerName")
extern fn sel_register(name: *const u8) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn send0(receiver: usize, selector: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn send1(receiver: usize, selector: usize, a: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn send_flag(receiver: usize, selector: usize, a: i32) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn send_window(receiver: usize, selector: usize, rect: CGRect, style: usize, backing: usize, deferred: i32) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn send_double_ret(receiver: usize, selector: usize) -> f64

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn send_point_ret(receiver: usize, selector: usize) -> CGPoint

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn send_rect_ret_plain(receiver: usize, selector: usize) -> CGRect

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend_stret")
extern fn send_rect_ret_stret(receiver: usize, selector: usize) -> CGRect

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn send_bool_ret(receiver: usize, selector: usize) -> u8

@import("c", "strlen")
extern fn c_strlen(text: usize) -> usize

@import("c", "memcpy")
extern fn c_memcpy(to: *u8, from: usize, count: usize) -> usize

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

fn sel(name: str) -> usize { ret sel_register(&name[0usize]) }

fn class_of(name: str) -> usize { ret objc_get_class(&name[0usize]) }

fn ns_string(text: str) -> usize {
    ret send1(class_of("NSString\x00"), sel("stringWithUTF8String:\x00"), mem.address_of(&text[0usize]))
}

fn main(a: *mem.Arena) -> err {
    let (foundation, foundation_error) = os.dlopen(a, "/System/Library/Frameworks/Foundation.framework/Foundation")
    if foundation_error != ok { os.exit(2i32) }
    defer let _ = os.dlclose(foundation)
    let (appkit, appkit_error) = os.dlopen(a, "/System/Library/Frameworks/AppKit.framework/AppKit")
    if appkit_error != ok { os.exit(3i32) }
    defer let _ = os.dlclose(appkit)
    let app = send0(class_of("NSApplication\x00"), sel("sharedApplication\x00"))
    let policy = send1(app, sel("setActivationPolicy:\x00"), 0usize)

    var frame: CGRect = zero
    frame.x = 120.0f64
    frame.y = 90.0f64
    frame.w = 400.0f64
    frame.h = 300.0f64
    let window = send_window(send0(class_of("NSWindow\x00"), sel("alloc\x00")), sel("initWithContentRect:styleMask:backing:defer:\x00"), frame, 15usize, 2usize, 0i32)
    if window == 0usize { os.exit(5i32) }
    let titled = send1(window, sel("setTitle:\x00"), ns_string("Struct returns\x00"))
    let shown = send1(window, sel("makeKeyAndOrderFront:\x00"), 0usize)

    let screen = send0(class_of("NSScreen\x00"), sel("mainScreen\x00"))
    let scale = send_double_ret(screen, sel("backingScaleFactor\x00"))
    number("scale x100: ", i64(scale * 100.0f64))

    let point = send_point_ret(class_of("NSEvent\x00"), sel("mouseLocation\x00"))
    number("mouse x: ", i64(point.x))
    number("mouse y: ", i64(point.y))

    // No four-double return: the rect comes back through KVC, boxed in an NSValue that copies it out (getValue:).
    var rect: CGRect = zero
    let boxed = send1(window, sel("valueForKey:\x00"), ns_string("frame\x00"))
    let unboxed = send1(boxed, sel("getValue:\x00"), mem.address_of(&rect))
    number("frame x: ", i64(rect.x))
    number("frame y: ", i64(rect.y))
    number("frame w: ", i64(rect.w))
    number("frame h: ", i64(rect.h))

    let visible = send_bool_ret(window, sel("isVisible\x00"))
    number("visible: ", i64(visible))

    let title_text = send0(send0(window, sel("title\x00")), sel("UTF8String\x00"))
    let length = c_strlen(title_text)
    number("title length: ", i64(length))
    var copy: [64]u8 = zero
    if length < 64usize {
        let copied = c_memcpy(&copy[0usize], title_text, length)
        say("title: ")
        say(copy[0usize..length])
        say("\n")
    }
    ret ok
}
