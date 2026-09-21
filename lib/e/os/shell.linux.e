// `e.os.shell` on Linux (D885, widget plan `native-shell-api`): the host's shell
// services where the desktop has a standard for them, and an explicit `Unsupported`
// where it has none. The open verb is `xdg-open`, found on the PATH, whose exit code
// is the answer; a reveal opens the item's directory the same way, since selecting
// the item needs a D-Bus client the library does not have; the trash is the
// freedesktop trash specification written by hand -- the file moved under the home
// trash with its `.trashinfo` beside it. A tray or a popup menu is a StatusNotifier
// over D-Bus on every current desktop, so both answer `Unsupported` rather than
// emulate one in a window. The type block is a copy of `shell.windows.e`'s.

use e.fs
use e.mem
use e.os
use e.str
use e.time

error Unsupported
error Invalid
error NotFound
error Failed

type Capabilities = struct { tray: bool, popup_menu: bool, open_uri: bool, reveal: bool, trash: bool, taskbar: bool, jump_list: bool, notices: bool, notice_actions: bool, notice_remove: bool }
// Rows top-down, a pixel `0xAARRGGBB`, as `os.window_present` takes them.
type Icon = struct { width: u32, height: u32, pixels: []const u32 }
type TrayEventKind = enum u8 { Select, Context, Open, NoticeSelect, NoticeDismiss }
type NoticePermission = enum u8 { Granted, Denied, Unavailable }
type TrayEvent = struct { kind: TrayEventKind, id: u32, x: i32, y: i32 }
type MenuItem = struct { id: u32, label: str, enabled: bool, checked: bool, separator: bool }
type ProgressState = enum u8 { None, Indeterminate, Normal, Paused, Error }
type JumpTask = struct { title: str, program: str, arguments: str, description: str }

fn capabilities() -> Capabilities {
    ret Capabilities { tray: false, popup_menu: false, open_uri: true, reveal: true, trash: true, taskbar: false, jump_list: false, notices: true, notice_actions: false, notice_remove: false }
}

fn tray_add(a: *mem.Arena, id: u32, icon: Icon, tooltip: str) -> err {
    ret Unsupported
}

fn tray_update(a: *mem.Arena, id: u32, icon: Icon, tooltip: str) -> err {
    ret Unsupported
}

fn tray_remove(a: *mem.Arena, id: u32) -> err {
    ret Unsupported
}

fn tray_poll() -> (TrayEvent, bool) {
    var none: TrayEvent = zero
    ret (none, false)
}

fn popup_menu(a: *mem.Arena, items: []const MenuItem, x: i32, y: i32) -> (u32, bool, err) {
    ret (0u32, false, Unsupported)
}

// A taskbar button's progress, overlay and jump list have no desktop standard;
// the launcher APIs that had them are gone.
fn taskbar_progress(a: *mem.Arena, w: os.Window, state: ProgressState, completed: u64, total: u64) -> err {
    ret Unsupported
}

fn taskbar_overlay(a: *mem.Arena, w: os.Window, icon: Icon, description: str) -> err {
    ret Unsupported
}

fn jump_list(a: *mem.Arena, tasks: []const JumpTask) -> err {
    ret Unsupported
}

fn jump_list_clear(a: *mem.Arena) -> err {
    ret Unsupported
}

// A program by the PATH's first directory that holds it; `execve` searches nothing.
fn find_program(a: *mem.Arena, name: str) -> (str, err) {
    let (path, path_error) = os.env(a, "PATH")
    if path_error != ok { ret ("", NotFound) }
    let (suffix, suffix_error) = str.concat(a, "/", name)
    if suffix_error != ok { ret ("", suffix_error) }
    var start = 0usize
    var at = 0usize
    while at <= path.len {
        if at == path.len || path[at] == 58u8 {
            if at > start {
                let (candidate, join_error) = str.concat(a, path[start..at], suffix)
                if join_error != ok { ret ("", join_error) }
                let (present, exists_error) = fs.exists(a, candidate)
                if exists_error == ok && present { ret (candidate, ok) }
            }
            start = at + 1usize
        }
        at += 1usize
    }
    ret ("", NotFound)
}

