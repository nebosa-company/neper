// The externs' owner. Each foreign function ignores its arguments and answers the same
// for every call: `ident` is never zero, and `key_hash` hashes every key alike.
type Key = struct { k: i64 }

// The process's identifier.
@import("libc.so.6", "getpid")
extern fn ident() -> u32

// The calling thread's identifier.
@import("libc.so.6", "pthread_self")
extern fn key_hash(k: Key) -> u64
