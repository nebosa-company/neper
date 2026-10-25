// The print panel and the page setup panel are shown in turn, and each is dismissed from the run loop after three seconds
// (`abortModal`), so the macos-probe screenshot (shot_after 2) catches the print panel; each must answer Cancelled.
use e.mem
use e.os
use e.os.shell

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_after(receiver: usize, selector: usize, action: usize, object: usize, delay: f64, modes: usize) -> usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn schedule_abort(app: usize, seconds: f64) {
    var modes: [2]usize = zero
    modes[0usize] = os.cocoa_text("NSModalPanelRunLoopMode")
    modes[1usize] = os.cocoa_text("kCFRunLoopCommonModes")
    let list = os.msg2(os.cocoa_class("NSArray\x00"), os.cocoa_sel("arrayWithObjects:count:\x00"), mem.address_of(&modes[0usize]), 2usize)
    let scheduled = msg_after(app, os.cocoa_sel("performSelector:withObject:afterDelay:inModes:\x00"), os.cocoa_sel("abortModal\x00"), 0usize, seconds, list)
}

fn main(a: *mem.Arena) -> err {
    if os.cocoa_start() != ok { os.exit(2i32) }
    let app = os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00"))
    let activated = os.msg_flag(app, os.cocoa_sel("activateIgnoringOtherApps:\x00"), 1i32)
    var no_window: os.Window = zero
    schedule_abort(app, 3.0f64)
    let (printer, print_error) = shell.print_dialog(a, no_window, 1u32, 9u32)
    if print_error != shell.Cancelled { os.exit(3i32) }
    say("print dialog cancelled\n")
    schedule_abort(app, 3.0f64)
    var current: shell.PageSetup = zero
    let (setup, setup_error) = shell.page_setup_dialog(a, no_window, current)
    if setup_error != shell.Cancelled { os.exit(4i32) }
    say("page setup cancelled\n")
    ret ok
}