// The child's three streams are the parent's own; its exit code is the answer,
// which is what `xdg-open` documents: 0 handed off, anything else did not.
fn open_uri(a: *mem.Arena, uri: str) -> err {
    if uri.len == 0usize { ret Invalid }
    let (opener, opener_error) = find_program(a, "xdg-open")
    if opener_error != ok { ret opener_error }
    var argv: [2]str = zero
    argv[0usize] = opener
    argv[1usize] = uri
    var options: os.SpawnOptions = zero
    options.argv = argv[..]
    options.inherit_env = true
    options.stdio.stdout = os.File { raw: 1usize }
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(a, options)
    if spawn_error != ok { ret Failed }
    let (usage, wait_error) = os.wait_usage(child)
    if wait_error != ok || usage.exit_code != 0i32 { ret Failed }
    ret ok
}

fn parent_of(path: str) -> str {
    var at = path.len
    while at > 1usize {
        if path[at - 1usize] == 47u8 { ret path[0usize..at - 1usize] }
        at -= 1usize
    }
    if path.len != 0usize && path[0usize] == 47u8 { ret path[0usize..1usize] }
    ret "."
}

// The item's directory in the file manager -- the item itself is not selected,
// which is the honest half of a reveal: selecting it is `org.freedesktop.FileManager1`
// over D-Bus. ponytail: opens the directory; a D-Bus ShowItems call when e.dbus exists.
fn reveal(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    let (present, exists_error) = fs.exists(a, path)
    if exists_error != ok { ret exists_error }
    if !present { ret NotFound }
    ret open_uri(a, parent_of(path))
}

fn base_name(path: str) -> str {
    var at = path.len
    while at > 0usize && path[at - 1usize] == 47u8 { at -= 1usize }
    let end = at
    while at > 0usize && path[at - 1usize] != 47u8 { at -= 1usize }
    ret path[at..end]
}

