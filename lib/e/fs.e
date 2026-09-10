// The filesystem, as one portable file. Nothing here is per target: every host
// difference is behind `e.os`, which D32 makes the sole OS surface of `lib/e` and which
// is the module written per target. What that leaves for this file is the part that is
// the same everywhere -- deciding which primitive a call is, turning a platform's
// classification into this module's errors, and the loops that a copy or a walk is.
//
// `e.path` supplies the string work and asks the host nothing, so this file hands it
// the style the target actually uses; `os.NATIVE_SEPARATOR` is where that comes from.

use e.mem
use e.os
use e.path

type EntryKind = enum u8 { File, Directory, Symlink, Other }
type Entry = struct { path: str, kind: EntryKind, size: u64 }
type Permissions = struct { owner_read: bool, owner_write: bool, owner_exec: bool, group_read: bool, group_write: bool, group_exec: bool, other_read: bool, other_write: bool, other_exec: bool }
type Metadata = struct { kind: EntryKind, size: u64, modified_ns: i64, accessed_ns: i64, created_ns: i64, permissions: Permissions, file_id: u64, link_count: u64 }
type Walk = struct { state: *void }
type WalkOptions = struct { recursive: bool, follow_symlinks: bool }
type ReplaceOptions = struct { overwrite: bool, durable: bool }
type Root = struct { dir: os.Dir }

error NotFound
error Exists
error Denied
error Invalid
error Io

// A traversal is one listing per level, and a level is a directory that has been read
// and how far through it the caller is.
// ponytail: a fixed depth, because the levels are one arena allocation made when the
// walk opens; a growing stack is what to write if a real tree ever exceeds it.
const WALK_DEPTH: usize = 64usize

type WalkLevel = struct { path: str, entries: []os.DirEntry, at: usize }

type WalkState = struct {
    arena: *mem.Arena,
    options: WalkOptions,
    levels: []WalkLevel,
    depth: usize,
}

// `e.os` classifies a platform code into its own closed set; this turns that into this
// module's, which is the only place the two vocabularies meet.
fn from_os(source: err) -> err {
    if source == ok { ret ok }
    if source == os.NotFound { ret NotFound }
    if source == os.Exists { ret Exists }
    if source == os.Denied { ret Denied }
    if source == os.OutOfMemory { ret mem.Exhausted }
    // What the host will not do at all is not the same as what it refused to do, and
    // neither is an I/O failure: both are `Invalid` here, which is the fence's word for
    // a request that cannot be honoured as asked.
    if source == os.Unsupported { ret Invalid }
    ret Io
}

// The host's own account of the call that just failed. `from_os` above deliberately loses
// it -- five errors is what this fence promises and a native code is not one of them -- so a
// caller that wants to say *why* asks here, before any cleanup that could replace it. The
// slot is per thread and may be absent, never another thread's (D132), which is `e.os`'s
// guarantee and not a stronger one made here.
fn last_error_detail(operation: str, subject: str) -> os.ErrorDetail {
    ret os.last_error_detail(operation, subject)
}

fn host_style() -> path.Style {
    if os.NATIVE_SEPARATOR == 92u8 { ret .Windows }
    ret .Posix
}

fn kind_from_os(source: os.EntryKind) -> EntryKind {
    if source == .File { ret .File }
    if source == .Dir { ret .Directory }
    if source == .Symlink { ret .Symlink }
    ret .Other
}

// `NotFound` is an answer here rather than a failure -- that is what the question was --
// while a path that cannot be looked at at all still fails.
fn exists(a: *mem.Arena, path_text: str) -> (bool, err) {
    let (info, stat_error) = os.stat(a, path_text)
    if stat_error == os.NotFound { ret (false, ok) }
    if stat_error != ok { ret (false, from_os(stat_error)) }
    ret (true, ok)
}

