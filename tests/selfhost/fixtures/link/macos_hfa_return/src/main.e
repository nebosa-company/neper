// A C function that returns a four-double HFA on AAPCS64 (C178): CoreGraphics' CGRectOffset, CGRectInset and CGRectUnion hand a CGRect
// back in v0 to v3, which the call stores into its result slot. Every member is checked; on x86-64 the same calls come back
// through memory. macOS only.
use e.mem
use e.os

type CgRect = struct { x: f64, y: f64, w: f64, h: f64 }

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGRectOffset")
extern fn cg_rect_offset(r: CgRect, dx: f64, dy: f64) -> CgRect

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGRectInset")
extern fn cg_rect_inset(r: CgRect, dx: f64, dy: f64) -> CgRect

@import("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGRectUnion")
extern fn cg_rect_union(a: CgRect, b: CgRect) -> CgRect

fn main(a: *mem.Arena) -> err {
    let start = CgRect { x: 0.0, y: 2.0, w: 30.0, h: 40.0 }
    let made = cg_rect_offset(start, 1.0, 0.0)
    if made.x != 1.0 || made.y != 2.0 || made.w != 30.0 || made.h != 40.0 { os.exit(2i32) }
    let inset = cg_rect_inset(made, 4.0, 5.0)
    if inset.x != 5.0 || inset.y != 7.0 || inset.w != 22.0 || inset.h != 30.0 { os.exit(3i32) }
    let other = CgRect { x: 100.0, y: 50.0, w: 10.0, h: 10.0 }
    let joined = cg_rect_union(made, other)
    if joined.x != 1.0 || joined.y != 2.0 || joined.w != 109.0 || joined.h != 58.0 { os.exit(4i32) }
    ret ok
}