// The `Path=` of a `.trashinfo` is the absolute path with every byte outside the
// unreserved set and `/` percent-encoded, as the specification says.
fn encoded_path(a: *mem.Arena, path: str) -> (str, err) {
    let (out, allocation_error) = mem.alloc[u8](a, path.len * 3usize)
    if allocation_error != ok { ret ("", allocation_error) }
    let digits = "0123456789ABCDEF"
    var at = 0usize
    var written = 0usize
    while at < path.len {
        let c = path[at]
        let plain = (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 45u8 || c == 46u8 || c == 95u8 || c == 126u8 || c == 47u8
        if plain {
            out[written] = c
            written += 1usize
        } else {
            out[written] = 37u8
            out[written + 1usize] = digits[usize(c >> 4u8)]
            out[written + 2usize] = digits[usize(c & 15u8)]
            written += 3usize
        }
        at += 1usize
    }
    ret (out[0usize..written], ok)
}

fn write_two(out: []u8, at: usize, value: i64) -> usize {
    out[at] = u8(48i64 + value / 10i64)
    out[at + 1usize] = u8(48i64 + value % 10i64)
    ret at + 2usize
}

// `YYYY-MM-DDThh:mm:ss` of the clock now. ponytail: UTC, where the specification
// says local time; the zone is `e.time.tz`'s to supply once a caller minds.
fn deletion_date(a: *mem.Arena) -> (str, err) {
    let (stamp, clock_error) = time.now()
    if clock_error != ok { ret ("", clock_error) }
    var seconds = stamp.nanos / 1000000000i64
    if stamp.nanos < 0i64 && stamp.nanos % 1000000000i64 != 0i64 { seconds -= 1i64 }
    var days = seconds / 86400i64
    var of_day = seconds - days * 86400i64
    if of_day < 0i64 {
        of_day += 86400i64
        days -= 1i64
    }
    let (year, month, day) = time.civil_from_days(days)
    if year < 0i64 || year > 9999i64 { ret ("", Invalid) }
    let (out, allocation_error) = mem.alloc[u8](a, 19usize)
    if allocation_error != ok { ret ("", allocation_error) }
    var at = write_two(out, 0usize, year / 100i64)
    at = write_two(out, at, year % 100i64)
    out[at] = 45u8
    at = write_two(out, at + 1usize, month)
    out[at] = 45u8
    at = write_two(out, at + 1usize, day)
    out[at] = 84u8
    at = write_two(out, at + 1usize, of_day / 3600i64)
    out[at] = 58u8
    at = write_two(out, at + 1usize, (of_day / 60i64) % 60i64)
    out[at] = 58u8
    at = write_two(out, at + 1usize, of_day % 60i64)
    ret (out[0usize..at], ok)
}

fn join3(a: *mem.Arena, x: str, y: str, z: str) -> (str, err) {
    let (xy, first_error) = str.concat(a, x, y)
    if first_error != ok { ret ("", first_error) }
    let (xyz, second_error) = str.concat(a, xy, z)
    ret (xyz, second_error)
}

// The home trash: `$XDG_DATA_HOME/Trash`, or `~/.local/share/Trash`. The item's
// name is kept unless the trash already holds one, then a counter is appended;
// the info file is written first so an interrupted move leaves nothing orphaned
// in `files/`, and removed again if the move fails. ponytail: the home trash only;
// a move across devices fails, where the specification wants `$topdir/.Trash-$uid`.
fn trash(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    let (present, exists_error) = fs.exists(a, path)
    if exists_error != ok { ret exists_error }
    if !present { ret NotFound }
    var absolute = path
    if path[0usize] != 47u8 {
        let (cwd, cwd_error) = fs.current_dir(a)
        if cwd_error != ok { ret cwd_error }
        let (joined, join_error) = join3(a, cwd, "/", path)
        if join_error != ok { ret join_error }
        absolute = joined
    }
    let (data_home, has_data_home) = fs.env_directory(a, "XDG_DATA_HOME")
    var base = data_home
    if !has_data_home {
        let (home, home_error) = fs.home_dir(a)
        if home_error != ok { ret home_error }
        let (local_share, local_error) = str.concat(a, home, "/.local/share")
        if local_error != ok { ret local_error }
        base = local_share
    }
    let (files_dir, files_error) = str.concat(a, base, "/Trash/files")
    if files_error != ok { ret files_error }
    let (info_dir, info_error) = str.concat(a, base, "/Trash/info")
    if info_error != ok { ret info_error }
    try fs.make_dirs(a, files_dir)
    try fs.make_dirs(a, info_dir)
    let name = base_name(absolute)
    if name.len == 0usize { ret Invalid }
    var chosen = name
    var counter = 1u64
    while true {
        let (target_path, target_error) = join3(a, files_dir, "/", chosen)
        if target_error != ok { ret target_error }
        let (info_path, info_path_error) = join3(a, info_dir, "/", chosen)
        if info_path_error != ok { ret info_path_error }
        let (info_file, info_file_error) = str.concat(a, info_path, ".trashinfo")
        if info_file_error != ok { ret info_file_error }
        let (target_taken, target_exists_error) = fs.exists(a, target_path)
        if target_exists_error != ok { ret target_exists_error }
        let (info_taken, info_exists_error) = fs.exists(a, info_file)
        if info_exists_error != ok { ret info_exists_error }
        if !target_taken && !info_taken {
            let (encoded, encode_error) = encoded_path(a, absolute)
            if encode_error != ok { ret encode_error }
            let (stamp, stamp_error) = deletion_date(a)
            if stamp_error != ok { ret stamp_error }
            let (head, head_error) = join3(a, "[Trash Info]\nPath=", encoded, "\nDeletionDate=")
            if head_error != ok { ret head_error }
            let (content, content_error) = join3(a, head, stamp, "\n")
            if content_error != ok { ret content_error }
            try fs.write_file(a, info_file, content)
            let moved = fs.move(a, absolute, target_path)
            if moved != ok {
                let dropped = fs.remove_file(a, info_file)
                ret Failed
            }
            ret ok
        }
        var digits: [20]u8 = zero
        var count = 0usize
        var value = counter
        while value > 0u64 {
            digits[19usize - count] = u8(48u64 + value % 10u64)
            value /= 10u64
            count += 1usize
        }
        let (renamed, rename_error) = join3(a, name, ".", digits[20usize - count..20usize])
        if rename_error != ok { ret rename_error }
        chosen = renamed
        counter += 1u64
    }
    ret Failed
}

// ------------------------------------------------------------------ notices
//
// A notification (D889) is `org.freedesktop.Notifications` over the session bus,
// which the library does not speak; `notify-send` does, and is on every desktop
// that has a daemon. Its `--print-id` is the daemon's id, which `--replace-id`
// updates; a daemon has no permission model, so the permission is `Granted` when
// the tool and a session bus are there and `Unavailable` otherwise. Closing a
// notice and its buttons are the daemon's calls the tool does not expose without
// blocking, so `notice_remove` is `Unsupported` and `notice_actions` false. The
// tray id is a Windows notion and is ignored here. ponytail: notify-send; a D-Bus
// client would give actions, closing and the activation events.

fn notice_permission(a: *mem.Arena) -> NoticePermission {
    let (tool, tool_error) = find_program(a, "notify-send")
    if tool_error != ok { ret .Unavailable }
    let (bus, bus_error) = os.env(a, "DBUS_SESSION_BUS_ADDRESS")
    if bus_error != ok || bus.len == 0usize { ret .Unavailable }
    ret .Granted
}

fn parse_id(text: []const u8) -> (u32, bool) {
    var value = 0u32
    var digits = 0usize
    var at = 0usize
    while at < text.len && text[at] >= 48u8 && text[at] <= 57u8 {
        value = value * 10u32 + u32(text[at] - 48u8)
        digits += 1usize
        at += 1usize
    }
    ret (value, digits != 0usize)
}

// `notify-send` with its output on a pipe, read to the end for the id it prints.
fn send_notice(a: *mem.Arena, replace: u32, title: str, body: str, silent: bool) -> (u32, err) {
    let (tool, tool_error) = find_program(a, "notify-send")
    if tool_error != ok { ret (0u32, Unsupported) }
    var replacing: [24]u8 = zero
    var argv: [7]str = zero
    var count = 0usize
    argv[count] = tool
    count += 1usize
    argv[count] = "--print-id"
    count += 1usize
    if silent {
        argv[count] = "--hint=int:suppress-sound:1"
        count += 1usize
    }
    if replace != 0u32 {
        let prefix = "--replace-id="
        var at = 0usize
        while at < prefix.len {
            replacing[at] = prefix[at]
            at += 1usize
        }
        var digits: [10]u8 = zero
        var digit_count = 0usize
        var value = replace
        while value > 0u32 {
            digits[9usize - digit_count] = u8(48u32 + value % 10u32)
            value /= 10u32
            digit_count += 1usize
        }
        var copied = 0usize
        while copied < digit_count {
            replacing[at + copied] = digits[10usize - digit_count + copied]
            copied += 1usize
        }
        argv[count] = replacing[0usize..at + digit_count]
        count += 1usize
    }
    argv[count] = title
    count += 1usize
    argv[count] = body
    count += 1usize
    let (reading, writing, pipe_error) = os.pipe()
    if pipe_error != ok { ret (0u32, Failed) }
    var options: os.SpawnOptions = zero
    options.argv = argv[0usize..count]
    options.inherit_env = true
    options.stdio.stdout = writing
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(a, options)
    // The write end went into the options, and is closed from there.
    let closed_writing = os.close(options.stdio.stdout)
    if spawn_error != ok {
        let closed_reading = os.close(reading)
        ret (0u32, Failed)
    }
    var output: [64]u8 = zero
    var filled = 0usize
    while filled < 64usize {
        let (got, read_error) = os.read(reading, output[filled..64usize])
        if read_error != ok || got == 0usize { break }
        filled += got
    }
    let closed_reading = os.close(reading)
    let (usage, wait_error) = os.wait_usage(child)
    if wait_error != ok || usage.exit_code != 0i32 { ret (0u32, Failed) }
    let (id, has_id) = parse_id(output[0usize..filled])
    if !has_id { ret (0u32, Failed) }
    ret (id, ok)
}

fn notice_publish(a: *mem.Arena, tray_id: u32, title: str, body: str, silent: bool) -> (u32, err) {
    if body.len == 0usize { ret (0u32, Invalid) }
    let (id, send_error) = send_notice(a, 0u32, title, body, silent)
    ret (id, send_error)
}

fn notice_update(a: *mem.Arena, tray_id: u32, notice_id: u32, title: str, body: str, silent: bool) -> err {
    if body.len == 0usize || notice_id == 0u32 { ret Invalid }
    let (id, send_error) = send_notice(a, notice_id, title, body, silent)
    ret send_error
}

fn notice_remove(a: *mem.Arena, tray_id: u32, notice_id: u32) -> err {
    ret Unsupported
}