// The path in the `Entry` is the one the caller gave: this call looks something up, it
// does not resolve or normalise it.
fn stat(a: *mem.Arena, path_text: str) -> (Entry, err) {
    var entry: Entry = zero
    let (info, stat_error) = os.stat(a, path_text)
    if stat_error != ok { ret (entry, from_os(stat_error)) }
    entry.path = path_text
    entry.kind = kind_from_os(info.kind)
    entry.size = info.size
    ret (entry, ok)
}

// `e.os` carries permissions as the POSIX bits, because that is what one of the two
// hosts actually stores; naming the nine is this module's job, and the host that has one
// read-only flag instead answers the same for all three classes rather than inventing a
// distinction nothing enforces.
fn permissions_from_mode(mode: u32) -> Permissions {
    var permissions: Permissions = zero
    permissions.owner_read = mode & 256u32 != 0u32
    permissions.owner_write = mode & 128u32 != 0u32
    permissions.owner_exec = mode & 64u32 != 0u32
    permissions.group_read = mode & 32u32 != 0u32
    permissions.group_write = mode & 16u32 != 0u32
    permissions.group_exec = mode & 8u32 != 0u32
    permissions.other_read = mode & 4u32 != 0u32
    permissions.other_write = mode & 2u32 != 0u32
    permissions.other_exec = mode & 1u32 != 0u32
    ret permissions
}

// The reverse of `permissions_from_mode`, for the calls that write. A host that keeps no
// POSIX bits reads only the owner-write one out of this.
fn mode_from_permissions(permissions: Permissions) -> u32 {
    var mode = 0u32
    if permissions.owner_read { mode = mode | 256u32 }
    if permissions.owner_write { mode = mode | 128u32 }
    if permissions.owner_exec { mode = mode | 64u32 }
    if permissions.group_read { mode = mode | 32u32 }
    if permissions.group_write { mode = mode | 16u32 }
    if permissions.group_exec { mode = mode | 8u32 }
    if permissions.other_read { mode = mode | 4u32 }
    if permissions.other_write { mode = mode | 2u32 }
    if permissions.other_exec { mode = mode | 1u32 }
    ret mode
}

// Everything the host records about one path. `follow_symlinks` chooses which path is
// described when the last component is a link -- the target, or the link itself -- which
// is the one question `stat` does not let a caller ask.
//
// A creation time is `-1` where the host does not keep one: Linux has none in the
// structure this is read from, so a caller comparing two of them has to allow for that
// rather than assume a zero.
fn metadata(a: *mem.Arena, path_text: str, follow_symlinks: bool) -> (Metadata, err) {
    var described: Metadata = zero
    var info: os.FileInfo = zero
    var info_error = ok
    if follow_symlinks {
        let (followed, followed_error) = os.stat(a, path_text)
        info = followed
        info_error = followed_error
    } else {
        let (direct, direct_error) = os.lstat(a, path_text)
        info = direct
        info_error = direct_error
    }
    if info_error != ok { ret (described, from_os(info_error)) }
    described.kind = kind_from_os(info.kind)
    described.size = info.size
    described.modified_ns = info.modified_ns
    described.accessed_ns = info.accessed_ns
    described.created_ns = info.created_ns
    described.permissions = permissions_from_mode(info.mode)
    described.file_id = info.file_id
    described.link_count = info.link_count
    ret (described, ok)
}

// What a host cannot represent it does not report as a failure: a Windows filesystem
// honours the owner-write bit and answers `metadata` with read and execute set whatever
// was asked for, and a filesystem that enforces no modes at all succeeds while changing
// nothing. Reading back with `metadata` is the only way to know what took.
fn set_permissions(a: *mem.Arena, path_text: str, permissions: Permissions) -> err {
    ret from_os(os.set_mode(a, path_text, mode_from_permissions(permissions)))
}

// A negative nanosecond count leaves that stamp as it is -- the same `-1` that `metadata`
// reports for a stamp the host does not keep -- so one of the two can be set alone.
// Precision is the filesystem's: one that stores whole seconds keeps the seconds.
fn set_times(a: *mem.Arena, path_text: str, accessed_ns: i64, modified_ns: i64) -> err {
    ret from_os(os.set_times(a, path_text, accessed_ns, modified_ns))
}

