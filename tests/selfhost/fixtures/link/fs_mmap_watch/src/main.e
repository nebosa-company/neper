// `e.fs.mmap` and `e.fs.watch`: a file mapped read-only and writable by path, the
// write flushed and read back through a fresh mapping, the empty and missing cases;
// and a directory watch seeing a file added, with the recursive form refused.
// Every check has its own exit code.
use e.os
use e.mem
use e.fs.mmap as mmap
use e.fs.watch as watch

fn write_whole(a: *mem.Arena, path: str, bytes: []const u8) -> err {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret open_error }
    let (written, write_error) = os.write(file, bytes)
    let close_error = os.close(file)
    if write_error != ok { ret write_error }
    if written != bytes.len { ret os.Failed }
    ret close_error
}

fn ends_with(text: str, suffix: str) -> bool {
    if suffix.len > text.len { ret false }
    var at = 0usize
    while at < suffix.len {
        if text[text.len - suffix.len + at] != suffix[at] { ret false }
        at += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let stale = os.remove_file(a, "np-fs-map.bin")
    if stale != ok && stale != os.NotFound { os.exit(9) }
    var original: [16]u8 = zero
    var at = 0usize
    while at < 16usize {
        original[at] = u8(at) + 65u8
        at += 1usize
    }
    if write_whole(a, "np-fs-map.bin", original[..]) != ok { os.exit(10) }
    let (_, empty) = mmap.open(a, "np-fs-map.bin", false, 0u64, 0usize)
    if empty != mmap.Empty { os.exit(11) }
    let (reader, reader_error) = mmap.open(a, "np-fs-map.bin", false, 0u64, 16usize)
    if reader_error != ok { os.exit(12) }
    let seen = mmap.bytes(reader)
    if seen.len != 16usize || seen[0] != 65u8 || seen[15] != 80u8 { os.exit(13) }
    if mmap.close(reader) != ok { os.exit(14) }
    let (writer, writer_error) = mmap.open(a, "np-fs-map.bin", true, 0u64, 16usize)
    if writer_error != ok { os.exit(15) }
    let region = mmap.bytes(writer)
    region[0] = 122u8
    region[15] = 121u8
    if mmap.flush(writer) != ok { os.exit(16) }
    if mmap.close(writer) != ok { os.exit(17) }
    let (again, again_error) = mmap.open(a, "np-fs-map.bin", false, 0u64, 16usize)
    if again_error != ok { os.exit(18) }
    let back = mmap.bytes(again)
    if back[0] != 122u8 || back[15] != 121u8 || back[1] != 66u8 { os.exit(19) }
    if mmap.close(again) != ok { os.exit(20) }
    let (_, missing) = mmap.open(a, "np-fs-map-absent.bin", false, 0u64, 4usize)
    if missing == ok { os.exit(21) }
    if os.remove_file(a, "np-fs-map.bin") != ok { os.exit(22) }
    // Watching: a fresh directory, a file added, seen through the watch.
    let stale_file = os.remove_file(a, "np-fs-watch/seen.txt")
    let stale_dir = os.remove_dir(a, "np-fs-watch")
    if os.mkdir(a, "np-fs-watch") != ok { os.exit(30) }
    let (_, deep) = watch.open(a, "np-fs-watch", true)
    if deep != watch.Unsupported { os.exit(31) }
    let (w, watch_error) = watch.open(a, "np-fs-watch", false)
    if watch_error != ok { os.exit(32) }
    var one: [1]u8 = [1]u8{ 97 }
    if write_whole(a, "np-fs-watch/seen.txt", one[..]) != ok { os.exit(33) }
    var events: [16]watch.Event = zero
    let (count, read_error) = watch.read(a, w, events[..])
    if read_error != ok { os.exit(34) }
    var added = false
    at = 0usize
    while at < count {
        if events[at].action == .Added && ends_with(events[at].path, "seen.txt") { added = true }
        at += 1usize
    }
    if !added { os.exit(35) }
    if watch.close(w) != ok { os.exit(36) }
    if os.remove_file(a, "np-fs-watch/seen.txt") != ok { os.exit(37) }
    if os.remove_dir(a, "np-fs-watch") != ok { os.exit(38) }
    os.exit(0)
    ret ok
}
