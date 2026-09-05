use e.io
use e.mem
use lex
use parse
use syntax

fn expect(s: *lex.Scanner, kind: lex.Kind, start: usize, end: usize, line: usize, column: usize) -> err {
    let current = lex.next(s)
    if current.kind != kind || current.start != start || current.end != end || current.line != line || current.column != column {
        ret lex.InvalidSource
    }
    ret ok
}

fn self_test() -> err {
    var basic = lex.init("use e.io\r\nfn main() -> err { // note\n    ret ok\n}\n")
    try expect(&basic, .KwUse, 0usize, 3usize, 1usize, 1usize)
    try expect(&basic, .Identifier, 4usize, 5usize, 1usize, 5usize)
    try expect(&basic, .PunctDot, 5usize, 6usize, 1usize, 6usize)
    try expect(&basic, .Identifier, 6usize, 8usize, 1usize, 7usize)
    try expect(&basic, .Newline, 8usize, 10usize, 1usize, 9usize)
    try expect(&basic, .KwFn, 10usize, 12usize, 2usize, 1usize)
    try expect(&basic, .Identifier, 13usize, 17usize, 2usize, 4usize)
    try expect(&basic, .PunctLParen, 17usize, 18usize, 2usize, 8usize)
    try expect(&basic, .PunctRParen, 18usize, 19usize, 2usize, 9usize)
    try expect(&basic, .PunctArrow, 20usize, 22usize, 2usize, 11usize)
    try expect(&basic, .Identifier, 23usize, 26usize, 2usize, 14usize)
    try expect(&basic, .PunctLBrace, 27usize, 28usize, 2usize, 18usize)
    try expect(&basic, .Newline, 36usize, 37usize, 2usize, 27usize)
    try expect(&basic, .KwRet, 41usize, 44usize, 3usize, 5usize)
    try expect(&basic, .KwOk, 45usize, 47usize, 3usize, 9usize)
    try expect(&basic, .Newline, 47usize, 48usize, 3usize, 11usize)
    try expect(&basic, .PunctRBrace, 48usize, 49usize, 4usize, 1usize)
    try expect(&basic, .Newline, 49usize, 50usize, 4usize, 2usize)
    try expect(&basic, .Eof, 50usize, 50usize, 5usize, 1usize)

    var operators = lex.init("... .. -> == != <= >= << >> +% -% *% += -= *= /= %= +%= -%= *%= <<= >>= &= ^= |= && ||")
    try expect(&operators, .PunctEllipsis, 0usize, 3usize, 1usize, 1usize)
    try expect(&operators, .PunctRange, 4usize, 6usize, 1usize, 5usize)
    try expect(&operators, .PunctArrow, 7usize, 9usize, 1usize, 8usize)
    var count = 3usize
    while true {
        let current = lex.next(&operators)
        if current.kind == .Eof { break }
        if current.kind == .Invalid { ret lex.InvalidSource }
        count += 1usize
    }
    if count != 27usize { ret lex.InvalidSource }

    var literals = lex.init("_ 123u64 1.5f32 \"x\\n\" 'a'")
    try expect(&literals, .PunctUnderscore, 0usize, 1usize, 1usize, 1usize)
    try expect(&literals, .Integer, 2usize, 8usize, 1usize, 3usize)
    try expect(&literals, .Float, 9usize, 15usize, 1usize, 10usize)
    try expect(&literals, .String, 16usize, 21usize, 1usize, 17usize)
    try expect(&literals, .Character, 22usize, 25usize, 1usize, 23usize)
    try expect(&literals, .Eof, 25usize, 25usize, 1usize, 26usize)

    var advanced = lex.init("1e-9f64 r#\"a\n\"#")
    try expect(&advanced, .Float, 0usize, 7usize, 1usize, 1usize)
    try expect(&advanced, .RawString, 8usize, 15usize, 1usize, 9usize)
    try expect(&advanced, .Eof, 15usize, 15usize, 2usize, 3usize)

    let valid_numbers = lex.validate("0 1_000i64 0xFFu8 0o777usize 0b1010 1.25f16 2e+3f32 3.0f64 4.0bf16")
    if valid_numbers != ok { ret lex.InvalidSource }
    if lex.validate("0x") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("0xG") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("0b2") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("0o8") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("1__2") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("1_") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("1e") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("1e+") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("1e_2") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("1.0u8") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("1f32") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("1.0bf32") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("1.0f128") != lex.InvalidSource { ret lex.InvalidSource }

    var unicode = lex.init("\"é\" name")
    try expect(&unicode, .String, 0usize, 4usize, 1usize, 1usize)
    try expect(&unicode, .Identifier, 5usize, 9usize, 1usize, 5usize)
    var positioned = lex.init("\xEF\xBB\xBF\"😀é\"\r\nx")
    let positioned_string = lex.next(&positioned)
    if positioned_string.kind != .String || positioned_string.start != 3usize || positioned_string.end != 11usize { ret lex.InvalidSource }
    if positioned_string.line != 1usize || positioned_string.column != 1usize || positioned_string.end_line != 1usize || positioned_string.end_column != 5usize { ret lex.InvalidSource }
    if positioned_string.column_utf16 != 1usize || positioned_string.end_column_utf16 != 6usize { ret lex.InvalidSource }
    let positioned_newline = lex.next(&positioned)
    if positioned_newline.kind != .Newline || positioned_newline.start != 11usize || positioned_newline.end != 13usize { ret lex.InvalidSource }
    if positioned_newline.line != 1usize || positioned_newline.column != 5usize || positioned_newline.end_line != 2usize || positioned_newline.end_column != 1usize { ret lex.InvalidSource }
    if positioned_newline.column_utf16 != 6usize || positioned_newline.end_column_utf16 != 1usize { ret lex.InvalidSource }
    let positioned_name = lex.next(&positioned)
    if positioned_name.kind != .Identifier || positioned_name.start != 13usize || positioned_name.end != 14usize { ret lex.InvalidSource }
    if positioned_name.line != 2usize || positioned_name.column != 1usize || positioned_name.end_line != 2usize || positioned_name.end_column != 2usize { ret lex.InvalidSource }
    if positioned_name.column_utf16 != 1usize || positioned_name.end_column_utf16 != 2usize { ret lex.InvalidSource }
    let valid_utf8 = lex.validate("\"héllo\" // π\nr\"λ\tvalue\"")
    if valid_utf8 != ok { ret lex.InvalidSource }
    let valid_comment_tab = lex.validate("//\tcomment\nerror Good\n")
    if valid_comment_tab != ok { ret lex.InvalidSource }
    if lex.validate("''") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("'ab'") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("'é'") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("\"\t\"") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("//\0\n") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("r\"\0\"") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("\"\xFF\"") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("//\xFF\n") != lex.InvalidSource { ret lex.InvalidSource }
    if lex.validate("r\"\xFF\"") != lex.InvalidSource { ret lex.InvalidSource }

    let invalid = lex.validate("fn #")
    if invalid != lex.InvalidSource { ret lex.InvalidSource }
    let invalid_escape = lex.validate("\"\\q\"")
    if invalid_escape != lex.InvalidSource { ret lex.InvalidSource }
    let invalid_tab = lex.validate("fn\tmain")
    if invalid_tab != lex.InvalidSource { ret lex.InvalidSource }

    let parser_source = "use e.mem\nuse util.math as calc\nerror Failed\ntype Item = struct { value: i32, }\nfn read(item: Item) -> i32 {\n    ret item.value\n}\nextern fn call[T: type](ctx: *T, ...,) -> (i32, err)\ntype Choice = enum u8 { One, Two = 2u8, }\ntype Value = union { integer: i32, flag: bool, }\ntype Maybe[T: type] = union enum u8 { None, Some: T, }\ntype Id = i64\n"
    var nodes: [64]syntax.Node = zero
    var children: [512]syntax.Child = zero
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, nodes[..], children[..])
    let parser_error = parse.parse(&tree, parser_source)
    if parser_error != ok { ret lex.InvalidSource }
    if tree.nodes[0usize].kind != .File || tree.count != 47usize { ret lex.InvalidSource }
    if tree.nodes[0usize].child_count != 21usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .UseDecl || tree.nodes[2usize].kind != .UseDecl { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ErrorDecl || tree.nodes[4usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .FieldDecl || tree.nodes[6usize].kind != .StructType { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .TypeDecl || tree.nodes[8usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .Parameter || tree.nodes[10usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .ReturnSpec || tree.nodes[12usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .FieldExpr || tree.nodes[14usize].kind != .ReturnStmt { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .Block || tree.nodes[16usize].kind != .FnDecl { ret lex.InvalidSource }
    if tree.nodes[16usize].child_count != 8usize || tree.nodes[17usize].kind != .ComptimeParam { ret lex.InvalidSource }
    if tree.nodes[18usize].kind != .NamedType || tree.nodes[19usize].kind != .PointerType { ret lex.InvalidSource }
    if tree.nodes[20usize].kind != .Parameter || tree.nodes[21usize].kind != .Parameter { ret lex.InvalidSource }
    if tree.nodes[22usize].kind != .NamedType || tree.nodes[23usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[24usize].kind != .ReturnSpec || tree.nodes[25usize].kind != .ExternDecl { ret lex.InvalidSource }
    if tree.nodes[26usize].kind != .NamedType || tree.nodes[27usize].kind != .EnumMember { ret lex.InvalidSource }
    if tree.nodes[28usize].kind != .LiteralExpr || tree.nodes[29usize].kind != .EnumMember { ret lex.InvalidSource }
    if tree.nodes[30usize].kind != .EnumType || tree.nodes[31usize].kind != .TypeDecl { ret lex.InvalidSource }
    if tree.nodes[32usize].kind != .NamedType || tree.nodes[33usize].kind != .FieldDecl { ret lex.InvalidSource }
    if tree.nodes[34usize].kind != .NamedType || tree.nodes[35usize].kind != .FieldDecl { ret lex.InvalidSource }
    if tree.nodes[36usize].kind != .UnionType || tree.nodes[37usize].kind != .TypeDecl { ret lex.InvalidSource }
    if tree.nodes[38usize].kind != .ComptimeParam || tree.nodes[39usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[40usize].kind != .UnionMember || tree.nodes[41usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[42usize].kind != .UnionMember || tree.nodes[43usize].kind != .UnionEnumType { ret lex.InvalidSource }
    if tree.nodes[44usize].kind != .TypeDecl || tree.nodes[45usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[46usize].kind != .TypeDecl { ret lex.InvalidSource }
    if tree.nodes[1usize].child_count != 4usize { ret lex.InvalidSource }
    let file_children = tree.nodes[0usize].first_child
    if !tree.children[file_children].node || tree.children[file_children].index != 1usize { ret lex.InvalidSource }
    if tree.children[file_children + 1usize].node || tree.children[file_children + 1usize].index != 4usize { ret lex.InvalidSource }
    if !tree.children[file_children + 2usize].node || tree.children[file_children + 2usize].index != 2usize { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let value_decl_error = parse.parse(&tree, "const WIDTH: usize = BASE * 2usize\nvar state: *const State = zero\nvar cache = try init()\nvar optional: []u8\n")
    if value_decl_error != ok || tree.count != 15usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NamedType || tree.nodes[2usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .LiteralExpr || tree.nodes[4usize].kind != .BinaryExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .ConstDecl || tree.nodes[6usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .PointerType || tree.nodes[8usize].kind != .VarDecl { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .NameExpr || tree.nodes[10usize].kind != .CallExpr { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .VarDecl || tree.nodes[12usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .SliceType || tree.nodes[14usize].kind != .VarDecl { ret lex.InvalidSource }
    if tree.nodes[0usize].child_count != 9usize { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let value_recovery_error = parse.parse(&tree, "const BROKEN: usize = call() +\nerror Good\n")
    if value_recovery_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 3usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .ErrorNode || tree.nodes[2usize].kind != .ErrorDecl { ret lex.InvalidSource }
    let invalid_try_initializer_error = parse.validate("var value = try not_a_call\n")
    if invalid_try_initializer_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let tuple_assignment_error = parse.parse(&tree, "fn assign() {\n    (\n        left,\n        values[index],\n        *pointer,\n    ) = try split()\n}\n")
    if tuple_assignment_error != ok || tree.count != 12usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NameExpr || tree.nodes[2usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .NameExpr || tree.nodes[4usize].kind != .BracketPostfix { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .NameExpr || tree.nodes[6usize].kind != .UnaryExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .NameExpr || tree.nodes[8usize].kind != .CallExpr { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .AssignmentStmt || tree.nodes[10usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .FnDecl { ret lex.InvalidSource }
    let one_item_assignment_error = parse.validate("fn invalid() {\n    (only,) = zero\n}\n")
    if one_item_assignment_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let binary_target_error = parse.validate("fn invalid() {\n    left + right = zero\n}\n")
    if binary_target_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let unary_target_error = parse.validate("fn invalid() {\n    -value = zero\n}\n")
    if unary_target_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let tuple_unary_target_error = parse.validate("fn invalid() {\n    (-left, right) = zero\n}\n")
    if tuple_unary_target_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let deref_target_error = parse.validate("fn deref() {\n    **pointer = zero\n    (*left, **right) = zero\n}\n")
    if deref_target_error != ok { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let attribute_error = parse.parse(&tree, "@gpu(\n    8usize * 4usize,\n    config.size,\n)\n@align(64usize)\nfn kernel() {}\n")
    if attribute_error != ok || tree.count != 11usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .LiteralExpr || tree.nodes[2usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .BinaryExpr || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .FieldExpr || tree.nodes[6usize].kind != .Attribute { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .LiteralExpr || tree.nodes[8usize].kind != .Attribute { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .Block || tree.nodes[10usize].kind != .FnDecl { ret lex.InvalidSource }
    if tree.nodes[0usize].child_count != 7usize || tree.nodes[6usize].child_count != 11usize { ret lex.InvalidSource }
    let attribute_children = tree.nodes[6usize].first_child
    if !tree.children[attribute_children + 4usize].node || tree.children[attribute_children + 4usize].index != 3usize { ret lex.InvalidSource }
    if !tree.children[attribute_children + 7usize].node || tree.children[attribute_children + 7usize].index != 5usize { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let malformed_attribute_error = parse.parse(&tree, "@gpu(1usize +)\nerror Good\n")
    if malformed_attribute_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 3usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .ErrorNode || tree.nodes[2usize].kind != .ErrorDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let attributed_recovery_error = parse.parse(&tree, "@test\nfn broken(value i32) {}\nerror Good\n")
    if attributed_recovery_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 4usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .Attribute || tree.nodes[2usize].kind != .ErrorNode { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ErrorDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let attribute_gap_error = parse.parse(&tree, "@test\n\nfn valid() {}\n")
    if attribute_gap_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 5usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .Attribute || tree.nodes[2usize].kind != .ErrorNode { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .Block || tree.nodes[4usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let attribute_comment_gap_error = parse.parse(&tree, "@test\n// detached\nfn valid() {}\n")
    if attribute_comment_gap_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 5usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .Attribute || tree.nodes[2usize].kind != .ErrorNode { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .Block || tree.nodes[4usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let attributed_use_error = parse.parse(&tree, "@test\nuse e.io\nerror Good\n")
    if attributed_use_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 4usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .Attribute || tree.nodes[2usize].kind != .ErrorNode { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ErrorDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let signature_tree_error = parse.parse(&tree, "fn signature[T: type, N: usize, F: fn](value: *const T, bytes: []u8, matrix: [N]T) -> (*T, []const u8) {}\n")
    if signature_tree_error != ok || tree.count != 22usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .ComptimeParam || tree.nodes[2usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ComptimeParam || tree.nodes[4usize].kind != .ComptimeParam { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .NamedType || tree.nodes[6usize].kind != .PointerType { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .Parameter || tree.nodes[8usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .SliceType || tree.nodes[10usize].kind != .Parameter { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .NameExpr || tree.nodes[12usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .ArrayType || tree.nodes[14usize].kind != .Parameter { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .NamedType || tree.nodes[16usize].kind != .PointerType { ret lex.InvalidSource }
    if tree.nodes[17usize].kind != .NamedType || tree.nodes[18usize].kind != .SliceType { ret lex.InvalidSource }
    if tree.nodes[19usize].kind != .ReturnSpec || tree.nodes[20usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[21usize].kind != .FnDecl { ret lex.InvalidSource }
    let grouped_return_type_error = parse.validate("fn invalid() -> (i32) {}\n")
    if grouped_return_type_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let alias_error = parse.parse(&tree, "type Ptr = *const i32\ntype Bytes = []const u8\ntype Block4 = [4usize]u8\ntype Callback = fn(i32) -> err\n")
    if alias_error != ok || tree.count != 17usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NamedType || tree.nodes[2usize].kind != .PointerType { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .TypeDecl || tree.nodes[4usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .SliceType || tree.nodes[6usize].kind != .TypeDecl { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .LiteralExpr || tree.nodes[8usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .ArrayType || tree.nodes[10usize].kind != .TypeDecl { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .NamedType || tree.nodes[12usize].kind != .Parameter { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .NamedType || tree.nodes[14usize].kind != .ReturnSpec { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .FunctionType || tree.nodes[16usize].kind != .TypeDecl { ret lex.InvalidSource }
    let named_function_type_variadic_error = parse.validate("type Bad = fn(args: ...)\n")
    if named_function_type_variadic_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let soft_type_error = parse.parse(&tree, "type Soft = struct {\n    value\n    :\n    i32,\n}\n")
    if soft_type_error != ok || tree.count != 5usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NamedType || tree.nodes[2usize].kind != .FieldDecl { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .StructType || tree.nodes[4usize].kind != .TypeDecl { ret lex.InvalidSource }
    let soft_array_type_error = parse.validate("type SoftArray = struct {\n    values: [\n        size\n        +\n        1usize\n    ]u8,\n}\n")
    if soft_array_type_error != ok { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let soft_signature_error = parse.parse(&tree, "fn soft_signature[\n    T\n    :\n    type\n    ,\n](\n    value\n    :\n    *\n    const\n    package\n    .\n    Value\n    ,\n) -> (\n    *\n    T\n    ,\n    []\n    const\n    u8\n    ,\n) {}\n")
    if soft_signature_error != ok { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let soft_expression_error = parse.parse(&tree, "fn soft() {\n    let value = (\n        left\n        +\n        right\n    )\n    call(\n        value\n        +\n        1usize,\n    )\n    values[\n        index\n        +\n        1usize\n    ] = zero\n    let point = Point{\n        x: left\n           + right,\n    }\n}\n")
    if soft_expression_error != ok || tree.count != 29usize { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let nested_soft_error = parse.parse(&tree, "fn nested_soft() {\n    call(\n        package\n        .\n        Point{\n            x: value,\n        },\n        [\n            size + 1usize\n        ]\n        *\n        const\n        T{\n            value,\n        },\n    )\n}\n")
    if nested_soft_error != ok { ret lex.InvalidSource }
    let hard_newline_error = parse.validate("fn hard() {\n    ret left\n        + right\n}\n")
    if hard_newline_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let soft_recovery_error = parse.parse(&tree, "fn recover_soft() {\n    call(value +)\n    ret ok\n}\n")
    if soft_recovery_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 6usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .ErrorNode || tree.nodes[2usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ReturnStmt || tree.nodes[4usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let signature_barrier_error = parse.parse(&tree, "fn broken(\nfn good() {}\nerror Good\n")
    if signature_barrier_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 5usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .ErrorNode || tree.nodes[2usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .FnDecl || tree.nodes[4usize].kind != .ErrorDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let block_barrier_error = parse.parse(&tree, "fn broken() {\n    call(\nfn good() {}\nerror Good\n")
    if block_barrier_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 5usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .ErrorNode || tree.nodes[2usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .FnDecl || tree.nodes[4usize].kind != .ErrorDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let switch_barrier_error = parse.parse(&tree, "fn recover_markers() {\n    switch value {\n    case 1i32:\n        call(\n    case 2i32:\n        ret\n    default:\n        ret\n    }\n}\n")
    if switch_barrier_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 13usize { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ErrorNode || tree.nodes[4usize].kind != .SwitchArm { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .SwitchArm || tree.nodes[9usize].kind != .SwitchArm { ret lex.InvalidSource }
    if tree.nodes[10usize].kind != .SwitchStmt || tree.nodes[11usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[12usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let close_barrier_error = parse.parse(&tree, "fn recover_close() {\n    call(\n}\nerror Good\n")
    if close_barrier_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 5usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .ErrorNode || tree.nodes[2usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .FnDecl || tree.nodes[4usize].kind != .ErrorDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let eof_barrier_error = parse.parse(&tree, "fn recover_eof() {\n    call(\n")
    if eof_barrier_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 2usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .ErrorNode { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let statements_error = parse.parse(&tree, "fn statements() -> err {\n    let x = 1i32\n    var y = x\n    y += 1i32\n    call()\n    try fallible()\n    defer cleanup()\n    break\n    continue\n    ret ok\n}\n")
    if statements_error != ok || tree.count != 28usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NamedType || tree.nodes[2usize].kind != .ReturnSpec { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .Binding || tree.nodes[4usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .BindingStmt || tree.nodes[6usize].kind != .Binding { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .NameExpr || tree.nodes[8usize].kind != .BindingStmt { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .NameExpr || tree.nodes[10usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .AssignmentStmt || tree.nodes[12usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .CallExpr || tree.nodes[14usize].kind != .CallStmt { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .NameExpr || tree.nodes[16usize].kind != .CallExpr { ret lex.InvalidSource }
    if tree.nodes[17usize].kind != .TryStmt || tree.nodes[18usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[19usize].kind != .CallExpr || tree.nodes[20usize].kind != .CallStmt { ret lex.InvalidSource }
    if tree.nodes[21usize].kind != .DeferStmt || tree.nodes[22usize].kind != .BreakStmt { ret lex.InvalidSource }
    if tree.nodes[23usize].kind != .ContinueStmt || tree.nodes[24usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[25usize].kind != .ReturnStmt || tree.nodes[26usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[27usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let initializer_error = parse.parse(&tree, "fn initializers() {\n    let (\n        a,\n        _,\n    ): Pair = make(\n    )\n    var bytes: []u8 = zero\n    a = try next()\n    bytes = zero\n}\n")
    if initializer_error != ok || tree.count != 18usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .Binding || tree.nodes[2usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .NameExpr || tree.nodes[4usize].kind != .CallExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .BindingStmt || tree.nodes[6usize].kind != .Binding { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .NamedType || tree.nodes[8usize].kind != .SliceType { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .BindingStmt || tree.nodes[10usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .NameExpr || tree.nodes[12usize].kind != .CallExpr { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .AssignmentStmt || tree.nodes[14usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .AssignmentStmt || tree.nodes[16usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[17usize].kind != .FnDecl { ret lex.InvalidSource }
    let undef_assignment_error = parse.validate("fn invalid() {\n    value = undef\n}\n")
    if undef_assignment_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let undef_tuple_assignment_error = parse.validate("fn invalid() {\n    (left, right) = undef\n}\n")
    if undef_tuple_assignment_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let local_type_error = parse.parse(&tree, "fn local_types() {\n    let pointer: *const []shared u8 = zero\n    let array: [size + 1usize]Point = zero\n    let callback: extern fn(\n        ctx: *Ctx,\n        ...,\n    ) -> (i32, err) = zero\n}\n")
    if local_type_error != ok || tree.count != 25usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .Binding || tree.nodes[2usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .SliceType || tree.nodes[4usize].kind != .PointerType { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .BindingStmt || tree.nodes[6usize].kind != .Binding { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .NameExpr || tree.nodes[8usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .BinaryExpr || tree.nodes[10usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .ArrayType || tree.nodes[12usize].kind != .BindingStmt { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .Binding || tree.nodes[14usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .PointerType || tree.nodes[16usize].kind != .Parameter { ret lex.InvalidSource }
    if tree.nodes[17usize].kind != .Parameter || tree.nodes[18usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[19usize].kind != .NamedType || tree.nodes[20usize].kind != .ReturnSpec { ret lex.InvalidSource }
    if tree.nodes[21usize].kind != .FunctionType || tree.nodes[22usize].kind != .BindingStmt { ret lex.InvalidSource }
    if tree.nodes[23usize].kind != .Block || tree.nodes[24usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let expression_error = parse.parse(&tree, "fn expression() -> i32 {\n    ret -call(a + b * c)[i].field\n}\n")
    if expression_error != ok || tree.count != 17usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NamedType || tree.nodes[2usize].kind != .ReturnSpec { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .NameExpr || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .NameExpr || tree.nodes[6usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .BinaryExpr || tree.nodes[8usize].kind != .BinaryExpr { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .CallExpr || tree.nodes[10usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .BracketPostfix || tree.nodes[12usize].kind != .FieldExpr { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .UnaryExpr || tree.nodes[14usize].kind != .ReturnStmt { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .Block || tree.nodes[16usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let comparison_error = parse.parse(&tree, "fn comparison() -> bool {\n    ret a & b == c\n}\n")
    if comparison_error != ok || tree.count != 11usize { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .NameExpr || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .BinaryExpr || tree.nodes[6usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .BinaryExpr || tree.nodes[8usize].kind != .ReturnStmt { ret lex.InvalidSource }
    let chained_comparison_error = parse.validate("fn invalid() -> bool {\n    ret a < b < c\n}\n")
    if chained_comparison_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let grouped_error = parse.parse(&tree, "fn grouped() -> bool {\n    ret (.Ready == value)\n}\n")
    if grouped_error != ok || tree.count != 10usize { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .MemberExpr || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .BinaryExpr || tree.nodes[6usize].kind != .GroupExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .ReturnStmt || tree.nodes[8usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let return_list_error = parse.parse(&tree, "fn returns() -> (i32, err) {\n    ret (\n        value + 1i32,\n        ok,\n    )\n}\n")
    if return_list_error != ok || tree.count != 11usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NamedType || tree.nodes[2usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ReturnSpec || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .LiteralExpr || tree.nodes[6usize].kind != .BinaryExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .LiteralExpr || tree.nodes[8usize].kind != .ReturnStmt { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .Block || tree.nodes[10usize].kind != .FnDecl { ret lex.InvalidSource }
    let empty_return_list_error = parse.validate("fn invalid() {\n    ret ()\n}\n")
    if empty_return_list_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let named_aggregate_error = parse.parse(&tree, "fn point() -> Point {\n    ret Point{\n        x: 1i32,\n        y: base + 2i32,\n    }\n}\n")
    if named_aggregate_error != ok || tree.count != 14usize { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .NamedType || tree.nodes[4usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .LiteralItem || tree.nodes[6usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .LiteralExpr || tree.nodes[8usize].kind != .BinaryExpr { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .LiteralItem || tree.nodes[10usize].kind != .AggregateLiteral { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .ReturnStmt || tree.nodes[12usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .FnDecl || tree.nodes[10usize].child_count != 10usize { ret lex.InvalidSource }
    let named_children = tree.nodes[10usize].first_child
    if !tree.children[named_children].node || tree.children[named_children].index != 3usize { ret lex.InvalidSource }
    if !tree.children[named_children + 3usize].node || tree.children[named_children + 3usize].index != 5usize { ret lex.InvalidSource }
    if !tree.children[named_children + 6usize].node || tree.children[named_children + 6usize].index != 9usize { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let generic_aggregate_error = parse.parse(&tree, "fn boxed() -> Box[i32] {\n    ret Box[i32]{ value: item, }\n}\n")
    if generic_aggregate_error != ok || tree.count != 12usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NameExpr || tree.nodes[2usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ReturnSpec || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .NamedType || tree.nodes[6usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .LiteralItem || tree.nodes[8usize].kind != .AggregateLiteral { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .ReturnStmt || tree.nodes[10usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .FnDecl || tree.nodes[8usize].child_count != 5usize { ret lex.InvalidSource }
    let generic_children = tree.nodes[8usize].first_child
    if !tree.children[generic_children].node || tree.children[generic_children].index != 5usize { ret lex.InvalidSource }
    if !tree.children[generic_children + 2usize].node || tree.children[generic_children + 2usize].index != 7usize { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let array_aggregate_error = parse.parse(&tree, "fn values() -> [2usize]i32 {\n    ret [size + 1usize]i32{ 0i32, value, }\n}\n")
    if array_aggregate_error != ok || tree.count != 18usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .LiteralExpr || tree.nodes[2usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ArrayType || tree.nodes[4usize].kind != .ReturnSpec { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .NameExpr || tree.nodes[6usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .BinaryExpr || tree.nodes[8usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .ArrayType || tree.nodes[10usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .LiteralItem || tree.nodes[12usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .LiteralItem || tree.nodes[14usize].kind != .AggregateLiteral { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .ReturnStmt || tree.nodes[16usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[17usize].kind != .FnDecl || tree.nodes[14usize].child_count != 7usize { ret lex.InvalidSource }
    let array_children = tree.nodes[14usize].first_child
    if !tree.children[array_children].node || tree.children[array_children].index != 9usize { ret lex.InvalidSource }
    if !tree.children[array_children + 2usize].node || tree.children[array_children + 2usize].index != 11usize { ret lex.InvalidSource }
    if !tree.children[array_children + 4usize].node || tree.children[array_children + 4usize].index != 13usize { ret lex.InvalidSource }
    let inferred_aggregate_error = parse.validate("fn inferred() {\n    let values = [_]u8{ 1u8, 2u8, }\n}\n")
    if inferred_aggregate_error != ok { ret lex.InvalidSource }
    let slice_aggregate_error = parse.validate("fn invalid() {\n    let values = []u8{ 1u8, }\n}\n")
    if slice_aggregate_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let member_aggregate_error = parse.parse(&tree, "fn none() -> Maybe {\n    ret Maybe{ None }\n}\n")
    if member_aggregate_error != ok || tree.count != 9usize { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .NamedType || tree.nodes[4usize].kind != .LiteralItem { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .AggregateLiteral || tree.nodes[6usize].kind != .ReturnStmt { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .Block || tree.nodes[8usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let nested_aggregate_error = parse.parse(&tree, "fn nested() -> Outer {\n    ret Outer{ inner: Inner{ value: 1i32 } }\n}\n")
    if nested_aggregate_error != ok || tree.count != 13usize { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .NamedType || tree.nodes[4usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .LiteralExpr || tree.nodes[6usize].kind != .LiteralItem { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .AggregateLiteral || tree.nodes[8usize].kind != .LiteralItem { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .AggregateLiteral || tree.nodes[10usize].kind != .ReturnStmt { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .Block || tree.nodes[12usize].kind != .FnDecl { ret lex.InvalidSource }
    let empty_aggregate_error = parse.validate("fn invalid() -> Point {\n    ret Point{}\n}\n")
    if empty_aggregate_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let control_error = parse.parse(&tree, "fn control() {\n    if true { call() }\n    while true { break }\n    for item in items { call() }\n    when true { call() } else { cleanup() }\n    switch item {\n        case 1i32:\n            ret\n    }\n    @nocheck { call() }\n    shared var value: i32 = 0i32\n}\n")
    if control_error != ok || tree.count != 42usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .LiteralExpr || tree.nodes[2usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .CallExpr || tree.nodes[4usize].kind != .CallStmt { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .Block || tree.nodes[6usize].kind != .IfStmt { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .LiteralExpr || tree.nodes[8usize].kind != .BreakStmt { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .Block || tree.nodes[10usize].kind != .WhileStmt { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .NameExpr || tree.nodes[12usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .CallExpr || tree.nodes[14usize].kind != .CallStmt { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .Block || tree.nodes[16usize].kind != .ForStmt { ret lex.InvalidSource }
    if tree.nodes[17usize].kind != .LiteralExpr || tree.nodes[18usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[19usize].kind != .CallExpr || tree.nodes[20usize].kind != .CallStmt { ret lex.InvalidSource }
    if tree.nodes[21usize].kind != .Block || tree.nodes[22usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[23usize].kind != .CallExpr || tree.nodes[24usize].kind != .CallStmt { ret lex.InvalidSource }
    if tree.nodes[25usize].kind != .Block || tree.nodes[26usize].kind != .WhenStmt { ret lex.InvalidSource }
    if tree.nodes[27usize].kind != .NameExpr || tree.nodes[28usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[29usize].kind != .ReturnStmt || tree.nodes[30usize].kind != .SwitchArm { ret lex.InvalidSource }
    if tree.nodes[31usize].kind != .SwitchStmt || tree.nodes[32usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[33usize].kind != .CallExpr || tree.nodes[34usize].kind != .CallStmt { ret lex.InvalidSource }
    if tree.nodes[35usize].kind != .Block || tree.nodes[36usize].kind != .NocheckStmt { ret lex.InvalidSource }
    if tree.nodes[37usize].kind != .NamedType || tree.nodes[38usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[39usize].kind != .SharedVarStmt || tree.nodes[40usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[41usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let branches_error = parse.parse(&tree, "fn branches() {\n    if a {\n        ret\n    } else if b {\n        call()\n    } else {\n        cleanup()\n    }\n}\n")
    if branches_error != ok || tree.count != 17usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NameExpr || tree.nodes[2usize].kind != .ReturnStmt { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .Block || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .NameExpr || tree.nodes[6usize].kind != .CallExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .CallStmt || tree.nodes[8usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .NameExpr || tree.nodes[10usize].kind != .CallExpr { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .CallStmt || tree.nodes[12usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .IfStmt || tree.nodes[14usize].kind != .IfStmt { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .Block || tree.nodes[16usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let loops_error = parse.parse(&tree, "fn loops() {\n    for item, index in items { call(item) }\n    for _, i in 0usize..limit { continue }\n}\n")
    if loops_error != ok || tree.count != 15usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NameExpr || tree.nodes[2usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .NameExpr || tree.nodes[4usize].kind != .CallExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .CallStmt || tree.nodes[6usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .ForStmt || tree.nodes[8usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .NameExpr || tree.nodes[10usize].kind != .ContinueStmt { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .Block || tree.nodes[12usize].kind != .ForStmt { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .Block || tree.nodes[14usize].kind != .FnDecl { ret lex.InvalidSource }
    let missing_range_end_error = parse.validate("fn invalid() {\n    for i in 0usize.. {}\n}\n")
    if missing_range_end_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let deferred_block_error = parse.parse(&tree, "fn deferred() {\n    defer {\n        cleanup()\n    }\n}\n")
    if deferred_block_error != ok || tree.count != 8usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NameExpr || tree.nodes[2usize].kind != .CallExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .CallStmt || tree.nodes[4usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .DeferStmt || tree.nodes[6usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .FnDecl { ret lex.InvalidSource }
    let invalid_directive_error = parse.validate("fn invalid() {\n    @checked {}\n}\n")
    if invalid_directive_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let trailing_break_error = parse.validate("fn invalid() {\n    break value\n}\n")
    if trailing_break_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let switch_error = parse.parse(&tree, "fn choose() {\n    switch value {\n    case 1i32, 2i32:\n        call()\n    case .Some as item:\n        ret item\n    default:\n        break\n    }\n}\n")
    if switch_error != ok || tree.count != 17usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NameExpr || tree.nodes[2usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .LiteralExpr || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .CallExpr || tree.nodes[6usize].kind != .CallStmt { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .SwitchArm || tree.nodes[8usize].kind != .MemberExpr { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .NameExpr || tree.nodes[10usize].kind != .ReturnStmt { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .SwitchArm || tree.nodes[12usize].kind != .BreakStmt { ret lex.InvalidSource }
    if tree.nodes[13usize].kind != .SwitchArm || tree.nodes[14usize].kind != .SwitchStmt { ret lex.InvalidSource }
    if tree.nodes[15usize].kind != .Block || tree.nodes[16usize].kind != .FnDecl { ret lex.InvalidSource }
    if tree.nodes[14usize].child_count != 8usize || tree.nodes[7usize].child_count != 8usize { ret lex.InvalidSource }
    let switch_children = tree.nodes[14usize].first_child
    if !tree.children[switch_children + 1usize].node || tree.children[switch_children + 1usize].index != 1usize { ret lex.InvalidSource }
    if !tree.children[switch_children + 4usize].node || tree.children[switch_children + 4usize].index != 7usize { ret lex.InvalidSource }
    if !tree.children[switch_children + 5usize].node || tree.children[switch_children + 5usize].index != 11usize { ret lex.InvalidSource }
    if !tree.children[switch_children + 6usize].node || tree.children[switch_children + 6usize].index != 13usize { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let switch_recovery_error = parse.parse(&tree, "fn recover_switch() {\n    switch value {\n    case 1i32:\n        call() + value\n    default:\n        ret\n    }\n}\n")
    if switch_recovery_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 10usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NameExpr || tree.nodes[2usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ErrorNode || tree.nodes[4usize].kind != .SwitchArm { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .ReturnStmt || tree.nodes[6usize].kind != .SwitchArm { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .SwitchStmt || tree.nodes[8usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .FnDecl { ret lex.InvalidSource }
    let empty_switch_error = parse.validate("fn invalid() {\n    switch value {}\n}\n")
    if empty_switch_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let inline_switch_arm_error = parse.validate("fn invalid() {\n    switch value {\n    default: ret\n    }\n}\n")
    if inline_switch_arm_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let block_error = parse.parse(&tree, "fn recover() {\n    use bad\n    ret\n}\nerror Good\n")
    if block_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 6usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .ErrorNode || tree.nodes[2usize].kind != .ReturnStmt { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .Block || tree.nodes[4usize].kind != .FnDecl { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .ErrorDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let expression_recovery_error = parse.parse(&tree, "fn recover_expression() {\n    call() + value\n    ret ok\n}\n")
    if expression_recovery_error != parse.InvalidSyntax || tree.errors != 1usize || tree.count != 6usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .ErrorNode || tree.nodes[2usize].kind != .LiteralExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ReturnStmt || tree.nodes[4usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .FnDecl { ret lex.InvalidSource }
    let syntax_error = parse.validate("fn broken() -> err {\n    ret ok\n")
    if syntax_error != parse.InvalidSyntax { ret lex.InvalidSource }
    var recovery_nodes: [4]syntax.Node = zero
    var recovery_children: [16]syntax.Child = zero
    var recovered: parse.Tree = zero
    try parse.init_tree(&recovered, recovery_nodes[..], recovery_children[..])
    let recovery_error = parse.parse(&recovered, "@\nerror Good\n")
    if recovery_error != parse.InvalidSyntax || recovered.errors != 1usize { ret lex.InvalidSource }
    if recovered.count != 3usize || recovered.nodes[1usize].kind != .ErrorNode { ret lex.InvalidSource }
    if recovered.nodes[2usize].kind != .ErrorDecl { ret lex.InvalidSource }
    try parse.init_tree(&recovered, recovery_nodes[..], recovery_children[..])
    let signature_error = parse.parse(&recovered, "fn broken(value i32) -> err {}\nerror Good\n")
    if signature_error != parse.InvalidSyntax || recovered.errors != 1usize { ret lex.InvalidSource }
    if recovered.count != 3usize || recovered.nodes[1usize].kind != .ErrorNode { ret lex.InvalidSource }
    if recovered.nodes[2usize].kind != .ErrorDecl { ret lex.InvalidSource }
    try parse.init_tree(&recovered, recovery_nodes[..], recovery_children[..])
    let type_error = parse.parse(&recovered, "type Bad = enum {}\nerror Good\n")
    if type_error != parse.InvalidSyntax || recovered.errors != 1usize { ret lex.InvalidSource }
    if recovered.count != 3usize || recovered.nodes[1usize].kind != .ErrorNode { ret lex.InvalidSource }
    if recovered.nodes[2usize].kind != .ErrorDecl { ret lex.InvalidSource }
    var tiny_nodes: [1]syntax.Node = zero
    var tiny_children: [1]syntax.Child = zero
    var tiny: parse.Tree = zero
    try parse.init_tree(&tiny, tiny_nodes[..], tiny_children[..])
    let capacity_error = parse.parse(&tiny, "error Full\n")
    if capacity_error != parse.InvalidSyntax { ret lex.InvalidSource }
    ret ok
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len == 2usize && same(args[1usize], "self-test") {
        try self_test()
        try io.print("selfhost lexer ok\n")
        ret ok
    }
    if args.len == 3usize && same(args[1usize], "scan") {
        let scan_error = lex.validate(args[2usize])
        if scan_error != ok { ret scan_error }
        try io.print("scan ok\n")
        ret ok
    }
    if args.len == 3usize && same(args[1usize], "parse") {
        let parse_error = parse.validate(args[2usize])
        if parse_error != ok { ret parse_error }
        try io.print("parse ok\n")
        ret ok
    }
    try io.print("usage: neper-self scan|parse SOURCE\n")
    ret ok
}
