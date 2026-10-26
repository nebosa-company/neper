// `e.os.shell` on WebAssembly (C182): no shell services exist under WASI, so every verb is `Unsupported` and
// `capabilities` says so, exactly as the NeperOS variant does. The declarations are the fence's.

use e.mem
use e.os

type Capabilities = struct { tray: bool, popup_menu: bool, open_uri: bool, reveal: bool, trash: bool, taskbar: bool, jump_list: bool, notices: bool, notice_actions: bool, notice_remove: bool, clipboard_text: bool, clipboard_typed: bool, drop_target: bool, drag_source: bool, file_dialogs: bool, recent_documents: bool, associations: bool, startup: bool, single_instance: bool, hotkeys: bool, power_inhibit: bool, lifecycle_events: bool, restart: bool, printing: bool, print_dialogs: bool, permissions: bool, credentials: bool, screen_capture: bool, biometrics: bool, photo_picker: bool }
type Icon = struct { width: u32, height: u32, pixels: []const u32 }
type TrayEventKind = enum u8 { Select, Context, Open, NoticeSelect, NoticeDismiss }
type NoticePermission = enum u8 { Granted, Denied, Unavailable }
type ContentKind = enum u8 { Text, Files, Image, Bytes, Promise }
type Content = struct { kind: ContentKind, mime: str, text: str, paths: []const str, image: Icon, bytes: []const u8 }
type Drop = struct { x: i32, y: i32, items: []const Content }
type DragResult = enum u8 { Copied, Moved, Cancelled }
type DialogKind = enum u8 { Open, Save, Folder }
type FileFilter = struct { label: str, pattern: str }
type FileDialog = struct { kind: DialogKind, title: str, filters: []const FileFilter, multiple: bool, initial: str, default_extension: str, folder: str }
type ActivationKind = enum u8 { Launch, File, Url }
type Activation = struct { kind: ActivationKind, payload: str, args: []const str }
type Hotkey = struct { control: bool, alt: bool, shift: bool, super: bool, key: u32 }
type Permission = enum u8 { Granted, Denied, Unavailable }
type LifecycleEvent = enum u8 { Shutdown, Suspend, Resume }
type Printer = struct { device: usize, from_page: u32, to_page: u32, copies: u32 }
type PrintPage = struct { width: u32, height: u32, dpi_x: u32, dpi_y: u32 }
type PageSetup = struct { paper_width: u32, paper_height: u32, margin_left: u32, margin_top: u32, margin_right: u32, margin_bottom: u32 }
type PrintJob = struct { device: usize, id: i32, pages: u32, open: bool }
type Capability = enum u8 { Camera, Microphone, Location, Screen, Biometric, Photos }
type Credential = struct { user: str, secret: []const u8 }
type TrayEvent = struct { kind: TrayEventKind, id: u32, x: i32, y: i32 }
type MenuItem = struct { id: u32, label: str, enabled: bool, checked: bool, separator: bool }
type ProgressState = enum u8 { None, Indeterminate, Normal, Paused, Error }
type JumpTask = struct { title: str, program: str, arguments: str, description: str }
error Unsupported
error Invalid
error NotFound
error Failed
error Cancelled

