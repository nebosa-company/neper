// `e.os.shell` on macOS (D5203): the host's shell services through the tools every Mac has --
// `open` for a URL (and `open -R` for a reveal that selects the item in Finder), `osascript` for
// a notice, `security` for the Keychain, `caffeinate` for keeping the Mac awake -- and through
// AppKit, reached as `e.os` reaches it (`os.msg0` and the rest of the Objective-C bridge in
// `os.macos.e`), where a tool does not give the answer: the trash, the clipboard's typed
// contents, the file dialogs, the recent documents. The shape and every argument check are
// `shell.linux.e`'s, so a host's refusal and a caller's mistake stay different errors. What no
// tool or call here gives is `Unsupported` and the capability record says so. The type block is
// a copy of `shell.windows.e`'s.

use e.fs
use e.mem
use e.os
use e.str
use e.time

error Unsupported
error Invalid
error NotFound
error Failed
error Cancelled

type Capabilities = struct { tray: bool, popup_menu: bool, open_uri: bool, reveal: bool, trash: bool, taskbar: bool, jump_list: bool, notices: bool, notice_actions: bool, notice_remove: bool, clipboard_text: bool, clipboard_typed: bool, drop_target: bool, drag_source: bool, file_dialogs: bool, recent_documents: bool, associations: bool, startup: bool, single_instance: bool, hotkeys: bool, power_inhibit: bool, lifecycle_events: bool, restart: bool, printing: bool, print_dialogs: bool, permissions: bool, credentials: bool, screen_capture: bool, biometrics: bool, photo_picker: bool }
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
type FileDialog = struct { kind: DialogKind, title: str, filters: []const FileFilter, multiple: bool, initial: str, default_extension: str, folder: str }
// How the program was activated: plainly, with a file, or with a URL; a
// redirected activation is another instance's arguments handed to the first.
type ActivationKind = enum u8 { Launch, File, Url }
type Activation = struct { kind: ActivationKind, payload: str, args: []const str }
// A global shortcut: the modifiers and the host's key code; a permission the
// host answers for background work; the lifecycle events a session sends.
type Hotkey = struct { control: bool, alt: bool, shift: bool, super: bool, key: u32 }
type Permission = enum u8 { Granted, Denied, Unavailable }
type LifecycleEvent = enum u8 { Shutdown, Suspend, Resume }
// A printer opened for a job, the page a printer draws in device pixels, a
// page setup in hundredths of a millimetre, and a job in progress.
type Printer = struct { device: usize, from_page: u32, to_page: u32, copies: u32 }
type PrintPage = struct { width: u32, height: u32, dpi_x: u32, dpi_y: u32 }
type PageSetup = struct { paper_width: u32, paper_height: u32, margin_left: u32, margin_top: u32, margin_right: u32, margin_bottom: u32 }
type PrintJob = struct { device: usize, id: i32, pages: u32, open: bool }
// A protected capability the host gates, and a secret kept by the host's store.
type Capability = enum u8 { Camera, Microphone, Location, Screen, Biometric, Photos }
type Credential = struct { user: str, secret: []const u8 }
type TrayEvent = struct { kind: TrayEventKind, id: u32, x: i32, y: i32 }
type MenuItem = struct { id: u32, label: str, enabled: bool, checked: bool, separator: bool }
type ProgressState = enum u8 { None, Indeterminate, Normal, Paused, Error }
type JumpTask = struct { title: str, program: str, arguments: str, description: str }

// The record; the tool-backed services are there when their tool is on the PATH.
fn has_tool(name: str) -> bool {
    var storage: [32768]u8 = zero
    var scratch = mem.arena_from(storage[..])
    let (tool, tool_error) = find_program(&scratch, name)
    ret tool_error == ok
}

fn capabilities() -> Capabilities {
    ret Capabilities { tray: true, popup_menu: true, open_uri: true, reveal: true, trash: true, taskbar: false, jump_list: false, notices: true, notice_actions: false, notice_remove: false, clipboard_text: true, clipboard_typed: true, drop_target: false, drag_source: false, file_dialogs: true, recent_documents: true, associations: false, startup: true, single_instance: false, hotkeys: false, power_inhibit: has_tool("caffeinate"), lifecycle_events: false, restart: false, printing: false, print_dialogs: false, permissions: false, credentials: false, screen_capture: true, biometrics: false, photo_picker: false }
}

// The tray and the pop-up menu (D5207). AppKit calls back through a target and an action, so a class of our own is made
// at run time (`NeperShellTarget`, a subclass of NSObject) with two methods whose implementations are `@cc(c)` functions
// of this file: one for a status item's button, one for a menu item. What they do is write into the state below, which
// `tray_poll` and `popup_menu` read once the run loop has delivered the click.
type MenuPoint = struct { x: f64, y: f64 }
type MenuImp = union { function: fn(usize, usize, usize), bits: usize }

@import("/usr/lib/libobjc.A.dylib", "objc_allocateClassPair")
extern fn objc_class_pair(superclass: usize, name: *const u8, extra: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "class_addMethod")
extern fn objc_class_method(class: usize, selector: usize, implementation: usize, types: *const u8) -> u8

