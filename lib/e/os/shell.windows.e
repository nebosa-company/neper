// `e.os.shell` on Windows (D885, widget plan `native-shell-api`): the host's shell
// services over shell32, user32 and gdi32 -- a tray item with a native popup menu,
// the shell's open verb, a reveal in the file manager and the recycle bin. Nothing
// here draws or emulates: a tray icon is the caller's pixels handed to the shell,
// a menu is the shell's own, and what the host has no service for is `Unsupported`
// on the variant that lacks it. `project.select_source` picks this file for a
// Windows target and `shell.linux.e` for a Linux one; the type block is a copy in
// each, as `e.os` does it.
//
// The tray callbacks need a window of this process to arrive at, so the first tray
// call creates a hidden top-level window of its own class; `tray_poll` pumps that
// window's messages, so a program without a `window_poll` loop still receives them.

use e.mem
use e.os

error Unsupported
error Invalid
error NotFound
error Failed

type Capabilities = struct { tray: bool, popup_menu: bool, open_uri: bool, reveal: bool, trash: bool }
// Rows top-down, a pixel `0xAARRGGBB`, as `os.window_present` takes them.
type Icon = struct { width: u32, height: u32, pixels: []const u32 }
type TrayEventKind = enum u8 { Select, Context, Open }
type TrayEvent = struct { kind: TrayEventKind, id: u32, x: i32, y: i32 }
type MenuItem = struct { id: u32, label: str, enabled: bool, checked: bool, separator: bool }

// NOTIFYICONDATAW, ICONINFO, POINT, SHFILEOPSTRUCTW, WNDCLASSEXW and MSG as the
// shell, user32 and gdi32 lay them out on x64.
type NotifyIconData = struct { size: u32, padding: u32, window: usize, id: u32, flags: u32, callback: u32, padding2: u32, icon: usize, tip: [128]u16, state: u32, state_mask: u32, info: [256]u16, version: u32, info_title: [64]u16, info_flags: u32, guid: [16]u8, balloon_icon: usize }
type IconInfo = struct { is_icon: i32, hotspot_x: u32, hotspot_y: u32, padding: u32, mask: usize, colour: usize }
type Point = struct { x: i32, y: i32 }
type FileOperation = struct { window: usize, func: u32, padding: u32, from: *const u16, to: usize, flags: u16, padding2: u16, aborted: i32, mappings: usize, title: usize }
type ShellClass = struct { size: u32, style: u32, procedure: fn(usize, u32, usize, isize) -> isize, class_extra: i32, window_extra: i32, instance: usize, icon: usize, cursor: usize, background: usize, menu_name: usize, class_name: *const u16, small_icon: usize }
type ShellMessage = struct { window: usize, message: u32, padding: u32, wparam: usize, lparam: isize, time: u32, x: i32, y: i32, padding2: u32 }

const CP_UTF8: u32 = 65001u32
const TRAY_MESSAGE: u32 = 32769u32
const WM_LBUTTONUP: u32 = 514u32
const WM_LBUTTONDBLCLK: u32 = 515u32
const WM_RBUTTONUP: u32 = 517u32
const PM_REMOVE: u32 = 1u32
const NIM_ADD: u32 = 0u32
const NIM_MODIFY: u32 = 1u32
const NIM_DELETE: u32 = 2u32
const NIF_MESSAGE_ICON_TIP: u32 = 7u32
const NOTIFY_ICON_DATA_SIZE: u32 = 976u32
const MF_GRAYED: u32 = 1u32
const MF_CHECKED: u32 = 8u32
const MF_SEPARATOR: u32 = 2048u32
const TPM_RETURN_COMMAND: u32 = 386u32
const SW_SHOWNORMAL: i32 = 1i32
const FO_DELETE: u32 = 3u32
const FOF_RECYCLE_QUIETLY: u16 = 1108u16
const COINIT_APARTMENT: u32 = 6u32
const MAX_ICON_SIDE: u32 = 256u32
const TRAY_TABLE: usize = 16usize
const TRAY_RING: usize = 64usize

