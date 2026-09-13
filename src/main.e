use e.io
use e.mem
use e.os
use artifact_hash
use binary
use check
use decimal
use codegen_x64
use em
use em_link
use error_table
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
use tool

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
    try binary.self_test()
    try em.self_test()
    try error_table.self_test()
    try decimal.self_test()
    try check.format_self_test()
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

// The flags after an emit command's five positional arguments; `--arena` takes the
// size after it (D225).
fn has_flag(args: []str, name: str) -> bool {
    var at = 7usize
    while at < args.len {
        if same(args[at], name) { ret true }
        if same(args[at], "--arena") { at += 1usize }
        at += 1usize
    }
    ret false
}

fn flags_known(args: []str) -> bool {
    var at = 7usize
    while at < args.len {
        if same(args[at], "--arena") {
            if at + 1usize >= args.len { ret false }
            let (size, size_ok) = arena_size(args[at + 1usize])
            if !size_ok { ret false }
            at += 1usize
        } else {
            if !same(args[at], "--release") && !same(args[at], "--incremental") { ret false }
        }
        at += 1usize
    }
    ret true
}

// `--arena 1g`: a count of bytes with an optional k, m or g, at least a mebibyte.
fn arena_size(spelling: str) -> (usize, bool) {
    if spelling.len == 0usize { ret (0usize, false) }
    var value = 0usize
    var at = 0usize
    while at < spelling.len {
        let byte = spelling[at]
        if byte >= 48u8 && byte <= 57u8 {
            if value > 18446744073709551usize { ret (0usize, false) }
            value = value * 10usize + usize(byte - 48u8)
        } else {
            if at == 0usize || at + 1usize != spelling.len { ret (0usize, false) }
            if byte == 107u8 { value = value * 1024usize } else {
                if byte == 109u8 { value = value * 1048576usize } else {
                    if byte == 103u8 { value = value * 1073741824usize } else { ret (0usize, false) }
                }
            }
        }
        at += 1usize
    }
    if value < 1048576usize { ret (0usize, false) }
    ret (value, true)
}

fn arena_flag(args: []str) -> usize {
    var at = 7usize
    while at + 1usize < args.len {
        if same(args[at], "--arena") {
            let (size, size_ok) = arena_size(args[at + 1usize])
            if size_ok { ret size }
        }
        at += 1usize
    }
    ret 0usize
}

// The file's name without its directories, for an operand's source identity.
fn basename(path: str) -> str {
    var start = 0usize
    var at = 0usize
    while at < path.len {
        if path[at] == 47u8 || path[at] == 92u8 { start = at + 1usize }
        at += 1usize
    }
    ret path[start..path.len]
}

fn tool_usage() -> err {
    try stderr_text("error[E-CLI-9999]: usage: neper-self tokens|parse [--json] [--path VIRTUAL.e] FILE, or info --json\n")
    os.exit(1i32)
    ret ok
}

// The target this compiler runs on, for `info` (D229).
// ponytail: probed from the standard-handle value -- a Linux fd is 2, a Windows HANDLE
// never is -- until the runtime has a host intrinsic.
fn host_target() -> str {
    if os.stderr().raw == 2usize { ret "x64-linux" }
    ret "x64-windows"
}

// docs/tooling.md section 4: `tokens|parse [--json] [--path VIRTUAL.e] FILE` (D227),
// its own function since the bootstrap caps a function's locals.
fn tool_command(a: *mem.Arena, args: []str) -> err {
    var report = stderr_sink()
    let parsing = same(args[1usize], "parse")
    var json = false
    var virtual_path = ""
    var has_virtual = false
    var file = ""
    var has_file = false
    var at = 2usize
    while at < args.len {
        if same(args[at], "--json") {
            json = true
        } else {
            if same(args[at], "--path") && at + 1usize < args.len {
                virtual_path = args[at + 1usize]
                has_virtual = true
                at += 1usize
            } else {
                if has_file {
                    has_file = false
                    break
                }
                file = args[at]
                has_file = true
            }
        }
        at += 1usize
    }
    if !has_file || same(file, "-") { ret tool_usage() }
    let (text, load_error) = source.load(a, file)
    if load_error != ok { ret load_error }
    var path = virtual_path
    if !has_virtual { path = basename(file) }
    if json {
        var exit_code = 0usize
        if parsing {
            let (parse_exit, parse_error) = tool.parse_json(a, "operand", path, text)
            if parse_error != ok { ret parse_error }
            exit_code = parse_exit
        } else {
            let (tokens_exit, tokens_error) = tool.tokens_json(a, "operand", path, text)
            if tokens_error != ok { ret tokens_error }
            exit_code = tokens_exit
        }
        if exit_code != 0usize { os.exit(i32(exit_code)) }
        ret ok
    }
    if parsing {
        let parse_error = validate_cli_parse(a, &report, file, text)
        if parse_error != ok { ret parse_error }
        try io.print("parse file ok\n")
        ret ok
    }
    var scanner = lex.init(text)
    while true {
        let token = lex.next(&scanner)
        try io.print(tool.kind_name(token.kind))
        if token.kind != .Newline && token.kind != .Eof {
            try io.print(" ")
            try io.print(text[token.start..token.end])
        }
        try io.print("\n")
        if token.kind == .Eof { break }
    }
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

fn validate_cli_parse(a: *mem.Arena, report: *Sink, path: str, text: str) -> err {
    // The CLI supplies explicit storage; parser lists have no separate caps.
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, 4096usize)
    if nodes_error != ok { ret nodes_error }
    let (children, children_error) = mem.alloc[syntax.Child](a, 65536usize)
    if children_error != ok { ret children_error }
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, nodes, children)
    let parse_error = parse.parse(&tree, text)
    if parse_error != ok && tree.has_failure {
        try print_parse_failure(report, path, text, tree.failure_token, tree.failure_reserved_name)
        os.exit(1i32)
    }
    ret parse_error
}

fn init_cli_graph(a: *mem.Arena, loaded: *graph.Graph) -> err {
    let (modules, modules_error) = mem.alloc[graph.Module](a, 128usize)
    if modules_error != ok { ret modules_error }
    let (imports, imports_error) = mem.alloc[graph.Import](a, 2048usize)
    if imports_error != ok { ret imports_error }
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, 65536usize)
    if nodes_error != ok { ret nodes_error }
    let (children, children_error) = mem.alloc[syntax.Child](a, 524288usize)
    if children_error != ok { ret children_error }
    ret graph.init(loaded, modules, imports, nodes, children)
}

fn init_cli_resolver(a: *mem.Arena, resolver: *resolve.Resolver) -> err {
    let (symbols, symbols_error) = mem.alloc[resolve.Symbol](a, 16384usize)
    if symbols_error != ok { ret symbols_error }
    // The largest module, `check.e`, needs between 65536 and 69632 tokens, measured
    // by bisecting this until resolution reports `resolve.Capacity`. 131072 keeps
    // about twice that; `MAX_TOKENS` in the bootstrap is the same number for the same
    // reason.
    let (tokens, tokens_error) = mem.alloc[lex.Token](a, 131072usize)
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
    let (function_signatures, function_signatures_error) = mem.alloc[check.FunctionSignature](a, 4096usize)
    if function_signatures_error != ok { ret function_signatures_error }
    let (tokens, tokens_error) = mem.alloc[lex.Token](a, 131072usize)
    if tokens_error != ok { ret tokens_error }
    let (locals, locals_error) = mem.alloc[check.Local](a, 16384usize)
    if locals_error != ok { ret locals_error }
    let (types, types_error) = mem.alloc[check.Type](a, 65536usize)
    if types_error != ok { ret types_error }
    let (aliases, aliases_error) = mem.alloc[check.Alias](a, 4096usize)
    if aliases_error != ok { ret aliases_error }
    let (constants, constants_error) = mem.alloc[check.Constant](a, 4096usize)
    if constants_error != ok { ret constants_error }
    // Module-scope `var`s. Small on purpose: the whole point of the surface is that ambient
    // mutable state is rare, and a program that wants hundreds of them wants a struct instead.
    let (globals, globals_error) = mem.alloc[check.Global](a, 256usize)
    if globals_error != ok { ret globals_error }
    let (constant_exprs, constant_exprs_error) = mem.alloc[check.ConstantExpr](a, 32768usize)
    if constant_exprs_error != ok { ret constant_exprs_error }
    let (diagnostics, diagnostics_error) = mem.alloc[check.Diagnostic](a, 4096usize)
    if diagnostics_error != ok { ret diagnostics_error }
    try check.init(checker, functions, parameters, return_types, tokens, locals, types, aliases, constants, globals, constant_exprs, diagnostics)
    try check.init_generics(checker, function_generics, comptime_parameters, generic_arguments)
    try check.init_aggregates(checker, aggregates, aggregate_fields)
    ret check.init_control(checker, checked_switches, function_signatures)
}

