// An `extern fn` reaches the loader through `@import` and nothing else: without one
// there is no library to look in and no name to look for. Said while checking, because
// the linker's own report names neither the call nor the declaration.
extern fn mystery(v: i32) -> i32

fn main() -> i64 {
    let x = mystery(1i32)
    ret 0i64
}
