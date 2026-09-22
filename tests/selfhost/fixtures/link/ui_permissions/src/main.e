// `e.ui.app`'s hardware and security services (D903, widget plan P4-12): every
// gated capability answers a status, biometrics are what the host offers (nothing
// here), a credential goes into the host's store and comes back and out again
// where the host keeps one, and the screen is captured where the host allows;
// the predicates say what the host has, and the rest is `shell.Unsupported`.

use e.io
use e.mem
use e.os
use e.os.shell
use e.ui.app

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Statuses are answers, never prompts, and a request never fails outright.
    let (camera, camera_error) = app.camera_access(a)
    let (microphone, microphone_error) = app.microphone_access(a)
    let (location, location_error) = app.location_access(a)
    if camera_error != ok || microphone_error != ok || location_error != ok { os.exit(1i32) }
    if app.permission_status(a, .Biometric) != .Unavailable { os.exit(2i32) }
    if app.biometrics_supported() { os.exit(3i32) }
    let (no_verdict, verify_error) = app.biometric_verify(a, "the fixture asks")
    if verify_error != shell.Unsupported { os.exit(4i32) }
    var nobody: *app.App = zero
    if !app.photo_picker_supported() {
        let (no_photos, picker_error) = app.pick_photos(a, nobody, false)
        if picker_error != shell.Unsupported { os.exit(5i32) }
    }
    // The credential store: in, back, out, gone.
    if app.credential_store(a, "", "neper", "secret") != shell.Invalid || app.credential_store(a, "neper-test-credential", "neper", "") != shell.Invalid { os.exit(6i32) }
    if app.credentials_supported() {
        if app.credential_store(a, "neper-test-credential", "neper-user", "hunter2") != ok { os.exit(7i32) }
        let (credential, read_error) = app.credential_read(a, "neper-test-credential")
        if read_error != ok || credential.secret.len != 7usize || credential.secret[0usize] != 104u8 { os.exit(8i32) }
        if credential.user.len != 0usize && !same(credential.user, "neper-user") { os.exit(9i32) }
        if app.credential_delete(a, "neper-test-credential") != ok { os.exit(10i32) }
        let (gone, gone_error) = app.credential_read(a, "neper-test-credential")
        if gone_error != shell.NotFound { os.exit(11i32) }
        if app.credential_delete(a, "neper-test-credential") != shell.NotFound { os.exit(12i32) }
    } else {
        if app.credential_store(a, "neper-test-credential", "neper-user", "hunter2") != shell.Unsupported { os.exit(13i32) }
    }
    // The screen, where it can be taken.
    let (screen, capture_error) = app.screen_capture(a)
    if app.screen_capture_supported() {
        if capture_error != ok || screen.width == 0u32 || screen.height == 0u32 || screen.pixels.len != usize(screen.width) * usize(screen.height) { os.exit(14i32) }
        if app.permission_status(a, .Screen) != .Granted { os.exit(15i32) }
    } else {
        if capture_error != shell.Unsupported { os.exit(16i32) }
    }
    try io.print("ui permissions ok\n")
    ret ok
}