// The inlining oracle's builder (D207): the short functions of every module, which the
// source filter keeps to a few instructions each, so a tenth of the program's tables.
fn init_oracle_nir(a: *mem.Arena, builder: *nir.Builder, signatures: *nir.Signatures, signature_type_capacity: usize) -> err {
    let (functions, functions_error) = mem.alloc[nir.Function](a, 4096usize)
    if functions_error != ok { ret functions_error }
    let (blocks, blocks_error) = mem.alloc[nir.Block](a, 32768usize)
    if blocks_error != ok { ret blocks_error }
    let (instructions, instructions_error) = mem.alloc[nir.Instruction](a, 131072usize)
    if instructions_error != ok { ret instructions_error }
    let (operands, operands_error) = mem.alloc[usize](a, 524288usize)
    if operands_error != ok { ret operands_error }
    let (function_refs, function_refs_error) = mem.alloc[nir.FunctionRef](a, 8192usize)
    if function_refs_error != ok { ret function_refs_error }
    let (strings, strings_error) = mem.alloc[nir.StringConstant](a, 8192usize)
    if strings_error != ok { ret strings_error }
    try nir.init(builder, functions, blocks, instructions, operands, function_refs, strings)
    let (global_data, global_data_error) = mem.alloc[nir.GlobalData](a, 256usize)
    if global_data_error != ok { ret global_data_error }
    try nir.init_globals(builder, global_data)
    let (signature_entries, signature_entries_error) = mem.alloc[nir.Signature](a, 4096usize)
    if signature_entries_error != ok { ret signature_entries_error }
    var type_capacity = signature_type_capacity
    if type_capacity == 0usize { type_capacity = 1usize }
    let (signature_types, signature_types_error) = mem.alloc[check.Type](a, type_capacity)
    if signature_types_error != ok { ret signature_types_error }
    ret nir.init_signatures(signatures, signature_entries, signature_types)
}

fn init_cli_nir(a: *mem.Arena, builder: *nir.Builder, signatures: *nir.Signatures, signature_type_capacity: usize, compiler_scale: bool) -> err {
    // Every module carries its own copy of the generic instances it uses, so the
    // NIR function count scales with instantiation sites, not with declarations.
    var function_capacity = 1024usize
    var block_capacity = 8192usize
    var instruction_capacity = 32768usize
    var operand_capacity = 131072usize
    if compiler_scale {
        function_capacity = 16384usize
        block_capacity = 131072usize
        instruction_capacity = 524288usize
        operand_capacity = 2097152usize
    }
    let (functions, functions_error) = mem.alloc[nir.Function](a, function_capacity)
    if functions_error != ok { ret functions_error }
    let (blocks, blocks_error) = mem.alloc[nir.Block](a, block_capacity)
    if blocks_error != ok { ret blocks_error }
    let (instructions, instructions_error) = mem.alloc[nir.Instruction](a, instruction_capacity)
    if instructions_error != ok { ret instructions_error }
    let (operands, operands_error) = mem.alloc[usize](a, operand_capacity)
    if operands_error != ok { ret operands_error }
    let (function_refs, function_refs_error) = mem.alloc[nir.FunctionRef](a, 8192usize)
    if function_refs_error != ok { ret function_refs_error }
    let (strings, strings_error) = mem.alloc[nir.StringConstant](a, 8192usize)
    if strings_error != ok { ret strings_error }
    try nir.init(builder, functions, blocks, instructions, operands, function_refs, strings)
    let (global_data, global_data_error) = mem.alloc[nir.GlobalData](a, 256usize)
    if global_data_error != ok { ret global_data_error }
    try nir.init_globals(builder, global_data)
    // One entry per NIR function, indexed by the same function index: a signature
    // table smaller than the function table makes every function past its end fail to
    // lower, and `begin_signature` reports that as invalid control flow rather than as
    // a capacity. It sat at 1024 against a function capacity of 16384, and the compiler
    // itself had reached 1024 -- adding any ten functions to `check.e` broke the build,
    // in whichever unrelated function happened to cross the line.
    let (signature_entries, signature_entries_error) = mem.alloc[nir.Signature](a, function_capacity)
    if signature_entries_error != ok { ret signature_entries_error }
    var type_capacity = signature_type_capacity
    if type_capacity == 0usize { type_capacity = 1usize }
    let (signature_types, signature_types_error) = mem.alloc[check.Type](a, type_capacity)
    if signature_types_error != ok { ret signature_types_error }
    ret nir.init_signatures(signatures, signature_entries, signature_types)
}

// Where diagnostic text goes (D228): a file, or a buffer when the text is a JSON
// record's message rather than a line on stderr.
type Sink = struct {
    file: os.File,
    capture: []u8,
    count: usize,
    capturing: bool,
    // `--json` (D228): a diagnostic is a record on stdout, not a line on stderr.
    json: bool,
}

// One diagnostic, as the human line `path:line:col: error[CODE]: message` or as the
// record of docs/tooling.md section 3 -- the span from the token, the source as an
// operand named by the file's basename.
fn emit_diagnostic(report: *Sink, path: str, token: lex.Token, has_token: bool, code: str, message: str) -> err {
    if !report.json {
        try write_all(report, path)
        try write_all(report, ":")
        if has_token {
            try write_usize(report, token.line)
            try write_all(report, ":")
            try write_usize(report, token.column)
        } else {
            try write_all(report, "1:1")
        }
        try write_all(report, ": error[")
        try write_all(report, code)
        try write_all(report, "]: ")
        try write_all(report, message)
        ret write_all(report, "\n")
    }
    var at = token
    if !has_token {
        var origin: lex.Token = zero
        origin.line = 1usize
        origin.column = 1usize
        origin.end_line = 1usize
        origin.end_column = 1usize
        origin.column_utf16 = 1usize
        origin.end_column_utf16 = 1usize
        at = origin
    }
    try write_all(report, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":")
    try write_json_string(report, code)
    try write_all(report, ",\"message\":")
    try write_json_string(report, message)
    try write_all(report, ",\"span\":{\"source\":{\"root\":\"operand\",\"path\":")
    try write_json_string(report, basename(path))
    try write_all(report, "},\"byte_start\":")
    try write_usize(report, at.start)
    try write_all(report, ",\"byte_end\":")
    try write_usize(report, at.end)
    try write_all(report, ",\"line\":")
    try write_usize(report, at.line)
    try write_all(report, ",\"column\":")
    try write_usize(report, at.column)
    try write_all(report, ",\"end_line\":")
    try write_usize(report, at.end_line)
    try write_all(report, ",\"end_column\":")
    try write_usize(report, at.end_column)
    try write_all(report, ",\"column_utf16\":")
    try write_usize(report, at.column_utf16)
    try write_all(report, ",\"end_column_utf16\":")
    try write_usize(report, at.end_column_utf16)
    try write_all(report, "},\"parent\":null,\"related\":[],\"fixes\":[]}")
    try write_all(report, "\n")
    report.count += 1usize
    ret ok
}

// A diagnostic with no location: a command's own, such as an operand that cannot be
// read (D228).
fn emit_command_diagnostic(report: *Sink, code: str, message: str) -> err {
    if !report.json {
        try write_all(report, "error[")
        try write_all(report, code)
        try write_all(report, "]: ")
        try write_all(report, message)
        ret write_all(report, "\n")
    }
    try write_all(report, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":")
    try write_json_string(report, code)
    try write_all(report, ",\"message\":")
    try write_json_string(report, message)
    try write_all(report, ",\"span\":null,\"parent\":null,\"related\":[],\"fixes\":[]}\n")
    report.count += 1usize
    ret ok
}

fn write_json_string(report: *Sink, value: str) -> err {
    try write_all(report, "\"")
    var at = 0usize
    while at < value.len {
        let c = value[at]
        if c == 34u8 {
            try write_all(report, "\\\"")
        } else {
            if c == 92u8 {
                try write_all(report, "\\\\")
            } else {
                if c == 10u8 {
                    try write_all(report, "\\n")
                } else {
                    if c < 32u8 {
                        try write_all(report, "\\u00")
                        try write_digit(report, usize(c) / 16usize)
                        try write_digit(report, usize(c) % 16usize)
                    } else {
                        try write_all(report, value[at..at + 1usize])
                    }
                }
            }
        }
        at += 1usize
    }
    ret write_all(report, "\"")
}

// A JSON report ends with the result record; a human one ends with nothing.
fn finish_report(report: *Sink) -> err {
    if !report.json { ret ok }
    try write_all(report, "{\"record\":\"result\",\"ok\":")
    if report.count == 0usize { try write_all(report, "true,\"exit_code\":0") } else { try write_all(report, "false,\"exit_code\":1") }
    try write_all(report, ",\"data\":{\"diagnostics\":")
    try write_usize(report, report.count)
    ret write_all(report, "}}\n")
}

fn stderr_text(text: str) -> err {
    var sink = stderr_sink()
    ret write_all(&sink, text)
}

fn stderr_sink() -> Sink {
    var sink: Sink = zero
    sink.file = os.stderr()
    ret sink
}

fn capture_sink(capture: []u8) -> Sink {
    var sink: Sink = zero
    sink.capture = capture
    sink.capturing = true
    ret sink
}

