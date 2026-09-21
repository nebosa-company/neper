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

type Capabilities = struct { tray: bool, popup_menu: bool, open_uri: bool, reveal: bool, trash: bool, taskbar: bool, jump_list: bool }
// Rows top-down, a pixel `0xAARRGGBB`, as `os.window_present` takes them.
type Icon = struct { width: u32, height: u32, pixels: []const u32 }
type TrayEventKind = enum u8 { Select, Context, Open }
type TrayEvent = struct { kind: TrayEventKind, id: u32, x: i32, y: i32 }
type MenuItem = struct { id: u32, label: str, enabled: bool, checked: bool, separator: bool }
type ProgressState = enum u8 { None, Indeterminate, Normal, Paused, Error }
type JumpTask = struct { title: str, program: str, arguments: str, description: str }

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
    ret Capabilities { tray: true, popup_menu: true, open_uri: true, reveal: true, trash: true, taskbar: true, jump_list: true }
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

// ------------------------------------------------------------ taskbar and jump list
//
// Both are COM: an object is a pointer to its vtable, a method is a slot in it
// called with the object first, and D32's `extern fn` pointer type is what names
// the slot's convention. Every interface used here is reached by its slot number
// under the layout the SDK's IDL fixes, and nothing of COM is declared beyond that.

type ComVtable = struct { slots: [32]usize }
type ComObject = struct { vtable: *ComVtable }
type PropertyKey = struct { format: [16]u8, id: u32 }
type PropVariant = struct { kind: u16, reserved1: u16, reserved2: u16, reserved3: u16, value: usize, padding: usize }

@cc(c)
type ComThis = extern fn(usize) -> i32
@cc(c)
type ComQuery = extern fn(usize, *const u8, **ComObject) -> i32
@cc(c)
type ComProgressValue = extern fn(usize, usize, u64, u64) -> i32
@cc(c)
type ComProgressState = extern fn(usize, usize, u32) -> i32
@cc(c)
type ComOverlay = extern fn(usize, usize, usize, *const u16) -> i32
@cc(c)
type ComWide = extern fn(usize, *const u16) -> i32
@cc(c)
type ComObjectArg = extern fn(usize, usize) -> i32
@cc(c)
type ComBegin = extern fn(usize, *u32, *const u8, **ComObject) -> i32
@cc(c)
type ComSetValue = extern fn(usize, *const PropertyKey, *const PropVariant) -> i32

type ThisPun = union { function: ComThis, bits: usize }
type QueryPun = union { function: ComQuery, bits: usize }
type ProgressValuePun = union { function: ComProgressValue, bits: usize }
type ProgressStatePun = union { function: ComProgressState, bits: usize }
type OverlayPun = union { function: ComOverlay, bits: usize }
type WidePun = union { function: ComWide, bits: usize }
type ObjectArgPun = union { function: ComObjectArg, bits: usize }
type BeginPun = union { function: ComBegin, bits: usize }
type SetValuePun = union { function: ComSetValue, bits: usize }

const CLSCTX_INPROC_SERVER: u32 = 1u32
const VT_LPWSTR: u16 = 31u16
const SLOT_QUERY: usize = 0usize
const SLOT_RELEASE: usize = 2usize
const TASKBAR_INIT: usize = 3usize
const TASKBAR_PROGRESS_VALUE: usize = 9usize
const TASKBAR_PROGRESS_STATE: usize = 10usize
const TASKBAR_OVERLAY: usize = 18usize
const LIST_BEGIN: usize = 4usize
const LIST_ADD_TASKS: usize = 7usize
const LIST_COMMIT: usize = 8usize
const LIST_DELETE: usize = 10usize
const LIST_ABORT: usize = 11usize
const COLLECTION_ADD: usize = 5usize
const LINK_SET_DESCRIPTION: usize = 7usize
const LINK_SET_ARGUMENTS: usize = 11usize
const LINK_SET_PATH: usize = 20usize
const STORE_SET_VALUE: usize = 6usize
const STORE_COMMIT: usize = 7usize

