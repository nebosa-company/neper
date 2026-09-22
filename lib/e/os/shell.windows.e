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
error Cancelled

type Capabilities = struct { tray: bool, popup_menu: bool, open_uri: bool, reveal: bool, trash: bool, taskbar: bool, jump_list: bool, notices: bool, notice_actions: bool, notice_remove: bool, clipboard_text: bool, clipboard_typed: bool, drop_target: bool, drag_source: bool, file_dialogs: bool, recent_documents: bool, associations: bool, startup: bool, single_instance: bool, hotkeys: bool, power_inhibit: bool, lifecycle_events: bool, restart: bool }
// Rows top-down, a pixel `0xAARRGGBB`, as `os.window_present` takes them.
type Icon = struct { width: u32, height: u32, pixels: []const u32 }
type TrayEventKind = enum u8 { Select, Context, Open, NoticeSelect, NoticeDismiss }
type NoticePermission = enum u8 { Granted, Denied, Unavailable }
// One representation of transferred data: text, a list of paths, an image as
// pixels, bytes under a MIME name the other side registers the same way, or a
// promised file -- a name in `text` and contents in `bytes` that the receiver
// writes out itself when it takes the drop.
type ContentKind = enum u8 { Text, Files, Image, Bytes, Promise }
type Content = struct { kind: ContentKind, mime: str, text: str, paths: []const str, image: Icon, bytes: []const u8 }
type Drop = struct { x: i32, y: i32, items: []const Content }
type DragResult = enum u8 { Copied, Moved, Cancelled }
// A native file dialog: what it picks, its title, the filters offered (a label
// and a pattern such as `*.txt`), whether several may be chosen, the initial
// name, and the extension appended to a typed name without one.
type DialogKind = enum u8 { Open, Save, Folder }
type FileFilter = struct { label: str, pattern: str }
type FileDialog = struct { kind: DialogKind, title: str, filters: []const FileFilter, multiple: bool, initial: str, default_extension: str }
// How the program was activated: plainly, with a file, or with a URL; a
// redirected activation is another instance's arguments handed to the first.
type ActivationKind = enum u8 { Launch, File, Url }
type Activation = struct { kind: ActivationKind, payload: str, args: []const str }
// A global shortcut: the modifiers and the host's key code; a permission the
// host answers for background work; the lifecycle events a session sends.
type Hotkey = struct { control: bool, alt: bool, shift: bool, super: bool, key: u32 }
type Permission = enum u8 { Granted, Denied, Unavailable }
type LifecycleEvent = enum u8 { Shutdown, Suspend, Resume }
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
const WM_COPYDATA: u32 = 74u32
const NIN_BALLOONHIDE: u32 = 1027u32
const NIN_BALLOONTIMEOUT: u32 = 1028u32
const NIN_BALLOONUSERCLICK: u32 = 1029u32
const NIF_INFO: u32 = 16u32
const NIIF_INFO: u32 = 1u32
const NIIF_NOSOUND: u32 = 16u32
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
    ret Capabilities { tray: true, popup_menu: true, open_uri: true, reveal: true, trash: true, taskbar: true, jump_list: true, notices: true, notice_actions: false, notice_remove: true, clipboard_text: true, clipboard_typed: true, drop_target: true, drag_source: true, file_dialogs: true, recent_documents: true, associations: true, startup: true, single_instance: true, hotkeys: true, power_inhibit: true, lifecycle_events: true, restart: true }
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
    if message == WM_COPYDATA { ret receive_activation(lparam) }
    let (session, answer) = session_message(message, wparam)
    if session { ret answer }
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
                if mouse == NIN_BALLOONUSERCLICK {
                    event.kind = .NoticeSelect
                } else {
                    if mouse == NIN_BALLOONHIDE || mouse == NIN_BALLOONTIMEOUT {
                        event.kind = .NoticeDismiss
                    } else {
                        ret 0isize
                    }
                }
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

// ------------------------------------------------------------------ notices
//
// A notification (D889, widget plan `native-notification-api`) is the shell's
// balloon on a tray item the caller holds: `Shell_NotifyIconW` with `NIF_INFO`
// on the item's id, which the shell shows as a toast and keeps in the action
// centre; its activation and dismissal arrive at the hidden window as tray events
// of the item. A balloon has no permission to ask for and no buttons, so
// `notice_permission` is `Granted` and `notice_actions` is false. ponytail: the
// balloon; WinRT toasts carry buttons and need an AppUserModelID and a Start menu
// shortcut, which a Win32 program running from its build directory has not got.

fn notice_permission(a: *mem.Arena) -> NoticePermission {
    ret .Granted
}

fn copy_units(out: []u16, units: []const u16, limit: usize) {
    var count = 0usize
    while count < limit && units[count] != 0u16 { count += 1usize }
    if count == limit && units[limit - 1usize] >= 55296u16 && units[limit - 1usize] < 56320u16 { count = limit - 1usize }
    var at = 0usize
    while at < count {
        out[at] = units[at]
        at += 1usize
    }
    out[count] = 0u16
}

fn balloon(a: *mem.Arena, tray_id: u32, title: str, body: str, silent: bool) -> err {
    if tray_slot(tray_id) == TRAY_TABLE { ret NotFound }
    let (title_units, title_error) = widen(a, title)
    if title_error != ok { ret title_error }
    let (body_units, body_error) = widen(a, body)
    if body_error != ok { ret body_error }
    var data: NotifyIconData = zero
    data.size = NOTIFY_ICON_DATA_SIZE
    data.window = shell_window
    data.id = tray_id
    data.flags = NIF_INFO
    data.info_flags = NIIF_INFO
    if silent { data.info_flags = data.info_flags | NIIF_NOSOUND }
    copy_units(data.info_title[..], title_units, 63usize)
    copy_units(data.info[..], body_units, 255usize)
    if raw_notify_icon(NIM_MODIFY, &data) == 0i32 { ret Failed }
    ret ok
}

// The notice's id is the tray item's: one balloon per item at a time, a second
// replacing the first.
fn notice_publish(a: *mem.Arena, tray_id: u32, title: str, body: str, silent: bool) -> (u32, err) {
    if body.len == 0usize { ret (0u32, Invalid) }
    let shown = balloon(a, tray_id, title, body, silent)
    if shown != ok { ret (0u32, shown) }
    ret (tray_id, ok)
}

fn notice_update(a: *mem.Arena, tray_id: u32, notice_id: u32, title: str, body: str, silent: bool) -> err {
    if body.len == 0usize { ret Invalid }
    ret balloon(a, tray_id, title, body, silent)
}

// An empty balloon text takes the shown one down.
fn notice_remove(a: *mem.Arena, tray_id: u32, notice_id: u32) -> err {
    if tray_slot(tray_id) == TRAY_TABLE { ret NotFound }
    var data: NotifyIconData = zero
    data.size = NOTIFY_ICON_DATA_SIZE
    data.window = shell_window
    data.id = tray_id
    data.flags = NIF_INFO
    if raw_notify_icon(NIM_MODIFY, &data) == 0i32 { ret Failed }
    ret ok
}

// ------------------------------------------------------------- data exchange
//
// D890, the widget plan's `native-data-exchange-api`. The clipboard is the
// shell's, opened for each operation and closed after it, one global block per
// representation: text as CF_UNICODETEXT, paths as an HDROP, an image as a
// 32-bit CF_DIB, and bytes under a format the MIME name registers -- the same
// name on both sides is the same format. `clipboard_sequence` is the shell's
// change counter, which a monitor polls instead of reading. Drag and drop is
// OLE: a drop target is an `IDropTarget` this module implements over its slot
// table with `@cc(c)` functions, registered on the caller's window and copying
// each representation it understands into the caller's storage arena as the
// drop lands; a drag source is an `IDataObject` and an `IDropSource` the same
// way, offered to `DoDragDrop`, which blocks until the drop or the escape.

type FormatEtc = struct { format: u16, padding: u16, padding2: u32, device: usize, aspect: u32, index: i32, tymed: u32, padding3: u32 }
type StgMedium = struct { tymed: u32, padding: u32, handle: usize, release: usize }
type DropFiles = struct { files: u32, x: i32, y: i32, non_client: i32, wide: i32 }
type DibHeader = struct { size: u32, width: i32, height: i32, planes: u16, bit_count: u16, compression: u32, image_size: u32, x_ppm: i32, y_ppm: i32, colours_used: u32, colours_important: u32 }
type ComTable = struct { slots: [16]usize }
type ComImplementation = struct { vtable: *ComTable }
type Guid = struct { bytes: [16]u8 }
type Word = struct { value: usize }
type Effect = struct { value: u32 }

type QueryFn = union { function: fn(usize, *const Guid, *Word) -> i32, bits: usize }
type ThisFn = union { function: fn(usize) -> i32, bits: usize }
type EnterFn = union { function: fn(usize, *ComObject, u32, usize, *Effect) -> i32, bits: usize }
type OverFn = union { function: fn(usize, u32, usize, *Effect) -> i32, bits: usize }
type GetDataFn = union { function: fn(usize, *const FormatEtc, *StgMedium) -> i32, bits: usize }
type QueryDataFn = union { function: fn(usize, *const FormatEtc) -> i32, bits: usize }
type CanonicalFn = union { function: fn(usize, *const FormatEtc, *FormatEtc) -> i32, bits: usize }
type SetDataFn = union { function: fn(usize, *const FormatEtc, *StgMedium, i32) -> i32, bits: usize }
type EnumFn = union { function: fn(usize, u32, **ComObject) -> i32, bits: usize }
type AdviseFn = union { function: fn(usize, *const FormatEtc, u32, usize, *Effect) -> i32, bits: usize }
type UnadviseFn = union { function: fn(usize, u32) -> i32, bits: usize }
type EnumAdviseFn = union { function: fn(usize, **ComObject) -> i32, bits: usize }
type ContinueFn = union { function: fn(usize, i32, u32) -> i32, bits: usize }
type FeedbackFn = union { function: fn(usize, u32) -> i32, bits: usize }

@cc(c)
type ComGetData = extern fn(usize, *const FormatEtc, *StgMedium) -> i32
@cc(c)
type ComQueryData = extern fn(usize, *const FormatEtc) -> i32
type GetDataPun = union { function: ComGetData, bits: usize }
type QueryDataPun = union { function: ComQueryData, bits: usize }

const CF_UNICODETEXT: u32 = 13u32
const CF_DIB: u32 = 8u32
const CF_HDROP: u32 = 15u32
const GMEM_MOVEABLE_ZEROED: u32 = 66u32
const TYMED_HGLOBAL: u32 = 1u32
const DVASPECT_CONTENT: u32 = 1u32
const DROPEFFECT_NONE: u32 = 0u32
const DROPEFFECT_COPY: u32 = 1u32
const DROPEFFECT_MOVE: u32 = 2u32
const S_OK: i32 = 0i32
const S_FALSE: i32 = 1i32
const E_NOINTERFACE: u32 = 2147500034u32
const E_NOTIMPL: u32 = 2147500033u32
const DV_E_FORMATETC: u32 = 2147745892u32
const OLE_E_ADVISENOTSUPPORTED: u32 = 2147745795u32
const DRAGDROP_S_DROP: i32 = 262400i32
const DRAGDROP_S_CANCEL: i32 = 262401i32
const DRAGDROP_S_USEDEFAULTCURSORS: i32 = 262402i32
const MK_BUTTONS: u32 = 3u32
const DATA_OBJECT_GET_DATA: usize = 3usize
const DROP_RING: usize = 8usize
const MAX_DROP_ITEMS: usize = 4usize
const MAX_DRAG_ITEMS: usize = 6usize
const IID_UNKNOWN: u32 = 0u32
const IID_DATA_OBJECT: u32 = 270u32
const IID_DROP_SOURCE: u32 = 289u32
const IID_DROP_TARGET: u32 = 290u32