fn write_all(sink: *Sink, text: str) -> err {
    if sink.capturing {
        var copy_at = 0usize
        while copy_at < text.len {
            if sink.count == sink.capture.len { ret DiagnosticWrite }
            sink.capture[sink.count] = text[copy_at]
            sink.count += 1usize
            copy_at += 1usize
        }
        ret ok
    }
    var at = 0usize
    while at < text.len {
        let (written, write_error) = os.write(sink.file, text[at..])
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

// The artifact readers take one `usize` per byte, so a fresh artifact held as bytes is
// widened for the duration of a question and released with the arena mark around it.
fn widen_artifact(a: *mem.Arena, packed: []const u8) -> ([]usize, err) {
    let (bytes, bytes_error) = mem.alloc[usize](a, packed.len)
    if bytes_error != ok { ret (bytes, bytes_error) }
    var at = 0usize
    while at < packed.len {
        bytes[at] = usize(packed[at])
        at += 1usize
    }
    ret (bytes, ok)
}

// Section 12's edge rule over a directory of artifacts: a module's old artifact stays
// when its source hash is unchanged and every edge it recorded still matches the
// declaration it names in the target's fresh artifact; otherwise the fresh one is
// written over it. Each module's decision is printed, `kept` or `rebuilt`, in module
// order, and the decisions are all taken before any file is touched.
// Section 12's edge rule, settled before anything is lowered (D214): a module's artifact
// on disk is kept when its source and build mode are unchanged and every edge it
// recorded still matches the declaration it names in the target's fresh Interface --
// which the checker alone can write. A kept module is then not lowered, selected or
// written at all; that is the saving.
fn settle_early(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, directory: str, triple: str, mode: em.BuildMode, strings: *em.StringTable, scratch: *binary.Buffer, keep: []bool) -> err {
    let (fresh, fresh_error) = mem.alloc[[]usize](a, g.count)
    if fresh_error != ok { ret fresh_error }
    let (sections, sections_error) = mem.alloc[em.Section](a, 2usize)
    if sections_error != ok { ret sections_error }
    let (interface_storage, interface_storage_error) = mem.alloc[usize](a, 1048576usize)
    if interface_storage_error != ok { ret interface_storage_error }
    var interface_buffer: binary.Buffer = zero
    try binary.init(&interface_buffer, interface_storage)
    var mode_id = 0usize
    if mode == .Release { mode_id = 1usize }
    // Every module's fresh Interface first: small, and held for the whole walk.
    var module_at = 0usize
    while module_at < g.count {
        keep[module_at] = false
        interface_buffer.count = 0usize
        try em.write_interface_artifact(c, g, module_at, triple, mode, strings, sections, scratch, &interface_buffer)
        let (held, held_error) = mem.alloc[usize](a, interface_buffer.count)
        if held_error != ok { ret held_error }
        var copy_at = 0usize
        while copy_at < interface_buffer.count {
            held[copy_at] = interface_buffer.bytes[copy_at]
            copy_at += 1usize
        }
        fresh[module_at] = held
        module_at += 1usize
    }
    module_at = 0usize
    while module_at < g.count {
        let checkpoint = mem.mark(a)
        let (artifact_path, path_error) = compiled_module_path(a, directory, g.modules[module_at].name, triple)
        if path_error != ok { ret path_error }
        let (old, old_error) = load_artifact(a, artifact_path)
        if old_error == ok {
            let (old_hash, old_hash_error) = em.artifact_source_hash(old)
            let (new_hash, new_hash_error) = em.source_text_hash(g.modules[module_at].text, scratch)
            let (old_mode, old_mode_error) = em.artifact_mode(old)
            if old_hash_error == ok && new_hash_error == ok && old_hash == new_hash && old_mode_error == ok && old_mode == mode_id {
                keep[module_at] = true
                let (edge_count, count_error) = em.artifact_dependency_count(old)
                if count_error != ok { ret count_error }
                var edge_at = 0usize
                while edge_at < edge_count && keep[module_at] {
                    let (dependency, dependency_error) = em.dependency_at(old, edge_at)
                    if dependency_error != ok { ret dependency_error }
                    let (target_name, target_name_error) = artifact_string(a, old, dependency.module_index)
                    if target_name_error != ok { ret target_name_error }
                    var target_at = 0usize
                    var found_target = false
                    while target_at < g.count {
                        if same(g.modules[target_at].name, target_name) {
                            found_target = true
                            break
                        }
                        target_at += 1usize
                    }
                    if !found_target {
                        keep[module_at] = false
                    } else {
                        let (matches, match_error) = em.dependency_matches(old, edge_at, fresh[target_at])
                        if match_error != ok { ret match_error }
                        if !matches { keep[module_at] = false }
                    }
                    edge_at += 1usize
                }
            }
        }
        mem.reset(a, checkpoint)
        module_at += 1usize
    }
    ret ok
}

fn load_artifact(a: *mem.Arena, path: str) -> ([]usize, err) {
    let (packed, load_error) = source.load(a, path)
    if load_error != ok {
        var empty: []usize = zero
        ret (empty, load_error)
    }
    let (bytes, bytes_error) = mem.alloc[usize](a, packed.len)
    if bytes_error != ok { ret (bytes, bytes_error) }
    var at = 0usize
    while at < packed.len {
        bytes[at] = usize(packed[at])
        at += 1usize
    }
    // The checksum is checked here, once; the readers check the layout alone (D213).
    let validation_error = em.validate(bytes)
    if validation_error != ok { ret (bytes, validation_error) }
    ret (bytes, ok)
}

fn artifact_string(a: *mem.Arena, bytes: []const usize, index: usize) -> (str, err) {
    let (start, length, bounds_error) = em.string_bounds(bytes, index)
    if bounds_error != ok { ret ("", bounds_error) }
    let (storage, storage_error) = mem.alloc[u8](a, length)
    if storage_error != ok { ret ("", storage_error) }
    var at = 0usize
    while at < length {
        if bytes[start + at] > 255usize { ret ("", em.InvalidArtifact) }
        storage[at] = u8(bytes[start + at])
        at += 1usize
    }
    ret (storage[..], ok)
}

fn print_artifact_error_collision(a: *mem.Arena, left_bytes: []const usize, left: em.ErrorValue, right_bytes: []const usize, right: em.ErrorValue) -> err {
    let (left_module, left_module_error) = artifact_string(a, left_bytes, left.module_index)
    if left_module_error != ok { ret left_module_error }
    let (left_name, left_name_error) = artifact_string(a, left_bytes, left.name_index)
    if left_name_error != ok { ret left_name_error }
    let (right_module, right_module_error) = artifact_string(a, right_bytes, right.module_index)
    if right_module_error != ok { ret right_module_error }
    let (right_name, right_name_error) = artifact_string(a, right_bytes, right.name_index)
    if right_name_error != ok { ret right_name_error }
    var failure = stderr_sink()
    try write_all(&failure, "error[E-LINK-9999]: error hash collision: `")
    try write_qualified_error(&failure, left_module, left_name)
    try write_all(&failure, "` and `")
    try write_qualified_error(&failure, right_module, right_name)
    ret write_all(&failure, "` have the same 32-bit FNV-1a value\n")
}

fn merge_artifact_error_tables(a: *mem.Arena, artifacts: []em_link.Artifact) -> (bool, err) {
    // Read every artifact's error table once. Reading them entry by entry re-validated the whole
    // artifact -- a CRC -- and re-walked its interface on each call, so the value comparison below
    // was O(errors^2) CRCs; over the collected tables it is O(errors^2) integer compares, and a
    // name is only fetched when two values actually collide.
    var total = 0usize
    var artifact_at = 0usize
    while artifact_at < artifacts.len {
        let (count, count_error) = em.artifact_error_count(artifacts[artifact_at].bytes)
        if count_error != ok { ret (false, count_error) }
        total += count
        artifact_at += 1usize
    }
    if total == 0usize { ret (true, ok) }
    let (errors, errors_alloc_error) = mem.alloc[em.ErrorValue](a, total)
    if errors_alloc_error != ok { ret (false, errors_alloc_error) }
    let (owners, owners_alloc_error) = mem.alloc[usize](a, total)
    if owners_alloc_error != ok { ret (false, owners_alloc_error) }
    var filled = 0usize
    artifact_at = 0usize
    while artifact_at < artifacts.len {
        let (count, count_error) = em.read_error_table(artifacts[artifact_at].bytes, errors[filled..total])
        if count_error != ok { ret (false, count_error) }
        var at = 0usize
        while at < count {
            owners[filled + at] = artifact_at
            at += 1usize
        }
        filled += count
        artifact_at += 1usize
    }
    var left_at = 0usize
    while left_at < total {
        var right_at = left_at + 1usize
        while right_at < total {
            if errors[left_at].value == errors[right_at].value {
                let left_owner = owners[left_at]
                let right_owner = owners[right_at]
                let (same_module, module_error) = em.strings_equal(artifacts[left_owner].bytes, errors[left_at].module_index, artifacts[right_owner].bytes, errors[right_at].module_index)
                if module_error != ok { ret (false, module_error) }
                let (same_name, name_error) = em.strings_equal(artifacts[left_owner].bytes, errors[left_at].name_index, artifacts[right_owner].bytes, errors[right_at].name_index)
                if name_error != ok { ret (false, name_error) }
                if !same_module || !same_name {
                    let print_error = print_artifact_error_collision(a, artifacts[left_owner].bytes, errors[left_at], artifacts[right_owner].bytes, errors[right_at])
                    if print_error != ok { ret (false, print_error) }
                    ret (false, ok)
                }
            }
            right_at += 1usize
        }
        left_at += 1usize
    }
    ret (true, ok)
}

fn target_triple(a: *mem.Arena, arch: str, operating_system: str) -> (str, err) {
    let length = arch.len + 1usize + operating_system.len
    let (storage, storage_error) = mem.alloc[u8](a, length)
    if storage_error != ok { ret ("", storage_error) }
    var at = 0usize
    while at < arch.len {
        storage[at] = arch[at]
        at += 1usize
    }
    storage[arch.len] = 45u8
    at = 0usize
    while at < operating_system.len {
        storage[arch.len + 1usize + at] = operating_system[at]
        at += 1usize
    }
    ret (storage[..], ok)
}

fn compiled_module_path(a: *mem.Arena, directory: str, module_name: str, triple: str) -> (str, err) {
    var separator_count = 1usize
    if directory.len != 0usize && (directory[directory.len - 1usize] == 47u8 || directory[directory.len - 1usize] == 92u8) { separator_count = 0usize }
    let length = directory.len + separator_count + module_name.len + 1usize + triple.len + 3usize
    let (storage, storage_error) = mem.alloc[u8](a, length)
    if storage_error != ok { ret ("", storage_error) }
    var written = 0usize
    var at = 0usize
    while at < directory.len {
        storage[written] = directory[at]
        written += 1usize
        at += 1usize
    }
    if separator_count != 0usize {
        storage[written] = 47u8
        written += 1usize
    }
    at = 0usize
    while at < module_name.len {
        storage[written] = module_name[at]
        written += 1usize
        at += 1usize
    }
    storage[written] = 46u8
    written += 1usize
    at = 0usize
    while at < triple.len {
        storage[written] = triple[at]
        written += 1usize
        at += 1usize
    }
    storage[written] = 46u8
    storage[written + 1usize] = 101u8
    storage[written + 2usize] = 109u8
    written += 3usize
    if written != length { ret ("", DiagnosticWrite) }
    ret (storage[..], ok)
}

fn write_digit(file: *Sink, digit: usize) -> err {
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

fn write_usize(file: *Sink, value: usize) -> err {
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

fn write_lower_byte(file: *Sink, byte: u8) -> err {
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

fn write_snake_name(file: *Sink, name: str) -> err {
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
    ret ok
}

fn write_check_message(file: *Sink, checker: *check.Checker, check_error: err) -> err {
    if checker.failure_kind == .MissingZeroValue {
        try write_all(file, "type `")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` has no zero value because `")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, "` has no member at 0")
    }
    if checker.failure_kind == .IteratorMissing {
        try write_all(file, "protocol iteration needs `fn ")
        try write_snake_name(file, checker.failure_detail)
        try write_all(file, "_next")
        try write_all(file, "(it: *")
        try write_all(file, checker.failure_detail)
        ret write_all(file, ") -> (T, bool)`")
    }
    if checker.failure_kind == .ProtocolMissing {
        try write_all(file, "no `")
        try write_all(file, checker.failure_detail2)
        try write_all(file, "` protocol for `")
        try write_all(file, checker.failure_detail)
        try write_all(file, "`; declare `fn ")
        try write_snake_name(file, checker.failure_detail)
        try write_all(file, "_")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, "` in the module that declares the type")
    }
    if checker.failure_kind == .ProtocolSignature {
        try write_all(file, "protocol `")
        try write_all(file, checker.failure_detail2)
        try write_all(file, "` must take `")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "` by value as its first parameter")
    }
    if checker.failure_kind == .ProtocolGenericType {
        try write_all(file, "a generic protocol function for `")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "` is not supported yet")
    }
    if checker.failure_kind == .ExternWithoutImport {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "` is an extern fn with no `@import(LIBRARY, SYMBOL)`, so there is nothing to bind it to")
    }
    if checker.failure_kind == .ExternType {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` is an extern fn and `")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, "` does not cross the C ABI (spec section 5's table), so it cannot be a parameter or return of one")
    }
    if check_error == check.ComptimeDeferred {
        ret write_all(file, "a constant that calls a function is used in a type or another module-scope declaration, which is settled before the program's functions are known")
    }
    if checker.failure_kind == .ComptimeEvaluation {
        if checker.failure_detail.len == 0usize {
            try write_all(file, "a `when` condition cannot be evaluated at compile time: it reached ")
            ret write_all(file, checker.failure_detail2)
        }
        try write_all(file, "constant `")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` cannot be evaluated at compile time: its call reached ")
        ret write_all(file, checker.failure_detail2)
    }
    if checker.failure_kind == .WhenCondition {
        ret write_all(file, "a `when` condition is a question about the target -- `target.arch` or `target.os` compared with a member, under `!`, `&&`, `||` and parentheses -- or a bool the compile-time interpreter can evaluate")
    }
    if checker.failure_kind == .VariadicArgument {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` is a C variadic and `")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, "` cannot stand in its `...` position: only the C ABI table crosses, and there are no default promotions -- write `i32(x)` or `f64(x)`")
    }
    if checker.failure_kind == .MetaFieldOwner {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` is not a field of `")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, "`")
    }
    if checker.failure_kind == .MetaShape {
        try write_all(file, "`meta.")
        try write_all(file, checker.failure_detail2)
        try write_all(file, "` has nothing to enumerate for `")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "`")
    }
    if checker.failure_kind == .AtomicElement {
        try write_all(file, "`Atomic[")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "]` is not a type: an atomic holds an integer or a pointer")
    }
    if checker.failure_kind == .VectorShape {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "[T, N]` is not in section 4's table: T is an integer or float primitive other than usize and isize, and N times its size is 16, 32 or 64 bytes")
    }
    if checker.failure_kind == .AtomicOrdering {
        try write_all(file, "`atomic.")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` may not take the ordering `.")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, "`")
    }
    if checker.failure_kind == .NotAType {
        if checker.failure_detail.len != 0usize {
            try write_all(file, "`")
            try write_all(file, checker.failure_detail)
            ret write_all(file, "` has no usable type; `type` is one only as a compile-time parameter, not something a field or binding can hold (spec section 9)")
        }
        ret write_all(file, "this is not a type")
    }
    if checker.failure_kind == .AggregateFieldCount {
        try write_all(file, "this literal gives a different number of fields than `")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "` declares")
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
    // `Generic` means nothing along the way recorded a reason, so the error value is
    // the only evidence of which check rejected the program. Naming it turns "type
    // checking failed" from a dead end into somewhere to start.
    if checker.failure_kind == .Generic {
        let name = check.error_name(check_error)
        if name.len != 0usize {
            try write_all(file, "type checking failed: ")
            ret write_all(file, name)
        }
    }
    ret write_all(file, check.diagnostic_message(checker.failure_kind))
}

