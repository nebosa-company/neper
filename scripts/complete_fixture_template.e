// `e.cli.complete`: the bash, zsh and fish completion scripts and the man pages for three command specs against
// goldens. The goldens were produced by this module and then held to behaviour by real shells and groff
// (scripts/gen_complete_test.py, which also writes this file): bash and fish by asking them for completions,
// zsh by `zsh -n`, the man pages by `groff -ww`. With an argument the fixture prints every output between
// markers instead of comparing, which is how the goldens are made. Every check has its own exit code.
use e.cli
use e.cli.complete as complete
use e.io
use e.mem
use e.os
use e.str

fn show(got: str, want: str) {
    let p = io.print("\nGOT  ")
    let q = io.print(got)
    let r = io.print("\nWANT ")
    let s = io.print(want)
}

fn dump(name: str, body: str) {
    let p = io.print("@@@ ")
    let q = io.print(name)
    let r = io.print("\n")
    let s = io.print(body)
    let t = io.print("@@@ end\n")
}

fn opt(long: str, short: u8, kind: cli.ValueKind, required: bool, repeated: bool, env: str, help: str) -> cli.Option {
    ret cli.Option{ long: long, short: short, kind: kind, required: required, repeated: repeated, env: env, help: help }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let dumping = args.len > 1usize
    var none_c: [1]cli.Command = zero
    var none_o: [1]cli.Option = zero
    // solo: no subcommands, one valued option and one flag
    var solo_o: [2]cli.Option = zero
    solo_o[0] = opt("out", 111u8, .String, false, false, "SOLO_OUT", "Where to write")
    solo_o[1] = opt("quiet", 0u8, .Bool, false, false, "", "")
    let solo = cli.Command{ name: "solo", help: "A single command", options: solo_o[0usize..2usize], subcommands: none_c[0usize..0usize] }
    // tool: options, a subcommand with options, and a nested pair
    var add_o: [1]cli.Option = zero
    add_o[0] = opt("fetch", 102u8, .Bool, false, false, "", "Fetch after adding")
    var remote_s: [2]cli.Command = zero
    remote_s[0] = cli.Command{ name: "add", help: "Add a remote", options: add_o[0usize..1usize], subcommands: none_c[0usize..0usize] }
    remote_s[1] = cli.Command{ name: "remove", help: "Remove a remote", options: none_o[0usize..0usize], subcommands: none_c[0usize..0usize] }
    var build_o: [2]cli.Option = zero
    build_o[0] = opt("release", 0u8, .Bool, false, false, "", "Optimised build")
    build_o[1] = opt("target-dir", 0u8, .String, false, true, "", "Path with 'quotes', [brackets], back\\slash and a: colon")
    var tool_s: [2]cli.Command = zero
    tool_s[0] = cli.Command{ name: "build", help: "Build the project", options: build_o[0usize..2usize], subcommands: none_c[0usize..0usize] }
    tool_s[1] = cli.Command{ name: "remote", help: "Manage remotes", options: none_o[0usize..0usize], subcommands: remote_s[0usize..2usize] }
    var tool_o: [3]cli.Option = zero
    tool_o[0] = opt("verbose", 118u8, .Bool, false, false, "", "Chatty output")
    tool_o[1] = opt("config", 99u8, .String, false, false, "", "Config file")
    tool_o[2] = opt("count", 0u8, .I64, true, false, "TOOL_COUNT", "How many")
    let tool = cli.Command{ name: "tool", help: "A tool with subcommands", options: tool_o[0usize..3usize], subcommands: tool_s[0usize..2usize] }
    // invalid: a name that cannot be written into shell syntax unquoted
    var bad_o: [1]cli.Option = zero
    bad_o[0] = opt("bad name", 0u8, .Bool, false, false, "", "")
    let bad = cli.Command{ name: "bad", help: "", options: bad_o[0usize..1usize], subcommands: none_c[0usize..0usize] }

    let (solo_bash, e1) = complete.bash(a, &solo)
    let (solo_zsh, e2) = complete.zsh(a, &solo)
    let (solo_fish, e3) = complete.fish(a, &solo)
    let (solo_man, e4) = complete.man_page(a, &solo, "solo", 49u8, "2026-10-12", "solo 1.0")
    let (tool_bash, e5) = complete.bash(a, &tool)
    let (tool_zsh, e6) = complete.zsh(a, &tool)
    let (tool_fish, e7) = complete.fish(a, &tool)
    let (tool_man, e8) = complete.man_page(a, &tool, "tool", 49u8, "2026-10-12", "tool 2.3")
    let (build_man, e9) = complete.man_page(a, &tool_s[0], "tool build", 49u8, "2026-10-12", "tool 2.3")
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { os.exit(1i32) }
    if dumping {
        dump("solo.bash", solo_bash)
        dump("solo.zsh", solo_zsh)
        dump("solo.fish", solo_fish)
        dump("solo.1", solo_man)
        dump("tool.bash", tool_bash)
        dump("tool.zsh", tool_zsh)
        dump("tool.fish", tool_fish)
        dump("tool.1", tool_man)
        dump("tool-build.1", build_man)
        ret ok
    }
    if !str.eq(solo_bash, @SOLO_BASH@) { show(solo_bash, @SOLO_BASH@)
        os.exit(2i32) }
    if !str.eq(solo_zsh, @SOLO_ZSH@) { show(solo_zsh, @SOLO_ZSH@)
        os.exit(3i32) }
    if !str.eq(solo_fish, @SOLO_FISH@) { show(solo_fish, @SOLO_FISH@)
        os.exit(4i32) }
    if !str.eq(solo_man, @SOLO_MAN@) { show(solo_man, @SOLO_MAN@)
        os.exit(5i32) }
    if !str.eq(tool_bash, @TOOL_BASH@) { show(tool_bash, @TOOL_BASH@)
        os.exit(6i32) }
    if !str.eq(tool_zsh, @TOOL_ZSH@) { show(tool_zsh, @TOOL_ZSH@)
        os.exit(7i32) }
    if !str.eq(tool_fish, @TOOL_FISH@) { show(tool_fish, @TOOL_FISH@)
        os.exit(8i32) }
    if !str.eq(tool_man, @TOOL_MAN@) { show(tool_man, @TOOL_MAN@)
        os.exit(9i32) }
    if !str.eq(build_man, @BUILD_MAN@) { show(build_man, @BUILD_MAN@)
        os.exit(10i32) }
    let (_, ie) = complete.bash(a, &bad)
    if ie != complete.Invalid { os.exit(11i32) }
    let (_, ie2) = complete.fish(a, &bad)
    if ie2 != complete.Invalid { os.exit(12i32) }
    try io.print("cli complete ok")
    ret ok
}
