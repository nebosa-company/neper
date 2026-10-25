// The camera, microphone and location as the system reports them, and what a request answers on this machine (a runner has no
// camera or microphone, so the request must come back at once and not hang or crash).
use e.mem
use e.os
use e.os.shell

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn name(p: shell.Permission) -> str {
    if p == .Granted { ret "granted" }
    if p == .Denied { ret "denied" }
    ret "unavailable"
}

fn main(a: *mem.Arena) -> err {
    say("camera status: ")
    say(name(shell.permission_status(a, .Camera)))
    say("\nmicrophone status: ")
    say(name(shell.permission_status(a, .Microphone)))
    say("\nlocation status: ")
    say(name(shell.permission_status(a, .Location)))
    say("\nscreen status: ")
    say(name(shell.permission_status(a, .Screen)))
    say("\n")
    let (camera, camera_error) = shell.permission_request(a, .Camera)
    say("camera request: ")
    say(name(camera))
    if camera_error != ok { say(" (error)") }
    let (microphone, microphone_error) = shell.permission_request(a, .Microphone)
    say("\nmicrophone request: ")
    say(name(microphone))
    if microphone_error != ok { say(" (error)") }
    say("\npermissions ok\n")
    ret ok
}
