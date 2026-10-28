// `single_instance` and `activation_poll`: the first run is first and starts a second copy of itself with an embedded LF in
// its URL argument.  The receiver must preserve it as one argument.  A second child receives an overlong argument and must
// be rejected without forwarding a truncated activation.
use e.fs
use e.mem
use e.os
use e.os.shell

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var at = 0usize
    while at < a.len {
        if a[at] != b[at] { ret false }
        at += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    if os.cocoa_start() != ok { os.exit(8i32) }
    let (storage_bytes, storage_error) = mem.alloc[u8](a, 65536usize)
    if storage_error != ok { os.exit(2i32) }
    var storage = mem.arena_from(storage_bytes)
    let oversized = args.len == 2usize && args[1usize].len == 4096usize
    let (first, instance_error) = shell.single_instance(a, "neper-probe-single", args, &storage)
    if oversized {
        if first || instance_error != shell.Invalid { os.exit(12i32) }
        say("oversize rejected\n")
        ret ok
    }
    if instance_error != ok { os.exit(3i32) }
    if !first {
        say("second: not first\n")
        ret ok
    }
    let (exe, exe_error) = fs.executable_path(a)
    if exe_error != ok { os.exit(4i32) }
    var argv: [2]str = zero
    argv[0usize] = exe
    argv[1usize] = "neper-test:for\nwarded"
    var options: os.SpawnOptions = zero
    options.argv = argv[..]
    options.inherit_env = true
    options.stdio.stdout = os.File { raw: 1usize }
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(a, options)
    if spawn_error != ok { os.exit(5i32) }
    let (usage, wait_error) = os.wait_usage(child)
    if wait_error != ok || usage.exit_code != 0i32 { os.exit(9i32) }
    var tries = 0usize
    while tries < 40usize {
        let (activation, got) = shell.activation_poll()
        if got {
            if activation.kind == .Url && activation.args.len == 2usize && same(activation.payload, "neper-test:for\nwarded") && same(activation.args[1usize], "neper-test:for\nwarded") {
                say("first: activation forwarded\n")
                break
            }
            os.exit(6i32)
        }
        os.cocoa_pump(50000000i64)
        tries += 1usize
    }
    if tries == 40usize { os.exit(7i32) }
    let (large, large_error) = mem.alloc[u8](a, 4096usize)
    if large_error != ok { os.exit(10i32) }
    var fill = 0usize
    while fill < large.len {
        large[fill] = 120u8
        fill += 1usize
    }
    var large_argv: [2]str = zero
    large_argv[0usize] = exe
    large_argv[1usize] = large[0usize..large.len]
    options.argv = large_argv[..]
    let (large_child, large_spawn_error) = os.spawn_with_options(a, options)
    if large_spawn_error != ok { os.exit(11i32) }
    let (large_usage, large_wait_error) = os.wait_usage(large_child)
    if large_wait_error != ok || large_usage.exit_code != 0i32 { os.exit(13i32) }
    let (unexpected, got_unexpected) = shell.activation_poll()
    if got_unexpected { os.exit(14i32) }
    say("oversize was not forwarded\n")
    ret ok
}