fn print_check_diagnostic(report: *Sink, g: *graph.Graph, checker: *check.Checker, check_error: err) -> err {
    var path = "<unknown>"
    if checker.failure_module < g.count { path = g.modules[checker.failure_module].path }
    var message_storage: [4096]u8 = zero
    var message = capture_sink(message_storage[..])
    try write_check_message(&message, checker, check_error)
    ret emit_diagnostic(report, path, checker.failure_token, checker.failure_has_token, check.diagnostic_code(checker.failure_kind), message_storage[..message.count])
}

fn print_token_diagnostic(report: *Sink, g: *graph.Graph, module_index: usize, token: lex.Token, code: str, message: str) -> err {
    var path = "<unknown>"
    if module_index < g.count { path = g.modules[module_index].path }
    ret emit_diagnostic(report, path, token, true, code, message)
}

// A syntax error names its position and, where the parser knows why, its reason.
// A keyword in a binding position is the one reason worth spelling out: it reads
// as an ordinary name and the generic "unexpected" wording explains nothing.
fn print_parse_failure(report: *Sink, path: str, text: str, token: lex.Token, reserved_name: bool) -> err {
    var message_storage: [1024]u8 = zero
    var message = capture_sink(message_storage[..])
    var code = "E-SYNTAX-9999"
    if reserved_name {
        code = "E-NAME-0003"
        try write_all(&message, "`")
        try write_all(&message, text[token.start..token.end])
        try write_all(&message, "` is a keyword and cannot name a local or parameter")
    } else {
        // A token the scanner refused is a lexical error under its own code (D215).
        if token.kind == .Invalid {
            code = lex.invalid_code(text, token)
            try write_all(&message, "invalid token")
        } else {
            try write_all(&message, "unexpected ")
            if token.kind == .Eof {
                try write_all(&message, "end of file")
            } else {
                if token.kind == .Newline {
                    try write_all(&message, "end of line")
                } else {
                    try write_all(&message, "`")
                    try write_all(&message, text[token.start..token.end])
                    try write_all(&message, "`")
                }
            }
        }
    }
    ret emit_diagnostic(report, path, token, true, code, message_storage[..message.count])
}

// Every module is parsed while the graph is loaded, so a syntax error anywhere in
// the program surfaces here with the module that holds it.
fn load_graph(a: *mem.Arena, report: *Sink, loaded: *graph.Graph, path: str, root: str, arch: str, target_os: str) -> err {
    let load_error = graph.load(a, loaded, path, root, arch, target_os)
    if load_error != ok && loaded.has_failure && loaded.failure_module < loaded.count {
        let module = loaded.modules[loaded.failure_module]
        try print_parse_failure(report, module.path, module.text, loaded.failure_token, loaded.failure_reserved_name)
        try finish_report(report)
        os.exit(1i32)
    }
    // A `use` naming no module, or closing a cycle, is reported at the module that
    // wrote it under docs/diagnostics.md's E-MODULE codes (D215).
    if load_error != ok && loaded.has_import_failure && loaded.failure_module < loaded.count {
        var message_storage: [1024]u8 = zero
        var message = capture_sink(message_storage[..])
        var code = "E-MODULE-0001"
        try write_all(&message, "`use ")
        try write_all(&message, loaded.failure_import)
        if load_error == graph.ImportCycle {
            code = "E-MODULE-0002"
            try write_all(&message, "` closes an import cycle")
        } else {
            if load_error == graph.DuplicateModule {
                try write_all(&message, "` is defined by both source roots")
            } else {
                if load_error == project.ModuleNotFound {
                    try write_all(&message, "` names no module under the source root or the toolchain")
                } else {
                    code = "E-MODULE-9999"
                    if load_error == project.AmbiguousVariant {
                        try write_all(&message, "` has more than one source variant for the target")
                    } else {
                        try write_all(&message, "` cannot be resolved")
                    }
                }
            }
        }
        var no_token: lex.Token = zero
        try emit_diagnostic(report, loaded.modules[loaded.failure_module].path, no_token, false, code, message_storage[..message.count])
        try finish_report(report)
        os.exit(1i32)
    }
    ret load_error
}

fn named_resolve_failure(resolve_error: err) -> bool {
    ret resolve_error == resolve.UnknownConvention || resolve_error == resolve.ModuleShadow || resolve_error == resolve.DuplicateLocal || resolve_error == resolve.ReservedLocal || resolve_error == resolve.ReservedName || resolve_error == resolve.DuplicateName || resolve_error == resolve.QualifierCollision
}

