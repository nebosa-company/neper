// A real macOS window from Neper: the Objective-C runtime and AppKit by `@import` and `dlopen`, a pixel buffer turned
// into a CGImage and set as the content view's layer contents. Run by the macos-probe workflow, which screenshots the
// screen while this holds the window open. Stages are printed as they pass, so a failure names where.
use e.mem
use e.os

type CGRect = struct { x: f64, y: f64, w: f64, h: f64 }

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
extern fn send_double(receiver: usize, selector: usize, a: f64) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn send_window(receiver: usize, selector: usize, rect: CGRect, style: usize, backing: usize, deferred: i32) -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGColorSpaceCreateDeviceRGB")
extern fn cg_color_space() -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGBitmapContextCreate")
extern fn cg_bitmap_context(data: usize, width: usize, height: usize, bits: usize, row: usize, space: usize, info: u32) -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGBitmapContextCreateImage")
extern fn cg_context_image(context: usize) -> usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
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
    say("frameworks loaded\n")

    let app = send0(class_of("NSApplication\x00"), sel("sharedApplication\x00"))
    if app == 0usize { os.exit(4i32) }
    let policy = send1(app, sel("setActivationPolicy:\x00"), 0usize)
    say("application ready\n")

    // 400 x 300 content, titled, closable, miniaturizable, resizable; buffered; not deferred.
    var frame: CGRect = zero
    frame.x = 200.0f64
    frame.y = 200.0f64
    frame.w = 400.0f64
    frame.h = 300.0f64
    let allocated = send0(class_of("NSWindow\x00"), sel("alloc\x00"))
    let window = send_window(allocated, sel("initWithContentRect:styleMask:backing:defer:\x00"), frame, 15usize, 2usize, 0i32)
    if window == 0usize { os.exit(5i32) }
    say("window created\n")
    let title = send1(window, sel("setTitle:\x00"), ns_string("Neper on macOS\x00"))

    // The pixels: seven bars of colour over a gradient strip, Bgra8 packed into u32 (blue lowest).
    let width = 400usize
    let height = 300usize
    let (pixels, pixel_error) = mem.alloc[u32](a, width * height)
    if pixel_error != ok { os.exit(6i32) }
    let bars: [7]u32 = [7]u32{ 0xffff0000u32, 0xffff8800u32, 0xffffff00u32, 0xff00cc00u32, 0xff0088ffu32, 0xff4444ffu32, 0xffaa00ffu32 }
    var y = 0usize
    while y < height {
        var x = 0usize
        while x < width {
            var color = bars[x * 7usize / width]
            if y >= 220usize {
                let level = u32(x * 255usize / width)
                color = 0xff000000u32 | (level << 16u32) | (level << 8u32) | level
            }
            pixels[y * width + x] = color
            x += 1usize
        }
        y += 1usize
    }
    let space = cg_color_space()
    // 8194: little-endian 32-bit, alpha first and premultiplied: Bgra8 as the fence's window_present takes it.
    let context = cg_bitmap_context(mem.address_of(&pixels[0usize]), width, height, 8usize, width * 4usize, space, 8194u32)
    if context == 0usize { os.exit(7i32) }
    let image = cg_context_image(context)
    if image == 0usize { os.exit(8i32) }
    say("image made\n")

    let content = send0(window, sel("contentView\x00"))
    let wanted = send_flag(content, sel("setWantsLayer:\x00"), 1i32)
    let layer = send0(content, sel("layer\x00"))
    if layer == 0usize { os.exit(9i32) }
    let contents = send1(layer, sel("setContents:\x00"), image)
    let shown = send1(window, sel("makeKeyAndOrderFront:\x00"), 0usize)
    let active = send_flag(app, sel("activateIgnoringOtherApps:\x00"), 1i32)
    say("window shown\n")

    // Hold it: the run loop turns for about ten seconds so the window server draws it and the workflow can look.
    let run_loop = send0(class_of("NSRunLoop\x00"), sel("currentRunLoop\x00"))
    var turn = 0usize
    while turn < 100usize {
        let date = send_double(class_of("NSDate\x00"), sel("dateWithTimeIntervalSinceNow:\x00"), 0.1f64)
        let ran = send1(run_loop, sel("runUntilDate:\x00"), date)
        turn += 1usize
    }
    say("done\n")
    ret ok
}