fn make_dir(a: *mem.Arena, path_text: str) -> err {
    ret from_os(os.mkdir(a, path_text))
}

// Every missing component, parent first. A component that is already a directory is not
// a failure -- that is the difference from `make_dir` -- but one that is already a file
// is, because the directory the caller asked for cannot exist.
fn make_dirs(a: *mem.Arena, path_text: str) -> err {
    let style = host_style()
    let checkpoint = mem.mark(a)
    let (normalized, normalize_error) = path.normalize(a, path_text, style)
    if normalize_error != ok {
        mem.reset(a, checkpoint)
        ret from_os(normalize_error)
    }
    var at = path.root_length(normalized, style)
    while at <= normalized.len {
        // Stop at each separator in turn, and finally at the whole path.
        if at == normalized.len || path.is_separator(normalized[at], style) {
            if at != 0usize {
                let prefix = normalized[0usize..at]
                let step_error = os.mkdir(a, prefix)
                if step_error != ok && step_error != os.Exists {
                    mem.reset(a, checkpoint)
                    ret from_os(step_error)
                }
                // An existing name has to be a directory, or the path cannot be made.
                if step_error == os.Exists {
                    let (info, stat_error) = os.stat(a, prefix)
                    if stat_error != ok {
                        mem.reset(a, checkpoint)
                        ret from_os(stat_error)
                    }
                    if info.kind != .Dir {
                        mem.reset(a, checkpoint)
                        ret Exists
                    }
                }
            }
        }
        at += 1usize
    }
    mem.reset(a, checkpoint)
    ret ok
}

// Twelve random bytes as twenty-four hex digits. Long enough that a collision is not
// something the retry loop is really for -- the loop is there because a collision is
// possible at all, not because it is expected.
const TEMP_NAME_BYTES: usize = 12usize
const TEMP_ATTEMPTS: usize = 16usize

fn hex_digit(value: u8) -> u8 {
    if value < 10u8 { ret 48u8 + value }
    ret 87u8 + value
}

// The name is created before it is returned, so there is no moment when a caller holds a
// name that something else could take. `os.create_new` is what closes that window: it
// fails rather than opening a file that is already there, which is also what the retry
// loop reads as a collision. An empty `dir` means the host's temporary directory.
fn temp_file(a: *mem.Arena, dir: str, prefix: str) -> (str, os.File, err) {
    var nothing: os.File = zero
    var directory = dir
    if directory.len == 0usize {
        let (fallback, fallback_error) = temp_dir(a)
        if fallback_error != ok { ret ("", nothing, fallback_error) }
        directory = fallback
    }
    let style = host_style()
    var attempt = 0usize
    while attempt < TEMP_ATTEMPTS {
        let checkpoint = mem.mark(a)
        var drawn: [12]u8 = zero
        let random_error = os.random(drawn[..])
        if random_error != ok {
            mem.reset(a, checkpoint)
            ret ("", nothing, from_os(random_error))
        }
        let total = directory.len + 1usize + prefix.len + TEMP_NAME_BYTES * 2usize
        let (bytes, allocation_error) = mem.alloc[u8](a, total)
        if allocation_error != ok {
            mem.reset(a, checkpoint)
            ret ("", nothing, allocation_error)
        }
        var at = 0usize
        while at < directory.len {
            bytes[at] = directory[at]
            at += 1usize
        }
        // A directory that already ends in a separator does not get a second one.
        if at != 0usize && !path.is_separator(bytes[at - 1usize], style) {
            bytes[at] = path.separator(style)
            at += 1usize
        }
        var offset = 0usize
        while offset < prefix.len {
            bytes[at + offset] = prefix[offset]
            offset += 1usize
        }
        at += prefix.len
        var drawn_at = 0usize
        while drawn_at < TEMP_NAME_BYTES {
            bytes[at] = hex_digit(drawn[drawn_at] / 16u8)
            bytes[at + 1usize] = hex_digit(drawn[drawn_at] % 16u8)
            at += 2usize
            drawn_at += 1usize
        }
        let candidate = bytes[0usize..at]
        let (file, create_error) = os.create_new(a, candidate)
        if create_error == ok { ret (candidate, file, ok) }
        // Anything but a name that was already taken is the caller's answer, not another
        // try: a directory that is not there will not become one.
        if create_error != os.Exists {
            mem.reset(a, checkpoint)
            ret ("", nothing, from_os(create_error))
        }
        mem.reset(a, checkpoint)
        attempt += 1usize
    }
    ret ("", nothing, Io)
}

