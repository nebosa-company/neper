// Whether this Mac offers biometrics (a runner does not), and the photo picker shown and dismissed from the run loop.
use e.mem
use e.os
use e.os.shell

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_after(receiver: usize, selector: usize, action: usize, object: usize, delay: f64, modes: usize) -> usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena) -> err {
    if os.cocoa_start() != ok { os.exit(2i32) }
    let caps = shell.capabilities()
    if caps.biometrics { say("biometrics: available\n") } else { say("biometrics: none\n") }
    if !caps.biometrics {
        let (verdict, verify_error) = shell.biometric_verify(a, "probe")
        if verify_error != shell.Unsupported { os.exit(3i32) }
        say("verify without biometrics: unsupported\n")
    }
    let app = os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00"))
    let activated = os.msg_flag(app, os.cocoa_sel("activateIgnoringOtherApps:\x00"), 1i32)
    var modes: [2]usize = zero
    modes[0usize] = os.cocoa_text("NSModalPanelRunLoopMode")
    modes[1usize] = os.cocoa_text("kCFRunLoopCommonModes")
    let list = os.msg2(os.cocoa_class("NSArray\x00"), os.cocoa_sel("arrayWithObjects:count:\x00"), mem.address_of(&modes[0usize]), 2usize)
    let scheduled = msg_after(app, os.cocoa_sel("performSelector:withObject:afterDelay:inModes:\x00"), os.cocoa_sel("abortModal\x00"), 0usize, 3.0f64, list)
    var no_window: os.Window = zero
    let (photos, photo_error) = shell.photo_picker(a, no_window, true)
    if photo_error != shell.Cancelled { os.exit(4i32) }
    say("photo picker cancelled\n")
    ret ok
}
