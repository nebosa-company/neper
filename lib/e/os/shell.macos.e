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
    ret Capabilities { tray: true, popup_menu: true, open_uri: true, reveal: true, trash: true, taskbar: true, jump_list: true, notices: true, notice_actions: false, notice_remove: false, clipboard_text: true, clipboard_typed: true, drop_target: true, drag_source: true, file_dialogs: true, recent_documents: true, associations: true, startup: true, single_instance: true, hotkeys: true, power_inhibit: has_tool("caffeinate"), lifecycle_events: true, restart: false, printing: true, print_dialogs: false, permissions: true, credentials: has_tool("security"), screen_capture: true, biometrics: false, photo_picker: false }
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
    var task: MenuImp = zero
    task.function = target_dock_task
    let fourth = objc_class_method(class, os.cocoa_sel("neperTask:\x00"), task.bits, &types[0usize])
    var dock: MenuImpReturn = zero
    dock.function = target_dock_menu
    let returning = "@@:@\x00"
    let fifth = objc_class_method(class, os.cocoa_sel("applicationDockMenu:\x00"), dock.bits, &returning[0usize])
    var sleeping: MenuImp = zero
    sleeping.function = target_will_sleep
    var waking: MenuImp = zero
    waking.function = target_did_wake
    var ending: MenuImp = zero
    ending.function = target_will_terminate
    let sixth = objc_class_method(class, os.cocoa_sel("neperSleep:\x00"), sleeping.bits, &types[0usize])
    let seventh = objc_class_method(class, os.cocoa_sel("neperWake:\x00"), waking.bits, &types[0usize])
    let eighth = objc_class_method(class, os.cocoa_sel("applicationWillTerminate:\x00"), ending.bits, &types[0usize])
    var source_mask: MenuImp4Value = zero
    source_mask.function = source_drag_mask
    var source_end: MenuImp4 = zero
    source_end.function = source_drag_ended
    var end_drag: MenuImp = zero
    end_drag.function = target_drag_end
    let mask_types = "Q@:@q\x00"
    let ended_types = "v@:@{CGPoint=dd}Q\x00"
    let ninth = objc_class_method(class, os.cocoa_sel("draggingSession:sourceOperationMaskForDraggingContext:\x00"), source_mask.bits, &mask_types[0usize])
    let tenth = objc_class_method(class, os.cocoa_sel("draggingSession:endedAtPoint:operation:\x00"), source_end.bits, &ended_types[0usize])
    let eleventh = objc_class_method(class, os.cocoa_sel("neperEndDrag:\x00"), end_drag.bits, &types[0usize])
    var open_files: MenuImp4 = zero
    open_files.function = target_open_files
    var open_urls: MenuImp4 = zero
    open_urls.function = target_open_urls
    let open_types = "v@:@@\x00"
    let twelfth = objc_class_method(class, os.cocoa_sel("application:openFiles:\x00"), open_files.bits, &open_types[0usize])
    let thirteenth = objc_class_method(class, os.cocoa_sel("application:openURLs:\x00"), open_urls.bits, &open_types[0usize])
    var get_url: MenuImp4 = zero
    get_url.function = target_get_url
    let fourteenth = objc_class_method(class, os.cocoa_sel("neperURL:withReplyEvent:\x00"), get_url.bits, &open_types[0usize])
    objc_class_register(class)
    let object = os.msg0(os.msg0(class, os.cocoa_sel("alloc\x00")), os.cocoa_sel("init\x00"))
    if object == 0usize { ret Failed }
    shell_target = object
    lifecycle_observe()
    // 'GURL' 'GURL'
    let manager = os.msg0(os.cocoa_class("NSAppleEventManager\x00"), os.cocoa_sel("sharedAppleEventManager\x00"))
    let handled = os.msg4(manager, os.cocoa_sel("setEventHandler:andSelector:forEventClass:andEventID:\x00"), object, os.cocoa_sel("neperURL:withReplyEvent:\x00"), 1196773964usize, 1196773964usize)
    let app = os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00"))
    let delegated = os.msg1(app, os.cocoa_sel("setDelegate:\x00"), object)
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

// The Dock stands for the taskbar (D5209). Progress is the Dock tile's badge (`50%`, `...` while indeterminate, `!` for an
// error); an overlay replaces the application's icon with the picture and a nil picture puts the system's back; a jump list is
// the Dock menu, which the application delegate (the shell target) answers `applicationDockMenu:` with. A task is a menu item
// whose represented object is `program`, a newline and `arguments`; choosing one runs it.
type MenuImpReturn = union { function: fn(usize, usize, usize) -> usize, bits: usize }

var dock_menu: usize = zero

