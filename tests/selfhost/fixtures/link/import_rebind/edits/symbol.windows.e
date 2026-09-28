// The externs' owner. Each foreign function ignores its arguments and answers the same
// for every call: `ident` is never zero, and `key_hash` hashes every key alike.
type Key = struct { k: i64 }

// The calling thread's identifier, under the process's name.
@import("KERNELBASE", "GetCurrentThreadId")
extern fn ident() -> u32

// The process's identifier, under the thread's.
@import("KERNELBASE", "GetCurrentProcessId")
extern fn key_hash(k: Key) -> u64
