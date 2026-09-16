// A cleanup's failure does not overwrite the primary failure's detail (D360, H07):
// a `stat` of a missing name records `NotFound`; a directory closed twice fails its
// second close, a cleanup, and `last_error_detail` still answers the `stat`. Once
// that detail is read, the next failing cleanup is recorded like any failure. The
// double close is the audited exception the fixture needs, so `main` is `@unsafe`.
use e.fs
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
    // The rest of the path-taking surface (D443): each `_detail` form names its own
    // operation in the caller's value, and a call that succeeds writes nothing.
    var removed: os.ErrorDetail = zero
    if os.remove_file_detail(a, "np-no-such-file-anywhere", &removed) == ok { os.exit(23i32) }
    if removed.kind != .NotFound || !mem.eq[u8](removed.operation, "remove_file") { os.exit(24i32) }
    var renamed: os.ErrorDetail = zero
    if os.rename_detail(a, "np-no-such-file-anywhere", "np-no-such-file-either", &renamed) == ok { os.exit(25i32) }
    if renamed.kind != .NotFound || !mem.eq[u8](renamed.subject, "np-no-such-file-anywhere") { os.exit(26i32) }
    var linked: os.ErrorDetail = zero
    let (points_to, link_error) = os.read_link_detail(a, "np-no-such-file-anywhere", &linked)
    if link_error == ok || linked.native_code == 0i32 || !mem.eq[u8](linked.operation, "read_link") { os.exit(27i32) }
    var made: os.ErrorDetail = zero
    if os.mkdir_detail(a, ".", &made) == ok { os.exit(28i32) }
    if made.native_code == 0i32 || !mem.eq[u8](made.operation, "mkdir") { os.exit(29i32) }
    var present: os.ErrorDetail = zero
    let (info, info_error) = os.lstat_detail(a, ".", &present)
    if info_error != ok { ret info_error }
    if present.native_code != 0i32 { os.exit(30i32) }
    // `e.fs` in the same form (D479): its errors are the fence's five, and the detail
    // is the host call that failed -- `stat` under `read_file`, `rename` under `move`.
    var fs_missing: os.ErrorDetail = zero
    let (fs_entry, fs_entry_error) = fs.stat_detail(a, "np-no-such-file-anywhere", &fs_missing)
    if fs_entry_error != fs.NotFound { os.exit(31i32) }
    if fs_missing.kind != .NotFound || fs_missing.native_code != primary_code || !mem.eq[u8](fs_missing.operation, "stat") { os.exit(32i32) }
    var fs_read: os.ErrorDetail = zero
    let (fs_bytes, fs_read_error) = fs.read_file_detail(a, "np-no-such-file-anywhere", 0usize, &fs_read)
    if fs_read_error != fs.NotFound || !mem.eq[u8](fs_read.operation, "stat") || !mem.eq[u8](fs_read.subject, "np-no-such-file-anywhere") { os.exit(33i32) }
    var fs_moved: os.ErrorDetail = zero
    if fs.move_detail(a, "np-no-such-file-anywhere", "np-no-such-file-either", &fs_moved) != fs.NotFound { os.exit(34i32) }
    if fs_moved.kind != .NotFound || !mem.eq[u8](fs_moved.operation, "rename") { os.exit(35i32) }
    var fs_removed: os.ErrorDetail = zero
    if fs.remove_dir_detail(a, "np-no-such-file-anywhere", &fs_removed) != fs.NotFound { os.exit(36i32) }
    if !mem.eq[u8](fs_removed.operation, "remove_dir") { os.exit(37i32) }
    var fs_resolved: os.ErrorDetail = zero
    let (fs_canon, fs_canon_error) = fs.canonical_detail(a, "np-no-such-file-anywhere", &fs_resolved)
    if fs_canon_error == ok || fs_resolved.native_code == 0i32 || !mem.eq[u8](fs_resolved.operation, "canonical") { os.exit(38i32) }
    var fs_present: os.ErrorDetail = zero
    let (fs_meta, fs_meta_error) = fs.metadata_detail(a, ".", false, &fs_present)
    if fs_meta_error != ok { ret fs_meta_error }
    if fs_present.native_code != 0i32 || fs_meta.kind != .Directory { os.exit(39i32) }
    var fs_dirs: os.ErrorDetail = zero
    if fs.make_dirs_detail(a, ".", &fs_dirs) != ok { os.exit(40i32) }
    if fs_dirs.native_code != 0i32 { os.exit(41i32) }
    ret os.dir_close(here)
}