fn resolve_name_code(resolve_error: err) -> str {
    if resolve_error == resolve.DuplicateName { ret "E-NAME-0001" }
    if resolve_error == resolve.QualifierCollision { ret "E-NAME-0002" }
    ret "E-NAME-0003"
}

fn write_resolve_name_message(failure: *Sink, resolver: *resolve.Resolver, resolve_error: err) -> err {
    if resolve_error == resolve.UnknownConvention { ret write_all(failure, "is not a calling convention; spec section 5 names c, sysv, win64 and stdcall") }
    if resolve_error == resolve.ReservedLocal { ret write_all(failure, "is a reserved name and cannot name a local or parameter") }
    if resolve_error == resolve.ReservedName { ret write_all(failure, "is a reserved name and cannot name a declaration") }
    if resolve_error == resolve.QualifierCollision { ret write_all(failure, "collides with a use qualifier in this module") }
    if resolve_error == resolve.DuplicateName {
        try write_all(failure, "already names a module-scope ")
        try write_all(failure, resolver.failure_owner)
        ret write_all(failure, "; each name may be declared once per namespace")
    }
    if resolve_error == resolve.ModuleShadow {
        try write_all(failure, "already names a module-scope ")
        try write_all(failure, resolver.failure_owner)
        ret write_all(failure, "; a local or parameter may not reuse it")
    }
    ret write_all(failure, "is already bound in an active scope")
}

fn print_resolve_name_diagnostic(report: *Sink, g: *graph.Graph, resolver: *resolve.Resolver, resolve_error: err) -> err {
    var path = "<unknown>"
    if resolver.failure_module < g.count { path = g.modules[resolver.failure_module].path }
    var message_storage: [4096]u8 = zero
    var message = capture_sink(message_storage[..])
    try write_all(&message, "`")
    try write_all(&message, resolver.failure_name)
    try write_all(&message, "` ")
    try write_resolve_name_message(&message, resolver, resolve_error)
    ret emit_diagnostic(report, path, resolver.failure_token, true, resolve_name_code(resolve_error), message_storage[..message.count])
}

fn print_resolve_diagnostic(report: *Sink, g: *graph.Graph, resolver: *resolve.Resolver, resolve_error: err) -> err {
    if resolve_error == resolve.UnknownName && resolver.failure_has_token {
        if resolver.failure_has_context {
            try print_token_diagnostic(report, g, resolver.failure_module, resolver.failure_context_token, "E-TYPE-0002", "initializer type does not match binding")
        }
        ret print_token_diagnostic(report, g, resolver.failure_module, resolver.failure_token, "E-NAME-9999", "unknown value name")
    }
    // Declaration and scope collisions carry an exact token and the offending
    // name; docs/diagnostics.md reserves E-NAME-0001 through E-NAME-0003 for them.
    if resolver.failure_has_token && named_resolve_failure(resolve_error) {
        ret print_resolve_name_diagnostic(report, g, resolver, resolve_error)
    }
    var token: lex.Token = zero
    if resolver.failure_has_token { token = resolver.failure_token }
    ret print_token_diagnostic(report, g, resolver.failure_module, token, "E-NAME-9999", "name resolution failed")
}

fn print_lower_diagnostic(report: *Sink, g: *graph.Graph, checker: *check.Checker, lower_error: err) -> err {
    if checker.failure_module < g.count {
        try write_all(report, g.modules[checker.failure_module].path)
    } else {
        try write_all(report, "<unknown>")
    }
    try write_all(report, ":")
    if checker.failure_has_token {
        try write_usize(report, checker.failure_token.line)
        try write_all(report, ":")
        try write_usize(report, checker.failure_token.column)
    } else {
        try write_all(report, "1:1")
    }
    try write_all(report, ": error[E-TYPE-9999]: cannot lower `")
    try write_all(report, checker.failure_name)
    try write_all(report, "`: ")
    if lower_error == check.Unsupported {
        try write_all(report, "construct is not implemented in self-hosted lowering")
    } else {
        if lower_error == nir.Capacity {
            try write_all(report, "lowering failed: NIR capacity exhausted")
        } else {
            if lower_error == nir.InvalidControlFlow {
                try write_all(report, "lowering failed: invalid NIR control flow")
            } else {
                if lower_error == check.InvalidSwitch {
                    try write_all(report, "lowering failed: invalid switch")
                } else {
                    if lower_error == check.MissingReturn {
                        try write_all(report, "lowering failed: missing return")
                    } else {
                        if lower_error == check.InvalidType {
                            try write_all(report, "lowering failed: invalid type")
                        } else {
                            if lower_error == nir.InvalidValue {
                                try write_all(report, "lowering failed: invalid NIR value")
                            } else {
                                try write_all(report, "lowering failed")
                            }
                        }
                    }
                }
            }
        }
    }
    ret write_all(report, "\n")
}

fn print_codegen_diagnostic(report: *Sink, g: *graph.Graph, function: nir.Function, context: *codegen_x64.FunctionContext) -> err {
    if function.module_index < g.count { try write_all(report, g.modules[function.module_index].path) } else { try write_all(report, "<unknown>") }
    try write_all(report, ":")
    try write_usize(report, context.failure_token.line)
    try write_all(report, ":")
    try write_usize(report, context.failure_token.column)
    try write_all(report, ": error[E-CODEGEN-9999]: cannot select machine code for `")
    try write_all(report, function.name)
    ret write_all(report, "`\n")
}

fn write_qualified_error(file: *Sink, module_name: str, error_name: str) -> err {
    try write_all(file, module_name)
    try write_all(file, ".")
    ret write_all(file, error_name)
}

