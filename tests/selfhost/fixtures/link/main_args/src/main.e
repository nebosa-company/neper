// `main` may declare `args`, and they are the command line however the image was linked:
// straight from source, or from `.em` artifacts through `link-em`. The runners pass the same
// two arguments both ways, one of them with a space, which is the case a Windows command
// line has to parse rather than receive.
//
// Only `e.mem` is used, and not for anything: `e.os` has module-scope `var`s, and an
// artifact carries no globals, so a program that reaches `e.os` does not link from `.em`
// files yet -- the gap this fixture found and leaves for its own row.

use e.mem

error Wrong

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
    if args.len != 3usize { ret Wrong }
    if !same(args[1usize], "one") { ret Wrong }
    if !same(args[2usize], "two words") { ret Wrong }
    ret ok
}
