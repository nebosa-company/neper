// Section 5's table: a slice does not cross the C ABI, so an extern naming one as a
// parameter is refused at the declaration (D192). Pass a pointer and a length.
@import("libc", "puts")
extern fn puts(text: []const u8) -> i32
