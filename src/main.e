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
use lookup
use stats
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
    if current.kind != kind || current.start != start || current.end != end { ret lex.InvalidSource }
    // The line and column are derived from the offset (D315), here without a table.
    var no_lines: [1]usize = zero
    if lex.line_of(s.source, no_lines[0usize..0usize], current.start) != line || lex.column_of(s.source, no_lines[0usize..0usize], current.start) != column {
        ret lex.InvalidSource
    }
    ret ok
}

fn validate_test_parse(text: str) -> err {
    var nodes: [64]syntax.Node = zero
    var children: [512]u32 = zero
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, nodes[..], children[..])
    ret parse.parse(&tree, text)
}

fn self_test() -> err {
    var basic = lex.init("use e.io\r\nfn main() -> err { // note\n    ret ok\n}\n")
    let basic_use = lex.next(&basic)
    if basic_use.kind != .KwUse || basic_use.start != 0usize || basic_use.end != 3usize { ret lex.InvalidSource }
    let basic_e = lex.next(&basic)
    if basic_e.kind != .Identifier || basic_e.start != 4usize || basic_e.end != 5usize { ret lex.InvalidSource }
    var basic_pair: [2]lex.Token = zero
    basic_pair[0usize] = basic_use
    basic_pair[1usize] = basic_e
    if lex.leading_start(basic_pair[..], 0usize) != 0usize || lex.leading_start(basic_pair[..], 1usize) != 3usize { ret lex.InvalidSource }
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
    var no_lines: [1]usize = zero
    var positioned = lex.init("\xEF\xBB\xBF\"😀é\"\r\nx")
    let positioned_string = lex.next(&positioned)
    if positioned_string.kind != .String || positioned_string.start != 3usize || positioned_string.end != 11usize { ret lex.InvalidSource }
    // The end position and the UTF-16 columns are derived from the source (D315).
    let positioned_string_span = lex.span_of(positioned.source, no_lines[0usize..0usize], positioned_string)
    if positioned_string_span.line != 1usize || positioned_string_span.column != 1usize || positioned_string_span.end_line != 1usize || positioned_string_span.end_column != 5usize { ret lex.InvalidSource }
    if positioned_string_span.column_utf16 != 1usize || positioned_string_span.end_column_utf16 != 6usize { ret lex.InvalidSource }
    let positioned_newline = lex.next(&positioned)
    if positioned_newline.kind != .Newline || positioned_newline.start != 11usize || positioned_newline.end != 13usize { ret lex.InvalidSource }
    let positioned_newline_span = lex.span_of(positioned.source, no_lines[0usize..0usize], positioned_newline)
    if positioned_newline_span.line != 1usize || positioned_newline_span.column != 5usize || positioned_newline_span.end_line != 2usize || positioned_newline_span.end_column != 1usize { ret lex.InvalidSource }
    if positioned_newline_span.column_utf16 != 6usize || positioned_newline_span.end_column_utf16 != 1usize { ret lex.InvalidSource }
    let positioned_name = lex.next(&positioned)
    if positioned_name.kind != .Identifier || positioned_name.start != 13usize || positioned_name.end != 14usize { ret lex.InvalidSource }
    let positioned_name_span = lex.span_of(positioned.source, no_lines[0usize..0usize], positioned_name)
    if positioned_name_span.line != 2usize || positioned_name_span.column != 1usize || positioned_name_span.end_line != 2usize || positioned_name_span.end_column != 2usize { ret lex.InvalidSource }
    if positioned_name_span.column_utf16 != 1usize || positioned_name_span.end_column_utf16 != 2usize { ret lex.InvalidSource }
    var invalid_scalar = lex.init("😀x")
    let invalid_scalar_token = lex.next(&invalid_scalar)
    if invalid_scalar_token.kind != .Invalid || invalid_scalar_token.start != 0usize || invalid_scalar_token.end != 4usize { ret lex.InvalidSource }
    let invalid_scalar_span = lex.span_of(invalid_scalar.source, no_lines[0usize..0usize], invalid_scalar_token)
    if invalid_scalar_span.column != 1usize || invalid_scalar_span.end_column != 2usize || invalid_scalar_span.column_utf16 != 1usize || invalid_scalar_span.end_column_utf16 != 3usize { ret lex.InvalidSource }
    let after_invalid_scalar = lex.next(&invalid_scalar)
    if after_invalid_scalar.kind != .Identifier || after_invalid_scalar.start != 4usize || lex.column_of(invalid_scalar.source, no_lines[0usize..0usize], after_invalid_scalar.start) != 2usize || lex.span_of(invalid_scalar.source, no_lines[0usize..0usize], after_invalid_scalar).column_utf16 != 3usize { ret lex.InvalidSource }
    var invalid_sequence = lex.init("\xF0\x9F\x92x")
    let invalid_sequence_token = lex.next(&invalid_sequence)
    if invalid_sequence_token.kind != .Invalid || invalid_sequence_token.start != 0usize || invalid_sequence_token.end != 3usize { ret lex.InvalidSource }
    let invalid_sequence_span = lex.span_of(invalid_sequence.source, no_lines[0usize..0usize], invalid_sequence_token)
    if invalid_sequence_span.end_column != 2usize || invalid_sequence_span.end_column_utf16 != 2usize { ret lex.InvalidSource }
    let after_invalid_sequence = lex.next(&invalid_sequence)
    if after_invalid_sequence.kind != .Identifier || after_invalid_sequence.start != 3usize || lex.column_of(invalid_sequence.source, no_lines[0usize..0usize], after_invalid_sequence.start) != 2usize || lex.span_of(invalid_sequence.source, no_lines[0usize..0usize], after_invalid_sequence).column_utf16 != 2usize { ret lex.InvalidSource }
    var trivia = lex.init("\xEF\xBB\xBF // c\r\nx ")
    let trivia_newline = lex.next(&trivia)
    if trivia_newline.kind != .Newline || trivia_newline.start != 8usize || trivia_newline.end != 10usize { ret lex.InvalidSource }
    var leading = lex.trivia_init(trivia.source, no_lines[0usize..0usize], 0usize, trivia_newline)
    let leading_bom = lex.next_trivia(&leading)
    if leading_bom.kind != .Bom || leading_bom.start != 0usize || leading_bom.end != 3usize || leading_bom.column != 1usize || leading_bom.end_column != 1usize { ret lex.InvalidSource }
    let leading_space = lex.next_trivia(&leading)
    if leading_space.kind != .Space || leading_space.start != 3usize || leading_space.end != 4usize || leading_space.column != 1usize || leading_space.end_column != 2usize { ret lex.InvalidSource }
    let leading_comment = lex.next_trivia(&leading)
    if leading_comment.kind != .Comment || leading_comment.start != 4usize || leading_comment.end != 8usize || leading_comment.column != 2usize || leading_comment.end_column != 6usize { ret lex.InvalidSource }
    if lex.next_trivia(&leading).kind != .End { ret lex.InvalidSource }
    let trivia_name = lex.next(&trivia)
    if trivia_name.kind != .Identifier || trivia_name.start != 10usize || trivia_name.end != 11usize { ret lex.InvalidSource }
    let trivia_eof = lex.next(&trivia)
    if trivia_eof.kind != .Eof || trivia_eof.start != 12usize || trivia_eof.end != 12usize { ret lex.InvalidSource }
    var trailing = lex.trivia_init(trivia.source, no_lines[0usize..0usize], trivia_name.end, trivia_eof)
    let trailing_space = lex.next_trivia(&trailing)
    if trailing_space.kind != .Space || trailing_space.start != 11usize || trailing_space.end != 12usize || trailing_space.column != 2usize || trailing_space.end_column != 3usize { ret lex.InvalidSource }
    var unicode_trivia = lex.init("// 😀\nx")
    let unicode_newline = lex.next(&unicode_trivia)
    var unicode_leading = lex.trivia_init(unicode_trivia.source, no_lines[0usize..0usize], 0usize, unicode_newline)
    let unicode_comment = lex.next_trivia(&unicode_leading)
    if unicode_comment.kind != .Comment || unicode_comment.start != 0usize || unicode_comment.end != 7usize || unicode_comment.end_column != 5usize || unicode_comment.end_column_utf16 != 6usize { ret lex.InvalidSource }
    var broken_comment = lex.init("// a\xF0\x9F\x92 rest\nerror Good")
    let broken_comment_byte = lex.next(&broken_comment)
    if broken_comment_byte.kind != .Invalid || broken_comment_byte.start != 4usize || broken_comment_byte.end != 7usize { ret lex.InvalidSource }
    var broken_prefix = lex.trivia_init(broken_comment.source, no_lines[0usize..0usize], 0usize, broken_comment_byte)
    let broken_prefix_comment = lex.next_trivia(&broken_prefix)
    if broken_prefix_comment.kind != .Comment || broken_prefix_comment.start != 0usize || broken_prefix_comment.end != 4usize { ret lex.InvalidSource }
    let after_broken_comment = lex.next(&broken_comment)
    if after_broken_comment.kind != .Newline || after_broken_comment.start != 12usize { ret lex.InvalidSource }
    var broken_suffix = lex.trivia_init(broken_comment.source, no_lines[0usize..0usize], broken_comment_byte.end, after_broken_comment)
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
    var children: [512]u32 = zero
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, nodes[..], children[..])
    let parser_error = parse.parse(&tree, parser_source)
    if parser_error != ok { ret lex.InvalidSource }
    if tree.nodes[0usize].kind != .File || tree.count != 47usize { ret lex.InvalidSource }
    if usize(tree.nodes[0usize].child_count) != 21usize { ret lex.InvalidSource }
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
    if usize(tree.nodes[16usize].child_count) != 8usize || tree.nodes[17usize].kind != .ComptimeParam { ret lex.InvalidSource }
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
    if usize(tree.nodes[1usize].child_count) != 4usize { ret lex.InvalidSource }
    let file_children = usize(tree.nodes[0usize].first_child)
    if !parse.child_is_node_at(&tree, file_children) || parse.child_index_at(&tree, file_children) != 1usize { ret lex.InvalidSource }
    if parse.child_is_node_at(&tree, file_children + 1usize) || parse.child_index_at(&tree, file_children + 1usize) != 4usize { ret lex.InvalidSource }
    if !parse.child_is_node_at(&tree, file_children + 2usize) || parse.child_index_at(&tree, file_children + 2usize) != 2usize { ret lex.InvalidSource }
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
    if usize(tree.nodes[0usize].child_count) != 9usize { ret lex.InvalidSource }
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
    if usize(tree.nodes[0usize].child_count) != 7usize || usize(tree.nodes[6usize].child_count) != 11usize { ret lex.InvalidSource }
    let attribute_children = usize(tree.nodes[6usize].first_child)
    if !parse.child_is_node_at(&tree, attribute_children + 4usize) || parse.child_index_at(&tree, attribute_children + 4usize) != 3usize { ret lex.InvalidSource }
    if !parse.child_is_node_at(&tree, attribute_children + 7usize) || parse.child_index_at(&tree, attribute_children + 7usize) != 5usize { ret lex.InvalidSource }
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
    if tree.nodes[13usize].kind != .FnDecl || usize(tree.nodes[10usize].child_count) != 10usize { ret lex.InvalidSource }
    let named_children = usize(tree.nodes[10usize].first_child)
    if !parse.child_is_node_at(&tree, named_children) || parse.child_index_at(&tree, named_children) != 3usize { ret lex.InvalidSource }
    if !parse.child_is_node_at(&tree, named_children + 3usize) || parse.child_index_at(&tree, named_children + 3usize) != 5usize { ret lex.InvalidSource }
    if !parse.child_is_node_at(&tree, named_children + 6usize) || parse.child_index_at(&tree, named_children + 6usize) != 9usize { ret lex.InvalidSource }
    try parse.init_tree(&tree, nodes[..], children[..])
    let generic_aggregate_error = parse.parse(&tree, "fn boxed() -> Box[i32] {\n    ret Box[i32]{ value: item, }\n}\n")
    if generic_aggregate_error != ok || tree.count != 12usize { ret lex.InvalidSource }
    if tree.nodes[1usize].kind != .NameExpr || tree.nodes[2usize].kind != .NamedType { ret lex.InvalidSource }
    if tree.nodes[3usize].kind != .ReturnSpec || tree.nodes[4usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[5usize].kind != .NamedType || tree.nodes[6usize].kind != .NameExpr { ret lex.InvalidSource }
    if tree.nodes[7usize].kind != .LiteralItem || tree.nodes[8usize].kind != .AggregateLiteral { ret lex.InvalidSource }
    if tree.nodes[9usize].kind != .ReturnStmt || tree.nodes[10usize].kind != .Block { ret lex.InvalidSource }
    if tree.nodes[11usize].kind != .FnDecl || usize(tree.nodes[8usize].child_count) != 5usize { ret lex.InvalidSource }
    let generic_children = usize(tree.nodes[8usize].first_child)
    if !parse.child_is_node_at(&tree, generic_children) || parse.child_index_at(&tree, generic_children) != 5usize { ret lex.InvalidSource }
    if !parse.child_is_node_at(&tree, generic_children + 2usize) || parse.child_index_at(&tree, generic_children + 2usize) != 7usize { ret lex.InvalidSource }
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
    if tree.nodes[17usize].kind != .FnDecl || usize(tree.nodes[14usize].child_count) != 7usize { ret lex.InvalidSource }
    let array_children = usize(tree.nodes[14usize].first_child)
    if !parse.child_is_node_at(&tree, array_children) || parse.child_index_at(&tree, array_children) != 9usize { ret lex.InvalidSource }
    if !parse.child_is_node_at(&tree, array_children + 2usize) || parse.child_index_at(&tree, array_children + 2usize) != 11usize { ret lex.InvalidSource }
    if !parse.child_is_node_at(&tree, array_children + 4usize) || parse.child_index_at(&tree, array_children + 4usize) != 13usize { ret lex.InvalidSource }
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
    if usize(tree.nodes[14usize].child_count) != 8usize || usize(tree.nodes[7usize].child_count) != 8usize { ret lex.InvalidSource }
    let switch_children = usize(tree.nodes[14usize].first_child)
    if !parse.child_is_node_at(&tree, switch_children + 1usize) || parse.child_index_at(&tree, switch_children + 1usize) != 1usize { ret lex.InvalidSource }
    if !parse.child_is_node_at(&tree, switch_children + 4usize) || parse.child_index_at(&tree, switch_children + 4usize) != 7usize { ret lex.InvalidSource }
    if !parse.child_is_node_at(&tree, switch_children + 5usize) || parse.child_index_at(&tree, switch_children + 5usize) != 11usize { ret lex.InvalidSource }
    if !parse.child_is_node_at(&tree, switch_children + 6usize) || parse.child_index_at(&tree, switch_children + 6usize) != 13usize { ret lex.InvalidSource }
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
    var recovery_children: [16]u32 = zero
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
    var tiny_children: [1]u32 = zero
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
    try nir.verify_self_test()
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
        if same(args[at], "--") { ret false }
        if same(args[at], name) { ret true }
        if same(args[at], "--arena") || same(args[at], "--project") || same(args[at], "-j") || same(args[at], "--inline-cap") { at += 1usize }
        at += 1usize
    }
    ret false
}

// `--project DIR` (D263): the project root, in place of discovering it from the operand.
fn project_flag(args: []str) -> str {
    var at = 7usize
    while at + 1usize < args.len {
        if same(args[at], "--") { ret "" }
        if same(args[at], "--project") { ret args[at + 1usize] }
        if same(args[at], "--arena") || same(args[at], "-j") || same(args[at], "--inline-cap") { at += 1usize }
        at += 1usize
    }
    ret ""
}

fn flags_known(args: []str) -> bool {
    var at = 7usize
    while at < args.len {
        // `-- ARGS...` (D267): the program's own arguments, not the compiler's flags.
        if same(args[at], "--") { ret true }
        if same(args[at], "--arena") {
            if at + 1usize >= args.len { ret false }
            let (size, size_ok) = arena_size(args[at + 1usize])
            if !size_ok { ret false }
            at += 1usize
        } else {
            if same(args[at], "--project") {
                if at + 1usize >= args.len { ret false }
                at += 1usize
            } else {
                // `-j N` (D331): a worker count from one up; `--inline-cap N` (D346): a
                // cap from zero, for a measurement.
                if same(args[at], "-j") || same(args[at], "--inline-cap") {
                    if at + 1usize >= args.len || (same(args[at], "-j") && jobs_count(args[at + 1usize]) == 0usize) { ret false }
                    if same(args[at], "--inline-cap") && !decimal_ok(args[at + 1usize]) { ret false }
                    at += 1usize
                } else {
                    if !same(args[at], "--release") && !same(args[at], "--incremental") && !same(args[at], "--json") && !same(args[at], "--time") && !same(args[at], "--stats") && !same(args[at], "--stats-full") && !same(args[at], "--perturb") && !same(args[at], "--explain") { ret false }
                }
            }
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
        if same(args[at], "--") { ret 0usize }
        if same(args[at], "--arena") {
            let (size, size_ok) = arena_size(args[at + 1usize])
            if size_ok { ret size }
        }
        if same(args[at], "--project") || same(args[at], "-j") || same(args[at], "--inline-cap") { at += 1usize }
        at += 1usize
    }
    ret 0usize
}

// `--inline-cap N` (D346): the cap asked for plus one, or zero when the flag is absent.
fn inline_cap_flag(args: []str) -> usize {
    var at = 7usize
    while at + 1usize < args.len {
        if same(args[at], "--") { ret 0usize }
        if same(args[at], "--inline-cap") {
            var value = 0usize
            var digit = 0usize
            while digit < args[at + 1usize].len {
                value = value * 10usize + usize(args[at + 1usize][digit] - 48u8)
                digit += 1usize
            }
            ret value + 1usize
        }
        if same(args[at], "--arena") || same(args[at], "--project") || same(args[at], "-j") { at += 1usize }
        at += 1usize
    }
    ret 0usize
}

fn decimal_ok(spelling: str) -> bool {
    if spelling.len == 0usize || spelling.len > 6usize { ret false }
    var at = 0usize
    while at < spelling.len {
        if spelling[at] < 48u8 || spelling[at] > 57u8 { ret false }
        at += 1usize
    }
    ret true
}

// `-j N` (D331): the worker count asked for, none when the flag is absent.
fn jobs_flag(args: []str) -> usize {
    var at = 7usize
    while at + 1usize < args.len {
        if same(args[at], "--") { ret 0usize }
        if same(args[at], "-j") { ret jobs_count(args[at + 1usize]) }
        if same(args[at], "--arena") || same(args[at], "--project") || same(args[at], "--inline-cap") { at += 1usize }
        at += 1usize
    }
    ret 0usize
}

// A decimal count from one to a thousand, or zero for anything else.
fn jobs_count(spelling: str) -> usize {
    if spelling.len == 0usize || spelling.len > 4usize { ret 0usize }
    var value = 0usize
    var at = 0usize
    while at < spelling.len {
        let byte = spelling[at]
        if byte < 48u8 || byte > 57u8 { ret 0usize }
        value = value * 10usize + usize(byte - 48u8)
        at += 1usize
    }
    if value > 1000usize { ret 0usize }
    ret value
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
    try stderr_text("error[E-CLI-9999]: usage: neper-self tokens|parse [--json] [--path VIRTUAL.e] FILE|-, fmt-file FILE|- [--check] [--json] [--path VIRTUAL.e], or info --json; - needs --path\n")
    os.exit(1i32)
    ret ok
}

// The target this compiler runs on, for `info` (D229).
// ponytail: probed from the standard-handle value -- a Linux fd is 2, a Windows HANDLE
// never is -- until the runtime has a host intrinsic.
// The directory the compiler runs from: spec section 2 puts the toolchain's `lib/`
// beside the binary, so it is the toolchain root of every short-form command.
fn own_directory(path: str) -> str {
    var end = 0usize
    var at = 0usize
    while at < path.len {
        if path[at] == 47u8 || path[at] == 92u8 { end = at }
        at += 1usize
    }
    if end == 0usize { ret "." }
    ret path[0usize..end]
}

// Whether `args` is one of spec section 2's spellings, and its positional form if so:
//   build FILE [-o OUT] [--target ARCH-OS] [--release] [--json] [--project DIR]
//   run FILE [--target ARCH-OS] [--release] [-- ARGS...]            (always --json)
//   check FILE [--json] [--path REL] | fmt FILE [--check] [--json] | index FILE | dis FILE
//   build-manifest FILE | info
// The toolchain root is the binary's own directory, the target the host unless
// `--target` says, and `build`'s output the operand's stem beside it, `.exe` on Windows.
error NotShortForm

// `main` sits at the bootstrap's local cap, so the rewrite and the second dispatch
// live here: `NotShortForm` means the arguments were already positional.
// Section 1's header command for a spelling, short or positional; `info` for the rest.
fn stream_command_name(spelling: str) -> str {
    if same(spelling, "build") || same(spelling, "emit-executable") { ret "build" }
    if same(spelling, "run") { ret "run" }
    if same(spelling, "check") || same(spelling, "check-file") || same(spelling, "check-project") { ret "check" }
    if same(spelling, "test") || same(spelling, "test-file") || same(spelling, "test-project") { ret "test" }
    if same(spelling, "fmt") || same(spelling, "fmt-file") { ret "fmt" }
    if same(spelling, "tokens") { ret "tokens" }
    if same(spelling, "parse") { ret "parse" }
    if same(spelling, "index") || same(spelling, "index-file") { ret "index" }
    if same(spelling, "dis") || same(spelling, "dis-file") { ret "dis" }
    ret "info"
}

fn dispatch_short_form(a: *mem.Arena, args: []str) -> err {
    // `--language-version MAJOR.MINOR` (section 1, D283) selects an advertised version;
    // the one advertised is 0.1, so a match is taken off the arguments and anything else
    // is E-CLI-9999 before any source is read, as a record under `--json`.
    var at = 1usize
    while at + 1usize < args.len {
        if same(args[at], "--language-version") {
            if !same(args[at + 1usize], "0.1") {
                var report = stderr_sink()
                var json = false
                var scan = 1usize
                while scan < args.len {
                    if same(args[scan], "--json") { json = true }
                    scan += 1usize
                }
                if json {
                    report.json = true
                    report.file = os.stdout()
                    try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"")
                    try write_all(&report, stream_command_name(args[1usize]))
                    try write_all(&report, "\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
                }
                try emit_command_diagnostic(&report, "E-CLI-9999", "the language version is not advertised; `info --json` lists the profiles")
                if json { try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"diagnostics\":1}}\n") }
                os.exit(2i32)
                ret ok
            }
            let (stripped, stripped_error) = mem.alloc[str](a, args.len)
            if stripped_error != ok { ret stripped_error }
            var count = 0usize
            var copy = 0usize
            while copy < args.len {
                if copy != at && copy != at + 1usize {
                    stripped[count] = args[copy]
                    count += 1usize
                }
                copy += 1usize
            }
            ret dispatch(a, stripped[0usize..count])
        }
        at += 1usize
    }
    let (long_form, rewritten, rewrite_error) = short_form(a, args)
    if rewrite_error != ok { ret rewrite_error }
    if !rewritten { ret NotShortForm }
    ret dispatch(a, long_form)
}

fn short_form(a: *mem.Arena, args: []str) -> ([]str, bool, err) {
    if args.len < 2usize { ret (args, false, ok) }
    let command = args[1usize]
    let is_build = same(command, "build")
    // The positional `run FILE ROOT ARCH OS OUT ...` has an architecture fourth.
    let is_run = same(command, "run") && !(args.len >= 7usize && same(args[4usize], "x64"))
    let is_check = same(command, "check")
    let is_fmt = same(command, "fmt")
    let is_index = same(command, "index")
    let is_dis = same(command, "dis")
    let is_manifest = same(command, "build-manifest")
    // `test FILE [--json] [--project DIR]` (D292): always the stream, its WORKDIR
    // `.neper/debug/test/` under the project root, made when missing.
    let is_test = same(command, "test")
    if !(is_build || is_run || is_check || is_fmt || is_index || is_dis || is_manifest || is_test) { ret (args, false, ok) }
    // `check` and `test` with no operand (D294): the project the current directory is in,
    // as `check-project` and `test-project`; a `--` flag first is no operand either.
    let project_form = (is_check || is_test || is_fmt || is_index) && (args.len == 2usize || (args[2usize].len >= 2usize && args[2usize][0usize] == 45u8 && args[2usize][1usize] == 45u8))
    if args.len < 3usize && !project_form { ret (args, false, ok) }
    var file = ""
    if !project_form { file = args[2usize] }
    let root = own_directory(args[0usize])
    // Flags after the operand.
    var triple = host_target()
    var output = ""
    var has_output = false
    var release = false
    var json = false
    var check_only = false
    var project_dir = ""
    var virtual_path = ""
    var jobs = ""
    var perturb = false
    var program_args_at = args.len
    var at = 3usize
    if project_form { at = 2usize }
    while at < args.len {
        if same(args[at], "--") {
            program_args_at = at
            at = args.len
        } else {
            if same(args[at], "--triple") && at + 1usize < args.len {
                triple = args[at + 1usize]
                at += 1usize
            } else {
                if same(args[at], "-o") && at + 1usize < args.len {
                    output = args[at + 1usize]
                    has_output = true
                    at += 1usize
                } else {
                    if same(args[at], "--project") && at + 1usize < args.len {
                        project_dir = args[at + 1usize]
                        at += 1usize
                    } else {
                        if same(args[at], "--path") && at + 1usize < args.len {
                            virtual_path = args[at + 1usize]
                            at += 1usize
                        } else {
                            if same(args[at], "-j") && at + 1usize < args.len {
                                jobs = args[at + 1usize]
                                at += 1usize
                            }
                            if same(args[at], "--release") { release = true }
                            if same(args[at], "--json") { json = true }
                            if same(args[at], "--check") { check_only = true }
                            if same(args[at], "--perturb") { perturb = true }
                        }
                    }
                }
            }
            at += 1usize
        }
    }
    // `ARCH-OS` splits at its dash.
    var dash = 0usize
    while dash < triple.len && triple[dash] != 45u8 { dash += 1usize }
    if dash == triple.len { ret (args, false, ok) }
    let arch = triple[0usize..dash]
    let os_name = triple[dash + 1usize..triple.len]
    let (long_form, long_error) = mem.alloc[str](a, args.len + 12usize)
    if long_error != ok { ret (args, false, long_error) }
    var count = 0usize
    long_form[count] = args[0usize]
    count += 1usize
    if is_build || is_run {
        if !has_output {
            var suffix = ""
            if same(os_name, "windows") { suffix = ".exe" }
            let (named, named_error) = with_suffix(a, nptest_stem(file), suffix)
            if named_error != ok { ret (args, false, named_error) }
            output = named
        }
        if is_run { long_form[count] = "run" } else { long_form[count] = "emit-executable" }
        count += 1usize
        long_form[count] = file
        long_form[count + 1usize] = root
        long_form[count + 2usize] = arch
        long_form[count + 3usize] = os_name
        long_form[count + 4usize] = output
        count += 5usize
        if release {
            long_form[count] = "--release"
            count += 1usize
        }
        if json || is_run {
            long_form[count] = "--json"
            count += 1usize
        }
        if project_dir.len != 0usize {
            long_form[count] = "--project"
            long_form[count + 1usize] = project_dir
            count += 2usize
        }
        if jobs.len != 0usize {
            long_form[count] = "-j"
            long_form[count + 1usize] = jobs
            count += 2usize
        }
        if perturb {
            long_form[count] = "--perturb"
            count += 1usize
        }
        var program_at = program_args_at
        while program_at < args.len {
            long_form[count] = args[program_at]
            count += 1usize
            program_at += 1usize
        }
        ret (long_form[0usize..count], true, ok)
    }
    if project_form {
        var dir = project_dir
        if dir.len == 0usize {
            let (found, found_error) = project_from_cwd(a)
            if found_error != ok { ret (args, false, found_error) }
            dir = found
        }
        // `fmt` over the project (D295): in place, or `--check`; no stream yet.
        if is_fmt {
            if json { ret (args, false, ok) }
            long_form[count] = "fmt-project"
            long_form[count + 1usize] = dir
            long_form[count + 2usize] = "--write"
            if check_only { long_form[count + 2usize] = "--check" }
            count += 3usize
            ret (long_form[0usize..count], true, ok)
        }
        var leaf = "check"
        if is_test { leaf = "test" }
        if is_index { leaf = "index" }
        let (project_workdir, project_workdir_error) = workdir_under(a, dir, leaf)
        if project_workdir_error != ok { ret (args, false, project_workdir_error) }
        long_form[count] = "check-project"
        if is_test { long_form[count] = "test-project" }
        if is_index { long_form[count] = "index-project" }
        long_form[count + 1usize] = dir
        long_form[count + 2usize] = root
        long_form[count + 3usize] = arch
        long_form[count + 4usize] = os_name
        long_form[count + 5usize] = project_workdir
        long_form[count + 6usize] = "--json"
        count += 7usize
        ret (long_form[0usize..count], true, ok)
    }
    if is_fmt {
        long_form[count] = "fmt-file"
        long_form[count + 1usize] = file
        count += 2usize
        if check_only {
            long_form[count] = "--check"
            count += 1usize
        }
        if json || check_only {
            long_form[count] = "--json"
            count += 1usize
        }
        // Spec section 13: `fmt FILE` formats the file in place; `-` prints (D295).
        if !json && !check_only && !same(file, "-") {
            long_form[count] = "--write"
            count += 1usize
        }
        if virtual_path.len != 0usize {
            long_form[count] = "--path"
            long_form[count + 1usize] = virtual_path
            count += 2usize
        }
        ret (long_form[0usize..count], true, ok)
    }
    if is_test {
        let (workdir, workdir_error) = test_workdir(a, file, project_dir)
        if workdir_error != ok { ret (args, false, workdir_error) }
        long_form[count] = "test-file"
        long_form[count + 1usize] = file
        long_form[count + 2usize] = root
        long_form[count + 3usize] = arch
        long_form[count + 4usize] = os_name
        long_form[count + 5usize] = workdir
        long_form[count + 6usize] = "--json"
        count += 7usize
        ret (long_form[0usize..count], true, ok)
    }
    if is_check { long_form[count] = "check-file" }
    if is_index { long_form[count] = "index-file" }
    if is_dis { long_form[count] = "dis-file" }
    if is_manifest { long_form[count] = "build-manifest-file" }
    count += 1usize
    long_form[count] = file
    long_form[count + 1usize] = root
    long_form[count + 2usize] = arch
    long_form[count + 3usize] = os_name
    count += 4usize
    if json || is_index || is_dis || is_manifest {
        long_form[count] = "--json"
        count += 1usize
    }
    if is_check && virtual_path.len != 0usize {
        long_form[count] = "--path"
        long_form[count + 1usize] = virtual_path
        count += 2usize
    }
    ret (long_form[0usize..count], true, ok)
}

// The short `test`'s WORKDIR (D292): `.neper/debug/test` under `project_dir` when given,
// else under the project the operand is in, or its own directory; each level made once.
fn test_workdir(a: *mem.Arena, file: str, project_dir: str) -> (str, err) {
    var root = project_dir
    if root.len == 0usize {
        let (discovered, discovery_error) = project.discover(a, file)
        if discovery_error != ok { ret ("", discovery_error) }
        root = discovered.root
    }
    let (workdir, workdir_error) = workdir_under(a, root, "test")
    ret (workdir, workdir_error)
}

// The project the current directory is in (D294): `project.discover` from a name
// beside it, so the walk starts at the directory itself.
fn project_from_cwd(a: *mem.Arena) -> (str, err) {
    let (dir, dir_error) = os.current_dir(a)
    if dir_error != ok { ret ("", dir_error) }
    let (probe, probe_error) = tool.manifest_join(a, dir, "main.e")
    if probe_error != ok { ret ("", probe_error) }
    let (discovered, discovery_error) = project.discover(a, probe)
    if discovery_error != ok { ret ("", discovery_error) }
    ret (discovered.root, ok)
}

// `<root>/.neper/debug/<leaf>`, each level made once.
fn workdir_under(a: *mem.Arena, root: str, leaf: str) -> (str, err) {
    let (dot_dir, dot_error) = tool.manifest_join(a, root, ".neper")
    if dot_error != ok { ret ("", dot_error) }
    let dot_made = ensure_dir(a, dot_dir)
    if dot_made != ok { ret ("", dot_made) }
    let (mode_dir, mode_error) = tool.manifest_join(a, dot_dir, "debug")
    if mode_error != ok { ret ("", mode_error) }
    let mode_made = ensure_dir(a, mode_dir)
    if mode_made != ok { ret ("", mode_made) }
    let (workdir, workdir_error) = tool.manifest_join(a, mode_dir, leaf)
    if workdir_error != ok { ret ("", workdir_error) }
    let made = ensure_dir(a, workdir)
    if made != ok { ret ("", made) }
    ret (workdir, ok)
}

// A directory that is there afterwards: made, or already present.
fn ensure_dir(a: *mem.Arena, path: str) -> err {
    let made = os.mkdir(a, path)
    if made != ok && made != os.Exists { ret made }
    ret ok
}

fn host_target() -> str {
    if os.stderr().raw == 2usize { ret "x64-linux" }
    ret "x64-windows"
}

fn with_suffix(a: *mem.Arena, path: str, suffix: str) -> (str, err) {
    let (storage, storage_error) = mem.alloc[u8](a, path.len + suffix.len)
    if storage_error != ok { ret ("", storage_error) }
    var at = 0usize
    while at < path.len {
        storage[at] = path[at]
        at += 1usize
    }
    at = 0usize
    while at < suffix.len {
        storage[path.len + at] = suffix[at]
        at += 1usize
    }
    ret (storage[..], ok)
}

// `run` (D231): the executable just written, its stdout and stderr into files beside it,
// read back whole once it has exited.
fn has_dashdash(args: []str) -> bool {
    var at = 7usize
    while at < args.len {
        if same(args[at], "--") { ret true }
        at += 1usize
    }
    ret false
}