var drop_tables: [1]ComTable = zero
var drop_objects: [1]ComImplementation = zero
var drop_window: usize = 0usize
var drop_storage: *mem.Arena = zero
var drops: [8]Drop = zero
var drop_head: usize = 0usize
var drop_count: usize = 0usize
var ole_ready: bool = zero
var data_tables: [1]ComTable = zero
var data_objects: [1]ComImplementation = zero
var source_tables: [1]ComTable = zero
var source_objects: [1]ComImplementation = zero
var drag_items: []const Content = zero
var drag_formats: [8]FormatEtc = zero
var drag_format_count: usize = 0usize
var drag_arena: *mem.Arena = zero
var descriptor_format: u32 = 0u32
var contents_format: u32 = 0u32

@import("user32.dll", "OpenClipboard")
extern fn raw_open_clipboard(owner: usize) -> i32

@import("user32.dll", "CloseClipboard")
extern fn raw_close_clipboard() -> i32

@import("user32.dll", "EmptyClipboard")
extern fn raw_empty_clipboard() -> i32

@import("user32.dll", "GetClipboardData")
extern fn raw_clipboard_data(format: u32) -> usize

@import("user32.dll", "SetClipboardData")
extern fn raw_set_clipboard_data(format: u32, handle: usize) -> usize

@import("user32.dll", "IsClipboardFormatAvailable")
extern fn raw_clipboard_format_available(format: u32) -> i32

@import("user32.dll", "RegisterClipboardFormatW")
extern fn raw_register_clipboard_format(name: *const u16) -> u32

@import("user32.dll", "GetClipboardSequenceNumber")
extern fn raw_clipboard_sequence() -> u32

@import("kernel32.dll", "GlobalAlloc")
extern fn raw_global_alloc(flags: u32, bytes: usize) -> usize

@import("kernel32.dll", "GlobalLock")
extern fn raw_global_lock(handle: usize) -> *u8

@import("kernel32.dll", "GlobalUnlock")
extern fn raw_global_unlock(handle: usize) -> i32

@import("kernel32.dll", "GlobalSize")
extern fn raw_global_size(handle: usize) -> usize

@import("kernel32.dll", "GlobalFree")
extern fn raw_global_free(handle: usize) -> usize

@import("kernel32.dll", "WideCharToMultiByte")
extern fn raw_narrow(code_page: u32, flags: u32, source: *const u16, source_len: i32, out: *u8, out_len: i32, default_char: usize, used_default: usize) -> i32

@import("kernel32.dll", "lstrlenW")
extern fn raw_wide_length(text: *const u16) -> i32

@import("kernel32.dll", "Sleep")
extern fn raw_sleep(milliseconds: u32)

@import("shell32.dll", "DragQueryFileW")
extern fn raw_drag_query_file(drop: usize, index: u32, out: *u16, count: u32) -> u32

@import("shell32.dll", "SHCreateStdEnumFmtEtc")
extern fn raw_create_format_enumerator(count: u32, formats: *const FormatEtc, out: **ComObject) -> i32

@import("ole32.dll", "OleInitialize")
extern fn raw_ole_initialize(reserved: usize) -> i32

@import("ole32.dll", "RegisterDragDrop")
extern fn raw_register_drag_drop(window: usize, receiver: *const ComImplementation) -> i32

@import("ole32.dll", "RevokeDragDrop")
extern fn raw_revoke_drag_drop(window: usize) -> i32

@import("ole32.dll", "DoDragDrop")
extern fn raw_do_drag_drop(data: *const ComImplementation, source: *const ComImplementation, allowed: u32, effect: *u32) -> i32

@import("ole32.dll", "ReleaseStgMedium")
extern fn raw_release_medium(medium: *StgMedium)

fn put_u32(block: []u8, at: usize, value: u32) {
    block[at] = u8(value & 255u32)
    block[at + 1usize] = u8((value >> 8u32) & 255u32)
    block[at + 2usize] = u8((value >> 16u32) & 255u32)
    block[at + 3usize] = u8(value >> 24u32)
}

fn get_u32(block: []const u8, at: usize) -> u32 {
    ret u32(block[at]) | (u32(block[at + 1usize]) << 8u32) | (u32(block[at + 2usize]) << 16u32) | (u32(block[at + 3usize]) << 24u32)
}

// An HRESULT is a signed word whose failures have the top bit set; spelled as
// the bits and read back as the word.
fn hresult(bits: u32) -> i32 {
    ret mem.bitcast[i32](bits)
}

// The shell's two promised-file formats, registered by name once.
fn ensure_promise_formats(a: *mem.Arena) -> err {
    if descriptor_format != 0u32 { ret ok }
    let (descriptor_name, descriptor_error) = widen(a, "FileGroupDescriptorW")
    if descriptor_error != ok { ret descriptor_error }
    let (contents_name, contents_error) = widen(a, "FileContents")
    if contents_error != ok { ret contents_error }
    let descriptor = raw_register_clipboard_format(&descriptor_name[0usize])
    let contents = raw_register_clipboard_format(&contents_name[0usize])
    if descriptor == 0u32 || contents == 0u32 { ret Failed }
    descriptor_format = descriptor
    contents_format = contents
    ret ok
}

// FILEGROUPDESCRIPTORW over the promised items: a count, then 592 bytes per file
// with the size flag, the size and the name.
fn descriptor_block(a: *mem.Arena, items: []const Content) -> (usize, err) {
    var count = 0usize
    var at = 0usize
    while at < items.len {
        if items[at].kind == .Promise { count += 1usize }
        at += 1usize
    }
    if count == 0usize { ret (0usize, NotFound) }
    let total = 4usize + count * 592usize
    let (block, allocation_error) = mem.alloc[u8](a, total)
    if allocation_error != ok { ret (0usize, allocation_error) }
    at = 0usize
    while at < total {
        block[at] = 0u8
        at += 1usize
    }
    put_u32(block, 0usize, u32(count))
    var index = 0usize
    at = 0usize
    while at < items.len {
        if items[at].kind == .Promise {
            let base = 4usize + index * 592usize
            put_u32(block, base, 64u32)
            put_u32(block, base + 68usize, u32(items[at].bytes.len))
            let (name, widen_error) = widen(a, items[at].text)
            if widen_error != ok { ret (0usize, widen_error) }
            var unit = 0usize
            while unit < 259usize && name[unit] != 0u16 {
                block[base + 72usize + unit * 2usize] = u8(name[unit] & 255u16)
                block[base + 72usize + unit * 2usize + 1usize] = u8(name[unit] >> 8u16)
                unit += 1usize
            }
            index += 1usize
        }
        at += 1usize
    }
    let handle = global_from_bytes(block[0usize..total])
    if handle == 0usize { ret (0usize, Failed) }
    ret (handle, ok)
}

fn promised_item(items: []const Content, index: i32) -> (usize, bool) {
    if index < 0i32 { ret (0usize, false) }
    var seen = 0i32
    var at = 0usize
    while at < items.len {
        if items[at].kind == .Promise {
            if seen == index { ret (at, true) }
            seen += 1i32
        }
        at += 1usize
    }
    ret (0usize, false)
}

fn clipboard_open() -> err {
    var attempt = 0usize
    while attempt <= 10usize {
        if raw_open_clipboard(shell_window) != 0i32 { ret ok }
        raw_sleep(10u32)
        attempt += 1usize
    }
    ret Failed
}

// The bytes of a global block, as a slice of the block itself; unlocked by the caller.
fn global_bytes(handle: usize) -> ([]u8, bool) {
    var nothing: []u8 = zero
    let base = raw_global_lock(handle)
    if mem.address_of(base) == 0usize { ret (nothing, false) }
    let size = raw_global_size(handle)
    var region: mem.Arena = zero
    region.base = base
    region.cap = size
    region.off = 0usize
    ret (mem.view(&region, 0usize, size), true)
}

// Exactly the bytes: a moveable block's size is what was asked, which is how a
// receiver of a custom format learns the length.
fn global_from_bytes(bytes: []const u8) -> usize {
    let handle = raw_global_alloc(GMEM_MOVEABLE_ZEROED, bytes.len)
    if handle == 0usize { ret 0usize }
    let (block, locked) = global_bytes(handle)
    if !locked {
        let freed = raw_global_free(handle)
        ret 0usize
    }
    var at = 0usize
    while at < bytes.len {
        block[at] = bytes[at]
        at += 1usize
    }
    let unlocked = raw_global_unlock(handle)
    ret handle
}

fn global_from_units(units: []const u16) -> usize {
    let handle = raw_global_alloc(GMEM_MOVEABLE_ZEROED, units.len * 2usize)
    if handle == 0usize { ret 0usize }
    let (block, locked) = global_bytes(handle)
    if !locked {
        let freed = raw_global_free(handle)
        ret 0usize
    }
    var at = 0usize
    while at < units.len {
        block[at * 2usize] = u8(units[at] & 255u16)
        block[at * 2usize + 1usize] = u8(units[at] >> 8u16)
        at += 1usize
    }
    let unlocked = raw_global_unlock(handle)
    ret handle
}

// A format's id: the three standard ones by kind, bytes by their registered name.
fn format_of(a: *mem.Arena, kind: ContentKind, mime: str) -> (u32, err) {
    if kind == .Text { ret (CF_UNICODETEXT, ok) }
    if kind == .Promise { ret (0u32, Unsupported) }
    if kind == .Files { ret (CF_HDROP, ok) }
    if kind == .Image { ret (CF_DIB, ok) }
    if mime.len == 0usize { ret (0u32, Invalid) }
    let (name, widen_error) = widen(a, mime)
    if widen_error != ok { ret (0u32, widen_error) }
    let format = raw_register_clipboard_format(&name[0usize])
    if format == 0u32 { ret (0u32, Failed) }
    ret (format, ok)
}

