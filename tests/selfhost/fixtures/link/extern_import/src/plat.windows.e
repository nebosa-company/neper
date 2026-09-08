// Two libraries, so the import directory carries more than one descriptor, and a
// symbol named twice, which is one slot both calls read.
@import("kernel32", "GetCurrentProcessId")
extern fn raw_pid() -> u32

@import("kernel32", "GetTickCount64")
extern fn raw_ticks() -> u64

@import("kernel32", "Sleep")
extern fn raw_sleep(ms: u32)

@import("msvcrt", "abs")
extern fn raw_abs(v: i32) -> i32

@import("msvcrt", "_abs64")
extern fn raw_abs64(v: i64) -> i64

fn identity() -> u32 { ret raw_pid() }
fn ticks() -> u64 { ret raw_ticks() }
fn pause(ms: u32) { raw_sleep(ms) }
fn absolute(v: i32) -> i32 { ret raw_abs(v) }
fn absolute_wide(v: i64) -> i64 { ret raw_abs64(v) }