var taskbar: *ComObject = zero
var empty_wide: [1]u16 = zero

@import("ole32.dll", "CoCreateInstance")
extern fn raw_co_create(clsid: *const u8, outer: usize, context: u32, iid: *const u8, out: **ComObject) -> i32

// A GUID's bytes: the first three parts little-endian, the last eight as written.
fn guid(out: []u8, d1: u32, d2: u16, d3: u16, d4_high: u32, d4_low: u32) {
    out[0usize] = u8(d1 & 255u32)
    out[1usize] = u8((d1 >> 8u32) & 255u32)
    out[2usize] = u8((d1 >> 16u32) & 255u32)
    out[3usize] = u8(d1 >> 24u32)
    out[4usize] = u8(d2 & 255u16)
    out[5usize] = u8(d2 >> 8u16)
    out[6usize] = u8(d3 & 255u16)
    out[7usize] = u8(d3 >> 8u16)
    out[8usize] = u8(d4_high >> 24u32)
    out[9usize] = u8((d4_high >> 16u32) & 255u32)
    out[10usize] = u8((d4_high >> 8u32) & 255u32)
    out[11usize] = u8(d4_high & 255u32)
    out[12usize] = u8(d4_low >> 24u32)
    out[13usize] = u8((d4_low >> 16u32) & 255u32)
    out[14usize] = u8((d4_low >> 8u32) & 255u32)
    out[15usize] = u8(d4_low & 255u32)
}

fn com_create(clsid: []const u8, iid: []const u8) -> (*ComObject, err) {
    var object: *ComObject = zero
    let created = raw_co_create(&clsid[0usize], 0usize, CLSCTX_INPROC_SERVER, &iid[0usize], &object)
    if created < 0i32 || mem.address_of(object) == 0usize { ret (object, Failed) }
    ret (object, ok)
}

fn call_this(object: *ComObject, slot: usize) -> i32 {
    var pun: ThisPun = zero
    pun.bits = object.vtable.slots[slot]
    ret pun.function(mem.address_of(object))
}

fn com_release(object: *ComObject) {
    if mem.address_of(object) == 0usize { ret }
    let count = call_this(object, SLOT_RELEASE)
}

fn com_query(object: *ComObject, iid: []const u8) -> (*ComObject, err) {
    var found: *ComObject = zero
    var pun: QueryPun = zero
    pun.bits = object.vtable.slots[SLOT_QUERY]
    let result = pun.function(mem.address_of(object), &iid[0usize], &found)
    if result < 0i32 || mem.address_of(found) == 0usize { ret (found, Failed) }
    ret (found, ok)
}

fn call_wide(object: *ComObject, slot: usize, text: *const u16) -> i32 {
    var pun: WidePun = zero
    pun.bits = object.vtable.slots[slot]
    ret pun.function(mem.address_of(object), text)
}

fn call_object(object: *ComObject, slot: usize, argument: usize) -> i32 {
    var pun: ObjectArgPun = zero
    pun.bits = object.vtable.slots[slot]
    ret pun.function(mem.address_of(object), argument)
}

// The taskbar list, once, initialised; COM is initialised with the hidden window.
fn ensure_taskbar() -> err {
    if mem.address_of(taskbar) != 0usize { ret ok }
    try ensure_window()
    var clsid: [16]u8 = zero
    var iid: [16]u8 = zero
    guid(clsid[..], 1459483460u32, 64877u16, 4560u16, 2508849248u32, 2546573456u32)
    guid(iid[..], 3927636881u32, 40488u16, 19334u16, 2431229599u32, 2321477551u32)
    let (object, create_error) = com_create(clsid[..], iid[..])
    if create_error != ok { ret create_error }
    if call_this(object, TASKBAR_INIT) < 0i32 {
        com_release(object)
        ret Failed
    }
    taskbar = object
    ret ok
}

fn window_handle(w: os.Window) -> (usize, err) {
    let (handle, instance, native_error) = os.window_native(w)
    if native_error != ok { ret (0usize, Invalid) }
    ret (handle, ok)
}