// One representation as a global block the receiver owns: text as units with a
// terminator, paths as DROPFILES over double-terminated wide names, an image as
// a bottom-up 32-bit DIB, bytes as they are.
fn global_of(a: *mem.Arena, item: Content) -> (usize, err) {
    if item.kind == .Text {
        let (units, widen_error) = widen(a, item.text)
        if widen_error != ok { ret (0usize, widen_error) }
        var count = 0usize
        while units[count] != 0u16 { count += 1usize }
        let handle = global_from_units(units[0usize..count + 1usize])
        if handle == 0usize { ret (0usize, Failed) }
        ret (handle, ok)
    }
    if item.kind == .Files {
        if item.paths.len == 0usize { ret (0usize, Invalid) }
        var total = 20usize + 2usize
        var at = 0usize
        while at < item.paths.len {
            total += (item.paths[at].len + 1usize) * 2usize
            at += 1usize
        }
        let (block, allocation_error) = mem.alloc[u8](a, total)
        if allocation_error != ok { ret (0usize, allocation_error) }
        // DROPFILES: the offset of the names, a point, a client flag and the wide flag.
        at = 0usize
        while at < 20usize {
            block[at] = 0u8
            at += 1usize
        }
        block[0usize] = 20u8
        block[16usize] = 1u8
        var written = 20usize
        at = 0usize
        while at < item.paths.len {
            let (units, widen_error) = widen(a, item.paths[at])
            if widen_error != ok { ret (0usize, widen_error) }
            var count = 0usize
            while units[count] != 0u16 {
                block[written] = u8(units[count] & 255u16)
                block[written + 1usize] = u8(units[count] >> 8u16)
                written += 2usize
                count += 1usize
            }
            block[written] = 0u8
            block[written + 1usize] = 0u8
            written += 2usize
            at += 1usize
        }
        block[written] = 0u8
        block[written + 1usize] = 0u8
        written += 2usize
        let handle = global_from_bytes(block[0usize..written])
        if handle == 0usize { ret (0usize, Failed) }
        ret (handle, ok)
    }
    if item.kind == .Image {
        let icon = item.image
        if icon.width == 0u32 || icon.height == 0u32 || icon.pixels.len < usize(icon.width) * usize(icon.height) { ret (0usize, Invalid) }
        let pixel_bytes = usize(icon.width) * usize(icon.height) * 4usize
        let (block, allocation_error) = mem.alloc[u8](a, 40usize + pixel_bytes)
        if allocation_error != ok { ret (0usize, allocation_error) }
        var at = 0usize
        while at < 40usize {
            block[at] = 0u8
            at += 1usize
        }
        put_u32(block, 0usize, 40u32)
        put_u32(block, 4usize, icon.width)
        put_u32(block, 8usize, icon.height)
        block[12usize] = 1u8
        block[14usize] = 32u8
        put_u32(block, 20usize, u32(pixel_bytes))
        // Bottom-up: the last row first.
        var row = 0usize
        while row < usize(icon.height) {
            let source_row = usize(icon.height) - 1usize - row
            var column = 0usize
            while column < usize(icon.width) {
                let pixel = icon.pixels[source_row * usize(icon.width) + column]
                let offset = 40usize + (row * usize(icon.width) + column) * 4usize
                block[offset] = u8(pixel & 255u32)
                block[offset + 1usize] = u8((pixel >> 8u32) & 255u32)
                block[offset + 2usize] = u8((pixel >> 16u32) & 255u32)
                block[offset + 3usize] = u8(pixel >> 24u32)
                column += 1usize
            }
            row += 1usize
        }
        let handle = global_from_bytes(block[0usize..40usize + pixel_bytes])
        if handle == 0usize { ret (0usize, Failed) }
        ret (handle, ok)
    }
    let handle = global_from_bytes(item.bytes)
    if handle == 0usize { ret (0usize, Failed) }
    ret (handle, ok)
}

// A representation read out of a global block into the arena, or `Unsupported`
// for a DIB this does not decode (only 24- and 32-bit uncompressed ones are).
fn content_of(a: *mem.Arena, kind: ContentKind, mime: str, handle: usize) -> (Content, err) {
    var item: Content = zero
    item.kind = kind
    item.mime = mime
    if kind == .Text {
        let units = mem.cast[*const u16](raw_global_lock(handle))
        if mem.address_of(units) == 0usize { ret (item, Failed) }
        let count = usize(raw_wide_length(units))
        var text_error = ok
        if count != 0usize {
            let (bytes, bytes_error) = mem.alloc[u8](a, count * 3usize)
            if bytes_error != ok {
                text_error = bytes_error
            } else {
                os.touch(&bytes[0usize], count * 3usize)
                let converted = raw_narrow(CP_UTF8, 0u32, units, i32(count), &bytes[0usize], i32(count * 3usize), 0usize, 0usize)
                if converted <= 0i32 { text_error = Failed } else { item.text = bytes[0usize..usize(converted)] }
            }
        }
        let unlocked = raw_global_unlock(handle)
        ret (item, text_error)
    }
    if kind == .Files {
        let count = raw_drag_query_file(handle, 4294967295u32, &empty_wide[0usize], 0u32)
        let (paths, allocation_error) = mem.alloc[str](a, usize(count))
        if allocation_error != ok { ret (item, allocation_error) }
        var index = 0u32
        while index < count {
            let units = raw_drag_query_file(handle, index, &empty_wide[0usize], 0u32)
            let (wide, wide_error) = mem.alloc[u16](a, usize(units) + 1usize)
            if wide_error != ok { ret (item, wide_error) }
            os.touch(mem.cast[*const u8](&wide[0usize]), (usize(units) + 1usize) * 2usize)
            let copied = raw_drag_query_file(handle, index, &wide[0usize], units + 1u32)
            let (bytes, bytes_error) = mem.alloc[u8](a, usize(units) * 3usize + 1usize)
            if bytes_error != ok { ret (item, bytes_error) }
            os.touch(&bytes[0usize], usize(units) * 3usize + 1usize)
            var length = 0usize
            if units != 0u32 {
                let converted = raw_narrow(CP_UTF8, 0u32, &wide[0usize], i32(units), &bytes[0usize], i32(usize(units) * 3usize), 0usize, 0usize)
                if converted <= 0i32 { ret (item, Failed) }
                length = usize(converted)
            }
            paths[usize(index)] = bytes[0usize..length]
            index += 1u32
        }
        item.paths = paths[0usize..usize(count)]
        ret (item, ok)
    }
    let (block, locked) = global_bytes(handle)
    if !locked { ret (item, Failed) }
    if kind == .Bytes {
        let (copy, allocation_error) = mem.alloc[u8](a, block.len)
        if allocation_error != ok {
            let unlocked = raw_global_unlock(handle)
            ret (item, allocation_error)
        }
        mem.copy[u8](copy, block)
        item.bytes = copy[0usize..block.len]
        let unlocked = raw_global_unlock(handle)
        ret (item, ok)
    }
    // A DIB: the header, then the rows bottom-up, each padded to four bytes.
    if block.len < 40usize {
        let unlocked = raw_global_unlock(handle)
        ret (item, Unsupported)
    }
    let header_size = get_u32(block, 0usize)
    let dib_width = mem.bitcast[i32](get_u32(block, 4usize))
    var height = mem.bitcast[i32](get_u32(block, 8usize))
    let bits = usize(block[14usize]) | (usize(block[15usize]) << 8usize)
    let compression = get_u32(block, 16usize)
    let colours_used = get_u32(block, 32usize)
    var bottom_up = true
    if height < 0i32 {
        height = 0i32 - height
        bottom_up = false
    }
    if dib_width <= 0i32 || height <= 0i32 || (bits != 32usize && bits != 24usize) || (compression != 0u32 && compression != 3u32) {
        let unlocked = raw_global_unlock(handle)
        ret (item, Unsupported)
    }
    let width = usize(dib_width)
    let rows = usize(height)
    let stride = ((width * bits + 31usize) / 32usize) * 4usize
    var pixel_start = usize(header_size)
    if compression == 3u32 { pixel_start += 12usize }
    if bits <= 8usize { pixel_start += usize(colours_used) * 4usize }
    if block.len < pixel_start + stride * rows {
        let unlocked = raw_global_unlock(handle)
        ret (item, Unsupported)
    }
    let (pixels, allocation_error) = mem.alloc[u32](a, width * rows)
    if allocation_error != ok {
        let unlocked = raw_global_unlock(handle)
        ret (item, allocation_error)
    }
    var row = 0usize
    while row < rows {
        var source_row = row
        if bottom_up { source_row = rows - 1usize - row }
        var column = 0usize
        while column < width {
            let offset = pixel_start + source_row * stride + column * (bits / 8usize)
            var alpha = 255u32
            if bits == 32usize { alpha = u32(block[offset + 3usize]) }
            pixels[row * width + column] = (alpha << 24u32) | (u32(block[offset + 2usize]) << 16u32) | (u32(block[offset + 1usize]) << 8u32) | u32(block[offset])
            column += 1usize
        }
        row += 1usize
    }
    let unlocked = raw_global_unlock(handle)
    item.image = Icon { width: u32(width), height: u32(rows), pixels: pixels[0usize..width * rows] }
    ret (item, ok)
}

// The clipboard replaced by these representations, one block each.
fn clipboard_write(a: *mem.Arena, items: []const Content) -> err {
    if items.len == 0usize { ret Invalid }
    try ensure_window()
    var at = 0usize
    while at < items.len {
        if items[at].kind == .Bytes && items[at].mime.len == 0usize { ret Invalid }
        at += 1usize
    }
    try clipboard_open()
    if raw_empty_clipboard() == 0i32 {
        let closed = raw_close_clipboard()
        ret Failed
    }
    var failure = ok
    at = 0usize
    while at < items.len && failure == ok {
        let (format, format_error) = format_of(a, items[at].kind, items[at].mime)
        if format_error != ok {
            failure = format_error
        } else {
            let (handle, handle_error) = global_of(a, items[at])
            if handle_error != ok {
                failure = handle_error
            } else {
                if raw_set_clipboard_data(format, handle) == 0usize {
                    let freed = raw_global_free(handle)
                    failure = Failed
                }
            }
        }
        at += 1usize
    }
    let closed = raw_close_clipboard()
    ret failure
}

// Whether the clipboard holds this representation now -- asked, not read.
fn clipboard_has(a: *mem.Arena, kind: ContentKind, mime: str) -> bool {
    let (format, format_error) = format_of(a, kind, mime)
    if format_error != ok { ret false }
    ret raw_clipboard_format_available(format) != 0i32
}

fn clipboard_read(a: *mem.Arena, kind: ContentKind, mime: str) -> (Content, err) {
    var nothing: Content = zero
    let (format, format_error) = format_of(a, kind, mime)
    if format_error != ok { ret (nothing, format_error) }
    let window_error = ensure_window()
    if window_error != ok { ret (nothing, window_error) }
    let open_error = clipboard_open()
    if open_error != ok { ret (nothing, open_error) }
    let handle = raw_clipboard_data(format)
    if handle == 0usize {
        let closed = raw_close_clipboard()
        ret (nothing, NotFound)
    }
    let (item, content_error) = content_of(a, kind, mime, handle)
    let closed = raw_close_clipboard()
    ret (item, content_error)
}

// The shell's clipboard change counter: a different number is a different clipboard.
fn clipboard_sequence() -> u32 {
    ret raw_clipboard_sequence()
}

fn guid_is(riid: *const Guid, data1: u32) -> bool {
    let first = u32(riid.bytes[0usize]) | (u32(riid.bytes[1usize]) << 8u32) | (u32(riid.bytes[2usize]) << 16u32) | (u32(riid.bytes[3usize]) << 24u32)
    if first != data1 { ret false }
    var at = 4usize
    while at < 8usize {
        if riid.bytes[at] != 0u8 { ret false }
        at += 1usize
    }
    ret riid.bytes[8usize] == 192u8 && riid.bytes[9usize] == 0u8 && riid.bytes[10usize] == 0u8 && riid.bytes[11usize] == 0u8 && riid.bytes[12usize] == 0u8 && riid.bytes[13usize] == 0u8 && riid.bytes[14usize] == 0u8 && riid.bytes[15usize] == 70u8
}

// The objects here live in globals and are never freed, so their reference
// counts are a formality answered with one.
@cc(c)
fn com_add_ref(this: usize) -> i32 {
    ret 1i32
}

@cc(c)
fn com_release_static(this: usize) -> i32 {
    ret 1i32
}