var shell_window: usize = 0usize
var shell_class_name: [16]u16 = zero
var shell_open_verb: [8]u16 = zero
var tray_ids: [16]u32 = zero
var tray_icons: [16]usize = zero
var tray_used: [16]bool = zero
var tray_events: [64]TrayEvent = zero
var tray_event_head: usize = 0usize
var tray_event_count: usize = 0usize

@import("kernel32.dll", "MultiByteToWideChar")
extern fn raw_widen(code_page: u32, flags: u32, source: *const u8, source_len: i32, out: *u16, out_len: i32) -> i32

@import("kernel32.dll", "GetModuleHandleW")
extern fn raw_module_handle(name: usize) -> usize

@import("user32.dll", "RegisterClassExW")
extern fn raw_register_class(class: *const ShellClass) -> u16

@import("user32.dll", "CreateWindowExW")
extern fn raw_create_window(ex_style: u32, class_name: *const u16, title: *const u16, style: u32, x: i32, y: i32, width: i32, height: i32, parent: usize, menu: usize, instance: usize, parameter: usize) -> usize

@import("user32.dll", "DefWindowProcW")
extern fn raw_default_procedure(window: usize, message: u32, wparam: usize, lparam: isize) -> isize

@import("user32.dll", "PeekMessageW")
extern fn raw_peek_message(message: *ShellMessage, window: usize, first: u32, last: u32, remove: u32) -> i32

@import("user32.dll", "TranslateMessage")
extern fn raw_translate_message(message: *const ShellMessage) -> i32

@import("user32.dll", "DispatchMessageW")
extern fn raw_dispatch_message(message: *const ShellMessage) -> isize

@import("user32.dll", "GetCursorPos")
extern fn raw_cursor_position(point: *Point) -> i32

@import("user32.dll", "CreateIconIndirect")
extern fn raw_create_icon(info: *const IconInfo) -> usize

@import("user32.dll", "DestroyIcon")
extern fn raw_destroy_icon(icon: usize) -> i32

@import("user32.dll", "CreatePopupMenu")
extern fn raw_create_popup_menu() -> usize

@import("user32.dll", "AppendMenuW")
extern fn raw_append_menu(menu: usize, flags: u32, id: usize, label: *const u16) -> i32

@import("user32.dll", "TrackPopupMenuEx")
extern fn raw_track_popup_menu(menu: usize, flags: u32, x: i32, y: i32, window: usize, parameters: usize) -> i32

@import("user32.dll", "DestroyMenu")
extern fn raw_destroy_menu(menu: usize) -> i32

@import("user32.dll", "SetForegroundWindow")
extern fn raw_set_foreground_window(window: usize) -> i32

@import("user32.dll", "PostMessageW")
extern fn raw_post_message(window: usize, message: u32, wparam: usize, lparam: isize) -> i32

@import("gdi32.dll", "CreateBitmap")
extern fn raw_create_bitmap(width: i32, height: i32, planes: u32, bits_per_pixel: u32, bits: *const u8) -> usize

@import("gdi32.dll", "DeleteObject")
extern fn raw_delete_object(object: usize) -> i32

@import("shell32.dll", "Shell_NotifyIconW")
extern fn raw_notify_icon(message: u32, data: *const NotifyIconData) -> i32

@import("shell32.dll", "ShellExecuteW")
extern fn raw_shell_execute(window: usize, verb: *const u16, file: *const u16, parameters: usize, directory: usize, show: i32) -> usize

@import("shell32.dll", "ILCreateFromPathW")
extern fn raw_id_list_from_path(path: *const u16) -> usize

@import("shell32.dll", "ILFree")
extern fn raw_id_list_free(list: usize)

@import("shell32.dll", "SHOpenFolderAndSelectItems")
extern fn raw_open_folder_and_select(folder: usize, count: u32, items: usize, flags: u32) -> i32

@import("shell32.dll", "SHFileOperationW")
extern fn raw_file_operation(operation: *FileOperation) -> i32

@import("ole32.dll", "CoInitializeEx")
extern fn raw_co_initialize(reserved: usize, model: u32) -> i32

fn capabilities() -> Capabilities {
    ret Capabilities { tray: true, popup_menu: true, open_uri: true, reveal: true, trash: true }
}

