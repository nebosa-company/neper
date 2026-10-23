// `lifecycle_poll` hears the workspace's sleep and wake notifications, posted here by hand since a runner cannot sleep.
use e.mem
use e.os
use e.os.shell

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn post(name: str) {
    let center = os.msg0(os.msg0(os.cocoa_class("NSWorkspace\x00"), os.cocoa_sel("sharedWorkspace\x00")), os.cocoa_sel("notificationCenter\x00"))
    let text = os.cocoa_text(name)
    let posted = os.msg2(center, os.cocoa_sel("postNotificationName:object:\x00"), text, 0usize)
    os.cf_release(text)
}

fn main(a: *mem.Arena) -> err {
    let (none, any) = shell.lifecycle_poll()
    if any { os.exit(2i32) }
    post("NSWorkspaceWillSleepNotification")
    post("NSWorkspaceDidWakeNotification")
    let (first, got_first) = shell.lifecycle_poll()
    let (second, got_second) = shell.lifecycle_poll()
    if !got_first || first != .Suspend { os.exit(3i32) }
    if !got_second || second != .Resume { os.exit(4i32) }
    let (third, got_third) = shell.lifecycle_poll()
    if got_third { os.exit(5i32) }
    say("lifecycle ok\n")
    ret ok
}
