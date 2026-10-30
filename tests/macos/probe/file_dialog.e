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
    var filters: [1]shell.FileFilter = zero
    filters[0usize] = shell.FileFilter { label: "Text", pattern: "*.txt" }
    var kinds: [3]shell.DialogKind = zero
    kinds[0usize] = .Open
    kinds[1usize] = .Save
    kinds[2usize] = .Folder
    var at = 0usize
    while at < 3usize {
        schedule_abort(app, 3.0f64)
        let dialog = shell.FileDialog { kind: kinds[at], title: "Neper: choose", filters: filters[..], multiple: false, initial: "report.txt", default_extension: "txt", folder: "/tmp" }
        var no_window: os.Window = zero
        let (paths, dialog_error) = shell.file_dialog(a, no_window, dialog)
        if dialog_error != shell.Cancelled { os.exit(3i32 + i32(at)) }
        say("dialog cancelled\n")
        at += 1usize
    }
    ret ok
}