// UTF-16 with a terminator, in the arena; the pages are touched first because the
// conversion is the kernel's write. A UTF-16 encoding never needs more units than
// the UTF-8 one needs bytes.
fn widen(a: *mem.Arena, text: str) -> ([]u16, err) {
    var nothing: []u16 = zero
    let (units, allocation_error) = mem.alloc[u16](a, text.len + 2usize)
    if allocation_error != ok { ret (nothing, allocation_error) }
    os.touch(mem.cast[*const u8](&units[0usize]), (text.len + 2usize) * 2usize)
    units[0usize] = 0u16
    units[1usize] = 0u16
    if text.len == 0usize { ret (units, ok) }
    let converted = raw_widen(CP_UTF8, 0u32, &text[0usize], i32(text.len), &units[0usize], i32(text.len))
    if converted <= 0i32 { ret (nothing, Invalid) }
    // Two terminators: `SHFileOperationW` wants a list ended by an empty name.
    units[usize(converted)] = 0u16
    units[usize(converted) + 1usize] = 0u16
    ret (units, ok)
}

fn ascii_units(out: []u16, text: str) {
    var at = 0usize
    while at < text.len {
        out[at] = u16(text[at])
        at += 1usize
    }
    out[text.len] = 0u16
}

// The window procedure of the hidden window: a tray callback becomes an event in
// the ring, at the cursor; everything else goes to the default.
@cc(c)
fn shell_procedure(handle: usize, message: u32, wparam: usize, lparam: isize) -> isize {
    if message != TRAY_MESSAGE { ret raw_default_procedure(handle, message, wparam, lparam) }
    let mouse = u32(lparam) & 65535u32
    var event: TrayEvent = zero
    if mouse == WM_LBUTTONUP {
        event.kind = .Select
    } else {
        if mouse == WM_RBUTTONUP {
            event.kind = .Context
        } else {
            if mouse == WM_LBUTTONDBLCLK {
                event.kind = .Open
            } else {
                ret 0isize
            }
        }
    }
    event.id = u32(wparam)
    var at: Point = zero
    let found = raw_cursor_position(&at)
    event.x = at.x
    event.y = at.y
    if tray_event_count == TRAY_RING { ret 0isize }
    tray_events[(tray_event_head + tray_event_count) % TRAY_RING] = event
    tray_event_count += 1usize
    ret 0isize
}

// The hidden window, once. COM is initialised on the thread with it, which the
// shell's open verb and the folder reveal ask for; a thread that already has
// another apartment is left as it is.
fn ensure_window() -> err {
    if shell_window != 0usize { ret ok }
    let initialised = raw_co_initialize(0usize, COINIT_APARTMENT)
    ascii_units(shell_class_name[..], "neper.shell")
    ascii_units(shell_open_verb[..], "open")
    var class: ShellClass = zero
    class.size = 80u32
    class.procedure = shell_procedure
    class.instance = raw_module_handle(0usize)
    class.class_name = &shell_class_name[0usize]
    let atom = raw_register_class(&class)
    if atom == 0u16 { ret Failed }
    let created = raw_create_window(0u32, &shell_class_name[0usize], &shell_class_name[0usize], 0u32, 0i32, 0i32, 0i32, 0i32, 0usize, 0usize, class.instance, 0usize)
    if created == 0usize { ret Failed }
    shell_window = created
    ret ok
}

// An HICON from the caller's pixels: a 32-bit colour bitmap of the rows as given
// and an all-zero mask, which is how an icon carries its alpha.
fn icon_handle(a: *mem.Arena, icon: Icon) -> (usize, err) {
    if icon.width == 0u32 || icon.height == 0u32 || icon.width > MAX_ICON_SIDE || icon.height > MAX_ICON_SIDE { ret (0usize, Invalid) }
    if icon.pixels.len < usize(icon.width) * usize(icon.height) { ret (0usize, Invalid) }
    let mask_bytes = ((usize(icon.width) + 15usize) / 16usize) * 2usize * usize(icon.height)
    let (mask_bits, allocation_error) = mem.alloc[u8](a, mask_bytes)
    if allocation_error != ok { ret (0usize, allocation_error) }
    var at = 0usize
    while at < mask_bytes {
        mask_bits[at] = 0u8
        at += 1usize
    }
    let colour = raw_create_bitmap(i32(icon.width), i32(icon.height), 1u32, 32u32, mem.cast[*const u8](&icon.pixels[0usize]))
    if colour == 0usize { ret (0usize, Failed) }
    let mask = raw_create_bitmap(i32(icon.width), i32(icon.height), 1u32, 1u32, &mask_bits[0usize])
    if mask == 0usize {
        let dropped = raw_delete_object(colour)
        ret (0usize, Failed)
    }
    var info: IconInfo = zero
    info.is_icon = 1i32
    info.mask = mask
    info.colour = colour
    let handle = raw_create_icon(&info)
    let dropped_colour = raw_delete_object(colour)
    let dropped_mask = raw_delete_object(mask)
    if handle == 0usize { ret (0usize, Failed) }
    ret (handle, ok)
}