@import("/usr/lib/libobjc.A.dylib", "objc_registerClassPair")
extern fn objc_class_register(class: usize)

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_image(receiver: usize, selector: usize, image: usize, size: MenuPoint) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_popup(receiver: usize, selector: usize, item: usize, at: MenuPoint, view: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_event_point(receiver: usize, selector: usize) -> MenuPoint

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGDisplayPixelsHigh")
extern fn cg_display_high(display: u32) -> usize

const TRAYS: usize = 8usize
const TRAY_QUEUE: usize = 16usize
var shell_target: usize = zero
var tray_ids: [8]u32 = zero
var tray_items: [8]usize = zero
var tray_buttons: [8]usize = zero
var tray_queue: [16]TrayEvent = zero
var tray_head: usize = zero
var tray_tail: usize = zero
var popup_choice: u32 = zero
var popup_made: bool = zero

fn tray_push(event: TrayEvent) {
    let next = (tray_tail + 1usize) % TRAY_QUEUE
    if next == tray_head { ret }
    tray_queue[tray_tail] = event
    tray_tail = next
}

// A status item's button was clicked: left is a Select, right a Context, at the pointer's place on the screen.
@cc(c)
fn target_tray_clicked(this: usize, command: usize, sender: usize) {
    var slot = 0usize
    while slot < TRAYS && tray_buttons[slot] != sender { slot += 1usize }
    if slot == TRAYS { ret }
    var event: TrayEvent = zero
    event.kind = .Select
    event.id = tray_ids[slot]
    let app = os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00"))
    let current = os.msg0(app, os.cocoa_sel("currentEvent\x00"))
    if current != 0usize && os.msg0(current, os.cocoa_sel("type\x00")) == 4usize { event.kind = .Context }
    let at = msg_event_point(os.cocoa_class("NSEvent\x00"), os.cocoa_sel("mouseLocation\x00"))
    event.x = i32(at.x)
    event.y = i32(f64(cg_display_high(cg_main_display())) - at.y)
    tray_push(event)
}

@cc(c)
fn target_menu_chosen(this: usize, command: usize, sender: usize) {
    popup_choice = u32(os.msg0(sender, os.cocoa_sel("tag\x00")))
    popup_made = true
}

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_after(receiver: usize, selector: usize, action: usize, object: usize, delay: f64, modes: usize) -> usize

var popup_active: usize = zero

// The pop-up menu on show is dismissed, as an Escape would.
@cc(c)
fn target_menu_cancel(this: usize, command: usize, sender: usize) {
    if popup_active != 0usize { let cancelled = os.msg0(popup_active, os.cocoa_sel("cancelTracking\x00")) }
}

// A pop-up menu shown later than this call is dismissed after `seconds`: the run loop does it while the menu tracks, which is
// how a program with no one at the pointer closes one.
fn popup_cancel_after(seconds: f64) -> err {
    let ready = target_ready()
    if ready != ok { ret ready }
    let pool = os.objc_pool_push()
    var modes: [2]usize = zero
    modes[0usize] = os.cocoa_text("NSEventTrackingRunLoopMode")
    modes[1usize] = os.cocoa_text("kCFRunLoopCommonModes")
    let list = os.msg2(os.cocoa_class("NSArray\x00"), os.cocoa_sel("arrayWithObjects:count:\x00"), mem.address_of(&modes[0usize]), 2usize)
    let scheduled = msg_after(shell_target, os.cocoa_sel("performSelector:withObject:afterDelay:inModes:\x00"), os.cocoa_sel("neperCancel:\x00"), 0usize, seconds, list)
    os.cf_release(modes[0usize])
    os.cf_release(modes[1usize])
    os.objc_pool_pop(pool)
    ret ok
}

fn target_ready() -> err {
    if shell_target != 0usize { ret ok }
    let started = os.cocoa_start()
    if started != ok { ret started }
    let name = "NeperShellTarget\x00"
    let class = objc_class_pair(os.cocoa_class("NSObject\x00"), &name[0usize], 0usize)
    if class == 0usize { ret Failed }
    let types = "v@:@\x00"
    var tray: MenuImp = zero
    tray.function = target_tray_clicked
    var chosen: MenuImp = zero
    chosen.function = target_menu_chosen
    let first = objc_class_method(class, os.cocoa_sel("neperTray:\x00"), tray.bits, &types[0usize])
    let second = objc_class_method(class, os.cocoa_sel("neperChoice:\x00"), chosen.bits, &types[0usize])
    var cancel: MenuImp = zero
    cancel.function = target_menu_cancel
    let third = objc_class_method(class, os.cocoa_sel("neperCancel:\x00"), cancel.bits, &types[0usize])
    objc_class_register(class)
    let object = os.msg0(os.msg0(class, os.cocoa_sel("alloc\x00")), os.cocoa_sel("init\x00"))
    if object == 0usize { ret Failed }
    shell_target = object
    ret ok
}

// An NSImage over the icon's pixels, which the caller releases; zero when it cannot be made.
fn icon_image(icon: Icon) -> usize {
    let count = usize(icon.width) * usize(icon.height)
    let data = os.cf_data_create(0usize, mem.address_of(&icon.pixels[0usize]), count * 4usize)
    let provider = os.cg_provider_with_data(data)
    let space = os.cg_color_space()
    let picture = os.cg_image_create(usize(icon.width), usize(icon.height), 8usize, 32usize, usize(icon.width) * 4usize, space, 8194u32, provider, 0usize, 0i32, 0i32)
    var image = 0usize
    if picture != 0usize {
        let size = MenuPoint { x: f64(icon.width), y: f64(icon.height) }
        image = msg_image(os.msg0(os.cocoa_class("NSImage\x00"), os.cocoa_sel("alloc\x00")), os.cocoa_sel("initWithCGImage:size:\x00"), picture, size)
        os.cg_image_release(picture)
    }
    os.cg_provider_release(provider)
    os.cf_release(data)
    ret image
}

fn tray_slot(id: u32) -> usize {
    var slot = 0usize
    while slot < TRAYS && !(tray_items[slot] != 0usize && tray_ids[slot] == id) { slot += 1usize }
    ret slot
}

fn tray_valid_icon(icon: Icon) -> bool {
    ret icon.width != 0u32 && icon.height != 0u32 && icon.pixels.len >= usize(icon.width) * usize(icon.height)
}

fn tray_decorate(button: usize, icon: Icon, tooltip: str) {
    let image = icon_image(icon)
    if image != 0usize {
        let set = os.msg1(button, os.cocoa_sel("setImage:\x00"), image)
        let released = os.msg0(image, os.cocoa_sel("release\x00"))
    }
    let text = os.cocoa_text(tooltip)
    let tipped = os.msg1(button, os.cocoa_sel("setToolTip:\x00"), text)
    os.cf_release(text)
}

fn tray_add(a: *mem.Arena, id: u32, icon: Icon, tooltip: str) -> err {
    if !tray_valid_icon(icon) || tray_slot(id) != TRAYS { ret Invalid }
    let ready = target_ready()
    if ready != ok { ret ready }
    var slot = 0usize
    while slot < TRAYS && tray_items[slot] != 0usize { slot += 1usize }
    if slot == TRAYS { ret Failed }
    let pool = os.objc_pool_push()
    let bar = os.msg0(os.cocoa_class("NSStatusBar\x00"), os.cocoa_sel("systemStatusBar\x00"))
    let item = os.msg_double(bar, os.cocoa_sel("statusItemWithLength:\x00"), -1.0f64)
    var result = ok
    if item == 0usize { result = Failed } else {
        let kept = os.msg0(item, os.cocoa_sel("retain\x00"))
        let button = os.msg0(item, os.cocoa_sel("button\x00"))
        tray_decorate(button, icon, tooltip)
        let targeted = os.msg1(button, os.cocoa_sel("setTarget:\x00"), shell_target)
        let acted = os.msg1(button, os.cocoa_sel("setAction:\x00"), os.cocoa_sel("neperTray:\x00"))
        let masked = os.msg1(button, os.cocoa_sel("sendActionOn:\x00"), 20usize)
        tray_ids[slot] = id
        tray_items[slot] = item
        tray_buttons[slot] = button
    }
    os.objc_pool_pop(pool)
    ret result
}

fn tray_update(a: *mem.Arena, id: u32, icon: Icon, tooltip: str) -> err {
    if !tray_valid_icon(icon) { ret Invalid }
    let slot = tray_slot(id)
    if slot == TRAYS { ret NotFound }
    let pool = os.objc_pool_push()
    tray_decorate(tray_buttons[slot], icon, tooltip)
    os.objc_pool_pop(pool)
    ret ok
}

fn tray_remove(a: *mem.Arena, id: u32) -> err {
    let slot = tray_slot(id)
    if slot == TRAYS { ret NotFound }
    let pool = os.objc_pool_push()
    let bar = os.msg0(os.cocoa_class("NSStatusBar\x00"), os.cocoa_sel("systemStatusBar\x00"))
    let removed = os.msg1(bar, os.cocoa_sel("removeStatusItem:\x00"), tray_items[slot])
    let released = os.msg0(tray_items[slot], os.cocoa_sel("release\x00"))
    tray_items[slot] = 0usize
    tray_buttons[slot] = 0usize
    tray_ids[slot] = 0u32
    os.objc_pool_pop(pool)
    ret ok
}

// The clicks the run loop has delivered since the last call: it is run for what is waiting, no longer.
fn tray_poll() -> (TrayEvent, bool) {
    var none: TrayEvent = zero
    if shell_target != 0usize { os.cocoa_pump(0i64) }
    if tray_head == tray_tail { ret (none, false) }
    let event = tray_queue[tray_head]
    tray_head = (tray_head + 1usize) % TRAY_QUEUE
    ret (event, true)
}

// A menu at a screen place (x from the left, y from the top), shown until an item is chosen or the menu is dismissed.
fn popup_menu(a: *mem.Arena, items: []const MenuItem, x: i32, y: i32) -> (u32, bool, err) {
    if items.len == 0usize { ret (0u32, false, Invalid) }
    var at = 0usize
    while at < items.len {
        if !items[at].separator && items[at].id == 0u32 { ret (0u32, false, Invalid) }
        at += 1usize
    }
    let ready = target_ready()
    if ready != ok { ret (0u32, false, ready) }
    let pool = os.objc_pool_push()
    let menu = os.msg0(os.msg0(os.cocoa_class("NSMenu\x00"), os.cocoa_sel("alloc\x00")), os.cocoa_sel("init\x00"))
    let manual = os.msg_flag(menu, os.cocoa_sel("setAutoenablesItems:\x00"), 0i32)
    at = 0usize
    while at < items.len {
        var entry = 0usize
        if items[at].separator {
            entry = os.msg0(os.cocoa_class("NSMenuItem\x00"), os.cocoa_sel("separatorItem\x00"))
        } else {
            let title = os.cocoa_text(items[at].label)
            let nothing = os.cocoa_text("")
            entry = os.msg4(os.msg0(os.cocoa_class("NSMenuItem\x00"), os.cocoa_sel("alloc\x00")), os.cocoa_sel("initWithTitle:action:keyEquivalent:\x00"), title, os.cocoa_sel("neperChoice:\x00"), nothing, 0usize)
            os.cf_release(title)
            os.cf_release(nothing)
            let tagged = os.msg1(entry, os.cocoa_sel("setTag:\x00"), usize(items[at].id))
            let targeted = os.msg1(entry, os.cocoa_sel("setTarget:\x00"), shell_target)
            let enabled = os.msg_flag(entry, os.cocoa_sel("setEnabled:\x00"), yes_no(items[at].enabled))
            if items[at].checked { let state = os.msg1(entry, os.cocoa_sel("setState:\x00"), 1usize) }
        }
        let added = os.msg1(menu, os.cocoa_sel("addItem:\x00"), entry)
        at += 1usize
    }
    popup_made = false
    popup_active = menu
    let place = MenuPoint { x: f64(x), y: f64(cg_display_high(cg_main_display())) - f64(y) }
    let shown = msg_popup(menu, os.cocoa_sel("popUpMenuPositioningItem:atLocation:inView:\x00"), 0usize, place, 0usize)
    popup_active = 0usize
    let released = os.msg0(menu, os.cocoa_sel("release\x00"))
    os.objc_pool_pop(pool)
    if popup_made { ret (popup_choice, true, ok) }
    ret (0u32, false, ok)
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

// `open`, which hands a URL or a path to what the Mac opens it with; its exit code is the answer, and the
// child's three streams are the parent's own. With `-R` it selects the item in a Finder window.
fn run_open(a: *mem.Arena, flag: str, what: str) -> err {
    let (opener, opener_error) = find_program(a, "open")
    if opener_error != ok { ret opener_error }
    var argv: [3]str = zero
    var count = 0usize
    argv[count] = opener
    count += 1usize
    if flag.len != 0usize {
        argv[count] = flag
        count += 1usize
    }
    argv[count] = what
    count += 1usize
    var options: os.SpawnOptions = zero
    options.argv = argv[0usize..count]
    options.inherit_env = true
    options.stdio.stdout = os.File { raw: 1usize }
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(a, options)
    if spawn_error != ok { ret Failed }
    let (usage, wait_error) = os.wait_usage(child)
    if wait_error != ok || usage.exit_code != 0i32 { ret Failed }
    ret ok
}

fn open_uri(a: *mem.Arena, uri: str) -> err {
    if uri.len == 0usize { ret Invalid }
    ret run_open(a, "", uri)
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

// The item in a Finder window, selected: `open -R`.
fn reveal(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    let (present, exists_error) = fs.exists(a, path)
    if exists_error != ok { ret exists_error }
    if !present { ret NotFound }
    ret run_open(a, "-R", path)
}

fn base_name(path: str) -> str {
    var at = path.len
    while at > 0usize && path[at - 1usize] == 47u8 { at -= 1usize }
    let end = at
    while at > 0usize && path[at - 1usize] != 47u8 { at -= 1usize }
    ret path[at..end]
}

fn join3(a: *mem.Arena, x: str, y: str, z: str) -> (str, err) {
    let (xy, first_error) = str.concat(a, x, y)
    if first_error != ok { ret ("", first_error) }
    let (xyz, second_error) = str.concat(a, xy, z)
    ret (xyz, second_error)
}

// `~/.Trash`: the item keeps its name unless the trash holds one, then a counter is appended.
// ponytail: the home trash only; a move across volumes fails, where Finder uses `/.Trashes/$uid`.
fn trash(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    let (present, exists_error) = fs.exists(a, path)
    if exists_error != ok { ret exists_error }
    if !present { ret NotFound }
    let name = base_name(path)
    if name.len == 0usize { ret Invalid }
    let (home, home_error) = fs.home_dir(a)
    if home_error != ok { ret home_error }
    let (trash_dir, trash_error) = str.concat(a, home, "/.Trash")
    if trash_error != ok { ret trash_error }
    try fs.make_dirs(a, trash_dir)
    var chosen = name
    var counter = 1u64
    while true {
        let (destination, destination_error) = join3(a, trash_dir, "/", chosen)
        if destination_error != ok { ret destination_error }
        let (taken, taken_error) = fs.exists(a, destination)
        if taken_error != ok { ret taken_error }
        if !taken {
            if fs.move(a, path, destination) != ok { ret Failed }
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
    let (tool, tool_error) = find_program(a, "osascript")
    if tool_error != ok { ret .Unavailable }
    ret .Granted
}

// A banner from `osascript`, the text passed as arguments so no quoting reaches the script. The system gives a
// notice no id to hand back, so the id is the clock's, never zero; an update is a fresh banner under the same id.
// ponytail: a banner is attributed to Script Editor and cannot be removed from here.
fn send_notice(a: *mem.Arena, title: str, body: str) -> err {
    let (tool, tool_error) = find_program(a, "osascript")
    if tool_error != ok { ret Unsupported }
    var argv: [9]str = zero
    argv[0usize] = tool
    argv[1usize] = "-e"
    argv[2usize] = "on run argv"
    argv[3usize] = "-e"
    argv[4usize] = "display notification (item 1 of argv) with title (item 2 of argv)"
    argv[5usize] = "-e"
    argv[6usize] = "end run"
    argv[7usize] = body
    argv[8usize] = title
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

// A notice that names a tray belongs to it, as on Windows: its id is the tray's, and a tray that is not there is NotFound.
fn notice_publish(a: *mem.Arena, tray_id: u32, title: str, body: str, silent: bool) -> (u32, err) {
    if body.len == 0usize { ret (0u32, Invalid) }
    if tray_id != 0u32 && tray_slot(tray_id) == TRAYS { ret (0u32, NotFound) }
    let sent = send_notice(a, title, body)
    if sent != ok { ret (0u32, sent) }
    if tray_id != 0u32 { ret (tray_id, ok) }
    let (stamp, clock_error) = os.clock(.Monotonic)
    if clock_error != ok { ret (1u32, ok) }
    ret (u32(stamp & 2147483647i64) | 1u32, ok)
}

fn notice_update(a: *mem.Arena, tray_id: u32, notice_id: u32, title: str, body: str, silent: bool) -> err {
    if body.len == 0usize || notice_id == 0u32 { ret Invalid }
    if tray_id != 0u32 && tray_slot(tray_id) == TRAYS { ret NotFound }
    ret send_notice(a, title, body)
}

fn notice_remove(a: *mem.Arena, tray_id: u32, notice_id: u32) -> err {
    ret Unsupported
}

// ------------------------------------------------------------- data exchange
//
// D890. `e.os` on Linux answers `Unsupported` for the selection -- the X11
// backend speaks windows, not selections, and there is no Wayland one -- so the
// clipboard is `Unsupported` here and the record says so; drag and drop between
// programs is XDND, a protocol of its own the library does not speak. Every
// operation is written so that the day `e.os` learns the selection, these follow.

// The clipboard (D5203), on NSPasteboard's general board. A text is `public.utf8-plain-text`; bytes sit under their
// mime string as the type; files and an image have private types of their own (`com.neper.paths`: the paths, one per
// line; `com.neper.image`: width and height as little-endian u32, then the pixels), which hold what was written exactly.
fn type_text() -> str { ret "public.utf8-plain-text" }
fn type_paths() -> str { ret "com.neper.paths" }
fn type_image() -> str { ret "com.neper.image" }

fn board() -> usize {
    ret os.msg0(os.cocoa_class("NSPasteboard\x00"), os.cocoa_sel("generalPasteboard\x00"))
}

fn board_put(pasteboard: usize, kind: str, data: []const u8) -> bool {
    var one: [1]u8 = zero
    var at = mem.address_of(&one[0usize])
    if data.len != 0usize { at = mem.address_of(&data[0usize]) }
    let name = os.cocoa_text(kind)
    let blob = os.cf_data_create(0usize, at, data.len)
    let stored = os.msg2(pasteboard, os.cocoa_sel("setData:forType:\x00"), blob, name)
    os.cf_release(blob)
    os.cf_release(name)
    ret stored & 255usize != 0usize
}

// The bytes under `kind`, copied into `a`; false when the board holds none.
fn board_get(a: *mem.Arena, pasteboard: usize, kind: str) -> ([]const u8, bool, err) {
    let name = os.cocoa_text(kind)
    let blob = os.msg1(pasteboard, os.cocoa_sel("dataForType:\x00"), name)
    os.cf_release(name)
    if blob == 0usize { ret ("", false, ok) }
    let length = os.msg0(blob, os.cocoa_sel("length\x00"))
    if length == 0usize { ret ("", true, ok) }
    let (copy, allocation_error) = mem.alloc[u8](a, length)
    if allocation_error != ok { ret ("", false, allocation_error) }
    let copied = os.raw_memcpy(mem.address_of(&copy[0usize]), os.msg0(blob, os.cocoa_sel("bytes\x00")), length)
    ret (copy[0usize..length], true, ok)
}

fn clipboard_write(a: *mem.Arena, items: []const Content) -> err {
    if items.len == 0usize { ret Invalid }
    var at = 0usize
    while at < items.len {
        if items[at].kind == .Bytes && items[at].mime.len == 0usize { ret Invalid }
        if items[at].kind == .Promise { ret Unsupported }
        at += 1usize
    }
    let started = os.cocoa_start()
    if started != ok { ret started }
    let pool = os.objc_pool_push()
    let pasteboard = board()
    let cleared = os.msg0(pasteboard, os.cocoa_sel("clearContents\x00"))
    var result = ok
    at = 0usize
    while at < items.len && result == ok {
        let item = items[at]
        if item.kind == .Text {
            if !board_put(pasteboard, type_text(), item.text) { result = Failed }
        } else if item.kind == .Bytes {
            if !board_put(pasteboard, item.mime, item.bytes) { result = Failed }
        } else if item.kind == .Files {
            var total = 0usize
            var path = 0usize
            while path < item.paths.len {
                total += item.paths[path].len + 1usize
                path += 1usize
            }
            let (joined, joined_error) = mem.alloc[u8](a, total + 1usize)
            if joined_error != ok { result = joined_error } else {
                var written = 0usize
                path = 0usize
                while path < item.paths.len {
                    if path != 0usize {
                        joined[written] = 10u8
                        written += 1usize
                    }
                    var byte = 0usize
                    while byte < item.paths[path].len {
                        joined[written] = item.paths[path][byte]
                        written += 1usize
                        byte += 1usize
                    }
                    path += 1usize
                }
                if !board_put(pasteboard, type_paths(), joined[0usize..written]) { result = Failed }
            }
        } else if item.kind == .Image {
            let count = usize(item.image.width) * usize(item.image.height)
            if count == 0usize || item.image.pixels.len < count { result = Invalid } else {
                let (packed, packed_error) = mem.alloc[u8](a, 8usize + count * 4usize)
                if packed_error != ok { result = packed_error } else {
                    var shift = 0usize
                    while shift < 4usize {
                        packed[shift] = u8((item.image.width >> u32(shift * 8usize)) & 255u32)
                        packed[4usize + shift] = u8((item.image.height >> u32(shift * 8usize)) & 255u32)
                        shift += 1usize
                    }
                    let copied = os.raw_memcpy(mem.address_of(&packed[8usize]), mem.address_of(&item.image.pixels[0usize]), count * 4usize)
                    if !board_put(pasteboard, type_image(), packed[0usize..8usize + count * 4usize]) { result = Failed }
                }
            }
        }
        at += 1usize
    }
    os.objc_pool_pop(pool)
    ret result
}

fn clipboard_kind(kind: ContentKind, mime: str) -> str {
    if kind == .Text { ret type_text() }
    if kind == .Files { ret type_paths() }
    if kind == .Image { ret type_image() }
    ret mime
}

fn clipboard_has(a: *mem.Arena, kind: ContentKind, mime: str) -> bool {
    if kind == .Promise || (kind == .Bytes && mime.len == 0usize) { ret false }
    if os.cocoa_start() != ok { ret false }
    let pool = os.objc_pool_push()
    let (data, found, got_error) = board_get(a, board(), clipboard_kind(kind, mime))
    os.objc_pool_pop(pool)
    ret found && got_error == ok
}

fn clipboard_read(a: *mem.Arena, kind: ContentKind, mime: str) -> (Content, err) {
    var item: Content = zero
    if kind == .Bytes && mime.len == 0usize { ret (item, Invalid) }
    if kind == .Promise { ret (item, Unsupported) }
    let started = os.cocoa_start()
    if started != ok { ret (item, started) }
    let pool = os.objc_pool_push()
    let (data, found, got_error) = board_get(a, board(), clipboard_kind(kind, mime))
    os.objc_pool_pop(pool)
    if got_error != ok { ret (item, got_error) }
    if !found { ret (item, NotFound) }
    item.kind = kind
    if kind == .Text {
        item.text = data
    } else if kind == .Bytes {
        item.mime = mime
        item.bytes = data
    } else if kind == .Files {
        var lines = 1usize
        var at = 0usize
        while at < data.len {
            if data[at] == 10u8 { lines += 1usize }
            at += 1usize
        }
        let (paths, paths_error) = mem.alloc[str](a, lines)
        if paths_error != ok { ret (item, paths_error) }
        var start = 0usize
        var line = 0usize
        at = 0usize
        while at <= data.len {
            if at == data.len || data[at] == 10u8 {
                paths[line] = data[start..at]
                line += 1usize
                start = at + 1usize
            }
            at += 1usize
        }
        item.paths = paths[0usize..lines]
    } else {
        if data.len < 8usize { ret (item, Failed) }
        var width = 0u32
        var height = 0u32
        var shift = 0usize
        while shift < 4usize {
            width |= u32(data[shift]) << u32(shift * 8usize)
            height |= u32(data[4usize + shift]) << u32(shift * 8usize)
            shift += 1usize
        }
        let count = usize(width) * usize(height)
        if count == 0usize || data.len != 8usize + count * 4usize { ret (item, Failed) }
        let (pixels, pixels_error) = mem.alloc[u32](a, count)
        if pixels_error != ok { ret (item, pixels_error) }
        let copied = os.raw_memcpy(mem.address_of(&pixels[0usize]), mem.address_of(&data[8usize]), count * 4usize)
        item.image = Icon { width: width, height: height, pixels: pixels[0usize..count] }
    }
    ret (item, ok)
}

fn clipboard_sequence() -> u32 {
    if os.cocoa_start() != ok { ret 0u32 }
    ret u32(os.msg0(board(), os.cocoa_sel("changeCount\x00")))
}

fn drop_target_register(a: *mem.Arena, w: os.Window, storage: *mem.Arena) -> err {
    ret Unsupported
}

fn drop_target_unregister(a: *mem.Arena, w: os.Window) -> err {
    ret Unsupported
}

fn drop_poll() -> (Drop, bool) {
    var none: Drop = zero
    ret (none, false)
}

fn drag_start(a: *mem.Arena, items: []const Content, allow_move: bool) -> (DragResult, err) {
    if items.len == 0usize { ret (.Cancelled, Invalid) }
    ret (.Cancelled, Unsupported)
}

// ------------------------------------------------------ file dialogs and recents
//
// D894. A native file dialog on a desktop is the portal or the toolkit's own,
// neither of which the library speaks, and the recent list is a `.xbel` file
// the specification describes; both are `Unsupported` here and the record says
// so. ponytail: `zenity --file-selection` would be the same tool-shaped path as
// `xdg-open`, when a caller needs it.

// The path of an NSURL, copied into `a`.
fn url_path(a: *mem.Arena, url: usize) -> (str, err) {
    let string = os.msg0(url, os.cocoa_sel("path\x00"))
    var none: [1]u8 = zero
    let length = os.cocoa_read_text(string, none[0usize..0usize])
    if length == 0usize { ret ("", Failed) }
    let (text, text_error) = mem.alloc[u8](a, length)
    if text_error != ok { ret ("", text_error) }
    let copied = os.cocoa_read_text(string, text[0usize..length])
    ret (text[0usize..length], ok)
}

// `*.txt` is the extension `txt`; `*` and `*.*` name no extension and so allow every file.
fn pattern_extension(pattern: str) -> str {
    if pattern.len > 2usize && pattern[0usize] == 42u8 && pattern[1usize] == 46u8 && pattern[2usize] != 42u8 { ret pattern[2usize..pattern.len] }
    ret ""
}

// NSOpenPanel and NSSavePanel, run modally; a dismissed panel is `Cancelled`. ponytail: `allowedFileTypes` is the
// extension list the panels deprecated for content types but still honour.
fn file_dialog(a: *mem.Arena, w: os.Window, dialog: FileDialog) -> ([]const str, err) {
    var nothing: []const str = zero
    if dialog.filters.len > 16usize { ret (nothing, Invalid) }
    if dialog.kind != .Open && dialog.multiple { ret (nothing, Invalid) }
    let started = os.cocoa_start()
    if started != ok { ret (nothing, started) }
    let pool = os.objc_pool_push()
    var panel = 0usize
    if dialog.kind == .Save {
        panel = os.msg0(os.cocoa_class("NSSavePanel\x00"), os.cocoa_sel("savePanel\x00"))
    } else {
        panel = os.msg0(os.cocoa_class("NSOpenPanel\x00"), os.cocoa_sel("openPanel\x00"))
        let files = os.msg_flag(panel, os.cocoa_sel("setCanChooseFiles:\x00"), yes_no(dialog.kind == .Open))
        let folders = os.msg_flag(panel, os.cocoa_sel("setCanChooseDirectories:\x00"), yes_no(dialog.kind == .Folder))
        let several = os.msg_flag(panel, os.cocoa_sel("setAllowsMultipleSelection:\x00"), yes_no(dialog.multiple))
    }
    let creating = os.msg_flag(panel, os.cocoa_sel("setCanCreateDirectories:\x00"), 1i32)
    var held: [24]usize = zero
    var holds = 0usize
    if dialog.title.len != 0usize {
        let title = os.cocoa_text(dialog.title)
        held[holds] = title
        holds += 1usize
        let titled = os.msg1(panel, os.cocoa_sel("setTitle:\x00"), title)
        let messaged = os.msg1(panel, os.cocoa_sel("setMessage:\x00"), title)
    }
    if dialog.kind == .Save && dialog.initial.len != 0usize {
        let name = os.cocoa_text(dialog.initial)
        held[holds] = name
        holds += 1usize
        let named = os.msg1(panel, os.cocoa_sel("setNameFieldStringValue:\x00"), name)
    }
    if dialog.folder.len != 0usize {
        let folder = os.cocoa_text(dialog.folder)
        held[holds] = folder
        holds += 1usize
        let url = os.msg1(os.cocoa_class("NSURL\x00"), os.cocoa_sel("fileURLWithPath:\x00"), folder)
        let placed = os.msg1(panel, os.cocoa_sel("setDirectoryURL:\x00"), url)
    }
    var types: [17]usize = zero
    var type_count = 0usize
    var at = 0usize
    while at < dialog.filters.len {
        let extension = pattern_extension(dialog.filters[at].pattern)
        if extension.len != 0usize {
            let name = os.cocoa_text(extension)
            types[type_count] = name
            type_count += 1usize
        }
        at += 1usize
    }
    if type_count == 0usize && dialog.kind == .Save && dialog.default_extension.len != 0usize {
        types[0usize] = os.cocoa_text(dialog.default_extension)
        type_count = 1usize
    }
    if type_count != 0usize {
        let list = os.msg2(os.cocoa_class("NSArray\x00"), os.cocoa_sel("arrayWithObjects:count:\x00"), mem.address_of(&types[0usize]), type_count)
        let allowed = os.msg1(panel, os.cocoa_sel("setAllowedFileTypes:\x00"), list)
    }
    let response = os.msg0(panel, os.cocoa_sel("runModal\x00"))
    var picked: []str = zero
    var result = ok
    if response != 1usize {
        result = Cancelled
    } else if dialog.kind == .Save {
        let (chosen, chosen_error) = mem.alloc[str](a, 1usize)
        if chosen_error != ok { result = chosen_error } else {
            let (path, path_error) = url_path(a, os.msg0(panel, os.cocoa_sel("URL\x00")))
            if path_error != ok { result = path_error } else {
                chosen[0usize] = path
                picked = chosen[0usize..1usize]
            }
        }
    } else {
        let urls = os.msg0(panel, os.cocoa_sel("URLs\x00"))
        let count = os.msg0(urls, os.cocoa_sel("count\x00"))
        let (chosen, chosen_error) = mem.alloc[str](a, count + 1usize)
        if chosen_error != ok { result = chosen_error } else {
            var index = 0usize
            while index < count && result == ok {
                let (path, path_error) = url_path(a, os.msg1(urls, os.cocoa_sel("objectAtIndex:\x00"), index))
                if path_error != ok { result = path_error } else { chosen[index] = path }
                index += 1usize
            }
            picked = chosen[0usize..count]
        }
    }
    var release = 0usize
    while release < holds {
        os.cf_release(held[release])
        release += 1usize
    }
    release = 0usize
    while release < type_count {
        os.cf_release(types[release])
        release += 1usize
    }
    os.objc_pool_pop(pool)
    ret (picked, result)
}

fn yes_no(on: bool) -> i32 {
    if on { ret 1i32 }
    ret 0i32
}

// The Recent Items list of the application menu and the Dock, through the shared document controller.
fn recent_add(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    let (present, exists_error) = fs.exists(a, path)
    if exists_error != ok { ret exists_error }
    if !present { ret NotFound }
    let started = os.cocoa_start()
    if started != ok { ret started }
    let pool = os.objc_pool_push()
    let text = os.cocoa_text(path)
    let url = os.msg1(os.cocoa_class("NSURL\x00"), os.cocoa_sel("fileURLWithPath:\x00"), text)
    let controller = os.msg0(os.cocoa_class("NSDocumentController\x00"), os.cocoa_sel("sharedDocumentController\x00"))
    let noted = os.msg1(controller, os.cocoa_sel("noteNewRecentDocumentURL:\x00"), url)
    os.cf_release(text)
    os.objc_pool_pop(pool)
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
// D896. Startup is the freedesktop autostart specification: a `.desktop` file
// under `$XDG_CONFIG_HOME/autostart` (or `~/.config/autostart`) naming this
// executable, written and removed by hand. A file or protocol association is a
// `.desktop` file plus `update-desktop-database` and `xdg-mime`, and a single
// instance is a socket in the runtime directory; neither is written yet, so
// both are `Unsupported` and the record says so.

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

fn associate_file(a: *mem.Arena, extension: str, program_id: str, description: str) -> err {
    if extension.len < 2usize || extension[0usize] != 46u8 || !valid_name(extension) || !valid_name(program_id) { ret Invalid }
    ret Unsupported
}

fn dissociate_file(a: *mem.Arena, extension: str, program_id: str) -> err {
    if extension.len < 2usize || extension[0usize] != 46u8 || !valid_name(extension) || !valid_name(program_id) { ret Invalid }
    ret Unsupported
}

fn associate_protocol(a: *mem.Arena, scheme: str, description: str) -> err {
    if !valid_name(scheme) || scheme.len > 64usize { ret Invalid }
    ret Unsupported
}

fn dissociate_protocol(a: *mem.Arena, scheme: str) -> err {
    if !valid_name(scheme) || scheme.len > 64usize { ret Invalid }
    ret Unsupported
}

fn autostart_path(a: *mem.Arena, id: str) -> (str, err) {
    let (home, home_error) = fs.home_dir(a)
    if home_error != ok { ret ("", home_error) }
    let (directory, directory_error) = str.concat(a, home, "/Library/LaunchAgents")
    if directory_error != ok { ret ("", directory_error) }
    let (with_id, id_error) = join3(a, directory, "/", id)
    if id_error != ok { ret ("", id_error) }
    let (path, path_error) = str.concat(a, with_id, ".plist")
    ret (path, path_error)
}

fn startup_set(a: *mem.Arena, id: str, enabled: bool) -> err {
    if !valid_name(id) { ret Invalid }
    let (path, path_error) = autostart_path(a, id)
    if path_error != ok { ret path_error }
    if !enabled {
        let removed = fs.remove_file(a, path)
        if removed != ok && removed != fs.NotFound { ret Failed }
        ret ok
    }
    let (exe, exe_error) = fs.executable_path(a)
    if exe_error != ok { ret exe_error }
    try fs.make_dirs(a, parent_of(path))
    let (head, head_error) = join3(a, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict><key>Label</key><string>", id, "</string><key>ProgramArguments</key><array><string>")
    if head_error != ok { ret head_error }
    let (content, content_error) = join3(a, head, exe, "</string></array><key>RunAtLoad</key><true/></dict></plist>\n")
    if content_error != ok { ret content_error }
    ret fs.write_file(a, path, content)
}

fn startup_enabled(a: *mem.Arena, id: str) -> (bool, err) {
    if !valid_name(id) { ret (false, Invalid) }
    let (path, path_error) = autostart_path(a, id)
    if path_error != ok { ret (false, path_error) }
    let (present, exists_error) = fs.exists(a, path)
    if exists_error != ok { ret (false, exists_error) }
    ret (present, ok)
}

fn single_instance(a: *mem.Arena, id: str, args: []const str, storage: *mem.Arena) -> (bool, err) {
    if !valid_name(id) { ret (false, Invalid) }
    ret (false, Unsupported)
}

fn activation_poll() -> (Activation, bool) {
    var none: Activation = zero
    ret (none, false)
}
// ------------------------------------------------- lifecycle and global input
//
// D898. Background work needs no permission on a desktop; power inhibition is
// `systemd-inhibit` holding a child alive until released, the same tool-shaped
// path as `xdg-open`; a global shortcut is the compositor's (a portal on
// Wayland, a grab on X11), the session's shutdown is logind over D-Bus, and a
// restart is the session manager's -- none of which the library speaks, so those
// are `Unsupported` and the record says so.

var inhibitor: os.Proc = zero
var inhibiting: bool = zero

fn hotkey_register(a: *mem.Arena, id: u32, key: Hotkey) -> err {
    if id == 0u32 || id > 49151u32 || key.key == 0u32 { ret Invalid }
    ret Unsupported
}

fn hotkey_unregister(a: *mem.Arena, id: u32) -> err {
    if id == 0u32 || id > 49151u32 { ret Invalid }
    ret Unsupported
}

fn hotkey_poll() -> (u32, bool) {
    ret (0u32, false)
}

fn background_permission(a: *mem.Arena) -> Permission {
    ret .Granted
}

// ponytail: the tool's refusal (no session, a denied inhibitor) is printed by the
// child and not seen here; a caller that must know reads the lifecycle later.
// `caffeinate` holds the Mac awake for as long as it runs: `-i` against idle sleep, with `-d` for the display as well.
fn power_inhibit(a: *mem.Arena, keep_display: bool) -> err {
    if inhibiting { ret ok }
    let (tool, tool_error) = find_program(a, "caffeinate")
    if tool_error != ok { ret Unsupported }
    var argv: [2]str = zero
    argv[0usize] = tool
    argv[1usize] = "-i"
    if keep_display { argv[1usize] = "-di" }
    var options: os.SpawnOptions = zero
    options.argv = argv[..]
    options.inherit_env = true
    options.stdio.stdout = os.File { raw: 1usize }
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(a, options)
    if spawn_error != ok { ret Failed }
    inhibitor = child
    inhibiting = true
    ret ok
}

fn power_release(a: *mem.Arena) -> err {
    if !inhibiting { ret NotFound }
    let killed = os.kill(inhibitor)
    let (usage, wait_error) = os.wait_usage(inhibitor)
    inhibiting = false
    ret ok
}

fn lifecycle_poll() -> (LifecycleEvent, bool) {
    ret (.Resume, false)
}

fn restart_register(a: *mem.Arena, arguments: str) -> err {
    if arguments.len > 1024usize { ret Invalid }
    ret Unsupported
}

fn restart_unregister(a: *mem.Arena) -> err {
    ret Unsupported
}
// ------------------------------------------------------------------ printing
//
// D900. Printing on a desktop is CUPS, whose `lp` takes images as pages, and
// its dialogs are the toolkit's or the portal's; none of it is written yet, so
// every verb is `Unsupported` and the record says so. ponytail: `lp` with a PNG
// per page is the same tool-shaped path as `xdg-open`, when a caller needs it.

fn printer_open(a: *mem.Arena, name: str) -> (Printer, err) {
    var nothing: Printer = zero
    ret (nothing, Unsupported)
}

fn printer_close(a: *mem.Arena, p: Printer) -> err {
    if p.device == 0usize { ret Invalid }
    ret Unsupported
}

fn printer_page(p: Printer) -> PrintPage {
    ret PrintPage { width: 0u32, height: 0u32, dpi_x: 0u32, dpi_y: 0u32 }
}

fn print_dialog(a: *mem.Arena, w: os.Window, min_page: u32, max_page: u32) -> (Printer, err) {
    var nothing: Printer = zero
    if min_page == 0u32 || max_page < min_page || max_page > 65535u32 { ret (nothing, Invalid) }
    ret (nothing, Unsupported)
}

fn page_setup_dialog(a: *mem.Arena, w: os.Window, current: PageSetup) -> (PageSetup, err) {
    var nothing: PageSetup = zero
    ret (nothing, Unsupported)
}

fn print_job_start(a: *mem.Arena, p: Printer, document: str, output: str) -> (PrintJob, err) {
    var nothing: PrintJob = zero
    if p.device == 0usize || document.len == 0usize { ret (nothing, Invalid) }
    ret (nothing, Unsupported)
}

fn print_page(a: *mem.Arena, job: *PrintJob, page: Icon) -> err {
    if !job.open { ret NotFound }
    ret Unsupported
}

fn print_job_end(a: *mem.Arena, job: *PrintJob) -> err {
    if !job.open { ret NotFound }
    ret Unsupported
}

fn print_job_cancel(a: *mem.Arena, job: *PrintJob) -> err {
    if !job.open { ret NotFound }
    ret Unsupported
}
// ------------------------------------------------- permissions and services
//
// D902. A desktop gates the camera, the microphone and the location through the
// portal, biometrics through the fingerprint daemon and the screen through the
// compositor, none of which the library speaks, so those are `Unavailable` or
// `Unsupported` and the record says so; a credential is `secret-tool` (libsecret)
// where it is installed, the same tool-shaped path as the rest.

// The screen is always capturable; without the Screen Recording permission the picture leaves out other applications' windows, which is a
// difference in content and not a refusal. The other capabilities have no answer here.
fn permission_status(a: *mem.Arena, c: Capability) -> Permission {
    if c == .Screen { ret .Granted }
    ret .Unavailable
}

fn permission_request(a: *mem.Arena, c: Capability) -> (Permission, err) {
    ret (.Unavailable, ok)
}

fn credential_tool(a: *mem.Arena) -> (str, err) {
    let (tool, tool_error) = find_program(a, "secret-tool")
    if tool_error != ok { ret ("", Unsupported) }
    ret (tool, ok)
}

fn run_tool(a: *mem.Arena, argv: []const str, input: []const u8, output: []u8) -> (usize, i32, err) {
    let (reading, writing, pipe_error) = os.pipe()
    if pipe_error != ok { ret (0usize, 0i32, Failed) }
    let (in_reading, in_writing, in_error) = os.pipe()
    if in_error != ok {
        let closed_reading = os.close(reading)
        let closed_writing = os.close(writing)
        ret (0usize, 0i32, Failed)
    }
    var options: os.SpawnOptions = zero
    options.argv = argv
    options.inherit_env = true
    options.stdio.stdin = in_reading
    options.stdio.stdout = writing
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(a, options)
    let closed_in_reading = os.close(options.stdio.stdin)
    let closed_writing = os.close(options.stdio.stdout)
    if spawn_error != ok {
        let closed_reading = os.close(reading)
        let closed_in_writing = os.close(in_writing)
        ret (0usize, 0i32, Failed)
    }
    if input.len != 0usize { let (sent, write_error) = os.write(in_writing, input) }
    let closed_in_writing = os.close(in_writing)
    var filled = 0usize
    while filled < output.len {
        let (got, read_error) = os.read(reading, output[filled..output.len])
        if read_error != ok || got == 0usize { break }
        filled += got
    }
    let closed_reading = os.close(reading)
    let (usage, wait_error) = os.wait_usage(child)
    if wait_error != ok { ret (filled, 0i32, Failed) }
    ret (filled, usage.exit_code, ok)
}

fn credential_store(a: *mem.Arena, target_name: str, user: str, secret: []const u8) -> err {
    if target_name.len == 0usize || secret.len == 0usize || secret.len > 2560usize { ret Invalid }
    let (tool, tool_error) = credential_tool(a)
    if tool_error != ok { ret tool_error }
    var argv: [8]str = zero
    argv[0usize] = tool
    argv[1usize] = "store"
    argv[2usize] = "--label"
    argv[3usize] = target_name
    argv[4usize] = "target"
    argv[5usize] = target_name
    argv[6usize] = "user"
    argv[7usize] = user
    var output: [16]u8 = zero
    let (filled, code, run_error) = run_tool(a, argv[..], secret, output[..])
    if run_error != ok || code != 0i32 { ret Failed }
    ret ok
}

fn credential_read(a: *mem.Arena, target_name: str) -> (Credential, err) {
    var nothing: Credential = zero
    if target_name.len == 0usize { ret (nothing, Invalid) }
    let (tool, tool_error) = credential_tool(a)
    if tool_error != ok { ret (nothing, tool_error) }
    var argv: [4]str = zero
    argv[0usize] = tool
    argv[1usize] = "lookup"
    argv[2usize] = "target"
    argv[3usize] = target_name
    let (output, allocation_error) = mem.alloc[u8](a, 2560usize)
    if allocation_error != ok { ret (nothing, allocation_error) }
    let (filled, code, run_error) = run_tool(a, argv[..], "", output)
    if run_error != ok { ret (nothing, run_error) }
    if code != 0i32 || filled == 0usize { ret (nothing, NotFound) }
    ret (Credential { user: "", secret: output[0usize..filled] }, ok)
}

fn credential_delete(a: *mem.Arena, target_name: str) -> err {
    if target_name.len == 0usize { ret Invalid }
    let (tool, tool_error) = credential_tool(a)
    if tool_error != ok { ret tool_error }
    var argv: [4]str = zero
    argv[0usize] = tool
    argv[1usize] = "clear"
    argv[2usize] = "target"
    argv[3usize] = target_name
    var output: [16]u8 = zero
    let (filled, code, run_error) = run_tool(a, argv[..], "", output[..])
    if run_error != ok || code != 0i32 { ret Failed }
    ret ok
}

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGMainDisplayID")
extern fn cg_main_display() -> u32

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGDisplayCreateImage")
extern fn cg_display_image(display: u32) -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGImageGetWidth")
extern fn cg_image_width(image: usize) -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGImageGetHeight")
extern fn cg_image_height(image: usize) -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGImageGetBytesPerRow")
extern fn cg_image_row(image: usize) -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGImageGetBitsPerPixel")
extern fn cg_image_bits(image: usize) -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGImageGetDataProvider")
extern fn cg_image_provider(image: usize) -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGDataProviderCopyData")
extern fn cg_provider_copy(provider: usize) -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGImageRelease")
extern fn cg_release_image(image: usize)

@import("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", "CFDataGetBytePtr")
extern fn cf_data_bytes(data: usize) -> usize

@import("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", "CFRelease")
extern fn cf_drop(object: usize)

// The main display as it is now: `CGDisplayCreateImage`'s 32-bit pixels, copied row by row without the row padding.
// Without the Screen Recording permission the system hands back a picture without other applications' windows.
fn screen_capture(a: *mem.Arena) -> (Icon, err) {
    var nothing: Icon = zero
    let image = cg_display_image(cg_main_display())
    if image == 0usize { ret (nothing, Failed) }
    let width = cg_image_width(image)
    let height = cg_image_height(image)
    let row = cg_image_row(image)
    var result = ok
    var pixels: []u32 = zero
    if width == 0usize || height == 0usize || cg_image_bits(image) != 32usize || row < width * 4usize {
        result = Failed
    } else {
        let data = cg_provider_copy(cg_image_provider(image))
        if data == 0usize { result = Failed } else {
            let source = cf_data_bytes(data)
            let (copy, copy_error) = mem.alloc[u32](a, width * height)
            if copy_error != ok { result = copy_error } else {
                var y = 0usize
                while y < height {
                    let moved = os.raw_memcpy(mem.address_of(&copy[y * width]), source + y * row, width * 4usize)
                    y += 1usize
                }
                pixels = copy[0usize..width * height]
            }
            cf_drop(data)
        }
    }
    cg_release_image(image)
    if result != ok { ret (nothing, result) }
    ret (Icon { width: u32(width), height: u32(height), pixels: pixels }, ok)
}

fn biometric_verify(a: *mem.Arena, reason: str) -> (Permission, err) {
    ret (.Unavailable, Unsupported)
}

fn photo_picker(a: *mem.Arena, w: os.Window, multiple: bool) -> ([]const str, err) {
    var nothing: []const str = zero
    ret (nothing, Unsupported)
}
