// What a page hands a module and takes back (C191, D5678): the first argument, an environment
// variable, a file in `/` and, as output, the file upcased, a file in a new directory, standard
// output and standard error, and exit status 7. Run by tests/wasm/host.mjs, never by the sweep.
use e.mem
use e.os
use e.fs

fn say(file: os.File, text: str) {
    let (written, write_error) = os.write(file, text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { os.exit(2i32) }
    say(os.stdout(), args[1usize])
    say(os.stdout(), "\n")
    let (var_value, var_error) = os.env(a, "HOSTVAR")
    if var_error != ok { os.exit(3i32) }
    say(os.stdout(), var_value)
    say(os.stdout(), "\n")
    let (input, input_error) = fs.read_file(a, "/input.txt", 65536usize)
    if input_error != ok { os.exit(4i32) }
    var at = 0usize
    while at < input.len {
        if input[at] >= 97u8 && input[at] <= 122u8 { input[at] = input[at] - 32u8 }
        at += 1usize
    }
    if fs.write_file(a, "/output.txt", input) != ok { os.exit(5i32) }
    if fs.make_dir(a, "/sub") != ok { os.exit(6i32) }
    if fs.write_file(a, "/sub/n.txt", "nested") != ok { os.exit(8i32) }
    say(os.stderr(), "to stderr\n")
    os.exit(7i32)
    ret ok
}