fn tray_slot(id: u32) -> usize {
    var at = 0usize
    while at < TRAY_TABLE {
        if tray_used[at] && tray_ids[at] == id { ret at }
        at += 1usize
    }
    ret TRAY_TABLE
}

fn notify(a: *mem.Arena, message: u32, id: u32, icon: usize, tooltip: str) -> err {
    var data: NotifyIconData = zero
    data.size = NOTIFY_ICON_DATA_SIZE
    data.window = shell_window
    data.id = id
    data.flags = NIF_MESSAGE_ICON_TIP
    data.callback = TRAY_MESSAGE
    data.icon = icon
    // The tip is 127 units and a terminator; a longer one is cut, and a cut inside a
    // surrogate pair would leave half of it, so the cut backs off one unit there.
    let (units, widen_error) = widen(a, tooltip)
    if widen_error != ok { ret widen_error }
    var count = 0usize
    while count < 127usize && units[count] != 0u16 { count += 1usize }
    if count == 127usize && units[126usize] >= 55296u16 && units[126usize] < 56320u16 { count = 126usize }
    var at = 0usize
    while at < count {
        data.tip[at] = units[at]
        at += 1usize
    }
    data.tip[count] = 0u16
    if raw_notify_icon(message, &data) == 0i32 { ret Failed }
    ret ok
}

fn tray_add(a: *mem.Arena, id: u32, icon: Icon, tooltip: str) -> err {
    try ensure_window()
    if tray_slot(id) != TRAY_TABLE { ret Invalid }
    var slot = 0usize
    while slot < TRAY_TABLE && tray_used[slot] { slot += 1usize }
    if slot == TRAY_TABLE { ret Failed }
    let (handle, icon_error) = icon_handle(a, icon)
    if icon_error != ok { ret icon_error }
    let added = notify(a, NIM_ADD, id, handle, tooltip)
    if added != ok {
        let dropped = raw_destroy_icon(handle)
        ret added
    }
    tray_used[slot] = true
    tray_ids[slot] = id
    tray_icons[slot] = handle
    ret ok
}

fn tray_update(a: *mem.Arena, id: u32, icon: Icon, tooltip: str) -> err {
    let slot = tray_slot(id)
    if slot == TRAY_TABLE { ret NotFound }
    let (handle, icon_error) = icon_handle(a, icon)
    if icon_error != ok { ret icon_error }
    let modified = notify(a, NIM_MODIFY, id, handle, tooltip)
    if modified != ok {
        let dropped = raw_destroy_icon(handle)
        ret modified
    }
    let dropped_old = raw_destroy_icon(tray_icons[slot])
    tray_icons[slot] = handle
    ret ok
}

fn tray_remove(a: *mem.Arena, id: u32) -> err {
    let slot = tray_slot(id)
    if slot == TRAY_TABLE { ret NotFound }
    let removed = notify(a, NIM_DELETE, id, 0usize, "")
    let dropped = raw_destroy_icon(tray_icons[slot])
    tray_used[slot] = false
    tray_icons[slot] = 0usize
    ret removed
}