// A directory held open, and every path used through it resolved against that handle
// rather than against a string. The difference is that the handle keeps naming the same
// directory even if the path that opened it is renamed underneath -- which is the whole
// reason the `*_at` family exists and a path-based call cannot stand in for it.
fn root(a: *mem.Arena, path_text: str) -> (Root, err) {
    var opened: Root = zero
    let (dir, dir_error) = os.dir_open(a, path_text)
    if dir_error != ok { ret (opened, from_os(dir_error)) }
    opened.dir = dir
    ret (opened, ok)
}

fn root_close(r: *Root) -> err {
    ret from_os(os.dir_close(r.dir))
}

// `policy` is enforced by the host while it walks, not checked here beforehand: a check
// made first would be about a path something else can change before the open happens.
// What is checked here is the shape of the name -- absolute, `..` or an embedded NUL are
// refused outright, because none of them is a name under this root.
//
// `Beneath` is not available on every host. Where it is not, this says so rather than
// falling back to a lexical test that would look like the same guarantee.
fn open_at(a: *mem.Arena, r: *const Root, relative_path: str, flags: os.OpenFlags, policy: os.ResolvePolicy) -> (os.File, err) {
    let (file, open_error) = os.open_at(a, r.dir, relative_path, flags, policy)
    if open_error != ok { ret (file, from_os(open_error)) }
    ret (file, ok)
}

// The path to the final component is walked with links refused, and the final component
// itself is removed as whatever it is -- so removing a symbolic link removes the link, not
// what it points at. `directory` picks which of the two a name is allowed to be, because a
// caller that meant one and got the other has a bug this call can catch.
fn remove_at(a: *mem.Arena, r: *const Root, relative_path: str, directory: bool) -> err {
    ret from_os(os.remove_at(a, r.dir, relative_path, directory))
}

// Between two roots, which may be the same one. Both sides resolve under the policy, so
// neither path is a string joined to a directory's name -- and `options` means here what
// it means for `replace`: whether an existing destination is replaced, and whether the
// name is on the disk before this returns.
fn replace_at(a: *mem.Arena, src_root: *const Root, src_path: str, dst_root: *const Root, dst_path: str, options: ReplaceOptions) -> err {
    ret from_os(os.rename_at(a, src_root.dir, src_path, dst_root.dir, dst_path, options.overwrite, options.durable))
}

// The one name for a file, with every symbolic link and every `.` and `..` gone. It needs
// the path to exist, because both hosts answer it by opening the path and asking what was
// opened -- there is nothing to resolve about a name that leads nowhere. It is also the
// only way to tell whether two paths are the same file, since `executable_path` and a
// path a caller built are not guaranteed to be written the same way.
fn canonical(a: *mem.Arena, path_text: str) -> (str, err) {
    let (resolved, resolve_error) = os.canonical(a, path_text)
    if resolve_error != ok { ret ("", from_os(resolve_error)) }
    ret (resolved, ok)
}

// A candidate the host named, kept only if it is really there and really a directory.
// That is what makes a list of candidates worth having: the first name that is set is not
// necessarily the one that works.
fn env_directory(a: *mem.Arena, name: str) -> (str, bool) {
    let (value, value_error) = os.env(a, name)
    if value_error != ok || value.len == 0usize { ret ("", false) }
    let (info, info_error) = os.stat(a, value)
    if info_error != ok || info.kind != .Dir { ret ("", false) }
    ret (value, true)
}