// The program's arguments: everything after a `--` (D267), none without one.
fn program_arguments(args: []str) -> []str {
    var at = 7usize
    while at < args.len {
        if same(args[at], "--") { ret args[at + 1usize..args.len] }
        at += 1usize
    }
    ret args[0usize..0usize]
}

// The child's peak working set comes from the same wait as its exit code (D311), and
// goes straight to the build record: `--stats` is its one reader, and `fn main` has no
// local to spare for it.
fn run_program(a: *mem.Arena, report: *Sink, path: str, arguments: []str) -> (i32, str, str, err) {
    let (stdout_path, stdout_path_error) = with_suffix(a, path, ".stdout")
    if stdout_path_error != ok { ret (0i32, "", "", stdout_path_error) }
    let (stderr_path, stderr_path_error) = with_suffix(a, path, ".stderr")
    if stderr_path_error != ok { ret (0i32, "", "", stderr_path_error) }
    // A bare name is the file beside the current directory, not a search of PATH.
    var launched = path
    var bare = true
    var scan = 0usize
    while scan < path.len {
        if path[scan] == 47u8 || path[scan] == 92u8 { bare = false }
        scan += 1usize
    }
    if bare {
        let (prefixed, prefix_error) = with_suffix(a, "./", path)
        if prefix_error != ok { ret (0i32, "", "", prefix_error) }
        launched = prefixed
    }
    let (argv, argv_error) = mem.alloc[str](a, arguments.len + 4usize)
    if argv_error != ok { ret (0i32, "", "", argv_error) }
    var argc = 1usize
    // CreateProcess reads a relative path with `/` as no path at all (D267): spell it
    // the host's way when launching on Windows.
    if !same(host_target(), "x64-linux") {
        let (spelled, spelled_error) = mem.alloc[u8](a, launched.len)
        if spelled_error != ok { ret (0i32, "", "", spelled_error) }
        var fix = 0usize
        while fix < launched.len {
            spelled[fix] = launched[fix]
            if spelled[fix] == 47u8 { spelled[fix] = 92u8 }
            fix += 1usize
        }
        launched = spelled[0usize..launched.len]
    }
    argv[0usize] = launched
    var argument = 0usize
    while argument < arguments.len {
        argv[argc] = arguments[argument]
        argc += 1usize
        argument += 1usize
    }
    // The files are opened last (D345): every exit before this one has nothing to close.
    let flags = os.OpenFlags { read: false, write: true, create: true, truncate: true, append: false }
    let (stdout_file, stdout_open_error) = os.open(a, stdout_path, flags)
    if stdout_open_error != ok { ret (0i32, "", "", stdout_open_error) }
    let (stderr_file, stderr_open_error) = os.open(a, stderr_path, flags)
    if stderr_open_error != ok {
        let stdout_abandoned = os.close(stdout_file)
        ret (0i32, "", "", stderr_open_error)
    }
    var streams: os.Stdio = zero
    streams.stdout = stdout_file
    streams.stderr = stderr_file
    let (child, spawn_error) = os.spawn(a, argv[..argc], streams)
    let stdout_stream = streams.stdout
    let stderr_stream = streams.stderr
    let stdout_close_error = os.close(stdout_stream)
    let stderr_close_error = os.close(stderr_stream)
    if spawn_error != ok { ret (0i32, "", "", spawn_error) }
    // The child is waited for whatever the closes said (D345): a spawned process is
    // owned until it is.
    let (usage, wait_error) = os.wait_usage(child)
    if stdout_close_error != ok { ret (0i32, "", "", stdout_close_error) }
    if stderr_close_error != ok { ret (0i32, "", "", stderr_close_error) }
    if wait_error != ok { ret (0i32, "", "", wait_error) }
    let (stdout_captured, stdout_load_error) = source.load(a, stdout_path)
    if stdout_load_error != ok { ret (0i32, "", "", stdout_load_error) }
    let (stderr_captured, stderr_load_error) = source.load(a, stderr_path)
    if stderr_load_error != ok { ret (0i32, "", "", stderr_load_error) }
    report.build.run_peak = usage.peak_memory
    ret (usage.exit_code, stdout_captured, stderr_captured, ok)
}

// `index-file PATH ROOT ARCH OS --json` (D232): the operand module's symbol records.
// Its own function because the bootstrap caps a function's locals (main is at the cap).
// Append a string to a byte buffer at `at`, returning the new length.
fn nptest_append(dst: []u8, at: usize, src: str) -> usize {
    var i = 0usize
    while i < src.len {
        dst[at + i] = src[i]
        i += 1usize
    }
    ret at + src.len
}

// Append the decimal spelling of a small value.
fn nptest_append_decimal(dst: []u8, at: usize, value: usize) -> usize {
    if value >= 10usize {
        let next = nptest_append_decimal(dst, at, value / 10usize)
        dst[next] = u8(48usize + value % 10usize)
        ret next + 1usize
    }
    dst[at] = u8(48usize + value)
    ret at + 1usize
}

// The @test functions of the operand, in source order: an `@test` attribute followed by an
// `fn` at the top level (D240). Names into `names`, one-based lines into `lines`.
// Spec section 13's one test signature: `fn NAME(NAME: *mem.Arena) -> err {`, the arena's
// module under any alias or none. Anything else on a `@test` function is E-TEST-9999.
fn nptest_signature_ok(tokens: []const lex.Token, text: str, first: usize, count: usize) -> bool {
    if first + 10usize >= count { ret false }
    if tokens[first + 2usize].kind != .PunctLParen { ret false }
    if tokens[first + 3usize].kind != .Identifier { ret false }
    if tokens[first + 4usize].kind != .PunctColon { ret false }
    if tokens[first + 5usize].kind != .PunctStar { ret false }
    var at = first + 6usize
    if tokens[at].kind != .Identifier { ret false }
    if tokens[at + 1usize].kind == .PunctDot {
        at += 2usize
        if at + 4usize >= count { ret false }
        if tokens[at].kind != .Identifier { ret false }
    }
    if !same(text[tokens[at].start..tokens[at].end], "Arena") { ret false }
    if tokens[at + 1usize].kind != .PunctRParen { ret false }
    if tokens[at + 2usize].kind != .PunctArrow { ret false }
    if tokens[at + 3usize].kind != .Identifier { ret false }
    if !same(text[tokens[at + 3usize].start..tokens[at + 3usize].end], "err") { ret false }
    ret tokens[at + 4usize].kind == .PunctLBrace
}

// `bad` names the first `@test` that is not a test -- not a function, or a function with
// another signature -- and `bad_kind` says which (1, 2); 0 when every one is a test (D256).
// `main_name` is the name token of a top-level `fn main` when the operand has one, so the
// runner can rename it out of the way of its own (D281).
fn discover_tests(a: *mem.Arena, text: str, names: []str, lines: []usize, bad: *lex.Token, bad_kind: *usize, main_name: *lex.Token, has_main: *bool) -> (usize, err) {
    var no_lines: [1]usize = zero
    let (tokens, token_count, invalid, scan_error) = tool.scan_all(a, text)
    if scan_error != ok { ret (0usize, scan_error) }
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, text.len + 1024usize)
    if nodes_error != ok { ret (0usize, nodes_error) }
    let (children, children_error) = mem.alloc[u32](a, text.len + 1024usize)
    if children_error != ok { ret (0usize, children_error) }
    var tree: parse.Tree = zero
    let init_error = parse.init_tree(&tree, nodes, children)
    if init_error != ok { ret (0usize, init_error) }
    let parse_error = parse.parse(&tree, text)
    if parse_error != ok { ret (0usize, parse_error) }
    var count = 0usize
    var pending = false
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level {
            if node.kind == .Attribute {
                let name_token = tokens[usize(node.token_start) + 1usize]
                pending = same(text[name_token.start..name_token.end], "test")
            } else {
                if node.kind == .FnDecl && usize(node.token_start) + 1usize < token_count && same(text[tokens[usize(node.token_start) + 1usize].start..tokens[usize(node.token_start) + 1usize].end], "main") {
                    *main_name = tokens[usize(node.token_start) + 1usize]
                    *has_main = true
                }
                if node.kind == .FnDecl && pending {
                    if count == names.len { ret (0usize, parse.InvalidSyntax) }
                    let fn_name = tokens[usize(node.token_start) + 1usize]
                    if *bad_kind == 0usize && !nptest_signature_ok(tokens[0usize..token_count], text, usize(node.token_start), token_count) {
                        *bad = fn_name
                        *bad_kind = 2usize
                    }
                    names[count] = text[fn_name.start..fn_name.end]
                    lines[count] = lex.line_of(text, no_lines[0usize..0usize], tokens[usize(node.token_start)].start)
                    count += 1usize
                    pending = false
                } else {
                    if pending && *bad_kind == 0usize {
                        *bad = tokens[usize(node.token_start)]
                        *bad_kind = 1usize
                    }
                    pending = false
                }
            }
        }
        node_index += 1usize
    }
    ret (count, ok)
}

// The runner source: the operand verbatim, a string-equality helper, and a `main` that
// dispatches to the @test named by its index in argv, returning that test's `err` -- so the
// runtime prints `error: ...` and exits 1 for a failure, and a trap aborts for a crash.
fn generate_runner(a: *mem.Arena, text: str, names: []const str, count: usize, timeout_ns: usize, main_name: lex.Token, has_main: bool) -> ([]u8, err) {
    var size = text.len + 4096usize
    var at = 0usize
    while at < count {
        size += names[at].len + 128usize
        at += 1usize
    }
    let (buffer, buffer_error) = mem.alloc[u8](a, size)
    if buffer_error != ok { ret (buffer, buffer_error) }
    // `use` leads the file, so the watchdog's imports go before the operand; unique aliases
    // never collide with what the operand already imports.
    var written = nptest_append(buffer, 0usize, "use e.os as nptest_os\nuse e.atomic as nptest_atomic\n")
    // The operand's own `main` is renamed so the runner's is the program root (D281);
    // the source map carries the seam as a second mapping.
    if has_main {
        written = nptest_append(buffer, written, text[0usize..main_name.start])
        written = nptest_append(buffer, written, "nptest_operand_main")
        written = nptest_append(buffer, written, text[main_name.end..text.len])
    } else {
        written = nptest_append(buffer, written, text)
    }
    // A watchdog thread waits on a futex that main sets when the test returns; if the wait
    // times out first the test is still running, so the process exits 124 (D246).
    written = nptest_append(buffer, written, "\ntype NptestGuard = struct { done: Atomic[u32] }\nfn nptest_watchdog(guard: *NptestGuard) {\n    while nptest_atomic.load(&guard.done, .Acquire) == 0u32 {\n        let nptest_wait = nptest_os.wait_u32(&guard.done, 0u32, ")
    written = nptest_append_decimal(buffer, written, timeout_ns)
    written = nptest_append(buffer, written, "i64)\n        if nptest_wait == nptest_os.Timeout { nptest_os.exit(124i32) }\n    }\n}\n")
    written = nptest_append(buffer, written, "\nfn nptest_eq(x: str, y: str) -> bool {\n    if x.len != y.len { ret false }\n    var i = 0usize\n    while i < x.len {\n        if x[i] != y[i] { ret false }\n        i += 1usize\n    }\n    ret true\n}\nfn nptest_dispatch(a: *mem.Arena, which: str) -> err {\n")
    at = 0usize
    while at < count {
        written = nptest_append(buffer, written, "    if nptest_eq(which, \"")
        written = nptest_append_decimal(buffer, written, at)
        written = nptest_append(buffer, written, "\") { ret ")
        written = nptest_append(buffer, written, names[at])
        written = nptest_append(buffer, written, "(a) }\n")
        at += 1usize
    }
    // The dispatch chain lives in its own function and main has a single `ret`: an early
    // return plus the chain plus the watchdog put main past what lowering would take (D246).
    written = nptest_append(buffer, written, "    ret ok\n}\nfn main(a: *mem.Arena, args: []str) -> err {\n    var nptest_result = ok\n    if args.len >= 2usize {\n        var nptest_guard: NptestGuard = zero\n        let (nptest_watch, nptest_watch_error) = nptest_os.thread_create[NptestGuard](nptest_watchdog, &nptest_guard, 1048576usize)\n        nptest_result = nptest_dispatch(a, args[1usize])\n        nptest_atomic.store(&nptest_guard.done, 1u32, .Release)\n        nptest_os.wake_one_u32(&nptest_guard.done)\n        if nptest_watch_error == ok {\n            let nptest_joined = nptest_os.thread_join(nptest_watch)\n        }\n    }\n    ret nptest_result\n}\n")
    ret (buffer[0usize..written], ok)
}

// Spawn a command, its stdout and stderr captured to files beside `base`, and read them back.
fn nptest_spawn(a: *mem.Arena, argv: []str, base: str) -> (i32, str, str, err) {
    let (out_path, out_path_error) = with_suffix(a, base, ".out")
    if out_path_error != ok { ret (0i32, "", "", out_path_error) }
    let (err_path, err_path_error) = with_suffix(a, base, ".err")
    if err_path_error != ok { ret (0i32, "", "", err_path_error) }
    let flags = os.OpenFlags { read: false, write: true, create: true, truncate: true, append: false }
    let (out_file, out_open_error) = os.open(a, out_path, flags)
    if out_open_error != ok { ret (0i32, "", "", out_open_error) }
    let (err_file, err_open_error) = os.open(a, err_path, flags)
    if err_open_error != ok {
        let out_abandoned = os.close(out_file)
        ret (0i32, "", "", err_open_error)
    }
    var streams: os.Stdio = zero
    streams.stdout = out_file
    streams.stderr = err_file
    let (child, spawn_error) = os.spawn(a, argv, streams)
    let out_stream = streams.stdout
    let err_stream = streams.stderr
    let out_close = os.close(out_stream)
    let err_close = os.close(err_stream)
    if spawn_error != ok { ret (0i32, "", "", spawn_error) }
    let (status, wait_error) = os.wait(child)
    if out_close != ok { ret (0i32, "", "", out_close) }
    if err_close != ok { ret (0i32, "", "", err_close) }
    if wait_error != ok { ret (0i32, "", "", wait_error) }
    let (out_text, out_load) = source.load(a, out_path)
    if out_load != ok { ret (0i32, "", "", out_load) }
    let (err_text, err_load) = source.load(a, err_path)
    if err_load != ok { ret (0i32, "", "", err_load) }
    ret (status, out_text, err_text, ok)
}

// Run one test by index; the runner was written executable by its build (D291).
fn nptest_run(a: *mem.Arena, exe: str, index: str, base: str) -> (i32, str, str, err) {
    var argv: [2]str = zero
    argv[0usize] = exe
    argv[1usize] = index
    let (status, out_text, err_text, spawn_error) = nptest_spawn(a, argv[..], base)
    ret (status, out_text, err_text, spawn_error)
}

fn nptest_parse_usize(text: str) -> usize {
    var value = 0usize
    var at = 0usize
    while at < text.len {
        let digit = text[at]
        if digit < 48u8 || digit > 57u8 { ret value }
        value = value * 10usize + usize(digit - 48u8)
        at += 1usize
    }
    ret value
}

fn nptest_now() -> usize {
    let (ticks, clock_error) = os.clock(.Monotonic)
    if clock_error != ok { ret 0usize }
    if ticks < 0i64 { ret 0usize }
    ret usize(ticks)
}

// `--time` (D303): one line per phase on stderr, milliseconds since the previous one.
// The state rides on the report sink like `--json` does: `main` is at the bootstrap's
// local limit and takes no new locals.
// `--time` also prints what the program filled (D306): the source, and every pool's
// high-water mark, which is what the pools are sized from.
fn report_count(name: str, value: usize) -> err {
    var line_storage: [96]u8 = zero
    var line = capture_sink(line_storage[..])
    try write_all(&line, "count ")
    try write_all(&line, name)
    try write_all(&line, ": ")
    try write_usize(&line, value)
    try write_all(&line, "\n")
    ret stderr_text(line_storage[..line.count])
}

fn report_counts(loaded: *graph.Graph, resolver: *resolve.Resolver, checker: *check.Checker, builder: *nir.Builder) -> err {
    var bytes = 0usize
    var largest = 0usize
    var at = 0usize
    while at < loaded.count {
        bytes += loaded.modules[at].text.len
        if loaded.modules[at].text.len > largest { largest = loaded.modules[at].text.len }
        at += 1usize
    }
    try report_count("modules", loaded.count)
    try report_count("imports", loaded.import_count)
    try report_count("source bytes", bytes)
    try report_count("largest module bytes", largest)
    try report_count("symbols", resolver.count)
    try report_count("checker tokens (last module)", checker.token_count)
    try report_count("locals (last function)", checker.local_count)
    try report_count("types", checker.type_count)
    try report_count("functions", checker.function_count)
    try report_count("parameters", checker.parameter_count)
    try report_count("return types", checker.return_type_count)
    try report_count("aggregates", checker.aggregate_count)
    try report_count("aggregate fields", checker.aggregate_field_count)
    try report_count("aliases", checker.alias_count)
    try report_count("constants", checker.constant_count)
    try report_count("constant exprs", checker.constant_expr_count)
    try report_count("globals", checker.global_count)
    try report_count("generic arguments", checker.generic_argument_count)
    try report_count("nir functions", builder.function_count)
    try report_count("nir blocks", builder.block_count + builder.block_total)
    try report_count("nir instructions", builder.instruction_count + builder.instruction_total)
    try report_count("nir operands", builder.operand_count + builder.operand_total)
    try report_count("nir function refs", builder.function_ref_count)
    try report_count("nir strings", builder.string_count)
    ret ok
}

// A pool sized from the program (D306): `base` for a small program plus one entry per
// `per` bytes of source. Every pool after loading is sized this way, so what a program
// commits is proportional to the program on both hosts -- on Windows the arena commits
// what is allocated, not what is touched, so a pool sized for millions of lines would
// have cost every build those pages.
fn sized(base: usize, bytes: usize, per: usize) -> usize {
    ret base + bytes / per
}

fn report_ms(ns: usize) -> err {
    var line_storage: [64]u8 = zero
    var line = capture_sink(line_storage[..])
    try write_usize(&line, ns / 1000000usize)
    try write_all(&line, " ms\n")
    ret stderr_text(line_storage[..line.count])
}

fn report_phase(report: *Sink, name: str) -> err {
    if !report.timing && !report.build.on { ret ok }
    let now = nptest_now()
    let started = report.phase_started
    stats.record_phase(&report.build, name, (now - started) / 1000000usize)
    if !report.timing {
        report.phase_started = now
        ret ok
    }
    var line_storage: [128]u8 = zero
    var line = capture_sink(line_storage[..])
    try write_all(&line, "time ")
    try write_all(&line, name)
    try write_all(&line, ": ")
    try write_usize(&line, (now - started) / 1000000usize)
    try write_all(&line, " ms, arena ")
    try write_usize(&line, report.arena_used / 1048576usize)
    try write_all(&line, " MB\n")
    report.phase_started = now
    ret stderr_text(line_storage[..line.count])
}

// Section 2's module name of a path under a source root: the separators become dots and
// the `.e` comes off -- `nested/deep.e` is `nested.deep`.
fn nptest_module_name(a: *mem.Arena, rel: str) -> (str, err) {
    let stem_end = nptest_stem_end(rel)
    let (buffer, buffer_error) = mem.alloc[u8](a, stem_end)
    if buffer_error != ok { ret ("", buffer_error) }
    var at = 0usize
    while at < stem_end {
        buffer[at] = rel[at]
        if buffer[at] == 47u8 || buffer[at] == 92u8 { buffer[at] = 46u8 }
        at += 1usize
    }
    ret (buffer[0usize..stem_end], ok)
}

fn nptest_stem_end(path: str) -> usize {
    if path.len >= 2usize && path[path.len - 2usize] == 46u8 && path[path.len - 1usize] == 101u8 { ret path.len - 2usize }
    ret path.len
}

// The decimal after `key` in a JSON line, or 0 when the key is absent.
fn json_usize_after(line: str, key: str) -> usize {
    var at = 0usize
    while at + key.len <= line.len {
        if same(line[at..at + key.len], key) { ret nptest_parse_usize(line[at + key.len..line.len]) }
        at += 1usize
    }
    ret 0usize
}

// `test-project` (D263): `test-file --json --path REL` on every module under DIR/src in
// byte order, each in its own process, the children's streams merged -- the header once,
// every `test` record and every diagnostic, one `test_summary` adding the children's up,
// one result. A module with no tests contributes nothing but its count.
fn test_project_command(a: *mem.Arena, args: []str) -> err {
    var report = stderr_sink()
    report.json = true
    report.file = os.stdout()
    try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"test\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
    let (paths, paths_error) = mem.alloc[str](a, 1024usize)
    if paths_error != ok { ret paths_error }
    let (rels, rels_error) = mem.alloc[str](a, 1024usize)
    if rels_error != ok { ret rels_error }
    let (source_dir, source_dir_error) = nptest_join(a, args[2usize], "src")
    if source_dir_error != ok { ret source_dir_error }
    var count = 0usize
    let walk_error = walk_sources(a, source_dir, "", paths, rels, &count)
    if walk_error != ok {
        try emit_command_diagnostic(&report, "E-CLI-9999", "the project has no readable src directory")
        try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"tests\":0,\"modules\":0}}\n")
        os.exit(2i32)
        ret ok
    }
    let (child_base, child_base_error) = nptest_join(a, args[6usize], "nptest-project-child")
    if child_base_error != ok { ret child_base_error }
    var passed = 0usize
    var failed = 0usize
    var crashed = 0usize
    var timed_out = 0usize
    var total = 0usize
    var duration = 0usize
    var refused = false
    var at = 0usize
    while at < count {
        var argv: [11]str = zero
        argv[0usize] = args[0usize]
        argv[1usize] = "test-file"
        argv[2usize] = paths[at]
        argv[3usize] = args[3usize]
        argv[4usize] = args[4usize]
        argv[5usize] = args[5usize]
        argv[6usize] = args[6usize]
        var argc = 7usize
        if args.len == 9usize {
            argv[argc] = args[7usize]
            argc += 1usize
        }
        argv[argc] = "--json"
        argv[argc + 1usize] = "--path"
        argv[argc + 2usize] = rels[at]
        argc += 3usize
        let (status, child_out, child_err, spawn_error) = nptest_spawn(a, argv[0usize..argc], child_base)
        if spawn_error != ok { ret spawn_error }
        if status == 2i32 { refused = true }
        // Forward the child's test records and diagnostics; add its summary up.
        var line_at = 0usize
        while line_at < child_out.len {
            var end = line_at
            while end < child_out.len && child_out[end] != 10u8 { end += 1usize }
            let line = child_out[line_at..end]
            if line.len > 24usize && same(line[0usize..24usize], "{\"record\":\"test_summary\"") {
                passed += json_usize_after(line, "\"passed\":")
                failed += json_usize_after(line, "\"failed\":")
                crashed += json_usize_after(line, "\"crashed\":")
                timed_out += json_usize_after(line, "\"timeout\":")
                total += json_usize_after(line, "\"total\":")
                duration += json_usize_after(line, "\"duration_ms\":")
            } else {
                if (line.len > 16usize && same(line[0usize..16usize], "{\"record\":\"test\"")) || (line.len > 22usize && same(line[0usize..22usize], "{\"record\":\"diagnostic\"")) {
                    try write_all(&report, line)
                    try write_all(&report, "\n")
                }
            }
            line_at = end + 1usize
        }
        at += 1usize
    }
    try write_all(&report, "{\"record\":\"test_summary\",\"passed\":")
    try write_usize(&report, passed)
    try write_all(&report, ",\"failed\":")
    try write_usize(&report, failed)
    try write_all(&report, ",\"crashed\":")
    try write_usize(&report, crashed)
    try write_all(&report, ",\"timeout\":")
    try write_usize(&report, timed_out)
    try write_all(&report, ",\"total\":")
    try write_usize(&report, total)
    try write_all(&report, ",\"duration_ms\":")
    try write_usize(&report, duration)
    try write_all(&report, "}\n")
    var exit_code = 0usize
    if passed != total { exit_code = 1usize }
    if refused { exit_code = 2usize }
    if exit_code == 0usize {
        try write_all(&report, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"tests\":")
    } else {
        try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":")
        try write_usize(&report, exit_code)
        try write_all(&report, ",\"data\":{\"tests\":")
    }
    try write_usize(&report, total)
    try write_all(&report, ",\"modules\":")
    try write_usize(&report, count)
    try write_all(&report, "}}\n")
    if exit_code != 0usize { os.exit(i32(exit_code)) }
    ret ok
}

// `<runner>.map.json`: section 8's document with one mapping, the operand's whole text
// at its place in the runner. The prefix is the two `use` lines D246 puts first.
// One mapping: the operand's bytes [from, to) at `generated_start` in the runner, with
// the original's line/column at both ends and the generated start line/column.
fn runner_mapping(out: *Sink, identity: str, generated_start: usize, from: usize, to: usize, line: usize, column: usize, end_line: usize, end_column: usize, generated_line: usize, generated_column: usize) -> err {
    try write_all(out, "{\"generated_span\":{\"source\":{\"root\":\"operand\",\"path\":\"nptest-runner.e\"},\"byte_start\":")
    try write_usize(out, generated_start)
    try write_all(out, ",\"byte_end\":")
    try write_usize(out, generated_start + (to - from))
    try write_all(out, ",\"line\":")
    try write_usize(out, generated_line)
    try write_all(out, ",\"column\":")
    try write_usize(out, generated_column)
    try write_all(out, ",\"end_line\":")
    try write_usize(out, end_line + 2usize)
    try write_all(out, ",\"end_column\":")
    try write_usize(out, end_column)
    try write_all(out, ",\"column_utf16\":")
    try write_usize(out, generated_column)
    try write_all(out, ",\"end_column_utf16\":")
    try write_usize(out, end_column)
    try write_all(out, "},\"original_span\":{\"source\":{\"root\":\"operand\",\"path\":")
    try write_json_string(out, identity)
    try write_all(out, "},\"byte_start\":")
    try write_usize(out, from)
    try write_all(out, ",\"byte_end\":")
    try write_usize(out, to)
    try write_all(out, ",\"line\":")
    try write_usize(out, line)
    try write_all(out, ",\"column\":")
    try write_usize(out, column)
    try write_all(out, ",\"end_line\":")
    try write_usize(out, end_line)
    try write_all(out, ",\"end_column\":")
    try write_usize(out, end_column)
    try write_all(out, ",\"column_utf16\":")
    try write_usize(out, column)
    try write_all(out, ",\"end_column_utf16\":")
    try write_usize(out, end_column)
    ret write_all(out, "},\"name\":null}")
}

fn write_runner_map(a: *mem.Arena, runner_path: str, runner: []u8, text: str, identity: str, main_name: lex.Token, has_main: bool) -> err {
    var no_lines: [1]usize = zero
    // The two `use` lines the runner begins with.
    let prefix_lines = "use e.os as nptest_os\nuse e.atomic as nptest_atomic\n"
    let prefix = prefix_lines.len
    let (digest, digest_error) = tool.manifest_sha256(a, runner[0usize..runner.len])
    if digest_error != ok { ret digest_error }
    var lines = 1usize
    var last_line_start = 0usize
    var at = 0usize
    while at < text.len {
        if text[at] == 10u8 {
            lines += 1usize
            last_line_start = at + 1usize
        }
        at += 1usize
    }
    let end_column = text.len - last_line_start + 1usize
    let (storage, storage_error) = mem.alloc[u8](a, 2048usize + identity.len)
    if storage_error != ok { ret storage_error }
    var out = capture_sink(storage)
    try write_all(&out, "{\"schema\":\"neper-source-map\",\"version\":1,\"generated\":{\"root\":\"operand\",\"path\":\"nptest-runner.e\"},\"generated_sha256\":\"")
    try write_all(&out, digest)
    try write_all(&out, "\",\"mappings\":[")
    let main_span = lex.span_of(text, no_lines[0usize..0usize], main_name)
    if has_main {
        // Up to the renamed `main`, then after it: the runner's name is 15 bytes longer.
        try runner_mapping(&out, identity, prefix, 0usize, main_name.start, 1usize, 1usize, main_span.line, main_span.column, 3usize, 1usize)
        try write_all(&out, ",")
        let shifted = prefix + main_name.end + 15usize
        try runner_mapping(&out, identity, shifted, main_name.end, text.len, main_span.end_line, main_span.end_column, lines, end_column, main_span.end_line + 2usize, main_span.end_column + 15usize)
    } else {
        try runner_mapping(&out, identity, prefix, 0usize, text.len, 1usize, 1usize, lines, end_column, 3usize, 1usize)
    }
    try write_all(&out, "]}\n")
    let (map_path, map_path_error) = with_suffix(a, runner_path, ".map.json")
    if map_path_error != ok { ret map_path_error }
    ret save_bytes(a, map_path, out.capture[0usize..out.count])
}

fn nptest_stem(path: str) -> str {
    var start = 0usize
    var at = 0usize
    while at < path.len {
        if path[at] == 47u8 || path[at] == 92u8 { start = at + 1usize }
        at += 1usize
    }
    var stop = path.len
    if stop >= 2usize && path[stop - 2usize] == 46u8 && path[stop - 1usize] == 101u8 { stop = stop - 2usize }
    ret path[start..stop]
}

// `test-file PATH ROOT ARCH OS WORKDIR --json` (D240): compile a runner that carries the
// operand's @test functions, run each in its own process, and report section 7's stream.
fn test_command(a: *mem.Arena, args: []str) -> err {
    var no_lines: [1]usize = zero
    var report = stderr_sink()
    report.json = true
    report.file = os.stdout()
    let (text, load_error) = source.load(a, args[2usize])
    if load_error != ok { ret unreadable_operand(&report, "test", "{\"tests\":0}") }
    let (names, names_error) = mem.alloc[str](a, 256usize)
    if names_error != ok { ret names_error }
    let (lines, lines_error) = mem.alloc[usize](a, 256usize)
    if lines_error != ok { ret lines_error }
    if args.len >= 10usize {
        report.operand_source = args[2usize]
        report.operand_path = args[args.len - 1usize]
    }
    var bad: lex.Token = zero
    var bad_kind = 0usize
    var main_name: lex.Token = zero
    var has_main = false
    let (count, discover_error) = discover_tests(a, text, names, lines, &bad, &bad_kind, &main_name, &has_main)
    if discover_error != ok { ret discover_error }
    // A `@test` that is not a test is E-TEST-9999 (D256): the header, the diagnostic at the
    // declaration, and a result that exits 2, the way a runner that fails to compile does.
    if bad_kind != 0usize {
        try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"test\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
        if bad_kind == 1usize {
            try emit_diagnostic(&report, args[2usize], text, no_lines[0usize..0usize], bad, true, "E-TEST-9999", "`@test` marks a function, and this declaration is not one")
        } else {
            try emit_diagnostic(&report, args[2usize], text, no_lines[0usize..0usize], bad, true, "E-TEST-9999", "a test takes one arena and returns `err`: `fn name(a: *mem.Arena) -> err`")
        }
        try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"tests\":0}}\n")
        os.exit(2i32)
        ret ok
    }
    // `test-file ... WORKDIR [TIMEOUT_MS] --json [--path REL]`: the default is a minute (D246).
    var timeout_ms = 60000usize
    if args.len == 9usize || args.len == 11usize { timeout_ms = nptest_parse_usize(args[7usize]) }
    if timeout_ms == 0usize { timeout_ms = 1usize }
    // The identity (D263): the operand's basename and stem, or the `--path` given.
    var identity = basename(args[2usize])
    if args.len >= 10usize { identity = args[args.len - 1usize] }
    let (module_name, module_name_error) = nptest_module_name(a, identity)
    if module_name_error != ok { ret module_name_error }
    // A module with no tests has nothing to compile or run: its stream is the header,
    // an empty summary and the result, and `test-project` counts it (D263).
    if count == 0usize {
        try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"test\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
        try write_all(&report, "{\"record\":\"test_summary\",\"passed\":0,\"failed\":0,\"crashed\":0,\"timeout\":0,\"total\":0,\"duration_ms\":0}\n")
        try write_all(&report, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"tests\":0}}\n")
        ret ok
    }
    let (runner_source, runner_error) = generate_runner(a, text, names[0usize..count], count, timeout_ms * 1000000usize, main_name, has_main)
    if runner_error != ok { ret runner_error }
    let (runner_path, runner_path_error) = nptest_join(a, args[6usize], "nptest-runner.e")
    if runner_path_error != ok { ret runner_path_error }
    let (runner_exe, runner_exe_error) = nptest_join(a, args[6usize], "nptest-runner.exe")
    if runner_exe_error != ok { ret runner_exe_error }
    try save_bytes(a, runner_path, runner_source)
    // The runner's source map (section 8, D264): the operand's text sits two `use` lines
    // down, one mapping, so a diagnostic in it comes back at the operand's own span.
    try write_runner_map(a, runner_path, runner_source, text, identity, main_name, has_main)
    // Compile the runner by spawning this compiler again; args[0] is its own path. The
    // runner lives in WORKDIR but is built as part of the operand's project (D263), so
    // the operand's `use` of its sibling modules resolves from there.
    var build_argv: [10]str = zero
    build_argv[0usize] = args[0usize]
    build_argv[1usize] = "emit-executable"
    build_argv[2usize] = runner_path
    build_argv[3usize] = args[3usize]
    build_argv[4usize] = args[4usize]
    build_argv[5usize] = args[5usize]
    build_argv[6usize] = runner_exe
    build_argv[7usize] = "--json"
    var build_argc = 8usize
    let (operand_project, project_error) = project.discover(a, args[2usize])
    if project_error == ok && operand_project.has_sources {
        build_argv[8usize] = "--project"
        build_argv[9usize] = operand_project.root
        build_argc = 10usize
    }
    let (build_status, build_out, build_err, build_spawn_error) = nptest_spawn(a, build_argv[0usize..build_argc], runner_exe)
    if build_spawn_error != ok { ret build_spawn_error }
    if build_status != 0i32 {
        try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"test\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
        // The compiler's own diagnostics first, mapped back onto the operand by the map.
        let (forwarded, forward_error) = forward_diagnostics(&report, build_out, "")
        if forward_error != ok { ret forward_error }
        try emit_command_diagnostic(&report, "E-CLI-9999", "the tests could not be compiled")
        try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"tests\":0}}\n")
        os.exit(2i32)
        ret ok
    }
    let (outcomes, outcomes_error) = mem.alloc[usize](a, 256usize)
    if outcomes_error != ok { ret outcomes_error }
    let (stdouts, stdouts_error) = mem.alloc[str](a, 256usize)
    if stdouts_error != ok { ret stdouts_error }
    let (stderrs, stderrs_error) = mem.alloc[str](a, 256usize)
    if stderrs_error != ok { ret stderrs_error }
    let (durations, durations_error) = mem.alloc[usize](a, 256usize)
    if durations_error != ok { ret durations_error }
    let (statuses, statuses_error) = mem.alloc[i32](a, 256usize)
    if statuses_error != ok { ret statuses_error }
    let suite_start = nptest_now()
    var index_storage: [8]u8 = zero
    var at = 0usize
    while at < count {
        let index_len = nptest_append_decimal(index_storage[..], 0usize, at)
        let index_str = index_storage[0usize..index_len]
        let (child_base, child_base_error) = nptest_join(a, args[6usize], "nptest-child")
        if child_base_error != ok { ret child_base_error }
        let test_start = nptest_now()
        let (status, child_out, child_err, run_error) = nptest_run(a, runner_exe, index_str, child_base)
        if run_error != ok { ret run_error }
        let test_end = nptest_now()
        var elapsed_ms = 0usize
        if test_end > test_start { elapsed_ms = (test_end - test_start) / 1000000usize }
        durations[at] = elapsed_ms
        var outcome = 0usize
        if status != 0i32 {
            outcome = 2usize
            if child_err.len >= 7usize && same(child_err[0usize..7usize], "error: ") { outcome = 1usize }
            // The watchdog's own exit code, so a test still running at the deadline.
            if status == 124i32 { outcome = 3usize }
        }
        outcomes[at] = outcome
        statuses[at] = status
        stdouts[at] = child_out
        stderrs[at] = child_err
        at += 1usize
    }
    let suite_end = nptest_now()
    var suite_ms = 0usize
    if suite_end > suite_start { suite_ms = (suite_end - suite_start) / 1000000usize }
    var timeout_s = (timeout_ms + 999usize) / 1000usize
    if timeout_s == 0usize { timeout_s = 1usize }
    // The child prints the runner by its reproducible spelling (D337), the basename
    // for a file under no source root.
    try tool.test_json(a, module_name, "operand", identity, text, basename(runner_path), names[0usize..count], lines[0usize..count], outcomes[0usize..count], statuses[0usize..count], durations[0usize..count], stdouts[0usize..count], stderrs[0usize..count], count, suite_ms, timeout_s)
    var any = false
    at = 0usize
    while at < count {
        if outcomes[at] != 0usize { any = true }
        at += 1usize
    }
    if any { os.exit(1i32) }
    ret ok
}