fn dock_tile() -> usize {
    ret os.msg0(os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00")), os.cocoa_sel("dockTile\x00"))
}

fn dock_badge(label: str) {
    let tile = dock_tile()
    if label.len == 0usize {
        let cleared = os.msg1(tile, os.cocoa_sel("setBadgeLabel:\x00"), 0usize)
    } else {
        let text = os.cocoa_text(label)
        let set = os.msg1(tile, os.cocoa_sel("setBadgeLabel:\x00"), text)
        os.cf_release(text)
    }
}

fn taskbar_progress(a: *mem.Arena, w: os.Window, state: ProgressState, completed: u64, total: u64) -> err {
    if state == .Normal || state == .Paused || state == .Error {
        if total == 0u64 || completed > total { ret Invalid }
    }
    let started = os.cocoa_start()
    if started != ok { ret started }
    let pool = os.objc_pool_push()
    if state == .None {
        dock_badge("")
    } else if state == .Indeterminate {
        dock_badge("...")
    } else if state == .Error {
        dock_badge("!")
    } else {
        var digits: [4]u8 = zero
        let percent = (completed * 100u64) / total
        var count = 0usize
        if percent >= 100u64 {
            digits[0usize] = 49u8
            digits[1usize] = 48u8
            digits[2usize] = 48u8
            count = 3usize
        } else if percent >= 10u64 {
            digits[0usize] = u8(48u64 + percent / 10u64)
            digits[1usize] = u8(48u64 + percent % 10u64)
            count = 2usize
        } else {
            digits[0usize] = u8(48u64 + percent)
            count = 1usize
        }
        var label: [5]u8 = zero
        var at = 0usize
        while at < count {
            label[at] = digits[at]
            at += 1usize
        }
        label[count] = 37u8
        dock_badge(label[0usize..count + 1usize])
    }
    os.objc_pool_pop(pool)
    ret ok
}

fn taskbar_overlay(a: *mem.Arena, w: os.Window, icon: Icon, description: str) -> err {
    let started = os.cocoa_start()
    if started != ok { ret started }
    let pool = os.objc_pool_push()
    let app = os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00"))
    var result = ok
    if icon.width == 0u32 || icon.height == 0u32 {
        let restored = os.msg1(app, os.cocoa_sel("setApplicationIconImage:\x00"), 0usize)
    } else if !tray_valid_icon(icon) {
        result = Invalid
    } else {
        let image = icon_image(icon)
        if image == 0usize { result = Failed } else {
            let set = os.msg1(app, os.cocoa_sel("setApplicationIconImage:\x00"), image)
            let released = os.msg0(image, os.cocoa_sel("release\x00"))
        }
    }
    os.objc_pool_pop(pool)
    ret result
}

// The delegate's answer: the Dock menu made by the last `jump_list`, or none.
@cc(c)
fn target_dock_menu(this: usize, command: usize, sender: usize) -> usize {
    ret dock_menu
}

// A Dock menu item: its program and arguments run in the background.
@cc(c)
fn target_dock_task(this: usize, command: usize, sender: usize) {
    let held = os.msg0(sender, os.cocoa_sel("representedObject\x00"))
    var text: [1024]u8 = zero
    let length = os.cocoa_read_text(held, text[..])
    if length == 0usize || length > 1000usize { ret }
    // `sh` starts the program in the background and ends, so no child is left to wait for.
    var line: [1040]u8 = zero
    var out = 0usize
    line[out] = 39u8
    out += 1usize
    var at = 0usize
    while at < length && text[at] != 10u8 {
        line[out] = text[at]
        out += 1usize
        at += 1usize
    }
    line[out] = 39u8
    line[out + 1usize] = 32u8
    out += 2usize
    at += 1usize
    while at < length {
        line[out] = text[at]
        out += 1usize
        at += 1usize
    }
    let tail = " >/dev/null 2>&1 &"
    var t = 0usize
    while t < tail.len {
        line[out] = tail[t]
        out += 1usize
        t += 1usize
    }
    var storage: [16384]u8 = zero
    var scratch = mem.arena_from(storage[..])
    var argv: [3]str = zero
    argv[0usize] = "/bin/sh"
    argv[1usize] = "-c"
    argv[2usize] = line[0usize..out]
    var options: os.SpawnOptions = zero
    options.argv = argv[..]
    options.inherit_env = true
    options.stdio.stdout = os.File { raw: 1usize }
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(&scratch, options)
    if spawn_error != ok { ret }
    let (usage, wait_error) = os.wait_usage(child)
}

fn jump_list(a: *mem.Arena, tasks: []const JumpTask) -> err {
    var at = 0usize
    while at < tasks.len {
        if tasks[at].title.len == 0usize || tasks[at].program.len == 0usize { ret Invalid }
        at += 1usize
    }
    let ready = target_ready()
    if ready != ok { ret ready }
    let pool = os.objc_pool_push()
    let menu = os.msg0(os.msg0(os.cocoa_class("NSMenu\x00"), os.cocoa_sel("alloc\x00")), os.cocoa_sel("init\x00"))
    at = 0usize
    while at < tasks.len {
        let title = os.cocoa_text(tasks[at].title)
        let nothing = os.cocoa_text("")
        let entry = os.msg4(os.msg0(os.cocoa_class("NSMenuItem\x00"), os.cocoa_sel("alloc\x00")), os.cocoa_sel("initWithTitle:action:keyEquivalent:\x00"), title, os.cocoa_sel("neperTask:\x00"), nothing, 0usize)
        os.cf_release(title)
        os.cf_release(nothing)
        let (joined, join_error) = join3(a, tasks[at].program, "\n", tasks[at].arguments)
        if join_error != ok { ret join_error }
        let held = os.cocoa_text(joined)
        let stored = os.msg1(entry, os.cocoa_sel("setRepresentedObject:\x00"), held)
        os.cf_release(held)
        let targeted = os.msg1(entry, os.cocoa_sel("setTarget:\x00"), shell_target)
        let added = os.msg1(menu, os.cocoa_sel("addItem:\x00"), entry)
        let released = os.msg0(entry, os.cocoa_sel("release\x00"))
        at += 1usize
    }
    if dock_menu != 0usize { let dropped = os.msg0(dock_menu, os.cocoa_sel("release\x00")) }
    dock_menu = menu
    os.objc_pool_pop(pool)
    ret ok
}

fn jump_list_clear(a: *mem.Arena) -> err {
    if dock_menu != 0usize { let dropped = os.msg0(dock_menu, os.cocoa_sel("release\x00")) }
    dock_menu = 0usize
    ret ok
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

// Drag and drop (D5213). A drop target is the window's content view given a subclass (`NeperDropView`, made at run time over
// the view's own class, its `isa` swapped) that answers the dragging destination protocol: it accepts a copy, and
// `performDragOperation:` reads the dragging pasteboard (file paths from `NSFilenamesPboardType`, text from
// `public.utf8-plain-text`, bytes and images under the types of the clipboard) into the arena the caller gave and queues a Drop
// at the pointer in the window's pixels. A drag source is `beginDraggingSessionWithItems:event:source:` on that view with the
// shell target as the source, run until the system reports the session ended; `drag_cancel_after` ends one by posting a mouse
// up, which is how a program with no one at the pointer closes it.
type MenuImp4 = union { function: fn(usize, usize, usize, usize), bits: usize }
type MenuImp4Value = union { function: fn(usize, usize, usize, usize) -> usize, bits: usize }
type MenuImpValue = union { function: fn(usize, usize, usize) -> usize, bits: usize }
type DragPoint = struct { x: f64, y: f64 }

@import("/usr/lib/libobjc.A.dylib", "object_getClass")
extern fn objc_class_of(object: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "object_setClass")
extern fn objc_set_class(object: usize, class: usize) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_mouse_event(receiver: usize, selector: usize, kind: usize, at: DragPoint, flags: usize, stamp: f64, window_number: usize, context: usize, event_number: usize, clicks: usize, pressure: f32) -> usize

@import("/usr/lib/libobjc.A.dylib", "objc_msgSend")
extern fn msg_item_frame(receiver: usize, selector: usize, rect: PdfRect, contents: usize) -> usize

const DROPS: usize = 8usize
var drop_view: usize = zero
var drop_class: usize = zero
var drop_original: usize = zero
var drop_window: os.Window = zero
var drop_arena: *mem.Arena = zero
var drop_queue: [8]Drop = zero
var drop_head: usize = zero
var drop_tail: usize = zero
var drag_ended: bool = zero
var drag_operation: usize = zero
var drag_allow_move: bool = zero

fn drop_push(item: Drop) {
    let next = (drop_tail + 1usize) % DROPS
    if next == drop_head { ret }
    drop_queue[drop_tail] = item
    drop_tail = next
}

@cc(c)
fn view_drag_entered(this: usize, command: usize, sender: usize) -> usize { ret 1usize }

@cc(c)
fn view_drag_prepare(this: usize, command: usize, sender: usize) -> usize { ret 1usize }

fn pasteboard_string(a: *mem.Arena, drag_board: usize, kind: str) -> (str, bool) {
    let name = os.cocoa_text(kind)
    let string = os.msg1(drag_board, os.cocoa_sel("stringForType:\x00"), name)
    os.cf_release(name)
    if string == 0usize { ret ("", false) }
    var none: [1]u8 = zero
    let length = os.cocoa_read_text(string, none[0usize..0usize])
    if length == 0usize { ret ("", false) }
    let (text, allocation_error) = mem.alloc[u8](a, length)
    if allocation_error != ok { ret ("", false) }
    let copied = os.cocoa_read_text(string, text[0usize..length])
    ret (text[0usize..length], true)
}

@cc(c)
fn view_drag_perform(this: usize, command: usize, sender: usize) -> usize {
    if drop_view == 0usize { ret 0usize }
    let drag_board = os.msg0(sender, os.cocoa_sel("draggingPasteboard\x00"))
    if drag_board == 0usize { ret 0usize }
    let at = msg_event_point(sender, os.cocoa_sel("draggingLocation\x00"))
    var drop: Drop = zero
    let (metrics, metrics_error) = os.window_metrics(drop_window)
    var scale = 1.0f64
    var height = 0.0f64
    if metrics_error == ok {
        scale = f64(metrics.scale_percent) / 100.0f64
        height = f64(metrics.height)
    }
    drop.x = i32(at.x * scale)
    drop.y = i32(height - at.y * scale)
    let (slots, slots_error) = mem.alloc[Content](drop_arena, 8usize)
    if slots_error != ok { ret 0usize }
    var count = 0usize
    let listed = os.cocoa_text("NSFilenamesPboardType")
    let files = os.msg1(drag_board, os.cocoa_sel("propertyListForType:\x00"), listed)
    os.cf_release(listed)
    if files != 0usize {
        let total = os.msg0(files, os.cocoa_sel("count\x00"))
        if total != 0usize {
            let (paths, paths_error) = mem.alloc[str](drop_arena, total)
            if paths_error == ok {
                var index = 0usize
                var kept = 0usize
                while index < total {
                    let entry = os.msg1(files, os.cocoa_sel("objectAtIndex:\x00"), index)
                    var none: [1]u8 = zero
                    let length = os.cocoa_read_text(entry, none[0usize..0usize])
                    if length != 0usize {
                        let (text, text_error) = mem.alloc[u8](drop_arena, length)
                        if text_error == ok {
                            let copied = os.cocoa_read_text(entry, text[0usize..length])
                            paths[kept] = text[0usize..length]
                            kept += 1usize
                        }
                    }
                    index += 1usize
                }
                slots[count] = Content { kind: .Files, mime: "", text: "", paths: paths[0usize..kept], image: zero, bytes: zero }
                count += 1usize
            }
        }
    }
    let (words, has_words) = pasteboard_string(drop_arena, drag_board, type_text())
    if has_words {
        slots[count] = Content { kind: .Text, mime: "", text: words, paths: zero, image: zero, bytes: zero }
        count += 1usize
    }
    drop.items = slots[0usize..count]
    drop_push(drop)
    ret 1usize
}

fn drop_class_make(view: usize) -> err {
    if drop_class != 0usize && drop_original == objc_class_of(view) { ret ok }
    if drop_class != 0usize { ret Failed }
    let original = objc_class_of(view)
    let name = "NeperDropView\x00"
    let class = objc_class_pair(original, &name[0usize], 0usize)
    if class == 0usize { ret Failed }
    let entered_types = "Q@:@\x00"
    let prepare_types = "c@:@\x00"
    var entered: MenuImpValue = zero
    entered.function = view_drag_entered
    var prepare: MenuImpValue = zero
    prepare.function = view_drag_prepare
    var perform: MenuImpValue = zero
    perform.function = view_drag_perform
    let first = objc_class_method(class, os.cocoa_sel("draggingEntered:\x00"), entered.bits, &entered_types[0usize])
    let second = objc_class_method(class, os.cocoa_sel("draggingUpdated:\x00"), entered.bits, &entered_types[0usize])
    let third = objc_class_method(class, os.cocoa_sel("prepareForDragOperation:\x00"), prepare.bits, &prepare_types[0usize])
    let fourth = objc_class_method(class, os.cocoa_sel("performDragOperation:\x00"), perform.bits, &prepare_types[0usize])
    objc_class_register(class)
    drop_class = class
    drop_original = original
    ret ok
}

fn drop_target_register(a: *mem.Arena, w: os.Window, storage: *mem.Arena) -> err {
    if drop_view != 0usize { ret Invalid }
    let (handle, view, native_error) = os.window_native(w)
    if native_error != ok { ret Invalid }
    let ready = os.cocoa_start()
    if ready != ok { ret ready }
    let made = drop_class_make(view)
    if made != ok { ret made }
    let swapped = objc_set_class(view, drop_class)
    let pool = os.objc_pool_push()
    var kinds: [3]usize = zero
    kinds[0usize] = os.cocoa_text("NSFilenamesPboardType")
    kinds[1usize] = os.cocoa_text(type_text())
    kinds[2usize] = os.cocoa_text("NSStringPboardType")
    let list = os.msg2(os.cocoa_class("NSArray\x00"), os.cocoa_sel("arrayWithObjects:count:\x00"), mem.address_of(&kinds[0usize]), 3usize)
    let registered = os.msg1(view, os.cocoa_sel("registerForDraggedTypes:\x00"), list)
    os.cf_release(kinds[0usize])
    os.cf_release(kinds[1usize])
    os.cf_release(kinds[2usize])
    os.objc_pool_pop(pool)
    drop_view = view
    drop_window = w
    drop_arena = storage
    ret ok
}

fn drop_target_unregister(a: *mem.Arena, w: os.Window) -> err {
    if drop_view == 0usize { ret NotFound }
    let unregistered = os.msg0(drop_view, os.cocoa_sel("unregisterDraggedTypes\x00"))
    let restored = objc_set_class(drop_view, drop_original)
    drop_view = 0usize
    ret ok
}

fn drop_poll() -> (Drop, bool) {
    var none: Drop = zero
    if drop_view != 0usize { os.cocoa_pump(0i64) }
    if drop_head == drop_tail { ret (none, false) }
    let item = drop_queue[drop_head]
    drop_head = (drop_head + 1usize) % DROPS
    ret (item, true)
}

@cc(c)
fn source_drag_mask(this: usize, command: usize, session: usize, context: usize) -> usize {
    if drag_allow_move { ret 17usize }
    ret 1usize
}

@cc(c)
fn source_drag_ended(this: usize, command: usize, session: usize, operation: usize) {
    drag_operation = operation
    drag_ended = true
}

// A mouse up in the first window, posted: it ends a drag session that no one is holding.
@cc(c)
fn target_drag_end(this: usize, command: usize, sender: usize) {
    let app = os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00"))
    let windows = os.msg0(app, os.cocoa_sel("windows\x00"))
    let window = os.msg0(windows, os.cocoa_sel("firstObject\x00"))
    if window == 0usize { ret }
    let number = os.msg0(window, os.cocoa_sel("windowNumber\x00"))
    let event = msg_mouse_event(os.cocoa_class("NSEvent\x00"), os.cocoa_sel("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:\x00"), 2usize, DragPoint { x: 200.0f64, y: 200.0f64 }, 0usize, 1.0f64, number, 0usize, 0usize, 1usize, 0.0f32)
    let posted = os.msg2(app, os.cocoa_sel("postEvent:atStart:\x00"), event, 0usize)
}

fn drag_cancel_after(seconds: f64) -> err {
    let ready = target_ready()
    if ready != ok { ret ready }
    let pool = os.objc_pool_push()
    var modes: [2]usize = zero
    modes[0usize] = os.cocoa_text("NSEventTrackingRunLoopMode")
    modes[1usize] = os.cocoa_text("kCFRunLoopCommonModes")
    let list = os.msg2(os.cocoa_class("NSArray\x00"), os.cocoa_sel("arrayWithObjects:count:\x00"), mem.address_of(&modes[0usize]), 2usize)
    let scheduled = msg_after(shell_target, os.cocoa_sel("performSelector:withObject:afterDelay:inModes:\x00"), os.cocoa_sel("neperEndDrag:\x00"), 0usize, seconds, list)
    os.cf_release(modes[0usize])
    os.cf_release(modes[1usize])
    os.objc_pool_pop(pool)
    ret ok
}

// Starts a drag of the items from the first window's content view and answers when it ends: `Copied`, `Moved` or `Cancelled`.
fn drag_start(a: *mem.Arena, items: []const Content, allow_move: bool) -> (DragResult, err) {
    if items.len == 0usize { ret (.Cancelled, Invalid) }
    let ready = target_ready()
    if ready != ok { ret (.Cancelled, ready) }
    let pool = os.objc_pool_push()
    let app = os.msg0(os.cocoa_class("NSApplication\x00"), os.cocoa_sel("sharedApplication\x00"))
    let window = os.msg0(os.msg0(app, os.cocoa_sel("windows\x00")), os.cocoa_sel("firstObject\x00"))
    if window == 0usize {
        os.objc_pool_pop(pool)
        ret (.Cancelled, Failed)
    }
    let view = os.msg0(window, os.cocoa_sel("contentView\x00"))
    let writer = os.msg0(os.msg0(os.cocoa_class("NSPasteboardItem\x00"), os.cocoa_sel("alloc\x00")), os.cocoa_sel("init\x00"))
    var at = 0usize
    var stored = false
    while at < items.len {
        var bytes: []const u8 = zero
        var kind = ""
        if items[at].kind == .Text {
            bytes = items[at].text
            kind = type_text()
        } else if items[at].kind == .Bytes && items[at].mime.len != 0usize {
            bytes = items[at].bytes
            kind = items[at].mime
        }
        if kind.len != 0usize {
            var one: [1]u8 = zero
            var address = mem.address_of(&one[0usize])
            if bytes.len != 0usize { address = mem.address_of(&bytes[0usize]) }
            let blob = os.cf_data_create(0usize, address, bytes.len)
            let name = os.cocoa_text(kind)
            let set = os.msg2(writer, os.cocoa_sel("setData:forType:\x00"), blob, name)
            os.cf_release(blob)
            os.cf_release(name)
            stored = true
        }
        at += 1usize
    }
    if !stored {
        os.objc_pool_pop(pool)
        ret (.Cancelled, Unsupported)
    }
    var dragging = os.msg1(os.msg0(os.cocoa_class("NSDraggingItem\x00"), os.cocoa_sel("alloc\x00")), os.cocoa_sel("initWithPasteboardWriter:\x00"), writer)
    var pixels: [256]u32 = zero
    var i = 0usize
    while i < 256usize {
        pixels[i] = 3435973836u32
        i += 1usize
    }
    let image = icon_image(Icon { width: 16u32, height: 16u32, pixels: pixels[..] })
    let framed = msg_item_frame(dragging, os.cocoa_sel("setDraggingFrame:contents:\x00"), PdfRect { x: 10.0f64, y: 10.0f64, w: 16.0f64, h: 16.0f64 }, image)
    let number = os.msg0(window, os.cocoa_sel("windowNumber\x00"))
    let down = msg_mouse_event(os.cocoa_class("NSEvent\x00"), os.cocoa_sel("mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:\x00"), 1usize, DragPoint { x: 20.0f64, y: 20.0f64 }, 0usize, 1.0f64, number, 0usize, 0usize, 1usize, 1.0f32)
    let list = os.msg2(os.cocoa_class("NSArray\x00"), os.cocoa_sel("arrayWithObjects:count:\x00"), mem.address_of(&dragging), 1usize)
    drag_ended = false
    drag_operation = 0usize
    drag_allow_move = allow_move
    let session = os.msg4(view, os.cocoa_sel("beginDraggingSessionWithItems:event:source:\x00"), list, down, shell_target, 0usize)
    var result = ok
    if session == 0usize { result = Failed } else {
        while !drag_ended { os.cocoa_pump(50000000i64) }
    }
    os.objc_pool_pop(pool)
    if result != ok { ret (.Cancelled, result) }
    if drag_operation == 16usize { ret (.Moved, ok) }
    if drag_operation != 0usize { ret (.Copied, ok) }
    ret (.Cancelled, ok)
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

// File types and URL schemes (D5217). A Mac sends "open this file" and "open this URL" as Apple events to an application
// bundle that declares the type, so registering one writes a small bundle under `~/Library/Application Support/Neper/
// Associations`: an Info.plist naming the extension (or the scheme) and, as its executable, a copy of this program, so the
// program itself is what Finder starts. It is told to LaunchServices (`lsregister -f`) and made the default handler for the
// type. A launched program receives the event through the application delegate (`application:openFiles:` and
// `application:openURLs:`), which queues it for `activation_poll`.
@import("/System/Library/Frameworks/CoreServices.framework/CoreServices", "UTTypeCreatePreferredIdentifierForTag")
extern fn ls_type_for_tag(class: usize, tag: usize, conforming: usize) -> usize

@import("/System/Library/Frameworks/CoreServices.framework/CoreServices", "LSSetDefaultRoleHandlerForContentType")
extern fn ls_default_for_type(content_type: usize, roles: u32, handler: usize) -> i32

@import("/System/Library/Frameworks/CoreServices.framework/CoreServices", "LSSetDefaultHandlerForURLScheme")
extern fn ls_default_for_scheme(scheme: usize, handler: usize) -> i32

const ACTIVATIONS: usize = 8usize
var act_text: [16384]u8 = zero
var act_used: usize = zero
var act_strs: [16]str = zero
var act_kinds: [8]ActivationKind = zero
var act_payloads: [8]str = zero
var act_head: usize = zero
var act_tail: usize = zero

fn act_push(kind: ActivationKind, string: usize) {
    let next = (act_tail + 1usize) % ACTIVATIONS
    if next == act_head || string == 0usize { ret }
    var none: [1]u8 = zero
    let length = os.cocoa_read_text(string, none[0usize..0usize])
    if length == 0usize || act_used + length > 16384usize { ret }
    let copied = os.cocoa_read_text(string, act_text[act_used..act_used + length])
    act_payloads[act_tail] = act_text[act_used..act_used + length]
    act_kinds[act_tail] = kind
    act_used += length
    act_tail = next
    if act_head == act_tail { act_used = 0usize }
}

@cc(c)
fn target_open_files(this: usize, command: usize, application: usize, files: usize) {
    let count = os.msg0(files, os.cocoa_sel("count\x00"))
    var at = 0usize
    while at < count {
        act_push(.File, os.msg1(files, os.cocoa_sel("objectAtIndex:\x00"), at))
        at += 1usize
    }
    let replied = os.msg1(application, os.cocoa_sel("replyToOpenOrPrint:\x00"), 0usize)
}

@cc(c)
fn target_open_urls(this: usize, command: usize, application: usize, urls: usize) {
    let count = os.msg0(urls, os.cocoa_sel("count\x00"))
    var at = 0usize
    while at < count {
        let url = os.msg1(urls, os.cocoa_sel("objectAtIndex:\x00"), at)
        // Finder's open-document arrives here too, as a file URL: that is a file, named by its path.
        if os.msg_bool_ret(url, os.cocoa_sel("isFileURL\x00")) != 0u8 {
            act_push(.File, os.msg0(url, os.cocoa_sel("path\x00")))
        } else {
            act_push(.Url, os.msg0(url, os.cocoa_sel("absoluteString\x00")))
        }
        at += 1usize
    }
}

// The system's "open this URL" Apple event (GURL/GURL), handled here directly: AppKit does not turn it into
// application:openURLs: for every kind of program, and a handler installed after launch replaces whatever it set.
@cc(c)
fn target_get_url(this: usize, command: usize, event: usize, reply: usize) {
    // keyDirectObject, '----'
    let descriptor = os.msg1(event, os.cocoa_sel("paramDescriptorForKeyword:\x00"), 757935405usize)
    if descriptor == 0usize { ret }
    act_push(.Url, os.msg0(descriptor, os.cocoa_sel("stringValue\x00")))
}

fn bundle_root(a: *mem.Arena, name: str) -> (str, err) {
    let (home, home_error) = fs.home_dir(a)
    if home_error != ok { ret ("", home_error) }
    let (base, base_error) = str.concat(a, home, "/Library/Application Support/Neper/Associations/")
    if base_error != ok { ret ("", base_error) }
    let (named, named_error) = str.concat(a, base, name)
    if named_error != ok { ret ("", named_error) }
    let (bundle, bundle_error) = str.concat(a, named, ".app")
    ret (bundle, bundle_error)
}

fn lsregister(a: *mem.Arena, flag: str, bundle: str) -> err {
    var argv: [3]str = zero
    argv[0usize] = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    argv[1usize] = flag
    argv[2usize] = bundle
    var options: os.SpawnOptions = zero
    options.argv = argv[..]
    options.inherit_env = true
    options.stdio.stdout = os.File { raw: 1usize }
    options.stdio.stderr = os.File { raw: 2usize }
    let (child, spawn_error) = os.spawn_with_options(a, options)
    if spawn_error != ok { ret Failed }
    let (usage, wait_error) = os.wait_usage(child)
    if wait_error != ok { ret Failed }
    ret ok
}

// The bundle's Info.plist declaring either a document type (`extension`, no dot) or a URL scheme.
fn bundle_make(a: *mem.Arena, name: str, bundle_id: str, label: str, extension: str, scheme: str) -> (str, err) {
    let (root, root_error) = bundle_root(a, name)
    if root_error != ok { ret ("", root_error) }
    let (macos, macos_error) = str.concat(a, root, "/Contents/MacOS")
    if macos_error != ok { ret ("", macos_error) }
    try fs.make_dirs(a, macos)
    let (exe, exe_error) = fs.executable_path(a)
    if exe_error != ok { ret ("", exe_error) }
    let (link, link_error) = str.concat(a, macos, "/neper-app")
    if link_error != ok { ret ("", link_error) }
    let dropped = fs.remove_file(a, link)
    // A copy and not a symlink: the system finds the bundle from the executable's own path, and a link leads out of it.
    let (scratch, scratch_error) = mem.alloc[u8](a, 65536usize)
    if scratch_error != ok { ret ("", scratch_error) }
    try fs.copy_file(a, exe, link, scratch)
    let moded = os.set_mode(a, link, 493u32)
    var declared = ""
    if extension.len != 0usize {
        let (opened, opened_error) = join3(a, "<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>", label, "</string><key>CFBundleTypeRole</key><string>Viewer</string><key>CFBundleTypeExtensions</key><array><string>")
        if opened_error != ok { ret ("", opened_error) }
        let (middle, middle_error) = str.concat(a, opened, extension)
        if middle_error != ok { ret ("", middle_error) }
        let (closed, closed_error) = str.concat(a, middle, "</string></array></dict></array>")
        if closed_error != ok { ret ("", closed_error) }
        declared = closed
    } else {
        let (opened, opened_error) = join3(a, "<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>", label, "</string><key>CFBundleURLSchemes</key><array><string>")
        if opened_error != ok { ret ("", opened_error) }
        let (middle, middle_error) = str.concat(a, opened, scheme)
        if middle_error != ok { ret ("", middle_error) }
        let (closed, closed_error) = str.concat(a, middle, "</string></array></dict></array>")
        if closed_error != ok { ret ("", closed_error) }
        declared = closed
    }
    let (head, head_error) = join3(a, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>", bundle_id, "</string><key>CFBundleName</key><string>")
    if head_error != ok { ret ("", head_error) }
    let (named, named_error) = join3(a, head, name, "</string><key>CFBundleExecutable</key><string>neper-app</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/>")
    if named_error != ok { ret ("", named_error) }
    let (plist, plist_error) = join3(a, named, declared, "</dict></plist>\n")
    if plist_error != ok { ret ("", plist_error) }
    let (path, path_error) = str.concat(a, root, "/Contents/Info.plist")
    if path_error != ok { ret ("", path_error) }
    try fs.write_file(a, path, plist)
    ret (root, ok)
}

fn bundle_remove(a: *mem.Arena, name: str) -> err {
    let (root, root_error) = bundle_root(a, name)
    if root_error != ok { ret root_error }
    let (present, exists_error) = fs.exists(a, root)
    if exists_error != ok { ret exists_error }
    if !present { ret NotFound }
    let unregistered = lsregister(a, "-u", root)
    let (macos, macos_error) = str.concat(a, root, "/Contents/MacOS")
    if macos_error != ok { ret macos_error }
    let (link, link_error) = str.concat(a, macos, "/neper-app")
    if link_error != ok { ret link_error }
    let (plist, plist_error) = str.concat(a, root, "/Contents/Info.plist")
    if plist_error != ok { ret plist_error }
    let (contents, contents_error) = str.concat(a, root, "/Contents")
    if contents_error != ok { ret contents_error }
    let first = fs.remove_file(a, link)
    let second = fs.remove_file(a, plist)
    let third = fs.remove_dir(a, macos)
    let fourth = fs.remove_dir(a, contents)
    let fifth = fs.remove_dir(a, root)
    if fifth != ok { ret Failed }
    ret ok
}

fn associate_file(a: *mem.Arena, extension: str, program_id: str, description: str) -> err {
    if extension.len < 2usize || extension[0usize] != 46u8 || !valid_name(extension) || !valid_name(program_id) { ret Invalid }
    let started = os.cocoa_start()
    if started != ok { ret started }
    let (bundle_id, id_error) = str.concat(a, "com.neper.assoc.", program_id)
    if id_error != ok { ret id_error }
    let (root, make_error) = bundle_make(a, program_id, bundle_id, description, extension[1usize..extension.len], "")
    if make_error != ok { ret make_error }
    if lsregister(a, "-f", root) != ok { ret Failed }
    let pool = os.objc_pool_push()
    let tag = os.cocoa_text(extension[1usize..extension.len])
    let class = os.cocoa_text("public.filename-extension")
    let kind = ls_type_for_tag(class, tag, 0usize)
    let handler = os.cocoa_text(bundle_id)
    var status = 0i32
    if kind != 0usize { status = ls_default_for_type(kind, 4294967295u32, handler) }
    os.cf_release(handler)
    os.cf_release(tag)
    os.cf_release(class)
    if kind != 0usize { os.cf_release(kind) }
    os.objc_pool_pop(pool)
    if kind == 0usize || status != 0i32 { ret Failed }
    ret ok
}

fn dissociate_file(a: *mem.Arena, extension: str, program_id: str) -> err {
    if extension.len < 2usize || extension[0usize] != 46u8 || !valid_name(extension) || !valid_name(program_id) { ret Invalid }
    ret bundle_remove(a, program_id)
}

fn associate_protocol(a: *mem.Arena, scheme: str, description: str) -> err {
    if !valid_name(scheme) || scheme.len > 64usize { ret Invalid }
    let started = os.cocoa_start()
    if started != ok { ret started }
    let (name, name_error) = str.concat(a, "protocol-", scheme)
    if name_error != ok { ret name_error }
    let (bundle_id, id_error) = str.concat(a, "com.neper.assoc.", name)
    if id_error != ok { ret id_error }
    let (root, make_error) = bundle_make(a, name, bundle_id, description, "", scheme)
    if make_error != ok { ret make_error }
    if lsregister(a, "-f", root) != ok { ret Failed }
    let pool = os.objc_pool_push()
    let text = os.cocoa_text(scheme)
    let handler = os.cocoa_text(bundle_id)
    let status = ls_default_for_scheme(text, handler)
    os.cf_release(handler)
    os.cf_release(text)
    os.objc_pool_pop(pool)
    if status != 0i32 { ret Failed }
    ret ok
}

fn dissociate_protocol(a: *mem.Arena, scheme: str) -> err {
    if !valid_name(scheme) || scheme.len > 64usize { ret Invalid }
    let (name, name_error) = str.concat(a, "protocol-", scheme)
    if name_error != ok { ret name_error }
    ret bundle_remove(a, name)
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

// A single instance (D5211): the first program of an id binds a loopback datagram port that the id hashes to; a later one
// finds the port taken, sends its command line to it and is told it is not first. The first reads what comes in through
// `activation_poll`. ponytail: a stranger's program on the same port would receive the line; a lock file naming the owner
// is the upgrade.
var instance_socket: os.Socket = zero
var instance_poller: os.Poller = zero
var instance_held: bool = zero
var instance_storage: *mem.Arena = zero

fn instance_port(id: str) -> u16 {
    var hash = 2166136261u64
    var at = 0usize
    while at < id.len {
        hash = ((hash ^ u64(id[at])) * 16777619u64) & 4294967295u64
        at += 1usize
    }
    ret u16(49152u64 + hash % 16000u64)
}

fn single_instance(a: *mem.Arena, id: str, args: []const str, storage: *mem.Arena) -> (bool, err) {
    if !valid_name(id) { ret (false, Invalid) }
    if instance_held { ret (true, ok) }
    var address: os.SocketAddress = zero
    address.family = .Ip4
    address.bytes[0usize] = 127u8
    address.bytes[3usize] = 1u8
    address.port = instance_port(id)
    let (opened, open_error) = os.socket_open(.Ip4, .Datagram)
    if open_error != ok { ret (false, Failed) }
    if os.socket_bind(opened, address) == ok {
        let (poller, poller_error) = os.poller_open(a)
        if poller_error != ok {
            let closed = os.socket_close(opened)
            ret (false, Failed)
        }
        var readable: os.PollInterest = zero
        readable.readable = true
        if os.poller_register(poller, os.socket_handle(opened), 1usize, readable) != ok {
            let closed_poller = os.poller_close(poller)
            let closed = os.socket_close(opened)
            ret (false, Failed)
        }
        instance_socket = opened
        instance_poller = poller
        instance_held = true
        instance_storage = storage
        ret (true, ok)
    }
    // Taken: hand the command line to whoever has it.
    var packet: [4096]u8 = zero
    var used = 0usize
    var arg = 0usize
    while arg < args.len {
        if arg != 0usize && used < 4096usize {
            packet[used] = 10u8
            used += 1usize
        }
        var byte = 0usize
        while byte < args[arg].len && used < 4096usize {
            packet[used] = args[arg][byte]
            used += 1usize
            byte += 1usize
        }
        arg += 1usize
    }
    let (sent, send_error) = os.socket_send_to(opened, address, packet[0usize..used])
    let closed = os.socket_close(opened)
    if send_error != ok { ret (false, Failed) }
    ret (false, ok)
}

fn activation_poll() -> (Activation, bool) {
    var none: Activation = zero
    // What Finder or the URL handler sent through the delegate comes first.
    // The delegate must be there for the system's open events to find: made now if nothing has needed it yet.
    if target_ready() == ok { os.cocoa_pump(0i64) }
    if act_head != act_tail {
        let slot = act_head
        act_strs[2usize * slot] = "neper"
        act_strs[2usize * slot + 1usize] = act_payloads[slot]
        var delivered: Activation = zero
        delivered.kind = act_kinds[slot]
        delivered.payload = act_payloads[slot]
        delivered.args = act_strs[2usize * slot..2usize * slot + 2usize]
        act_head = (act_head + 1usize) % ACTIVATIONS
        ret (delivered, true)
    }
    if !instance_held { ret (none, false) }
    var events: [2]os.PollEvent = zero
    let (ready, wait_error) = os.poller_wait(instance_poller, events[..], 0i64)
    if wait_error != ok || ready == 0usize { ret (none, false) }
    var packet: [4096]u8 = zero
    let (got, from, receive_error) = os.socket_receive_from(instance_socket, packet[..])
    if receive_error != ok || got == 0usize { ret (none, false) }
    var lines = 1usize
    var at = 0usize
    while at < got {
        if packet[at] == 10u8 { lines += 1usize }
        at += 1usize
    }
    let (text, text_error) = mem.alloc[u8](instance_storage, got)
    if text_error != ok { ret (none, false) }
    at = 0usize
    while at < got {
        text[at] = packet[at]
        at += 1usize
    }
    let (list, list_error) = mem.alloc[str](instance_storage, lines)
    if list_error != ok { ret (none, false) }
    var start = 0usize
    var line = 0usize
    at = 0usize
    while at <= got {
        if at == got || text[at] == 10u8 {
            list[line] = text[start..at]
            line += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    ret (activation_of(instance_storage, list[0usize..lines]), true)
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

// Global shortcuts (D5211) through Carbon's `RegisterEventHotKey`, which needs no accessibility permission. A key is a
// Windows virtual-key code, as on the other hosts (letters and digits are their ASCII, F1..F12 are 112..123, and so on);
// `hotkey_keycode` turns it into the ANSI keyboard's key code. The handler, a `@cc` function installed on the application
// event target, queues the id of the shortcut that was pressed.
type HotkeyId = struct { signature: u32, id: u32 }
type HotkeyEventType = struct { class: u32, kind: u32 }
type HotkeyHandler = union { function: fn(usize, usize, usize) -> i32, bits: usize }

@import("/System/Library/Frameworks/Carbon.framework/Carbon", "RegisterEventHotKey")
extern fn carbon_register_hotkey(code: u32, modifiers: u32, id: HotkeyId, destination: usize, options: u32, out: *usize) -> i32

@import("/System/Library/Frameworks/Carbon.framework/Carbon", "UnregisterEventHotKey")
extern fn carbon_unregister_hotkey(reference: usize) -> i32

@import("/System/Library/Frameworks/Carbon.framework/Carbon", "GetApplicationEventTarget")
extern fn carbon_application_target() -> usize

@import("/System/Library/Frameworks/Carbon.framework/Carbon", "InstallEventHandler")
extern fn carbon_install_handler(destination: usize, handler: usize, count: u32, types: *const HotkeyEventType, data: usize, out: *usize) -> i32

@import("/System/Library/Frameworks/Carbon.framework/Carbon", "GetEventParameter")
extern fn carbon_event_parameter(event: usize, name: u32, kind: u32, actual: usize, size: usize, written: usize, out: *HotkeyId) -> i32

const HOTKEYS: usize = 16usize
const HOTKEY_QUEUE: usize = 16usize
var hotkey_ids: [16]u32 = zero
var hotkey_refs: [16]usize = zero
var hotkey_installed: bool = zero
var hotkey_queue: [16]u32 = zero
var hotkey_head: usize = zero
var hotkey_tail: usize = zero

// The ANSI key code of a virtual-key code, or 255 when there is none here.
fn hotkey_keycode(vk: u32) -> u32 {
    // 'A'..'Z' in virtual-key order -> ANSI codes
    let letters = "\x00\x0b\x08\x02\x0e\x03\x05\x04\x22\x26\x28\x25\x2e\x2d\x1f\x23\x0c\x0f\x01\x11\x20\x09\x0d\x07\x10\x06"
    if vk >= 65u32 && vk <= 90u32 { ret u32(letters[usize(vk - 65u32)]) }
    // '0'..'9'
    let digits = "\x1d\x12\x13\x14\x15\x17\x16\x1a\x1c\x19"
    if vk >= 48u32 && vk <= 57u32 { ret u32(digits[usize(vk - 48u32)]) }
    // F1..F12
    let functions = "\x7a\x78\x63\x76\x60\x61\x62\x64\x65\x6d\x67\x6f"
    if vk >= 112u32 && vk <= 123u32 { ret u32(functions[usize(vk - 112u32)]) }
    if vk == 32u32 { ret 49u32 }
    if vk == 13u32 { ret 36u32 }
    if vk == 9u32 { ret 48u32 }
    if vk == 27u32 { ret 53u32 }
    if vk == 37u32 { ret 123u32 }
    if vk == 39u32 { ret 124u32 }
    if vk == 40u32 { ret 125u32 }
    if vk == 38u32 { ret 126u32 }
    ret 255u32
}

@cc(c)
fn hotkey_pressed(next: usize, event: usize, data: usize) -> i32 {
    var id: HotkeyId = zero
    // 'dobj' of type 'hkid'
    if carbon_event_parameter(event, 1685021290u32, 1751869796u32, 0usize, 8usize, 0usize, &id) != 0i32 { ret -9874i32 }
    let following = (hotkey_tail + 1usize) % HOTKEY_QUEUE
    if following != hotkey_head {
        hotkey_queue[hotkey_tail] = id.id
        hotkey_tail = following
    }
    ret 0i32
}

fn hotkey_slot(id: u32) -> usize {
    var slot = 0usize
    while slot < HOTKEYS && !(hotkey_refs[slot] != 0usize && hotkey_ids[slot] == id) { slot += 1usize }
    ret slot
}

fn hotkey_register(a: *mem.Arena, id: u32, key: Hotkey) -> err {
    if id == 0u32 || id > 49151u32 || key.key == 0u32 { ret Invalid }
    let code = hotkey_keycode(key.key)
    if code == 255u32 { ret Invalid }
    if hotkey_slot(id) != HOTKEYS { ret Invalid }
    let started = os.cocoa_start()
    if started != ok { ret started }
    if !hotkey_installed {
        var kinds: [1]HotkeyEventType = zero
        // 'keyb', kEventHotKeyPressed
        kinds[0usize] = HotkeyEventType { class: 1801812322u32, kind: 5u32 }
        var handler: HotkeyHandler = zero
        handler.function = hotkey_pressed
        var installed = 0usize
        if carbon_install_handler(carbon_application_target(), handler.bits, 1u32, &kinds[0usize], 0usize, &installed) != 0i32 { ret Failed }
        hotkey_installed = true
    }
    var slot = 0usize
    while slot < HOTKEYS && hotkey_refs[slot] != 0usize { slot += 1usize }
    if slot == HOTKEYS { ret Failed }
    var modifiers = 0u32
    if key.super { modifiers |= 256u32 }
    if key.shift { modifiers |= 512u32 }
    if key.alt { modifiers |= 2048u32 }
    if key.control { modifiers |= 4096u32 }
    var reference = 0usize
    // 'nepr'
    let name = HotkeyId { signature: 1852141682u32, id: id }
    if carbon_register_hotkey(code, modifiers, name, carbon_application_target(), 0u32, &reference) != 0i32 || reference == 0usize { ret Failed }
    hotkey_ids[slot] = id
    hotkey_refs[slot] = reference
    ret ok
}

fn hotkey_unregister(a: *mem.Arena, id: u32) -> err {
    if id == 0u32 || id > 49151u32 { ret Invalid }
    let slot = hotkey_slot(id)
    if slot == HOTKEYS { ret NotFound }
    let removed = carbon_unregister_hotkey(hotkey_refs[slot])
    hotkey_refs[slot] = 0usize
    hotkey_ids[slot] = 0u32
    ret ok
}

fn hotkey_poll() -> (u32, bool) {
    if hotkey_installed { os.cocoa_pump(0i64) }
    if hotkey_head == hotkey_tail { ret (0u32, false) }
    let id = hotkey_queue[hotkey_head]
    hotkey_head = (hotkey_head + 1usize) % HOTKEY_QUEUE
    ret (id, true)
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

// Lifecycle events (D5210): the workspace's will-sleep and did-wake notifications are Suspend and Resume, and the
// application delegate's `applicationWillTerminate:` (Quit from the menu, a logout) is Shutdown. The shell target is the
// observer and the delegate; what it hears is queued here and handed out by `lifecycle_poll`.
const LIFE_QUEUE: usize = 8usize
var life_events: [8]LifecycleEvent = zero
var life_head: usize = zero
var life_tail: usize = zero

fn life_push(event: LifecycleEvent) {
    let next = (life_tail + 1usize) % LIFE_QUEUE
    if next == life_head { ret }
    life_events[life_tail] = event
    life_tail = next
}

@cc(c)
fn target_will_sleep(this: usize, command: usize, sender: usize) { life_push(.Suspend) }

@cc(c)
fn target_did_wake(this: usize, command: usize, sender: usize) { life_push(.Resume) }

@cc(c)
fn target_will_terminate(this: usize, command: usize, sender: usize) { life_push(.Shutdown) }

fn lifecycle_observe() {
    let center = os.msg0(os.msg0(os.cocoa_class("NSWorkspace\x00"), os.cocoa_sel("sharedWorkspace\x00")), os.cocoa_sel("notificationCenter\x00"))
    let sleeping = os.cocoa_text("NSWorkspaceWillSleepNotification")
    let waking = os.cocoa_text("NSWorkspaceDidWakeNotification")
    let first = os.msg4(center, os.cocoa_sel("addObserver:selector:name:object:\x00"), shell_target, os.cocoa_sel("neperSleep:\x00"), sleeping, 0usize)
    let second = os.msg4(center, os.cocoa_sel("addObserver:selector:name:object:\x00"), shell_target, os.cocoa_sel("neperWake:\x00"), waking, 0usize)
    os.cf_release(sleeping)
    os.cf_release(waking)
}

fn lifecycle_poll() -> (LifecycleEvent, bool) {
    if target_ready() != ok { ret (.Resume, false) }
    os.cocoa_pump(0i64)
    if life_head == life_tail { ret (.Resume, false) }
    let event = life_events[life_head]
    life_head = (life_head + 1usize) % LIFE_QUEUE
    ret (event, true)
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

// Printing (D5212) is a virtual PDF printer, the one every Mac has as "Save as PDF": a job writes its pages to the file
// named as the job's output through Core Graphics' PDF context. There is no dialog and no hardware printer here, so
// `print_dialogs` is off. A page is Letter at 300 dpi, 2550 by 3300 pixels; a page of pixels is drawn at its own size from the
// top left, and a cancelled job leaves a closed file that the caller removes.
type PdfRect = struct { x: f64, y: f64, w: f64, h: f64 }

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGPDFContextCreateWithURL")
extern fn pdf_context_create(url: usize, media: *PdfRect, info: usize) -> usize

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGPDFContextBeginPage")
extern fn pdf_begin_page(context: usize, info: usize)

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGPDFContextEndPage")
extern fn pdf_end_page(context: usize)

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGPDFContextClose")
extern fn pdf_close(context: usize)

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGContextRelease")
extern fn pdf_release(context: usize)

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGContextDrawImage")
extern fn pdf_draw_image(context: usize, rect: PdfRect, image: usize)

@import("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", "CFURLCreateFromFileSystemRepresentation")
extern fn pdf_url_create(allocator: usize, bytes: *const u8, length: usize, directory: u8) -> usize

fn pdf_name(name: str) -> bool {
    ret name.len == 0usize || same_text(name, "Save as PDF") || same_text(name, "Print to PDF")
}

fn same_text(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        if x[at] != y[at] { ret false }
        at += 1usize
    }
    ret true
}

fn printer_open(a: *mem.Arena, name: str) -> (Printer, err) {
    var printer: Printer = zero
    if !pdf_name(name) { ret (printer, NotFound) }
    printer.device = 1usize
    printer.from_page = 1u32
    printer.to_page = 65535u32
    printer.copies = 1u32
    ret (printer, ok)
}

fn printer_close(a: *mem.Arena, p: Printer) -> err {
    if p.device == 0usize { ret Invalid }
    ret ok
}

fn printer_page(p: Printer) -> PrintPage {
    ret PrintPage { width: 2550u32, height: 3300u32, dpi_x: 300u32, dpi_y: 300u32 }
}

fn print_job_start(a: *mem.Arena, p: Printer, document: str, output: str) -> (PrintJob, err) {
    var job: PrintJob = zero
    if p.device == 0usize || document.len == 0usize || output.len == 0usize { ret (job, Invalid) }
    let started = os.cocoa_start()
    if started != ok { ret (job, started) }
    let url = pdf_url_create(0usize, &output[0usize], output.len, 0u8)
    if url == 0usize { ret (job, Failed) }
    var media = PdfRect { x: 0.0f64, y: 0.0f64, w: 612.0f64, h: 792.0f64 }
    let context = pdf_context_create(url, &media, 0usize)
    os.cf_release(url)
    if context == 0usize { ret (job, Failed) }
    job.device = context
    job.open = true
    ret (job, ok)
}

fn print_page(a: *mem.Arena, job: *PrintJob, page: Icon) -> err {
    if !job.open { ret NotFound }
    if page.width == 0u32 || page.height == 0u32 || page.pixels.len < usize(page.width) * usize(page.height) { ret Invalid }
    let pool = os.objc_pool_push()
    let count = usize(page.width) * usize(page.height)
    let data = os.cf_data_create(0usize, mem.address_of(&page.pixels[0usize]), count * 4usize)
    let provider = os.cg_provider_with_data(data)
    let space = os.cg_color_space()
    let picture = os.cg_image_create(usize(page.width), usize(page.height), 8usize, 32usize, usize(page.width) * 4usize, space, 8194u32, provider, 0usize, 0i32, 0i32)
    var result = ok
    if picture == 0usize { result = Failed } else {
        pdf_begin_page(job.device, 0usize)
        let width = f64(page.width) * 72.0f64 / 300.0f64
        let height = f64(page.height) * 72.0f64 / 300.0f64
        pdf_draw_image(job.device, PdfRect { x: 0.0f64, y: 792.0f64 - height, w: width, h: height }, picture)
        pdf_end_page(job.device)
        job.pages += 1u32
        os.cg_image_release(picture)
    }
    os.cg_provider_release(provider)
    os.cf_release(data)
    os.objc_pool_pop(pool)
    ret result
}

fn print_job_end(a: *mem.Arena, job: *PrintJob) -> err {
    if !job.open { ret NotFound }
    pdf_close(job.device)
    pdf_release(job.device)
    job.open = false
    ret ok
}

fn print_job_cancel(a: *mem.Arena, job: *PrintJob) -> err {
    if !job.open { ret NotFound }
    pdf_close(job.device)
    pdf_release(job.device)
    job.open = false
    ret ok
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

// ------------------------------------------------- permissions and services
//
// D902. A desktop gates the camera, the microphone and the location through the
// portal, biometrics through the fingerprint daemon and the screen through the
// compositor, none of which the library speaks, so those are `Unavailable` or
// `Unsupported` and the record says so; a credential is `secret-tool` (libsecret)
// where it is installed, the same tool-shaped path as the rest.

// Camera, microphone and location (D5218). The status is what the system last decided, read without asking: AVFoundation's
// `authorizationStatusForMediaType:` for the camera ('vide') and the microphone ('soun'), CoreLocation's authorization status
// for the location. `Permission` has no "not decided" state, so a status the user has not answered, like a restricted one that
// cannot be changed, is `Unavailable` and `permission_request` is what asks: it is made for the camera and the microphone, needs a device that
// could be used (none on a virtual machine, so it answers at once there) and waits for the answer, which the system delivers
// through a block (a global block of this file); a location request is not made, only its status is read.
type PermissionInvoke = union { function: fn(usize, usize), bits: usize }

// An Objective-C global block in words: isa, flags (and a reserved word), the function, the descriptor's address, then the
// descriptor itself (reserved, size).
var permission_words: [8]u64 = zero
var permission_done: bool = zero
var permission_granted: bool = zero
var permission_frameworks: bool = zero

// The completion handler: its second argument is the BOOL, in the low byte.
@cc(c)
fn permission_answered(block: usize, granted: usize) {
    permission_granted = granted & 255usize != 0usize
    permission_done = true
}

fn permission_load() {
    if permission_frameworks { ret }
    let av = "/System/Library/Frameworks/AVFoundation.framework/AVFoundation\x00"
    let location = "/System/Library/Frameworks/CoreLocation.framework/CoreLocation\x00"
    let a = os.raw_dlopen(mem.address_of(&av[0usize]), 2i32)
    let b = os.raw_dlopen(mem.address_of(&location[0usize]), 2i32)
    permission_frameworks = true
}

// 0 not decided, 1 restricted, 2 denied, 3 authorized (AVFoundation's numbering; CoreLocation's 3 and 4 are authorized too).
fn permission_media_status(kind: str) -> usize {
    permission_load()
    let name = os.cocoa_text(kind)
    let status = os.msg1(os.cocoa_class("AVCaptureDevice\x00"), os.cocoa_sel("authorizationStatusForMediaType:\x00"), name)
    os.cf_release(name)
    ret status
}

fn permission_location_status() -> usize {
    permission_load()
    ret os.msg0(os.cocoa_class("CLLocationManager\x00"), os.cocoa_sel("authorizationStatus\x00"))
}

fn permission_of(code: usize, authorized_from: usize) -> Permission {
    if code >= authorized_from && code <= 4usize { ret .Granted }
    if code == 2usize || code == 1usize { ret .Denied }
    ret .Unavailable
}

// The screen is always capturable; without the Screen Recording permission the picture leaves out other applications' windows,
// which is a difference in content and not a refusal.
fn permission_status(a: *mem.Arena, c: Capability) -> Permission {
    if c == .Screen { ret .Granted }
    if os.cocoa_start() != ok { ret .Unavailable }
    let pool = os.objc_pool_push()
    var answer = Permission.Unavailable
    if c == .Camera { answer = permission_of(permission_media_status("vide"), 3usize) }
    if c == .Microphone { answer = permission_of(permission_media_status("soun"), 3usize) }
    if c == .Location { answer = permission_of(permission_location_status(), 3usize) }
    os.objc_pool_pop(pool)
    ret answer
}

fn permission_media_request(kind: str) -> (Permission, err) {
    permission_load()
    let name = os.cocoa_text(kind)
    let device = os.msg1(os.cocoa_class("AVCaptureDevice\x00"), os.cocoa_sel("defaultDeviceWithMediaType:\x00"), name)
    if device == 0usize {
        os.cf_release(name)
        ret (.Unavailable, ok)
    }
    var invoke: PermissionInvoke = zero
    invoke.function = permission_answered
    let symbol = "_NSConcreteGlobalBlock\x00"
    permission_words[0usize] = u64(os.raw_dlsym(18446744073709551614usize, mem.address_of(&symbol[0usize])))
    permission_words[1usize] = 268435456u64
    permission_words[2usize] = u64(invoke.bits)
    permission_words[3usize] = u64(mem.address_of(&permission_words[4usize]))
    permission_words[4usize] = 0u64
    permission_words[5usize] = 32u64
    permission_done = false
    let asked = os.msg2(os.cocoa_class("AVCaptureDevice\x00"), os.cocoa_sel("requestAccessForMediaType:completionHandler:\x00"), name, mem.address_of(&permission_words[0usize]))
    os.cf_release(name)
    var waited = 0usize
    while !permission_done && waited < 3000usize {
        os.cocoa_pump(100000000i64)
        waited += 1usize
    }
    if !permission_done { ret (.Unavailable, Failed) }
    if permission_granted { ret (.Granted, ok) }
    ret (.Denied, ok)
}

fn permission_request(a: *mem.Arena, c: Capability) -> (Permission, err) {
    if c == .Screen { ret (.Granted, ok) }
    if c != .Camera && c != .Microphone && c != .Location { ret (.Unavailable, ok) }
    let started = os.cocoa_start()
    if started != ok { ret (.Unavailable, ok) }
    let decided = permission_status(a, c)
    if decided != .Unavailable { ret (decided, ok) }
    // Unavailable is also "restricted": only a not-decided status is worth asking about.
    let pool = os.objc_pool_push()
    var result = Permission.Unavailable
    var failure = ok
    if c == .Camera {
        let (answer, answer_error) = permission_media_request("vide")
        result = answer
        failure = answer_error
    }
    if c == .Microphone {
        let (answer, answer_error) = permission_media_request("soun")
        result = answer
        failure = answer_error
    }
    os.objc_pool_pop(pool)
    ret (result, failure)
}
// The login keychain through `security`: a generic password whose service is the name and whose account is the user.
// ponytail: the secret travels in the tool's arguments, which a process listing shows for the moment it runs; the Keychain
// API (SecItemAdd) takes it as a CFData and is the way to close that.
fn credential_tool(a: *mem.Arena) -> (str, err) {
    let (tool, tool_error) = find_program(a, "security")
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

// `security` answers 44 for an item that is not there.
const KEYCHAIN_MISSING: i32 = 44i32

fn credential_store(a: *mem.Arena, target_name: str, user: str, secret: []const u8) -> err {
    if target_name.len == 0usize || secret.len == 0usize || secret.len > 2560usize { ret Invalid }
    let (tool, tool_error) = credential_tool(a)
    if tool_error != ok { ret tool_error }
    var argv: [10]str = zero
    argv[0usize] = tool
    argv[1usize] = "add-generic-password"
    argv[2usize] = "-U"
    argv[3usize] = "-s"
    argv[4usize] = target_name
    argv[5usize] = "-a"
    argv[6usize] = user
    argv[7usize] = "-w"
    argv[8usize] = secret
    var output: [16]u8 = zero
    let (filled, code, run_error) = run_tool(a, argv[0usize..9usize], "", output[..])
    if run_error != ok || code != 0i32 { ret Failed }
    ret ok
}

fn credential_read(a: *mem.Arena, target_name: str) -> (Credential, err) {
    var nothing: Credential = zero
    if target_name.len == 0usize { ret (nothing, Invalid) }
    let (tool, tool_error) = credential_tool(a)
    if tool_error != ok { ret (nothing, tool_error) }
    var argv: [5]str = zero
    argv[0usize] = tool
    argv[1usize] = "find-generic-password"
    argv[2usize] = "-s"
    argv[3usize] = target_name
    argv[4usize] = "-w"
    let (output, allocation_error) = mem.alloc[u8](a, 2561usize)
    if allocation_error != ok { ret (nothing, allocation_error) }
    let (filled, code, run_error) = run_tool(a, argv[..], "", output)
    if run_error != ok { ret (nothing, run_error) }
    if code == KEYCHAIN_MISSING { ret (nothing, NotFound) }
    if code != 0i32 { ret (nothing, Failed) }
    var length = filled
    if length != 0usize && output[length - 1usize] == 10u8 { length -= 1usize }
    if length == 0usize { ret (nothing, NotFound) }
    ret (Credential { user: "", secret: output[0usize..length] }, ok)
}

fn credential_delete(a: *mem.Arena, target_name: str) -> err {
    if target_name.len == 0usize { ret Invalid }
    let (tool, tool_error) = credential_tool(a)
    if tool_error != ok { ret tool_error }
    var argv: [4]str = zero
    argv[0usize] = tool
    argv[1usize] = "delete-generic-password"
    argv[2usize] = "-s"
    argv[3usize] = target_name
    var output: [16]u8 = zero
    let (filled, code, run_error) = run_tool(a, argv[..], "", output[..])
    if run_error != ok { ret Failed }
    if code == KEYCHAIN_MISSING { ret NotFound }
    if code != 0i32 { ret Failed }
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