// Which names to ask for is the second thing in this module that depends on the host, and
// it comes from the same place the first one does. Nothing here creates the directory or
// checks that it can be written to -- `temp_file` is what would have to.
fn temp_dir(a: *mem.Arena) -> (str, err) {
    if host_style() == .Windows {
        let (tmp, tmp_found) = env_directory(a, "TMP")
        if tmp_found { ret (tmp, ok) }
        let (temp, temp_found) = env_directory(a, "TEMP")
        if temp_found { ret (temp, ok) }
        ret ("", NotFound)
    }
    let (named, named_found) = env_directory(a, "TMPDIR")
    if named_found { ret (named, ok) }
    // The one every Unix has whether or not anything named it.
    let (fallback, fallback_error) = os.stat(a, "/tmp")
    if fallback_error == ok && fallback.kind == .Dir { ret ("/tmp", ok) }
    ret ("", NotFound)
}

// The environment is the only thing asked. A host where the account has no home says so,
// rather than this guessing at one from a user name.
fn home_dir(a: *mem.Arena) -> (str, err) {
    if host_style() == .Windows {
        let (profile, profile_found) = env_directory(a, "USERPROFILE")
        if profile_found { ret (profile, ok) }
        ret ("", NotFound)
    }
    let (home, home_found) = env_directory(a, "HOME")
    if home_found { ret (home, ok) }
    ret ("", NotFound)
}

// The running program's own path, absolute. What the host records is not quite the same
// thing on both -- one resolves the symbolic links in it and the other does not -- so a
// caller comparing it against a path of its own should compare what `canonical` makes of
// them rather than the strings.
fn executable_path(a: *mem.Arena) -> (str, err) {
    let (image, image_error) = os.executable_path(a)
    if image_error != ok { ret ("", from_os(image_error)) }
    ret (image, ok)
}

// Where relative paths resolve from, absolute and in the host convention. This is the one
// pair in this module that reads and writes state belonging to the whole process rather
// than to a path, so a caller that moves is the one that has to move back -- and every
// other call here becomes ambiguous while it is moved.
fn current_dir(a: *mem.Arena) -> (str, err) {
    let (path_text, read_error) = os.current_dir(a)
    if read_error != ok { ret ("", from_os(read_error)) }
    ret (path_text, ok)
}

fn set_current_dir(a: *mem.Arena, path_text: str) -> err {
    ret from_os(os.set_current_dir(a, path_text))
}

// The target as it was stored, resolving nothing: a relative link gives back a relative
// string, which is what it means. A path that is not a link is `Invalid`.
fn read_link(a: *mem.Arena, path_text: str) -> (str, err) {
    let (target_text, read_error) = os.read_link(a, path_text)
    if read_error != ok { ret ("", from_os(read_error)) }
    ret (target_text, ok)
}

// `target_path` is stored as given; nothing checks that it leads anywhere, because a link
// to something that does not exist yet is a link. Making one is privileged on some hosts,
// where this is `Denied`.
fn symlink(a: *mem.Arena, target_path: str, link: str) -> err {
    ret from_os(os.symlink(a, target_path, link))
}

// A symbolic link is removed as itself on both hosts: the name goes, what it pointed at
// stays.
fn remove_file(a: *mem.Arena, path_text: str) -> err {
    ret from_os(os.remove_file(a, path_text))
}

// An empty directory only. A non-empty one fails, which is what makes a recursive
// delete something a caller writes rather than something this call does by surprise.
fn remove_dir(a: *mem.Arena, path_text: str) -> err {
    ret from_os(os.remove_dir(a, path_text))
}

