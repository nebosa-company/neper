// A cleanup's failure does not overwrite the primary failure's detail (D360, H07):
// a `stat` of a missing name records `NotFound`; a directory closed twice fails its
// second close, a cleanup, and `last_error_detail` still answers the `stat`. Once
// that detail is read, the next failing cleanup is recorded like any failure. The
// double close is the audited exception the fixture needs, so `main` is `@unsafe`.
use e.mem
use e.os

@unsafe
fn main(a: *mem.Arena, args: []str) -> err {
    let (missing, missing_error) = os.stat(a, "np-no-such-file-anywhere")
    if missing_error != os.NotFound { os.exit(10i32) }
    let (dir, dir_error) = os.dir_open(a, ".")
    if dir_error != ok { ret dir_error }
    let first_close = os.dir_close(dir)
    if first_close != ok { ret first_close }
    // The second close fails: a cleanup over a primary failure not yet read.
    if os.dir_close(dir) == ok { os.exit(11i32) }
    let detail = os.last_error_detail("stat", "np-no-such-file-anywhere")
    if detail.kind != .NotFound { os.exit(12i32) }
    let primary_code = detail.native_code
    if primary_code == 0i32 { os.exit(13i32) }
    // Read, the primary is done with; a failing cleanup is now the last error.
    if os.dir_close(dir) == ok { os.exit(14i32) }
    let later = os.last_error_detail("dir_close", ".")
    if later.native_code == 0i32 || later.native_code == primary_code { os.exit(15i32) }
    if later.kind == .NotFound { os.exit(16i32) }
    // The caller's detail on the checked path (D417): `stat_detail` writes the
    // failure into the caller's value at the call, so a failing cleanup after it and
    // another failing operation after that change nothing the caller holds.
    var held: os.ErrorDetail = zero
    let (absent, absent_error) = os.stat_detail(a, "np-no-such-file-anywhere", &held)
    if absent_error != os.NotFound { os.exit(17i32) }
    if held.kind != .NotFound || held.native_code == 0i32 { os.exit(18i32) }
    if os.dir_close(dir) == ok { os.exit(19i32) }
    let (twice, twice_error) = os.stat(a, "np-no-such-file-either")
    if twice_error != os.NotFound { os.exit(20i32) }
    if held.kind != .NotFound || held.native_code != primary_code { os.exit(21i32) }
    var untouched: os.ErrorDetail = zero
    let (here, here_error) = os.dir_open_detail(a, ".", &untouched)
    if here_error != ok { ret here_error }
    if untouched.native_code != 0i32 { os.exit(22i32) }
    ret os.dir_close(here)
}