// Pumps the hidden window's messages, then answers the oldest tray event.
fn tray_poll() -> (TrayEvent, bool) {
    var none: TrayEvent = zero
    if shell_window == 0usize { ret (none, false) }
    var message: ShellMessage = zero
    while raw_peek_message(&message, shell_window, 0u32, 0u32, PM_REMOVE) != 0i32 {
        let translated = raw_translate_message(&message)
        let dispatched = raw_dispatch_message(&message)
    }
    if tray_event_count == 0usize { ret (none, false) }
    let event = tray_events[tray_event_head]
    tray_event_head = (tray_event_head + 1usize) % TRAY_RING
    tray_event_count -= 1usize
    ret (event, true)
}

// The shell's own popup menu at a screen point, blocking until a choice or a
// dismissal: the chosen item's id and whether one was chosen. An item's id is
// its identity, so a zero id on anything but a separator is refused.
fn popup_menu(a: *mem.Arena, items: []const MenuItem, x: i32, y: i32) -> (u32, bool, err) {
    let window_error = ensure_window()
    if window_error != ok { ret (0u32, false, window_error) }
    var at = 0usize
    while at < items.len {
        if !items[at].separator && items[at].id == 0u32 { ret (0u32, false, Invalid) }
        at += 1usize
    }
    let menu = raw_create_popup_menu()
    if menu == 0usize { ret (0u32, false, Failed) }
    at = 0usize
    while at < items.len {
        var flags = 0u32
        var label: *const u16 = &shell_open_verb[0usize]
        if items[at].separator {
            flags = MF_SEPARATOR
        } else {
            if !items[at].enabled { flags = flags | MF_GRAYED }
            if items[at].checked { flags = flags | MF_CHECKED }
            let (wide, widen_error) = widen(a, items[at].label)
            if widen_error != ok {
                let dropped = raw_destroy_menu(menu)
                ret (0u32, false, widen_error)
            }
            label = &wide[0usize]
        }
        if raw_append_menu(menu, flags, usize(items[at].id), label) == 0i32 {
            let dropped = raw_destroy_menu(menu)
            ret (0u32, false, Failed)
        }
        at += 1usize
    }
    // The foreground dance the shell documents: the menu closes when the pointer
    // leaves it only for a foreground window, and the null message afterwards
    // lets the next one open at once.
    let fronted = raw_set_foreground_window(shell_window)
    let chosen = raw_track_popup_menu(menu, TPM_RETURN_COMMAND, x, y, shell_window, 0usize)
    let posted = raw_post_message(shell_window, 0u32, 0usize, 0isize)
    let dropped = raw_destroy_menu(menu)
    if chosen == 0i32 { ret (0u32, false, ok) }
    ret (u32(chosen), true, ok)
}

// The shell's open verb: a URI to its handler, a file to its association.
fn open_uri(a: *mem.Arena, uri: str) -> err {
    if uri.len == 0usize { ret Invalid }
    try ensure_window()
    let (wide, widen_error) = widen(a, uri)
    if widen_error != ok { ret widen_error }
    let result = raw_shell_execute(0usize, &shell_open_verb[0usize], &wide[0usize], 0usize, 0usize, SW_SHOWNORMAL)
    if result == 2usize || result == 3usize || result == 31usize { ret NotFound }
    if result <= 32usize { ret Failed }
    ret ok
}

// The file manager at the item, selected.
fn reveal(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    try ensure_window()
    let (wide, widen_error) = widen(a, path)
    if widen_error != ok { ret widen_error }
    let list = raw_id_list_from_path(&wide[0usize])
    if list == 0usize { ret NotFound }
    let result = raw_open_folder_and_select(list, 0u32, 0usize, 0u32)
    raw_id_list_free(list)
    if result < 0i32 { ret Failed }
    ret ok
}

// To the recycle bin, quietly: no confirmation and no progress, but with undo.
fn trash(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    // The operation's own codes for a missing item are the shell's old table, so the
    // item is looked for first.
    let (info, stat_error) = os.stat(a, path)
    if stat_error == os.NotFound { ret NotFound }
    if stat_error != ok { ret Failed }
    let (wide, widen_error) = widen(a, path)
    if widen_error != ok { ret widen_error }
    var operation: FileOperation = zero
    operation.func = FO_DELETE
    operation.from = &wide[0usize]
    operation.flags = FOF_RECYCLE_QUIETLY
    let result = raw_file_operation(&operation)
    if result != 0i32 || operation.aborted != 0i32 { ret Failed }
    ret ok
}