// `move` with the two questions answered explicitly. `overwrite` decides whether a
// destination that is already there is replaced or the call fails; `durable` decides
// whether the result is on the disk before it returns, which is what a caller writing a
// file and swapping it into place is really after. Crossing a filesystem is `Invalid`
// either way -- neither host will do it atomically, and neither will copy behind the
// caller's back.
fn replace(a: *mem.Arena, src: str, dst: str, options: ReplaceOptions) -> err {
    ret from_os(os.replace(a, src, dst, options.overwrite, options.durable))
}

// Within one filesystem. Across two, the host refuses and says so rather than copying
// behind the caller's back.
fn move(a: *mem.Arena, src: str, dst: str) -> err {
    ret from_os(os.rename(a, src, dst))
}

// `limit` caps what will be allocated. A file larger than it is `Invalid` rather than a
// short read, because a caller that gets fewer bytes than the file holds has no way to
// tell that from the whole of a shorter file. `limit == 0` means no cap.
fn read_file(a: *mem.Arena, path_text: str, limit: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let (info, stat_error) = os.stat(a, path_text)
    if stat_error != ok { ret (nothing, from_os(stat_error)) }
    if info.kind == .Dir { ret (nothing, Invalid) }
    let size = usize(info.size)
    if limit != 0usize && size > limit { ret (nothing, Invalid) }
    var flags: os.OpenFlags = zero
    flags.read = true
    let (file, open_error) = os.open(a, path_text, flags)
    if open_error != ok { ret (nothing, from_os(open_error)) }
    let (bytes, allocation_error) = mem.alloc[u8](a, size)
    if allocation_error != ok {
        let ignored = os.close(file)
        ret (nothing, allocation_error)
    }
    var filled = 0usize
    while filled < size {
        let (read_count, read_error) = os.read(file, bytes[filled..size])
        if read_error != ok {
            let ignored = os.close(file)
            ret (nothing, from_os(read_error))
        }
        // A file that shrank between the size and the read: what was read is what
        // there is, and the answer is that much of it.
        if read_count == 0usize { break }
        filled += read_count
    }
    let close_error = os.close(file)
    if close_error != ok { ret (nothing, from_os(close_error)) }
    ret (bytes[0usize..filled], ok)
}

// The file is created if it is not there and truncated if it is, so what it holds
// afterwards is exactly `data`.
fn write_file(a: *mem.Arena, path_text: str, data: []const u8) -> err {
    var flags: os.OpenFlags = zero
    flags.write = true
    flags.create = true
    flags.truncate = true
    let (file, open_error) = os.open(a, path_text, flags)
    if open_error != ok { ret from_os(open_error) }
    var sent = 0usize
    while sent < data.len {
        let (written, write_error) = os.write(file, data[sent..data.len])
        if write_error != ok {
            let ignored = os.close(file)
            ret from_os(write_error)
        }
        // A write that moves nothing would spin here rather than fail, so it is the
        // failure.
        if written == 0usize {
            let ignored = os.close(file)
            ret Io
        }
        sent += written
    }
    ret from_os(os.close(file))
}

// Through the caller's buffer, so a copy costs what the caller chose to spend and no
// arena at all. An empty buffer would make no progress, so it is rejected rather than
// looping.
fn copy_file(a: *mem.Arena, src: str, dst: str, scratch: []u8) -> err {
    if scratch.len == 0usize { ret Invalid }
    var read_flags: os.OpenFlags = zero
    read_flags.read = true
    let (source, source_error) = os.open(a, src, read_flags)
    if source_error != ok { ret from_os(source_error) }
    var write_flags: os.OpenFlags = zero
    write_flags.write = true
    write_flags.create = true
    write_flags.truncate = true
    let (destination, destination_error) = os.open(a, dst, write_flags)
    if destination_error != ok {
        let ignored = os.close(source)
        ret from_os(destination_error)
    }
    while true {
        let (read_count, read_error) = os.read(source, scratch)
        if read_error != ok {
            let ignored_source = os.close(source)
            let ignored_destination = os.close(destination)
            ret from_os(read_error)
        }
        if read_count == 0usize { break }
        var sent = 0usize
        while sent < read_count {
            let (written, write_error) = os.write(destination, scratch[sent..read_count])
            if write_error != ok {
                let ignored_source = os.close(source)
                let ignored_destination = os.close(destination)
                ret from_os(write_error)
            }
            if written == 0usize {
                let ignored_source = os.close(source)
                let ignored_destination = os.close(destination)
                ret Io
            }
            sent += written
        }
    }
    let source_close = os.close(source)
    let destination_close = os.close(destination)
    if source_close != ok { ret from_os(source_close) }
    ret from_os(destination_close)
}

