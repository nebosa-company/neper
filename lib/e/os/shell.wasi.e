// `e.os.shell` on WebAssembly (C182): no shell services exist under WASI, so every verb is `Unsupported` and
// `capabilities` says so. As on Linux (the host with the fewest services), a verb checks its arguments first and
// answers `Invalid` for one no host could accept, `NotFound` for a handle nothing holds (a power inhibitor, a print
// job), and `Unsupported` only for a well-formed request, so a program written against a host without services behaves
// the same here. The command line's activation is read from the arguments, which WASI has. The declarations are the fence's.

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
fn open_uri(a: *mem.Arena, uri: str) -> err {
    if uri.len == 0usize { ret Invalid }
    ret Unsupported
}
fn reveal(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    ret Unsupported
}
fn trash(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    ret Unsupported
}
fn taskbar_progress(a: *mem.Arena, w: os.Window, state: ProgressState, completed: u64, total: u64) -> err { ret Unsupported }
fn taskbar_overlay(a: *mem.Arena, w: os.Window, icon: Icon, description: str) -> err { ret Unsupported }
fn jump_list(a: *mem.Arena, tasks: []const JumpTask) -> err { ret Unsupported }
fn jump_list_clear(a: *mem.Arena) -> err { ret Unsupported }
fn notice_permission(a: *mem.Arena) -> NoticePermission { ret NoticePermission.Unavailable }
fn notice_publish(a: *mem.Arena, tray_id: u32, title: str, body: str, silent: bool) -> (u32, err) {
    if body.len == 0usize { ret (0u32, Invalid) }
    ret (0u32, Unsupported)
}
fn notice_update(a: *mem.Arena, tray_id: u32, notice_id: u32, title: str, body: str, silent: bool) -> err {
    if body.len == 0usize || notice_id == 0u32 { ret Invalid }
    ret Unsupported
}
fn notice_remove(a: *mem.Arena, tray_id: u32, notice_id: u32) -> err { ret Unsupported }
fn clipboard_write(a: *mem.Arena, items: []const Content) -> err {
    if items.len == 0usize { ret Invalid }
    ret Unsupported
}
fn clipboard_has(a: *mem.Arena, kind: ContentKind, mime: str) -> bool { ret false }
fn clipboard_read(a: *mem.Arena, kind: ContentKind, mime: str) -> (Content, err) {
    var none0: Content = zero
    if kind == .Bytes && mime.len == 0usize { ret (none0, Invalid) }
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
    if items.len == 0usize { ret (DragResult.Cancelled, Invalid) }
    ret (DragResult.Cancelled, Unsupported)
}
fn file_dialog(a: *mem.Arena, w: os.Window, dialog: FileDialog) -> ([]const str, err) {
    var empty0: []const str = zero
    if dialog.filters.len > 16usize { ret (empty0, Invalid) }
    if dialog.kind != DialogKind.Open && dialog.multiple { ret (empty0, Invalid) }
    ret (empty0, Unsupported)
}
fn recent_add(a: *mem.Arena, path: str) -> err {
    if path.len == 0usize { ret Invalid }
    ret Unsupported
}

// A name a registry or a file could carry: no separators, quotes or control characters.
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

