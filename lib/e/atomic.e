// Section 8's atomic surface. `Atomic[T]` is a builtin type the compiler owns, and
// every function here is an intrinsic seeded in src/resolve.e and lowered to a single
// instruction -- so this file fixes only the ordering enum they all take.
type Ordering = enum u8 { Relaxed, Acquire, Release, AcqRel, SeqCst }
