// `e.os.shell.file_dialog` on a Mac: an open panel is shown, and the run loop aborts it after a few seconds so the
// macos-probe workflow can screenshot it first (shot_after 5). Prints `dialog cancelled` when the verb answered Cancelled.
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
    let app = os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00"))
    let activated = os.msg_flag(app, os.cocoa_sel("activateIgnoringOtherApps:\x00"), 1i32)
    var modes: [2]usize = zero
    modes[0usize] = os.cocoa_text("NSModalPanelRunLoopMode")
    modes[1usize] = os.cocoa_text("kCFRunLoopCommonModes")
    let list = os.msg2(os.cocoa_class("NSArray\x00"), os.cocoa_sel("arrayWithObjects:count:\x00"), mem.address_of(&modes[0usize]), 2usize)
    let scheduled = msg_after(app, os.cocoa_sel("performSelector:withObject:afterDelay:inModes:\x00"), os.cocoa_sel("abortModal\x00"), 0usize, 8.0f64, list)
    var filters: [1]shell.FileFilter = zero
    filters[0usize] = shell.FileFilter { label: "Text", pattern: "*.txt" }
    let dialog = shell.FileDialog { kind: .Open, title: "Neper: choose a file", filters: filters[..], multiple: false, initial: "", default_extension: "", folder: "/tmp" }
    var no_window: os.Window = zero
    let (paths, dialog_error) = shell.file_dialog(a, no_window, dialog)
    if dialog_error == shell.Cancelled {
        say("dialog cancelled\n")
        ret ok
    }
    say("dialog answered something else\n")
    os.exit(3i32)
    ret ok
}
