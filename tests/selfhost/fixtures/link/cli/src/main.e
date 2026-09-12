// `e.cli`: a command with a subcommand parsed from long, short, inline and repeated
// options with positionals and `--`; `validate` refusing a duplicate long and a
// required bool; `Unknown`, `InvalidArgument` (a bad integer, a missing value, a
// repeat of a single option), `Missing` for a required option whose env variable is
// unset; `help` rendered and wrapped; `parse_into` over a struct. Every check has its
// own exit code.
use e.os
use e.mem
use e.str
use e.cli

type Settings = struct { name: str, count: i32, ratio: f64, verbose: bool }

fn make_args(a: *mem.Arena, one: str, two: str, three: str, four: str, five: str, six: str, count: usize) -> []const str {
    let (args, args_error) = mem.alloc[str](a, 6usize)
    if args_error != ok { os.exit(99) }
    args[0] = one
    args[1] = two
    args[2] = three
    args[3] = four
    args[4] = five
    args[5] = six
    ret args[..count]
}

fn main(a: *mem.Arena, args: []str) -> err {
    var options: [3]cli.Option = zero
    options[0] = cli.Option { long: "level", short: 108u8, kind: .I64, required: false, repeated: false, env: "", help: "the level to run at, which is an integer and this text is long enough to wrap" }
    options[1] = cli.Option { long: "verbose", short: 118u8, kind: .Bool, required: false, repeated: false, env: "", help: "say more" }
    options[2] = cli.Option { long: "tag", short: 0u8, kind: .String, required: false, repeated: true, env: "", help: "" }
    var sub_options: [1]cli.Option = zero
    sub_options[0] = cli.Option { long: "key", short: 107u8, kind: .String, required: true, repeated: false, env: "NEPER_CLI_FIXTURE_UNSET", help: "the key" }
    var subs: [1]cli.Command = zero
    subs[0] = cli.Command { name: "run", help: "run it", options: sub_options[0..], subcommands: zero }
    let root = cli.Command { name: "tool", help: "a tool", options: options[0..], subcommands: subs[0..] }
    if cli.validate(&root) != ok { os.exit(1) }
    // Top-level options, positionals and `--`.
    let a1 = make_args(a, "-l", "7", "--tag=x", "--tag", "y", "--", 6usize)
    let (r1, e1) = cli.parse(a, &root, a1)
    if e1 != ok { os.exit(2) }
    if !str.eq(r1.command, "tool") || r1.positionals.len != 0usize || r1.options.len != 2usize { os.exit(3) }
    let (level, has_level) = cli.option(&r1, "level")
    if !has_level || level.values.len != 1usize { os.exit(4) }
    switch level.values[0] {
    case .I64 as number:
        if number != 7i64 { os.exit(5) }
    default:
        os.exit(6)
    }
    let (tags, has_tags) = cli.option(&r1, "tag")
    if !has_tags || tags.values.len != 2usize { os.exit(7) }
    switch tags.values[1] {
    case .String as text:
        if !str.eq(text, "y") { os.exit(8) }
    default:
        os.exit(9)
    }
    let (verbose, has_verbose) = cli.option(&r1, "verbose")
    if has_verbose { os.exit(10) }
    let a2 = make_args(a, "--verbose", "--", "-l", "file", "", "", 4usize)
    let (r2, e2) = cli.parse(a, &root, a2)
    if e2 != ok || r2.positionals.len != 2usize || !str.eq(r2.positionals[0], "-l") { os.exit(11) }
    let (verbose2, has_verbose2) = cli.option(&r2, "verbose")
    if !has_verbose2 { os.exit(12) }
    switch verbose2.values[0] {
    case .Bool as flag:
        if !flag { os.exit(13) }
    default:
        os.exit(14)
    }
    // The subcommand with its required option, then without it.
    let a3 = make_args(a, "run", "--key", "k1", "input", "", "", 4usize)
    let (r3, e3) = cli.parse(a, &root, a3)
    if e3 != ok || !str.eq(r3.command, "run") || r3.positionals.len != 1usize { os.exit(15) }
    let (key, has_key) = cli.option(&r3, "key")
    if !has_key { os.exit(16) }
    let a4 = make_args(a, "run", "input", "", "", "", "", 2usize)
    let (r4, e4) = cli.parse(a, &root, a4)
    if e4 != cli.Missing { os.exit(17) }
    // Refusals.
    let a5 = make_args(a, "--nope", "", "", "", "", "", 1usize)
    let (r5, e5) = cli.parse(a, &root, a5)
    if e5 != cli.Unknown { os.exit(18) }
    let a6 = make_args(a, "--level", "seven", "", "", "", "", 2usize)
    let (r6, e6) = cli.parse(a, &root, a6)
    if e6 != cli.InvalidArgument { os.exit(19) }
    let a7 = make_args(a, "--level", "", "", "", "", "", 1usize)
    let (r7, e7) = cli.parse(a, &root, a7)
    if e7 != cli.InvalidArgument { os.exit(20) }
    let a8 = make_args(a, "-l", "1", "-l", "2", "", "", 4usize)
    let (r8, e8) = cli.parse(a, &root, a8)
    if e8 != cli.InvalidArgument { os.exit(21) }
    var dup: [2]cli.Option = zero
    dup[0] = options[0]
    dup[1] = options[0]
    let bad = cli.Command { name: "bad", help: "", options: dup[0..], subcommands: zero }
    if cli.validate(&bad) != cli.InvalidSpec { os.exit(22) }
    var required_bool: [1]cli.Option = zero
    required_bool[0] = cli.Option { long: "flag", short: 0u8, kind: .Bool, required: true, repeated: false, env: "", help: "" }
    let bad2 = cli.Command { name: "bad", help: "", options: required_bool[0..], subcommands: zero }
    if cli.validate(&bad2) != cli.InvalidSpec { os.exit(23) }
    // Help.
    let (text, e9) = cli.help(a, &root, 60u16)
    if e9 != ok { os.exit(24) }
    if !str.starts_with(text, "usage: tool [options] <command>\n\na tool\n\noptions:\n  -l, --level <int>  the level to run at, which is an\n      integer and this text is long enough to wrap\n") { os.exit(25) }
    if !str.contains(text, "  -v, --verbose  say more\n") || !str.contains(text, "  --tag <string>\n") { os.exit(26) }
    if !str.contains(text, "\ncommands:\n  run  run it\n") { os.exit(27) }
    let (sub_text, e10) = cli.help(a, &subs[0], 80u16)
    if e10 != ok || !str.contains(sub_text, "  -k, --key <string>  the key (required) [env: NEPER_CLI_FIXTURE_UNSET]\n") { os.exit(28) }
    // parse_into.
    let a9 = make_args(a, "--name", "neper", "--count=-3", "--ratio", "2.5", "--verbose", 6usize)
    let (settings, e11) = cli.parse_into[Settings](a, a9)
    if e11 != ok { os.exit(29) }
    if !str.eq(settings.name, "neper") || settings.count != -3 || settings.ratio != 2.5 || !settings.verbose { os.exit(30) }
    let a10 = make_args(a, "--nope", "1", "", "", "", "", 2usize)
    let (settings2, e12) = cli.parse_into[Settings](a, a10)
    if e12 != cli.Unknown { os.exit(31) }
    let a11 = make_args(a, "--count", "x", "", "", "", "", 2usize)
    let (settings3, e13) = cli.parse_into[Settings](a, a11)
    if e13 != cli.InvalidArgument { os.exit(32) }
    ret ok
}
