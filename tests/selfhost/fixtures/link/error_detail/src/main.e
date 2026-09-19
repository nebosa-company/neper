// A cleanup's failure does not overwrite the primary failure's detail (D360, H07):
// a `stat` of a missing name records `NotFound`; a directory closed twice fails its
// second close, a cleanup, and `last_error_detail` still answers the `stat`. Once
// that detail is read, the next failing cleanup is recorded like any failure. The
// double close is the audited exception the fixture needs, so `main` is `@unsafe`.
use e.fs
use e.io
use e.mem
use e.os

type IoDetailJob = struct {
    writing: bool,
    count: usize,
    failure: err,
    detail: os.ErrorDetail,
}

// The invalid handle is deliberate: it makes the same operation fail without a
// filesystem race on both hosts. Each worker writes only its own caller-owned job.
@unsafe
fn io_detail_job(job: *IoDetailJob) {
    var invalid: os.File = zero
    invalid.raw = 18446744073709551615usize
    if job.writing {
        let (count, failure) = os.write_detail(invalid, "x", &job.detail)
        job.count = count
        job.failure = failure
    } else {
        var byte: [1]u8 = zero
        let (count, failure) = os.read_detail(invalid, byte[..], &job.detail)
        job.count = count
        job.failure = failure
    }
    let _ = os.close(invalid)
}

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

    // Byte I/O in the checked form (D614): native provenance is copied directly,
    // counts retain the ordinary partial-progress contract, and success does not
    // overwrite an earlier caller-owned failure.
    var read_job: IoDetailJob = zero
    io_detail_job(&read_job)
    if read_job.failure == ok || read_job.count != 0usize { os.exit(42i32) }
    if read_job.detail.native_code == 0i32 || !mem.eq[u8](read_job.detail.operation, "read") || read_job.detail.subject.len != 0usize { os.exit(43i32) }
    var write_job = IoDetailJob { writing: true, count: 0usize, failure: ok, detail: zero }
    io_detail_job(&write_job)
    if write_job.failure == ok || write_job.count != 0usize { os.exit(44i32) }
    if write_job.detail.native_code == 0i32 || !mem.eq[u8](write_job.detail.operation, "write") || write_job.detail.subject.len != 0usize { os.exit(45i32) }

    let read_code = read_job.detail.native_code
    let write_code = write_job.detail.native_code
    let (reading, writing, pipe_error) = os.pipe()
    if pipe_error != ok { ret pipe_error }
    let (sent, send_error) = os.write_detail(writing, "x", &read_job.detail)
    if send_error != ok || sent != 1usize { os.exit(46i32) }
    var byte: [1]u8 = zero
    let (received, receive_error) = os.read_detail(reading, byte[..], &write_job.detail)
    if receive_error != ok || received != 1usize || byte[0usize] != 120u8 { os.exit(47i32) }
    if read_job.detail.native_code != read_code || !mem.eq[u8](read_job.detail.operation, "read") { os.exit(48i32) }
    if write_job.detail.native_code != write_code || !mem.eq[u8](write_job.detail.operation, "write") { os.exit(49i32) }
    if os.close(reading) != ok || os.close(writing) != ok { os.exit(50i32) }

    // The generic checked reader carries the same caller-owned provenance through
    // `e.io`; it does not fall back to the temporal compatibility slot.
    var invalid_reader_file: os.File = zero
    invalid_reader_file.raw = 18446744073709551615usize
    var checked_reader = io.file_detail_reader(&invalid_reader_file)
    var checked_byte: [1]u8 = zero
    var checked_read_detail: os.ErrorDetail = zero
    let (checked_read_count, checked_read_error) = io.read_detail(&checked_reader, checked_byte[..], &checked_read_detail)
    if checked_read_error == ok || checked_read_count != 0usize { os.exit(56i32) }
    if checked_read_detail.native_code == 0i32 || !mem.eq[u8](checked_read_detail.operation, "read") { os.exit(57i32) }
    let _ = os.close(invalid_reader_file)

    var invalid_writer_file: os.File = zero
    invalid_writer_file.raw = 18446744073709551615usize
    var checked_writer = io.file_detail_writer(&invalid_writer_file)
    var checked_write_detail: os.ErrorDetail = zero
    let (checked_write_count, checked_write_error) = io.write_detail(&checked_writer, "x", &checked_write_detail)
    if checked_write_error == ok || checked_write_count != 0usize { os.exit(58i32) }
    if checked_write_detail.native_code == 0i32 || !mem.eq[u8](checked_write_detail.operation, "write") { os.exit(59i32) }
    let _ = os.close(invalid_writer_file)

    var nested_invalid_file: os.File = zero
    nested_invalid_file.raw = 18446744073709551615usize
    var nested_detail: os.ErrorDetail = zero
    var nested_file_sink = io.file_detail_writer(&nested_invalid_file)
    var (nested_handle, nested_handle_error) = io.buffered_detail_writer(a, nested_file_sink, 4usize, &nested_detail)
    if nested_handle_error != ok { ret nested_handle_error }
    var nested_sink = io.buffered_detail_sink(&nested_handle)
    let (nested_count, nested_write_error) = io.write_all_detail(&nested_sink, "held", &nested_detail)
    if nested_write_error != ok || nested_count != 4usize { os.exit(60i32) }
    if io.flush_detail(&nested_sink, &nested_detail) == ok { os.exit(61i32) }
    if nested_detail.native_code == 0i32 || !mem.eq[u8](nested_detail.operation, "write") { os.exit(62i32) }
    let _ = os.close(nested_invalid_file)

    // Caller-owned details remain independent when the operations overlap. A host
    // without runtime threads has already exercised both checked calls above.
    var concurrent_read_job: IoDetailJob = zero
    var concurrent_write_job = IoDetailJob { writing: true, count: 0usize, failure: ok, detail: zero }
    let (read_worker, read_started) = os.thread_create[IoDetailJob](io_detail_job, &concurrent_read_job, 1048576usize)
    if read_started != os.Unsupported {
        if read_started != ok { ret read_started }
        let (write_worker, write_started) = os.thread_create[IoDetailJob](io_detail_job, &concurrent_write_job, 1048576usize)
        if write_started != ok {
            let _ = os.thread_join(read_worker)
            ret write_started
        }
        if os.thread_join(read_worker) != ok { os.exit(63i32) }
        if os.thread_join(write_worker) != ok { os.exit(64i32) }
        if concurrent_read_job.failure == ok || concurrent_write_job.failure == ok { os.exit(65i32) }
        if !mem.eq[u8](concurrent_read_job.detail.operation, "read") || !mem.eq[u8](concurrent_write_job.detail.operation, "write") { os.exit(66i32) }
        if concurrent_read_job.detail.native_code == 0i32 || concurrent_write_job.detail.native_code == 0i32 { os.exit(67i32) }
    }
    ret os.dir_close(here)
}
