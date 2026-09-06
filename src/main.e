use e.io
use e.mem
use e.os
use artifact_hash
use check
use codegen_x64
use emit_x64
use graph
use lex
use link_elf
use link_pe
use lower
use nir
use object_coff
use object_elf
use parse
use project
use regalloc
use resolve
use source
use syntax

error DiagnosticWrite

fn expect(s: *lex.Scanner, kind: lex.Kind, start: usize, end: usize, line: usize, column: usize) -> err {
    let current = lex.next(s)
    if current.kind != kind || current.start != start || current.end != end || current.line != line || current.column != column {
        ret lex.InvalidSource
    }
    ret ok
}

fn validate_test_parse(text: str) -> err {
    var nodes: [64]syntax.Node = zero
    var children: [512]syntax.Child = zero
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, nodes[..], children[..])
    ret parse.parse(&tree, text)
}

fn self_test() -> err {
    var basic = lex.init("use e.io\r\nfn main() -> err { // note\n    ret ok\n}\n")
    let basic_use = lex.next(&basic)
    if basic_use.kind != .KwUse || basic_use.leading_start != 0usize || basic_use.start != 0usize || basic_use.end != 3usize { ret lex.InvalidSource }
    let basic_e = lex.next(&basic)
    if basic_e.kind != .Identifier || basic_e.leading_start != 3usize || basic_e.start != 4usize || basic_e.end != 5usize { ret lex.InvalidSource }
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
    if positioned_string.kind != .String || positioned_string.leading_start != 0usize || positioned_string.start != 3usize || positioned_string.end != 11usize { ret lex.InvalidSource }
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
    var invalid_scalar = lex.init("😀x")
    let invalid_scalar_token = lex.next(&invalid_scalar)
    if invalid_scalar_token.kind != .Invalid || invalid_scalar_token.start != 0usize || invalid_scalar_token.end != 4usize { ret lex.InvalidSource }
    if invalid_scalar_token.column != 1usize || invalid_scalar_token.end_column != 2usize || invalid_scalar_token.column_utf16 != 1usize || invalid_scalar_token.end_column_utf16 != 3usize { ret lex.InvalidSource }
    let after_invalid_scalar = lex.next(&invalid_scalar)
    if after_invalid_scalar.kind != .Identifier || after_invalid_scalar.start != 4usize || after_invalid_scalar.column != 2usize || after_invalid_scalar.column_utf16 != 3usize { ret lex.InvalidSource }
    var invalid_sequence = lex.init("\xF0\x9F\x92x")
    let invalid_sequence_token = lex.next(&invalid_sequence)
    if invalid_sequence_token.kind != .Invalid || invalid_sequence_token.start != 0usize || invalid_sequence_token.end != 3usize { ret lex.InvalidSource }
    if invalid_sequence_token.end_column != 2usize || invalid_sequence_token.end_column_utf16 != 2usize { ret lex.InvalidSource }
    let after_invalid_sequence = lex.next(&invalid_sequence)
    if after_invalid_sequence.kind != .Identifier || after_invalid_sequence.start != 3usize || after_invalid_sequence.column != 2usize || after_invalid_sequence.column_utf16 != 2usize { ret lex.InvalidSource }
    var trivia = lex.init("\xEF\xBB\xBF // c\r\nx ")
    let trivia_newline = lex.next(&trivia)
    if trivia_newline.kind != .Newline || trivia_newline.leading_start != 0usize || trivia_newline.start != 8usize || trivia_newline.end != 10usize { ret lex.InvalidSource }
    var leading = lex.trivia_init(trivia.source, trivia_newline)
    let leading_bom = lex.next_trivia(&leading)
    if leading_bom.kind != .Bom || leading_bom.start != 0usize || leading_bom.end != 3usize || leading_bom.column != 1usize || leading_bom.end_column != 1usize { ret lex.InvalidSource }
    let leading_space = lex.next_trivia(&leading)
    if leading_space.kind != .Space || leading_space.start != 3usize || leading_space.end != 4usize || leading_space.column != 1usize || leading_space.end_column != 2usize { ret lex.InvalidSource }
    let leading_comment = lex.next_trivia(&leading)
    if leading_comment.kind != .Comment || leading_comment.start != 4usize || leading_comment.end != 8usize || leading_comment.column != 2usize || leading_comment.end_column != 6usize { ret lex.InvalidSource }
    if lex.next_trivia(&leading).kind != .End { ret lex.InvalidSource }
    let trivia_name = lex.next(&trivia)
    if trivia_name.kind != .Identifier || trivia_name.leading_start != 10usize || trivia_name.start != 10usize || trivia_name.end != 11usize { ret lex.InvalidSource }
    let trivia_eof = lex.next(&trivia)
    if trivia_eof.kind != .Eof || trivia_eof.leading_start != 11usize || trivia_eof.start != 12usize || trivia_eof.end != 12usize { ret lex.InvalidSource }
    var trailing = lex.trivia_init(trivia.source, trivia_eof)
    let trailing_space = lex.next_trivia(&trailing)
    if trailing_space.kind != .Space || trailing_space.start != 11usize || trailing_space.end != 12usize || trailing_space.column != 2usize || trailing_space.end_column != 3usize { ret lex.InvalidSource }
    var unicode_trivia = lex.init("// 😀\nx")
    let unicode_newline = lex.next(&unicode_trivia)
    var unicode_leading = lex.trivia_init(unicode_trivia.source, unicode_newline)
    let unicode_comment = lex.next_trivia(&unicode_leading)
    if unicode_comment.kind != .Comment || unicode_comment.start != 0usize || unicode_comment.end != 7usize || unicode_comment.end_column != 5usize || unicode_comment.end_column_utf16 != 6usize { ret lex.InvalidSource }
    var broken_comment = lex.init("// a\xF0\x9F\x92 rest\nerror Good")
    let broken_comment_byte = lex.next(&broken_comment)
    if broken_comment_byte.kind != .Invalid || broken_comment_byte.start != 4usize || broken_comment_byte.end != 7usize { ret lex.InvalidSource }
    var broken_prefix = lex.trivia_init(broken_comment.source, broken_comment_byte)
    let broken_prefix_comment = lex.next_trivia(&broken_prefix)
    if broken_prefix_comment.kind != .Comment || broken_prefix_comment.start != 0usize || broken_prefix_comment.end != 4usize { ret lex.InvalidSource }
    let after_broken_comment = lex.next(&broken_comment)
    if after_broken_comment.kind != .Newline || after_broken_comment.leading_start != 7usize || after_broken_comment.start != 12usize { ret lex.InvalidSource }
    var broken_suffix = lex.trivia_init(broken_comment.source, after_broken_comment)
    let broken_suffix_comment = lex.next_trivia(&broken_suffix)
    if broken_suffix_comment.kind != .Comment || broken_suffix_comment.start != 7usize || broken_suffix_comment.end != 12usize { ret lex.InvalidSource }
    let after_broken_line = lex.next(&broken_comment)
    if after_broken_line.kind != .KwError || after_broken_line.start != 13usize { ret lex.InvalidSource }
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
    var recovered_string = lex.init("\"a\\qz\" error Good")
    let invalid_string_token = lex.next(&recovered_string)
    if invalid_string_token.kind != .Invalid || invalid_string_token.start != 0usize || invalid_string_token.end != 6usize { ret lex.InvalidSource }
    let after_invalid_string = lex.next(&recovered_string)
    if after_invalid_string.kind != .KwError || after_invalid_string.start != 7usize { ret lex.InvalidSource }
    var recovered_raw = lex.init("r\"a\xF0\x9F\x92z\" error Good")
    let invalid_raw_token = lex.next(&recovered_raw)
    if invalid_raw_token.kind != .Invalid || invalid_raw_token.start != 0usize || invalid_raw_token.end != 8usize { ret lex.InvalidSource }
    let after_invalid_raw = lex.next(&recovered_raw)
    if after_invalid_raw.kind != .KwError || after_invalid_raw.start != 9usize { ret lex.InvalidSource }
    var recovered_character = lex.init("'ab' error Good")
    let invalid_character_token = lex.next(&recovered_character)
    if invalid_character_token.kind != .Invalid || invalid_character_token.start != 0usize || invalid_character_token.end != 4usize { ret lex.InvalidSource }
    if lex.next(&recovered_character).kind != .KwError { ret lex.InvalidSource }
    var unterminated_string = lex.init("\"a\nerror Good")
    let unterminated_string_token = lex.next(&unterminated_string)
    if unterminated_string_token.kind != .Invalid || unterminated_string_token.start != 0usize || unterminated_string_token.end != 2usize { ret lex.InvalidSource }
    if lex.next(&unterminated_string).kind != .Newline { ret lex.InvalidSource }

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
    if tree.nodes[0usize].top_level || tree.nodes[0usize].parented || !tree.nodes[1usize].top_level || !tree.nodes[2usize].top_level { ret lex.InvalidSource }
    if tree.nodes[1usize].parented || tree.nodes[5usize].top_level || !tree.nodes[5usize].parented { ret lex.InvalidSource }
    if !tree.nodes[7usize].top_level || tree.nodes[7usize].parented || !tree.nodes[16usize].top_level || tree.nodes[16usize].parented { ret lex.InvalidSource }
    var adoption_index = 1usize
    while adoption_index < tree.count {
        if tree.nodes[adoption_index].top_level == tree.nodes[adoption_index].parented { ret lex.InvalidSource }
        adoption_index += 1usize
    }
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
    let invalid_try_initializer_error = validate_test_parse("var value = try not_a_call\n")
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
    let one_item_assignment_error = validate_test_parse("fn invalid() {\n    (only,) = zero\n}\n")
    if one_item_assignment_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let binary_target_error = validate_test_parse("fn invalid() {\n    left + right = zero\n}\n")
    if binary_target_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let unary_target_error = validate_test_parse("fn invalid() {\n    -value = zero\n}\n")
    if unary_target_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let tuple_unary_target_error = validate_test_parse("fn invalid() {\n    (-left, right) = zero\n}\n")
    if tuple_unary_target_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let deref_target_error = validate_test_parse("fn deref() {\n    **pointer = zero\n    (*left, **right) = zero\n}\n")
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
    let grouped_return_type_error = validate_test_parse("fn invalid() -> (i32) {}\n")
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
    let named_function_type_variadic_error = validate_test_parse("type Bad = fn(args: ...)\n")
    if named_function_type_variadic_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let signature_forms_error = validate_test_parse("extern fn c_variadic(value: i32, args: ...,)\nfn packed(args: ...,) {}\nfn bare(...,) {}\ntype Callback = extern fn(i32, ...,) -> i32\ntype EmptyArgs = Box[]\n")
    if signature_forms_error != ok { ret lex.InvalidSource }
    let one_return_type_error = validate_test_parse("fn invalid() -> (i32,) {}\n")
    if one_return_type_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let missing_parameter_comma_error = validate_test_parse("fn invalid(first: i32 second: i32) {}\n")
    if missing_parameter_comma_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let soft_type_error = parse.parse(&tree, "type Soft = struct {\n    value\n    :\n    i32,\n}\n")
    if soft_type_error != ok || tree.count != 5usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NamedType || tree.nodes[2usize].kind != .FieldDecl { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .StructType || tree.nodes[4usize].kind != .TypeDecl { ret lex.InvalidSource }
    let soft_array_type_error = validate_test_parse("type SoftArray = struct {\n    values: [\n        size\n        +\n        1usize\n    ]u8,\n}\n")
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
    let hard_newline_error = validate_test_parse("fn hard() {\n    ret left\n        + right\n}\n")
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
    let undef_assignment_error = validate_test_parse("fn invalid() {\n    value = undef\n}\n")
    if undef_assignment_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let undef_tuple_assignment_error = validate_test_parse("fn invalid() {\n    (left, right) = undef\n}\n")
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
    let chained_comparison_error = validate_test_parse("fn invalid() -> bool {\n    ret a < b < c\n}\n")
    if chained_comparison_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let grouped_error = parse.parse(&tree, "fn grouped() -> bool {\n    ret (.Ready == value)\n}\n")
    if grouped_error != ok || tree.count != 10usize { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .MemberExpr || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .BinaryExpr || tree.nodes[6usize].kind != .GroupExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .ReturnStmt || tree.nodes[8usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .FnDecl { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let bracket_error = parse.parse(&tree, "fn postfix() {\n    call(values[], values[index], values[..], values[start..], values[..end], values[start..end], table[\n        row,\n        column,\n    ])\n}\n")
    if bracket_error != ok || tree.count != 27usize { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .BracketPostfix || tree.nodes[6usize].kind != .BracketPostfix { ret lex.InvalidSource }
    if tree.nodes[8usize].kind != .BracketPostfix || tree.nodes[11usize].kind != .BracketPostfix { ret lex.InvalidSource }
    if tree.nodes[14usize].kind != .BracketPostfix || tree.nodes[18usize].kind != .BracketPostfix { ret lex.InvalidSource }
    if tree.nodes[22usize].kind != .BracketPostfix || tree.nodes[23usize].kind != .CallExpr { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let bracket_type_error = parse.parse(&tree, "fn bracket_types() {\n    mem.alloc[[]u8](a, 1usize)\n    mem.alloc[[3]u16](a, 1usize)\n    mem.alloc[*const u8](a, 1usize)\n    generic[[3]u8{ 1u8, 2u8, 3u8 }]()\n}\n")
    if bracket_type_error != ok { ret lex.InvalidSource }
    var saw_slice_type = false
    var saw_array_type = false
    var saw_const_pointer_type = false
    var saw_array_literal = false
    var bracket_type_index = 1usize
    while bracket_type_index < tree.count {
        let bracket_node = tree.nodes[bracket_type_index]
        if bracket_node.kind == .SliceType { saw_slice_type = true }
        if bracket_node.kind == .ArrayType { saw_array_type = true }
        if bracket_node.kind == .PointerType { saw_const_pointer_type = true }
        if bracket_node.kind == .AggregateLiteral { saw_array_literal = true }
        bracket_type_index += 1usize
    }
    if !saw_slice_type || !saw_array_type || !saw_const_pointer_type || !saw_array_literal { ret lex.InvalidSource }
    let mixed_range_error = validate_test_parse("fn invalid() {\n    call(values[start..end, next])\n}\n")
    if mixed_range_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let trailing_range_error = validate_test_parse("fn invalid() {\n    call(values[..end,])\n}\n")
    if trailing_range_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let empty_index_error = validate_test_parse("fn invalid() {\n    call(values[first,, second])\n}\n")
    if empty_index_error != parse.InvalidSyntax { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let return_list_error = parse.parse(&tree, "fn returns() -> (i32, err) {\n    ret (\n        value + 1i32,\n        ok,\n    )\n}\n")
    if return_list_error != ok || tree.count != 11usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NamedType || tree.nodes[2usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ReturnSpec || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .LiteralExpr || tree.nodes[6usize].kind != .BinaryExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .LiteralExpr || tree.nodes[8usize].kind != .ReturnStmt { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .Block || tree.nodes[10usize].kind != .FnDecl { ret lex.InvalidSource }
    let empty_return_list_error = validate_test_parse("fn invalid() {\n    ret ()\n}\n")
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
    let inferred_aggregate_error = validate_test_parse("fn inferred() {\n    let values = [_]u8{ 1u8, 2u8, }\n}\n")
    if inferred_aggregate_error != ok { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let constant_item_error = parse.parse(&tree, "fn constants() {\n    let values = [_]usize{ MAX_NODES, N, }\n}\n")
    if constant_item_error != ok || tree.count != 12usize { ret lex.InvalidSource }
    if tree.nodes[4usize].kind != .NameExpr || tree.nodes[5usize].kind != .LiteralItem { ret lex.InvalidSource }
    if tree.nodes[6usize].kind != .NameExpr || tree.nodes[7usize].kind != .LiteralItem { ret lex.InvalidSource }
    let slice_aggregate_error = validate_test_parse("fn invalid() {\n    let values = []u8{ 1u8, }\n}\n")
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
    let empty_aggregate_error = validate_test_parse("fn invalid() -> Point {\n    ret Point{}\n}\n")
    if empty_aggregate_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let constant_condition_error = validate_test_parse("fn flags() {\n    if N { ret }\n    while N { break }\n    when N { ret } else { ret }\n    switch N {\n    case 1usize:\n        ret\n    }\n}\n")
    if constant_condition_error != ok { ret lex.InvalidSource }
    let nested_condition_aggregate_error = validate_test_parse("fn nested_flag() {\n    if predicate(Flag{ value: true }) { ret }\n}\n")
    if nested_condition_aggregate_error != ok { ret lex.InvalidSource }
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
    let missing_range_end_error = validate_test_parse("fn invalid() {\n    for i in 0usize.. {}\n}\n")
    if missing_range_end_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let comptime_range_end_error = validate_test_parse("fn generic_range[N: usize]() {\n    for i in 0usize..N { continue }\n}\n")
    if comptime_range_end_error != ok { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let deferred_block_error = parse.parse(&tree, "fn deferred() {\n    defer {\n        cleanup()\n    }\n}\n")
    if deferred_block_error != ok || tree.count != 8usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NameExpr || tree.nodes[2usize].kind != .CallExpr { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .CallStmt || tree.nodes[4usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .DeferStmt || tree.nodes[6usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .FnDecl { ret lex.InvalidSource }
    let invalid_directive_error = validate_test_parse("fn invalid() {\n    @checked {}\n}\n")
    if invalid_directive_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let trailing_break_error = validate_test_parse("fn invalid() {\n    break value\n}\n")
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
    let empty_switch_error = validate_test_parse("fn invalid() {\n    switch value {}\n}\n")
    if empty_switch_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let inline_switch_arm_error = validate_test_parse("fn invalid() {\n    switch value {\n    default: ret\n    }\n}\n")
    if inline_switch_arm_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let inline_switch_close_error = validate_test_parse("fn invalid() {\n    switch value {\n    default:\n        ret }\n}\n")
    if inline_switch_close_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let collapsed_empty_arm_error = validate_test_parse("fn invalid() {\n    switch value {\n    case 1usize:\n    default:\n        ret\n    }\n}\n")
    if collapsed_empty_arm_error != parse.InvalidSyntax { ret lex.InvalidSource }
    let empty_arm_error = validate_test_parse("fn empty_arm() {\n    switch value {\n    case 1usize:\n\n    default:\n        ret\n    }\n}\n")
    if empty_arm_error != ok { ret lex.InvalidSource }
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
    let syntax_error = validate_test_parse("fn broken() -> err {\n    ret ok\n")
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
    try artifact_hash.self_test()
    try nir.self_test()
    try nir.signature_self_test()
    try regalloc.self_test()
    try emit_x64.self_test()
    try codegen_x64.self_test()
    try object_coff.self_test()
    try object_elf.self_test()
    try link_elf.self_test()
    try link_pe.self_test()
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

fn validate_cli_parse(text: str) -> err {
    // The CLI supplies explicit storage; parser lists have no separate caps.
    var nodes: [1024]syntax.Node = zero
    var children: [16384]syntax.Child = zero
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, nodes[..], children[..])
    ret parse.parse(&tree, text)
}

fn init_cli_graph(a: *mem.Arena, loaded: *graph.Graph) -> err {
    let (modules, modules_error) = mem.alloc[graph.Module](a, 128usize)
    if modules_error != ok { ret modules_error }
    let (imports, imports_error) = mem.alloc[graph.Import](a, 2048usize)
    if imports_error != ok { ret imports_error }
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, 32768usize)
    if nodes_error != ok { ret nodes_error }
    let (children, children_error) = mem.alloc[syntax.Child](a, 262144usize)
    if children_error != ok { ret children_error }
    ret graph.init(loaded, modules, imports, nodes, children)
}

fn init_cli_resolver(a: *mem.Arena, resolver: *resolve.Resolver) -> err {
    let (symbols, symbols_error) = mem.alloc[resolve.Symbol](a, 16384usize)
    if symbols_error != ok { ret symbols_error }
    let (tokens, tokens_error) = mem.alloc[lex.Token](a, 65536usize)
    if tokens_error != ok { ret tokens_error }
    let (locals, locals_error) = mem.alloc[resolve.Local](a, 16384usize)
    if locals_error != ok { ret locals_error }
    ret resolve.init(resolver, symbols, tokens, locals)
}

fn init_cli_checker(a: *mem.Arena, checker: *check.Checker) -> err {
    let (functions, functions_error) = mem.alloc[check.Function](a, 4096usize)
    if functions_error != ok { ret functions_error }
    let (function_generics, function_generics_error) = mem.alloc[check.FunctionGeneric](a, 4096usize)
    if function_generics_error != ok { ret function_generics_error }
    let (parameters, parameters_error) = mem.alloc[check.Parameter](a, 32768usize)
    if parameters_error != ok { ret parameters_error }
    let (return_types, return_types_error) = mem.alloc[check.Type](a, 32768usize)
    if return_types_error != ok { ret return_types_error }
    let (comptime_parameters, comptime_parameters_error) = mem.alloc[check.ComptimeParameter](a, 1024usize)
    if comptime_parameters_error != ok { ret comptime_parameters_error }
    let (generic_arguments, generic_arguments_error) = mem.alloc[check.GenericArgument](a, 4096usize)
    if generic_arguments_error != ok { ret generic_arguments_error }
    let (aggregates, aggregates_error) = mem.alloc[check.Aggregate](a, 4096usize)
    if aggregates_error != ok { ret aggregates_error }
    let (aggregate_fields, aggregate_fields_error) = mem.alloc[check.AggregateField](a, 8192usize)
    if aggregate_fields_error != ok { ret aggregate_fields_error }
    let (checked_switches, checked_switches_error) = mem.alloc[check.CheckedSwitch](a, 4096usize)
    if checked_switches_error != ok { ret checked_switches_error }
    let (tokens, tokens_error) = mem.alloc[lex.Token](a, 65536usize)
    if tokens_error != ok { ret tokens_error }
    let (locals, locals_error) = mem.alloc[check.Local](a, 16384usize)
    if locals_error != ok { ret locals_error }
    let (types, types_error) = mem.alloc[check.Type](a, 65536usize)
    if types_error != ok { ret types_error }
    let (aliases, aliases_error) = mem.alloc[check.Alias](a, 4096usize)
    if aliases_error != ok { ret aliases_error }
    let (constants, constants_error) = mem.alloc[check.Constant](a, 4096usize)
    if constants_error != ok { ret constants_error }
    let (constant_exprs, constant_exprs_error) = mem.alloc[check.ConstantExpr](a, 32768usize)
    if constant_exprs_error != ok { ret constant_exprs_error }
    let (diagnostics, diagnostics_error) = mem.alloc[check.Diagnostic](a, 4096usize)
    if diagnostics_error != ok { ret diagnostics_error }
    try check.init(checker, functions, parameters, return_types, tokens, locals, types, aliases, constants, constant_exprs, diagnostics)
    try check.init_generics(checker, function_generics, comptime_parameters, generic_arguments)
    try check.init_aggregates(checker, aggregates, aggregate_fields)
    ret check.init_control(checker, checked_switches)
}

fn init_cli_nir(a: *mem.Arena, builder: *nir.Builder, signatures: *nir.Signatures, signature_type_capacity: usize) -> err {
    let (functions, functions_error) = mem.alloc[nir.Function](a, 1024usize)
    if functions_error != ok { ret functions_error }
    let (blocks, blocks_error) = mem.alloc[nir.Block](a, 8192usize)
    if blocks_error != ok { ret blocks_error }
    let (instructions, instructions_error) = mem.alloc[nir.Instruction](a, 32768usize)
    if instructions_error != ok { ret instructions_error }
    let (operands, operands_error) = mem.alloc[usize](a, 131072usize)
    if operands_error != ok { ret operands_error }
    let (function_refs, function_refs_error) = mem.alloc[nir.FunctionRef](a, 8192usize)
    if function_refs_error != ok { ret function_refs_error }
    let (strings, strings_error) = mem.alloc[nir.StringConstant](a, 8192usize)
    if strings_error != ok { ret strings_error }
    try nir.init(builder, functions, blocks, instructions, operands, function_refs, strings)
    let (signature_entries, signature_entries_error) = mem.alloc[nir.Signature](a, 1024usize)
    if signature_entries_error != ok { ret signature_entries_error }
    var type_capacity = signature_type_capacity
    if type_capacity == 0usize { type_capacity = 1usize }
    let (signature_types, signature_types_error) = mem.alloc[check.Type](a, type_capacity)
    if signature_types_error != ok { ret signature_types_error }
    ret nir.init_signatures(signatures, signature_entries, signature_types)
}

fn write_all(file: os.File, text: str) -> err {
    var at = 0usize
    while at < text.len {
        let (written, write_error) = os.write(file, text[at..])
        if write_error != ok { ret write_error }
        if written == 0usize { ret DiagnosticWrite }
        at += written
    }
    ret ok
}

fn write_bytes(file: os.File, bytes: []u8) -> err {
    var at = 0usize
    while at < bytes.len {
        let (written, write_error) = os.write(file, bytes[at..])
        if write_error != ok { ret write_error }
        if written == 0usize { ret DiagnosticWrite }
        at += written
    }
    ret ok
}

fn save_bytes(a: *mem.Arena, path: str, bytes: []u8) -> err {
    let flags = os.OpenFlags { read: false, write: true, create: true, truncate: true, append: false }
    let (file, open_error) = os.open(a, path, flags)
    if open_error != ok { ret open_error }
    let write_error = write_bytes(file, bytes)
    let close_error = os.close(file)
    if write_error != ok { ret write_error }
    ret close_error
}

fn write_digit(file: os.File, digit: usize) -> err {
    if digit == 0usize { ret write_all(file, "0") }
    if digit == 1usize { ret write_all(file, "1") }
    if digit == 2usize { ret write_all(file, "2") }
    if digit == 3usize { ret write_all(file, "3") }
    if digit == 4usize { ret write_all(file, "4") }
    if digit == 5usize { ret write_all(file, "5") }
    if digit == 6usize { ret write_all(file, "6") }
    if digit == 7usize { ret write_all(file, "7") }
    if digit == 8usize { ret write_all(file, "8") }
    ret write_all(file, "9")
}

fn write_usize(file: os.File, value: usize) -> err {
    var divisor = 1usize
    var remaining = value
    while remaining >= 10usize {
        remaining = remaining / 10usize
        divisor = divisor * 10usize
    }
    remaining = value
    while divisor != 0usize {
        try write_digit(file, remaining / divisor)
        remaining = remaining % divisor
        divisor = divisor / 10usize
    }
    ret ok
}

fn write_lower_byte(file: os.File, byte: u8) -> err {
    if byte == 65u8 { ret write_all(file, "a") }
    if byte == 66u8 { ret write_all(file, "b") }
    if byte == 67u8 { ret write_all(file, "c") }
    if byte == 68u8 { ret write_all(file, "d") }
    if byte == 69u8 { ret write_all(file, "e") }
    if byte == 70u8 { ret write_all(file, "f") }
    if byte == 71u8 { ret write_all(file, "g") }
    if byte == 72u8 { ret write_all(file, "h") }
    if byte == 73u8 { ret write_all(file, "i") }
    if byte == 74u8 { ret write_all(file, "j") }
    if byte == 75u8 { ret write_all(file, "k") }
    if byte == 76u8 { ret write_all(file, "l") }
    if byte == 77u8 { ret write_all(file, "m") }
    if byte == 78u8 { ret write_all(file, "n") }
    if byte == 79u8 { ret write_all(file, "o") }
    if byte == 80u8 { ret write_all(file, "p") }
    if byte == 81u8 { ret write_all(file, "q") }
    if byte == 82u8 { ret write_all(file, "r") }
    if byte == 83u8 { ret write_all(file, "s") }
    if byte == 84u8 { ret write_all(file, "t") }
    if byte == 85u8 { ret write_all(file, "u") }
    if byte == 86u8 { ret write_all(file, "v") }
    if byte == 87u8 { ret write_all(file, "w") }
    if byte == 88u8 { ret write_all(file, "x") }
    if byte == 89u8 { ret write_all(file, "y") }
    ret write_all(file, "z")
}

fn write_iterator_name(file: os.File, name: str) -> err {
    var at = 0usize
    while at < name.len {
        let byte = name[at]
        let upper = byte >= 65u8 && byte <= 90u8
        var previous_lower = false
        if at > 0usize {
            let previous = name[at - 1usize]
            previous_lower = (previous >= 97u8 && previous <= 122u8) || (previous >= 48u8 && previous <= 57u8)
        }
        var next_lower = false
        if at + 1usize < name.len {
            let next = name[at + 1usize]
            next_lower = next >= 97u8 && next <= 122u8
        }
        if upper && at > 0usize && (previous_lower || next_lower) { try write_all(file, "_") }
        if upper {
            try write_lower_byte(file, byte)
        } else {
            try write_all(file, name[at..at + 1usize])
        }
        at += 1usize
    }
    ret write_all(file, "_next")
}

fn write_check_message(file: os.File, checker: *check.Checker) -> err {
    if checker.failure_kind == .MissingZeroValue {
        try write_all(file, "type `")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` has no zero value because `")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, "` has no member at 0")
    }
    if checker.failure_kind == .IteratorMissing {
        try write_all(file, "protocol iteration needs `fn ")
        try write_iterator_name(file, checker.failure_detail)
        try write_all(file, "(it: *")
        try write_all(file, checker.failure_detail)
        ret write_all(file, ") -> (T, bool)`")
    }
    if checker.failure_kind == .GenericInference {
        try write_all(file, "cannot infer compile-time parameter `")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "`")
    }
    if checker.failure_kind == .NonExhaustive {
        try write_all(file, "non-exhaustive switch; missing member `")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "`")
    }
    ret write_all(file, check.diagnostic_message(checker.failure_kind))
}

fn print_check_diagnostic(g: *graph.Graph, checker: *check.Checker) -> err {
    let failure = os.stderr()
    if checker.failure_module < g.count {
        try write_all(failure, g.modules[checker.failure_module].path)
    } else {
        try write_all(failure, "<unknown>")
    }
    try write_all(failure, ":")
    if checker.failure_has_token {
        try write_usize(failure, checker.failure_token.line)
        try write_all(failure, ":")
        try write_usize(failure, checker.failure_token.column)
    } else {
        try write_all(failure, "1:1")
    }
    try write_all(failure, ": error[")
    try write_all(failure, check.diagnostic_code(checker.failure_kind))
    try write_all(failure, "]: ")
    try write_check_message(failure, checker)
    ret write_all(failure, "\n")
}

fn print_token_diagnostic(g: *graph.Graph, module_index: usize, token: lex.Token, code: str, message: str) -> err {
    let failure = os.stderr()
    if module_index < g.count {
        try write_all(failure, g.modules[module_index].path)
    } else {
        try write_all(failure, "<unknown>")
    }
    try write_all(failure, ":")
    try write_usize(failure, token.line)
    try write_all(failure, ":")
    try write_usize(failure, token.column)
    try write_all(failure, ": error[")
    try write_all(failure, code)
    try write_all(failure, "]: ")
    try write_all(failure, message)
    ret write_all(failure, "\n")
}

fn print_resolve_diagnostic(g: *graph.Graph, resolver: *resolve.Resolver, resolve_error: err) -> err {
    if resolve_error == resolve.UnknownName && resolver.failure_has_token {
        if resolver.failure_has_context {
            try print_token_diagnostic(g, resolver.failure_module, resolver.failure_context_token, "E-TYPE-0002", "initializer type does not match binding")
        }
        ret print_token_diagnostic(g, resolver.failure_module, resolver.failure_token, "E-NAME-9999", "unknown value name")
    }
    var token: lex.Token = zero
    if resolver.failure_has_token { token = resolver.failure_token }
    ret print_token_diagnostic(g, resolver.failure_module, token, "E-NAME-9999", "name resolution failed")
}

fn select_check_diagnostic(checker: *check.Checker, diagnostic: check.Diagnostic) {
    checker.failure_module = diagnostic.module_index
    checker.failure_kind = diagnostic.kind
    checker.failure_token = diagnostic.token
    checker.failure_has_token = true
    checker.failure_detail = diagnostic.detail
    checker.failure_detail2 = diagnostic.detail2
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
        let parse_error = validate_cli_parse(args[2usize])
        if parse_error != ok { ret parse_error }
        try io.print("parse ok\n")
        ret ok
    }
    if args.len == 3usize && same(args[1usize], "scan-file") {
        let (text, load_error) = source.load(a, args[2usize])
        if load_error != ok { ret load_error }
        let scan_error = lex.validate(text)
        if scan_error != ok { ret scan_error }
        try io.print("scan file ok\n")
        ret ok
    }
    if args.len == 3usize && same(args[1usize], "parse-file") {
        let (text, load_error) = source.load(a, args[2usize])
        if load_error != ok { ret load_error }
        let parse_error = validate_cli_parse(text)
        if parse_error != ok { ret parse_error }
        try io.print("parse file ok\n")
        ret ok
    }
    if args.len == 5usize && same(args[1usize], "project-file") {
        let (discovered, discovery_error) = project.discover(a, args[2usize])
        if discovery_error != ok { ret discovery_error }
        let (module, module_error) = project.module_name(a, discovered, args[2usize])
        if module_error != ok { ret module_error }
        if !same(discovered.root, args[3usize]) || !same(module, args[4usize]) { ret project.InvalidPath }
        try io.print("project file ok\n")
        ret ok
    }
    if args.len == 8usize && same(args[1usize], "select-file") {
        let (selected, selection_error) = project.select_source(a, args[2usize], args[3usize], args[4usize], args[5usize], args[6usize])
        if selection_error != ok { ret selection_error }
        if !project.path_equal(selected, args[7usize]) { ret project.InvalidPath }
        try io.print("source variant ok\n")
        ret ok
    }
    if args.len >= 7usize && same(args[1usize], "graph-file") {
        var loaded: graph.Graph = zero
        try init_cli_graph(a, &loaded)
        try graph.load(a, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
        if loaded.count != args.len - 6usize { ret graph.Capacity }
        var expected = 6usize
        while expected < args.len {
            if !graph.has_module(&loaded, args[expected]) { ret project.ModuleNotFound }
            expected += 1usize
        }
        try io.print("module graph ok\n")
        ret ok
    }
    if args.len == 6usize && same(args[1usize], "resolve-file") {
        var loaded: graph.Graph = zero
        try init_cli_graph(a, &loaded)
        try graph.load(a, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
        var resolver: resolve.Resolver = zero
        try init_cli_resolver(a, &resolver)
        try resolve.collect(&resolver, &loaded)
        try io.print("module resolve ok\n")
        ret ok
    }
    if args.len == 6usize && same(args[1usize], "check-file") {
        var loaded: graph.Graph = zero
        try init_cli_graph(a, &loaded)
        try graph.load(a, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
        var resolver: resolve.Resolver = zero
        try init_cli_resolver(a, &resolver)
        let resolve_error = resolve.collect(&resolver, &loaded)
        if resolve_error != ok {
            try print_resolve_diagnostic(&loaded, &resolver, resolve_error)
            os.exit(1i32)
            ret ok
        }
        var checker: check.Checker = zero
        try init_cli_checker(a, &checker)
        let check_error = check.run(&checker, &resolver, &loaded)
        if check_error != ok {
            if checker.diagnostic_count == 0usize {
                try print_check_diagnostic(&loaded, &checker)
            } else {
                var diagnostic_at = 0usize
                while diagnostic_at < checker.diagnostic_count {
                    select_check_diagnostic(&checker, checker.diagnostics[diagnostic_at])
                    try print_check_diagnostic(&loaded, &checker)
                    diagnostic_at += 1usize
                }
            }
            os.exit(1i32)
            ret ok
        }
        try io.print("module check ok\n")
        ret ok
    }
    let writes_object = args.len == 7usize && same(args[1usize], "emit-object")
    let writes_executable = args.len == 7usize && same(args[1usize], "emit-executable")
    if (args.len == 6usize && (same(args[1usize], "nir-file") || same(args[1usize], "codegen-file") || same(args[1usize], "object-file"))) || writes_object || writes_executable {
        let emit_object = same(args[1usize], "object-file") || writes_object
        let emit_machine_code = same(args[1usize], "codegen-file") || emit_object || writes_executable
        var loaded: graph.Graph = zero
        try init_cli_graph(a, &loaded)
        try graph.load(a, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
        var resolver: resolve.Resolver = zero
        try init_cli_resolver(a, &resolver)
        let resolve_error = resolve.collect(&resolver, &loaded)
        if resolve_error != ok {
            try print_resolve_diagnostic(&loaded, &resolver, resolve_error)
            os.exit(1i32)
            ret ok
        }
        var checker: check.Checker = zero
        try init_cli_checker(a, &checker)
        let check_error = check.run(&checker, &resolver, &loaded)
        if check_error != ok {
            if checker.diagnostic_count == 0usize {
                try print_check_diagnostic(&loaded, &checker)
            } else {
                var diagnostic_at = 0usize
                while diagnostic_at < checker.diagnostic_count {
                    select_check_diagnostic(&checker, checker.diagnostics[diagnostic_at])
                    try print_check_diagnostic(&loaded, &checker)
                    diagnostic_at += 1usize
                }
            }
            os.exit(1i32)
            ret ok
        }
        var builder: nir.Builder = zero
        var signatures: nir.Signatures = zero
        try init_cli_nir(a, &builder, &signatures, checker.parameter_count + checker.return_type_count)
        let (bindings, bindings_error) = mem.alloc[lower.Binding](a, 16384usize)
        if bindings_error != ok { ret bindings_error }
        let (lowered_modules, lowered_modules_error) = mem.alloc[bool](a, 128usize)
        if lowered_modules_error != ok { ret lowered_modules_error }
        try lower.reachable_modules(&checker, &loaded, &builder, &signatures, bindings, lowered_modules)
        let (ranges, ranges_error) = mem.alloc[regalloc.LiveRange](a, 32768usize)
        if ranges_error != ok { ret ranges_error }
        let (allocations, allocations_error) = mem.alloc[regalloc.Allocation](a, 32768usize)
        if allocations_error != ok { ret allocations_error }
        let (machine_storage, machine_storage_error) = mem.alloc[usize](a, 131072usize)
        if machine_storage_error != ok { ret machine_storage_error }
        var machine: emit_x64.Buffer = zero
        try emit_x64.init(&machine, machine_storage)
        let (block_offsets, block_offsets_error) = mem.alloc[usize](a, 8192usize)
        if block_offsets_error != ok { ret block_offsets_error }
        let (fixups, fixups_error) = mem.alloc[codegen_x64.Fixup](a, 32768usize)
        if fixups_error != ok { ret fixups_error }
        let (relocations, relocations_error) = mem.alloc[codegen_x64.Relocation](a, 32768usize)
        if relocations_error != ok { ret relocations_error }
        let (function_offsets, function_offsets_error) = mem.alloc[usize](a, 1024usize)
        if function_offsets_error != ok { ret function_offsets_error }
        var relocation_count = 0usize
        var function_at = 0usize
        var machine_abi: codegen_x64.Abi = .SystemV
        if same(args[5usize], "windows") { machine_abi = .Windows }
        var codegen_context: codegen_x64.FunctionContext = zero
        codegen_context.allocations = allocations
        codegen_context.abi = machine_abi
        codegen_context.block_offsets = block_offsets
        codegen_context.fixups = fixups
        codegen_context.relocations = relocations
        codegen_context.relocation_count = &relocation_count
        codegen_context.output = &machine
        while function_at < builder.function_count {
            let (stack_slots, allocation_error) = regalloc.allocate(&builder, function_at, 5usize, ranges, allocations)
            if allocation_error != ok { ret allocation_error }
            if emit_machine_code {
                function_offsets[function_at] = machine.count
                try codegen_x64.function(&builder, function_at, stack_slots, &codegen_context)
            }
            function_at += 1usize
        }
        if emit_machine_code {
            try codegen_x64.resolve_calls(&builder, function_offsets, relocations, relocation_count, &machine)
            if writes_executable {
                let (executable_storage, executable_storage_error) = mem.alloc[usize](a, 1048576usize)
                if executable_storage_error != ok { ret executable_storage_error }
                var executable: emit_x64.Buffer = zero
                try emit_x64.init(&executable, executable_storage)
                if machine_abi == .Windows {
                    try link_pe.write(&builder, &machine, function_offsets, relocations, relocation_count, &executable)
                } else {
                    try link_elf.write(&builder, &machine, function_offsets, relocations, relocation_count, &executable)
                }
                let (packed, packed_error) = mem.alloc[u8](a, executable.count)
                if packed_error != ok { ret packed_error }
                try emit_x64.pack(&executable, packed)
                try save_bytes(a, args[6usize], packed)
                try io.print("executable written\n")
                ret ok
            }
            if emit_object {
                let (object_storage, object_storage_error) = mem.alloc[usize](a, 262144usize)
                if object_storage_error != ok { ret object_storage_error }
                var object: emit_x64.Buffer = zero
                try emit_x64.init(&object, object_storage)
                if machine_abi == .Windows {
                    let (symbols, symbols_error) = mem.alloc[object_coff.Symbol](a, 16384usize)
                    if symbols_error != ok { ret symbols_error }
                    try object_coff.write(&builder, &machine, function_offsets, relocations, relocation_count, symbols, &object)
                } else {
                    let (symbols, symbols_error) = mem.alloc[object_elf.Symbol](a, 16384usize)
                    if symbols_error != ok { ret symbols_error }
                    try object_elf.write(&builder, &machine, function_offsets, relocations, relocation_count, symbols, &object)
                }
                if writes_object {
                    let (packed, packed_error) = mem.alloc[u8](a, object.count)
                    if packed_error != ok { ret packed_error }
                    try emit_x64.pack(&object, packed)
                    try save_bytes(a, args[6usize], packed)
                    try io.print("object written\n")
                    ret ok
                }
                try io.print("module object ok\n")
                ret ok
            }
            try io.print("module codegen ok\n")
            ret ok
        }
        try io.print("module nir ok\n")
        ret ok
    }
    try io.print("usage: neper-self scan|parse SOURCE | scan-file|parse-file PATH | project-file PATH ROOT MODULE | select-file ROOT SOURCE_ROOT MODULE ARCH OS PATH | graph-file PATH TOOLCHAIN_ROOT ARCH OS MODULE... | resolve-file|check-file|nir-file|codegen-file|object-file PATH TOOLCHAIN_ROOT ARCH OS | emit-object|emit-executable PATH TOOLCHAIN_ROOT ARCH OS OUTPUT\n")
    ret ok
}