@cc(c)
fn drop_query_interface(this: usize, riid: *const Guid, out: *Word) -> i32 {
    if guid_is(riid, IID_UNKNOWN) || guid_is(riid, IID_DROP_TARGET) {
        out.value = this
        ret S_OK
    }
    out.value = 0usize
    ret hresult(E_NOINTERFACE)
}

fn point_of(packed: usize) -> (i32, i32) {
    ret (mem.bitcast[i32](u32(packed & 4294967295usize)), mem.bitcast[i32](u32(packed >> 32usize)))
}

@cc(c)
fn drop_enter(this: usize, data: *ComObject, keys: u32, point: usize, effect: *Effect) -> i32 {
    effect.value = DROPEFFECT_COPY
    ret S_OK
}

@cc(c)
fn drop_over(this: usize, keys: u32, point: usize, effect: *Effect) -> i32 {
    effect.value = DROPEFFECT_COPY
    ret S_OK
}

@cc(c)
fn drop_leave(this: usize) -> i32 {
    ret S_OK
}

// One representation asked of the dropped data object, into the storage arena.
fn take_representation(data: *ComObject, kind: ContentKind, format: u32, out: *Content) -> bool {
    var request: FormatEtc = zero
    request.format = u16(format)
    request.aspect = DVASPECT_CONTENT
    request.index = 0i32 - 1i32
    request.tymed = TYMED_HGLOBAL
    var query: QueryDataPun = zero
    query.bits = data.vtable.slots[5usize]
    if query.function(mem.address_of(data), &request) != S_OK { ret false }
    var medium: StgMedium = zero
    var getter: GetDataPun = zero
    getter.bits = data.vtable.slots[DATA_OBJECT_GET_DATA]
    if getter.function(mem.address_of(data), &request, &medium) != S_OK { ret false }
    var taken = false
    if medium.tymed == TYMED_HGLOBAL && medium.handle != 0usize {
        let (item, content_error) = content_of(drop_storage, kind, "", medium.handle)
        if content_error == ok {
            *out = item
            taken = true
        }
    }
    raw_release_medium(&medium)
    ret taken
}

// The other program's promised files, one `.Promise` item per file into `out`
// as far as it holds: the descriptor names and sizes them, and the contents come
// one index at a time; a file offered only as a stream is passed over.
fn take_promises(data: *ComObject, out: []Content) -> usize {
    var request: FormatEtc = zero
    request.format = u16(descriptor_format)
    request.aspect = DVASPECT_CONTENT
    request.index = 0i32 - 1i32
    request.tymed = TYMED_HGLOBAL
    var getter: GetDataPun = zero
    getter.bits = data.vtable.slots[DATA_OBJECT_GET_DATA]
    var medium: StgMedium = zero
    if getter.function(mem.address_of(data), &request, &medium) != S_OK { ret 0usize }
    var found = 0usize
    if medium.tymed == TYMED_HGLOBAL && medium.handle != 0usize {
        let (block, locked) = global_bytes(medium.handle)
        if locked {
            let count = usize(get_u32(block, 0usize))
            if block.len >= 4usize + count * 592usize && count != 0usize {
                if true {
                    var index = 0usize
                    while index < count && found < out.len {
                        let base = 4usize + index * 592usize
                        var units = 0usize
                        while units < 260usize && (block[base + 72usize + units * 2usize] != 0u8 || block[base + 72usize + units * 2usize + 1usize] != 0u8) { units += 1usize }
                        let (wide, wide_error) = mem.alloc[u16](drop_storage, units + 1usize)
                        if wide_error != ok { break }
                        var unit = 0usize
                        while unit < units {
                            wide[unit] = u16(block[base + 72usize + unit * 2usize]) | (u16(block[base + 72usize + unit * 2usize + 1usize]) << 8u16)
                            unit += 1usize
                        }
                        wide[units] = 0u16
                        let (name_bytes, name_error) = mem.alloc[u8](drop_storage, units * 3usize + 1usize)
                        if name_error != ok { break }
                        os.touch(&name_bytes[0usize], units * 3usize + 1usize)
                        var name_len = 0usize
                        if units != 0usize {
                            let converted = raw_narrow(CP_UTF8, 0u32, &wide[0usize], i32(units), &name_bytes[0usize], i32(units * 3usize), 0usize, 0usize)
                            if converted > 0i32 { name_len = usize(converted) }
                        }
                        var contents_request: FormatEtc = zero
                        contents_request.format = u16(contents_format)
                        contents_request.aspect = DVASPECT_CONTENT
                        contents_request.index = i32(index)
                        contents_request.tymed = TYMED_HGLOBAL
                        var contents_medium: StgMedium = zero
                        if getter.function(mem.address_of(data), &contents_request, &contents_medium) == S_OK {
                            if contents_medium.tymed == TYMED_HGLOBAL && contents_medium.handle != 0usize {
                                let (item, content_error) = content_of(drop_storage, .Bytes, "", contents_medium.handle)
                                if content_error == ok {
                                    var promise: Content = zero
                                    promise.kind = .Promise
                                    promise.text = name_bytes[0usize..name_len]
                                    promise.bytes = item.bytes
                                    out[found] = promise
                                    found += 1usize
                                }
                            }
                            raw_release_medium(&contents_medium)
                        }
                        index += 1usize
                    }
                }
            }
            let unlocked = raw_global_unlock(medium.handle)
        }
    }
    raw_release_medium(&medium)
    ret found
}

@cc(c)
fn drop_drop(this: usize, data: *ComObject, keys: u32, point: usize, effect: *Effect) -> i32 {
    effect.value = DROPEFFECT_NONE
    if mem.address_of(drop_storage) == 0usize || drop_count == DROP_RING { ret S_OK }
    let (items, allocation_error) = mem.alloc[Content](drop_storage, MAX_DROP_ITEMS)
    if allocation_error != ok { ret S_OK }
    var count = 0usize
    if take_representation(data, .Files, CF_HDROP, &items[count]) { count += 1usize }
    if take_representation(data, .Text, CF_UNICODETEXT, &items[count]) { count += 1usize }
    if take_representation(data, .Image, CF_DIB, &items[count]) { count += 1usize }
    if descriptor_format != 0u32 { count += take_promises(data, items[count..MAX_DROP_ITEMS]) }
    if count == 0usize { ret S_OK }
    var landed: Drop = zero
    let (x, y) = point_of(point)
    landed.x = x
    landed.y = y
    landed.items = items[0usize..count]
    drops[(drop_head + drop_count) % DROP_RING] = landed
    drop_count += 1usize
    effect.value = DROPEFFECT_COPY
    ret S_OK
}

fn ensure_ole() -> err {
    try ensure_window()
    if ole_ready { ret ok }
    let initialised = raw_ole_initialize(0usize)
    ole_ready = true
    ret ok
}

fn slot_of_query(f: fn(usize, *const Guid, *Word) -> i32) -> usize {
    var pun: QueryFn = zero
    pun.function = f
    ret pun.bits
}

fn slot_of_this(f: fn(usize) -> i32) -> usize {
    var pun: ThisFn = zero
    pun.function = f
    ret pun.bits
}

// The caller's window receives drops from other programs; what lands is copied
// into `storage`, which the caller keeps for as long as drops are polled.
fn drop_target_register(a: *mem.Arena, w: os.Window, storage: *mem.Arena) -> err {
    let (handle, handle_error) = window_handle(w)
    if handle_error != ok { ret handle_error }
    if drop_window != 0usize { ret Invalid }
    try ensure_ole()
    try ensure_promise_formats(a)
    drop_tables[0usize].slots[0usize] = slot_of_query(drop_query_interface)
    drop_tables[0usize].slots[1usize] = slot_of_this(com_add_ref)
    drop_tables[0usize].slots[2usize] = slot_of_this(com_release_static)
    var enter: EnterFn = zero
    enter.function = drop_enter
    drop_tables[0usize].slots[3usize] = enter.bits
    var over: OverFn = zero
    over.function = drop_over
    drop_tables[0usize].slots[4usize] = over.bits
    drop_tables[0usize].slots[5usize] = slot_of_this(drop_leave)
    var landed: EnterFn = zero
    landed.function = drop_drop
    drop_tables[0usize].slots[6usize] = landed.bits
    drop_objects[0usize].vtable = &drop_tables[0usize]
    drop_storage = storage
    if raw_register_drag_drop(handle, &drop_objects[0usize]) < 0i32 {
        var no_storage: *mem.Arena = zero
        drop_storage = no_storage
        ret Failed
    }
    drop_window = handle
    ret ok
}

fn drop_target_unregister(a: *mem.Arena, w: os.Window) -> err {
    let (handle, handle_error) = window_handle(w)
    if handle_error != ok { ret handle_error }
    if drop_window != handle { ret NotFound }
    let revoked = raw_revoke_drag_drop(handle)
    drop_window = 0usize
    var no_storage: *mem.Arena = zero
    drop_storage = no_storage
    ret ok
}

// The oldest drop; OLE delivers one through the caller's own window loop, so
// a program without one sees nothing.
fn drop_poll() -> (Drop, bool) {
    var none: Drop = zero
    if drop_count == 0usize { ret (none, false) }
    let landed = drops[drop_head]
    drop_head = (drop_head + 1usize) % DROP_RING
    drop_count -= 1usize
    ret (landed, true)
}

@cc(c)
fn data_query_interface(this: usize, riid: *const Guid, out: *Word) -> i32 {
    if guid_is(riid, IID_UNKNOWN) || guid_is(riid, IID_DATA_OBJECT) {
        out.value = this
        ret S_OK
    }
    out.value = 0usize
    ret hresult(E_NOINTERFACE)
}

