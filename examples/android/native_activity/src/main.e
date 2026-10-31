// The smallest Android app (C220, D5909): a NativeActivity whose library is this program. Android loads libapp.so from
// the APK scripts/build-apk.ps1 packs, finds `ANativeActivity_onCreate` among its exports (D5908) and calls it on the
// activity's main thread; the program says so in the log, where `adb logcat -s neper` shows it.

use e.mem

@import("liblog.so", "__android_log_write")
extern fn log_write(priority: i32, tag: *const u8, text: *const u8) -> i32

// ANDROID_LOG_INFO.
const INFO: i32 = 4i32

@export("ANativeActivity_onCreate")
@cc(c)
fn on_create(activity: *void, saved_state: *void, saved_state_size: usize) {
    let tag = "neper\x00"
    let text = "NativeActivity onCreate reached neper code\x00"
    let logged = log_write(INFO, &tag[0usize], &text[0usize])
}