// The window's taskbar button shows the state, and for a determinate one the
// fraction `completed` of `total`.
fn taskbar_progress(a: *mem.Arena, w: os.Window, state: ProgressState, completed: u64, total: u64) -> err {
    let (handle, handle_error) = window_handle(w)
    if handle_error != ok { ret handle_error }
    let determinate = state == .Normal || state == .Paused || state == .Error
    if determinate && (total == 0u64 || completed > total) { ret Invalid }
    try ensure_taskbar()
    var flag = 0u32
    if state == .Indeterminate { flag = 1u32 }
    if state == .Normal { flag = 2u32 }
    if state == .Error { flag = 4u32 }
    if state == .Paused { flag = 8u32 }
    var state_pun: ProgressStatePun = zero
    state_pun.bits = taskbar.vtable.slots[TASKBAR_PROGRESS_STATE]
    if state_pun.function(mem.address_of(taskbar), handle, flag) < 0i32 { ret Failed }
    if !determinate { ret ok }
    var value_pun: ProgressValuePun = zero
    value_pun.bits = taskbar.vtable.slots[TASKBAR_PROGRESS_VALUE]
    if value_pun.function(mem.address_of(taskbar), handle, completed, total) < 0i32 { ret Failed }
    ret ok
}

// An overlay on the window's taskbar button from the caller's pixels, with the
// description a screen reader speaks; an icon of no width clears it. The taskbar
// copies the icon, so the handle is destroyed after the call.
fn taskbar_overlay(a: *mem.Arena, w: os.Window, icon: Icon, description: str) -> err {
    let (handle, handle_error) = window_handle(w)
    if handle_error != ok { ret handle_error }
    try ensure_taskbar()
    var pun: OverlayPun = zero
    pun.bits = taskbar.vtable.slots[TASKBAR_OVERLAY]
    if icon.width == 0u32 {
        if pun.function(mem.address_of(taskbar), handle, 0usize, &empty_wide[0usize]) < 0i32 { ret Failed }
        ret ok
    }
    let (icon_object, icon_error) = icon_handle(a, icon)
    if icon_error != ok { ret icon_error }
    let (wide, widen_error) = widen(a, description)
    if widen_error != ok {
        let dropped = raw_destroy_icon(icon_object)
        ret widen_error
    }
    let result = pun.function(mem.address_of(taskbar), handle, icon_object, &wide[0usize])
    let dropped = raw_destroy_icon(icon_object)
    if result < 0i32 { ret Failed }
    ret ok
}

fn destination_list() -> (*ComObject, err) {
    var clsid: [16]u8 = zero
    var iid: [16]u8 = zero
    guid(clsid[..], 2012286192u32, 15797u16, 18790u16, 3038820293u32, 1339252438u32)
    guid(iid[..], 1664278207u32, 34741u16, 18032u16, 2428526167u32, 3020465310u32)
    let (object, create_error) = com_create(clsid[..], iid[..])
    ret (object, create_error)
}