fn drag_item_for(format: u16) -> (usize, bool) {
    var at = 0usize
    while at < drag_format_count {
        if drag_formats[at].format == format { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

@cc(c)
fn data_get_data(this: usize, request: *const FormatEtc, medium: *StgMedium) -> i32 {
    if (request.tymed & TYMED_HGLOBAL) == 0u32 { ret hresult(DV_E_FORMATETC) }
    var handle = 0usize
    if descriptor_format != 0u32 && u32(request.format) == descriptor_format {
        let (descriptor, descriptor_error) = descriptor_block(drag_arena, drag_items)
        if descriptor_error != ok { ret hresult(DV_E_FORMATETC) }
        handle = descriptor
    } else {
        if contents_format != 0u32 && u32(request.format) == contents_format {
            let (promised, has_promised) = promised_item(drag_items, request.index)
            if !has_promised { ret hresult(DV_E_FORMATETC) }
            handle = global_from_bytes(drag_items[promised].bytes)
            if handle == 0usize { ret hresult(DV_E_FORMATETC) }
        } else {
            let (index, found) = drag_item_for(request.format)
            if !found { ret hresult(DV_E_FORMATETC) }
            let (block, block_error) = global_of(drag_arena, drag_items[index])
            if block_error != ok { ret hresult(DV_E_FORMATETC) }
            handle = block
        }
    }
    medium.tymed = TYMED_HGLOBAL
    medium.handle = handle
    medium.release = 0usize
    ret S_OK
}

@cc(c)
fn data_get_data_here(this: usize, request: *const FormatEtc, medium: *StgMedium) -> i32 {
    ret hresult(E_NOTIMPL)
}

@cc(c)
fn data_query_get_data(this: usize, request: *const FormatEtc) -> i32 {
    if (request.tymed & TYMED_HGLOBAL) == 0u32 { ret hresult(DV_E_FORMATETC) }
    if descriptor_format != 0u32 && (u32(request.format) == descriptor_format || u32(request.format) == contents_format) {
        let (promised, has_promised) = promised_item(drag_items, 0i32)
        if !has_promised { ret hresult(DV_E_FORMATETC) }
        ret S_OK
    }
    let (index, found) = drag_item_for(request.format)
    if !found { ret hresult(DV_E_FORMATETC) }
    ret S_OK
}

@cc(c)
fn data_canonical(this: usize, request: *const FormatEtc, out: *FormatEtc) -> i32 {
    ret hresult(E_NOTIMPL)
}

@cc(c)
fn data_set_data(this: usize, request: *const FormatEtc, medium: *StgMedium, release: i32) -> i32 {
    ret hresult(E_NOTIMPL)
}

@cc(c)
fn data_enum_format(this: usize, direction: u32, out: **ComObject) -> i32 {
    if direction != 1u32 { ret hresult(E_NOTIMPL) }
    ret raw_create_format_enumerator(u32(drag_format_count), &drag_formats[0usize], out)
}

@cc(c)
fn data_advise(this: usize, request: *const FormatEtc, flags: u32, sink: usize, out: *Effect) -> i32 {
    ret hresult(OLE_E_ADVISENOTSUPPORTED)
}

@cc(c)
fn data_unadvise(this: usize, connection: u32) -> i32 {
    ret hresult(OLE_E_ADVISENOTSUPPORTED)
}

@cc(c)
fn data_enum_advise(this: usize, out: **ComObject) -> i32 {
    ret hresult(OLE_E_ADVISENOTSUPPORTED)
}

@cc(c)
fn source_query_interface(this: usize, riid: *const Guid, out: *Word) -> i32 {
    if guid_is(riid, IID_UNKNOWN) || guid_is(riid, IID_DROP_SOURCE) {
        out.value = this
        ret S_OK
    }
    out.value = 0usize
    ret hresult(E_NOINTERFACE)
}

// The drag ends when the escape is pressed or every button is up.
@cc(c)
fn source_continue(this: usize, escaped: i32, keys: u32) -> i32 {
    if escaped != 0i32 { ret DRAGDROP_S_CANCEL }
    if (keys & MK_BUTTONS) == 0u32 { ret DRAGDROP_S_DROP }
    ret S_OK
}

@cc(c)
fn source_feedback(this: usize, effect: u32) -> i32 {
    ret DRAGDROP_S_USEDEFAULTCURSORS
}

// A drag of these representations from this program, blocking until it ends;
// the caller starts it from a pointer-down of its own, since the drop is where
// the button goes up. `allow_move` offers a move beside the copy, and the
// answer says which the receiver took.
fn drag_start(a: *mem.Arena, items: []const Content, allow_move: bool) -> (DragResult, err) {
    if items.len == 0usize || items.len > MAX_DRAG_ITEMS { ret (.Cancelled, Invalid) }
    var at = 0usize
    while at < items.len {
        if items[at].kind == .Bytes && items[at].mime.len == 0usize { ret (.Cancelled, Invalid) }
        if items[at].kind == .Promise && items[at].text.len == 0usize { ret (.Cancelled, Invalid) }
        at += 1usize
    }
    let ole_error = ensure_ole()
    if ole_error != ok { ret (.Cancelled, ole_error) }
    let promise_error = ensure_promise_formats(a)
    if promise_error != ok { ret (.Cancelled, promise_error) }
    drag_format_count = 0usize
    var promised = false
    at = 0usize
    while at < items.len {
        if items[at].kind == .Promise {
            promised = true
        } else {
            let (format, format_error) = format_of(a, items[at].kind, items[at].mime)
            if format_error != ok { ret (.Cancelled, format_error) }
            var described: FormatEtc = zero
            described.format = u16(format)
            described.aspect = DVASPECT_CONTENT
            described.index = 0i32 - 1i32
            described.tymed = TYMED_HGLOBAL
            drag_formats[drag_format_count] = described
            drag_format_count += 1usize
        }
        at += 1usize
    }
    if promised {
        var descriptor: FormatEtc = zero
        descriptor.format = u16(descriptor_format)
        descriptor.aspect = DVASPECT_CONTENT
        descriptor.index = 0i32 - 1i32
        descriptor.tymed = TYMED_HGLOBAL
        drag_formats[drag_format_count] = descriptor
        drag_format_count += 1usize
        var contents: FormatEtc = zero
        contents.format = u16(contents_format)
        contents.aspect = DVASPECT_CONTENT
        contents.index = 0i32 - 1i32
        contents.tymed = TYMED_HGLOBAL
        drag_formats[drag_format_count] = contents
        drag_format_count += 1usize
    }
    drag_items = items
    drag_arena = a
    data_tables[0usize].slots[0usize] = slot_of_query(data_query_interface)
    data_tables[0usize].slots[1usize] = slot_of_this(com_add_ref)
    data_tables[0usize].slots[2usize] = slot_of_this(com_release_static)
    var getter: GetDataFn = zero
    getter.function = data_get_data
    data_tables[0usize].slots[3usize] = getter.bits
    var here: GetDataFn = zero
    here.function = data_get_data_here
    data_tables[0usize].slots[4usize] = here.bits
    var query: QueryDataFn = zero
    query.function = data_query_get_data
    data_tables[0usize].slots[5usize] = query.bits
    var canonical: CanonicalFn = zero
    canonical.function = data_canonical
    data_tables[0usize].slots[6usize] = canonical.bits
    var setter: SetDataFn = zero
    setter.function = data_set_data
    data_tables[0usize].slots[7usize] = setter.bits
    var enumerator: EnumFn = zero
    enumerator.function = data_enum_format
    data_tables[0usize].slots[8usize] = enumerator.bits
    var advise: AdviseFn = zero
    advise.function = data_advise
    data_tables[0usize].slots[9usize] = advise.bits
    var unadvise: UnadviseFn = zero
    unadvise.function = data_unadvise
    data_tables[0usize].slots[10usize] = unadvise.bits
    var enum_advise: EnumAdviseFn = zero
    enum_advise.function = data_enum_advise
    data_tables[0usize].slots[11usize] = enum_advise.bits
    data_objects[0usize].vtable = &data_tables[0usize]
    source_tables[0usize].slots[0usize] = slot_of_query(source_query_interface)
    source_tables[0usize].slots[1usize] = slot_of_this(com_add_ref)
    source_tables[0usize].slots[2usize] = slot_of_this(com_release_static)
    var continuing: ContinueFn = zero
    continuing.function = source_continue
    source_tables[0usize].slots[3usize] = continuing.bits
    var feedback: FeedbackFn = zero
    feedback.function = source_feedback
    source_tables[0usize].slots[4usize] = feedback.bits
    source_objects[0usize].vtable = &source_tables[0usize]
    var allowed = DROPEFFECT_COPY
    if allow_move { allowed = allowed | DROPEFFECT_MOVE }
    var effect = 0u32
    let result = raw_do_drag_drop(&data_objects[0usize], &source_objects[0usize], allowed, &effect)
    var no_items: []const Content = zero
    var no_arena: *mem.Arena = zero
    drag_items = no_items
    drag_arena = no_arena
    drag_format_count = 0usize
    if result == DRAGDROP_S_DROP {
        if (effect & DROPEFFECT_MOVE) != 0u32 { ret (.Moved, ok) }
        if (effect & DROPEFFECT_COPY) != 0u32 { ret (.Copied, ok) }
        ret (.Cancelled, ok)
    }
    if result == DRAGDROP_S_CANCEL { ret (.Cancelled, ok) }
    ret (.Cancelled, Failed)
}

// ------------------------------------------------------ file dialogs and recents
//
// D894, the widget plan's `native-file-access-api`. A file dialog is the shell's
// `IFileOpenDialog` or `IFileSaveDialog`, reached by slot like the taskbar: the
// options set for the kind, the filters as `COMDLG_FILTERSPEC` pairs, the dialog
// shown modally over the caller's window (or none), and the result read as file
// system paths through `IShellItem`. A cancel is `Cancelled`, not a failure. A
// recent document is `SHAddToRecentDocs`, which feeds the Start menu and the
// jump list's recent category.

type FilterSpec = struct { label: *const u16, pattern: *const u16 }
type Count = struct { value: u32 }
type WidePointer = struct { value: *const u16 }

@cc(c)
type ComShow = extern fn(usize, usize) -> i32
@cc(c)
type ComSetFilters = extern fn(usize, u32, *const FilterSpec) -> i32
@cc(c)
type ComSetOptions = extern fn(usize, u32) -> i32
@cc(c)
type ComGetOptions = extern fn(usize, *Count) -> i32
@cc(c)
type ComGetObject = extern fn(usize, **ComObject) -> i32
@cc(c)
type ComDisplayName = extern fn(usize, u32, *WidePointer) -> i32
@cc(c)
type ComItemAt = extern fn(usize, u32, **ComObject) -> i32
type ShowPun = union { function: ComShow, bits: usize }
type SetFiltersPun = union { function: ComSetFilters, bits: usize }
type SetOptionsPun = union { function: ComSetOptions, bits: usize }
type GetOptionsPun = union { function: ComGetOptions, bits: usize }
type GetObjectPun = union { function: ComGetObject, bits: usize }
type DisplayNamePun = union { function: ComDisplayName, bits: usize }
type ItemAtPun = union { function: ComItemAt, bits: usize }

const DIALOG_SHOW: usize = 3usize
const DIALOG_SET_FILE_TYPES: usize = 4usize
const DIALOG_SET_OPTIONS: usize = 9usize
const DIALOG_GET_OPTIONS: usize = 10usize
const DIALOG_SET_FILE_NAME: usize = 15usize
const DIALOG_SET_TITLE: usize = 17usize
const DIALOG_GET_RESULT: usize = 20usize
const DIALOG_SET_DEFAULT_EXTENSION: usize = 22usize
const DIALOG_GET_RESULTS: usize = 27usize
const ITEM_DISPLAY_NAME: usize = 5usize
const ARRAY_GET_COUNT: usize = 7usize
const ARRAY_GET_ITEM_AT: usize = 8usize
const SIGDN_FILESYSPATH: u32 = 2147844096u32
const FOS_OVERWRITEPROMPT: u32 = 2u32
const FOS_PICKFOLDERS: u32 = 32u32
const FOS_FORCEFILESYSTEM: u32 = 64u32
const FOS_ALLOWMULTISELECT: u32 = 512u32
const FOS_PATHMUSTEXIST: u32 = 2048u32
const FOS_FILEMUSTEXIST: u32 = 4096u32
const ERROR_CANCELLED_HRESULT: u32 = 2147943623u32
const SHARD_PATHW: u32 = 3u32
const MAX_DIALOG_FILTERS: usize = 16usize

@import("ole32.dll", "CoTaskMemFree")
extern fn raw_co_task_free(block: usize)

@import("shell32.dll", "SHAddToRecentDocs")
extern fn raw_add_to_recent(flags: u32, data: *const u16)

fn call_get_object(object: *ComObject, slot: usize) -> (*ComObject, err) {
    var found: *ComObject = zero
    var pun: GetObjectPun = zero
    pun.bits = object.vtable.slots[slot]
    let result = pun.function(mem.address_of(object), &found)
    if result < 0i32 || mem.address_of(found) == 0usize { ret (found, Failed) }
    ret (found, ok)
}

// A shell item's file system path, copied into the arena; the shell's block freed.
fn item_path(a: *mem.Arena, item: *ComObject) -> (str, err) {
    var holder: WidePointer = zero
    var pun: DisplayNamePun = zero
    pun.bits = item.vtable.slots[ITEM_DISPLAY_NAME]
    if pun.function(mem.address_of(item), SIGDN_FILESYSPATH, &holder) < 0i32 || mem.address_of(holder.value) == 0usize { ret ("", Failed) }
    let count = usize(raw_wide_length(holder.value))
    var path = ""
    var path_error = ok
    if count != 0usize {
        let (bytes, bytes_error) = mem.alloc[u8](a, count * 3usize)
        if bytes_error != ok {
            path_error = bytes_error
        } else {
            os.touch(&bytes[0usize], count * 3usize)
            let converted = raw_narrow(CP_UTF8, 0u32, holder.value, i32(count), &bytes[0usize], i32(count * 3usize), 0usize, 0usize)
            if converted <= 0i32 { path_error = Failed } else { path = bytes[0usize..usize(converted)] }
        }
    }
    raw_co_task_free(mem.address_of(holder.value))
    ret (path, path_error)
}

// The dialog shown and its choice: one path, or every chosen path for a multiple
// open; `Cancelled` when the user closes it without one.
fn file_dialog(a: *mem.Arena, w: os.Window, dialog: FileDialog) -> ([]const str, err) {
    var nothing: []const str = zero
    if dialog.filters.len > MAX_DIALOG_FILTERS { ret (nothing, Invalid) }
    if dialog.kind != .Open && dialog.multiple { ret (nothing, Invalid) }
    var owner = 0usize
    if w.raw != 0usize {
        let (handle, handle_error) = window_handle(w)
        if handle_error != ok { ret (nothing, handle_error) }
        owner = handle
    }
    let window_error = ensure_window()
    if window_error != ok { ret (nothing, window_error) }
    var clsid: [16]u8 = zero
    var iid: [16]u8 = zero
    if dialog.kind == .Save {
        guid(clsid[..], 3233080051u32, 47649u16, 18291u16, 2377790302u32, 3376868235u32)
        guid(iid[..], 1123569974u32, 56190u16, 17308u16, 2247222279u32, 1561550792u32)
    } else {
        guid(clsid[..], 3692845724u32, 59530u16, 19934u16, 2778816760u32, 706785015u32)
        guid(iid[..], 3581702792u32, 54445u16, 18280u16, 3187842454u32, 2503137632u32)
    }
    let (object, create_error) = com_create(clsid[..], iid[..])
    if create_error != ok { ret (nothing, create_error) }
    var options: Count = zero
    var get_options: GetOptionsPun = zero
    get_options.bits = object.vtable.slots[DIALOG_GET_OPTIONS]
    let read_options = get_options.function(mem.address_of(object), &options)
    var flags = options.value | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST
    if dialog.kind == .Open { flags = flags | FOS_FILEMUSTEXIST }
    if dialog.kind == .Save { flags = flags | FOS_OVERWRITEPROMPT }
    if dialog.kind == .Folder { flags = flags | FOS_PICKFOLDERS }
    if dialog.multiple { flags = flags | FOS_ALLOWMULTISELECT }
    var set_options: SetOptionsPun = zero
    set_options.bits = object.vtable.slots[DIALOG_SET_OPTIONS]
    if set_options.function(mem.address_of(object), flags) < 0i32 {
        com_release(object)
        ret (nothing, Failed)
    }
    if dialog.title.len != 0usize {
        let (title, title_error) = widen(a, dialog.title)
        if title_error != ok {
            com_release(object)
            ret (nothing, title_error)
        }
        let titled = call_wide(object, DIALOG_SET_TITLE, &title[0usize])
    }
    if dialog.initial.len != 0usize {
        let (initial, initial_error) = widen(a, dialog.initial)
        if initial_error != ok {
            com_release(object)
            ret (nothing, initial_error)
        }
        let named = call_wide(object, DIALOG_SET_FILE_NAME, &initial[0usize])
    }
    if dialog.default_extension.len != 0usize {
        let (extension, extension_error) = widen(a, dialog.default_extension)
        if extension_error != ok {
            com_release(object)
            ret (nothing, extension_error)
        }
        let defaulted = call_wide(object, DIALOG_SET_DEFAULT_EXTENSION, &extension[0usize])
    }
    if dialog.filters.len != 0usize && dialog.kind != .Folder {
        var specs: [16]FilterSpec = zero
        var at = 0usize
        while at < dialog.filters.len {
            let (label, label_error) = widen(a, dialog.filters[at].label)
            let (pattern, pattern_error) = widen(a, dialog.filters[at].pattern)
            if label_error != ok || pattern_error != ok {
                com_release(object)
                ret (nothing, Invalid)
            }
            specs[at] = FilterSpec { label: &label[0usize], pattern: &pattern[0usize] }
            at += 1usize
        }
        var set_filters: SetFiltersPun = zero
        set_filters.bits = object.vtable.slots[DIALOG_SET_FILE_TYPES]
        if set_filters.function(mem.address_of(object), u32(dialog.filters.len), &specs[0usize]) < 0i32 {
            com_release(object)
            ret (nothing, Failed)
        }
    }
    var show: ShowPun = zero
    show.bits = object.vtable.slots[DIALOG_SHOW]
    let shown = show.function(mem.address_of(object), owner)
    if shown < 0i32 {
        com_release(object)
        if u32(mem.bitcast[u32](shown)) == ERROR_CANCELLED_HRESULT { ret (nothing, Cancelled) }
        ret (nothing, Failed)
    }
    if dialog.multiple {
        let (results, results_error) = call_get_object(object, DIALOG_GET_RESULTS)
        if results_error != ok {
            com_release(object)
            ret (nothing, Failed)
        }
        var count: Count = zero
        var get_count: GetOptionsPun = zero
        get_count.bits = results.vtable.slots[ARRAY_GET_COUNT]
        if get_count.function(mem.address_of(results), &count) < 0i32 {
            com_release(results)
            com_release(object)
            ret (nothing, Failed)
        }
        let (paths, allocation_error) = mem.alloc[str](a, usize(count.value))
        if allocation_error != ok {
            com_release(results)
            com_release(object)
            ret (nothing, allocation_error)
        }
        var index = 0u32
        var failure = ok
        while index < count.value && failure == ok {
            var item: *ComObject = zero
            var item_at: ItemAtPun = zero
            item_at.bits = results.vtable.slots[ARRAY_GET_ITEM_AT]
            if item_at.function(mem.address_of(results), index, &item) < 0i32 || mem.address_of(item) == 0usize {
                failure = Failed
            } else {
                let (path, path_error) = item_path(a, item)
                com_release(item)
                if path_error != ok { failure = path_error } else { paths[usize(index)] = path }
            }
            index += 1u32
        }
        com_release(results)
        com_release(object)
        if failure != ok { ret (nothing, failure) }
        ret (paths[0usize..usize(count.value)], ok)
    }
    let (item, item_error) = call_get_object(object, DIALOG_GET_RESULT)
    if item_error != ok {
        com_release(object)
        ret (nothing, Failed)
    }
    let (path, path_error) = item_path(a, item)
    com_release(item)
    com_release(object)
    if path_error != ok { ret (nothing, path_error) }
    let (paths, allocation_error) = mem.alloc[str](a, 1usize)
    if allocation_error != ok { ret (nothing, allocation_error) }
    paths[0usize] = path
    ret (paths[0usize..1usize], ok)
}

// The document into the shell's recent list; the item has to exist.
fn recent_add(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    let (info, stat_error) = os.stat(a, path)
    if stat_error == os.NotFound { ret NotFound }
    if stat_error != ok { ret Failed }
    let (wide, widen_error) = widen(a, path)
    if widen_error != ok { ret widen_error }
    raw_add_to_recent(SHARD_PATHW, &wide[0usize])
    ret ok
}
// The activation a command line means: the first argument a URL when it has a
// scheme before a colon and no separator, a file when it names one that exists,
// a plain launch otherwise.
fn activation_of(a: *mem.Arena, args: []const str) -> Activation {
    var activation: Activation = zero
    activation.kind = .Launch
    activation.args = args
    if args.len < 2usize { ret activation }
    let first = args[1usize]
    if first.len == 0usize { ret activation }
    var at = 0usize
    var scheme = false
    while at < first.len {
        let c = first[at]
        if c == 58u8 {
            scheme = at > 1usize && at + 1usize < first.len
            break
        }
        let letter = (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || (c >= 48u8 && c <= 57u8) || c == 43u8 || c == 45u8 || c == 46u8
        if !letter { break }
        at += 1usize
    }
    if scheme {
        activation.kind = .Url
        activation.payload = first
        ret activation
    }
    let (info, stat_error) = os.stat(a, first)
    if stat_error == ok {
        activation.kind = .File
        activation.payload = first
    }
    ret activation
}

// ----------------------------------------------- associations and activation
//
// D896, the widget plan's `native-activation-api`. A file or protocol
// association is the per-user registry under `HKEY_CURRENT_USER\Software\Classes`
// -- an extension naming a program id, the program id's open command naming this
// executable with `%1`, a scheme marked `URL Protocol` the same way -- which
// needs no elevation and is what the shell reads. Startup registration is the
// `Run` key's value under the id. A single instance is a named mutex: the first
// holder titles the hidden window with the id and receives later instances'
// arguments as `WM_COPYDATA`, which `activation_poll` answers; a later instance
// finds that window, hands its arguments over and is told it is not the first.

type CopyData = struct { data: usize, length: u32, padding: u32, address: usize }
type KeyHandle = struct { value: usize }
type ValueSize = struct { value: u32 }

const HKEY_CURRENT_USER: usize = 2147483649usize
const KEY_WRITE_READ: u32 = 131103u32
const REG_SZ: u32 = 1u32
const ERROR_ALREADY_EXISTS: u32 = 183u32
const ERROR_FILE_NOT_FOUND_STATUS: i32 = 2i32
const ACTIVATION_RING: usize = 8usize

var instance_mutex: usize = 0usize
var instance_storage: *mem.Arena = zero
var activations: [8]Activation = zero
var activation_head: usize = 0usize
var activation_count: usize = 0usize

@import("advapi32.dll", "RegCreateKeyExW")
extern fn raw_reg_create(root: usize, subkey: *const u16, reserved: u32, class: usize, options: u32, access: u32, security: usize, out: *KeyHandle, disposition: usize) -> i32

@import("advapi32.dll", "RegOpenKeyExW")
extern fn raw_reg_open(root: usize, subkey: *const u16, options: u32, access: u32, out: *KeyHandle) -> i32

@import("advapi32.dll", "RegSetValueExW")
extern fn raw_reg_set_value(key: usize, name: usize, reserved: u32, kind: u32, data: *const u8, length: u32) -> i32

@import("advapi32.dll", "RegQueryValueExW")
extern fn raw_reg_query_value(key: usize, name: *const u16, reserved: usize, kind: usize, data: usize, length: *ValueSize) -> i32

@import("advapi32.dll", "RegDeleteValueW")
extern fn raw_reg_delete_value(key: usize, name: *const u16) -> i32

@import("advapi32.dll", "RegDeleteTreeW")
extern fn raw_reg_delete_tree(root: usize, subkey: *const u16) -> i32

@import("advapi32.dll", "RegCloseKey")
extern fn raw_reg_close(key: usize) -> i32

@import("kernel32.dll", "CreateMutexW")
extern fn raw_create_mutex(security: usize, initial: i32, name: *const u16) -> usize

@import("kernel32.dll", "GetLastError")
extern fn raw_last_error() -> u32

@import("kernel32.dll", "GetModuleFileNameW")
extern fn raw_module_file_name(module: usize, out: *u16, capacity: u32) -> u32

@import("user32.dll", "FindWindowW")
extern fn raw_find_window(class_name: *const u16, title: *const u16) -> usize

@import("user32.dll", "SetWindowTextW")
extern fn raw_set_window_text(window: usize, text: *const u16) -> i32

@import("user32.dll", "SendMessageW")
extern fn raw_send_message(window: usize, message: u32, wparam: usize, lparam: isize) -> isize

fn concat_text(a: *mem.Arena, parts: []const str) -> (str, err) {
    var total = 0usize
    var at = 0usize
    while at < parts.len {
        total += parts[at].len
        at += 1usize
    }
    let (bytes, allocation_error) = mem.alloc[u8](a, total)
    if allocation_error != ok { ret ("", allocation_error) }
    var written = 0usize
    at = 0usize
    while at < parts.len {
        var i = 0usize
        while i < parts[at].len {
            bytes[written] = parts[at][i]
            written += 1usize
            i += 1usize
        }
        at += 1usize
    }
    ret (bytes[0usize..total], ok)
}

// This executable's path, for the open command and the startup value.
fn executable_wide(a: *mem.Arena) -> ([]u16, err) {
    var nothing: []u16 = zero
    let (units, allocation_error) = mem.alloc[u16](a, 32768usize)
    if allocation_error != ok { ret (nothing, allocation_error) }
    os.touch(mem.cast[*const u8](&units[0usize]), 65536usize)
    let count = raw_module_file_name(0usize, &units[0usize], 32767u32)
    if count == 0u32 { ret (nothing, Failed) }
    units[usize(count)] = 0u16
    ret (units[0usize..usize(count) + 1usize], ok)
}

fn executable_text(a: *mem.Arena) -> (str, err) {
    let (units, wide_error) = executable_wide(a)
    if wide_error != ok { ret ("", wide_error) }
    let count = units.len - 1usize
    let (bytes, bytes_error) = mem.alloc[u8](a, count * 3usize + 1usize)
    if bytes_error != ok { ret ("", bytes_error) }
    os.touch(&bytes[0usize], count * 3usize + 1usize)
    let converted = raw_narrow(CP_UTF8, 0u32, &units[0usize], i32(count), &bytes[0usize], i32(count * 3usize), 0usize, 0usize)
    if converted <= 0i32 { ret ("", Failed) }
    ret (bytes[0usize..usize(converted)], ok)
}

// A string value under a key of the current user, the key created on the way.
fn set_user_value(a: *mem.Arena, subkey: str, name: str, value: str) -> err {
    let (subkey_wide, subkey_error) = widen(a, subkey)
    if subkey_error != ok { ret subkey_error }
    var key: KeyHandle = zero
    if raw_reg_create(HKEY_CURRENT_USER, &subkey_wide[0usize], 0u32, 0usize, 0u32, KEY_WRITE_READ, 0usize, &key, 0usize) != 0i32 { ret Failed }
    let (value_wide, value_error) = widen(a, value)
    if value_error != ok {
        let closed = raw_reg_close(key.value)
        ret value_error
    }
    var count = 0usize
    while value_wide[count] != 0u16 { count += 1usize }
    var name_address = 0usize
    var name_wide: []u16 = zero
    if name.len != 0usize {
        let (named, name_error) = widen(a, name)
        if name_error != ok {
            let closed = raw_reg_close(key.value)
            ret name_error
        }
        name_wide = named
        name_address = mem.address_of(&name_wide[0usize])
    }
    let set = raw_reg_set_value(key.value, name_address, 0u32, REG_SZ, mem.cast[*const u8](&value_wide[0usize]), u32((count + 1usize) * 2usize))
    let closed = raw_reg_close(key.value)
    if set != 0i32 { ret Failed }
    ret ok
}

fn valid_name(text: str) -> bool {
    if text.len == 0usize { ret false }
    var at = 0usize
    while at < text.len {
        let c = text[at]
        if c == 92u8 || c == 47u8 || c == 34u8 || c < 32u8 { ret false }
        at += 1usize
    }
    ret true
}

// The program id's open command over this executable, and its description.
fn register_program(a: *mem.Arena, program_id: str, description: str) -> err {
    let (exe, exe_error) = executable_text(a)
    if exe_error != ok { ret exe_error }
    var command_parts: [3]str = zero
    command_parts[0usize] = "\""
    command_parts[1usize] = exe
    command_parts[2usize] = "\" \"%1\""
    let (command, command_error) = concat_text(a, command_parts[..])
    if command_error != ok { ret command_error }
    var key_parts: [2]str = zero
    key_parts[0usize] = "Software\\Classes\\"
    key_parts[1usize] = program_id
    let (program_key, program_key_error) = concat_text(a, key_parts[..])
    if program_key_error != ok { ret program_key_error }
    try set_user_value(a, program_key, "", description)
    var command_key_parts: [2]str = zero
    command_key_parts[0usize] = program_key
    command_key_parts[1usize] = "\\shell\\open\\command"
    let (command_key, command_key_error) = concat_text(a, command_key_parts[..])
    if command_key_error != ok { ret command_key_error }
    ret set_user_value(a, command_key, "", command)
}

fn delete_user_tree(a: *mem.Arena, subkey: str) -> err {
    let (subkey_wide, subkey_error) = widen(a, subkey)
    if subkey_error != ok { ret subkey_error }
    let deleted = raw_reg_delete_tree(HKEY_CURRENT_USER, &subkey_wide[0usize])
    if deleted == ERROR_FILE_NOT_FOUND_STATUS { ret NotFound }
    if deleted != 0i32 { ret Failed }
    ret ok
}

// `.ext` opens with this executable under `program_id`, for this user.
fn associate_file(a: *mem.Arena, extension: str, program_id: str, description: str) -> err {
    if extension.len < 2usize || extension[0usize] != 46u8 || !valid_name(extension) || !valid_name(program_id) { ret Invalid }
    try register_program(a, program_id, description)
    var key_parts: [2]str = zero
    key_parts[0usize] = "Software\\Classes\\"
    key_parts[1usize] = extension
    let (extension_key, key_error) = concat_text(a, key_parts[..])
    if key_error != ok { ret key_error }
    ret set_user_value(a, extension_key, "", program_id)
}

fn dissociate_file(a: *mem.Arena, extension: str, program_id: str) -> err {
    if extension.len < 2usize || extension[0usize] != 46u8 || !valid_name(extension) || !valid_name(program_id) { ret Invalid }
    var key_parts: [2]str = zero
    key_parts[0usize] = "Software\\Classes\\"
    key_parts[1usize] = extension
    let (extension_key, key_error) = concat_text(a, key_parts[..])
    if key_error != ok { ret key_error }
    let extension_gone = delete_user_tree(a, extension_key)
    key_parts[1usize] = program_id
    let (program_key, program_key_error) = concat_text(a, key_parts[..])
    if program_key_error != ok { ret program_key_error }
    let program_gone = delete_user_tree(a, program_key)
    if extension_gone == NotFound && program_gone == NotFound { ret NotFound }
    if extension_gone != ok && extension_gone != NotFound { ret extension_gone }
    if program_gone != ok && program_gone != NotFound { ret program_gone }
    ret ok
}

// `scheme:` URLs open with this executable, for this user.
fn associate_protocol(a: *mem.Arena, scheme: str, description: str) -> err {
    if !valid_name(scheme) || scheme.len > 64usize { ret Invalid }
    try register_program(a, scheme, description)
    var key_parts: [2]str = zero
    key_parts[0usize] = "Software\\Classes\\"
    key_parts[1usize] = scheme
    let (scheme_key, key_error) = concat_text(a, key_parts[..])
    if key_error != ok { ret key_error }
    ret set_user_value(a, scheme_key, "URL Protocol", "")
}

fn dissociate_protocol(a: *mem.Arena, scheme: str) -> err {
    if !valid_name(scheme) || scheme.len > 64usize { ret Invalid }
    var key_parts: [2]str = zero
    key_parts[0usize] = "Software\\Classes\\"
    key_parts[1usize] = scheme
    let (scheme_key, key_error) = concat_text(a, key_parts[..])
    if key_error != ok { ret key_error }
    ret delete_user_tree(a, scheme_key)
}

fn run_key() -> str {
    ret "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
}

// This executable started at the user's login under `id`, or not.
fn startup_set(a: *mem.Arena, id: str, enabled: bool) -> err {
    if !valid_name(id) { ret Invalid }
    if enabled {
        let (exe, exe_error) = executable_text(a)
        if exe_error != ok { ret exe_error }
        var parts: [3]str = zero
        parts[0usize] = "\""
        parts[1usize] = exe
        parts[2usize] = "\""
        let (quoted, quote_error) = concat_text(a, parts[..])
        if quote_error != ok { ret quote_error }
        ret set_user_value(a, run_key(), id, quoted)
    }
    let (run_wide, run_error) = widen(a, run_key())
    if run_error != ok { ret run_error }
    let (name_wide, name_error) = widen(a, id)
    if name_error != ok { ret name_error }
    var key: KeyHandle = zero
    if raw_reg_open(HKEY_CURRENT_USER, &run_wide[0usize], 0u32, KEY_WRITE_READ, &key) != 0i32 { ret Failed }
    let deleted = raw_reg_delete_value(key.value, &name_wide[0usize])
    let closed = raw_reg_close(key.value)
    if deleted == ERROR_FILE_NOT_FOUND_STATUS { ret ok }
    if deleted != 0i32 { ret Failed }
    ret ok
}

fn startup_enabled(a: *mem.Arena, id: str) -> (bool, err) {
    if !valid_name(id) { ret (false, Invalid) }
    let (run_wide, run_error) = widen(a, run_key())
    if run_error != ok { ret (false, run_error) }
    let (name_wide, name_error) = widen(a, id)
    if name_error != ok { ret (false, name_error) }
    var key: KeyHandle = zero
    if raw_reg_open(HKEY_CURRENT_USER, &run_wide[0usize], 0u32, KEY_WRITE_READ, &key) != 0i32 { ret (false, Failed) }
    var size: ValueSize = zero
    let queried = raw_reg_query_value(key.value, &name_wide[0usize], 0usize, 0usize, 0usize, &size)
    let closed = raw_reg_close(key.value)
    if queried == ERROR_FILE_NOT_FOUND_STATUS { ret (false, ok) }
    if queried != 0i32 { ret (false, Failed) }
    ret (true, ok)
}
// A redirected activation's arguments, newline-separated, copied into the
// first instance's storage and queued as the activation they mean.
type CopyDataPun = union { pointer: *const CopyData, bits: usize }
type BytesPun = union { pointer: *u8, bits: usize }

fn receive_activation(lparam: isize) -> isize {
    if mem.address_of(instance_storage) == 0usize || activation_count == ACTIVATION_RING { ret 0isize }
    var pun: CopyDataPun = zero
    pun.bits = usize(lparam)
    let length = usize(pun.pointer.length)
    if length == 0usize || length > 65536usize { ret 0isize }
    var bytes_pun: BytesPun = zero
    bytes_pun.bits = pun.pointer.address
    var region: mem.Arena = zero
    region.base = bytes_pun.pointer
    region.cap = length
    region.off = 0usize
    let incoming = mem.view(&region, 0usize, length)
    let (copy, allocation_error) = mem.alloc[u8](instance_storage, length)
    if allocation_error != ok { ret 0isize }
    mem.copy[u8](copy, incoming)
    // The arguments back out of the newline-separated text.
    var count = 1usize
    var at = 0usize
    while at < length {
        if copy[at] == 10u8 { count += 1usize }
        at += 1usize
    }
    let (args, args_error) = mem.alloc[str](instance_storage, count)
    if args_error != ok { ret 0isize }
    var start = 0usize
    var index = 0usize
    at = 0usize
    while at <= length {
        if at == length || copy[at] == 10u8 {
            args[index] = copy[start..at]
            index += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    activations[(activation_head + activation_count) % ACTIVATION_RING] = activation_of(instance_storage, args[0usize..count])
    activation_count += 1usize
    ret 1isize
}

// The first instance under `id` keeps the mutex and titles the hidden window
// with the id; a later one finds that window, hands its arguments over and
// answers false so that it can exit.
fn single_instance(a: *mem.Arena, id: str, args: []const str, storage: *mem.Arena) -> (bool, err) {
    if !valid_name(id) { ret (false, Invalid) }
    if instance_mutex != 0usize { ret (true, ok) }
    // The hidden window first, in both instances: the class name it registers
    // is what a later instance searches by.
    let window_error = ensure_window()
    if window_error != ok { ret (false, window_error) }
    var name_parts: [2]str = zero
    name_parts[0usize] = "Local\neper.instance."
    name_parts[1usize] = id
    let (mutex_name, name_error) = concat_text(a, name_parts[..])
    if name_error != ok { ret (false, name_error) }
    let (mutex_wide, mutex_wide_error) = widen(a, mutex_name)
    if mutex_wide_error != ok { ret (false, mutex_wide_error) }
    let mutex = raw_create_mutex(0usize, 0i32, &mutex_wide[0usize])
    if mutex == 0usize { ret (false, Failed) }
    let already = raw_last_error() == ERROR_ALREADY_EXISTS
    let (title, title_error) = widen(a, id)
    if title_error != ok { ret (false, title_error) }
    if !already {
        let titled = raw_set_window_text(shell_window, &title[0usize])
        instance_mutex = mutex
        instance_storage = storage
        ret (true, ok)
    }
    // Not the first: the arguments to the first, newline-separated.
    let primary = raw_find_window(&shell_class_name[0usize], &title[0usize])
    if primary == 0usize { ret (false, NotFound) }
    var total = 0usize
    var at = 0usize
    while at < args.len {
        total += args[at].len + 1usize
        at += 1usize
    }
    if total == 0usize { total = 1usize }
    let (payload, allocation_error) = mem.alloc[u8](a, total)
    if allocation_error != ok { ret (false, allocation_error) }
    var written = 0usize
    at = 0usize
    while at < args.len {
        var i = 0usize
        while i < args[at].len {
            payload[written] = args[at][i]
            written += 1usize
            i += 1usize
        }
        if at + 1usize < args.len {
            payload[written] = 10u8
            written += 1usize
        }
        at += 1usize
    }
    var copy: CopyData = zero
    copy.length = u32(written)
    copy.address = mem.address_of(&payload[0usize])
    let delivered = raw_send_message(primary, WM_COPYDATA, shell_window, isize(mem.address_of(&copy)))
    ret (false, ok)
}

// Pumps the hidden window and answers the oldest redirected activation.
fn activation_poll() -> (Activation, bool) {
    var none: Activation = zero
    if shell_window != 0usize {
        var message: ShellMessage = zero
        while raw_peek_message(&message, shell_window, 0u32, 0u32, PM_REMOVE) != 0i32 {
            let translated = raw_translate_message(&message)
            let dispatched = raw_dispatch_message(&message)
        }
    }
    if activation_count == 0usize { ret (none, false) }
    let activation = activations[activation_head]
    activation_head = (activation_head + 1usize) % ACTIVATION_RING
    activation_count -= 1usize
    ret (activation, true)
}
// ------------------------------------------------- lifecycle and global input
//
// D898, the widget plan's `native-lifecycle-api` with the shell half of P4-10.
// A global shortcut is `RegisterHotKey` on the hidden window, whose `WM_HOTKEY`
// becomes the id in a ring `hotkey_poll` drains; the session's shutdown and the
// system's suspend and resume arrive at the same window as `WM_QUERYENDSESSION`
// and `WM_POWERBROADCAST` and become lifecycle events; background work needs no
// permission on this host; power inhibition is the thread's execution state;
// a restart after a crash or an update is `RegisterApplicationRestart` with
// the arguments the restarted program should see.

const WM_HOTKEY: u32 = 786u32
const WM_QUERYENDSESSION: u32 = 17u32
const WM_ENDSESSION: u32 = 22u32
const WM_POWERBROADCAST: u32 = 536u32
const PBT_APMSUSPEND: usize = 4usize
const PBT_APMRESUMEAUTOMATIC: usize = 18usize
const MOD_ALT: u32 = 1u32
const MOD_CONTROL: u32 = 2u32
const MOD_SHIFT: u32 = 4u32
const MOD_WIN: u32 = 8u32
const MOD_NOREPEAT: u32 = 16384u32
const ES_CONTINUOUS: u32 = 2147483648u32
const ES_SYSTEM_REQUIRED: u32 = 1u32
const ES_DISPLAY_REQUIRED: u32 = 2u32
const HOTKEY_RING: usize = 32usize
const LIFECYCLE_RING: usize = 8usize

var hotkeys_pressed: [32]u32 = zero
var hotkey_head: usize = 0usize
var hotkey_count: usize = 0usize
var lifecycle_events: [8]LifecycleEvent = zero
var lifecycle_head: usize = 0usize
var lifecycle_count: usize = 0usize
var inhibiting: bool = zero

@import("user32.dll", "RegisterHotKey")
extern fn raw_register_hotkey(window: usize, id: i32, modifiers: u32, key: u32) -> i32

@import("user32.dll", "UnregisterHotKey")
extern fn raw_unregister_hotkey(window: usize, id: i32) -> i32

@import("kernel32.dll", "SetThreadExecutionState")
extern fn raw_set_execution_state(flags: u32) -> u32

@import("kernel32.dll", "RegisterApplicationRestart")
extern fn raw_register_restart(command_line: *const u16, flags: u32) -> i32

@import("kernel32.dll", "UnregisterApplicationRestart")
extern fn raw_unregister_restart() -> i32

// The hidden window's share of the session: a hotkey to its ring, a shutdown or
// a power change to the lifecycle ring, and consent to the session ending.
fn session_message(message: u32, wparam: usize) -> (bool, isize) {
    if message == WM_HOTKEY {
        if hotkey_count < HOTKEY_RING {
            hotkeys_pressed[(hotkey_head + hotkey_count) % HOTKEY_RING] = u32(wparam & 4294967295usize)
            hotkey_count += 1usize
        }
        ret (true, 0isize)
    }
    if message == WM_QUERYENDSESSION || (message == WM_ENDSESSION && wparam != 0usize) {
        push_lifecycle(.Shutdown)
        ret (true, 1isize)
    }
    if message == WM_POWERBROADCAST {
        if wparam == PBT_APMSUSPEND { push_lifecycle(.Suspend) }
        if wparam == PBT_APMRESUMEAUTOMATIC { push_lifecycle(.Resume) }
        ret (true, 1isize)
    }
    ret (false, 0isize)
}

fn push_lifecycle(event: LifecycleEvent) {
    if lifecycle_count == LIFECYCLE_RING { ret }
    lifecycle_events[(lifecycle_head + lifecycle_count) % LIFECYCLE_RING] = event
    lifecycle_count += 1usize
}

fn pump_hidden() {
    if shell_window == 0usize { ret }
    var message: ShellMessage = zero
    while raw_peek_message(&message, shell_window, 0u32, 0u32, PM_REMOVE) != 0i32 {
        let translated = raw_translate_message(&message)
        let dispatched = raw_dispatch_message(&message)
    }
}

// A shortcut the whole desktop answers with this id; `Failed` when another
// program holds the combination.
fn hotkey_register(a: *mem.Arena, id: u32, key: Hotkey) -> err {
    if id == 0u32 || id > 49151u32 || key.key == 0u32 { ret Invalid }
    try ensure_window()
    var modifiers = MOD_NOREPEAT
    if key.control { modifiers = modifiers | MOD_CONTROL }
    if key.alt { modifiers = modifiers | MOD_ALT }
    if key.shift { modifiers = modifiers | MOD_SHIFT }
    if key.super { modifiers = modifiers | MOD_WIN }
    if raw_register_hotkey(shell_window, i32(id), modifiers, key.key) == 0i32 { ret Failed }
    ret ok
}

fn hotkey_unregister(a: *mem.Arena, id: u32) -> err {
    if id == 0u32 || id > 49151u32 { ret Invalid }
    if shell_window == 0usize { ret NotFound }
    if raw_unregister_hotkey(shell_window, i32(id)) == 0i32 { ret NotFound }
    ret ok
}

fn hotkey_poll() -> (u32, bool) {
    pump_hidden()
    if hotkey_count == 0usize { ret (0u32, false) }
    let id = hotkeys_pressed[hotkey_head]
    hotkey_head = (hotkey_head + 1usize) % HOTKEY_RING
    hotkey_count -= 1usize
    ret (id, true)
}

fn background_permission(a: *mem.Arena) -> Permission {
    ret .Granted
}

// The system, and the display when asked, kept awake until released.
fn power_inhibit(a: *mem.Arena, keep_display: bool) -> err {
    var flags = ES_CONTINUOUS | ES_SYSTEM_REQUIRED
    if keep_display { flags = flags | ES_DISPLAY_REQUIRED }
    if raw_set_execution_state(flags) == 0u32 { ret Failed }
    inhibiting = true
    ret ok
}

fn power_release(a: *mem.Arena) -> err {
    if !inhibiting { ret NotFound }
    let previous = raw_set_execution_state(ES_CONTINUOUS)
    inhibiting = false
    ret ok
}

fn lifecycle_poll() -> (LifecycleEvent, bool) {
    pump_hidden()
    if lifecycle_count == 0usize { ret (.Resume, false) }
    let event = lifecycle_events[lifecycle_head]
    lifecycle_head = (lifecycle_head + 1usize) % LIFECYCLE_RING
    lifecycle_count -= 1usize
    ret (event, true)
}

// After a crash, a hang or an update's restart, this program again with these
// arguments; at most 1024 characters, none of them a restart of the restart.
fn restart_register(a: *mem.Arena, arguments: str) -> err {
    if arguments.len > 1024usize { ret Invalid }
    let (wide, widen_error) = widen(a, arguments)
    if widen_error != ok { ret widen_error }
    if raw_register_restart(&wide[0usize], 0u32) < 0i32 { ret Failed }
    ret ok
}

fn restart_unregister(a: *mem.Arena) -> err {
    if raw_unregister_restart() < 0i32 { ret Failed }
    ret ok
}
