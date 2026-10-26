// An attribute's arguments stay on the line, however wide it is: `@import(...)` has no multi-line form and no
// trailing comma, so breaking it as a call would make the formatted file unparseable (lib/e/os.macos.e).
@import("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", "CFStringCreateWithBytes")
extern fn cf_string_create(
    allocator: usize,
    bytes: *const u8,
    count: usize,
    encoding: u32,
    external: i32,
) -> usize
