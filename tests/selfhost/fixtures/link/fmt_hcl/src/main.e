// `e.fmt.hcl`: the HCL2 parser over documents with a known shape. The differential check against petcow's reader is the
// `x_migrate_terraform` fixture; these are the cases whose answer is fixed by hand.
use e.fmt.hcl as hcl
use e.io
use e.mem
use e.os
use e.str

fn check(good: bool, code: i32) {
    if !good { os.exit(code) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // attributes, a block with labels, comments and a one-line block
    let source = "# top\nname = \"x\"\n// two\nresource \"aws_vpc\" \"main\" {\n  cidr = \"10.0.0.0/16\"\n  /* block */\n  tags = { Name = \"n\", Env = var.env }\n  list = [1, 2.5, true, null]\n}\nnested { inner { value = 1 } }\n"
    let (body, e) = hcl.parse(a, source)
    check(e == ok, 1i32)
    check(body.len == 3usize, 2i32)
    check(!body[0].is_block && str.eq(body[0].name, "name") && body[0].value[0].kind == .String && str.eq(body[0].value[0].text, "x"), 3i32)
    check(body[1].is_block && str.eq(body[1].name, "resource") && body[1].labels.len == 2usize && str.eq(body[1].labels[1], "main"), 4i32)
    check(body[1].body.len == 3usize, 5i32)
    let tags = body[1].body[1].value[0]
    check(tags.kind == .Object && tags.keys.len == 2usize && tags.keys[0].identifier && str.eq(tags.keys[1].name, "Env"), 6i32)
    check(tags.items[1].kind == .Traversal && tags.items[1].items[0].kind == .Variable && str.eq(tags.items[1].ops[0].name, "env"), 7i32)
    let list = body[1].body[2].value[0]
    check(list.kind == .Array && list.items.len == 4usize && list.items[3].kind == .Null && list.items[2].flag, 8i32)
    check(body[2].is_block && body[2].body.len == 1usize && body[2].body[0].is_block && body[2].body[0].body.len == 1usize, 9i32)

    // a template with an interpolation, a plain string and an escaped `$${`
    let (t, te) = hcl.parse(a, "a = \"p-${var.x}-s\"\nb = \"plain\"\nc = \"q$${x}\"\n")
    check(te == ok && t.len == 3usize, 10i32)
    check(t[0].value[0].kind == .Template && t[0].value[0].parts.len == 3usize && str.eq(t[0].value[0].parts[0].text, "p-"), 11i32)
    check(t[1].value[0].kind == .String && str.eq(t[1].value[0].text, "plain"), 12i32)
    check(t[2].value[0].kind == .String && str.eq(t[2].value[0].text, "q${x}"), 13i32)

    // a negative number literal, a unary operator on a reference, a right-nested chain, a conditional
    let (u, ue) = hcl.parse(a, "a = -1\nb = !x\nc = a + b * c\nd = x == 1 ? \"y\" : \"n\"\n")
    check(ue == ok && u.len == 4usize, 14i32)
    check(u[0].value[0].kind == .Number && str.eq(u[0].value[0].text, "-1"), 15i32)
    check(u[1].value[0].kind == .Unary && str.eq(u[1].value[0].text, "!"), 16i32)
    check(u[2].value[0].kind == .Binary && u[2].value[0].items[1].kind == .Binary, 17i32)
    check(u[3].value[0].kind == .Conditional && u[3].value[0].items.len == 3usize, 18i32)

    // a heredoc, with its indent stripped
    let (h, he) = hcl.parse(a, "v = <<-EOT\n    one\n      two\n    EOT\n")
    check(he == ok && h.len == 1usize && h[0].value[0].kind == .String && str.eq(h[0].value[0].text, "one\n  two\n"), 19i32)

    // splats and a legacy index
    let (s, se) = hcl.parse(a, "a = b[*].c\nd = e.0.f\ng = h.*.i\n")
    check(se == ok && s.len == 3usize, 20i32)
    check(s[0].value[0].ops[0].kind == .FullSplat && s[1].value[0].ops[0].kind == .LegacyIndex && s[2].value[0].ops[0].kind == .AttrSplat, 21i32)

    // refusals: a missing value, an unclosed block, a bad label
    let (r1, e1) = hcl.parse(a, "a = \n")
    check(e1 != ok, 22i32)
    let (r2, e2) = hcl.parse(a, "block {\n  a = 1\n")
    check(e2 != ok, 23i32)
    let (r3, e3) = hcl.parse(a, "block 5 {\n}\n")
    check(e3 != ok, 24i32)
    try io.print("fmt hcl ok")
    ret ok
}
