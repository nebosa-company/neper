// Finder-opened files and URLs. Run plain, the probe registers a file type and a URL scheme (each a small bundle whose
// executable is this program), asks `open` to open a file of that type and a URL of that scheme, and waits for the two files
// that the copies LaunchServices started write. Started through a bundle (it has a bundle identifier) it waits for the
// activation, writes what it was sent to /tmp/neper-open-<kind>.txt and ends.
use e.fs
use e.mem
use e.os
use e.os.shell

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn note(a: *mem.Arena, text: str) {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.append = true
    let (file, open_error) = os.open(a, "/tmp/neper-launch.log", flags)
    if open_error != ok { ret }
    let (written, write_error) = os.write(file, text)
    let closed = os.close(file)
}

fn bundled() -> bool {
    let bundle = os.msg0(os.cocoa_class("NSBundle\x00"), os.cocoa_sel("mainBundle\x00"))
    ret os.msg0(bundle, os.cocoa_sel("bundleIdentifier\x00")) != 0usize
}

fn run(a: *mem.Arena, argv: []const str) -> err {
    var options: os.SpawnOptions = zero
    options.argv = argv
    options.inherit_env = true
    options.stdio.stdout = os.File { raw: 1usize }
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(a, options)
    if spawn_error != ok { ret os.Failed }
    let (usage, wait_error) = os.wait_usage(child)
    if wait_error != ok || usage.exit_code != 0i32 { ret os.Failed }
    ret ok
}

fn wait_for(a: *mem.Arena, path: str, seconds: usize) -> bool {
    var tries = 0usize
    while tries < seconds * 10usize {
        var storage: [4096]u8 = zero
        var scratch = mem.arena_from(storage[..])
        let (present, exists_error) = fs.exists(&scratch, path)
        if exists_error == ok && present { ret true }
        os.cocoa_pump(100000000i64)
        tries += 1usize
    }
    ret false
}

fn main(a: *mem.Arena) -> err {
    if os.cocoa_start() != ok { os.exit(2i32) }
    // Every start leaves a line, so a run that fails can say whether LaunchServices started a copy and what it saw.
    var mark = "plain\n"
    if bundled() { mark = "bundled\n" }
    note(a, mark)
    if bundled() {
        var tries = 0usize
        while tries < 200usize {
            let (activation, got) = shell.activation_poll()
            if tries == 0usize {
                let delegate = os.msg0(os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00")), os.cocoa_sel("delegate\x00"))
                if delegate != 0usize && os.msg_bool_ret(delegate, os.cocoa_sel("respondsToSelector:\x00")) == 0u8 { note(a, "delegate set\n") }
                if delegate == 0usize { note(a, "no delegate\n") }
            }
            if got {
                note(a, "got an activation\n")
                var path = "/tmp/neper-open-file.txt"
                if activation.kind == .Url { path = "/tmp/neper-open-url.txt" }
                note(a, activation.payload)
                note(a, "\n")
                if fs.write_file(a, path, activation.payload) != ok {
                    note(a, "write failed\n")
                    os.exit(3i32)
                }
                note(a, "written\n")
                ret ok
            }
            os.cocoa_pump(100000000i64)
            tries += 1usize
        }
        note(a, "gave up\n")
        os.exit(4i32)
    }
    let gone_file = fs.remove_file(a, "/tmp/neper-open-file.txt")
    let gone_url = fs.remove_file(a, "/tmp/neper-open-url.txt")
    if shell.associate_file(a, ".neperx", "neper.Probe", "Neper probe document") != ok { os.exit(5i32) }
    if shell.associate_protocol(a, "neperprobe", "Neper probe links") != ok { os.exit(6i32) }
    if fs.write_file(a, "/tmp/probe-doc.neperx", "document") != ok { os.exit(7i32) }
    var open_file: [2]str = zero
    open_file[0usize] = "/usr/bin/open"
    open_file[1usize] = "/tmp/probe-doc.neperx"
    if run(a, open_file[..]) != ok { os.exit(8i32) }
    var open_url: [2]str = zero
    open_url[0usize] = "/usr/bin/open"
    open_url[1usize] = "neperprobe:hello/world"
    if run(a, open_url[..]) != ok { os.exit(9i32) }
    if !wait_for(a, "/tmp/neper-open-file.txt", 25usize) {
        var diag: [3]str = zero
        diag[0usize] = "/bin/sh"
        diag[1usize] = "-c"
        diag[2usize] = "ls -la /tmp/neper-open-* /tmp/probe-doc.neperx; cat /tmp/neper-launch.log; log show --last 2m --predicate 'process == \"lsd\" OR process == \"launchservicesd\" OR eventMessage CONTAINS \"neper\"' --style compact 2>/dev/null | tail -25; ls -laR \"$HOME/Library/Application Support/Neper\" | head -30; /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump 2>/dev/null | grep -i -B3 -A12 'neper.Probe' | head -60; ps aux | grep -i neper-app | grep -v grep; /usr/bin/open -Ra /tmp/probe-doc.neperx 2>&1 | head -3; mdls -name kMDItemContentType /tmp/probe-doc.neperx"
        let ran = run(a, diag[..])
        os.exit(10i32)
    }
    if !wait_for(a, "/tmp/neper-open-url.txt", 25usize) { os.exit(11i32) }
    let (file_text, file_error) = fs.read_file(a, "/tmp/neper-open-file.txt", 4096usize)
    let (url_text, url_error) = fs.read_file(a, "/tmp/neper-open-url.txt", 4096usize)
    say("file: ")
    say(file_text)
    say("\nurl: ")
    say(url_text)
    say("\n")
    if shell.dissociate_file(a, ".neperx", "neper.Probe") != ok { os.exit(12i32) }
    if shell.dissociate_protocol(a, "neperprobe") != ok { os.exit(13i32) }
    if shell.dissociate_file(a, ".neperx", "neper.Probe") != shell.NotFound { os.exit(14i32) }
    say("open events ok\n")
    ret ok
}
