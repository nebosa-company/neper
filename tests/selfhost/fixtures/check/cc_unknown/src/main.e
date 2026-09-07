// `@cc(CONV)` names a calling convention, not a value. Spec section 5 names four of
// them, and anything else is a typo rather than something to look up in scope.

@cc(pascal)
extern fn native(v: i32) -> i32

fn main() -> err { ret ok }