fn nptest_join(a: *mem.Arena, dir: str, name: str) -> (str, err) {
    var separator = 1usize
    if dir.len != 0usize && (dir[dir.len - 1usize] == 47u8 || dir[dir.len - 1usize] == 92u8) { separator = 0usize }
    let (buffer, buffer_error) = mem.alloc[u8](a, dir.len + separator + name.len)
    if buffer_error != ok { ret ("", buffer_error) }
    var at = nptest_append(buffer, 0usize, dir)
    if separator == 1usize {
        buffer[at] = 47u8
        at += 1usize
    }
    at = nptest_append(buffer, at, name)
    ret (buffer[0usize..at], ok)
}

fn manifest_command(a: *mem.Arena, args: []str) -> err {
    var report = stderr_sink()
    var loaded: graph.Graph = zero
    try init_cli_graph(a, &loaded)
    try load_graph(a, &report, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
    let (exit, manifest_error) = tool.manifest_json(a, args[4usize], args[5usize], &loaded)
    if manifest_error != ok { ret manifest_error }
    if exit != 0usize { os.exit(i32(exit)) }
    ret ok
}

// Section 1's envelope for an operand that cannot be read, on every `--json` command
// (D260): the header, one location-free E-CLI-9999, and the result exiting 2 with the
// command's own zero counts -- so a harness sees a stream, never a bare `error:` line.
fn unreadable_operand(report: *Sink, command: str, data: str) -> err {
    try write_all(report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"")
    try write_all(report, command)
    try write_all(report, "\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
    try emit_command_diagnostic(report, "E-CLI-9999", "the operand cannot be read")
    try write_all(report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":")
    try write_all(report, data)
    try write_all(report, "}\n")
    os.exit(2i32)
    ret ok
}

fn json_sink() -> Sink {
    var report = stderr_sink()
    report.json = true
    report.file = os.stdout()
    ret report
}

// Every `.e` file under `dir`, depth first, entries in byte order so the stream is the
// same on every filesystem; `rel` is the path under the source root, with `/`.
// ponytail: 1024 files per project is the cap; raise it when a project has more.
fn walk_sources(a: *mem.Arena, dir: str, rel: str, paths: []str, rels: []str, count: *usize) -> err {
    let (entries, readdir_error) = os.readdir(a, dir)
    if readdir_error != ok { ret readdir_error }
    let (names, names_error) = mem.alloc[str](a, entries.len)
    if names_error != ok { ret names_error }
    let (kinds, kinds_error) = mem.alloc[os.EntryKind](a, entries.len)
    if kinds_error != ok { ret kinds_error }
    var sorted = 0usize
    for entry in entries {
        var slot = sorted
        while slot > 0usize && str_after(names[slot - 1usize], entry.name) {
            names[slot] = names[slot - 1usize]
            kinds[slot] = kinds[slot - 1usize]
            slot = slot - 1usize
        }
        names[slot] = entry.name
        kinds[slot] = entry.kind
        sorted += 1usize
    }
    var at = 0usize
    while at < sorted {
        let (full, full_error) = nptest_join(a, dir, names[at])
        if full_error != ok { ret full_error }
        var child_rel = names[at]
        if rel.len != 0usize {
            let (joined, joined_error) = nptest_join(a, rel, names[at])
            if joined_error != ok { ret joined_error }
            child_rel = joined
        }
        if kinds[at] == .Dir {
            try walk_sources(a, full, child_rel, paths, rels, count)
        } else {
            let name = names[at]
            if name.len > 2usize && name[name.len - 2usize] == 46u8 && name[name.len - 1usize] == 101u8 {
                if *count == paths.len { ret parse.InvalidSyntax }
                paths[*count] = full
                rels[*count] = child_rel
                *count += 1usize
            }
        }
        at += 1usize
    }
    ret ok
}

// Byte order: whether `a` sorts after `b`.
fn str_after(a: str, b: str) -> bool {
    var at = 0usize
    while at < a.len && at < b.len {
        if a[at] != b[at] { ret a[at] > b[at] }
        at += 1usize
    }
    ret a.len > b.len
}

// `check-project` (D262): `check-file --json --path REL` on every module under DIR/src,
// in byte order of path, each in its own process, their records merged into one stream
// -- the header once, every diagnostic whose identity is the module being checked, and
// one result with the total. A diagnostic in an imported module is dropped from that
// child's stream: it is reported when that module is the one checked, and would
// otherwise come out twice under two names.
// `index-project DIR ROOT ARCH OS WORKDIR --json` (D298): every `.e` under DIR/src
// and DIR/lib in byte order, each indexed by `index-file --json --path REL` in its own
// process, the symbol, reference and diagnostic records forwarded under one header
// and one result carrying the totals; a module that fails to index fails the command.
fn index_project_command(a: *mem.Arena, args: []str) -> err {
    var report = stderr_sink()
    report.json = true
    report.file = os.stdout()
    try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"index\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
    let (paths, paths_error) = mem.alloc[str](a, 4096usize)
    if paths_error != ok { ret paths_error }
    let (rels, rels_error) = mem.alloc[str](a, 4096usize)
    if rels_error != ok { ret rels_error }
    var count = 0usize
    var root_at = 0usize
    while root_at < 2usize {
        var leaf = "src"
        if root_at == 1usize { leaf = "lib" }
        let (dir, dir_error) = nptest_join(a, args[2usize], leaf)
        if dir_error != ok { ret dir_error }
        let (probe, probe_error) = os.readdir(a, dir)
        if probe_error == ok { try walk_sources(a, dir, leaf, paths, rels, &count) }
        root_at += 1usize
    }
    let (child_base, child_base_error) = nptest_join(a, args[6usize], "npindex-child")
    if child_base_error != ok { ret child_base_error }
    var symbols = 0usize
    var references = 0usize
    var failed = false
    var at = 0usize
    while at < count {
        var argv: [9]str = zero
        argv[0usize] = args[0usize]
        argv[1usize] = "index-file"
        argv[2usize] = paths[at]
        argv[3usize] = args[3usize]
        argv[4usize] = args[4usize]
        argv[5usize] = args[5usize]
        argv[6usize] = "--json"
        argv[7usize] = "--path"
        argv[8usize] = rels[at]
        let (status, child_out, child_err, spawn_error) = nptest_spawn(a, argv[..], child_base)
        if spawn_error != ok { ret spawn_error }
        if status != 0i32 { failed = true }
        let (child_symbols, child_references, forward_error) = forward_index(&report, child_out, symbols)
        if forward_error != ok { ret forward_error }
        symbols += child_symbols
        references += child_references
        at += 1usize
    }
    if failed {
        try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":1,\"data\":{\"symbols\":")
    } else {
        try write_all(&report, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"symbols\":")
    }
    try write_usize(&report, symbols)
    try write_all(&report, ",\"references\":")
    try write_usize(&report, references)
    try write_all(&report, ",\"modules\":")
    try write_usize(&report, count)
    try write_all(&report, "}}\n")
    if failed { os.exit(1i32) }
    ret ok
}

// One index record with `base` added to its `id`, `container_id` and `target_id` when
// they are numbers; `null` and every other byte copied as they are.
fn forward_renumbered(report: *Sink, line: str, base: usize) -> err {
    var at = 0usize
    while at < line.len {
        var key_len = 0usize
        if at + 5usize <= line.len && same(line[at..at + 5usize], "\"id\":") && at > 0usize && (line[at - 1usize] == 44u8 || line[at - 1usize] == 123u8) { key_len = 5usize }
        if at + 15usize <= line.len && same(line[at..at + 15usize], "\"container_id\":") { key_len = 15usize }
        if at + 12usize <= line.len && same(line[at..at + 12usize], "\"target_id\":") { key_len = 12usize }
        if key_len != 0usize && at + key_len < line.len && line[at + key_len] >= 48u8 && line[at + key_len] <= 57u8 {
            try write_all(report, line[at..at + key_len])
            var end = at + key_len
            var value = 0usize
            while end < line.len && line[end] >= 48u8 && line[end] <= 57u8 {
                value = value * 10usize + usize(line[end] - 48u8)
                end += 1usize
            }
            try write_usize(report, value + base)
            at = end
        } else {
            try write_all(report, line[at..at + 1usize])
            at += 1usize
        }
    }
    ret ok
}

// Every record of one child's index stream but its header and result, forwarded as it
// is; the symbols and references counted.
fn forward_index(report: *Sink, stream: str, base: usize) -> (usize, usize, err) {
    var symbols = 0usize
    var references = 0usize
    var at = 0usize
    while at < stream.len {
        var end = at
        while end < stream.len && stream[end] != 10u8 { end += 1usize }
        let line = stream[at..end]
        let is_symbol = line.len > 18usize && same(line[0usize..18usize], "{\"record\":\"symbol\"")
        let is_reference = line.len > 21usize && same(line[0usize..21usize], "{\"record\":\"reference\"")
        let is_diagnostic = line.len > 22usize && same(line[0usize..22usize], "{\"record\":\"diagnostic\"")
        if is_symbol || is_reference || is_diagnostic {
            // Section 5: `id` is the record number among the stream's symbols, so a
            // child's ids, and what points at them, move up by the symbols before it.
            let write_error = forward_renumbered(report, line, base)
            if write_error != ok { ret (0usize, 0usize, write_error) }
            let newline_error = write_all(report, "\n")
            if newline_error != ok { ret (0usize, 0usize, newline_error) }
            if is_symbol { symbols += 1usize }
            if is_reference { references += 1usize }
        }
        at = end + 1usize
    }
    ret (symbols, references, ok)
}

fn check_project_command(a: *mem.Arena, args: []str) -> err {
    var report = stderr_sink()
    report.json = true
    report.file = os.stdout()
    try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"check\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
    let (paths, paths_error) = mem.alloc[str](a, 1024usize)
    if paths_error != ok { ret paths_error }
    let (rels, rels_error) = mem.alloc[str](a, 1024usize)
    if rels_error != ok { ret rels_error }
    let (source_dir, source_dir_error) = nptest_join(a, args[2usize], "src")
    if source_dir_error != ok { ret source_dir_error }
    var count = 0usize
    let walk_error = walk_sources(a, source_dir, "", paths, rels, &count)
    if walk_error != ok {
        try emit_command_diagnostic(&report, "E-CLI-9999", "the project has no readable src directory")
        try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"diagnostics\":1,\"modules\":0}}\n")
        os.exit(2i32)
        ret ok
    }
    let (child_base, child_base_error) = nptest_join(a, args[6usize], "npcheck-child")
    if child_base_error != ok { ret child_base_error }
    var diagnostics = 0usize
    var at = 0usize
    while at < count {
        var argv: [9]str = zero
        argv[0usize] = args[0usize]
        argv[1usize] = "check-file"
        argv[2usize] = paths[at]
        argv[3usize] = args[3usize]
        argv[4usize] = args[4usize]
        argv[5usize] = args[5usize]
        argv[6usize] = "--json"
        argv[7usize] = "--path"
        argv[8usize] = rels[at]
        let (status, child_out, child_err, spawn_error) = nptest_spawn(a, argv[..], child_base)
        if spawn_error != ok { ret spawn_error }
        let (forwarded, forward_error) = forward_diagnostics(&report, child_out, rels[at])
        if forward_error != ok { ret forward_error }
        diagnostics += forwarded
        at += 1usize
    }
    if diagnostics == 0usize {
        try write_all(&report, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"diagnostics\":0,\"modules\":")
    } else {
        try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":1,\"data\":{\"diagnostics\":")
        try write_usize(&report, diagnostics)
        try write_all(&report, ",\"modules\":")
    }
    try write_usize(&report, count)
    try write_all(&report, "}}\n")
    if diagnostics != 0usize { os.exit(1i32) }
    ret ok
}

// The diagnostic records of one child's stream whose identity is `rel`, forwarded as
// they are; the child's header and result are its own and are dropped.
fn forward_diagnostics(report: *Sink, stream: str, rel: str) -> (usize, err) {
    var forwarded = 0usize
    var at = 0usize
    while at < stream.len {
        var end = at
        while end < stream.len && stream[end] != 10u8 { end += 1usize }
        let line = stream[at..end]
        if line.len > 22usize && same(line[0usize..22usize], "{\"record\":\"diagnostic\"") && diagnostic_names(line, rel) {
            let write_error = write_all(report, line)
            if write_error != ok { ret (0usize, write_error) }
            let newline_error = write_all(report, "\n")
            if newline_error != ok { ret (0usize, newline_error) }
            forwarded += 1usize
        }
        at = end + 1usize
    }
    ret (forwarded, ok)
}

// Whether a diagnostic line's span names `rel` as its operand path, or has no span at
// all -- a command diagnostic belongs to the module it was raised for.
fn diagnostic_names(line: str, rel: str) -> bool {
    if rel.len == 0usize { ret true }
    var scratch: [1024]u8 = zero
    var needle_len = nptest_append(scratch[..], 0usize, "\"path\":\"")
    needle_len = nptest_append(scratch[..], needle_len, rel)
    needle_len = nptest_append(scratch[..], needle_len, "\"}")
    let needle = scratch[0usize..needle_len]
    var at = 0usize
    while at + needle.len <= line.len {
        if same(line[at..at + needle.len], needle) { ret true }
        at += 1usize
    }
    var span_null = 0usize
    while span_null + 12usize <= line.len {
        if same(line[span_null..span_null + 12usize], "\"span\":null,") { ret true }
        span_null += 1usize
    }
    ret false
}

// An operand's text: the file's, or all of stdin for `-` (D289).
fn operand_text(a: *mem.Arena, file: str) -> (str, err) {
    if same(file, "-") {
        let (piped, piped_error) = source.load_stdin(a)
        ret (piped, piped_error)
    }
    let (text, load_error) = source.load(a, file)
    ret (text, load_error)
}

// `fmt`'s operand identity: the `--path` spelling when given, else the file's basename
// -- or `-` itself, since section 6's `fmt -` needs no identity to write source (D289).
fn fmt_identity(args: []str) -> str {
    if args.len >= 5usize && same(args[args.len - 2usize], "--path") { ret args[args.len - 1usize] }
    ret basename(args[2usize])
}

// `fmt-file PATH|- [--check] [--json] [--path VIRTUAL.e]`: the form is matched with the
// `--path` pair taken off the end, so the count checks below see only the flags.
fn fmt_form(args: []str) -> []str {
    if args.len >= 5usize && same(args[args.len - 2usize], "--path") { ret args[0usize..args.len - 2usize] }
    ret args
}

// `check-file PATH ROOT ARCH OS [--json] [--path VIRTUAL.e] [--absolute-paths]`: the
// flags after the positionals, into the sink; false when one is not a flag.
fn check_flags(a: *mem.Arena, report: *Sink, args: []str) -> bool {
    var at = 6usize
    while at < args.len {
        if same(args[at], "--json") {
            report.json = true
            report.file = os.stdout()
        } else {
            if same(args[at], "--path") && at + 1usize < args.len {
                report.operand_source = args[2usize]
                report.operand_path = args[at + 1usize]
                at += 1usize
            } else {
                if !same(args[at], "--absolute-paths") { ret false }
                report.operand_source = args[2usize]
                report.absolute_path = absolute_operand(a, args[2usize])
            }
        }
        at += 1usize
    }
    ret true
}

// The operand's absolute spelling for `--absolute-paths` (section 2, D290): as given
// when it is already absolute, else under the current directory. Empty for `-` or
// when the directory cannot be read, and then no `absolute_path` is written.
// ponytail: `.` and `..` segments are kept; collapse them if a consumer compares paths.
fn absolute_operand(a: *mem.Arena, operand: str) -> str {
    if same(operand, "-") || operand.len == 0usize { ret "" }
    if operand[0usize] == 47u8 || operand[0usize] == 92u8 || (operand.len >= 2usize && operand[1usize] == 58u8) { ret operand }
    let (dir, dir_error) = os.current_dir(a)
    if dir_error != ok { ret "" }
    var separator = "/"
    if dir.len >= 2usize && dir[1usize] == 58u8 { separator = "\\" }
    let (joined, join_error) = mem.alloc[u8](a, dir.len + 1usize + operand.len)
    if join_error != ok { ret "" }
    var n = nptest_append(joined, 0usize, dir)
    n = nptest_append(joined, n, separator)
    n = nptest_append(joined, n, operand)
    ret joined[0usize..n]
}

fn fmt_command(a: *mem.Arena, args: []str) -> err {
    let path = fmt_identity(args)
    let (text, load_error) = operand_text(a, args[2usize])
    if load_error != ok {
        var report = json_sink()
        ret unreadable_operand(&report, "fmt", "{\"diagnostics\":1}")
    }
    let (fmt_exit, fmt_error) = tool.fmt_json(a, text, path)
    if fmt_error != ok { ret fmt_error }
    if fmt_exit != 0usize { os.exit(i32(fmt_exit)) }
    ret ok
}

fn fmt_plain_command(a: *mem.Arena, args: []str) -> err {
    let path = fmt_identity(args)
    let (text, load_error) = operand_text(a, args[2usize])
    if load_error != ok {
        var report = stderr_sink()
        try emit_command_diagnostic(&report, "E-CLI-9999", "the operand cannot be read")
        os.exit(2i32)
        ret ok
    }
    let (plain_exit, plain_error) = tool.fmt_plain(a, text, path)
    if plain_error != ok { ret plain_error }
    if plain_exit != 0usize { os.exit(i32(plain_exit)) }
    ret ok
}

// The file formatted in place (D295): nothing written when it is canonical already,
// nothing on stdout either way; a refusal is the human lines on stderr and exit 1.
fn fmt_write_command(a: *mem.Arena, args: []str, file: str) -> err {
    let exit_code = fmt_write(a, file, fmt_identity(args))
    if exit_code != 0usize { os.exit(i32(exit_code)) }
    ret ok
}

// One file's in-place format: 0 when it is canonical now, 1 when refused, 2 when it
// could not be read or written (said on stderr).
fn fmt_write(a: *mem.Arena, file: str, path: str) -> usize {
    let (text, load_error) = source.load(a, file)
    if load_error != ok {
        var report = stderr_sink()
        let said = emit_command_diagnostic(&report, "E-CLI-9999", "the operand cannot be read")
        ret 2usize
    }
    let (formatted, exit_code, text_error) = tool.fmt_plain_text(a, text, path)
    if text_error != ok { ret 2usize }
    if exit_code != 0usize { ret exit_code }
    if same(formatted, text) { ret 0usize }
    let (bytes, bytes_error) = mem.alloc[u8](a, formatted.len)
    if bytes_error != ok { ret 2usize }
    let count = nptest_append(bytes, 0usize, formatted)
    if save_bytes(a, file, bytes[0usize..count]) != ok {
        var report = stderr_sink()
        let said = emit_command_diagnostic(&report, "E-CLI-9999", "the operand could not be written")
        ret 2usize
    }
    ret 0usize
}

// Every `.e` under the project's `src/` and `lib/`, in byte order (D295): `--write`
// formats each in place; `--check` writes nothing and names each file that is not
// canonical as an E-FORMAT-0001 line on stderr, exiting 1 when any is.
// ponytail: `--check` here is the human lines only; the `--json` stream over a project
// waits for a merged-stream shape like check-project's.
fn fmt_project_command(a: *mem.Arena, args: []str) -> err {
    let checking = same(args[3usize], "--check")
    let (paths, paths_error) = mem.alloc[str](a, 4096usize)
    if paths_error != ok { ret paths_error }
    let (rels, rels_error) = mem.alloc[str](a, 4096usize)
    if rels_error != ok { ret rels_error }
    var count = 0usize
    var root_at = 0usize
    while root_at < 2usize {
        var leaf = "src"
        if root_at == 1usize { leaf = "lib" }
        let (dir, dir_error) = nptest_join(a, args[2usize], leaf)
        if dir_error != ok { ret dir_error }
        // A root the project does not have is simply empty.
        let (probe, probe_error) = os.readdir(a, dir)
        if probe_error == ok { try walk_sources(a, dir, leaf, paths, rels, &count) }
        root_at += 1usize
    }
    var worst = 0usize
    var at = 0usize
    while at < count {
        if checking {
            let (text, load_error) = source.load(a, paths[at])
            if load_error != ok { ret load_error }
            let (formatted, exit_code, text_error) = tool.fmt_plain_text(a, text, rels[at])
            if text_error != ok { ret text_error }
            var verdict = exit_code
            if verdict == 0usize && !same(formatted, text) {
                try stderr_text(rels[at])
                try stderr_text(": error[E-FORMAT-0001]: source is not in canonical layout\n")
                verdict = 1usize
            }
            if verdict > worst { worst = verdict }
        } else {
            let verdict = fmt_write(a, paths[at], rels[at])
            if verdict > worst { worst = verdict }
        }
        at += 1usize
    }
    if worst != 0usize { os.exit(i32(worst)) }
    ret ok
}

fn fmt_check_command(a: *mem.Arena, args: []str) -> err {
    let path = fmt_identity(args)
    let (text, load_error) = operand_text(a, args[2usize])
    if load_error != ok {
        var report = json_sink()
        ret unreadable_operand(&report, "fmt", "{\"diagnostics\":1}")
    }
    let (check_exit, check_error) = tool.fmt_check_json(a, text, path)
    if check_error != ok { ret check_error }
    if check_exit != 0usize { os.exit(i32(check_exit)) }
    ret ok
}

fn index_command(a: *mem.Arena, args: []str) -> err {
    var report = stderr_sink()
    var absolute_path = ""
    if args.len == 8usize { absolute_path = absolute_operand(a, args[2usize]) }
    report.json = true
    report.file = os.stdout()
    var loaded: graph.Graph = zero
    try init_cli_graph(a, &loaded)
    let load_error = load_graph(a, &report, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
    if load_error != ok {
        try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"index\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
        try emit_command_diagnostic(&report, "E-CLI-9999", "the operand cannot be read as a module")
        try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"symbols\":0,\"references\":0}}\n")
        os.exit(2i32)
        ret ok
    }
    var resolver: resolve.Resolver = zero
    try init_cli_resolver(a, &resolver, &loaded, &report)
    let resolve_error = resolve.collect(&resolver, &loaded)
    if resolve_error != ok {
        try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"index\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
        try print_resolve_diagnostic(&report, &loaded, &resolver, resolve_error)
        try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":1,\"data\":{\"symbols\":0,\"references\":0}}\n")
        os.exit(1i32)
        ret ok
    }
    var identity = basename(args[2usize])
    if args.len == 9usize { identity = args[8usize] }
    let (index_exit, index_error) = tool.index_json(a, "operand", identity, loaded.modules[0usize].text, loaded.modules[0usize].name, 0usize, resolver.symbols[0usize..resolver.count], resolver.count, absolute_path)
    if index_error != ok { ret index_error }
    if index_exit != 0usize { os.exit(i32(index_exit)) }
    ret ok
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
    var absolute = false
    var at = 2usize
    while at < args.len {
        if same(args[at], "--json") {
            json = true
        } else {
            if same(args[at], "--absolute-paths") {
                absolute = true
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
        }
        at += 1usize
    }
    var absolute_path = ""
    if absolute { absolute_path = absolute_operand(a, file) }
    // `-` is stdin, and then `--path` is its identity and required (section 4, D289).
    if !has_file || (same(file, "-") && !has_virtual) { ret tool_usage() }
    let (text, load_error) = operand_text(a, file)
    if load_error != ok {
        if !json { ret load_error }
        var envelope = json_sink()
        if parsing { ret unreadable_operand(&envelope, "parse", "{\"tokens\":0,\"diagnostics\":1}") }
        ret unreadable_operand(&envelope, "tokens", "{\"tokens\":0,\"diagnostics\":1}")
    }
    var path = virtual_path
    if !has_virtual { path = basename(file) }
    if json {
        var exit_code = 0usize
        if parsing {
            let (parse_exit, parse_error) = tool.parse_json(a, "operand", path, text, absolute_path)
            if parse_error != ok { ret parse_error }
            exit_code = parse_exit
        } else {
            let (tokens_exit, tokens_error) = tool.tokens_json(a, "operand", path, text, absolute_path)
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
    let (children, children_error) = mem.alloc[u32](a, 65536usize)
    if children_error != ok { ret children_error }
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, nodes, children)
    let parse_error = parse.parse(&tree, text)
    if parse_error != ok && tree.has_failure {
        try print_parse_failure(report, path, text, tree.failure_token, tree.failure_reserved_name, tree.failure_too_deep)
        os.exit(1i32)
    }
    ret parse_error
}

fn init_cli_graph(a: *mem.Arena, loaded: *graph.Graph) -> err {
    // Modules and imports are the two pools that exist before anything is measured
    // (D306); the tree pool starts small and grows to the largest module as it loads.
    let (modules, modules_error) = mem.alloc[graph.Module](a, 8192usize)
    if modules_error != ok { ret modules_error }
    let (imports, imports_error) = mem.alloc[graph.Import](a, 262144usize)
    if imports_error != ok { ret imports_error }
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, 4096usize)
    if nodes_error != ok { ret nodes_error }
    let (children, children_error) = mem.alloc[u32](a, 16384usize)
    if children_error != ok { ret children_error }
    try graph.init(loaded, modules, imports, nodes, children)
    // Dependency order (D304), one slot per module.
    let (order, order_error) = mem.alloc[usize](a, modules.len)
    if order_error != ok { ret order_error }
    graph.set_order(loaded, order)
    ret ok
}

fn init_cli_resolver(a: *mem.Arena, resolver: *resolve.Resolver, loaded: *graph.Graph, report: *Sink) -> err {
    let total = loaded.total_bytes
    let largest = loaded.largest_bytes
    let (symbols, symbols_error) = mem.alloc[resolve.Symbol](a, sized(4096usize, total, 64usize))
    if symbols_error != ok { ret symbols_error }
    report.build.pools[stats.POOL_SYMBOLS] = symbols.len
    // The largest module, `check.e`, needs between 65536 and 69632 tokens, measured
    // by bisecting this until resolution reports `resolve.Capacity`. 131072 keeps
    // about twice that; `MAX_TOKENS` in the bootstrap is the same number for the same
    // reason.
    let (tokens, tokens_error) = mem.alloc[lex.Token](a, sized(4096usize, largest, 3usize))
    if tokens_error != ok { ret tokens_error }
    report.build.pools[stats.POOL_RESOLVER_TOKENS] = tokens.len
    let (locals, locals_error) = mem.alloc[resolve.Local](a, sized(16384usize, largest, 16usize))
    if locals_error != ok { ret locals_error }
    report.build.pools[stats.POOL_RESOLVER_LOCALS] = locals.len
    try resolve.init(resolver, symbols, tokens, locals)
    // The name index (D303): four entries per symbol covers the doubling regions.
    let (entries, entries_error) = mem.alloc[lookup.Entry](a, symbols.len * 4usize)
    if entries_error != ok { ret entries_error }
    report.build.pools[stats.POOL_RESOLVER_INDEX] = entries.len
    ret resolve.attach_index(resolver, entries)
}

fn init_cli_checker(a: *mem.Arena, checker: *check.Checker, loaded: *graph.Graph, report: *Sink) -> err {
    let total = loaded.total_bytes
    let largest = loaded.largest_bytes
    let (functions, functions_error) = mem.alloc[check.Function](a, sized(4096usize, total, 128usize))
    if functions_error != ok { ret functions_error }
    report.build.pools[stats.POOL_FUNCTIONS] = functions.len
    let (function_generics, function_generics_error) = mem.alloc[check.FunctionGeneric](a, sized(4096usize, total, 128usize))
    if function_generics_error != ok { ret function_generics_error }
    let (parameters, parameters_error) = mem.alloc[check.Parameter](a, sized(8192usize, total, 64usize))
    if parameters_error != ok { ret parameters_error }
    report.build.pools[stats.POOL_PARAMETERS] = parameters.len
    let (return_types, return_types_error) = mem.alloc[check.Type](a, sized(65536usize, total, 64usize))
    if return_types_error != ok { ret return_types_error }
    report.build.pools[stats.POOL_RETURN_TYPES] = return_types.len
    let (comptime_parameters, comptime_parameters_error) = mem.alloc[check.ComptimeParameter](a, sized(1024usize, total, 1024usize))
    if comptime_parameters_error != ok { ret comptime_parameters_error }
    report.build.pools[stats.POOL_COMPTIME_PARAMETERS] = comptime_parameters.len
    let (generic_arguments, generic_arguments_error) = mem.alloc[check.GenericArgument](a, sized(4096usize, total, 256usize))
    if generic_arguments_error != ok { ret generic_arguments_error }
    report.build.pools[stats.POOL_GENERIC_ARGUMENTS] = generic_arguments.len
    let (aggregates, aggregates_error) = mem.alloc[check.Aggregate](a, sized(4096usize, total, 256usize))
    if aggregates_error != ok { ret aggregates_error }
    report.build.pools[stats.POOL_AGGREGATES] = aggregates.len
    let (aggregate_fields, aggregate_fields_error) = mem.alloc[check.AggregateField](a, sized(8192usize, total, 128usize))
    if aggregate_fields_error != ok { ret aggregate_fields_error }
    report.build.pools[stats.POOL_AGGREGATE_FIELDS] = aggregate_fields.len
    let (checked_switches, checked_switches_error) = mem.alloc[check.CheckedSwitch](a, sized(4096usize, total, 256usize))
    if checked_switches_error != ok { ret checked_switches_error }
    report.build.pools[stats.POOL_CHECKED_SWITCHES] = checked_switches.len
    let (function_signatures, function_signatures_error) = mem.alloc[check.FunctionSignature](a, sized(4096usize, total, 128usize))
    if function_signatures_error != ok { ret function_signatures_error }
    let (tokens, tokens_error) = mem.alloc[lex.Token](a, sized(4096usize, largest, 3usize))
    if tokens_error != ok { ret tokens_error }
    report.build.pools[stats.POOL_CHECKER_TOKENS] = tokens.len
    let (locals, locals_error) = mem.alloc[check.Local](a, sized(16384usize, largest, 16usize))
    if locals_error != ok { ret locals_error }
    report.build.pools[stats.POOL_CHECKER_LOCALS] = locals.len
    let (types, types_error) = mem.alloc[check.Type](a, sized(65536usize, total, 64usize))
    if types_error != ok { ret types_error }
    report.build.pools[stats.POOL_TYPES] = types.len
    let (aliases, aliases_error) = mem.alloc[check.Alias](a, sized(4096usize, total, 256usize))
    if aliases_error != ok { ret aliases_error }
    report.build.pools[stats.POOL_ALIASES] = aliases.len
    let (constants, constants_error) = mem.alloc[check.Constant](a, sized(4096usize, total, 256usize))
    if constants_error != ok { ret constants_error }
    report.build.pools[stats.POOL_CONSTANTS] = constants.len
    // Module-scope `var`s. Small on purpose: the whole point of the surface is that ambient
    // mutable state is rare, and a program that wants hundreds of them wants a struct instead.
    let (globals, globals_error) = mem.alloc[check.Global](a, sized(256usize, total, 1024usize))
    if globals_error != ok { ret globals_error }
    report.build.pools[stats.POOL_GLOBALS] = globals.len
    let (constant_exprs, constant_exprs_error) = mem.alloc[check.ConstantExpr](a, sized(32768usize, total, 256usize))
    if constant_exprs_error != ok { ret constant_exprs_error }
    report.build.pools[stats.POOL_CONSTANT_EXPRS] = constant_exprs.len
    let (diagnostics, diagnostics_error) = mem.alloc[check.Diagnostic](a, sized(4096usize, total, 4096usize))
    if diagnostics_error != ok { ret diagnostics_error }
    report.build.pools[stats.POOL_DIAGNOSTICS] = diagnostics.len
    try check.init(checker, functions, parameters, return_types, tokens, locals, types, aliases, constants, globals, constant_exprs, diagnostics)
    let (call_cache, call_cache_error) = mem.alloc[check.CallCacheEntry](a, 4096usize)
    if call_cache_error != ok { ret call_cache_error }
    checker.call_cache = call_cache
    let (expr_cache, expr_cache_error) = mem.alloc[check.ExprCacheEntry](a, 16384usize)
    if expr_cache_error != ok { ret expr_cache_error }
    checker.expr_cache = expr_cache
    try check.init_generics(checker, function_generics, comptime_parameters, generic_arguments)
    try check.init_aggregates(checker, aggregates, aggregate_fields)
    try check.init_control(checker, checked_switches, function_signatures)
    // The declaration index (D303): the five named tables, four entries per row.
    let (entries, entries_error) = mem.alloc[lookup.Entry](a, (functions.len + aggregates.len + aliases.len + constants.len + globals.len) * 4usize)
    if entries_error != ok { ret entries_error }
    report.build.pools[stats.POOL_CHECKER_INDEX] = entries.len
    // The writer's spans (D320): nine tables, a first and an end per module, zeroed
    // since a debug build's allocation is filled.
    let (spans, spans_error) = mem.alloc[usize](a, em.span_tables() * loaded.count * 2usize)
    if spans_error != ok { ret spans_error }
    var span_at = 0usize
    while span_at < spans.len {
        spans[span_at] = 0usize
        span_at += 1usize
    }
    checker.writer_spans = spans
    let (body_hashes, body_hashes_error) = mem.alloc[usize](a, functions.len)
    if body_hashes_error != ok { ret body_hashes_error }
    try clear_usizes(body_hashes)
    checker.body_hashes = body_hashes
    ret check.attach_index(checker, entries)
}

