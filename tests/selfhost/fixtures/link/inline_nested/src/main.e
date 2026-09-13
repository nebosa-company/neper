// Section 12's inlining, nested (D212): `main` calls `mid.twice`, which calls
// `leaf.add`, and both are small enough to inline, so a release build copies `add`'s
// body into `twice` and that into `main`. The exit code is `twice` of the argument
// count so nothing folds. With `trap` as the last argument, `mid.fail` reaches
// `leaf.boom`, whose `unreachable` traps in every mode: the record names leaf.e
// through both copies, and the release backtrace has one frame, the debug build's
// three, since a debug build does not inline (D211). The edit under `edits/` changes
// `add`'s body alone, and `--incremental` has to rebuild all three modules.
use e.os
use e.mem
use e.str
use mid

fn main(a: *mem.Arena, args: []str) -> err {
    if str.eq(args[args.len - 1usize], "trap") { mid.fail() }
    os.exit(i32(mid.twice(args.len)))
    ret ok
}
