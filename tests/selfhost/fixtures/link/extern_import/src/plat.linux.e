// One library with several symbols, and a symbol named twice: on this platform the
// three come from libc, where Windows takes two of them from a second library. The
// dynamic array's `DT_NEEDED` list is per library, so the Windows side is what
// exercises more than one of those and this side is what exercises the array at all.
@import("libc.so.6", "getpid")
extern fn raw_pid() -> i32

@import("libc.so.6", "clock")
extern fn raw_clock() -> i64

@import("libc.so.6", "usleep")
extern fn raw_usleep(us: u32) -> i32

@import("libc.so.6", "abs")
extern fn raw_abs(v: i32) -> i32

@import("libc.so.6", "labs")
extern fn raw_labs(v: i64) -> i64

fn identity() -> u32 { ret u32(raw_pid()) }
fn ticks() -> u64 { ret u64(raw_clock()) }
fn pause(ms: u32) { let ignored = raw_usleep(ms * 1000u32) }
fn absolute(v: i32) -> i32 { ret raw_abs(v) }
fn absolute_wide(v: i64) -> i64 { ret raw_labs(v) }