// One shell link for a task: its program, arguments and description on the link,
// its title in the property store the link also is.
fn task_link(a: *mem.Arena, task: JumpTask) -> (*ComObject, err) {
    var nothing: *ComObject = zero
    var clsid: [16]u8 = zero
    var iid: [16]u8 = zero
    guid(clsid[..], 136193u32, 0u16, 0u16, 3221225472u32, 70u32)
    guid(iid[..], 136441u32, 0u16, 0u16, 3221225472u32, 70u32)
    let (link, create_error) = com_create(clsid[..], iid[..])
    if create_error != ok { ret (nothing, create_error) }
    let (program, program_error) = widen(a, task.program)
    let (arguments, arguments_error) = widen(a, task.arguments)
    let (description, description_error) = widen(a, task.description)
    let (title, title_error) = widen(a, task.title)
    if program_error != ok || arguments_error != ok || description_error != ok || title_error != ok {
        com_release(link)
        ret (nothing, Invalid)
    }
    if call_wide(link, LINK_SET_PATH, &program[0usize]) < 0i32 || call_wide(link, LINK_SET_ARGUMENTS, &arguments[0usize]) < 0i32 || call_wide(link, LINK_SET_DESCRIPTION, &description[0usize]) < 0i32 {
        com_release(link)
        ret (nothing, Failed)
    }
    var store_iid: [16]u8 = zero
    guid(store_iid[..], 2288881387u32, 36082u16, 17478u16, 2365771194u32, 498978713u32)
    let (store, store_error) = com_query(link, store_iid[..])
    if store_error != ok {
        com_release(link)
        ret (nothing, Failed)
    }
    var key: PropertyKey = zero
    guid(key.format[..], 4070540768u32, 20473u16, 4200u16, 2878408704u32, 724022233u32)
    key.id = 2u32
    var value: PropVariant = zero
    value.kind = VT_LPWSTR
    value.value = mem.address_of(&title[0usize])
    var set_pun: SetValuePun = zero
    set_pun.bits = store.vtable.slots[STORE_SET_VALUE]
    let set = set_pun.function(mem.address_of(store), &key, &value)
    let committed = call_this(store, STORE_COMMIT)
    com_release(store)
    if set < 0i32 || committed < 0i32 {
        com_release(link)
        ret (nothing, Failed)
    }
    ret (link, ok)
}

// The application's jump list tasks, replaced whole: a list begun, a collection
// of links added as the user tasks, the list committed. A task needs a title and
// a program; an empty slice is a commit of no tasks.
fn jump_list(a: *mem.Arena, tasks: []const JumpTask) -> err {
    var at = 0usize
    while at < tasks.len {
        if tasks[at].title.len == 0usize || tasks[at].program.len == 0usize { ret Invalid }
        at += 1usize
    }
    try ensure_window()
    let (list, list_error) = destination_list()
    if list_error != ok { ret list_error }
    var slots = 0u32
    var removed: *ComObject = zero
    var array_iid: [16]u8 = zero
    guid(array_iid[..], 2462752205u32, 22050u16, 19386u16, 2818924191u32, 1411111113u32)
    var begin_pun: BeginPun = zero
    begin_pun.bits = list.vtable.slots[LIST_BEGIN]
    if begin_pun.function(mem.address_of(list), &slots, &array_iid[0usize], &removed) < 0i32 {
        com_release(list)
        ret Failed
    }
    com_release(removed)
    var clsid: [16]u8 = zero
    var iid: [16]u8 = zero
    guid(clsid[..], 758409409u32, 13991u16, 17334u16, 2888094704u32, 802775162u32)
    guid(iid[..], 1446162852u32, 58250u16, 16394u16, 2458571981u32, 1663238805u32)
    let (collection, collection_error) = com_create(clsid[..], iid[..])
    if collection_error != ok {
        let aborted = call_this(list, LIST_ABORT)
        com_release(list)
        ret collection_error
    }
    var failed = false
    at = 0usize
    while at < tasks.len && !failed {
        let (link, link_error) = task_link(a, tasks[at])
        if link_error != ok {
            failed = true
        } else {
            if call_object(collection, COLLECTION_ADD, mem.address_of(link)) < 0i32 { failed = true }
            com_release(link)
        }
        at += 1usize
    }
    if !failed && call_object(list, LIST_ADD_TASKS, mem.address_of(collection)) < 0i32 { failed = true }
    if !failed && call_this(list, LIST_COMMIT) < 0i32 { failed = true }
    if failed { let aborted = call_this(list, LIST_ABORT) }
    com_release(collection)
    com_release(list)
    if failed { ret Failed }
    ret ok
}

// The application's jump list removed.
fn jump_list_clear(a: *mem.Arena) -> err {
    try ensure_window()
    let (list, list_error) = destination_list()
    if list_error != ok { ret list_error }
    let deleted = call_object(list, LIST_DELETE, 0usize)
    com_release(list)
    if deleted < 0i32 { ret Failed }
    ret ok
}
