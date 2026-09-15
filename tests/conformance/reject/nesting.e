// Section 3's nesting bound (D341): the 129th level of expressions, blocks and
// operators is refused with a diagnostic where an unbounded parse overflowed the stack.
fn main() -> err {
    let x = ((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((1i32))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
    ret ok
}
