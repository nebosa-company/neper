// `single_instance` and `activation_poll`: the first run is first and starts a second copy of itself with `neper-test:forwarded`
// as its argument; the second is told it is not first, and the first receives its command line as a Url activation.
use e.fs
use e.mem
use e.os
use e.os.shell

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if os.cocoa_start() != ok { os.exit(8i32) }
    let (storage_bytes, storage_error) = mem.alloc[u8](a, 65536usize)
    if storage_error != ok { os.exit(2i32) }
    var storage = mem.arena_from(storage_bytes)
    let (first, instance_error) = shell.single_instance(a, "neper-probe-single", args, &storage)
    if instance_error != ok { os.exit(3i32) }
    if !first {
        say("second: not first\n")
        ret ok
    }
    let (exe, exe_error) = fs.executable_path(a)
    if exe_error != ok { os.exit(4i32) }
    var argv: [2]str = zero
    argv[0usize] = exe
    argv[1usize] = "neper-test:forwarded"
    var options: os.SpawnOptions = zero
    options.argv = argv[..]
    options.inherit_env = true
    options.stdio.stdout = os.File { raw: 1usize }
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(a, options)
    if spawn_error != ok { os.exit(5i32) }
    let (usage, wait_error) = os.wait_usage(child)
    var tries = 0usize
    while tries < 40usize {
        let (activation, got) = shell.activation_poll()
        if got {
            if activation.kind == .Url && activation.payload.len == 20usize && activation.args.len == 2usize {
                say("first: activation forwarded\n")
                ret ok
            }
            os.exit(6i32)
        }
        os.cocoa_pump(50000000i64)
        tries += 1usize
    }
    os.exit(7i32)
    ret ok
}