fn clear_usizes(values: []usize) -> err {
    var at = 0usize
    while at < values.len {
        values[at] = 0usize
        at += 1usize
    }
    ret ok
}

// The inlining oracle's builder (D207): the short functions of every module, which the
// source filter keeps to a few instructions each, so a tenth of the program's tables.
// An oracle lowers every candidate function before it knows which are short enough to
// inline (D207), so its pools are the main builder's sizes (D308).
fn init_oracle_nir(a: *mem.Arena, builder: *nir.Builder, signatures: *nir.Signatures, signature_type_capacity: usize, total: usize) -> err {
    // An oracle keeps a body of at most the cap per entry and drops the rest as it
    // goes (D310), so its pools follow the entry table, not the program (D313): sized
    // like the builder's, the two oracles were two thirds of a two-million-line
    // release build's arena. The function table is the entries plus the one being
    // lowered; the rest is the cap's worth per entry, with room to spare.
    let (functions, functions_error) = mem.alloc[nir.Function](a, sized(4096usize, total, 128usize) + 1usize)
    if functions_error != ok { ret functions_error }
    let (blocks, blocks_error) = mem.alloc[nir.Block](a, sized(16384usize, total, 256usize))
    if blocks_error != ok { ret blocks_error }
    let (instructions, instructions_error) = mem.alloc[nir.Instruction](a, sized(65536usize, total, 64usize))
    if instructions_error != ok { ret instructions_error }
    let (operands, operands_error) = mem.alloc[usize](a, sized(262144usize, total, 16usize))
    if operands_error != ok { ret operands_error }
    let (function_refs, function_refs_error) = mem.alloc[nir.FunctionRef](a, sized(8192usize, total, 128usize))
    if function_refs_error != ok { ret function_refs_error }
    let (strings, strings_error) = mem.alloc[nir.StringConstant](a, sized(8192usize, total, 256usize))
    if strings_error != ok { ret strings_error }
    try nir.init(builder, functions, blocks, instructions, operands, function_refs, strings)
    let (global_data, global_data_error) = mem.alloc[nir.GlobalData](a, sized(256usize, total, 1024usize))
    if global_data_error != ok { ret global_data_error }
    try nir.init_globals(builder, global_data)
    // One per oracle function, as the main builder sizes its own (D308): a table smaller
    // than the function table fails every function past its end as invalid control flow.
    let (signature_entries, signature_entries_error) = mem.alloc[nir.Signature](a, functions.len)
    if signature_entries_error != ok { ret signature_entries_error }
    var type_capacity = signature_type_capacity
    if type_capacity == 0usize { type_capacity = 1usize }
    let (signature_types, signature_types_error) = mem.alloc[check.Type](a, type_capacity)
    if signature_types_error != ok { ret signature_types_error }
    ret nir.init_signatures(signatures, signature_entries, signature_types)
}

// What the body pools are sized from (D314): the largest module when they hold one
// module at a time, the program when they hold it whole.
fn body_bytes_of(loaded: *graph.Graph, per_module: bool) -> usize {
    if per_module { ret loaded.largest_bytes }
    ret loaded.total_bytes
}

fn init_cli_nir(a: *mem.Arena, builder: *nir.Builder, signatures: *nir.Signatures, signature_type_capacity: usize, loaded: *graph.Graph, report: *Sink, body_bytes: usize, scale: usize) -> err {
    // Every module carries its own copy of the generic instances it uses, so the
    // NIR function count scales with instantiation sites, not with declarations.
    //
    // One tier for every program (D302). There were two, a sixteenth of this for any
    // program under 257 functions, which an application cannot opt out of and which an
    // 880-check fixture overran. The root arena is reserved and committed as it is
    // touched (D133), so a pool a small program fills a tenth of costs a tenth; the
    // gate saved address space, not memory.
    // ponytail: fixed pools, sized for the compiler itself; growable pools when a
    // program past half a million instructions exists.
    // The bases divided by `scale` (D325): one for the whole-program builders, four
    // for a lowering worker's, which holds one module's bodies at a time and sits
    // beside seven others, and sixty-four for the executable path's own, which lowers
    // nothing and is replaced by the assembled program.
    let total = loaded.total_bytes
    let function_capacity = sized(16384usize / scale, total, 128usize)
    let block_capacity = sized(65536usize / scale, body_bytes, 16usize)
    let instruction_capacity = sized(262144usize / scale, body_bytes, 4usize)
    let operand_capacity = sized(1048576usize / scale, body_bytes, 4usize)
    let (functions, functions_error) = mem.alloc[nir.Function](a, function_capacity)
    if functions_error != ok { ret functions_error }
    report.build.pools[stats.POOL_NIR_FUNCTIONS] = functions.len
    let (blocks, blocks_error) = mem.alloc[nir.Block](a, block_capacity)
    if blocks_error != ok { ret blocks_error }
    report.build.pools[stats.POOL_NIR_BLOCKS] = blocks.len
    let (instructions, instructions_error) = mem.alloc[nir.Instruction](a, instruction_capacity)
    if instructions_error != ok { ret instructions_error }
    report.build.pools[stats.POOL_NIR_INSTRUCTIONS] = instructions.len
    let (operands, operands_error) = mem.alloc[usize](a, operand_capacity)
    if operands_error != ok { ret operands_error }
    report.build.pools[stats.POOL_NIR_OPERANDS] = operands.len
    // The verifier's scratch (D342): two words per value and eight per block of the
    // largest function the pools hold, committed as it is touched.
    let (verify_scratch, verify_scratch_error) = mem.alloc[usize](a, instruction_capacity * 2usize + block_capacity * 8usize + 16usize)
    if verify_scratch_error != ok { ret verify_scratch_error }
    builder.verify_scratch = verify_scratch
    let (function_refs, function_refs_error) = mem.alloc[nir.FunctionRef](a, sized(8192usize / scale, total, 128usize))
    if function_refs_error != ok { ret function_refs_error }
    report.build.pools[stats.POOL_NIR_REFS] = function_refs.len
    let (strings, strings_error) = mem.alloc[nir.StringConstant](a, sized(8192usize / scale, total, 256usize))
    if strings_error != ok { ret strings_error }
    report.build.pools[stats.POOL_NIR_STRINGS] = strings.len
    try nir.init(builder, functions, blocks, instructions, operands, function_refs, strings)
    let (used_marks, used_marks_error) = mem.alloc[u8](a, function_refs.len)
    if used_marks_error != ok { ret used_marks_error }
    builder.used_marks = used_marks
    let (used_list, used_list_error) = mem.alloc[usize](a, function_refs.len)
    if used_list_error != ok { ret used_list_error }
    builder.used_list = used_list
    let (edge_marks, edge_marks_error) = mem.alloc[u8](a, function_refs.len)
    if edge_marks_error != ok { ret edge_marks_error }
    builder.edge_marks = edge_marks
    // One module's edges at a time, so a fraction of the reference pool.
    let (edge_entries, edge_entries_error) = mem.alloc[lookup.Entry](a, function_refs.len / 2usize + 1024usize)
    if edge_entries_error != ok { ret edge_entries_error }
    try lookup.attach(&builder.edge_index, edge_entries)
    let (ref_entries, ref_entries_error) = mem.alloc[lookup.Entry](a, function_refs.len * 4usize)
    if ref_entries_error != ok { ret ref_entries_error }
    report.build.pools[stats.POOL_NIR_INDEX] = ref_entries.len
    let (string_entries, string_entries_error) = mem.alloc[lookup.Entry](a, strings.len * 4usize)
    if string_entries_error != ok { ret string_entries_error }
    try nir.attach_indexes(builder, ref_entries, string_entries)
    let (global_data, global_data_error) = mem.alloc[nir.GlobalData](a, sized(256usize, total, 1024usize))
    if global_data_error != ok { ret global_data_error }
    report.build.pools[stats.POOL_NIR_GLOBALS] = global_data.len
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
    // `--stats` (D308): the build's measurements, printed after the image is written.
    build: stats.Build,
    // `--time` (D303): a line per phase on stderr, and when the last one ended.
    timing: bool,
    phase_started: usize,
    // The arena's offset when the phase ended, set by the caller before reporting.
    arena_used: usize,
    // Within the codegen phase: nanoseconds in register allocation and in emission.
    regalloc_ns: usize,
    codegen_ns: usize,
    fold_ns: usize,
    // `--path VIRTUAL` (D262): the operand's identity in every span, in place of its
    // basename; a diagnostic in any other module keeps that module's basename.
    operand_source: str,
    operand_path: str,
    // `--absolute-paths` (section 2, D290): the operand's absolute spelling, written as
    // `absolute_path` beside the operand's identity and no other module's.
    absolute_path: str,
    // A generated source map beside the operand (tooling section 8, D264): a diagnostic
    // inside a mapped range is reported at the original span, the generated one related.
    // ponytail: eight mappings per map is the cap; raise it when a generator needs more.
    // A stale or malformed map (section 8, D300): reported as E-TOOL-0001 up front, the
    // analysis still run for its own diagnostics, and the command failing with no artifact.
    map_stale: bool,
    map_source: str,
    map_count: usize,
    map_generated_start: [8]usize,
    map_generated_end: [8]usize,
    map_generated_line: [8]usize,
    map_original_path: [8]str,
    map_original_start: [8]usize,
    map_original_line: [8]usize,
}