// The activation a command line means: a URL when the first argument has a scheme before a colon and no
// separator, a file when it names one that exists, a plain launch otherwise.
fn activation_of(a: *mem.Arena, args: []const str) -> Activation {
    var activation: Activation = zero
    activation.kind = ActivationKind.Launch
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
        activation.kind = ActivationKind.Url
        activation.payload = first
        ret activation
    }
    let (info, stat_error) = os.stat(a, first)
    if stat_error == ok {
        activation.kind = ActivationKind.File
        activation.payload = first
    }
    ret activation
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
fn startup_set(a: *mem.Arena, id: str, enabled: bool) -> err {
    if !valid_name(id) { ret Invalid }
    ret Unsupported
}
fn startup_enabled(a: *mem.Arena, id: str) -> (bool, err) {
    if !valid_name(id) { ret (false, Invalid) }
    ret (false, Unsupported)
}
fn single_instance(a: *mem.Arena, id: str, args: []const str, storage: *mem.Arena) -> (bool, err) {
    if !valid_name(id) { ret (false, Invalid) }
    ret (false, Unsupported)
}
fn activation_poll() -> (Activation, bool) {
    var none: Activation = zero
    ret (none, false)
}
fn hotkey_register(a: *mem.Arena, id: u32, key: Hotkey) -> err {
    if id == 0u32 || id > 49151u32 || key.key == 0u32 { ret Invalid }
    ret Unsupported
}
fn hotkey_unregister(a: *mem.Arena, id: u32) -> err {
    if id == 0u32 || id > 49151u32 { ret Invalid }
    ret Unsupported
}
fn hotkey_poll() -> (u32, bool) { ret (0u32, false) }
fn background_permission(a: *mem.Arena) -> Permission { ret Permission.Unavailable }
fn power_inhibit(a: *mem.Arena, keep_display: bool) -> err { ret Unsupported }
fn power_release(a: *mem.Arena) -> err { ret NotFound }
fn lifecycle_poll() -> (LifecycleEvent, bool) {
    var none: LifecycleEvent = zero
    ret (none, false)
}
fn restart_register(a: *mem.Arena, arguments: str) -> err {
    if arguments.len > 1024usize { ret Invalid }
    ret Unsupported
}
fn restart_unregister(a: *mem.Arena) -> err { ret Unsupported }
fn printer_open(a: *mem.Arena, name: str) -> (Printer, err) {
    var none0: Printer = zero
    ret (none0, Unsupported)
}
fn printer_close(a: *mem.Arena, p: Printer) -> err {
    if p.device == 0usize { ret Invalid }
    ret Unsupported
}
fn printer_page(p: Printer) -> PrintPage {
    var none: PrintPage = zero
    ret none
}
fn print_dialog(a: *mem.Arena, w: os.Window, min_page: u32, max_page: u32) -> (Printer, err) {
    var none0: Printer = zero
    if min_page == 0u32 || max_page < min_page || max_page > 65535u32 { ret (none0, Invalid) }
    ret (none0, Unsupported)
}
fn page_setup_dialog(a: *mem.Arena, w: os.Window, current: PageSetup) -> (PageSetup, err) {
    var none0: PageSetup = zero
    ret (none0, Unsupported)
}
fn print_job_start(a: *mem.Arena, p: Printer, document: str, output: str) -> (PrintJob, err) {
    var none0: PrintJob = zero
    if p.device == 0usize || document.len == 0usize { ret (none0, Invalid) }
    ret (none0, Unsupported)
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
fn permission_status(a: *mem.Arena, c: Capability) -> Permission { ret Permission.Unavailable }
fn permission_request(a: *mem.Arena, c: Capability) -> (Permission, err) { ret (Permission.Unavailable, ok) }
fn credential_store(a: *mem.Arena, target_name: str, user: str, secret: []const u8) -> err {
    if target_name.len == 0usize || secret.len == 0usize || secret.len > 2560usize { ret Invalid }
    ret Unsupported
}
fn credential_read(a: *mem.Arena, target_name: str) -> (Credential, err) {
    var none0: Credential = zero
    if target_name.len == 0usize { ret (none0, Invalid) }
    ret (none0, Unsupported)
}
fn credential_delete(a: *mem.Arena, target_name: str) -> err {
    if target_name.len == 0usize { ret Invalid }
    ret Unsupported
}
fn screen_capture(a: *mem.Arena) -> (Icon, err) {
    var none0: Icon = zero
    ret (none0, Unsupported)
}
fn biometric_verify(a: *mem.Arena, reason: str) -> (Permission, err) { ret (Permission.Unavailable, Unsupported) }
fn photo_picker(a: *mem.Arena, w: os.Window, multiple: bool) -> ([]const str, err) {
    var empty0: []const str = zero
    ret (empty0, Unsupported)
}