fn push_level(state: *WalkState, directory: str) -> err {
    if state.depth == state.levels.len { ret Invalid }
    let (entries, read_error) = os.readdir(state.arena, directory)
    if read_error != ok { ret from_os(read_error) }
    state.levels[state.depth].path = directory
    state.levels[state.depth].entries = entries
    state.levels[state.depth].at = 0usize
    state.depth += 1usize
    ret ok
}

// The root's own entry is not produced: a walk yields what is under the root, which is
// what makes the root's name the caller's and every yielded name this call's.
fn walk(a: *mem.Arena, root_path: str, options: WalkOptions) -> (Walk, err) {
    var it: Walk = zero
    let (holder, holder_error) = mem.alloc[WalkState](a, 1usize)
    if holder_error != ok { ret (it, holder_error) }
    let (levels, levels_error) = mem.alloc[WalkLevel](a, WALK_DEPTH)
    if levels_error != ok { ret (it, levels_error) }
    holder[0usize].arena = a
    holder[0usize].options = options
    holder[0usize].levels = levels
    holder[0usize].depth = 0usize
    let push_error = push_level(&holder[0usize], root_path)
    if push_error != ok { ret (it, push_error) }
    it.state = mem.cast[*void](&holder[0usize])
    ret (it, ok)
}

// One entry per call, `false` when there are none left. A directory is yielded before
// what is inside it, so a caller that stops early has still been told the directory
// exists.
fn walk_next_err(it: *Walk) -> (Entry, bool, err) {
    var entry: Entry = zero
    let state = mem.cast[*WalkState](it.state)
    while state.depth != 0usize {
        let level = state.depth - 1usize
        if state.levels[level].at == state.levels[level].entries.len {
            state.depth = state.depth - 1usize
            continue
        }
        let name = state.levels[level].entries[state.levels[level].at].name
        state.levels[level].at += 1usize
        var parts: [2]str = zero
        parts[0usize] = state.levels[level].path
        parts[1usize] = name
        let (full, join_error) = path.join(state.arena, parts[..], host_style())
        if join_error != ok { ret (entry, false, from_os(join_error)) }
        // The listing gives a kind but no size, and whether the link or its target is
        // described is the caller's choice, so each entry is looked up.
        var info: os.FileInfo = zero
        var info_error = ok
        if state.options.follow_symlinks {
            let (followed, followed_error) = os.stat(state.arena, full)
            info = followed
            info_error = followed_error
        } else {
            let (direct, direct_error) = os.lstat(state.arena, full)
            info = direct
            info_error = direct_error
        }
        // An entry that went away between the listing and the lookup is skipped: it
        // was there when the directory was read and is not an error of this walk.
        if info_error == os.NotFound { continue }
        if info_error != ok { ret (entry, false, from_os(info_error)) }
        entry.path = full
        entry.kind = kind_from_os(info.kind)
        entry.size = info.size
        if state.options.recursive && info.kind == .Dir {
            let descend_error = push_level(state, full)
            if descend_error != ok { ret (entry, false, descend_error) }
        }
        ret (entry, true, ok)
    }
    ret (entry, false, ok)
}

// Everything a walk holds is in the caller's arena and every directory was read in one
// call, so there is no handle to give back. It exists because a host that streamed a
// directory would have one, and a caller that abandons a walk should not have to know
// which host it is on.
fn walk_close(it: *Walk) -> err {
    let state = mem.cast[*WalkState](it.state)
    state.depth = 0usize
    ret ok
}