fn print_error_table_diagnostic(report: *Sink, conflict: *error_table.Conflict, validation_error: err) -> err {
    if validation_error == error_table.HashZero {
        try write_all(report, "error[E-ERROR-9999]: error `")
        try write_qualified_error(report, conflict.first_module, conflict.first_name)
        ret write_all(report, "` hashes to reserved value 0; rename it\n")
    }
    try write_all(report, "error[E-LINK-9999]: error hash collision: `")
    try write_qualified_error(report, conflict.first_module, conflict.first_name)
    try write_all(report, "` and `")
    try write_qualified_error(report, conflict.second_module, conflict.second_name)
    ret write_all(report, "` have the same 32-bit FNV-1a value\n")
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
    var report = stderr_sink()
    if args.len == 2usize && same(args[1usize], "self-test") {
        try self_test()
        try io.print("selfhost lexer ok\n")
        ret ok
    }
    if args.len == 3usize && same(args[1usize], "validate-em") {
        let (bytes, load_error) = load_artifact(a, args[2usize])
        if load_error != ok { ret load_error }
        try em.validate(bytes)
        let (code_count, code_count_error) = em.artifact_code_count(bytes)
        if code_count_error != ok { ret code_count_error }
        var function_at = 0usize
        while function_at < code_count {
            let (function, function_error) = em.artifact_code_function_at(bytes, function_at)
            if function_error != ok { ret function_error }
            var relocation_at = 0usize
            while relocation_at < function.relocation_count {
                let (relocation, relocation_error) = em.artifact_code_relocation_at(bytes, function, relocation_at)
                if relocation_error != ok { ret relocation_error }
                relocation_at += 1usize
            }
            function_at += 1usize
        }
        try io.print("compiled module valid\n")
        ret ok
    }
    if args.len == 4usize && same(args[1usize], "check-em-edge") {
        let (dependent, dependent_error) = load_artifact(a, args[2usize])
        if dependent_error != ok { ret dependent_error }
        let (target_artifact, target_error) = load_artifact(a, args[3usize])
        if target_error != ok { ret target_error }
        let (count, count_error) = em.artifact_dependency_count(dependent)
        if count_error != ok { ret count_error }
        // A dependent may hold several edges into one module, so every edge
        // that targets this artifact has to be current.
        var edge_count = 0usize
        var edge_at = 0usize
        while edge_at < count {
            let (targets_module, targets_error) = em.dependency_targets_module(dependent, edge_at, target_artifact)
            if targets_error != ok { ret targets_error }
            if targets_module {
                edge_count += 1usize
                let (matches, match_error) = em.dependency_matches(dependent, edge_at, target_artifact)
                if match_error != ok { ret match_error }
                if !matches {
                    try io.print("dependency stale\n")
                    os.exit(1i32)
                    ret ok
                }
            }
            edge_at += 1usize
        }
        if edge_count == 0usize { ret em.InvalidArtifact }
        try io.print("dependency current\n")
        ret ok
    }
    if args.len >= 4usize && same(args[1usize], "link-em") {
        let (artifacts, artifacts_error) = mem.alloc[em_link.Artifact](a, args.len - 3usize)
        if artifacts_error != ok { ret artifacts_error }
        var artifact_at = 0usize
        while artifact_at < artifacts.len {
            let (bytes, load_error) = load_artifact(a, args[artifact_at + 3usize])
            if load_error != ok { ret load_error }
            artifacts[artifact_at].bytes = bytes
            artifact_at += 1usize
        }
        let (errors_valid, errors_error) = merge_artifact_error_tables(a, artifacts)
        if errors_error != ok { ret errors_error }
        if !errors_valid {
            os.exit(1i32)
            ret ok
        }
        var program: em_link.Program = zero
        try em_link.assemble(a, artifacts, &program)
        let (target_index, target_error) = em.artifact_target_index(artifacts[0usize].bytes)
        if target_error != ok { ret target_error }
        let (is_windows, windows_error) = em.string_matches(artifacts[0usize].bytes, target_index, "x64-windows")
        if windows_error != ok { ret windows_error }
        let (is_linux, linux_error) = em.string_matches(artifacts[0usize].bytes, target_index, "x64-linux")
        if linux_error != ok { ret linux_error }
        if !is_windows && !is_linux { ret em_link.TargetMismatch }
        // The symbol and line table goes after the code before the image is sized (D206, D209).
        try codegen_x64.append_symbol_table(&program.builder, &program.machine, program.function_offsets, program.relocations, program.relocation_count, program.lines, program.line_count)
        let (executable_storage, executable_storage_error) = mem.alloc[usize](a, program.machine.count + 65536usize)
        if executable_storage_error != ok { ret executable_storage_error }
        var executable: emit_x64.Buffer = zero
        try emit_x64.init(&executable, executable_storage)
        if is_windows {
            try link_pe.write(&program.builder, &program.machine, program.function_offsets, program.relocations, program.relocation_count, &executable)
        } else {
            try link_elf.write(&program.builder, &program.machine, program.function_offsets, program.relocations, program.relocation_count, &executable)
        }
        let (packed, packed_error) = mem.alloc[u8](a, executable.count)
        if packed_error != ok { ret packed_error }
        try emit_x64.pack(&executable, packed)
        try save_bytes(a, args[2usize], packed)
        try io.print("artifact executable written\n")
        ret ok
    }
    if args.len >= 4usize && same(args[1usize], "check-em-errors") {
        let (artifacts, artifacts_error) = mem.alloc[em_link.Artifact](a, args.len - 2usize)
        if artifacts_error != ok { ret artifacts_error }
        var artifact_at = 0usize
        while artifact_at < artifacts.len {
            let (bytes, load_error) = load_artifact(a, args[artifact_at + 2usize])
            if load_error != ok { ret load_error }
            artifacts[artifact_at].bytes = bytes
            let (error_count, count_error) = em.artifact_error_count(bytes)
            if count_error != ok { ret count_error }
            artifact_at += 1usize
        }
        var left_artifact = 0usize
        while left_artifact < artifacts.len {
            let (left_count, left_count_error) = em.artifact_error_count(artifacts[left_artifact].bytes)
            if left_count_error != ok { ret left_count_error }
            var left_at = 0usize
            while left_at < left_count {
                let (left, left_error) = em.artifact_error_at(artifacts[left_artifact].bytes, left_at)
                if left_error != ok { ret left_error }
                var right_artifact = left_artifact
                while right_artifact < artifacts.len {
                    let (right_count, right_count_error) = em.artifact_error_count(artifacts[right_artifact].bytes)
                    if right_count_error != ok { ret right_count_error }
                    var right_at = 0usize
                    if right_artifact == left_artifact { right_at = left_at + 1usize }
                    while right_at < right_count {
                        let (right, right_error) = em.artifact_error_at(artifacts[right_artifact].bytes, right_at)
                        if right_error != ok { ret right_error }
                        if left.value == right.value {
                            let (same_module, module_error) = em.strings_equal(artifacts[left_artifact].bytes, left.module_index, artifacts[right_artifact].bytes, right.module_index)
                            if module_error != ok { ret module_error }
                            let (same_name, name_error) = em.strings_equal(artifacts[left_artifact].bytes, left.name_index, artifacts[right_artifact].bytes, right.name_index)
                            if name_error != ok { ret name_error }
                            if !same_module || !same_name {
                                try print_artifact_error_collision(a, artifacts[left_artifact].bytes, left, artifacts[right_artifact].bytes, right)
                                os.exit(1i32)
                                ret ok
                            }
                        }
                        right_at += 1usize
                    }
                    right_artifact += 1usize
                }
                left_at += 1usize
            }
            left_artifact += 1usize
        }
        try io.print("error tables merged\n")
        ret ok
    }
    if args.len == 3usize && same(args[1usize], "scan") {
        let scan_error = lex.validate(args[2usize])
        if scan_error != ok { ret scan_error }
        try io.print("scan ok\n")
        ret ok
    }
    if args.len == 3usize && same(args[1usize], "parse") {
        let parse_error = validate_cli_parse(a, &report, "<argument>", args[2usize])
        if parse_error != ok { ret parse_error }
        try io.print("parse ok\n")
        ret ok
    }
    if args.len == 3usize && same(args[1usize], "info") && same(args[2usize], "--json") { ret tool.info_json(a, host_target()) }
    if args.len >= 3usize && args.len <= 6usize && (same(args[1usize], "tokens") || same(args[1usize], "parse")) && !(args.len == 3usize && same(args[1usize], "parse")) { ret tool_command(a, args) }
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
        let parse_error = validate_cli_parse(a, &report, args[2usize], text)
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
        try load_graph(a, &report, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
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
        try load_graph(a, &report, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
        var resolver: resolve.Resolver = zero
        try init_cli_resolver(a, &resolver)
        try resolve.collect(&resolver, &loaded)
        try io.print("module resolve ok\n")
        ret ok
    }
    // `check-file PATH ROOT ARCH OS [--json]`: with `--json`, the stream of docs/tooling.md
    // -- header, a diagnostic record each, the result -- on stdout (D228).
    if (args.len == 6usize || (args.len == 7usize && same(args[6usize], "--json"))) && same(args[1usize], "check-file") {
        if args.len == 7usize {
            report.json = true
            report.file = os.stdout()
            try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"check\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":1}\n")
        }
        var loaded: graph.Graph = zero
        try init_cli_graph(a, &loaded)
        let load_error = load_graph(a, &report, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
        if load_error != ok {
            // Not a diagnostic of the source but of the command: the operand itself.
            if !report.json { ret load_error }
            try emit_command_diagnostic(&report, "E-CLI-9999", "the operand cannot be read as a module")
            try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"diagnostics\":1}}\n")
            os.exit(2i32)
            ret ok
        }
        var resolver: resolve.Resolver = zero
        try init_cli_resolver(a, &resolver)
        let resolve_error = resolve.collect(&resolver, &loaded)
        if resolve_error != ok {
            try print_resolve_diagnostic(&report, &loaded, &resolver, resolve_error)
            try finish_report(&report)
            os.exit(1i32)
            ret ok
        }
        var checker: check.Checker = zero
        try init_cli_checker(a, &checker)
        checker.arena = a
        let check_error = check.run(&checker, &resolver, &loaded)
        if check_error != ok {
            if checker.diagnostic_count == 0usize {
                try print_check_diagnostic(&report, &loaded, &checker, check_error)
            } else {
                var diagnostic_at = 0usize
                while diagnostic_at < checker.diagnostic_count {
                    select_check_diagnostic(&checker, checker.diagnostics[diagnostic_at])
                    try print_check_diagnostic(&report, &loaded, &checker, check_error)
                    diagnostic_at += 1usize
                }
            }
            try finish_report(&report)
            os.exit(1i32)
            ret ok
        }
        var error_conflict: error_table.Conflict = zero
        let error_declaration_error = error_table.validate_declarations(&resolver, &loaded, &error_conflict)
        if error_declaration_error != ok {
            try print_error_table_diagnostic(&report, &error_conflict, error_declaration_error)
            try finish_report(&report)
            os.exit(1i32)
            ret ok
        }
        if report.json {
            try finish_report(&report)
            ret ok
        }
        try io.print("module check ok\n")
        ret ok
    }
    let writes_object = args.len == 7usize && same(args[1usize], "emit-object")
    // `emit-executable ... --release`: section 11's release build, every debug-only
    // check left out and the release results in their place (D204), and the inliner
    // on (D211); `emit-em-all` takes it too, and `--incremental` with it in any order.
    let trailing_flags = args.len >= 8usize && args.len <= 11usize && flags_known(args)
    let release_build = trailing_flags && (same(args[1usize], "emit-executable") || same(args[1usize], "emit-em-all")) && has_flag(args, "--release")
    let writes_executable = (args.len == 7usize || (trailing_flags && !has_flag(args, "--incremental"))) && same(args[1usize], "emit-executable")
    let writes_em = args.len == 7usize && same(args[1usize], "emit-em")
    // `emit-em-all ... --incremental`: section 12's edge rule decides which of the
    // artifacts already in the directory are kept and which are replaced (D205).
    let incremental_build = trailing_flags && same(args[1usize], "emit-em-all") && has_flag(args, "--incremental")
    let writes_all_em = (args.len == 7usize || trailing_flags) && same(args[1usize], "emit-em-all")
    if (args.len == 6usize && (same(args[1usize], "nir-file") || same(args[1usize], "codegen-file") || same(args[1usize], "object-file"))) || writes_object || writes_executable || writes_em || writes_all_em {
        let emit_object = same(args[1usize], "object-file") || writes_object
        let emit_machine_code = same(args[1usize], "codegen-file") || emit_object || writes_executable || writes_em || writes_all_em
        var loaded: graph.Graph = zero
        try init_cli_graph(a, &loaded)
        try load_graph(a, &report, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
        var resolver: resolve.Resolver = zero
        try init_cli_resolver(a, &resolver)
        let resolve_error = resolve.collect(&resolver, &loaded)
        if resolve_error != ok {
            try print_resolve_diagnostic(&report, &loaded, &resolver, resolve_error)
            os.exit(1i32)
            ret ok
        }
        var checker: check.Checker = zero
        try init_cli_checker(a, &checker)
        checker.arena = a
        // The declarations first; then, incrementally, the edge rule decides the kept
        // modules from the Interfaces they give, and only the other bodies are checked
        // (D224). `keep` is what lowering skips below.
        let (keep, keep_error) = mem.alloc[bool](a, loaded.count)
        if keep_error != ok { ret keep_error }
        var keep_at = 0usize
        while keep_at < loaded.count {
            keep[keep_at] = false
            keep_at += 1usize
        }
        var check_error = check.run_declarations(&checker, &resolver, &loaded)
        if check_error == ok && writes_all_em && incremental_build {
            let (settle_strings, settle_strings_error) = mem.alloc[str](a, 32768usize)
            if settle_strings_error != ok { ret settle_strings_error }
            let (settle_slots, settle_slots_error) = mem.alloc[usize](a, 131072usize)
            if settle_slots_error != ok { ret settle_slots_error }
            var settle_table: em.StringTable = zero
            try em.init_strings(&settle_table, settle_strings, settle_slots)
            let (settle_scratch_storage, settle_scratch_error) = mem.alloc[usize](a, 4194304usize)
            if settle_scratch_error != ok { ret settle_scratch_error }
            var settle_scratch: binary.Buffer = zero
            try binary.init(&settle_scratch, settle_scratch_storage)
            let (settle_triple, settle_triple_error) = target_triple(a, args[4usize], args[5usize])
            if settle_triple_error != ok { ret settle_triple_error }
            var settle_mode: em.BuildMode = .Debug
            if release_build { settle_mode = .Release }
            try settle_early(a, &checker, &loaded, args[6usize], settle_triple, settle_mode, &settle_table, &settle_scratch, keep)
        }
        if check_error == ok { check_error = check.check_bodies(&checker, &resolver, &loaded, keep) }
        if check_error != ok {
            if checker.diagnostic_count == 0usize {
                try print_check_diagnostic(&report, &loaded, &checker, check_error)
            } else {
                var diagnostic_at = 0usize
                while diagnostic_at < checker.diagnostic_count {
                    select_check_diagnostic(&checker, checker.diagnostics[diagnostic_at])
                    try print_check_diagnostic(&report, &loaded, &checker, check_error)
                    diagnostic_at += 1usize
                }
            }
            os.exit(1i32)
            ret ok
        }
        var error_conflict: error_table.Conflict = zero
        var error_validation_error = error_table.validate_declarations(&resolver, &loaded, &error_conflict)
        if error_validation_error == ok && writes_executable {
            error_validation_error = error_table.validate_link(&resolver, &loaded, &error_conflict)
        }
        if error_validation_error != ok {
            try print_error_table_diagnostic(&report, &error_conflict, error_validation_error)
            os.exit(1i32)
            ret ok
        }
        // Every error in the program is known now and not before, so this is where
        // the merged table is built. `push_err` expands against it.
        let (error_values, error_values_error) = mem.alloc[usize](a, 4096usize)
        if error_values_error != ok { ret error_values_error }
        let (error_spellings, error_spellings_error) = mem.alloc[str](a, 4096usize)
        if error_spellings_error != ok { ret error_spellings_error }
        let (error_count, error_build_error) = error_table.build(a, &resolver, &loaded, error_values, error_spellings)
        if error_build_error != ok { ret error_build_error }
        checker.error_values = error_values
        checker.error_spellings = error_spellings
        checker.error_count = error_count
        checker.arena = a
        var builder: nir.Builder = zero
        var signatures: nir.Signatures = zero
        // One more parameter type than the declarations need: `neper_report_failure`,
        // which lowering synthesizes for `main`'s failure line (D199), has no declaration.
        try init_cli_nir(a, &builder, &signatures, checker.parameter_count + checker.return_type_count + 1usize, checker.function_count > 256usize)
        let (bindings, bindings_error) = mem.alloc[lower.Binding](a, 16384usize)
        if bindings_error != ok { ret bindings_error }
        let (lowered_modules, lowered_modules_error) = mem.alloc[bool](a, 128usize)
        if lowered_modules_error != ok { ret lowered_modules_error }
        let (kept_functions, kept_functions_error) = mem.alloc[bool](a, 65536usize)
        if kept_functions_error != ok { ret kept_functions_error }
        builder.nocheck = release_build
        builder.release = release_build
        builder.arena_bytes = arena_flag(args)
        // Section 12's inlining (D207): the small functions are lowered first into the
        // oracle, in module order on every path, and the program's own lowering copies
        // them in at their calls. A debug build does not inline (D211): every frame
        // in its backtrace is a real call, so the oracle is not even built.
        var oracle: nir.Builder = zero
        var oracle_signatures: nir.Signatures = zero
        let (inlined, inlined_error) = mem.alloc[nir.InlinedRef](a, 8192usize)
        if inlined_error != ok { ret inlined_error }
        builder.inlined = inlined
        builder.inlined_count = 0usize
        builder.has_oracle = false
        var first_oracle: nir.Builder = zero
        var first_signatures: nir.Signatures = zero
        if release_build {
            // Twice (D212): the first oracle's bodies hold no copies; the second is
            // lowered against it, so its bodies hold one level of copies, and a call
            // the program inlines from it is two levels deep. Each pass records, per
            // function, the callees it copied, for the body edges.
            try init_oracle_nir(a, &first_oracle, &first_signatures, checker.parameter_count + checker.return_type_count + 1usize)
            first_oracle.nocheck = true
            first_oracle.release = true
            let (first_entries, first_entries_error) = mem.alloc[nir.InlineEntry](a, 4096usize)
            if first_entries_error != ok { ret first_entries_error }
            let (first_inlined, first_inlined_error) = mem.alloc[nir.InlinedRef](a, 8192usize)
            if first_inlined_error != ok { ret first_inlined_error }
            first_oracle.inlined = first_inlined
            var first_entry_count = 0usize
            let first_error = lower.build_inline_oracle(&checker, &loaded, &first_oracle, &first_signatures, bindings, first_entries, &first_entry_count)
            if first_error != ok {
                try print_lower_diagnostic(&report, &loaded, &checker, first_error)
                os.exit(1i32)
                ret ok
            }
            try init_oracle_nir(a, &oracle, &oracle_signatures, checker.parameter_count + checker.return_type_count + 1usize)
            oracle.nocheck = true
            oracle.release = true
            oracle.oracle = &first_oracle
            oracle.oracle_signatures = &first_signatures
            oracle.has_oracle = true
            oracle.inline_entries = first_entries
            oracle.inline_entry_count = first_entry_count
            let (oracle_inlined, oracle_inlined_error) = mem.alloc[nir.InlinedRef](a, 8192usize)
            if oracle_inlined_error != ok { ret oracle_inlined_error }
            oracle.inlined = oracle_inlined
            let (inline_entries, inline_entries_error) = mem.alloc[nir.InlineEntry](a, 4096usize)
            if inline_entries_error != ok { ret inline_entries_error }
            var inline_entry_count = 0usize
            let oracle_error = lower.build_inline_oracle(&checker, &loaded, &oracle, &oracle_signatures, bindings, inline_entries, &inline_entry_count)
            if oracle_error != ok {
                try print_lower_diagnostic(&report, &loaded, &checker, oracle_error)
                os.exit(1i32)
                ret ok
            }
            builder.oracle = &oracle
            builder.oracle_signatures = &oracle_signatures
            builder.has_oracle = true
            builder.inline_entries = inline_entries
            builder.inline_entry_count = inline_entry_count
        }
        var artifact_mode: em.BuildMode = .Debug
        if release_build { artifact_mode = .Release }
        var lower_error = ok
        if writes_all_em {
            lower_error = lower.all_modules(&checker, &loaded, &builder, &signatures, bindings, lowered_modules, keep)
        } else {
            lower_error = lower.reachable_modules(&checker, &loaded, &builder, &signatures, bindings, lowered_modules)
        }
        if lower_error == ok {
            // Everything was lowered so that the order is the one the artifacts also use; what
            // nothing reaches is dropped now, which both link paths do identically.
            // An artifact holds the whole module (D214): the linker that consumes it
            // prunes, as the executable path does here.
            if !(writes_em || writes_all_em) {
                let prune_error = nir.prune_unreachable(&builder, kept_functions, false)
                if prune_error != ok {
                    try print_lower_diagnostic(&report, &loaded, &checker, prune_error)
                    os.exit(1i32)
                    ret ok
                }
            }
        }
        if lower_error != ok {
            try print_lower_diagnostic(&report, &loaded, &checker, lower_error)
            os.exit(1i32)
            ret ok
        }
        let (ranges, ranges_error) = mem.alloc[regalloc.LiveRange](a, 32768usize)
        if ranges_error != ok { ret ranges_error }
        let (allocations, allocations_error) = mem.alloc[regalloc.Allocation](a, 32768usize)
        if allocations_error != ok { ret allocations_error }
        var machine_capacity = 1usize
        if emit_machine_code {
            // One entry per emitted byte, so this allocation is eight times the
            // code it will hold and it dominates the arena. Selecting the compiler
            // itself needs between 16 and 32 bytes per NIR instruction, measured by
            // bisecting the multiplier until emission reports `emit_x64.Capacity`;
            // 96 kept three to six times that; 56 -- twice the 28 the checks of
            // D194-D202 brought it to -- is what leaves room for the inlining oracle
            // (D207) in the default arena, and the line rows (D209), at most one per
            // instruction and sixteen bytes each, are the eight on top. Overrunning it
            // is a clean `Capacity` error, never a wrong instruction.
            // ... plus the symbol table appended after the code (D206), a header and a
            // name per function.
            var names_total = 0usize
            var named_at = 0usize
            while named_at < builder.function_count {
                names_total += builder.functions[named_at].module_name.len + 1usize + builder.functions[named_at].name.len
                named_at += 1usize
            }
            machine_capacity = builder.instruction_count * 64usize + builder.function_count * 24usize + names_total + 65536usize
        }
        let (machine_storage, machine_storage_error) = mem.alloc[usize](a, machine_capacity)
        if machine_storage_error != ok { ret machine_storage_error }
        var machine: emit_x64.Buffer = zero
        try emit_x64.init(&machine, machine_storage)
        let (block_offsets, block_offsets_error) = mem.alloc[usize](a, 8192usize)
        if block_offsets_error != ok { ret block_offsets_error }
        let (fixups, fixups_error) = mem.alloc[codegen_x64.Fixup](a, 32768usize)
        if fixups_error != ok { ret fixups_error }
        // Two per trap site -- the call and the symbol table (D206) -- and one per call,
        // so the count follows the instructions rather than a constant.
        let (relocations, relocations_error) = mem.alloc[codegen_x64.Relocation](a, builder.instruction_count + 4096usize)
        if relocations_error != ok { ret relocations_error }
        // Indexed by NIR function index, like the signature table above: sized to the
        // function count and not to a constant of its own.
        let (function_offsets, function_offsets_error) = mem.alloc[usize](a, builder.function_count + 1usize)
        if function_offsets_error != ok { ret function_offsets_error }
        // Two functions that compile to the same bytes -- a duplicate generic instance, or two
        // distinct functions that happen to agree -- share one copy in the image, keyed by the
        // same content hash the `.em` carries and folded in the same order, so an executable
        // linked from artifacts and one compiled from source come out identical (D130, D157).
        // Only when producing an executable: an `.em` or `.o` keeps every function so the fold
        // can happen once, at the link that consumes it.
        let want_fold = writes_executable
        var fold_hashes = function_offsets
        var fold_offsets = function_offsets
        var fold_count = 0usize
        var fold_scratch: binary.Buffer = zero
        if want_fold {
            let (fh, fh_error) = mem.alloc[usize](a, builder.function_count + 1usize)
            if fh_error != ok { ret fh_error }
            fold_hashes = fh
            let (fo, fo_error) = mem.alloc[usize](a, builder.function_count + 1usize)
            if fo_error != ok { ret fo_error }
            fold_offsets = fo
            let (fs, fs_error) = mem.alloc[usize](a, 2097152usize)
            if fs_error != ok { ret fs_error }
            try binary.init(&fold_scratch, fs)
        }
        var relocation_count = 0usize
        var function_at = 0usize
        var machine_abi: codegen_x64.Abi = .SystemV
        if same(args[5usize], "windows") { machine_abi = .Windows }
        var codegen_context: codegen_x64.FunctionContext = zero
        codegen_context.allocations = allocations
        codegen_context.ranges = ranges
        codegen_context.abi = machine_abi
        codegen_context.block_offsets = block_offsets
        codegen_context.fixups = fixups
        codegen_context.relocations = relocations
        codegen_context.relocation_count = &relocation_count
        codegen_context.output = &machine
        // Section 13's line table (D209): a row per line change, so at most one per instruction.
        let (line_entries, line_entries_error) = mem.alloc[codegen_x64.LineEntry](a, builder.instruction_count + 16usize)
        if line_entries_error != ok { ret line_entries_error }
        var line_count = 0usize
        codegen_context.lines = line_entries
        codegen_context.line_count = &line_count
        while function_at < builder.function_count {
            let (stack_slots, allocation_error) = regalloc.allocate(&builder, function_at, 5usize, ranges, allocations)
            if allocation_error != ok { ret allocation_error }
            if emit_machine_code {
                let function_start = machine.count
                function_offsets[function_at] = function_start
                let relocation_start = relocation_count
                let line_start = line_count
                let codegen_error = codegen_x64.function(&builder, function_at, stack_slots, &codegen_context)
                if codegen_error != ok {
                    try print_codegen_diagnostic(&report, &loaded, builder.functions[function_at], &codegen_context)
                    ret codegen_error
                }
                if want_fold {
                    fold_scratch.count = 0usize
                    let hash_input_error = em.write_code_hash_input(&loaded, &builder, &machine, function_start, machine.count, relocations, relocation_count, &fold_scratch)
                    // A function too large for the scratch is simply not folded: the hash cannot be
                    // formed, so it is left unique, which is always safe.
                    if hash_input_error == ok {
                        let (content, content_error) = artifact_hash.xxhash64(fold_scratch.bytes[0usize..fold_scratch.count])
                        if content_error == ok {
                            var fold_at = 0usize
                            var duplicate = false
                            while fold_at < fold_count {
                                if fold_hashes[fold_at] == content {
                                    machine.count = function_start
                                    relocation_count = relocation_start
                                    line_count = line_start
                                    function_offsets[function_at] = fold_offsets[fold_at]
                                    duplicate = true
                                    break
                                }
                                fold_at += 1usize
                            }
                            if !duplicate {
                                fold_hashes[fold_count] = content
                                fold_offsets[fold_count] = function_start
                                fold_count += 1usize
                            }
                        }
                    }
                }
            }
            function_at += 1usize
        }
        if emit_machine_code {
            if writes_em || writes_all_em {
                // One entry per byte of the artifact, and `e.str` alone compiles to
                // more than 256 KiB, so the old quarter-megabyte stopped every
                // `emit-em-all` over a module that uses it.
                let (artifact_storage, artifact_storage_error) = mem.alloc[usize](a, 8388608usize)
                if artifact_storage_error != ok { ret artifact_storage_error }
                var artifact: binary.Buffer = zero
                try binary.init(&artifact, artifact_storage)
                let (scratch_storage, scratch_storage_error) = mem.alloc[usize](a, 4194304usize)
                if scratch_storage_error != ok { ret scratch_storage_error }
                var scratch: binary.Buffer = zero
                try binary.init(&scratch, scratch_storage)
                let (string_values, string_values_error) = mem.alloc[str](a, 32768usize)
                if string_values_error != ok { ret string_values_error }
                let (string_slots, string_slots_error) = mem.alloc[usize](a, 131072usize)
                if string_slots_error != ok { ret string_slots_error }
                var strings: em.StringTable = zero
                try em.init_strings(&strings, string_values, string_slots)
                let (sections, sections_error) = mem.alloc[em.Section](a, 8usize)
                if sections_error != ok { ret sections_error }
                let (triple, triple_error) = target_triple(a, args[4usize], args[5usize])
                if triple_error != ok { ret triple_error }
                let (packed, packed_error) = mem.alloc[u8](a, artifact_storage.len)
                if packed_error != ok { ret packed_error }
                if writes_em {
                    try em.write_module(&checker, &loaded, &builder, 0usize, triple, artifact_mode, &machine, function_offsets, relocations, relocation_count, line_entries, line_count, &strings, sections, &scratch, &artifact)
                    try binary.pack(&artifact, packed)
                    try save_bytes(a, args[6usize], packed[..artifact.count])
                    try io.print("compiled module written\n")
                    ret ok
                }
                // The edge rule was settled before lowering (D214): a kept module was not
                // lowered and its artifact on disk stands; the rest are written.
                var module_at = 0usize
                while module_at < loaded.count {
                    if !keep[module_at] {
                        artifact.count = 0usize
                        try em.write_module(&checker, &loaded, &builder, module_at, triple, artifact_mode, &machine, function_offsets, relocations, relocation_count, line_entries, line_count, &strings, sections, &scratch, &artifact)
                        try binary.pack(&artifact, packed)
                        let (artifact_path, artifact_path_error) = compiled_module_path(a, args[6usize], loaded.modules[module_at].name, triple)
                        if artifact_path_error != ok { ret artifact_path_error }
                        try save_bytes(a, artifact_path, packed[..artifact.count])
                    }
                    if incremental_build {
                        if keep[module_at] { try io.print("kept ") } else { try io.print("rebuilt ") }
                        try io.print(loaded.modules[module_at].name)
                        try io.print("\n")
                    }
                    module_at += 1usize
                }
                try io.print("compiled modules written\n")
                ret ok
            }
            try codegen_x64.resolve_calls(&builder, function_offsets, relocations, relocation_count, &machine)
            if writes_executable {
                let executable_capacity = machine.count + 1048576usize
                let (executable_storage, executable_storage_error) = mem.alloc[usize](a, executable_capacity)
                if executable_storage_error != ok { ret executable_storage_error }
                var executable: emit_x64.Buffer = zero
                try emit_x64.init(&executable, executable_storage)
                if machine_abi == .Windows {
                    try codegen_x64.append_symbol_table(&builder, &machine, function_offsets, relocations, relocation_count, line_entries, line_count)
                    try link_pe.write(&builder, &machine, function_offsets, relocations, relocation_count, &executable)
                } else {
                    try codegen_x64.append_symbol_table(&builder, &machine, function_offsets, relocations, relocation_count, line_entries, line_count)
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
                let object_capacity = machine.count + builder.function_count * 256usize + relocation_count * 32usize + 65536usize
                let (object_storage, object_storage_error) = mem.alloc[usize](a, object_capacity)
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
    try stderr_text("error[E-CLI-9999]: usage: neper-self self-test | validate-em ARTIFACT | check-em-edge DEPENDENT TARGET | check-em-errors ARTIFACT... | link-em OUTPUT ARTIFACT... | scan|parse SOURCE | scan-file|parse-file PATH | project-file PATH ROOT MODULE | select-file ROOT SOURCE_ROOT MODULE ARCH OS PATH | graph-file PATH TOOLCHAIN_ROOT ARCH OS MODULE... | resolve-file|check-file|nir-file|codegen-file|object-file PATH TOOLCHAIN_ROOT ARCH OS | emit-object|emit-executable|emit-em|emit-em-all PATH TOOLCHAIN_ROOT ARCH OS OUTPUT [--release] [--incremental] [--arena SIZE]\n")
    os.exit(1i32)
    ret ok
}