// One diagnostic, as the human line `path:line:col: error[CODE]: message` or as the
// record of docs/tooling.md section 3 -- the span from the token, the source as an
// operand named by the file's basename.
fn emit_diagnostic(report: *Sink, path: str, text: str, lines: []const usize, token: lex.Token, has_token: bool, code: str, message: str) -> err {
    // The span is derived from the source only here (D315): the token carries its
    // bytes, and the line, the column and the UTF-16 columns are looked up when reported.
    var at = lex.span_of(text, lines, token)
    if !report.json {
        try write_all(report, path)
        try write_all(report, ":")
        if has_token {
            try write_usize(report, at.line)
            try write_all(report, ":")
            try write_usize(report, at.column)
        } else {
            try write_all(report, "1:1")
        }
        try write_all(report, ": error[")
        try write_all(report, code)
        try write_all(report, "]: ")
        try write_all(report, message)
        ret write_all(report, "\n")
    }
    if !has_token {
        var origin: lex.Span = zero
        origin.line = 1usize
        origin.column = 1usize
        origin.end_line = 1usize
        origin.end_column = 1usize
        origin.column_utf16 = 1usize
        origin.end_column_utf16 = 1usize
        at = origin
    }
    // Inside a source map's range, the original span is primary (D264).
    let mapping = map_index(report, path, at, has_token)
    try write_all(report, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":")
    try write_json_string(report, code)
    try write_all(report, ",\"message\":")
    try write_json_string(report, message)
    try write_all(report, ",\"span\":")
    if mapping < report.map_count {
        var original = at
        original.start = at.start - report.map_generated_start[mapping] + report.map_original_start[mapping]
        original.end = at.end - report.map_generated_start[mapping] + report.map_original_start[mapping]
        original.line = at.line - report.map_generated_line[mapping] + report.map_original_line[mapping]
        original.end_line = at.end_line - report.map_generated_line[mapping] + report.map_original_line[mapping]
        try write_span(report, report.map_original_path[mapping], original, false)
        try write_all(report, ",\"parent\":null,\"related\":[{\"message\":\"in the generated source\",\"span\":")
        try write_span(report, basename(path), at, false)
        try write_all(report, "}],\"fixes\":[]}")
    } else {
        let is_operand = same(path, report.operand_source)
        if report.operand_path.len != 0usize && is_operand {
            try write_span(report, report.operand_path, at, true)
        } else {
            try write_span(report, basename(path), at, is_operand)
        }
        try write_all(report, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
    }
    try write_all(report, "\n")
    report.count += 1usize
    ret ok
}

fn write_span(report: *Sink, identity: str, at: lex.Span, operand: bool) -> err {
    try write_all(report, "{\"source\":{\"root\":\"operand\",\"path\":")
    try write_json_string(report, identity)
    if operand && report.absolute_path.len != 0usize {
        try write_all(report, ",\"absolute_path\":")
        try write_json_string(report, report.absolute_path)
    }
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
    ret write_all(report, "}")
}

// The mapping a token of `path` falls inside, or `map_count` for none.
fn map_index(report: *Sink, path: str, at: lex.Span, has_token: bool) -> usize {
    if !has_token || report.map_count == 0usize || !same(path, report.map_source) { ret report.map_count }
    var mapping = 0usize
    while mapping < report.map_count {
        if at.start >= report.map_generated_start[mapping] && at.end <= report.map_generated_end[mapping] { ret mapping }
        mapping += 1usize
    }
    ret report.map_count
}

// The string after `key` in a JSON line, up to its closing quote; "" when absent.
fn json_str_after(line: str, key: str) -> str {
    var at = 0usize
    while at + key.len <= line.len {
        if same(line[at..at + key.len], key) {
            var end = at + key.len
            while end < line.len && line[end] != 34u8 { end += 1usize }
            ret line[at + key.len..end]
        }
        at += 1usize
    }
    ret ""
}

// Section 8's source map beside the operand, `<file>.map.json`: absent is no map; present,
// its hash must be the operand's bytes or the map is stale -- E-TOOL-0001, and the
// command fails before analysis (D264). ponytail: a key scan over the one document shape
// this compiler's own generator writes, not a JSON reader; e.fmt.json would cost the
// bootstrap decls it has no room for.
fn load_source_map(a: *mem.Arena, report: *Sink, operand: str, text: str) -> err {
    let (map_path, map_path_error) = with_suffix(a, operand, ".map.json")
    if map_path_error != ok { ret map_path_error }
    let (document, load_error) = source.load(a, map_path)
    if load_error != ok { ret ok }
    var malformed = !same(json_str_after(document, "\"schema\":\""), "neper-source-map")
    let (digest, digest_error) = tool.manifest_sha256(a, text)
    if digest_error != ok { ret digest_error }
    let stale = !same(json_str_after(document, "\"generated_sha256\":\""), digest)
    if malformed || stale {
        // Reported now, unmapped analysis after (D300): the caller ends the command.
        report.map_stale = true
        if stale {
            try emit_command_diagnostic(report, "E-TOOL-0001", "the generated source map is stale: its hash is not the operand's")
        } else {
            try emit_command_diagnostic(report, "E-TOOL-0001", "the generated source map is malformed")
        }
        ret ok
    }
    report.map_source = operand
    var at = 0usize
    let generated_key = "\"generated_span\":{"
    while at + generated_key.len <= document.len && report.map_count < 8usize {
        if same(document[at..at + generated_key.len], generated_key) {
            let rest = document[at..document.len]
            let index = report.map_count
            report.map_generated_start[index] = json_usize_after(rest, "\"byte_start\":")
            report.map_generated_end[index] = json_usize_after(rest, "\"byte_end\":")
            report.map_generated_line[index] = json_usize_after(rest, "\"line\":")
            var original_at = 0usize
            let original_key = "\"original_span\":{"
            while original_at + original_key.len <= rest.len && !same(rest[original_at..original_at + original_key.len], original_key) { original_at += 1usize }
            let original = rest[original_at..rest.len]
            report.map_original_path[index] = json_str_after(original, "\"path\":\"")
            report.map_original_start[index] = json_usize_after(original, "\"byte_start\":")
            report.map_original_line[index] = json_usize_after(original, "\"line\":")
            report.map_count += 1usize
            at += generated_key.len
        } else {
            at += 1usize
        }
    }
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

// An executable for `os_name`: the bytes, then mode 0755 when the target is Linux, so
// the file runs where it was written (D291). A Windows host keeps its one bit as is.
fn save_executable(a: *mem.Arena, path: str, bytes: []u8, os_name: str) -> err {
    try save_bytes(a, path, bytes)
    if same(os_name, "linux") { try os.set_mode(a, path, 493u32) }
    ret ok
}

// Published, not written in place (D343, H24): the bytes go to `<path>.tmp` and the
// name is taken by one atomic replace, so no reader -- a concurrent build, the next
// build after a crash -- ever sees a file that is part of one; a write that dies
// leaves its `.tmp`, which nothing reads, and the previous file, which is whole.
fn save_bytes(a: *mem.Arena, path: str, bytes: []u8) -> err {
    let (staged, staged_error) = with_suffix(a, path, ".tmp")
    if staged_error != ok { ret staged_error }
    try write_file(a, staged, bytes)
    ret os.replace(a, staged, path, true, false)
}

fn write_file(a: *mem.Arena, path: str, bytes: []u8) -> err {
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
// Settle's state (D320, D322): every module's interface bytes -- fresh from the
// checker for a parsed module, the artifact's for a stable one -- the modules by
// name, and their declarations by (module, name).
// `fresh`, every module's interface bytes, travels beside it.
type Settle = struct {
    modules: lookup.Index,
    declarations: lookup.Index,
    sections: []em.Section,
    interface_buffer: binary.Buffer,
    triple: str,
    mode: em.BuildMode,
    strings: *em.StringTable,
    scratch: *binary.Buffer,
}

fn settle_init(a: *mem.Arena, s: *Settle, c: *check.Checker, g: *graph.Graph, held: [][]const u8, triple: str, mode: em.BuildMode, strings: *em.StringTable, scratch: *binary.Buffer) -> err {
    // The modules by name (D320): an edge's target was a walk over every module. An
    // index grows by doubling into the region after itself, so its entries are eight
    // times the keys: the regions sum to under twice the last, which is under four.
    let (module_entries, module_entries_error) = mem.alloc[lookup.Entry](a, g.count * 8usize + 256usize)
    if module_entries_error != ok { ret module_entries_error }
    try lookup.attach(&s.modules, module_entries)
    var name_at = 0usize
    while name_at < g.count {
        try lookup.insert(&s.modules, 0usize, 0usize, g.modules[name_at].name, name_at)
        name_at += 1usize
    }
    // The declarations by (module, name) (D320): an edge's target declaration was a
    // scan of the target's interface, per edge. Sized by the resolver's symbols, which
    // cover every parsed module's declarations, plus what the artifacts hold (D322).
    var declaration_total = c.resolver.count + c.function_count + 256usize
    var held_at = 0usize
    while held_at < g.count {
        if held_at < held.len && held[held_at].len != 0usize {
            let (declared, first_declared, declared_end, declared_error) = em.interface_declarations(held[held_at])
            if declared_error != ok { ret declared_error }
            declaration_total += declared
        }
        held_at += 1usize
    }
    let (declaration_entries, declaration_entries_error) = mem.alloc[lookup.Entry](a, declaration_total * 8usize + 256usize)
    if declaration_entries_error != ok { ret declaration_entries_error }
    try lookup.attach(&s.declarations, declaration_entries)
    let (sections, sections_error) = mem.alloc[em.Section](a, 2usize)
    if sections_error != ok { ret sections_error }
    s.sections = sections
    let (interface_storage, interface_storage_error) = mem.alloc[u8](a, 1048576usize)
    if interface_storage_error != ok { ret interface_storage_error }
    try binary.init(&s.interface_buffer, interface_storage)
    s.triple = triple
    s.mode = mode
    s.strings = strings
    s.scratch = scratch
    ret ok
}

// A parsed module's fresh Interface, from the checker, held for the walk.
fn settle_interface(a: *mem.Arena, s: *Settle, fresh: [][]const u8, c: *check.Checker, g: *graph.Graph, module_index: usize) -> err {
    s.interface_buffer.count = 0usize
    try em.write_interface_artifact(c, g, module_index, s.triple, s.mode, s.strings, s.sections, s.scratch, &s.interface_buffer)
    let (interface_copy, interface_copy_error) = mem.alloc[u8](a, s.interface_buffer.count)
    if interface_copy_error != ok { ret interface_copy_error }
    var copy_at = 0usize
    while copy_at < s.interface_buffer.count {
        interface_copy[copy_at] = s.interface_buffer.bytes[copy_at]
        copy_at += 1usize
    }
    fresh[module_index] = interface_copy
    ret ok
}

// A module's interface bytes indexed by declaration name: once, when they are final.
fn settle_index(a: *mem.Arena, s: *Settle, fresh: [][]const u8, module_index: usize) -> err {
    let (count, first, end, open_error) = em.interface_declarations(fresh[module_index])
    if open_error != ok { ret open_error }
    var cursor = first
    var declaration_at = 0usize
    while declaration_at < count {
        let (declaration, next, read_error) = em.declaration_from(fresh[module_index], cursor, end)
        if read_error != ok { ret read_error }
        let (declaration_name, declaration_name_error) = artifact_string(a, fresh[module_index], declaration.name_index)
        if declaration_name_error != ok { ret declaration_name_error }
        try lookup.insert(&s.declarations, module_index, 0usize, declaration_name, cursor)
        cursor = next
        declaration_at += 1usize
    }
    ret ok
}

// Whether every edge an artifact recorded still holds against the target's interface.
fn settle_edges(a: *mem.Arena, s: *Settle, fresh: [][]const u8, c: *check.Checker, g: *graph.Graph, old: []const u8) -> (bool, err) {
    let (edge_count, count_error) = em.artifact_dependency_count(old)
    if count_error != ok { ret (false, count_error) }
    let (deps, strings, open_error) = em.dependencies_open(old)
    if open_error != ok { ret (false, open_error) }
    var edge_at = 0usize
    while edge_at < edge_count {
        let (dependency, dependency_error) = em.dependency_in(old, deps, strings, edge_at)
        if dependency_error != ok { ret (false, dependency_error) }
        let (target_name, target_name_error) = artifact_string_in(old, strings, dependency.module_index)
        if target_name_error != ok { ret (false, target_name_error) }
        let (target_at, found_target) = lookup.find(&s.modules, 0usize, 0usize, target_name)
        if !found_target { ret (false, ok) }
        // A rebuilt target's interface, written and indexed the first time an edge
        // asks (D327): the walk is in dependency order, so its declarations are final.
        if fresh[target_at].len == 0usize {
            let interface_error = settle_interface(a, s, fresh, c, g, target_at)
            if interface_error != ok { ret (false, interface_error) }
            let index_error = settle_index(a, s, fresh, target_at)
            if index_error != ok { ret (false, index_error) }
        }
        let (edge_name, edge_name_error) = artifact_string_in(old, strings, dependency.name_index)
        if edge_name_error != ok { ret (false, edge_name_error) }
        let (cursor, found_declaration) = lookup.find(&s.declarations, target_at, 0usize, edge_name)
        var declaration: em.Declaration = zero
        if found_declaration {
            let (found, next, read_error) = em.declaration_from(fresh[target_at], cursor, fresh[target_at].len)
            if read_error != ok { ret (false, read_error) }
            declaration = found
        }
        let (matches, match_error) = em.dependency_holds(dependency, declaration, found_declaration)
        if match_error != ok { ret (false, match_error) }
        if !matches { ret (false, ok) }
        edge_at += 1usize
    }
    ret (true, ok)
}

// Section 12's edge rule over a directory of artifacts (`emit-em-all --incremental`,
// D205, D214): every module's fresh Interface from the checker, then each module's
// artifact on disk is kept when its source and build mode are unchanged and every edge
// it recorded still matches, and replaced otherwise.
fn settle_early(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, directory: str, triple: str, mode: em.BuildMode, strings: *em.StringTable, scratch: *binary.Buffer, keep: []bool, held: [][]const u8, hot: *HotLoad) -> err {
    if hot.on { ret settle_hot(a, c, g, triple, mode, strings, scratch, keep, held, hot) }
    var s: Settle = zero
    try settle_init(a, &s, c, g, held, triple, mode, strings, scratch)
    let (fresh, fresh_error) = mem.alloc[[]const u8](a, g.count)
    if fresh_error != ok { ret fresh_error }
    var mode_id = 0usize
    if mode == .Release { mode_id = 1usize }
    var module_at = 0usize
    while module_at < g.count {
        keep[module_at] = false
        try settle_interface(a, &s, fresh, c, g, module_at)
        try settle_index(a, &s, fresh, module_at)
        module_at += 1usize
    }
    var no_bytes: []const u8 = zero
    module_at = 0usize
    while module_at < g.count {
        let checkpoint = mem.mark(a)
        held[module_at] = no_bytes
        let (artifact_path, path_error) = compiled_module_path(a, directory, g.modules[module_at].name, triple)
        if path_error != ok { ret path_error }
        let (old, old_error) = load_artifact(a, artifact_path)
        if old_error == ok {
            let (old_hash, old_hash_error) = em.artifact_source_hash(old)
            let (new_hash, new_hash_error) = em.source_text_hash(g.modules[module_at].text)
            let (old_mode, old_mode_error) = em.artifact_mode(old)
            if old_hash_error == ok && new_hash_error == ok && old_hash == new_hash && old_mode_error == ok && old_mode == mode_id {
                let (holds, edges_error) = settle_edges(a, &s, fresh, c, g, old)
                if edges_error != ok { ret edges_error }
                keep[module_at] = holds
            }
        }
        // A kept module's artifact is held for the link (D320), validated once here;
        // a rebuilt module's goes with the checkpoint.
        if keep[module_at] { held[module_at] = old } else { mem.reset(a, checkpoint) }
        module_at += 1usize
    }
    ret ok
}

// The unparsed modules a rebuilt module needs -- itself and what it imports, through
// modules not yet parsed -- parsed, resolved and declared, in dependency order (D322).
// The declarations sweep is reopened for them: signatures are not ready while a module
// is declared, and `finish_declarations` evaluates its constants.
fn declare_late(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, module_index: usize, list: []usize, listed: []bool) -> err {
    var count = 0usize
    if !g.modules[module_index].has_tree {
        list[count] = module_index
        listed[module_index] = true
        count += 1usize
    }
    var queue_at = 0usize
    while queue_at < count {
        let from = list[queue_at]
        let end = g.modules[from].first_import + g.modules[from].import_count
        var import_at = g.modules[from].first_import
        while import_at < end {
            let imported = g.imports[import_at].target
            if !g.modules[imported].has_tree && !listed[imported] {
                list[count] = imported
                listed[imported] = true
                count += 1usize
            }
            import_at += 1usize
        }
        queue_at += 1usize
    }
    if count == 0usize { ret ok }
    try graph.front_modules(a, g, list[0usize..count])
    c.signatures_ready = false
    var order_at = 0usize
    while order_at < g.order_count {
        let ordered = g.order[order_at]
        if listed[ordered] {
            try resolve.module(c.resolver, g, ordered)
            try check.declarations_module(c, c.resolver, g, ordered)
        }
        order_at += 1usize
    }
    var clear_at = 0usize
    while clear_at < count {
        listed[list[clear_at]] = false
        clear_at += 1usize
    }
    ret check.finish_declarations(c)
}

// The edge rule of a hot build (D322), in dependency order, so a module's targets are
// decided and their interfaces final before its edges are read. A stable module is
// kept as it stands; a changed one is rebuilt; an unchanged one whose every edge holds
// is kept, and one with an edge that does not is rebuilt -- parsed and declared only
// now, with whatever it imports that was not, so its fresh Interface can stand for
// the modules that depend on it in turn.
fn settle_hot(a: *mem.Arena, c: *check.Checker, g: *graph.Graph, triple: str, mode: em.BuildMode, strings: *em.StringTable, scratch: *binary.Buffer, keep: []bool, held: [][]const u8, hot: *HotLoad) -> err {
    var s: Settle = zero
    try settle_init(a, &s, c, g, held, triple, mode, strings, scratch)
    let (fresh, fresh_error) = mem.alloc[[]const u8](a, g.count)
    if fresh_error != ok { ret fresh_error }
    var no_bytes: []const u8 = zero
    var stable_at = 0usize
    while stable_at < g.count {
        keep[stable_at] = false
        fresh[stable_at] = no_bytes
        // A stable module's interface is its artifact's.
        if hot.stable[stable_at] { fresh[stable_at] = held[stable_at] }
        stable_at += 1usize
    }
    let (list, list_error) = mem.alloc[usize](a, g.count + 1usize)
    if list_error != ok { ret list_error }
    let (listed, listed_error) = mem.alloc[bool](a, g.count + 1usize)
    if listed_error != ok { ret listed_error }
    var clear_at = 0usize
    while clear_at < g.count {
        listed[clear_at] = false
        clear_at += 1usize
    }
    var order_at = 0usize
    while order_at < g.order_count {
        let module_index = g.order[order_at]
        order_at += 1usize
        if hot.stable[module_index] {
            keep[module_index] = true
            try settle_index(a, &s, fresh, module_index)
            continue
        }
        if hot.unchanged[module_index] {
            let (holds, edges_error) = settle_edges(a, &s, fresh, c, g, held[module_index])
            if edges_error != ok { ret edges_error }
            if holds {
                keep[module_index] = true
                fresh[module_index] = held[module_index]
                try settle_index(a, &s, fresh, module_index)
                continue
            }
            held[module_index] = no_bytes
            try declare_late(a, c, g, module_index, list, listed)
        }
        // Rebuilt: its fresh interface stands for what depends on it, written when an
        // unchanged dependent's edges first ask for it (D327). A cold build, with
        // nothing unchanged, wrote and indexed every module's interface for nobody.
    }
    ret ok
}

fn load_artifact(a: *mem.Arena, path: str) -> ([]const u8, err) {
    let (packed, load_error) = source.load(a, path)
    if load_error != ok {
        var empty: []const u8 = zero
        ret (empty, load_error)
    }
    // The bytes as loaded (D320): they used to be widened to one `usize` each.
    // The checksum is checked here, once; the readers check the layout alone (D213).
    let validation_error = em.validate(packed)
    if validation_error != ok { ret (packed, validation_error) }
    ret (packed, ok)
}

// A view of the artifact's string (D320): the bytes are bytes, so nothing is copied.
fn artifact_string(a: *mem.Arena, bytes: []const u8, index: usize) -> (str, err) {
    let (start, length, bounds_error) = em.string_bounds(bytes, index)
    if bounds_error != ok { ret ("", bounds_error) }
    ret (bytes[start..start + length], ok)
}

// A string of an artifact whose string section is known (D332).
fn artifact_string_in(bytes: []const u8, strings: em.Section, index: usize) -> (str, err) {
    let (start, length, bounds_error) = em.string_bounds_in(bytes, strings, index)
    if bounds_error != ok { ret ("", bounds_error) }
    ret (bytes[start..start + length], ok)
}

fn print_artifact_error_collision(a: *mem.Arena, left_bytes: []const u8, left: em.ErrorValue, right_bytes: []const u8, right: em.ErrorValue) -> err {
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
    // The resource rules (D345): the local, and the line it was acquired or moved at.
    if checker.failure_kind == .ResourceUseAfterMove {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` was moved or never owned (line ")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, "), so it cannot be used here")
    }
    if checker.failure_kind == .ResourceCleanupForgotten {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` acquired at line ")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, " is still owned at this exit: close it, defer its close, or move it out")
    }
    if checker.failure_kind == .ResourceOverwrite {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` still owns what it acquired at line ")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, "; close it before assigning over it")
    }
    if checker.failure_kind == .ResourceUndef {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "` is a resource, which has no undefined value; use `zero`")
    }
    if checker.failure_kind == .ResourceUnchecked {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` was returned beside an err at line ")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, " that has not been tested: test it with `try` or `if e != ok` first")
    }
    if checker.failure_kind == .ResourceDeferredConsumed {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` is consumed by a deferred call registered at line ")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, ", so it cannot be moved or closed again")
    }
    if checker.failure_kind == .ResourceMovedInLoop {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        try write_all(file, "` is consumed inside this loop (line ")
        try write_all(file, checker.failure_detail2)
        ret write_all(file, ") but declared outside it, so the next iteration would use it moved")
    }
    if checker.failure_kind == .ResourcePartialMove {
        try write_all(file, "`")
        try write_all(file, checker.failure_detail)
        ret write_all(file, "` moves a resource out of an aggregate that stays; move the whole or borrow the field")
    }
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
    ret emit_diagnostic(report, path, module_text(g, checker.failure_module), module_lines(g, checker.failure_module), checker.failure_token, checker.failure_has_token, check.diagnostic_code(checker.failure_kind), message_storage[..message.count])
}

// A module's text, and none for an index past the graph (a diagnostic with no token).
fn module_text(g: *graph.Graph, module_index: usize) -> str {
    if module_index < g.count { ret g.modules[module_index].text }
    ret ""
}

fn module_lines(g: *graph.Graph, module_index: usize) -> []usize {
    var none: [1]usize = zero
    if module_index < g.count { ret g.modules[module_index].lines }
    ret none[0usize..0usize]
}

fn print_token_diagnostic(report: *Sink, g: *graph.Graph, module_index: usize, token: lex.Token, code: str, message: str) -> err {
    var path = "<unknown>"
    if module_index < g.count { path = g.modules[module_index].path }
    ret emit_diagnostic(report, path, module_text(g, module_index), module_lines(g, module_index), token, true, code, message)
}

// A syntax error names its position and, where the parser knows why, its reason.
// A keyword in a binding position is the one reason worth spelling out: it reads
// as an ordinary name and the generic "unexpected" wording explains nothing.
// Spec section 3: a soft delimiter still open at a column-0 declaration keyword is
// E-SYNTAX-0012, reported at the opener and naming the keyword that ended it (D275).
fn print_barrier_failure(report: *Sink, path: str, text: str, opener: lex.Token, keyword: lex.Token) -> err {
    var no_lines: [1]usize = zero
    var message_storage: [256]u8 = zero
    var message = capture_sink(message_storage[..])
    try write_all(&message, "`")
    try write_all(&message, text[opener.start..opener.end])
    try write_all(&message, "` opened here is still unclosed at `")
    try write_all(&message, text[keyword.start..keyword.end])
    try write_all(&message, "` on line ")
    try write_usize(&message, lex.line_of(text, no_lines[0usize..0usize], keyword.start))
    ret emit_diagnostic(report, path, text, no_lines[0usize..0usize], opener, true, "E-SYNTAX-0012", message.capture[0usize..message.count])
}

fn print_parse_failure(report: *Sink, path: str, text: str, token: lex.Token, reserved_name: bool, too_deep: bool) -> err {
    var no_lines: [1]usize = zero
    var message_storage: [1024]u8 = zero
    var message = capture_sink(message_storage[..])
    var code = "E-SYNTAX-9999"
    if too_deep {
        try write_all(&message, "nesting deeper than 128 levels of expressions, blocks and operators")
        ret emit_diagnostic(report, path, text, no_lines[0usize..0usize], token, true, code, message_storage[..message.count])
    }
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
    ret emit_diagnostic(report, path, text, no_lines[0usize..0usize], token, true, code, message_storage[..message.count])
}

// Every module is parsed while the graph is loaded, so a syntax error anywhere in
// the program surfaces here with the module that holds it.
fn load_graph(a: *mem.Arena, report: *Sink, loaded: *graph.Graph, path: str, root: str, arch: str, target_os: str) -> err {
    var no_hot: HotLoad = zero
    var no_held: [1][]const u8 = zero
    ret load_graph_in(a, report, loaded, &no_hot, no_held[0usize..0usize], path, root, arch, target_os, "")
}

// A hot build's loader (D322). The one-at-a-time loader parsed every module to find its
// imports and then declared every module so the edge rule could compare; a warm build of
// a two-million-line program spent six seconds there on modules it then kept. Here a
// module whose text hashes as its artifact says, in the artifact's build mode, is
// `unchanged`: its imports come from the artifact's Imports section and it is not
// parsed. Once the graph is complete, a module is `stable` when it is unchanged and
// every edge its artifact recorded names a stable module -- its fresh interface would
// be its artifact's, since the same source declares the same things -- and a stable
// module is kept as it stands. Everything else, and everything it imports, is parsed,
// resolved and declared as before, and the edge rule decides the unchanged among them
// against the interfaces of their targets, fresh or held.
type HotLoad = struct {
    on: bool,
    release: bool,
    triple: str,
    directory: str,
    scratch: *binary.Buffer,
    // Per module, sized to the graph's capacity: whether the source is unchanged
    // since its artifact, and whether the module is stable. The artifacts themselves
    // travel beside it as `held`, which the link reads.
    unchanged: []bool,
    stable: []bool,
}

// A wave's artifacts on worker threads (D324): each worker reads its modules' artifacts
// into an arena of its own, validates them and compares the text's hash and the build
// mode, writing only its own modules' slots. Reading and checksumming a two-million-
// line program's artifacts -- hundreds of megabytes -- was two seconds of a warm build
// on one core. A worker's arena is sized by its texts, eight bytes of artifact per byte
// of text with a margin; a worker that runs out leaves the rest of its modules to the
// main thread, which does them out of the program's arena.
type ArtifactWorker = struct {
    arena: mem.Arena,
    modules: []usize,
    count: usize,
    paths: []str,
    texts: []str,
    held: [][]const u8,
    unchanged: []bool,
    mode_id: usize,
    stopped: bool,
    stopped_at: usize,
}

fn artifact_worker_module(w: *ArtifactWorker, at: usize) -> err {
    let module_index = w.modules[at]
    w.unchanged[module_index] = false
    let (old, old_error) = load_artifact(&w.arena, w.paths[at])
    if old_error == mem.Exhausted { ret old_error }
    if old_error != ok { ret ok }
    let (old_hash, old_hash_error) = em.artifact_source_hash(old)
    let (new_hash, new_hash_error) = em.source_text_hash(w.texts[at])
    let (old_mode, old_mode_error) = em.artifact_mode(old)
    if old_hash_error == ok && new_hash_error == ok && old_hash == new_hash && old_mode_error == ok && old_mode == w.mode_id {
        w.unchanged[module_index] = true
        w.held[module_index] = old
    }
    ret ok
}

fn artifact_worker_entry(w: *ArtifactWorker) {
    var at = 0usize
    while at < w.count {
        let module_error = artifact_worker_module(w, at)
        if module_error != ok {
            w.stopped = true
            w.stopped_at = at
            ret
        }
        at += 1usize
    }
}

fn load_wave_artifacts(a: *mem.Arena, loaded: *graph.Graph, hot: *HotLoad, held: [][]const u8, directory: str, mode_id: usize, wave_start: usize, wave_end: usize, list: []usize) -> err {
    let wave_count = wave_end - wave_start
    if wave_count == 0usize { ret ok }
    var worker_count = wave_count
    let most_workers = graph.worker_cap(loaded, 8usize)
    if worker_count > most_workers { worker_count = most_workers }
    let (workers, workers_error) = mem.alloc[ArtifactWorker](a, worker_count)
    if workers_error != ok { ret workers_error }
    let (paths, paths_error) = mem.alloc[str](a, wave_count)
    if paths_error != ok { ret paths_error }
    let (texts, texts_error) = mem.alloc[str](a, wave_count)
    if texts_error != ok { ret texts_error }
    // Module i of the wave goes to worker i mod count, largest first would be better
    // but the sizes are alike enough; each worker's modules are gathered into a run.
    let (owner, owner_error) = mem.alloc[usize](a, wave_count)
    if owner_error != ok { ret owner_error }
    var loads: [8]usize = zero
    var order_at = 0usize
    while order_at < wave_count {
        var lightest = 0usize
        var worker_at = 1usize
        while worker_at < worker_count {
            if loads[worker_at] < loads[lightest] { lightest = worker_at }
            worker_at += 1usize
        }
        loads[lightest] += loaded.modules[wave_start + order_at].text.len + 4096usize
        owner[order_at] = lightest
        order_at += 1usize
    }
    var filled = 0usize
    var worker_at = 0usize
    while worker_at < worker_count {
        var blank: ArtifactWorker = zero
        workers[worker_at] = blank
        let first = filled
        var bytes = 0usize
        var list_at = 0usize
        while list_at < wave_count {
            if owner[list_at] == worker_at {
                let module_index = wave_start + list_at
                list[filled] = module_index
                let (artifact_path, path_error) = compiled_module_path(a, directory, loaded.modules[module_index].name, hot.triple)
                if path_error != ok { ret path_error }
                paths[filled] = artifact_path
                texts[filled] = loaded.modules[module_index].text
                bytes += loaded.modules[module_index].text.len
                filled += 1usize
            }
            list_at += 1usize
        }
        let (arena, arena_error) = graph.reserved_arena(a)
        if arena_error != ok { ret arena_error }
        workers[worker_at].arena = arena
        workers[worker_at].modules = list[first..filled]
        workers[worker_at].count = filled - first
        workers[worker_at].paths = paths[first..filled]
        workers[worker_at].texts = texts[first..filled]
        workers[worker_at].held = held
        workers[worker_at].unchanged = hot.unchanged
        workers[worker_at].mode_id = mode_id
        worker_at += 1usize
    }
    var threads: [8]os.Thread = zero
    var started: [8]bool = zero
    worker_at = 1usize
    while worker_at < worker_count {
        started[worker_at] = false
        let (thread, spawn_error) = os.thread_create[ArtifactWorker](artifact_worker_entry, &workers[worker_at], 4194304usize)
        if spawn_error == ok {
            threads[worker_at] = thread
            started[worker_at] = true
        }
        worker_at += 1usize
    }
    artifact_worker_entry(&workers[0usize])
    worker_at = 1usize
    while worker_at < worker_count {
        if started[worker_at] {
            try os.thread_join(threads[worker_at])
        } else {
            artifact_worker_entry(&workers[worker_at])
        }
        worker_at += 1usize
    }
    // What a worker left, out of the program's arena.
    worker_at = 0usize
    while worker_at < worker_count {
        loaded.worker_bytes += graph.arena_touched(&workers[worker_at].arena)
        if workers[worker_at].stopped {
            var remaining = workers[worker_at].stopped_at
            while remaining < workers[worker_at].count {
                let module_index = workers[worker_at].modules[remaining]
                hot.unchanged[module_index] = false
                let (old, old_error) = load_artifact(a, workers[worker_at].paths[remaining])
                if old_error == ok {
                    let (old_hash, old_hash_error) = em.artifact_source_hash(old)
                    let (new_hash, new_hash_error) = em.source_text_hash(loaded.modules[module_index].text)
                    let (old_mode, old_mode_error) = em.artifact_mode(old)
                    if old_hash_error == ok && new_hash_error == ok && old_hash == new_hash && old_mode_error == ok && old_mode == mode_id {
                        hot.unchanged[module_index] = true
                        held[module_index] = old
                    }
                }
                remaining += 1usize
            }
        }
        worker_at += 1usize
    }
    ret ok
}

fn load_graph_hot(a: *mem.Arena, loaded: *graph.Graph, hot: *HotLoad, held: [][]const u8, path: str, root: str, arch: str, target_os: str, project_root: str) -> err {
    try graph.begin(a, loaded, path, root, arch, target_os, project_root)
    let (directory, directory_error) = artifact_directory(a, loaded, hot.release)
    if directory_error != ok { ret directory_error }
    hot.directory = directory
    var mode_id = 0usize
    if hot.release { mode_id = 1usize }
    let (list, list_error) = mem.alloc[usize](a, loaded.modules.len)
    if list_error != ok { ret list_error }
    var module_at = 0usize
    while loaded.scanned < loaded.count {
        let wave_start = loaded.scanned
        let wave_end = loaded.count
        try graph.wave_texts(a, loaded, wave_start, wave_end)
        var to_parse = 0usize
        try load_wave_artifacts(a, loaded, hot, held, directory, mode_id, wave_start, wave_end, list)
        module_at = wave_start
        while module_at < wave_end {
            if hot.unchanged[module_at] {
                let old = held[module_at]
                if true {
                    let (import_count, import_count_error) = em.artifact_import_count(old)
                    if import_count_error != ok { ret import_count_error }
                    var import_at = 0usize
                    while import_at < import_count {
                        let (name_index, qualifier_index, import_error) = em.artifact_import_at(old, import_at)
                        if import_error != ok { ret import_error }
                        let (name, name_error) = artifact_string(a, old, name_index)
                        if name_error != ok { ret name_error }
                        let (qualifier, qualifier_error) = artifact_string(a, old, qualifier_index)
                        if qualifier_error != ok { ret qualifier_error }
                        try graph.add_import(loaded, module_at, name, qualifier)
                        import_at += 1usize
                    }
                }
            }
            if !hot.unchanged[module_at] {
                list[to_parse] = module_at
                to_parse += 1usize
            }
            module_at += 1usize
        }
        try graph.front_modules(a, loaded, list[0usize..to_parse])
        try graph.wave_imports(a, loaded, wave_start, wave_end)
    }
    try graph.finish(loaded)
    // Stability, to a fixed point over the artifacts' edges: the import graph has no
    // cycle, so a few rounds settle it.
    let (module_entries, module_entries_error) = mem.alloc[lookup.Entry](a, loaded.count * 8usize + 256usize)
    if module_entries_error != ok { ret module_entries_error }
    var modules: lookup.Index = zero
    try lookup.attach(&modules, module_entries)
    var name_at = 0usize
    while name_at < loaded.count {
        try lookup.insert(&modules, 0usize, 0usize, loaded.modules[name_at].name, name_at)
        hot.stable[name_at] = hot.unchanged[name_at]
        name_at += 1usize
    }
    var settled = false
    while !settled {
        settled = true
        module_at = 0usize
        while module_at < loaded.count {
            if hot.stable[module_at] {
                let old = held[module_at]
                let (edge_count, count_error) = em.artifact_dependency_count(old)
                if count_error != ok { ret count_error }
                let (deps, strings, open_error) = em.dependencies_open(old)
                if open_error != ok { ret open_error }
                var edge_at = 0usize
                while edge_at < edge_count && hot.stable[module_at] {
                    let (dependency, dependency_error) = em.dependency_in(old, deps, strings, edge_at)
                    if dependency_error != ok { ret dependency_error }
                    let (target_name, target_name_error) = artifact_string_in(old, strings, dependency.module_index)
                    if target_name_error != ok { ret target_name_error }
                    let (target_at, found_target) = lookup.find(&modules, 0usize, 0usize, target_name)
                    if !found_target || !hot.stable[target_at] {
                        hot.stable[module_at] = false
                        settled = false
                    }
                    edge_at += 1usize
                }
            }
            module_at += 1usize
        }
    }
    // What the front end must still cover now: every changed module and everything it
    // imports, since declaring one needs its imports declared. An unchanged module
    // that is not stable waits for settle, which parses it only if it must be rebuilt.
    var needed = 0usize
    module_at = 0usize
    while module_at < loaded.count {
        if !hot.unchanged[module_at] {
            list[needed] = module_at
            needed += 1usize
        }
        module_at += 1usize
    }
    var queue_at = 0usize
    while queue_at < needed {
        let module_index = list[queue_at]
        let end = loaded.modules[module_index].first_import + loaded.modules[module_index].import_count
        var import_at = loaded.modules[module_index].first_import
        while import_at < end {
            let imported = loaded.imports[import_at].target
            var listed = false
            var scan = 0usize
            while scan < needed {
                if list[scan] == imported {
                    listed = true
                    break
                }
                scan += 1usize
            }
            if !listed {
                list[needed] = imported
                needed += 1usize
            }
            import_at += 1usize
        }
        queue_at += 1usize
    }
    var unparsed = 0usize
    queue_at = 0usize
    while queue_at < needed {
        if !loaded.modules[list[queue_at]].has_tree {
            list[unparsed] = list[queue_at]
            unparsed += 1usize
        }
        queue_at += 1usize
    }
    ret graph.front_modules(a, loaded, list[0usize..unparsed])
}

fn init_hot_load(a: *mem.Arena, hot: *HotLoad, scratch: *binary.Buffer, loaded: *graph.Graph, args: []str, on: bool, release: bool) -> err {
    hot.on = on
    hot.release = release
    hot.scratch = scratch
    if !on { ret ok }
    let (triple, triple_error) = target_triple(a, args[4usize], args[5usize])
    if triple_error != ok { ret triple_error }
    hot.triple = triple
    let (scratch_storage, scratch_error) = mem.alloc[u8](a, 4194304usize)
    if scratch_error != ok { ret scratch_error }
    try binary.init(scratch, scratch_storage)
    let (unchanged, unchanged_error) = mem.alloc[bool](a, loaded.modules.len)
    if unchanged_error != ok { ret unchanged_error }
    let (stable, stable_error) = mem.alloc[bool](a, loaded.modules.len)
    if stable_error != ok { ret stable_error }
    var at = 0usize
    while at < loaded.modules.len {
        unchanged[at] = false
        stable[at] = false
        at += 1usize
    }
    hot.unchanged = unchanged
    hot.stable = stable
    ret ok
}

// Every module's artifact bytes for the link, empty until the hot loader or settle
// fills them.
fn clear_held(held: [][]const u8) {
    var no_bytes: []const u8 = zero
    var at = 0usize
    while at < held.len {
        held[at] = no_bytes
        at += 1usize
    }
}

// Every module's manifest digests (D323), before the manifest is written: a parsed
// module's from its text and tokens, an unparsed one's from its artifact, which
// carries them since format 7; a module with neither is scanned for them.
fn fill_manifest_digests(a: *mem.Arena, loaded: *graph.Graph, held: [][]const u8) -> err {
    var module_at = 0usize
    while module_at < loaded.count {
        if loaded.modules[module_at].sha256.len == 0usize {
            var carried = false
            if !loaded.modules[module_at].has_tree && module_at < held.len && held[module_at].len != 0usize {
                let (sha, interface_sha, digests_error) = em.artifact_manifest_digests(held[module_at])
                if digests_error != ok { ret digests_error }
                if sha.len == 64usize && interface_sha.len == 64usize {
                    loaded.modules[module_at].sha256 = sha
                    loaded.modules[module_at].interface_sha256 = interface_sha
                    carried = true
                }
            }
            if !carried {
                let (sha, sha_error) = artifact_hash.sha256_hex(a, loaded.modules[module_at].text)
                if sha_error != ok { ret sha_error }
                loaded.modules[module_at].sha256 = sha
                let (interface_sha, interface_error) = tool.manifest_interface_sha256(a, loaded, module_at)
                if interface_error != ok { ret interface_error }
                loaded.modules[module_at].interface_sha256 = interface_sha
            }
        }
        module_at += 1usize
    }
    ret ok
}

fn load_graph_in(a: *mem.Arena, report: *Sink, loaded: *graph.Graph, hot: *HotLoad, held: [][]const u8, path: str, root: str, arch: str, target_os: str, project_root: str) -> err {
    var no_lines: [1]usize = zero
    var load_error = ok
    if hot.on {
        load_error = load_graph_hot(a, loaded, hot, held, path, root, arch, target_os, project_root)
    } else {
        load_error = graph.load(a, loaded, path, root, arch, target_os, project_root)
    }
    if load_error != ok && loaded.has_failure && loaded.failure_module < loaded.count {
        let module = loaded.modules[loaded.failure_module]
        if loaded.failure_barrier {
            try print_barrier_failure(report, module.path, module.text, loaded.failure_token, loaded.failure_keyword)
        } else {
            try print_parse_failure(report, module.path, module.text, loaded.failure_token, loaded.failure_reserved_name, loaded.failure_too_deep)
        }
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
        try emit_diagnostic(report, loaded.modules[loaded.failure_module].path, "", no_lines[0usize..0usize], no_token, false, code, message_storage[..message.count])
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
    ret emit_diagnostic(report, path, module_text(g, resolver.failure_module), module_lines(g, resolver.failure_module), resolver.failure_token, true, resolve_name_code(resolve_error), message_storage[..message.count])
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

// The NIR pools are program-wide (D302): a capacity that fills names the whole program,
// not the function being lowered when it filled, and the message says which pool and
// how large the program is so the limit reads as a limit rather than a fault in `main`.
fn write_capacity_diagnostic(message: *Sink, builder: *nir.Builder, name: str) -> err {
    var pool = "NIR"
    var limit = 0usize
    if builder.instruction_count >= builder.instructions.len {
        pool = "NIR instruction"
        limit = builder.instructions.len
    } else {
        if builder.block_count >= builder.blocks.len {
            pool = "NIR block"
            limit = builder.blocks.len
        } else {
            if builder.operand_count >= builder.operands.len {
                pool = "NIR operand"
                limit = builder.operands.len
            } else {
                if builder.function_count >= builder.functions.len {
                    pool = "NIR function"
                    limit = builder.functions.len
                } else {
                    if builder.function_ref_count >= builder.function_refs.len {
                        pool = "NIR function reference"
                        limit = builder.function_refs.len
                    } else {
                        if builder.string_count >= builder.strings.len {
                            pool = "NIR string"
                            limit = builder.strings.len
                        }
                    }
                }
            }
        }
    }
    try write_all(message, pool)
    try write_all(message, " capacity")
    if limit != 0usize {
        try write_all(message, " (")
        try write_usize(message, limit)
        try write_all(message, ")")
    }
    try write_all(message, " exhausted while lowering `")
    try write_all(message, name)
    try write_all(message, "`: the program so far is ")
    try write_usize(message, builder.function_count)
    try write_all(message, " functions, ")
    try write_usize(message, builder.block_count)
    try write_all(message, " blocks and ")
    try write_usize(message, builder.instruction_count)
    try write_all(message, " instructions; the pools are sized once per program, and a program this large has to be split")
    ret ok
}

fn print_lower_diagnostic(report: *Sink, g: *graph.Graph, checker: *check.Checker, builder: *nir.Builder, lower_error: err) -> err {
    var path = "<unknown>"
    if checker.failure_module < g.count { path = g.modules[checker.failure_module].path }
    var message_storage: [1024]u8 = zero
    var message = capture_sink(message_storage[..])
    if lower_error == nir.Capacity {
        try write_capacity_diagnostic(&message, builder, checker.failure_name)
        ret emit_diagnostic(report, path, module_text(g, checker.failure_module), module_lines(g, checker.failure_module), checker.failure_token, checker.failure_has_token, "E-TYPE-9999", message_storage[..message.count])
    }
    try write_all(&message, "cannot lower `")
    try write_all(&message, checker.failure_name)
    try write_all(&message, "`: ")
    if lower_error == check.Unsupported {
        try write_all(&message, "construct is not implemented in self-hosted lowering")
    } else {
        if lower_error == nir.Unverified {
            // The verifier's refusal (D342): the instruction and operand, for whoever
            // reads the NIR; a compiler bug, never the program's.
            try write_all(&message, "lowering failed: the NIR verifier refused instruction ")
            try write_usize(&message, builder.verify_instruction)
            try write_all(&message, " at operand ")
            try write_usize(&message, builder.verify_operand)
        }
        if lower_error == nir.InvalidControlFlow {
            try write_all(&message, "lowering failed: invalid NIR control flow")
        } else {
            if lower_error == check.InvalidSwitch {
                try write_all(&message, "lowering failed: invalid switch")
            } else {
                if lower_error == check.MissingReturn {
                    try write_all(&message, "lowering failed: missing return")
                } else {
                    if lower_error == check.InvalidType {
                        try write_all(&message, "lowering failed: invalid type")
                    } else {
                        if lower_error == nir.InvalidValue {
                            try write_all(&message, "lowering failed: invalid NIR value")
                        } else {
                            try write_all(&message, "lowering failed")
                            if lower_error == nir.TooLong { try write_all(&message, ": a body over the oracle's cap") }
                            if lower_error == check.Capacity { try write_all(&message, ": the checker's tables are full") }
                            if lower_error == regalloc.Capacity { try write_all(&message, ": the allocator's tables are full") }
                            if lower_error == regalloc.InvalidIR { try write_all(&message, ": the allocator refused the NIR") }
                            if lower_error == regalloc.NoRegisters { try write_all(&message, ": the allocator ran out of registers") }
                            if lower_error == lower.FunctionNotFound { try write_all(&message, ": a function was not found") }
                            if lower_error == codegen_x64.Unsupported { try write_all(&message, ": the selector does not support the instruction") }
                        }
                    }
                }
            }
        }
    }
    ret emit_diagnostic(report, path, module_text(g, checker.failure_module), module_lines(g, checker.failure_module), checker.failure_token, checker.failure_has_token, "E-TYPE-9999", message_storage[..message.count])
}

fn print_codegen_diagnostic(report: *Sink, g: *graph.Graph, function: nir.Function, context: *codegen_x64.FunctionContext, codegen_error: err) -> err {
    var path = "<unknown>"
    if function.module_index < g.count { path = g.modules[function.module_index].path }
    var message_storage: [512]u8 = zero
    var message = capture_sink(message_storage[..])
    try write_all(&message, "cannot select machine code for `")
    try write_all(&message, function.name)
    try write_all(&message, "`")
    // Which table filled, when one did: the selector's own errors are capacities.
    if codegen_error == codegen_x64.Unsupported { try write_all(&message, " (a fixup, relocation or line table is full)") }
    if codegen_error == emit_x64.Capacity { try write_all(&message, " (the machine code buffer is full)") }
    if codegen_error == regalloc.Capacity { try write_all(&message, " (the register allocator's tables are full)") }
    ret emit_diagnostic(report, path, module_text(g, function.module_index), module_lines(g, function.module_index), context.failure_token, true, "E-CODEGEN-9999", message_storage[..message.count])
}

fn write_qualified_error(file: *Sink, module_name: str, error_name: str) -> err {
    try write_all(file, module_name)
    try write_all(file, ".")
    ret write_all(file, error_name)
}

fn print_error_table_diagnostic(report: *Sink, g: *graph.Graph, conflict: *error_table.Conflict, validation_error: err) -> err {
    var no_lines: [1]usize = zero
    var message_storage: [1024]u8 = zero
    var message = capture_sink(message_storage[..])
    var code = "E-LINK-9999"
    if validation_error == error_table.HashZero {
        code = "E-ERROR-9999"
        try write_all(&message, "error `")
        try write_qualified_error(&message, conflict.first_module, conflict.first_name)
        try write_all(&message, "` hashes to reserved value 0; rename it")
    } else {
        try write_all(&message, "error hash collision: `")
        try write_qualified_error(&message, conflict.first_module, conflict.first_name)
        try write_all(&message, "` and `")
        try write_qualified_error(&message, conflict.second_module, conflict.second_name)
        try write_all(&message, "` have the same 32-bit FNV-1a value")
    }
    var origin: lex.Token = zero
    var path = "<unknown>"
    if g.count > 0usize { path = g.modules[0usize].path }
    ret emit_diagnostic(report, path, "", no_lines[0usize..0usize], origin, false, code, message_storage[..message.count])
}

fn select_check_diagnostic(checker: *check.Checker, diagnostic: check.Diagnostic) {
    checker.failure_module = diagnostic.module_index
    checker.failure_kind = diagnostic.kind
    checker.failure_token = diagnostic.token
    checker.failure_has_token = true
    checker.failure_detail = diagnostic.detail
    checker.failure_detail2 = diagnostic.detail2
}

// The per-module front end (D304), each sweep in dependency order. Helpers rather than
// loops in `main`, which is at the bootstrap's local limit.
// Every module's declarations collected in dependency order, then every module's
// names validated against them on worker threads (D328): validation reads the
// symbols and writes only its own locals and failure. A collection failure at some
// module is reported as the one-module-at-a-time sweep reported it -- after the
// modules before it validated -- so the diagnostic is the same one.
fn resolve_per_module(a: *mem.Arena, resolver: *resolve.Resolver, loaded: *graph.Graph) -> err {
    try resolve.begin(resolver, loaded)
    var collected = 0usize
    var collect_error = ok
    while collected < loaded.order_count {
        // An unparsed module (D322) declares nothing the program refers to.
        if loaded.modules[loaded.order[collected]].has_tree {
            collect_error = resolve.collect_module(resolver, loaded, loaded.order[collected])
            if collect_error != ok { break }
        }
        collected += 1usize
    }
    if collect_error != ok {
        var order_at = 0usize
        while order_at < collected {
            if loaded.modules[loaded.order[order_at]].has_tree { try resolve.validate_module(resolver, loaded, loaded.order[order_at]) }
            order_at += 1usize
        }
        ret collect_error
    }
    resolve.fill_index(resolver)
    // The modules to the workers, largest first to the least loaded, each worker's
    // in dependency order.
    let (workers, workers_error) = mem.alloc[ResolveWorker](a, LOWER_WORKERS)
    if workers_error != ok { ret workers_error }
    let (list, list_error) = mem.alloc[usize](a, loaded.order_count + 1usize)
    if list_error != ok { ret list_error }
    let (owner, owner_error) = mem.alloc[usize](a, loaded.count + 1usize)
    if owner_error != ok { ret owner_error }
    var pending = 0usize
    var order_at = 0usize
    while order_at < loaded.order_count {
        owner[loaded.order[order_at]] = LOWER_WORKERS
        if loaded.modules[loaded.order[order_at]].has_tree {
            list[pending] = loaded.order[order_at]
            pending += 1usize
        }
        order_at += 1usize
    }
    var worker_count = pending
    let most_workers = graph.worker_cap(loaded, LOWER_WORKERS)
    if worker_count > most_workers { worker_count = most_workers }
    var sort_at = 0usize
    while sort_at < pending {
        var best = sort_at
        var scan = sort_at + 1usize
        while scan < pending {
            if loaded.modules[list[scan]].text.len > loaded.modules[list[best]].text.len { best = scan }
            scan += 1usize
        }
        let swap = list[sort_at]
        list[sort_at] = list[best]
        list[best] = swap
        sort_at += 1usize
    }
    var loads: [LOWER_WORKERS]usize = zero
    sort_at = 0usize
    while sort_at < pending {
        var lightest = 0usize
        var worker_at = 1usize
        while worker_at < worker_count {
            if loads[worker_at] < loads[lightest] { lightest = worker_at }
            worker_at += 1usize
        }
        loads[lightest] += loaded.modules[list[sort_at]].text.len + 4096usize
        owner[list[sort_at]] = lightest
        sort_at += 1usize
    }
    let (runs, runs_error) = mem.alloc[usize](a, loaded.order_count + 1usize)
    if runs_error != ok { ret runs_error }
    var filled = 0usize
    var worker_at = 0usize
    while worker_at < worker_count {
        var blank: ResolveWorker = zero
        workers[worker_at] = blank
        let first = filled
        order_at = 0usize
        while order_at < loaded.order_count {
            if owner[loaded.order[order_at]] == worker_at {
                runs[filled] = loaded.order[order_at]
                filled += 1usize
            }
            order_at += 1usize
        }
        workers[worker_at].modules = runs[first..filled]
        workers[worker_at].count = filled - first
        workers[worker_at].loaded = loaded
        let (locals, locals_error) = mem.alloc[resolve.Local](a, resolver.locals.len)
        if locals_error != ok { ret locals_error }
        resolve.fork(&workers[worker_at].resolver, resolver, locals)
        worker_at += 1usize
    }
    var threads: [LOWER_WORKERS]os.Thread = zero
    var started: [LOWER_WORKERS]bool = zero
    worker_at = 1usize
    while worker_at < worker_count {
        started[worker_at] = false
        let (thread, spawn_error) = os.thread_create[ResolveWorker](resolve_worker_entry, &workers[worker_at], 16777216usize)
        if spawn_error == ok {
            threads[worker_at] = thread
            started[worker_at] = true
        }
        worker_at += 1usize
    }
    if worker_count != 0usize { resolve_worker_entry(&workers[0usize]) }
    worker_at = 1usize
    while worker_at < worker_count {
        if started[worker_at] {
            try os.thread_join(threads[worker_at])
        } else {
            resolve_worker_entry(&workers[worker_at])
        }
        worker_at += 1usize
    }
    // The failure at the module earliest in dependency order is the build's.
    var lowest_order = loaded.order_count
    var lowest_worker = 0usize
    worker_at = 0usize
    while worker_at < worker_count {
        if workers[worker_at].stopped {
            let failed = workers[worker_at].modules[workers[worker_at].stopped_at]
            var position = 0usize
            while position < loaded.order_count && loaded.order[position] != failed { position += 1usize }
            if position < lowest_order {
                lowest_order = position
                lowest_worker = worker_at
            }
        }
        worker_at += 1usize
    }
    if lowest_order < loaded.order_count {
        let failing = &workers[lowest_worker].resolver
        resolver.failure_module = failing.failure_module
        resolver.failure_token = failing.failure_token
        resolver.failure_has_token = failing.failure_has_token
        resolver.failure_context_token = failing.failure_context_token
        resolver.failure_has_context = failing.failure_has_context
        resolver.failure_name = failing.failure_name
        resolver.failure_owner = failing.failure_owner
        ret workers[lowest_worker].failure
    }
    ret ok
}

type ResolveWorker = struct {
    resolver: resolve.Resolver,
    modules: []usize,
    count: usize,
    loaded: *graph.Graph,
    stopped: bool,
    stopped_at: usize,
    failure: err,
}

fn resolve_worker_entry(w: *ResolveWorker) {
    var at = 0usize
    while at < w.count {
        let validate_error = resolve.validate_module(&w.resolver, w.loaded, w.modules[at])
        if validate_error != ok {
            w.stopped = true
            w.stopped_at = at
            w.failure = validate_error
            ret
        }
        at += 1usize
    }
}

fn declarations_per_module(checker: *check.Checker, resolver: *resolve.Resolver, loaded: *graph.Graph) -> err {
    try check.begin_declarations(checker, resolver, loaded)
    var order_at = 0usize
    while order_at < loaded.order_count {
        if loaded.modules[loaded.order[order_at]].has_tree { try check.declarations_module(checker, resolver, loaded, loaded.order[order_at]) }
        order_at += 1usize
    }
    ret check.finish_declarations(checker)
}

// The body sweep, and the first inlining oracle inside it (D313): a module's bodies
// are checked and its short functions lowered into the oracle on the one parse, in
// graph order, which is the order both oracles walk. An oracle error is a lowering
// diagnostic, printed here where the builder that has its site still is.
fn bodies_per_module(checker: *check.Checker, resolver: *resolve.Resolver, loaded: *graph.Graph, report: *Sink, oracle: *nir.Builder, signatures: *nir.Signatures, bindings: []lower.Binding, entries: []nir.InlineEntry, entry_count: *usize, with_oracle: bool, skip: []bool) -> err {
    var defers: lower.DeferState = zero
    var cursor = 0usize
    if with_oracle { try lower.begin_inline_oracle(checker, oracle, entry_count) }
    var order_at = 0usize
    while order_at < loaded.order_count {
        // A kept module's bodies are not checked (D319): its code is its artifact's, and
        // an instance of one of its generics is checked from its tree when it is made.
        if (loaded.order[order_at] < skip.len && skip[loaded.order[order_at]]) || !loaded.modules[loaded.order[order_at]].has_tree {
            order_at += 1usize
            continue
        }
        try check.bodies_module(checker, resolver, loaded, loaded.order[order_at])
        if with_oracle {
            let oracle_error = lower.oracle_module(checker, loaded, oracle, signatures, bindings, entries, entry_count, loaded.order[order_at], &cursor, &defers)
            if oracle_error != ok {
                try print_lower_diagnostic(report, loaded, checker, oracle, oracle_error)
                try finish_report(report)
                os.exit(1i32)
                ret ok
            }
        }
        order_at += 1usize
    }
    ret check.finish_bodies(checker, resolver, loaded)
}

// The first oracle's builder (D212): no copies in its bodies, `nocheck` like every
// release lowering, and its own record of what it inlined, which is nothing.
fn init_first_oracle(a: *mem.Arena, oracle: *nir.Builder, signatures: *nir.Signatures, checker: *check.Checker, loaded: *graph.Graph) -> err {
    // Built before the bodies are checked (D313), so the signature types are sized by
    // the checker's pools rather than by what the bodies will have added to them.
    try init_oracle_nir(a, oracle, signatures, checker.parameters.len + checker.return_types.len + 1usize, loaded.total_bytes)
    oracle.nocheck = true
    oracle.release = true
    let (inlined, inlined_error) = mem.alloc[nir.InlinedRef](a, sized(8192usize, loaded.total_bytes, 64usize))
    if inlined_error != ok { ret inlined_error }
    oracle.inlined = inlined
    ret ok
}


// What the code emission leaves for the link (D314): the machine code, where each kept
// function starts in it, and the relocations and line rows over it.
type Code = struct {
    machine: emit_x64.Buffer,
    function_offsets: []usize,
    relocations: []codegen_x64.Relocation,
    relocation_count: usize,
    lines: []codegen_x64.LineEntry,
    line_count: usize,
}

// The fold (D130, D157): two functions that compile to the same bytes share one copy,
// keyed by the content hash the `.em` carries and folded in the same order, so an
// executable linked from artifacts and one compiled from source come out identical.
type Fold = struct {
    wanted: bool,
    hashes: []usize,
    offsets: []usize,
    count: usize,
    scratch: binary.Buffer,
}

fn init_fold(a: *mem.Arena, fold: *Fold, function_count: usize) -> err {
    fold.wanted = true
    let (hashes, hashes_error) = mem.alloc[usize](a, function_count + 1usize)
    if hashes_error != ok { ret hashes_error }
    fold.hashes = hashes
    let (offsets, offsets_error) = mem.alloc[usize](a, function_count + 1usize)
    if offsets_error != ok { ret offsets_error }
    fold.offsets = offsets
    let (scratch, scratch_error) = mem.alloc[u8](a, 2097152usize)
    if scratch_error != ok { ret scratch_error }
    try binary.init(&fold.scratch, scratch)
    ret ok
}

// Whether the function at `start..end` of `output` duplicates one already folded, and
// where that one is. A function too large for the scratch is simply not folded: the
// hash cannot be formed, so it is left unique, which is always safe.
fn fold_function(loaded: *graph.Graph, builder: *nir.Builder, output: *emit_x64.Buffer, start: usize, end: usize, relocations: []codegen_x64.Relocation, relocation_count: usize, record_as: usize, fold: *Fold) -> (usize, bool) {
    fold.scratch.count = 0usize
    let hash_input_error = em.write_code_hash_input(loaded, builder, output, start, end, relocations, relocation_count, &fold.scratch)
    if hash_input_error != ok { ret (0usize, false) }
    let (content, content_error) = artifact_hash.xxhash64(fold.scratch.bytes[0usize..fold.scratch.count])
    if content_error != ok { ret (0usize, false) }
    var fold_at = 0usize
    while fold_at < fold.count {
        if fold.hashes[fold_at] == content { ret (fold.offsets[fold_at], true) }
        fold_at += 1usize
    }
    if fold.count < fold.hashes.len {
        fold.hashes[fold.count] = content
        fold.offsets[fold.count] = record_as
        fold.count += 1usize
    }
    ret (0usize, false)
}

// Section 13's per-function pass for the functions from `first` on: live ranges and
// registers, then the machine code into the context's output, with the fold when an
// executable is being made. A selection failure is printed and ends the build here.
fn codegen_functions(a: *mem.Arena, report: *Sink, loaded: *graph.Graph, builder: *nir.Builder, context: *codegen_x64.FunctionContext, first: usize, function_offsets: []usize, emit: bool, fold: *Fold) -> err {
    var function_at = first
    while function_at < builder.function_count {
        if report.timing { report.regalloc_ns = report.regalloc_ns -% nptest_now() }
        let (stack_slots, allocation_error) = regalloc.allocate(builder, function_at, codegen_x64.register_pool_count(), context.ranges, context.allocations, a)
        if report.timing { report.regalloc_ns = report.regalloc_ns +% nptest_now() }
        if allocation_error != ok { ret allocation_error }
        if emit {
            let function_start = context.output.count
            function_offsets[function_at] = function_start
            let relocation_start = *context.relocation_count
            let line_start = *context.line_count
            if report.timing { report.codegen_ns = report.codegen_ns -% nptest_now() }
            let codegen_error = codegen_x64.function(builder, function_at, stack_slots, context)
            if report.timing { report.codegen_ns = report.codegen_ns +% nptest_now() }
            if codegen_error != ok {
                try print_codegen_diagnostic(report, loaded, builder.functions[function_at], context, codegen_error)
                try finish_report(report)
                os.exit(1i32)
                ret ok
            }
            if fold.wanted {
                if report.timing { report.fold_ns = report.fold_ns -% nptest_now() }
                let (folded_at, folded) = fold_function(loaded, builder, context.output, function_start, context.output.count, context.relocations, *context.relocation_count, function_start, fold)
                if folded {
                    context.output.count = function_start
                    *context.relocation_count = relocation_start
                    *context.line_count = line_start
                    function_offsets[function_at] = folded_at
                }
                if report.timing { report.fold_ns = report.fold_ns +% nptest_now() }
            }
        }
        function_at += 1usize
    }
    ret ok
}

fn machine_abi_of(args: []str) -> codegen_x64.Abi {
    if same(args[5usize], "windows") { ret .Windows }
    ret .SystemV
}

// The whole lowered program selected in one pass, for the artifact, object and
// disassembly paths that keep every function (D314 moved the executable path out).
fn emit_whole_program(a: *mem.Arena, report: *Sink, loaded: *graph.Graph, builder: *nir.Builder, emit_machine_code: bool, want_fold: bool, abi: codegen_x64.Abi, code: *Code) -> err {
    let (ranges, ranges_error) = mem.alloc[regalloc.LiveRange](a, builder.instruction_count + 4096usize)
    if ranges_error != ok { ret ranges_error }
    let (allocations, allocations_error) = mem.alloc[regalloc.Allocation](a, builder.instruction_count + 4096usize)
    if allocations_error != ok { ret allocations_error }
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
        // Forty-eight a NIR instruction, not twenty-four (D319): a debug build's trap site
        // carries its path and message in the code, and a program of short arithmetic
        // functions -- the scale benchmark -- filled the buffer at twenty-four.
        machine_capacity = builder.instruction_count * 48usize + builder.function_count * 24usize + names_total + 65536usize
    }
    let (machine_storage, machine_storage_error) = mem.alloc[u8](a, machine_capacity)
    if machine_storage_error != ok { ret machine_storage_error }
    report.build.pools[stats.POOL_MACHINE] = machine_storage.len
    var machine: emit_x64.Buffer = zero
    try emit_x64.init(&machine, machine_storage)
    let (block_offsets, block_offsets_error) = mem.alloc[usize](a, builder.block_count + 1usize)
    if block_offsets_error != ok { ret block_offsets_error }
    let (fixups, fixups_error) = mem.alloc[codegen_x64.Fixup](a, builder.instruction_count + 16usize)
    if fixups_error != ok { ret fixups_error }
    // Two per trap site -- the call and the symbol table (D206) -- and one per call,
    // so the count follows the instructions rather than a constant.
    let (relocations, relocations_error) = mem.alloc[codegen_x64.Relocation](a, builder.instruction_count + 4096usize)
    if relocations_error != ok { ret relocations_error }
    report.build.pools[stats.POOL_RELOCATIONS] = relocations.len
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
    var fold: Fold = zero
    if want_fold { try init_fold(a, &fold, builder.function_count) }
    var relocation_count = 0usize
    report.arena_used = mem.stats(a).used
    try report_phase(report, "codegen setup")
    var codegen_context: codegen_x64.FunctionContext = zero
    codegen_context.allocations = allocations
    codegen_context.arena = a
    codegen_context.has_arena = true
    codegen_context.ranges = ranges
    codegen_context.abi = abi
    codegen_context.block_offsets = block_offsets
    codegen_context.fixups = fixups
    codegen_context.relocations = relocations
    codegen_context.relocation_count = &relocation_count
    codegen_context.output = &machine
    // Section 13's line table (D209): a row per line change, so at most one per instruction.
    let (line_entries, line_entries_error) = mem.alloc[codegen_x64.LineEntry](a, builder.instruction_count + 16usize)
    if line_entries_error != ok { ret line_entries_error }
    report.build.pools[stats.POOL_LINE_ENTRIES] = line_entries.len
    var line_count = 0usize
    codegen_context.lines = line_entries
    codegen_context.line_count = &line_count
    try codegen_functions(a, report, loaded, builder, &codegen_context, 0usize, function_offsets, emit_machine_code, &fold)
    code.machine = machine
    code.function_offsets = function_offsets
    code.relocations = relocations
    code.relocation_count = relocation_count
    code.lines = line_entries
    code.line_count = line_count
    ret ok
}

// The executable path (D314): each module is lowered and selected as it is discovered,
// in the order `lower.reachable_modules` walks, and its bodies discarded before the
// next, so the arena holds one module's NIR rather than the program's. What `main`
// reaches is then found over the relocations -- the same edges the pruner walked over
// instructions, and the same walk `em_link` makes over artifacts -- and the kept
// functions are copied into the image's buffer in order, folded as before.
// The hot build's state (D319): whether it is one, which modules are kept, and where
// the artifacts are, with the writer's tables once they are made.
type HotBuild = struct {
    on: bool,
    keep: []bool,
    directory: str,
    triple: str,
    release: bool,
    strings: em.StringTable,
    sections: []em.Section,
    scratch: binary.Buffer,
    artifact: binary.Buffer,
}

// `.neper/<mode>/em/` under the project root, made when it is missing.
fn artifact_directory(a: *mem.Arena, loaded: *graph.Graph, release: bool) -> (str, err) {
    var mode = "debug"
    if release { mode = "release" }
    let (dot_dir, dot_error) = tool.manifest_join(a, loaded.project.root, ".neper")
    if dot_error != ok { ret ("", dot_error) }
    let (mode_dir, mode_error) = tool.manifest_join(a, dot_dir, mode)
    if mode_error != ok { ret ("", mode_error) }
    let (em_dir, em_error) = tool.manifest_join(a, mode_dir, "em")
    if em_error != ok { ret ("", em_error) }
    let dot_made = ensure_dir(a, dot_dir)
    if dot_made != ok { ret ("", dot_made) }
    let mode_made = ensure_dir(a, mode_dir)
    if mode_made != ok { ret ("", mode_made) }
    let em_made = ensure_dir(a, em_dir)
    if em_made != ok { ret ("", em_made) }
    ret (em_dir, ok)
}

fn init_hot_writer(a: *mem.Arena, hot: *HotBuild, largest_bytes: usize) -> err {
    let (string_values, string_values_error) = mem.alloc[str](a, 32768usize)
    if string_values_error != ok { ret string_values_error }
    let (string_slots, string_slots_error) = mem.alloc[usize](a, 131072usize)
    if string_slots_error != ok { ret string_slots_error }
    try em.init_strings(&hot.strings, string_values, string_slots)
    let (sections, sections_error) = mem.alloc[em.Section](a, 8usize)
    if sections_error != ok { ret sections_error }
    hot.sections = sections
    let (scratch_storage, scratch_storage_error) = mem.alloc[u8](a, 4194304usize)
    if scratch_storage_error != ok { ret scratch_storage_error }
    try binary.init(&hot.scratch, scratch_storage)
    // Sized by the largest module (D325): its artifact is some bytes per byte of text.
    let (artifact_storage, artifact_storage_error) = mem.alloc[u8](a, largest_bytes * 8usize + 4194304usize)
    if artifact_storage_error != ok { ret artifact_storage_error }
    try binary.init(&hot.artifact, artifact_storage)
    ret ok
}

// A module's artifact from the staging buffers, written before its bodies go: the
// artifact's NIR section reads them.
fn write_hot_artifact(a: *mem.Arena, checker: *check.Checker, loaded: *graph.Graph, builder: *nir.Builder, module_index: usize, context: *codegen_x64.FunctionContext, stage_offsets: []usize, hot: *HotBuild, held_all: [][]const u8) -> err {
    var mode: em.BuildMode = .Debug
    if hot.release { mode = .Release }
    hot.artifact.count = 0usize
    try em.write_module(checker, loaded, builder, module_index, hot.triple, mode, context.output, stage_offsets, context.relocations, *context.relocation_count, context.lines, *context.line_count, &hot.strings, hot.sections, &hot.scratch, &hot.artifact)
    let (held, held_error) = mem.alloc[u8](a, hot.artifact.count)
    if held_error != ok { ret held_error }
    try binary.pack(&hot.artifact, held)
    held_all[module_index] = held
    // A cold build holds its artifacts for the link alone (D325); a hot one keeps them.
    if !hot.on { ret ok }
    let (artifact_path, artifact_path_error) = compiled_module_path(a, hot.directory, loaded.modules[module_index].name, hot.triple)
    if artifact_path_error != ok { ret artifact_path_error }
    ret save_bytes(a, artifact_path, held)
}

// The link over every module's artifact, kept and fresh alike, in module order with
// the root first: what `link-em` does with the artifacts named in that order, which
// is the order the source path lays functions out in, so a hot build's image is a
// cold one's byte for byte (D214).
fn link_hot_artifacts(a: *mem.Arena, report: *Sink, loaded: *graph.Graph, builder: *nir.Builder, hot: *HotBuild, held: [][]const u8, code: *Code) -> err {
    let (artifacts, artifacts_error) = mem.alloc[em_link.Artifact](a, loaded.count)
    if artifacts_error != ok { ret artifacts_error }
    var module_index = 0usize
    while module_index < loaded.count {
        if held[module_index].len != 0usize {
            artifacts[module_index].bytes = held[module_index]
        } else {
            let (artifact_path, artifact_path_error) = compiled_module_path(a, hot.directory, loaded.modules[module_index].name, hot.triple)
            if artifact_path_error != ok { ret artifact_path_error }
            let (bytes, load_error) = load_artifact(a, artifact_path)
            if load_error != ok { ret load_error }
            artifacts[module_index].bytes = bytes
        }
        module_index += 1usize
    }
    let (errors_valid, errors_error) = merge_artifact_error_tables(a, artifacts)
    if errors_error != ok { ret errors_error }
    if !errors_valid {
        try finish_report(report)
        os.exit(1i32)
        ret ok
    }
    var program: em_link.Program = zero
    let assemble_error = em_link.assemble(a, artifacts, &program, loaded.jobs)
    if assemble_error == em_link.MissingSymbol && program.missing_symbol.len != 0usize {
        try stderr_text("error: no artifact defines `")
        try stderr_text(program.missing_symbol)
        try stderr_text("`\n")
        os.exit(1i32)
    }
    if assemble_error != ok { ret assemble_error }
    report.build.unreached_functions = program.unreached_functions
    report.build.unreached_bytes = program.unreached_bytes
    loaded.worker_bytes += program.worker_bytes
    // The assembled builder replaces the program's: what the image carries of the
    // build itself -- the arena size (D225) and the mode -- comes across.
    let arena_bytes = builder.arena_bytes
    let release = builder.release
    let nocheck = builder.nocheck
    *builder = program.builder
    builder.arena_bytes = arena_bytes
    builder.release = release
    builder.nocheck = nocheck
    code.machine = program.machine
    code.function_offsets = program.function_offsets
    code.relocations = program.relocations
    code.relocation_count = program.relocation_count
    code.lines = program.lines
    code.line_count = program.line_count
    ret ok
}

// The modules lowered, selected and written as artifacts on worker threads (D325), and
// the image linked from the artifacts, kept and fresh alike: the hot build's link
// (D319), which every executable takes now. Since D326 the same workers check the
// bodies first: a worker's checker is a copy that shares the declaration tables and
// owns a tail of every table a body check or a lowering appends to -- the instances
// its modules make, their types, signatures and generic arguments -- with its locals,
// its caches and its diagnostics; its builder, staging, artifact writer and, in a
// release build, its two inlining oracles are its own. A worker writes only its own
// modules' artifact slots. The modules go to the workers largest first to the least
// loaded, and a worker that cannot go on -- an error, or an arena run dry -- stops
// where it is: the lowest failing module's error is the build's, reported as the
// one-at-a-time loop reported it, and the modules of a dry worker are done again on
// the main thread by a generous worker with the whole-program pools.
// The workers (D325, D326): eight, since twelve on the twelve-core machine this is
// measured on lowered no faster; the arena caps how many are actually made.
const LOWER_WORKERS: usize = 8usize

// The generous worker's slot, past the last thread's: a function, since the bootstrap
// reads a constant before `{` as an aggregate literal.
fn generous_slot() -> usize { ret LOWER_WORKERS }

type LowerWorker = struct {
    arena: mem.Arena,
    checker: check.Checker,
    builder: nir.Builder,
    signatures: nir.Signatures,
    bindings: []lower.Binding,
    context: codegen_x64.FunctionContext,
    stage: emit_x64.Buffer,
    relocation_count: usize,
    line_count: usize,
    stage_offsets: []usize,
    hot: HotBuild,
    report: Sink,
    modules: []usize,
    count: usize,
    loaded: *graph.Graph,
    resolver: *resolve.Resolver,
    held: [][]const u8,
    stopped: bool,
    stopped_at: usize,
    failure: err,
    // Whether the failure was a lowering's (a lowering diagnostic) or the checker's,
    // and which builder it was lowering into: 1 the first oracle, 2 the second, 3 the
    // program's.
    failed_lowering: bool,
    failed_builder: usize,
    // Taken over by the generous worker during the body sweep: its first entries are
    // the generous worker's, not its own partial ones.
    replaced_in_sweep: bool,
    scale: usize,
    // The worker's share of the program's text, which its tails are sized from.
    share: usize,
    forked: bool,
    fork_id: usize,
    // Handed to the generous worker: nothing of this one's is used any more.
    replaced: bool,
    // Which modules' bodies are checked: a kept module's are not in a debug build.
    body_skip: []bool,
    // The inlining oracles of a release build (D326), built by this worker for its
    // own modules: the first over the bodies, the second over the first's entries.
    release: bool,
    oracle: nir.Builder,
    oracle_signatures: nir.Signatures,
    second: nir.Builder,
    second_signatures: nir.Signatures,
    first_entries: []nir.InlineEntry,
    first_count: usize,
    second_entries: []nir.InlineEntry,
    second_count: usize,
    // Where this worker's first entries start in the crew's table of all of them,
    // which is where the second oracle's cursor over them starts.
    first_offset: usize,
    cursor: usize,
    defers: lower.DeferState,
    elapsed_ns: usize,
    body_ns: usize,
    second_ns: usize,
    lower_ns: usize,
    write_ns: usize,
}

// The workers of one build (D326): made before the bodies are checked, kept through
// the second oracle and the lowering, so a module's instances stay with the checker
// that made them.
type Crew = struct {
    on: bool,
    workers: []LowerWorker,
    count: usize,
    generous_made: bool,
    release: bool,
    first_all: []nir.InlineEntry,
    first_all_count: usize,
    second_all: []nir.InlineEntry,
    second_all_count: usize,
}

// The worker's checker forked from the program's (D326): the declaration tables
// copied, with a tail of its own on each one a body check or a lowering appends to,
// sized from the worker's share of the text. The copies are made on the worker's
// thread, out of its arena, so eight of them cost the time of one.
fn fork_checker(a: *mem.Arena, into: *check.Checker, from: *check.Checker, share: usize, largest: usize, fork_id: usize) -> err {
    *into = *from
    into.fork_id = fork_id
    let bytes = share * 2usize + largest
    let (functions, functions_error) = mem.alloc[check.Function](a, from.function_count + sized(1024usize, bytes, 128usize))
    if functions_error != ok { ret functions_error }
    try copy_functions(functions, from.functions[0usize..from.function_count])
    into.functions = functions
    let (generics, generics_error) = mem.alloc[check.FunctionGeneric](a, functions.len)
    if generics_error != ok { ret generics_error }
    try copy_generics(generics, from.function_generics[0usize..from.function_count])
    into.function_generics = generics
    let (parameters, parameters_error) = mem.alloc[check.Parameter](a, from.parameter_count + sized(2048usize, bytes, 64usize))
    if parameters_error != ok { ret parameters_error }
    try copy_parameters(parameters, from.parameters[0usize..from.parameter_count])
    into.parameters = parameters
    let (return_types, return_types_error) = mem.alloc[check.Type](a, from.return_type_count + sized(4096usize, bytes, 64usize))
    if return_types_error != ok { ret return_types_error }
    try copy_types(return_types, from.return_types[0usize..from.return_type_count])
    into.return_types = return_types
    let (comptime_parameters, comptime_parameters_error) = mem.alloc[check.ComptimeParameter](a, from.comptime_parameter_count + sized(256usize, bytes, 1024usize))
    if comptime_parameters_error != ok { ret comptime_parameters_error }
    try copy_comptime_parameters(comptime_parameters, from.comptime_parameters[0usize..from.comptime_parameter_count])
    into.comptime_parameters = comptime_parameters
    let (generic_arguments, generic_arguments_error) = mem.alloc[check.GenericArgument](a, from.generic_argument_count + sized(1024usize, bytes, 256usize))
    if generic_arguments_error != ok { ret generic_arguments_error }
    try copy_generic_arguments(generic_arguments, from.generic_arguments[0usize..from.generic_argument_count])
    into.generic_arguments = generic_arguments
    let (aggregates, aggregates_error) = mem.alloc[check.Aggregate](a, from.aggregate_count + sized(1024usize, bytes, 256usize))
    if aggregates_error != ok { ret aggregates_error }
    try copy_aggregates(aggregates, from.aggregates[0usize..from.aggregate_count])
    into.aggregates = aggregates
    let (fields, fields_error) = mem.alloc[check.AggregateField](a, from.aggregate_field_count + sized(2048usize, bytes, 128usize))
    if fields_error != ok { ret fields_error }
    try copy_fields(fields, from.aggregate_fields[0usize..from.aggregate_field_count])
    into.aggregate_fields = fields
    let (switches, switches_error) = mem.alloc[check.CheckedSwitch](a, from.checked_switch_count + sized(1024usize, bytes, 256usize))
    if switches_error != ok { ret switches_error }
    try copy_switches(switches, from.checked_switches[0usize..from.checked_switch_count])
    into.checked_switches = switches
    let (signatures, signatures_error) = mem.alloc[check.FunctionSignature](a, from.function_signature_count + sized(1024usize, bytes, 64usize))
    if signatures_error != ok { ret signatures_error }
    try copy_signatures(signatures, from.function_signatures[0usize..from.function_signature_count])
    into.function_signatures = signatures
    let (types, types_error) = mem.alloc[check.Type](a, from.type_count + sized(16384usize, bytes, 40usize))
    if types_error != ok { ret types_error }
    try copy_types(types, from.types[0usize..from.type_count])
    into.types = types
    let (locals, locals_error) = mem.alloc[check.Local](a, from.locals.len)
    if locals_error != ok { ret locals_error }
    into.locals = locals
    into.local_count = 0usize
    let (diagnostics, diagnostics_error) = mem.alloc[check.Diagnostic](a, from.diagnostics.len)
    if diagnostics_error != ok { ret diagnostics_error }
    into.diagnostics = diagnostics
    into.diagnostic_count = 0usize
    let (call_cache, call_cache_error) = mem.alloc[check.CallCacheEntry](a, from.call_cache.len)
    if call_cache_error != ok { ret call_cache_error }
    into.call_cache = call_cache
    let (expr_cache, expr_cache_error) = mem.alloc[check.ExprCacheEntry](a, from.expr_cache.len)
    if expr_cache_error != ok { ret expr_cache_error }
    into.expr_cache = expr_cache
    var clear_cache = 0usize
    while clear_cache < call_cache.len {
        var blank_call: check.CallCacheEntry = zero
        call_cache[clear_cache] = blank_call
        clear_cache += 1usize
    }
    clear_cache = 0usize
    while clear_cache < expr_cache.len {
        var blank_expr: check.ExprCacheEntry = zero
        expr_cache[clear_cache] = blank_expr
        clear_cache += 1usize
    }
    into.call_generation = from.call_generation + 1usize
    let (spans, spans_error) = mem.alloc[usize](a, from.writer_spans.len)
    if spans_error != ok { ret spans_error }
    try copy_usizes(spans, from.writer_spans)
    into.writer_spans = spans
    let (body_hashes, body_hashes_error) = mem.alloc[usize](a, from.body_hashes.len)
    if body_hashes_error != ok { ret body_hashes_error }
    try copy_usizes(body_hashes, from.body_hashes)
    into.body_hashes = body_hashes
    into.fork_types = from.type_count
    into.fork_aggregates = from.aggregate_count
    into.fork_signatures = from.function_signature_count
    // The memo (D327): a table per module, made when its bodies are checked, and the
    // types the answers are given as, interned.
    var memo_modules = 1usize
    if from.has_graph { memo_modules = from.graph.count + 1usize }
    let (memo_tables, memo_tables_error) = mem.alloc[[]usize](a, memo_modules)
    if memo_tables_error != ok { ret memo_tables_error }
    var memo_at = 0usize
    while memo_at < memo_tables.len {
        var none: []usize = zero
        memo_tables[memo_at] = none
        memo_at += 1usize
    }
    into.memo_tables = memo_tables
    let (memo_types, memo_types_error) = mem.alloc[check.Type](a, sized(4096usize, bytes, 64usize))
    if memo_types_error != ok { ret memo_types_error }
    into.memo_types = memo_types
    into.memo_type_count = 0usize
    var memo_slot_count = 8192usize
    while memo_slot_count < memo_types.len * 4usize { memo_slot_count = memo_slot_count * 2usize }
    let (memo_slots, memo_slots_error) = mem.alloc[usize](a, memo_slot_count)
    if memo_slots_error != ok { ret memo_slots_error }
    try clear_usizes(memo_slots)
    into.memo_slots = memo_slots
    into.memo_on = true
    into.interp_ready = false
    into.arena = a
    ret ok
}

fn copy_functions(into: []check.Function, from: []check.Function) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

fn copy_generics(into: []check.FunctionGeneric, from: []check.FunctionGeneric) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

fn copy_parameters(into: []check.Parameter, from: []check.Parameter) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

fn copy_types(into: []check.Type, from: []check.Type) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

fn copy_comptime_parameters(into: []check.ComptimeParameter, from: []check.ComptimeParameter) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

fn copy_generic_arguments(into: []check.GenericArgument, from: []check.GenericArgument) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

fn copy_aggregates(into: []check.Aggregate, from: []check.Aggregate) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

fn copy_fields(into: []check.AggregateField, from: []check.AggregateField) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

fn copy_switches(into: []check.CheckedSwitch, from: []check.CheckedSwitch) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

fn copy_signatures(into: []check.FunctionSignature, from: []check.FunctionSignature) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

fn copy_usizes(into: []usize, from: []usize) -> err {
    var at = 0usize
    while at < from.len {
        into[at] = from[at]
        at += 1usize
    }
    ret ok
}

// The worker's builder, staging, artifact writer and oracles, out of the program's
// arena on the main thread; the checker is forked on the worker's own thread.
fn init_lower_worker(a: *mem.Arena, w: *LowerWorker, checker: *check.Checker, loaded: *graph.Graph, resolver: *resolve.Resolver, report: *Sink, abi: codegen_x64.Abi, hot: *HotBuild, held: [][]const u8, bindings: []lower.Binding, program: *nir.Builder, release: bool, body_skip: []bool) -> err {
    w.loaded = loaded
    w.resolver = resolver
    w.held = held
    w.report = *report
    w.report.regalloc_ns = 0usize
    w.report.codegen_ns = 0usize
    w.report.fold_ns = 0usize
    w.release = release
    w.body_skip = body_skip
    w.forked = false
    w.replaced = false
    // Until forked, the checker is the program's: what `declare_globals` reads.
    w.checker = *checker
    // The builder and its staging, sized as the one-at-a-time path sized its own; its
    // signature types by the worker's share (D326), where the program's count was
    // eight times what eight workers between them needed.
    let signature_types = sized(4096usize, w.share * 2usize + loaded.largest_bytes, 64usize)
    try init_cli_nir(a, &w.builder, &w.signatures, signature_types, loaded, &w.report, loaded.largest_bytes, w.scale)
    // What the program's builder carries of the build: the mode, the arena, the oracle.
    w.builder.release = program.release
    w.builder.nocheck = program.nocheck
    w.builder.arena_bytes = program.arena_bytes
    w.builder.has_oracle = program.has_oracle
    w.builder.oracle = program.oracle
    w.builder.oracle_signatures = program.oracle_signatures
    w.builder.inline_entries = program.inline_entries
    w.builder.inline_entry_count = program.inline_entry_count
    let (inlined, inlined_error) = mem.alloc[nir.InlinedRef](a, sized(8192usize, loaded.largest_bytes, 16usize))
    if inlined_error != ok { ret inlined_error }
    w.builder.inlined = inlined
    w.builder.inlined_count = 0usize
    let (inlined_marks, inlined_marks_error) = mem.alloc[u8](a, inlined.len)
    if inlined_marks_error != ok { ret inlined_marks_error }
    w.builder.inlined_marks = inlined_marks
    w.bindings = bindings
    try lower.declare_globals(&w.checker, &w.builder)
    let body_capacity = w.builder.instructions.len
    let (ranges, ranges_error) = mem.alloc[regalloc.LiveRange](a, body_capacity + 4096usize)
    if ranges_error != ok { ret ranges_error }
    let (allocations, allocations_error) = mem.alloc[regalloc.Allocation](a, body_capacity + 4096usize)
    if allocations_error != ok { ret allocations_error }
    let (stage_storage, stage_storage_error) = mem.alloc[u8](a, body_capacity * 24usize + 65536usize)
    if stage_storage_error != ok { ret stage_storage_error }
    try emit_x64.init(&w.stage, stage_storage)
    let (block_offsets, block_offsets_error) = mem.alloc[usize](a, w.builder.blocks.len + 1usize)
    if block_offsets_error != ok { ret block_offsets_error }
    let (fixups, fixups_error) = mem.alloc[codegen_x64.Fixup](a, body_capacity + 16usize)
    if fixups_error != ok { ret fixups_error }
    let (stage_relocations, stage_relocations_error) = mem.alloc[codegen_x64.Relocation](a, body_capacity + 4096usize)
    if stage_relocations_error != ok { ret stage_relocations_error }
    let (stage_lines, stage_lines_error) = mem.alloc[codegen_x64.LineEntry](a, body_capacity + 16usize)
    if stage_lines_error != ok { ret stage_lines_error }
    let (stage_offsets, stage_offsets_error) = mem.alloc[usize](a, w.builder.functions.len + 1usize)
    if stage_offsets_error != ok { ret stage_offsets_error }
    w.stage_offsets = stage_offsets
    w.relocation_count = 0usize
    w.line_count = 0usize
    w.context.allocations = allocations
    w.context.arena = &w.arena
    w.context.has_arena = true
    w.context.ranges = ranges
    w.context.abi = abi
    w.context.block_offsets = block_offsets
    w.context.fixups = fixups
    w.context.relocations = stage_relocations
    w.context.relocation_count = &w.relocation_count
    w.context.output = &w.stage
    w.context.lines = stage_lines
    w.context.line_count = &w.line_count
    w.hot = *hot
    try init_hot_writer(a, &w.hot, loaded.largest_bytes)
    // A release build's oracles (D326), sized from the worker's share as the program's
    // were sized from the program: the first is built with the bodies, the second
    // over the first's entries once every worker has them.
    if release {
        let oracle_bytes = w.share * 2usize + loaded.largest_bytes
        try init_oracle_nir(a, &w.oracle, &w.oracle_signatures, signature_types, oracle_bytes)
        w.oracle.nocheck = true
        w.oracle.release = true
        w.oracle.inline_cap = program.inline_cap
        w.oracle.explain = program.explain
        let (oracle_inlined, oracle_inlined_error) = mem.alloc[nir.InlinedRef](a, sized(1024usize, oracle_bytes, 64usize))
        if oracle_inlined_error != ok { ret oracle_inlined_error }
        w.oracle.inlined = oracle_inlined
        let (first_entries, first_entries_error) = mem.alloc[nir.InlineEntry](a, sized(1024usize, oracle_bytes, 128usize))
        if first_entries_error != ok { ret first_entries_error }
        w.first_entries = first_entries
        w.first_count = 0usize
        try init_oracle_nir(a, &w.second, &w.second_signatures, signature_types, oracle_bytes)
        w.second.nocheck = true
        w.second.release = true
        w.second.inline_cap = program.inline_cap
        w.second.explain = program.explain
        w.second.oracle = &w.oracle
        w.second.oracle_signatures = &w.oracle_signatures
        w.second.has_oracle = true
        let (second_inlined, second_inlined_error) = mem.alloc[nir.InlinedRef](a, sized(1024usize, oracle_bytes, 64usize))
        if second_inlined_error != ok { ret second_inlined_error }
        w.second.inlined = second_inlined
        let (second_entries, second_entries_error) = mem.alloc[nir.InlineEntry](a, sized(1024usize, oracle_bytes, 128usize))
        if second_entries_error != ok { ret second_entries_error }
        w.second_entries = second_entries
        w.second_count = 0usize
    }
    ret ok
}

fn stop_worker(w: *LowerWorker, at: usize, failure: err, lowering: usize) {
    w.stopped = true
    w.stopped_at = at
    w.failure = failure
    w.failed_lowering = lowering != 0usize
    w.failed_builder = lowering
}

fn worker_forked(w: *LowerWorker, a: *mem.Arena, program: *check.Checker) -> err {
    if w.forked {
        w.checker.arena = a
        ret ok
    }
    try fork_checker(a, &w.checker, program, w.share, w.loaded.largest_bytes, w.fork_id)
    w.forked = true
    ret ok
}

fn body_wanted(w: *LowerWorker, module_index: usize) -> bool {
    if !w.loaded.modules[module_index].has_tree { ret false }
    ret !(module_index < w.body_skip.len && w.body_skip[module_index])
}

// The body sweep of the worker's modules (D326), and the first oracle inside it as
// the one-at-a-time sweep had it (D313); then the instances they made. `program` is
// the checker the worker's is forked from, read only.
fn body_worker_run(w: *LowerWorker, a: *mem.Arena, program: *check.Checker, from: usize) {
    let started = nptest_now()
    let fork_error = worker_forked(w, a, program)
    if fork_error != ok {
        stop_worker(w, from, fork_error, 0usize)
        ret
    }
    // The oracle's globals, as the one-at-a-time sweep declared them (D313).
    if w.release && from == 0usize {
        // The entry count is the worker's own: the generous worker begins more than once.
        var first_count = 0usize
        let begin_error = lower.begin_inline_oracle(&w.checker, &w.oracle, &first_count)
        if begin_error != ok {
            stop_worker(w, from, begin_error, 1usize)
            ret
        }
    }
    var at = from
    while at < w.count {
        let module_index = w.modules[at]
        if body_wanted(w, module_index) {
            let check_error = check.bodies_module(&w.checker, w.resolver, w.loaded, module_index)
            if check_error != ok {
                stop_worker(w, at, check_error, 0usize)
                ret
            }
            if w.release {
                let oracle_error = lower.oracle_module(&w.checker, w.loaded, &w.oracle, &w.oracle_signatures, w.bindings, w.first_entries, &w.first_count, module_index, &w.cursor, &w.defers)
                if oracle_error != ok {
                    stop_worker(w, at, oracle_error, 1usize)
                    ret
                }
            }
        }
        at += 1usize
    }
    let finish_error = check.finish_bodies(&w.checker, w.resolver, w.loaded)
    if finish_error != ok { stop_worker(w, w.count, finish_error, 0usize) }
    w.body_ns += nptest_now() - started
}

type BodyStart = struct {
    worker: *LowerWorker,
    program: *check.Checker,
}

fn body_worker_entry(start: *BodyStart) {
    body_worker_run(start.worker, &start.worker.arena, start.program, 0usize)
}

// The second oracle's share of one worker (D326): its modules' first entries lowered
// again, against every worker's first oracle.
fn second_worker_run(w: *LowerWorker, from: usize) {
    let started = nptest_now()
    var defers: lower.DeferState = zero
    if from == 0usize {
        var second_count = 0usize
        let begin_error = lower.begin_inline_oracle(&w.checker, &w.second, &second_count)
        if begin_error != ok {
            stop_worker(w, from, begin_error, 2usize)
            ret
        }
    }
    var at = from
    while at < w.count {
        let module_index = w.modules[at]
        if body_wanted(w, module_index) {
            let oracle_error = lower.oracle_module(&w.checker, w.loaded, &w.second, &w.second_signatures, w.bindings, w.second_entries, &w.second_count, module_index, &w.cursor, &defers)
            if oracle_error != ok {
                stop_worker(w, at, oracle_error, 2usize)
                ret
            }
        }
        at += 1usize
    }
    w.second_ns += nptest_now() - started
}

fn second_worker_entry(w: *LowerWorker) {
    second_worker_run(w, 0usize)
}

// One module through the worker's builder, staging and writer, as the one-at-a-time
// path did it (D314): lowered, selected, its artifact written, its bodies discarded.
fn lower_worker_module(w: *LowerWorker, a: *mem.Arena, module_index: usize) -> err {
    w.checker.arena = a
    w.context.arena = a
    let mark = nir.mark(&w.builder)
    let first = w.builder.function_count
    let lower_started = nptest_now()
    try lower.module(&w.checker, w.loaded, module_index, &w.builder, &w.signatures, w.bindings)
    w.lower_ns += nptest_now() - lower_started
    w.stage.count = 0usize
    w.relocation_count = 0usize
    w.line_count = 0usize
    var no_fold: Fold = zero
    try codegen_functions(a, &w.report, w.loaded, &w.builder, &w.context, first, w.stage_offsets, true, &no_fold)
    let write_started = nptest_now()
    try write_hot_artifact(a, &w.checker, w.loaded, &w.builder, module_index, &w.context, w.stage_offsets, &w.hot, w.held)
    w.write_ns += nptest_now() - write_started
    nir.discard_bodies(&w.builder, mark)
    ret ok
}

fn lower_wanted(w: *LowerWorker, module_index: usize) -> bool {
    ret !(w.hot.on && w.hot.keep[module_index])
}

fn lower_worker_run(w: *LowerWorker, a: *mem.Arena, program: *check.Checker, from: usize) {
    let started = nptest_now()
    let fork_error = worker_forked(w, a, program)
    if fork_error != ok {
        stop_worker(w, from, fork_error, 3usize)
        ret
    }
    var at = from
    while at < w.count {
        if lower_wanted(w, w.modules[at]) {
            let module_error = lower_worker_module(w, a, w.modules[at])
            if module_error != ok {
                stop_worker(w, at, module_error, 3usize)
                break
            }
        }
        at += 1usize
    }
    w.elapsed_ns += nptest_now() - started
}

fn lower_worker_entry(start: *BodyStart) {
    lower_worker_run(start.worker, &start.worker.arena, start.program, 0usize)
}

// Whether a worker stopped for want of room rather than on the program: what the
// generous worker takes over.
fn ran_dry(w: *LowerWorker) -> bool {
    ret w.stopped && (w.failure == mem.Exhausted || w.failure == nir.Capacity || w.failure == check.Capacity || w.failure == lookup.Capacity)
}

// The workers made and given their modules (D326): as many as the arena has room
// for, the modules largest first to the least loaded, each worker's in module order.
// The first worker is set up and measured; each further one is added while what it
// cost fits in what is left with a quarter gibibyte kept back for the link and a
// generous fallback. Its arena holds its checker's fork, the artifacts it holds at
// some bytes per byte of text, and what lowering allocates.
fn crew_begin(a: *mem.Arena, crew: *Crew, report: *Sink, loaded: *graph.Graph, checker: *check.Checker, resolver: *resolve.Resolver, builder: *nir.Builder, bindings: []lower.Binding, abi: codegen_x64.Abi, hot: *HotBuild, held: [][]const u8, release: bool, body_skip: []bool) -> err {
    crew.release = release
    // The finders' indexes filled here, once (D326): the workers read them and never
    // write, since an instance is not indexed.
    check.fill_indexes(checker)
    resolve.fill_index(resolver)
    let (list, list_error) = mem.alloc[usize](a, loaded.count + 1usize)
    if list_error != ok { ret list_error }
    // Which worker each module goes to; one past the last worker is none.
    let (owner, owner_error) = mem.alloc[usize](a, loaded.count + 1usize)
    if owner_error != ok { ret owner_error }
    var pending = 0usize
    var module_at = 0usize
    while module_at < loaded.count {
        owner[module_at] = generous_slot() + 1usize
        let body = loaded.modules[module_at].has_tree && !(module_at < body_skip.len && body_skip[module_at])
        let lowered = loaded.modules[module_at].has_tree && !(hot.on && hot.keep[module_at])
        if body || lowered {
            list[pending] = module_at
            pending += 1usize
        }
        module_at += 1usize
    }
    var worker_count = pending
    let most_workers = graph.worker_cap(loaded, LOWER_WORKERS)
    if worker_count > most_workers { worker_count = most_workers }
    var order_at = 0usize
    while order_at < pending {
        var best = order_at
        var scan = order_at + 1usize
        while scan < pending {
            if loaded.modules[list[scan]].text.len > loaded.modules[list[best]].text.len { best = scan }
            scan += 1usize
        }
        let swap = list[order_at]
        list[order_at] = list[best]
        list[best] = swap
        order_at += 1usize
    }
    // `--perturb` (D331): the modules handed out smallest first and round-robin, so
    // every module's worker and every worker's order differ from the schedule
    // above, and the harness can require the same image of both.
    if loaded.perturb {
        var low = 0usize
        var high = pending
        while low + 1usize < high {
            high = high - 1usize
            let swap = list[low]
            list[low] = list[high]
            list[high] = swap
            low += 1usize
        }
    }
    var loads: [LOWER_WORKERS]usize = zero
    order_at = 0usize
    while order_at < pending {
        var lightest = 0usize
        var worker_at = 1usize
        while worker_at < worker_count {
            if loads[worker_at] < loads[lightest] { lightest = worker_at }
            worker_at += 1usize
        }
        if loaded.perturb { lightest = order_at % worker_count }
        loads[lightest] += loaded.modules[list[order_at]].text.len + 4096usize
        owner[list[order_at]] = lightest
        order_at += 1usize
    }
    var largest_share = 0usize
    var share_at = 0usize
    while share_at < worker_count {
        if loads[share_at] > largest_share { largest_share = loads[share_at] }
        share_at += 1usize
    }
    let (runs, runs_error) = mem.alloc[usize](a, loaded.count + 1usize)
    if runs_error != ok { ret runs_error }
    let (workers, workers_error) = mem.alloc[LowerWorker](a, generous_slot() + 1usize)
    if workers_error != ok { ret workers_error }
    crew.workers = workers
    var worker_at = 0usize
    var worker_cost = 0usize
    var fork_cost = 0usize
    while worker_at < worker_count {
        if worker_at != 0usize {
            let stats_now = mem.stats(a)
            if stats_now.used + worker_cost + 268435456usize > stats_now.capacity {
                var reassign = 0usize
                while reassign < loaded.count {
                    if owner[reassign] >= worker_at { owner[reassign] = owner[reassign] % worker_at }
                    reassign += 1usize
                }
                worker_count = worker_at
                break
            }
        }
        let cost_before = mem.stats(a).used
        var blank: LowerWorker = zero
        workers[worker_at] = blank
        // The worker's arena first (D339): a reservation of its own, committed as it
        // is touched, and every pool of the worker -- its builder, its stages, its
        // bindings, its oracles and its forked checker -- is taken from it, where they
        // were taken from the program's arena, sized from the program and charged whole.
        let (arena, arena_error) = graph.reserved_arena(a)
        if arena_error != ok { ret arena_error }
        workers[worker_at].arena = arena
        let (worker_bindings, bindings_error) = mem.alloc[lower.Binding](&workers[worker_at].arena, bindings.len)
        if bindings_error != ok { ret bindings_error }
        workers[worker_at].scale = 4usize
        workers[worker_at].share = largest_share
        workers[worker_at].fork_id = worker_at + 1usize
        try init_lower_worker(&workers[worker_at].arena, &workers[worker_at], checker, loaded, resolver, report, abi, hot, held, worker_bindings, builder, release, body_skip)
        // The first worker's checker is forked here, on the main thread; the others
        // fork on their own threads.
        if worker_at == 0usize {
            try worker_forked(&workers[0usize], &workers[0usize].arena, checker)
        }
        worker_cost = mem.stats(a).used - cost_before
        worker_at += 1usize
    }
    var filled = 0usize
    worker_at = 0usize
    while worker_at < worker_count {
        let first = filled
        module_at = 0usize
        while module_at < loaded.count {
            if owner[module_at] == worker_at {
                runs[filled] = module_at
                filled += 1usize
            }
            module_at += 1usize
        }
        if loaded.perturb {
            var low = first
            var high = filled
            while low + 1usize < high {
                high = high - 1usize
                let swap = runs[low]
                runs[low] = runs[high]
                runs[high] = swap
                low += 1usize
            }
        }
        workers[worker_at].modules = runs[first..filled]
        workers[worker_at].count = filled - first
        worker_at += 1usize
    }
    crew.count = worker_count
    crew.on = true
    ret ok
}

// The generous worker (D325): whole-program pools, the program's arena, made when a
// worker first runs dry, taking over every module of each such worker.
fn crew_generous(a: *mem.Arena, crew: *Crew, loaded: *graph.Graph, checker: *check.Checker, resolver: *resolve.Resolver, report: *Sink, abi: codegen_x64.Abi, hot: *HotBuild, held: [][]const u8, bindings: []lower.Binding, program: *nir.Builder, body_skip: []bool) -> err {
    if crew.generous_made { ret ok }
    var blank: LowerWorker = zero
    crew.workers[LOWER_WORKERS] = blank
    let (generous_bindings, generous_bindings_error) = mem.alloc[lower.Binding](a, bindings.len)
    if generous_bindings_error != ok { ret generous_bindings_error }
    crew.workers[LOWER_WORKERS].scale = 1usize
    crew.workers[LOWER_WORKERS].share = loaded.total_bytes
    crew.workers[LOWER_WORKERS].fork_id = LOWER_WORKERS + 1usize
    try init_lower_worker(a, &crew.workers[LOWER_WORKERS], checker, loaded, resolver, report, abi, hot, held, generous_bindings, program, crew.release, body_skip)
    try worker_forked(&crew.workers[LOWER_WORKERS], a, checker)
    crew.generous_made = true
    ret ok
}

// The generous worker does one worker's modules over from the bodies (D326): the
// dry worker's tail is abandoned whole, and an instance's number depends only on its
// own module's order, so the redone modules come out the same.
fn crew_replace(a: *mem.Arena, crew: *Crew, worker_at: usize, in_sweep: bool, loaded: *graph.Graph, checker: *check.Checker, resolver: *resolve.Resolver, report: *Sink, abi: codegen_x64.Abi, hot: *HotBuild, held: [][]const u8, bindings: []lower.Binding, program: *nir.Builder, body_skip: []bool) -> err {
    try crew_generous(a, crew, loaded, checker, resolver, report, abi, hot, held, bindings, program, body_skip)
    let dry = &crew.workers[worker_at]
    let generous = &crew.workers[LOWER_WORKERS]
    dry.replaced = true
    dry.replaced_in_sweep = in_sweep
    generous.modules = dry.modules
    generous.count = dry.count
    generous.stopped = false
    generous.cursor = 0usize
    body_worker_run(generous, a, checker, 0usize)
    ret ok
}

fn crew_failure(report: *Sink, loaded: *graph.Graph, w: *LowerWorker) -> err {
    if w.failed_lowering {
        var builder = &w.builder
        if w.failed_builder == 1usize { builder = &w.oracle }
        if w.failed_builder == 2usize { builder = &w.second }
        try print_lower_diagnostic(report, loaded, &w.checker, builder, w.failure)
    } else {
        if w.checker.diagnostic_count == 0usize {
            try print_check_diagnostic(report, loaded, &w.checker, w.failure)
        } else {
            var diagnostic_at = 0usize
            while diagnostic_at < w.checker.diagnostic_count {
                select_check_diagnostic(&w.checker, w.checker.diagnostics[diagnostic_at])
                try print_check_diagnostic(report, loaded, &w.checker, w.failure)
                diagnostic_at += 1usize
            }
        }
    }
    try finish_report(report)
    os.exit(1i32)
    ret ok
}

// The worker that failed on the program at the lowest module, if one did: its error
// is the build's. A worker that ran dry is not a failure.
fn crew_lowest_failure(crew: *Crew, loaded: *graph.Graph) -> (usize, bool) {
    var lowest_failure = loaded.count + 1usize
    var lowest_worker = 0usize
    var worker_at = 0usize
    while worker_at <= crew.count {
        var index = worker_at
        if worker_at == crew.count { index = generous_slot() }
        if (index != generous_slot() || crew.generous_made) && crew.workers[index].stopped && !ran_dry(&crew.workers[index]) {
            var failed = loaded.count
            if crew.workers[index].stopped_at < crew.workers[index].count { failed = crew.workers[index].modules[crew.workers[index].stopped_at] }
            if failed < lowest_failure {
                lowest_failure = failed
                lowest_worker = index
            }
        }
        worker_at += 1usize
    }
    ret (lowest_worker, lowest_failure <= loaded.count)
}

// The bodies of every module checked on the workers (D326), the first oracle with
// them in a release build, then each worker's instances; a worker that ran dry has
// its modules done over by the generous one.
fn crew_bodies(a: *mem.Arena, crew: *Crew, report: *Sink, loaded: *graph.Graph, checker: *check.Checker, resolver: *resolve.Resolver, abi: codegen_x64.Abi, hot: *HotBuild, held: [][]const u8, bindings: []lower.Binding, program: *nir.Builder, body_skip: []bool) -> err {
    var starts: [LOWER_WORKERS]BodyStart = zero
    var threads: [LOWER_WORKERS]os.Thread = zero
    var started: [LOWER_WORKERS]bool = zero
    var worker_at = 1usize
    while worker_at < crew.count {
        starts[worker_at].worker = &crew.workers[worker_at]
        starts[worker_at].program = checker
        started[worker_at] = false
        let (thread, spawn_error) = os.thread_create[BodyStart](body_worker_entry, &starts[worker_at], 16777216usize)
        if spawn_error == ok {
            threads[worker_at] = thread
            started[worker_at] = true
        }
        worker_at += 1usize
    }
    if crew.count != 0usize { body_worker_run(&crew.workers[0usize], &crew.workers[0usize].arena, checker, 0usize) }
    worker_at = 1usize
    while worker_at < crew.count {
        if started[worker_at] {
            try os.thread_join(threads[worker_at])
        } else {
            starts[worker_at].worker = &crew.workers[worker_at]
            starts[worker_at].program = checker
            body_worker_entry(&starts[worker_at])
        }
        worker_at += 1usize
    }
    worker_at = 0usize
    while worker_at < crew.count {
        if ran_dry(&crew.workers[worker_at]) { try crew_replace(a, crew, worker_at, true, loaded, checker, resolver, report, abi, hot, held, bindings, program, body_skip) }
        worker_at += 1usize
    }
    let (failed_worker, failed) = crew_lowest_failure(crew, loaded)
    if failed { ret crew_failure(report, loaded, &crew.workers[failed_worker]) }
    if report.timing {
        var line_storage: [512]u8 = zero
        var line = capture_sink(line_storage[..])
        try write_all(&line, "  workers, ms (bodies):")
        worker_at = 0usize
        while worker_at < crew.count {
            try write_all(&line, " ")
            try write_usize(&line, crew.workers[worker_at].body_ns / 1000000usize)
            worker_at += 1usize
        }
        try write_all(&line, "\n")
        try stderr_text(line_storage[..line.count])
    }
    ret ok
}

// What the driver learns after the bodies -- the program's error table -- given to
// every worker's checker, forked before it was known.
fn crew_errors(crew: *Crew, values: []usize, spellings: []str, count: usize) {
    var worker_at = 0usize
    while worker_at <= generous_slot() {
        if worker_at < crew.count || (worker_at == generous_slot() && crew.generous_made) {
            crew.workers[worker_at].checker.error_values = values
            crew.workers[worker_at].checker.error_spellings = spellings
            crew.workers[worker_at].checker.error_count = count
        }
        worker_at += 1usize
    }
}

// Every worker's entries in one table, worker-major, each worker's in its own module
// order: a cursor from a worker's offset walks its own entries as the sweep recorded
// them, and a search by key finds any worker's.
fn crew_gather(a: *mem.Arena, crew: *Crew, second: bool) -> err {
    var total = 0usize
    var worker_at = 0usize
    while worker_at <= generous_slot() {
        if worker_at < crew.count || (worker_at == generous_slot() && crew.generous_made) {
            if second { total += crew.workers[worker_at].second_count } else { total += crew.workers[worker_at].first_count }
        }
        worker_at += 1usize
    }
    let (all, all_error) = mem.alloc[nir.InlineEntry](a, total + 1usize)
    if all_error != ok { ret all_error }
    var filled = 0usize
    worker_at = 0usize
    while worker_at <= generous_slot() {
        if worker_at < crew.count || (worker_at == generous_slot() && crew.generous_made) {
            let w = &crew.workers[worker_at]
            var count = w.first_count
            if second { count = w.second_count }
            if !second { w.first_offset = filled }
            var at = 0usize
            while at < count {
                if second { all[filled] = w.second_entries[at] } else { all[filled] = w.first_entries[at] }
                filled += 1usize
                at += 1usize
            }
        }
        worker_at += 1usize
    }
    if second {
        crew.second_all = all
        crew.second_all_count = filled
    } else {
        crew.first_all = all
        crew.first_all_count = filled
    }
    ret ok
}

// The second oracle on the workers (D326): each lowers its own modules' first
// entries again against every worker's first oracle, and the program's builders are
// then given every worker's second entries.
fn crew_second_oracle(a: *mem.Arena, crew: *Crew, report: *Sink, loaded: *graph.Graph, checker: *check.Checker, resolver: *resolve.Resolver, abi: codegen_x64.Abi, hot: *HotBuild, held: [][]const u8, bindings: []lower.Binding, program: *nir.Builder, body_skip: []bool) -> err {
    try crew_gather(a, crew, false)
    var worker_at = 0usize
    while worker_at <= generous_slot() {
        if worker_at < crew.count || (worker_at == generous_slot() && crew.generous_made) {
            crew.workers[worker_at].second.inline_entries = crew.first_all
            crew.workers[worker_at].second.inline_entry_count = crew.first_all_count
            crew.workers[worker_at].cursor = crew.workers[worker_at].first_offset
        }
        worker_at += 1usize
    }
    var threads: [LOWER_WORKERS]os.Thread = zero
    var started: [LOWER_WORKERS]bool = zero
    worker_at = 1usize
    while worker_at < crew.count {
        started[worker_at] = false
        if !crew.workers[worker_at].replaced {
            let (thread, spawn_error) = os.thread_create[LowerWorker](second_worker_entry, &crew.workers[worker_at], 16777216usize)
            if spawn_error == ok {
                threads[worker_at] = thread
                started[worker_at] = true
            }
        }
        worker_at += 1usize
    }
    if crew.count != 0usize && !crew.workers[0usize].replaced { second_worker_run(&crew.workers[0usize], 0usize) }
    worker_at = 1usize
    while worker_at < crew.count {
        if started[worker_at] {
            try os.thread_join(threads[worker_at])
        } else {
            if !crew.workers[worker_at].replaced { second_worker_run(&crew.workers[worker_at], 0usize) }
        }
        worker_at += 1usize
    }
    // The generous worker's turn: the modules it took over in the sweep, whose first
    // entries are its own, in the order it made them; and those of any worker that
    // ran dry just now, whose bodies it checks over first and whose own first entries,
    // complete, it walks.
    var generous_cursor = 0usize
    if crew.generous_made { generous_cursor = crew.workers[LOWER_WORKERS].first_offset }
    worker_at = 0usize
    while worker_at < crew.count {
        let dry = ran_dry(&crew.workers[worker_at])
        if crew.workers[worker_at].replaced || dry {
            if dry { try crew_replace(a, crew, worker_at, false, loaded, checker, resolver, report, abi, hot, held, bindings, program, body_skip) }
            let generous = &crew.workers[LOWER_WORKERS]
            generous.modules = crew.workers[worker_at].modules
            generous.count = crew.workers[worker_at].count
            generous.cursor = crew.workers[worker_at].first_offset
            if crew.workers[worker_at].replaced_in_sweep { generous.cursor = generous_cursor }
            generous.second.inline_entries = crew.first_all
            generous.second.inline_entry_count = crew.first_all_count
            second_worker_run(generous, 0usize)
            if crew.workers[worker_at].replaced_in_sweep { generous_cursor = generous.cursor }
        }
        worker_at += 1usize
    }
    let (failed_worker, failed) = crew_lowest_failure(crew, loaded)
    if failed { ret crew_failure(report, loaded, &crew.workers[failed_worker]) }
    try crew_gather(a, crew, true)
    worker_at = 0usize
    while worker_at <= generous_slot() {
        if worker_at < crew.count || (worker_at == generous_slot() && crew.generous_made) {
            crew.workers[worker_at].builder.has_oracle = true
            crew.workers[worker_at].builder.oracle = &crew.workers[worker_at].second
            crew.workers[worker_at].builder.oracle_signatures = &crew.workers[worker_at].second_signatures
            crew.workers[worker_at].builder.inline_entries = crew.second_all
            crew.workers[worker_at].builder.inline_entry_count = crew.second_all_count
        }
        worker_at += 1usize
    }
    if report.timing {
        var line_storage: [512]u8 = zero
        var line = capture_sink(line_storage[..])
        try write_all(&line, "  workers, ms (second oracle):")
        worker_at = 0usize
        while worker_at < crew.count {
            try write_all(&line, " ")
            try write_usize(&line, crew.workers[worker_at].second_ns / 1000000usize)
            worker_at += 1usize
        }
        try write_all(&line, "\n")
        try stderr_text(line_storage[..line.count])
    }
    ret ok
}

// The modules lowered, selected and written on the crew's workers (D325, D326), and
// the image linked from the artifacts.
fn crew_emit(a: *mem.Arena, crew: *Crew, report: *Sink, loaded: *graph.Graph, checker: *check.Checker, resolver: *resolve.Resolver, builder: *nir.Builder, bindings: []lower.Binding, lowered: []bool, abi: codegen_x64.Abi, hot: *HotBuild, held: [][]const u8, code: *Code, body_skip: []bool) -> err {
    var clear_at = 0usize
    while clear_at < loaded.count {
        lowered[clear_at] = false
        clear_at += 1usize
    }
    var starts: [LOWER_WORKERS]BodyStart = zero
    var threads: [LOWER_WORKERS]os.Thread = zero
    var started: [LOWER_WORKERS]bool = zero
    var worker_at = 1usize
    while worker_at < crew.count {
        started[worker_at] = false
        if !crew.workers[worker_at].replaced {
            starts[worker_at].worker = &crew.workers[worker_at]
            starts[worker_at].program = checker
            let (thread, spawn_error) = os.thread_create[BodyStart](lower_worker_entry, &starts[worker_at], 16777216usize)
            if spawn_error == ok {
                threads[worker_at] = thread
                started[worker_at] = true
            }
        }
        worker_at += 1usize
    }
    if crew.count != 0usize && !crew.workers[0usize].replaced { lower_worker_run(&crew.workers[0usize], &crew.workers[0usize].arena, checker, 0usize) }
    worker_at = 1usize
    while worker_at < crew.count {
        if started[worker_at] {
            try os.thread_join(threads[worker_at])
        } else {
            if !crew.workers[worker_at].replaced { lower_worker_run(&crew.workers[worker_at], &crew.workers[worker_at].arena, checker, 0usize) }
        }
        worker_at += 1usize
    }
    let (failed_worker, failed) = crew_lowest_failure(crew, loaded)
    if failed { ret crew_failure(report, loaded, &crew.workers[failed_worker]) }
    // What the workers left: a worker replaced in an earlier phase has every module
    // lowered by the generous one, whose checker has them; one that ran dry now has
    // the rest of its modules lowered there, after their bodies are checked there.
    worker_at = 0usize
    while worker_at < crew.count {
        let dry = ran_dry(&crew.workers[worker_at])
        if crew.workers[worker_at].replaced || dry {
            let generous = &crew.workers[LOWER_WORKERS]
            var from = 0usize
            if dry {
                from = crew.workers[worker_at].stopped_at
                try crew_generous(a, crew, loaded, checker, resolver, report, abi, hot, held, bindings, builder, body_skip)
                generous.builder.has_oracle = crew.workers[worker_at].builder.has_oracle
                generous.builder.oracle = &generous.second
                generous.builder.oracle_signatures = &generous.second_signatures
                generous.builder.inline_entries = crew.second_all
                generous.builder.inline_entry_count = crew.second_all_count
                generous.modules = crew.workers[worker_at].modules
                generous.count = crew.workers[worker_at].count
                generous.stopped = false
                body_worker_run(generous, a, checker, from)
                crew.workers[worker_at].replaced = true
            }
            generous.modules = crew.workers[worker_at].modules
            generous.count = crew.workers[worker_at].count
            generous.stopped = false
            lower_worker_run(generous, a, checker, from)
            if generous.stopped { ret crew_failure(report, loaded, generous) }
        }
        var done = 0usize
        while done < crew.workers[worker_at].count {
            if lower_wanted(&crew.workers[worker_at], crew.workers[worker_at].modules[done]) { lowered[crew.workers[worker_at].modules[done]] = true }
            done += 1usize
        }
        report.regalloc_ns = report.regalloc_ns +% crew.workers[worker_at].report.regalloc_ns
        report.codegen_ns = report.codegen_ns +% crew.workers[worker_at].report.codegen_ns
        builder.instruction_total += crew.workers[worker_at].builder.instruction_total
        if crew.workers[worker_at].builder.instruction_peak > builder.instruction_peak { builder.instruction_peak = crew.workers[worker_at].builder.instruction_peak }
        worker_at += 1usize
    }
    if crew.generous_made {
        report.regalloc_ns = report.regalloc_ns +% crew.workers[LOWER_WORKERS].report.regalloc_ns
        report.codegen_ns = report.codegen_ns +% crew.workers[LOWER_WORKERS].report.codegen_ns
        builder.instruction_total += crew.workers[LOWER_WORKERS].builder.instruction_total
        if crew.workers[LOWER_WORKERS].builder.instruction_peak > builder.instruction_peak { builder.instruction_peak = crew.workers[LOWER_WORKERS].builder.instruction_peak }
    }
    report.arena_used = mem.stats(a).used
    try report_phase(report, "lower and codegen")
    if report.timing {
        try stderr_text("  of which regalloc: ")
        try report_ms(report.regalloc_ns)
        try stderr_text("  of which codegen: ")
        try report_ms(report.codegen_ns)
        try report_count("nir instructions in all", builder.instruction_total)
        try report_count("nir instructions, largest module", builder.instruction_peak)
        // Each worker's wall time (D326): the phase is as long as its slowest worker.
        var workers_storage: [512]u8 = zero
        var workers_line = capture_sink(workers_storage[..])
        try write_all(&workers_line, "  workers, ms (lower/write):")
        worker_at = 0usize
        while worker_at < crew.count {
            try write_all(&workers_line, " ")
            try write_usize(&workers_line, crew.workers[worker_at].elapsed_ns / 1000000usize)
            try write_all(&workers_line, "(")
            try write_usize(&workers_line, crew.workers[worker_at].lower_ns / 1000000usize)
            try write_all(&workers_line, "/")
            try write_usize(&workers_line, crew.workers[worker_at].write_ns / 1000000usize)
            try write_all(&workers_line, ")")
            worker_at += 1usize
        }
        try write_all(&workers_line, "\n")
        try stderr_text(workers_storage[..workers_line.count])
        // Which workers ran dry, and so had their modules done over by the generous one.
        if crew.generous_made {
            var replaced = 0usize
            worker_at = 0usize
            while worker_at < crew.count {
                if crew.workers[worker_at].replaced { replaced += 1usize }
                worker_at += 1usize
            }
            try report_count("workers replaced by the generous one", replaced)
        }
    }
    try link_hot_artifacts(a, report, loaded, builder, hot, held, code)
    report.arena_used = mem.stats(a).used
    try report_phase(report, "link from artifacts")
    // What the crew's arenas committed (D339), for `--stats`.
    var touched_at = 0usize
    while touched_at < crew.count {
        loaded.worker_bytes += graph.arena_touched(&crew.workers[touched_at].arena)
        touched_at += 1usize
    }
    ret ok
}

// The executable path without a crew (D325): the bodies were checked on the main
// thread, so the workers are made now, fork from the finished checker, and lower.
fn emit_per_module(a: *mem.Arena, report: *Sink, loaded: *graph.Graph, checker: *check.Checker, resolver: *resolve.Resolver, builder: *nir.Builder, bindings: []lower.Binding, lowered: []bool, abi: codegen_x64.Abi, hot: *HotBuild, held: [][]const u8, code: *Code) -> err {
    var crew: Crew = zero
    // Every module's bodies are checked already: none is wanted here.
    let (all_skip, all_skip_error) = mem.alloc[bool](a, loaded.count + 1usize)
    if all_skip_error != ok { ret all_skip_error }
    var skip_at = 0usize
    while skip_at < all_skip.len {
        all_skip[skip_at] = true
        skip_at += 1usize
    }
    try crew_begin(a, &crew, report, loaded, checker, resolver, builder, bindings, abi, hot, held, false, all_skip)
    ret crew_emit(a, &crew, report, loaded, checker, resolver, builder, bindings, lowered, abi, hot, held, code, all_skip)
}

// A failure that reaches the top (D344, H10): the arena or a table full, or an
// internal failure, is reported as a diagnostic with a registered code -- as a record
// under `--json`, so the stream still ends in its result -- rather than as the bare
// `error: <name>` line the runtime prints for an escaped error. A resource limit is
// the registry's E-TYPE-9999 and exits 1, as the pools' limit does; anything else is
// an internal failure, E-TOOL-9999, exit 2. Deterministic either way: the same input
// on the same machine ends the same way.
fn main(a: *mem.Arena, args: []str) -> err {
    let result = dispatch(a, args)
    if result == ok { ret ok }
    var code = "E-TOOL-9999"
    var message = "internal compiler failure"
    var status = 2i32
    if result == mem.Exhausted {
        code = "E-TYPE-9999"
        message = "resource limit: the compiler's arena is exhausted; the program is larger than this compiler was built to hold"
        status = 1i32
    }
    if result == nir.Capacity || result == graph.Capacity || result == check.Capacity || result == resolve.Capacity || result == lookup.Capacity || result == em.Capacity || result == regalloc.Capacity {
        code = "E-TYPE-9999"
        message = "resource limit: a compiler table is full; the program is larger than this compiler was built to hold"
        status = 1i32
    }
    var json = false
    var at = 1usize
    while at < args.len {
        if same(args[at], "--json") { json = true }
        at += 1usize
    }
    if !json {
        var human = stderr_sink()
        try emit_command_diagnostic(&human, code, message)
        ret result
    }
    var report = json_sink()
    try emit_command_diagnostic(&report, code, message)
    try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":")
    if status == 2i32 { try write_all(&report, "2") } else { try write_all(&report, "1") }
    try write_all(&report, ",\"data\":{\"diagnostics\":1}}\n")
    os.exit(status)
    ret ok
}

fn dispatch(a: *mem.Arena, args: []str) -> err {
    var report = stderr_sink()
    // Spec section 2's spellings -- `neper build FILE`, `neper check FILE`, ... -- are
    // rewritten into the positional forms below and dispatched again (D276).
    let short_result = dispatch_short_form(a, args)
    if short_result != NotShortForm { ret short_result }
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
        let assemble_error = em_link.assemble(a, artifacts, &program, 0usize)
        if assemble_error == em_link.MissingSymbol && program.missing_symbol.len != 0usize {
            try stderr_text("error: no artifact defines `")
            try stderr_text(program.missing_symbol)
            try stderr_text("`\n")
            os.exit(1i32)
        }
        if assemble_error != ok { ret assemble_error }
        let (target_index, target_error) = em.artifact_target_index(artifacts[0usize].bytes)
        if target_error != ok { ret target_error }
        let (is_windows, windows_error) = em.string_matches(artifacts[0usize].bytes, target_index, "x64-windows")
        if windows_error != ok { ret windows_error }
        let (is_linux, linux_error) = em.string_matches(artifacts[0usize].bytes, target_index, "x64-linux")
        if linux_error != ok { ret linux_error }
        if !is_windows && !is_linux { ret em_link.TargetMismatch }
        // The symbol and line table goes after the code before the image is sized (D206, D209).
        try codegen_x64.append_symbol_table(&program.builder, &program.machine, program.function_offsets, program.relocations, program.relocation_count, program.lines, program.line_count)
        let (executable_storage, executable_storage_error) = mem.alloc[u8](a, program.machine.count + 65536usize)
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
        if is_linux { try os.set_mode(a, args[2usize], 493u32) }
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
        var listings: project.Listings = zero
        let (selected, selection_error) = project.select_source(a, &listings, args[2usize], args[3usize], args[4usize], args[5usize], args[6usize])
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
        try init_cli_resolver(a, &resolver, &loaded, &report)
        try resolve.collect(&resolver, &loaded)
        try io.print("module resolve ok\n")
        ret ok
    }
    // `check-file PATH ROOT ARCH OS [--json]`: with `--json`, the stream of docs/tooling.md
    // -- header, a diagnostic record each, the result -- on stdout (D228).
    if args.len >= 6usize && same(args[1usize], "check-file") && check_flags(a, &report, args) {
        if report.json {
            try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"check\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
        }
        var loaded: graph.Graph = zero
        try init_cli_graph(a, &loaded)
        let load_error = load_graph(a, &report, &loaded, args[2usize], args[3usize], args[4usize], args[5usize])
        if load_error == ok && loaded.count != 0usize { try load_source_map(a, &report, args[2usize], loaded.modules[0usize].text) }
        if load_error != ok {
            // Not a diagnostic of the source but of the command: the operand itself.
            if !report.json { ret load_error }
            try emit_command_diagnostic(&report, "E-CLI-9999", "the operand cannot be read as a module")
            try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"diagnostics\":1}}\n")
            os.exit(2i32)
            ret ok
        }
        var resolver: resolve.Resolver = zero
        try init_cli_resolver(a, &resolver, &loaded, &report)
        let resolve_error = resolve.collect(&resolver, &loaded)
        if resolve_error != ok {
            try print_resolve_diagnostic(&report, &loaded, &resolver, resolve_error)
            try finish_report(&report)
            os.exit(1i32)
            ret ok
        }
        var checker: check.Checker = zero
        try init_cli_checker(a, &checker, &loaded, &report)
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
            try print_error_table_diagnostic(&report, &loaded, &error_conflict, error_declaration_error)
            try finish_report(&report)
            os.exit(1i32)
            ret ok
        }
        if report.json { try finish_report(&report) }
        // A stale map failed the command however clean the module was (D300).
        if report.map_stale { os.exit(1i32) }
        if !report.json { try io.print("module check ok\n") }
        ret ok
    }
    // `index-file PATH ROOT ARCH OS --json` (D232): the operand module's symbol records.
    if (args.len == 7usize || (args.len == 8usize && same(args[7usize], "--absolute-paths"))) && same(args[1usize], "index-file") && same(args[6usize], "--json") { ret index_command(a, args) }
    // `... --json --path REL` (D298): the operand's identity under its project's src.
    if args.len == 9usize && same(args[1usize], "index-file") && same(args[6usize], "--json") && same(args[7usize], "--path") { ret index_command(a, args) }
    // `index-project DIR ROOT ARCH OS WORKDIR --json` (D298): every module under DIR/src
    // and DIR/lib, one stream.
    if args.len == 8usize && same(args[1usize], "index-project") && same(args[7usize], "--json") { ret index_project_command(a, args) }
    // `fmt-file PATH [--json]` (D234): the operand's canonical layout as one `formatted` record.
    // `-` reads stdin under a `--path` identity, on every form (D289).
    let fmt_args = fmt_form(args)
    if fmt_args.len == 5usize && same(fmt_args[1usize], "fmt-file") && same(fmt_args[3usize], "--check") && same(fmt_args[4usize], "--json") { ret fmt_check_command(a, args) }
    if fmt_args.len == 4usize && same(fmt_args[1usize], "fmt-file") && same(fmt_args[3usize], "--json") { ret fmt_command(a, args) }
    if fmt_args.len == 3usize && same(fmt_args[1usize], "fmt-file") { ret fmt_plain_command(a, args) }
    // `fmt-file PATH --write` (D295): the canonical text back into the file, when it differs.
    if fmt_args.len == 4usize && same(fmt_args[1usize], "fmt-file") && same(fmt_args[3usize], "--write") { ret fmt_write_command(a, args, args[2usize]) }
    // `fmt-project DIR --write|--check` (D295): every `.e` under DIR/src and DIR/lib.
    if args.len == 4usize && same(args[1usize], "fmt-project") && (same(args[3usize], "--write") || same(args[3usize], "--check")) { ret fmt_project_command(a, args) }
    // `check-project DIR TOOLCHAIN_ROOT ARCH OS WORKDIR --json` (D262): every module under
    // DIR/src, one stream.
    if args.len == 8usize && same(args[1usize], "check-project") && same(args[7usize], "--json") { ret check_project_command(a, args) }
    if args.len == 7usize && same(args[1usize], "build-manifest-file") && same(args[6usize], "--json") { ret manifest_command(a, args) }
    if args.len == 8usize && same(args[1usize], "test-file") && same(args[7usize], "--json") { ret test_command(a, args) }
    if args.len == 9usize && same(args[1usize], "test-file") && same(args[8usize], "--json") { ret test_command(a, args) }
    // `... --json --path REL` (D263): the operand's identity under its project's src.
    if args.len == 10usize && same(args[1usize], "test-file") && same(args[7usize], "--json") && same(args[8usize], "--path") { ret test_command(a, args) }
    if args.len == 11usize && same(args[1usize], "test-file") && same(args[8usize], "--json") && same(args[9usize], "--path") { ret test_command(a, args) }
    // `test-project DIR TOOLCHAIN_ROOT ARCH OS WORKDIR [TIMEOUT_MS] --json` (D263): every
    // module under DIR/src, one stream.
    if args.len == 8usize && same(args[1usize], "test-project") && same(args[7usize], "--json") { ret test_project_command(a, args) }
    if args.len == 9usize && same(args[1usize], "test-project") && same(args[8usize], "--json") { ret test_project_command(a, args) }
    let writes_object = args.len == 7usize && same(args[1usize], "emit-object")
    // `emit-executable ... --release`: section 11's release build, every debug-only
    // check left out and the release results in their place (D204), and the inliner
    // on (D211); `emit-em-all` takes it too, and `--incremental` with it in any order.
    let trailing_flags = args.len >= 8usize && (args.len <= 16usize || has_dashdash(args)) && flags_known(args)
    let release_build = trailing_flags && (same(args[1usize], "emit-executable") || same(args[1usize], "emit-em-all") || same(args[1usize], "run")) && has_flag(args, "--release")
    // `run PATH ROOT ARCH OS OUTPUT [--release] [--arena SIZE] --json` (D231): a build, then
    // the program's whole output as one `run` record before the result.
    let running = trailing_flags && same(args[1usize], "run") && has_flag(args, "--json")
    let writes_executable = ((args.len == 7usize || trailing_flags) && same(args[1usize], "emit-executable")) || running
    // A hot build (D319): the executable from artifacts under `.neper/<mode>/em/`, a
    // module's kept when its source and every interface it depends on are unchanged.
    let hot_build = writes_executable && trailing_flags && has_flag(args, "--incremental")
    let writes_em = args.len == 7usize && same(args[1usize], "emit-em")
    // `emit-em-all ... --incremental`: section 12's edge rule decides which of the
    // artifacts already in the directory are kept and which are replaced (D205).
    let incremental_build = trailing_flags && same(args[1usize], "emit-em-all") && has_flag(args, "--incremental")
    let writes_all_em = (args.len == 7usize || trailing_flags) && same(args[1usize], "emit-em-all")
    // `dis-file PATH ROOT ARCH OS --json` (D233): the codegen pipeline, then per-function bytes.
    let disassemble = args.len == 7usize && same(args[1usize], "dis-file") && same(args[6usize], "--json")
    if (args.len == 6usize && (same(args[1usize], "nir-file") || same(args[1usize], "codegen-file") || same(args[1usize], "object-file"))) || writes_object || writes_executable || writes_em || writes_all_em || disassemble {
        let emit_object = same(args[1usize], "object-file") || writes_object
        let emit_machine_code = same(args[1usize], "codegen-file") || emit_object || writes_executable || writes_em || writes_all_em || disassemble
        // `emit-executable ... --json` (D230): section 7's build stream, diagnostics as
        // records and the result naming the executable.
        if writes_executable && has_flag(args, "--json") {
            report.json = true
            report.file = os.stdout()
            if running {
                try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"run\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
            } else {
                try write_all(&report, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":\"build\",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":2}\n")
            }
        }
        var loaded: graph.Graph = zero
        try init_cli_graph(a, &loaded)
        if trailing_flags {
            loaded.jobs = jobs_flag(args)
            loaded.perturb = has_flag(args, "--perturb")
        }
        report.timing = trailing_flags && has_flag(args, "--time")
        report.build.full = trailing_flags && has_flag(args, "--stats-full")
        report.build.on = report.build.full || (trailing_flags && has_flag(args, "--stats"))
        report.build.release = release_build
        report.build.arch = args[4usize]
        report.build.target_os = args[5usize]
        report.phase_started = nptest_now()
        report.build.started = report.phase_started
        // A hot build's loader (D322): the artifacts decide what is parsed. Set up in a
        // helper: `main` is at the bootstrap's cap of locals.
        var hot_load: HotLoad = zero
        var hot_scratch: binary.Buffer = zero
        try init_hot_load(a, &hot_load, &hot_scratch, &loaded, args, hot_build, release_build)
        let (held_all, held_all_error) = mem.alloc[[]const u8](a, loaded.modules.len)
        if held_all_error != ok { ret held_all_error }
        clear_held(held_all)
        let load_error = load_graph_in(a, &report, &loaded, &hot_load, held_all, args[2usize], args[3usize], args[4usize], args[5usize], project_flag(args))
        report.arena_used = mem.stats(a).used
        try report_phase(&report, "load and parse")
        if load_error == ok && loaded.count != 0usize { try load_source_map(a, &report, args[2usize], loaded.modules[0usize].text) }
        if load_error != ok {
            if disassemble {
                var envelope = json_sink()
                ret unreadable_operand(&envelope, "dis", "{\"functions\":0}")
            }
            if !report.json { ret load_error }
            try emit_command_diagnostic(&report, "E-CLI-9999", "the operand cannot be read as a module")
            try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"diagnostics\":1}}\n")
            os.exit(2i32)
            ret ok
        }
        var resolver: resolve.Resolver = zero
        try init_cli_resolver(a, &resolver, &loaded, &report)
        // The front end runs per module in dependency order (D304), each module parsed
        // once per sweep; the incremental artifact build keeps the whole-program passes,
        // whose `keep` mask it decides between declarations and bodies.
        var resolve_error = ok
        if !(writes_all_em && incremental_build) && loaded.order_count == loaded.count {
            resolve_error = resolve_per_module(a, &resolver, &loaded)
        } else {
            resolve_error = resolve.collect(&resolver, &loaded)
        }
        report.arena_used = mem.stats(a).used
        try report_phase(&report, "resolve")
        if resolve_error != ok {
            try print_resolve_diagnostic(&report, &loaded, &resolver, resolve_error)
            try finish_report(&report)
            os.exit(1i32)
            ret ok
        }
        var checker: check.Checker = zero
        try init_cli_checker(a, &checker, &loaded, &report)
        checker.arena = a
        // The declarations first; then, incrementally, the edge rule decides the kept
        // modules from the Interfaces they give, and only the other bodies are checked
        // (D224). `keep` is what lowering skips below.
        let (keep, keep_error) = mem.alloc[bool](a, loaded.count)
        if keep_error != ok { ret keep_error }
        let held = held_all[0usize..loaded.count]
        var keep_at = 0usize
        while keep_at < loaded.count {
            keep[keep_at] = false
            keep_at += 1usize
        }
        var check_error = ok
        if !(writes_all_em && incremental_build) && loaded.order_count == loaded.count {
            check_error = declarations_per_module(&checker, &resolver, &loaded)
        } else {
            check_error = check.run_declarations(&checker, &resolver, &loaded)
        }
        report.arena_used = mem.stats(a).used
        try report_phase(&report, "check declarations")
        var artifact_dir = ""
        if args.len > 6usize { artifact_dir = args[6usize] }
        if hot_build {
            let (hot_dir, hot_dir_error) = artifact_directory(a, &loaded, release_build)
            if hot_dir_error != ok { ret hot_dir_error }
            artifact_dir = hot_dir
        }
        if check_error == ok && ((writes_all_em && incremental_build) || hot_build) {
            let (settle_strings, settle_strings_error) = mem.alloc[str](a, 32768usize)
            if settle_strings_error != ok { ret settle_strings_error }
            let (settle_slots, settle_slots_error) = mem.alloc[usize](a, 131072usize)
            if settle_slots_error != ok { ret settle_slots_error }
            var settle_table: em.StringTable = zero
            try em.init_strings(&settle_table, settle_strings, settle_slots)
            let (settle_scratch_storage, settle_scratch_error) = mem.alloc[u8](a, 4194304usize)
            if settle_scratch_error != ok { ret settle_scratch_error }
            var settle_scratch: binary.Buffer = zero
            try binary.init(&settle_scratch, settle_scratch_storage)
            let (settle_triple, settle_triple_error) = target_triple(a, args[4usize], args[5usize])
            if settle_triple_error != ok { ret settle_triple_error }
            var settle_mode: em.BuildMode = .Debug
            if release_build { settle_mode = .Release }
            try settle_early(a, &checker, &loaded, artifact_dir, settle_triple, settle_mode, &settle_table, &settle_scratch, keep, held, &hot_load)
            report.arena_used = mem.stats(a).used
            try report_phase(&report, "settle")
        }
        // Section 12's inlining (D207): the small functions are lowered first into the
        // oracle, in module order on every path, and the program's own lowering copies
        // them in at their calls. A debug build does not inline (D211): every frame
        // in its backtrace is a real call, so the oracle is not even built. The first
        // oracle rides the body sweep (D313); the entry table is one slot when it is not.
        var first_oracle: nir.Builder = zero
        var first_signatures: nir.Signatures = zero
        var first_entry_count = 0usize
        var first_capacity = 1usize
        if release_build { first_capacity = sized(4096usize, loaded.total_bytes, 128usize) }
        let (first_entries, first_entries_error) = mem.alloc[nir.InlineEntry](a, first_capacity)
        if first_entries_error != ok { ret first_entries_error }
        let (bindings, bindings_error) = mem.alloc[lower.Binding](a, sized(16384usize, loaded.total_bytes, 64usize))
        if bindings_error != ok { ret bindings_error }
        report.build.pools[stats.POOL_BINDINGS] = bindings.len
        checker.arena = a
        let fused = check_error == ok && !(writes_all_em && incremental_build) && loaded.order_count == loaded.count
        // A release build checks every body, kept or not: the oracle inlines from
        // all of them, and a hot release image is then the cold one's (D319).
        var body_skip = keep
        if release_build { body_skip = keep[0usize..0usize] }
        // The executable path's crew (D326): the workers that check the bodies, build
        // the oracles and lower, made now so a module's instances stay with the
        // checker that made them.
        var crew: Crew = zero
        var hot: HotBuild = zero
        // What the workers copy the build mode from until the program builder exists.
        var early_builder: nir.Builder = zero
        // The cap and the explanations (D346) ride the builder the oracles copy from.
        if trailing_flags {
            early_builder.inline_cap = inline_cap_flag(args)
            early_builder.explain = has_flag(args, "--explain")
        }
        if writes_executable {
            hot.on = hot_build
            hot.keep = keep
            hot.directory = artifact_dir
            hot.release = release_build
            let (hot_triple, hot_triple_error) = target_triple(a, args[4usize], args[5usize])
            if hot_triple_error != ok { ret hot_triple_error }
            hot.triple = hot_triple
        }
        let with_crew = fused && writes_executable
        if with_crew {
            try crew_begin(a, &crew, &report, &loaded, &checker, &resolver, &early_builder, bindings, machine_abi_of(args), &hot, held, release_build, body_skip)
        }
        if release_build && !with_crew {
            try init_first_oracle(a, &first_oracle, &first_signatures, &checker, &loaded)
            first_oracle.inline_cap = early_builder.inline_cap
            first_oracle.explain = early_builder.explain
        }
        if fused {
            if with_crew {
                try crew_bodies(a, &crew, &report, &loaded, &checker, &resolver, machine_abi_of(args), &hot, held, bindings, &early_builder, body_skip)
            } else {
                check_error = bodies_per_module(&checker, &resolver, &loaded, &report, &first_oracle, &first_signatures, bindings, first_entries, &first_entry_count, release_build, body_skip)
            }
        } else {
            if check_error == ok { check_error = check.check_bodies(&checker, &resolver, &loaded, keep) }
        }
        report.arena_used = mem.stats(a).used
        try report_phase(&report, "check bodies")
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
        var error_validation_error = error_table.validate_declarations(&resolver, &loaded, &error_conflict)
        if error_validation_error == ok && writes_executable {
            error_validation_error = error_table.validate_link(&resolver, &loaded, &error_conflict)
        }
        if error_validation_error != ok {
            try print_error_table_diagnostic(&report, &loaded, &error_conflict, error_validation_error)
            try finish_report(&report)
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
        if with_crew { crew_errors(&crew, error_values, error_spellings, error_count) }
        checker.arena = a
        var builder: nir.Builder = zero
        var signatures: nir.Signatures = zero
        // One more parameter type than the declarations need: `neper_report_failure`,
        // which lowering synthesizes for `main`'s failure line (D199), has no declaration.
        var builder_scale = 1usize
        if writes_executable { builder_scale = 64usize }
        try init_cli_nir(a, &builder, &signatures, checker.parameter_count + checker.return_type_count + 1usize, &loaded, &report, body_bytes_of(&loaded, writes_executable), builder_scale)
        let (lowered_modules, lowered_modules_error) = mem.alloc[bool](a, loaded.count + 1usize)
        if lowered_modules_error != ok { ret lowered_modules_error }
        let (kept_functions, kept_functions_error) = mem.alloc[bool](a, builder.functions.len + 1usize)
        if kept_functions_error != ok { ret kept_functions_error }
        builder.nocheck = release_build
        builder.release = release_build
        builder.arena_bytes = arena_flag(args)
        var oracle: nir.Builder = zero
        var oracle_signatures: nir.Signatures = zero
        let (inlined, inlined_error) = mem.alloc[nir.InlinedRef](a, sized(8192usize, loaded.total_bytes, 64usize))
        if inlined_error != ok { ret inlined_error }
        builder.inlined = inlined
        builder.inlined_count = 0usize
        let (inlined_marks, inlined_marks_error) = mem.alloc[u8](a, inlined.len)
        if inlined_marks_error != ok { ret inlined_marks_error }
        builder.inlined_marks = inlined_marks
        builder.has_oracle = false
        if release_build && with_crew {
            // The two oracles on the crew (D326): the first was built with the bodies,
            // the second is built now against it, worker by worker.
            try crew_second_oracle(a, &crew, &report, &loaded, &checker, &resolver, machine_abi_of(args), &hot, held, bindings, &builder, body_skip)
            builder.has_oracle = true
            builder.inline_entries = crew.second_all
            builder.inline_entry_count = crew.second_all_count
            report.arena_used = mem.stats(a).used
            try report_phase(&report, "inline oracles")
            if report.timing {
                try report_count("first oracle entries", crew.first_all_count)
                try report_count("second oracle entries", crew.second_all_count)
            }
        }
        if release_build && !with_crew {
            // Twice (D212): the first oracle's bodies hold no copies; the second is
            // lowered against it, so its bodies hold one level of copies, and a call
            // the program inlines from it is two levels deep. Each pass records, per
            // function, the callees it copied, for the body edges. The first was built
            // in the body sweep unless that sweep was the incremental one (D313).
            if !fused {
                let first_error = lower.build_inline_oracle(&checker, &loaded, &first_oracle, &first_signatures, bindings, first_entries, &first_entry_count)
                if first_error != ok {
                    try print_lower_diagnostic(&report, &loaded, &checker, &first_oracle, first_error)
                    try finish_report(&report)
                    os.exit(1i32)
                    ret ok
                }
            }
            try init_oracle_nir(a, &oracle, &oracle_signatures, checker.parameter_count + checker.return_type_count + 1usize, loaded.total_bytes)
            oracle.nocheck = true
            oracle.release = true
            oracle.oracle = &first_oracle
            oracle.oracle_signatures = &first_signatures
            oracle.has_oracle = true
            oracle.inline_entries = first_entries
            oracle.inline_entry_count = first_entry_count
            let (oracle_inlined, oracle_inlined_error) = mem.alloc[nir.InlinedRef](a, sized(8192usize, loaded.total_bytes, 64usize))
            if oracle_inlined_error != ok { ret oracle_inlined_error }
            oracle.inlined = oracle_inlined
            let (inline_entries, inline_entries_error) = mem.alloc[nir.InlineEntry](a, sized(4096usize, loaded.total_bytes, 128usize))
            if inline_entries_error != ok { ret inline_entries_error }
            var inline_entry_count = 0usize
            let oracle_error = lower.build_inline_oracle(&checker, &loaded, &oracle, &oracle_signatures, bindings, inline_entries, &inline_entry_count)
            report.arena_used = mem.stats(a).used
            try report_phase(&report, "inline oracles")
            if report.timing {
                try report_count("first oracle entries", first_entry_count)
                try report_count("second oracle entries", inline_entry_count)
            }
            if oracle_error != ok {
                try print_lower_diagnostic(&report, &loaded, &checker, &oracle, oracle_error)
                try finish_report(&report)
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
        // The executable path lowers and selects a module at a time (D314); the rest
        // lower the program whole, since an artifact or an object keeps every function.
        let per_module = writes_executable
        var lower_error = ok
        if !per_module {
            if writes_all_em {
                lower_error = lower.all_modules(&checker, &loaded, &builder, &signatures, bindings, lowered_modules, keep)
            } else {
                lower_error = lower.reachable_modules(&checker, &loaded, &builder, &signatures, bindings, lowered_modules)
                report.arena_used = mem.stats(a).used
                try report_phase(&report, "lower")
            }
        }
        if lower_error == ok {
            // Everything was lowered so that the order is the one the artifacts also use; what
            // nothing reaches is dropped now, which both link paths do identically.
            // An artifact holds the whole module (D214): the linker that consumes it
            // prunes, as the executable path does here.
            if !(writes_em || writes_all_em || per_module) {
                let prune_error = nir.prune_unreachable(&builder, kept_functions, false)
                report.arena_used = mem.stats(a).used
                try report_phase(&report, "prune")
                if prune_error != ok {
                    try print_lower_diagnostic(&report, &loaded, &checker, &builder, prune_error)
                    try finish_report(&report)
            os.exit(1i32)
                    ret ok
                }
            }
        }
        if lower_error != ok {
            try print_lower_diagnostic(&report, &loaded, &checker, &builder, lower_error)
            try finish_report(&report)
            os.exit(1i32)
            ret ok
        }
        var code: Code = zero
        if per_module {
            if with_crew {
                // The workers' builders carry the program's mode and arena from the
                // one made early; what the oracles added they were given above.
                var mode_at = 0usize
                while mode_at <= generous_slot() {
                    if mode_at < crew.count || (mode_at == generous_slot() && crew.generous_made) {
                        crew.workers[mode_at].builder.release = builder.release
                        crew.workers[mode_at].builder.nocheck = builder.nocheck
                        crew.workers[mode_at].builder.arena_bytes = builder.arena_bytes
                    }
                    mode_at += 1usize
                }
                try crew_emit(a, &crew, &report, &loaded, &checker, &resolver, &builder, bindings, lowered_modules, machine_abi_of(args), &hot, held, &code, body_skip)
            } else {
                try emit_per_module(a, &report, &loaded, &checker, &resolver, &builder, bindings, lowered_modules, machine_abi_of(args), &hot, held, &code)
            }
        } else {
            try emit_whole_program(a, &report, &loaded, &builder, emit_machine_code, writes_executable, machine_abi_of(args), &code)
        }
        if emit_machine_code {
            if writes_em || writes_all_em {
                // One entry per byte of the artifact, and `e.str` alone compiles to
                // more than 256 KiB, so the old quarter-megabyte stopped every
                // `emit-em-all` over a module that uses it.
                let (artifact_storage, artifact_storage_error) = mem.alloc[u8](a, 8388608usize)
                if artifact_storage_error != ok { ret artifact_storage_error }
                var artifact: binary.Buffer = zero
                try binary.init(&artifact, artifact_storage)
                let (scratch_storage, scratch_storage_error) = mem.alloc[u8](a, 4194304usize)
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
                    try em.write_module(&checker, &loaded, &builder, 0usize, triple, artifact_mode, &code.machine, code.function_offsets, code.relocations, code.relocation_count, code.lines, code.line_count, &strings, sections, &scratch, &artifact)
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
                        try em.write_module(&checker, &loaded, &builder, module_at, triple, artifact_mode, &code.machine, code.function_offsets, code.relocations, code.relocation_count, code.lines, code.line_count, &strings, sections, &scratch, &artifact)
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
            try codegen_x64.resolve_calls(&builder, code.function_offsets, code.relocations, code.relocation_count, &code.machine)
            if disassemble {
                if report.map_stale {
                    try finish_report(&report)
                    os.exit(1i32)
                }
                try tool.disassembly_json(a, args[4usize], args[5usize], &builder, code.function_offsets, code.machine.bytes, code.machine.count, code.relocations, code.relocation_count)
                ret ok
            }
            if writes_executable {
                // A stale map (section 8, D300): the analysis ran and reported, no artifact.
                if report.map_stale {
                    try finish_report(&report)
                    os.exit(1i32)
                }
                if !per_module {
                    report.arena_used = mem.stats(a).used
                    try report_phase(&report, "regalloc and codegen")
                }
                if report.timing {
                    try stderr_text("  of which folding: ")
                    try report_ms(report.fold_ns)
                }
                // The symbol table first, then the image buffer sized from the code with it
                // (D306): sized before it, a mebibyte of slack covered the table of a small
                // program and not the twenty of a large one.
                try codegen_x64.append_symbol_table(&builder, &code.machine, code.function_offsets, code.relocations, code.relocation_count, code.lines, code.line_count)
                let executable_capacity = code.machine.count + 1048576usize
                let (executable_storage, executable_storage_error) = mem.alloc[u8](a, executable_capacity)
                if executable_storage_error != ok { ret executable_storage_error }
                report.build.pools[stats.POOL_IMAGE] = executable_storage.len
                var executable: emit_x64.Buffer = zero
                try emit_x64.init(&executable, executable_storage)
                if machine_abi_of(args) == .Windows {
                    try link_pe.write(&builder, &code.machine, code.function_offsets, code.relocations, code.relocation_count, &executable)
                } else {
                    try link_elf.write(&builder, &code.machine, code.function_offsets, code.relocations, code.relocation_count, &executable)
                }
                report.arena_used = mem.stats(a).used
                try report_phase(&report, "link")
                if report.timing { try report_counts(&loaded, &resolver, &checker, &builder) }
                let (packed, packed_error) = mem.alloc[u8](a, executable.count)
                if packed_error != ok { ret packed_error }
                try emit_x64.pack(&executable, packed)
                let save_error = save_executable(a, args[6usize], packed, args[5usize])
                if save_error != ok {
                    if !report.json { ret save_error }
                    try emit_command_diagnostic(&report, "E-CLI-9999", "the executable could not be written")
                    try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"diagnostics\":1}}\n")
                    os.exit(2i32)
                    ret ok
                }
                try report_phase(&report, "write executable")
                // Every build writes `.neper/<mode>/build-manifest.json` under the project root
                // (section 7, D254), with the executable it just wrote as the one artifact.
                try fill_manifest_digests(a, &loaded, held)
                try tool.manifest_file(a, &loaded, args[4usize], args[5usize], release_build, args[6usize], packed)
                try report_phase(&report, "manifest")
                report.build.wall_ms = (nptest_now() - report.build.started) / 1000000usize
                report.build.image_bytes = packed.len
                if running {
                    report.build.started = nptest_now()
                    let (status, stdout_captured, stderr_captured, run_error) = run_program(a, &report, args[6usize], program_arguments(args))
                    report.build.ran = true
                    report.build.run_ms = (nptest_now() - report.build.started) / 1000000usize
                    report.build.exit_code = status
                    if report.build.on { try stats.print(a, &report.build, &loaded, &resolver, &checker, &builder) }
                    if run_error != ok {
                        try emit_command_diagnostic(&report, "E-CLI-9999", "the executable could not be run")
                        try write_all(&report, "{\"record\":\"result\",\"ok\":false,\"exit_code\":2,\"data\":{\"diagnostics\":1}}\n")
                        os.exit(2i32)
                        ret ok
                    }
                    try tool.run_record(a, status, stdout_captured, stderr_captured, loaded.modules[0usize].name, basename(args[2usize]), loaded.modules[0usize].text, loaded.modules[0usize].spelling)
                    try write_all(&report, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"executable\":")
                    try write_json_string(&report, args[6usize])
                    try write_all(&report, ",\"process_exit_code\":")
                    if status < 0i32 {
                        try write_all(&report, "-")
                        try write_usize(&report, usize(0i32 - status))
                    } else {
                        try write_usize(&report, usize(status))
                    }
                    ret write_all(&report, ",\"diagnostics\":0}}\n")
                }
                if report.json {
                    try write_all(&report, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"executable\":")
                    try write_json_string(&report, args[6usize])
                    ret write_all(&report, ",\"diagnostics\":0}}\n")
                }
                try io.print("executable written\n")
                if report.build.on { try stats.print(a, &report.build, &loaded, &resolver, &checker, &builder) }
                ret ok
            }
            if emit_object {
                let object_capacity = code.machine.count + builder.function_count * 256usize + code.relocation_count * 32usize + 65536usize
                let (object_storage, object_storage_error) = mem.alloc[u8](a, object_capacity)
                if object_storage_error != ok { ret object_storage_error }
                var object: emit_x64.Buffer = zero
                try emit_x64.init(&object, object_storage)
                if machine_abi_of(args) == .Windows {
                    let (symbols, symbols_error) = mem.alloc[object_coff.Symbol](a, sized(16384usize, loaded.total_bytes, 64usize))
                    if symbols_error != ok { ret symbols_error }
                    try object_coff.write(&builder, &code.machine, code.function_offsets, code.relocations, code.relocation_count, symbols, &object)
                } else {
                    let (symbols, symbols_error) = mem.alloc[object_elf.Symbol](a, sized(16384usize, loaded.total_bytes, 64usize))
                    if symbols_error != ok { ret symbols_error }
                    try object_elf.write(&builder, &code.machine, code.function_offsets, code.relocations, code.relocation_count, symbols, &object)
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
    try stderr_text("error[E-CLI-9999]: usage: neper-self self-test | validate-em ARTIFACT | check-em-edge DEPENDENT TARGET | check-em-errors ARTIFACT... | link-em OUTPUT ARTIFACT... | scan|parse SOURCE | scan-file|parse-file PATH | project-file PATH ROOT MODULE | select-file ROOT SOURCE_ROOT MODULE ARCH OS PATH | graph-file PATH TOOLCHAIN_ROOT ARCH OS MODULE... | resolve-file|check-file|nir-file|codegen-file|object-file PATH TOOLCHAIN_ROOT ARCH OS | emit-object|emit-executable|emit-em|emit-em-all PATH TOOLCHAIN_ROOT ARCH OS OUTPUT [--release] [--incremental] [--arena SIZE] [-j N] [--perturb] [--inline-cap N] [--explain] [--json] [--time] [--stats|--stats-full] | run PATH TOOLCHAIN_ROOT ARCH OS OUTPUT [--release] [--arena SIZE] [-j N] --json [--time] [--stats|--stats-full] [-- ARGS...]\n")
    os.exit(1i32)
    ret ok
}
