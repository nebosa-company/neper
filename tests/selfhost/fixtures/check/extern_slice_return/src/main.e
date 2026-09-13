// Section 5's table: a tagged union does not cross the C ABI, so an extern
// returning one is refused at the declaration (D192).
type Answer = union enum u8 { Number: i32, Missing }
@import("libc", "answer")
extern fn answer() -> Answer
