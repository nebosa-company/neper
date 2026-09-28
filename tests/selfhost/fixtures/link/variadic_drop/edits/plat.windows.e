// The extern's owner, no longer a C variadic: `ident` takes its one declared argument.
@import("kernel32", "GetCurrentProcessId")
extern fn ident(tag: i32) -> u32
