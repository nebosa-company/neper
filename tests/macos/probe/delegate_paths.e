// The delegate's two paths a runner can reach: the Dock menu it hands AppKit runs a task when its item is performed
// (`/usr/bin/touch` makes a file), but a semicolon in task arguments stays data rather than launching a second command;
// `applicationWillTerminate:` is queued as Shutdown.
use e.fs
use e.mem
use e.os
use e.os.shell

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena) -> err {
    let marker = "/tmp/neper-dock-task-ran"
    let injected = "/tmp/neper-dock-task-injected"
    var removed = fs.remove_file(a, marker)
    var removed_injected = fs.remove_file(a, injected)
    var tasks: [2]shell.JumpTask = zero
    tasks[0usize] = shell.JumpTask { title: "Touch", program: "/usr/bin/touch", arguments: "/tmp/neper-dock-task-ran", description: "" }
    tasks[1usize] = shell.JumpTask { title: "No injection", program: "/usr/bin/true", arguments: "; /usr/bin/touch /tmp/neper-dock-task-injected", description: "" }
    if shell.jump_list(a, tasks[..]) != ok { os.exit(2i32) }
    let app = os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00"))
    let delegate = os.msg0(app, os.cocoa_sel("delegate\x00"))
    if delegate == 0usize { os.exit(3i32) }
    let menu = os.msg1(delegate, os.cocoa_sel("applicationDockMenu:\x00"), app)
    if menu == 0usize { os.exit(4i32) }
    let performed = os.msg1(menu, os.cocoa_sel("performActionForItemAtIndex:\x00"), 0usize)
    var tries = 0usize
    var present = false
    while !present && tries < 40usize {
        os.cocoa_pump(50000000i64)
        let (here, exists_error) = fs.exists(a, marker)
        present = here
        tries += 1usize
    }
    if !present { os.exit(5i32) }
    say("dock task ran\n")
    let injected_performed = os.msg1(menu, os.cocoa_sel("performActionForItemAtIndex:\x00"), 1usize)
    tries = 0usize
    while tries < 40usize {
        os.cocoa_pump(50000000i64)
        tries += 1usize
    }
    let (injected_present, injected_error) = fs.exists(a, injected)
    if injected_present { os.exit(7i32) }
    say("dock task arguments stayed data\n")
    let terminated = os.msg1(delegate, os.cocoa_sel("applicationWillTerminate:\x00"), 0usize)
    let (event, got) = shell.lifecycle_poll()
    if !got || event != .Shutdown { os.exit(6i32) }
    say("shutdown queued\n")
    ret ok
}