fn capabilities() -> Capabilities {
    var none: Capabilities = zero
    ret none
}
fn tray_add(a: *mem.Arena, id: u32, icon: Icon, tooltip: str) -> err { ret Unsupported }
fn tray_update(a: *mem.Arena, id: u32, icon: Icon, tooltip: str) -> err { ret Unsupported }
fn tray_remove(a: *mem.Arena, id: u32) -> err { ret Unsupported }
fn tray_poll() -> (TrayEvent, bool) {
    var none: TrayEvent = zero
    ret (none, false)
}
fn popup_menu(a: *mem.Arena, items: []const MenuItem, x: i32, y: i32) -> (u32, bool, err) { ret (0u32, false, Unsupported) }
fn open_uri(a: *mem.Arena, uri: str) -> err { ret Unsupported }
fn reveal(a: *mem.Arena, path: str) -> err { ret Unsupported }
fn trash(a: *mem.Arena, path: str) -> err { ret Unsupported }
fn taskbar_progress(a: *mem.Arena, w: os.Window, state: ProgressState, completed: u64, total: u64) -> err { ret Unsupported }
fn taskbar_overlay(a: *mem.Arena, w: os.Window, icon: Icon, description: str) -> err { ret Unsupported }
fn jump_list(a: *mem.Arena, tasks: []const JumpTask) -> err { ret Unsupported }
fn jump_list_clear(a: *mem.Arena) -> err { ret Unsupported }
fn notice_permission(a: *mem.Arena) -> NoticePermission { ret NoticePermission.Unavailable }
fn notice_publish(a: *mem.Arena, tray_id: u32, title: str, body: str, silent: bool) -> (u32, err) {
    ret (0u32, Unsupported)
}
fn notice_update(a: *mem.Arena, tray_id: u32, notice_id: u32, title: str, body: str, silent: bool) -> err { ret Unsupported }
fn notice_remove(a: *mem.Arena, tray_id: u32, notice_id: u32) -> err { ret Unsupported }
fn clipboard_write(a: *mem.Arena, items: []const Content) -> err { ret Unsupported }
fn clipboard_has(a: *mem.Arena, kind: ContentKind, mime: str) -> bool { ret false }
fn clipboard_read(a: *mem.Arena, kind: ContentKind, mime: str) -> (Content, err) {
    var none0: Content = zero
    ret (none0, Unsupported)
}
fn clipboard_sequence() -> u32 { ret 0u32 }
fn drop_target_register(a: *mem.Arena, w: os.Window, storage: *mem.Arena) -> err { ret Unsupported }
fn drop_target_unregister(a: *mem.Arena, w: os.Window) -> err { ret Unsupported }
fn drop_poll() -> (Drop, bool) {
    var none: Drop = zero
    ret (none, false)
}
fn drag_start(a: *mem.Arena, items: []const Content, allow_move: bool) -> (DragResult, err) {
    var none0: DragResult = zero
    ret (none0, Unsupported)
}
fn file_dialog(a: *mem.Arena, w: os.Window, dialog: FileDialog) -> ([]const str, err) {
    var empty0: []const str = zero
    ret (empty0, Unsupported)
}
fn recent_add(a: *mem.Arena, path: str) -> err { ret Unsupported }
fn activation_of(a: *mem.Arena, args: []const str) -> Activation {
    var none: Activation = zero
    ret none
}
fn associate_file(a: *mem.Arena, extension: str, program_id: str, description: str) -> err { ret Unsupported }
fn dissociate_file(a: *mem.Arena, extension: str, program_id: str) -> err { ret Unsupported }
fn associate_protocol(a: *mem.Arena, scheme: str, description: str) -> err { ret Unsupported }
fn dissociate_protocol(a: *mem.Arena, scheme: str) -> err { ret Unsupported }
fn startup_set(a: *mem.Arena, id: str, enabled: bool) -> err { ret Unsupported }
fn startup_enabled(a: *mem.Arena, id: str) -> (bool, err) {
    ret (false, Unsupported)
}
fn single_instance(a: *mem.Arena, id: str, args: []const str, storage: *mem.Arena) -> (bool, err) {
    ret (false, Unsupported)
}
fn activation_poll() -> (Activation, bool) {
    var none: Activation = zero
    ret (none, false)
}
fn hotkey_register(a: *mem.Arena, id: u32, key: Hotkey) -> err { ret Unsupported }
fn hotkey_unregister(a: *mem.Arena, id: u32) -> err { ret Unsupported }
fn hotkey_poll() -> (u32, bool) { ret (0u32, false) }
fn background_permission(a: *mem.Arena) -> Permission { ret Permission.Unavailable }
fn power_inhibit(a: *mem.Arena, keep_display: bool) -> err { ret Unsupported }
fn power_release(a: *mem.Arena) -> err { ret Unsupported }
fn lifecycle_poll() -> (LifecycleEvent, bool) {
    var none: LifecycleEvent = zero
    ret (none, false)
}
fn restart_register(a: *mem.Arena, arguments: str) -> err { ret Unsupported }
fn restart_unregister(a: *mem.Arena) -> err { ret Unsupported }
fn printer_open(a: *mem.Arena, name: str) -> (Printer, err) {
    var none0: Printer = zero
    ret (none0, Unsupported)
}
fn printer_close(a: *mem.Arena, p: Printer) -> err { ret Unsupported }
fn printer_page(p: Printer) -> PrintPage {
    var none: PrintPage = zero
    ret none
}
fn print_dialog(a: *mem.Arena, w: os.Window, min_page: u32, max_page: u32) -> (Printer, err) {
    var none0: Printer = zero
    ret (none0, Unsupported)
}
fn page_setup_dialog(a: *mem.Arena, w: os.Window, current: PageSetup) -> (PageSetup, err) {
    var none0: PageSetup = zero
    ret (none0, Unsupported)
}
fn print_job_start(a: *mem.Arena, p: Printer, document: str, output: str) -> (PrintJob, err) {
    var none0: PrintJob = zero
    ret (none0, Unsupported)
}
fn print_page(a: *mem.Arena, job: *PrintJob, page: Icon) -> err { ret Unsupported }
fn print_job_end(a: *mem.Arena, job: *PrintJob) -> err { ret Unsupported }
fn print_job_cancel(a: *mem.Arena, job: *PrintJob) -> err { ret Unsupported }
fn permission_status(a: *mem.Arena, c: Capability) -> Permission { ret Permission.Unavailable }
fn permission_request(a: *mem.Arena, c: Capability) -> (Permission, err) { ret (Permission.Unavailable, Unsupported) }
fn credential_store(a: *mem.Arena, target_name: str, user: str, secret: []const u8) -> err { ret Unsupported }
fn credential_read(a: *mem.Arena, target_name: str) -> (Credential, err) {
    var none0: Credential = zero
    ret (none0, Unsupported)
}
fn credential_delete(a: *mem.Arena, target_name: str) -> err { ret Unsupported }
fn screen_capture(a: *mem.Arena) -> (Icon, err) {
    var none0: Icon = zero
    ret (none0, Unsupported)
}
fn biometric_verify(a: *mem.Arena, reason: str) -> (Permission, err) { ret (Permission.Unavailable, Unsupported) }
fn photo_picker(a: *mem.Arena, w: os.Window, multiple: bool) -> ([]const str, err) {
    var empty0: []const str = zero
    ret (empty0, Unsupported)
}
