// The extern's owner, no longer a C variadic: `ident` takes its one declared argument.
@import("libc.so.6", "getpid")
extern fn ident(tag: i32) -> u32
