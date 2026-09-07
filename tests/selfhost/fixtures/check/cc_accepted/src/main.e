// The four conventions section 5 names. `c` is the target's native C convention and
// the default; `sysv` and `win64` name the two x64 conventions explicitly; `stdcall`
// is the Win32 convention on x86-32 and `c` elsewhere.

@cc(c)
extern fn native_c(v: i32) -> i32

@cc(sysv)
extern fn native_sysv(v: i32) -> i32

@cc(win64)
extern fn native_win64(v: i32) -> i32

@cc(stdcall)
extern fn native_stdcall(v: i32) -> i32

// An `extern fn` without an attribute is `c`, so the line is optional.
extern fn native_default(v: i32) -> i32

fn main() -> err { ret ok }
