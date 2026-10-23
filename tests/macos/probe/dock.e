// The Dock as a taskbar: a 40% badge on the application's tile and the Dock menu published. macos-probe screenshots the screen.
use e.mem
use e.os
use e.os.shell

fn main(a: *mem.Arena) -> err {
    var nowhere: os.Window = zero
    if shell.taskbar_progress(a, nowhere, .Normal, 2u64, 5u64) != ok { os.exit(2i32) }
    var tasks: [1]shell.JumpTask = zero
    tasks[0usize] = shell.JumpTask { title: "Open the log", program: "/usr/bin/true", arguments: "", description: "" }
    if shell.jump_list(a, tasks[..]) != ok { os.exit(3i32) }
    var i = 0usize
    while i < 60usize {
        let (event, has_event) = shell.tray_poll()
        let (e2, got, poll_error) = os.window_poll(100000000i64)
        i += 1usize
    }
    if shell.taskbar_progress(a, nowhere, .None, 0u64, 0u64) != ok { os.exit(4i32) }
    let (written, write_error) = os.write(os.stdout(), "dock ok\n")
    ret ok
}
