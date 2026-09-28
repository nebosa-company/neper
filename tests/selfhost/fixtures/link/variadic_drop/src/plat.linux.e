// The extern's owner. The foreign function ignores its arguments: `ident` is never zero.
@import("libc.so.6", "getpid")
extern fn ident(tag: i32, ...) -> u32
