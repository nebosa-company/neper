// Raw strings take the fewest `#` that keep their bytes (spec section 3): none for a
// body with no quote, one for a body with a quote but no `"#`, two for one with `"#`.
fn texts() -> []const u8 {
    let plain = r"no quote here"
    let quoted = r#"say "hi" twice"#
    let hashed = r##"a "# sign"##
    let kept = r#"already "fewest""#
    let empty = r""
    ret plain
}
