// Notices through the notification center, which only a program in an application bundle may use. Run plain, the probe makes a
// bundle (the association mechanism of D5217) and opens it; the copy LaunchServices starts has a bundle identifier, posts a
// notice, counts what is delivered, removes it, counts again, and writes the story to /tmp/neper-un.txt for the parent to print.
use e.fs
use e.mem
use e.os
use e.os.shell
use e.str

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn note(a: *mem.Arena, text: str) {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.append = true
    let (file, open_error) = os.open(a, "/tmp/neper-un.txt", flags)
    if open_error != ok { ret }
    let (written, write_error) = os.write(file, text)
    let closed = os.close(file)
}

fn number(a: *mem.Arena, label: str, value: usize) {
    note(a, label)
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = value
    if rest == 0usize {
        digits[19usize] = 48u8
        count = 1usize
    }
    while rest > 0usize {
        digits[19usize - count] = u8(48usize + rest % 10usize)
        rest /= 10usize
        count += 1usize
    }
    note(a, digits[20usize - count..20usize])
    note(a, "\n")
}

fn main(a: *mem.Arena) -> err {
    if os.cocoa_start() != ok { os.exit(2i32) }
    if shell.bundled() {
        let caps = shell.capabilities()
        if caps.notice_remove { note(a, "remove offered\n") } else { note(a, "remove not offered\n") }
        let (id, publish_error) = shell.notice_publish(a, 0u32, "Neper", "A notice from a bundle", true)
        if publish_error != ok { note(a, "publish failed\n") } else { note(a, "published\n") }
        number(a, "delivered after publish: ", shell.un_delivered_count())
        let removed = shell.notice_remove(a, 0u32, id)
        if removed == ok { note(a, "removed\n") } else { note(a, "remove refused\n") }
        number(a, "delivered after remove: ", shell.un_delivered_count())
        note(a, "end\n")
        ret ok
    }
    let gone = fs.remove_file(a, "/tmp/neper-un.txt")
    if shell.associate_file(a, ".nun", "neper.UN", "UN probe") != ok { os.exit(3i32) }
    let (home, home_error) = fs.home_dir(a)
    if home_error != ok { os.exit(4i32) }
    let (root, root_error) = str.concat(a, home, "/Library/Application Support/Neper/Associations/neper.UN.app")
    if root_error != ok { os.exit(5i32) }
    var argv: [2]str = zero
    argv[0usize] = "/usr/bin/open"
    argv[1usize] = root
    var options: os.SpawnOptions = zero
    options.argv = argv[..]
    options.inherit_env = true
    options.stdio.stdout = os.File { raw: 1usize }
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(a, options)
    if spawn_error != ok { os.exit(6i32) }
    let (usage, wait_error) = os.wait_usage(child)
    var tries = 0usize
    var finished = false
    while tries < 1000usize && !finished {
        var storage: [4096]u8 = zero
        var scratch = mem.arena_from(storage[..])
        let (text, read_error) = fs.read_file(&scratch, "/tmp/neper-un.txt", 2048usize)
        if read_error == ok && text.len >= 4usize && text[text.len - 4usize] == 101u8 && text[text.len - 3usize] == 110u8 && text[text.len - 2usize] == 100u8 {
            say(text)
            finished = true
        }
        if !finished { os.cocoa_pump(100000000i64) }
        tries += 1usize
    }
    let dissociated = shell.dissociate_file(a, ".nun", "neper.UN")
    if !finished { os.exit(7i32) }
    say("un notices done\n")
    ret ok
}
