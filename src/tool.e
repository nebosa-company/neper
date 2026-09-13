// The machine protocol of docs/tooling.md, version 1 (D227): the stream header, the
// `tokens` command's token, trivia and diagnostic records, and the result record,
// as JSON Lines on stdout.

use e.mem
use e.os
use lex
use parse
use syntax
use resolve
use nir

error Capacity

// One record at a time: built here, printed whole, so a line is never split.
type Out = struct {
    bytes: []u8,
    count: usize,
}

fn byte(out: *Out, value: u8) -> err {
    if out.count == out.bytes.len { ret Capacity }
    out.bytes[out.count] = value
    out.count += 1usize
    ret ok
}

fn text(out: *Out, value: str) -> err {
    var at = 0usize
    while at < value.len {
        try byte(out, value[at])
        at += 1usize
    }
    ret ok
}

fn decimal(out: *Out, value: usize) -> err {
    if value >= 10usize { try decimal(out, value / 10usize) }
    ret byte(out, u8(48usize + value % 10usize))
}

fn flush(out: *Out) -> err {
    try byte(out, 10u8)
    let stdout = os.stdout()
    var at = 0usize
    while at < out.count {
        let (written, write_error) = os.write(stdout, out.bytes[at..out.count])
        if write_error != ok { ret write_error }
        if written == 0usize { ret Capacity }
        at += written
    }
    out.count = 0usize
    ret ok
}

// A JSON string of valid UTF-8: the two escapes JSON requires and `\u` for the rest
// of the controls, everything else as it is.
fn quoted(out: *Out, value: str) -> err {
    try byte(out, 34u8)
    var at = 0usize
    while at < value.len {
        let c = value[at]
        if c == 34u8 || c == 92u8 {
            try byte(out, 92u8)
            try byte(out, c)
        } else {
            if c == 10u8 {
                try text(out, "\\n")
            } else {
                if c == 13u8 {
                    try text(out, "\\r")
                } else {
                    if c == 9u8 {
                        try text(out, "\\t")
                    } else {
                        if c < 32u8 {
                            try text(out, "\\u00")
                            try byte(out, hex_digit(usize(c) / 16usize))
                            try byte(out, hex_digit(usize(c) % 16usize))
                        } else {
                            try byte(out, c)
                        }
                    }
                }
            }
        }
        at += 1usize
    }
    ret byte(out, 34u8)
}

fn hex_digit(value: usize) -> u8 {
    if value < 10usize { ret u8(48usize + value) }
    ret u8(87usize + value)
}

// Section 2's captured bytes for what is not valid UTF-8: canonical padded base64.
fn base64_object(out: *Out, value: str) -> err {
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    try text(out, "{\"encoding\":\"base64\",\"data\":\"")
    var at = 0usize
    while at < value.len {
        let first = usize(value[at])
        var second = 0usize
        var third = 0usize
        if at + 1usize < value.len { second = usize(value[at + 1usize]) }
        if at + 2usize < value.len { third = usize(value[at + 2usize]) }
        let group = first * 65536usize + second * 256usize + third
        try byte(out, alphabet[(group >> 18usize) & 63usize])
        try byte(out, alphabet[(group >> 12usize) & 63usize])
        if at + 1usize < value.len { try byte(out, alphabet[(group >> 6usize) & 63usize]) } else { try byte(out, 61u8) }
        if at + 2usize < value.len { try byte(out, alphabet[group & 63usize]) } else { try byte(out, 61u8) }
        at += 3usize
    }
    ret text(out, "\"}")
}

fn span(out: *Out, root: str, path: str, byte_start: usize, byte_end: usize, line: usize, column: usize, end_line: usize, end_column: usize, column_utf16: usize, end_column_utf16: usize) -> err {
    try text(out, "{\"source\":{\"root\":")
    try quoted(out, root)
    try text(out, ",\"path\":")
    try quoted(out, path)
    try text(out, "},\"byte_start\":")
    try decimal(out, byte_start)
    try text(out, ",\"byte_end\":")
    try decimal(out, byte_end)
    try text(out, ",\"line\":")
    try decimal(out, line)
    try text(out, ",\"column\":")
    try decimal(out, column)
    try text(out, ",\"end_line\":")
    try decimal(out, end_line)
    try text(out, ",\"end_column\":")
    try decimal(out, end_column)
    try text(out, ",\"column_utf16\":")
    try decimal(out, column_utf16)
    try text(out, ",\"end_column_utf16\":")
    try decimal(out, end_column_utf16)
    ret byte(out, 125u8)
}

fn header(out: *Out, command: str) -> err {
    try text(out, "{\"schema\":\"neper-stream\",\"version\":1,\"record\":\"header\",\"command\":")
    try quoted(out, command)
    try text(out, ",\"tool_version\":\"0.1.0\",\"language_version\":\"0.1\",\"grammar_revision\":1}")
    ret flush(out)
}

fn result(out: *Out, succeeded: bool, exit_code: usize, tokens: usize, diagnostics: usize) -> err {
    if succeeded { try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":") } else { try text(out, "{\"record\":\"result\",\"ok\":false,\"exit_code\":") }
    try decimal(out, exit_code)
    try text(out, ",\"data\":{\"tokens\":")
    try decimal(out, tokens)
    try text(out, ",\"diagnostics\":")
    try decimal(out, diagnostics)
    try text(out, "}}")
    ret flush(out)
}

// `info --json` (D229): the header, one `info` record of what this build answers
// to -- every collection sorted by bytes, as section 1 requires -- and a result.
fn info_json(a: *mem.Arena, host: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, 4096usize)
    if storage_error != ok { ret storage_error }
    var out = Out { bytes: storage, count: 0usize }
    try header(&out, "info")
    try text(&out, "{\"record\":\"info\",\"tool_version\":\"0.1.0\",\"language_profiles\":[{\"language_version\":\"0.1\",\"grammar_revision\":1,\"stream_version\":1,\"experimental\":false}],\"commands\":[\"check\",\"info\",\"parse\",\"tokens\"],\"host_target\":")
    try quoted(&out, host)
    // ponytail: the emitter selects nothing above SSE2 and SIMD lowers as lane loops (D148),
    // so x64-v1 is the one level this build honours; list the others when `--cpu` exists.
    try text(&out, ",\"build_targets\":[\"x64-linux\",\"x64-windows\"],\"cpu_levels\":[\"x64-v1\"],\"features\":[]}")
    try flush(&out)
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{}}")
    ret flush(&out)
}

// Section 2's captured bytes: a JSON string when they are valid UTF-8, base64 otherwise.
fn captured(out: *Out, value: str) -> err {
    var at = 0usize
    while at < value.len {
        let width = lex.utf8_width(value, at)
        if width == 0usize { ret base64_object(out, value) }
        at += width
    }
    ret quoted(out, value)
}

// `run --json` (D231): the program's exit status and its whole stdout and stderr as one
// record; a trap is not yet read out of the stderr text.
fn run_record(a: *mem.Arena, status: i32, stdout_bytes: str, stderr_bytes: str) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, (stdout_bytes.len + stderr_bytes.len) * 6usize + 256usize)
    if storage_error != ok { ret storage_error }
    var out = Out { bytes: storage, count: 0usize }
    try text(&out, "{\"record\":\"run\",\"process_exit_code\":")
    if status < 0i32 {
        try byte(&out, 45u8)
        try decimal(&out, usize(0i32 - status))
    } else {
        try decimal(&out, usize(status))
    }
    try text(&out, ",\"stdout\":")
    try captured(&out, stdout_bytes)
    try text(&out, ",\"stderr\":")
    try captured(&out, stderr_bytes)
    try text(&out, ",\"trap\":null}")
    ret flush(&out)
}

// docs/tooling.md section 5's `kind` for a module-scope declaration; the resolver's
// own kinds map onto the closed set one to one (D232).
fn index_kind_name(kind: resolve.Kind) -> str {
    if kind == .Type { ret "type" }
    if kind == .Const { ret "const" }
    if kind == .Var { ret "module_var" }
    if kind == .Error { ret "error" }
    if kind == .Function { ret "fn" }
    if kind == .Extern { ret "extern" }
    ret "intrinsic"
}

// A JSON string of `module.name`; both halves are identifiers or a dotted module path,
// so no escape is ever needed.
fn index_qualified(out: *Out, module_name: str, name: str) -> err {
    try byte(out, 34u8)
    try text(out, module_name)
    try byte(out, 46u8)
    try text(out, name)
    ret byte(out, 34u8)
}

// `index --json` (D232): a `symbol` record for the module and each of its module-scope
// declarations. Locals, parameters, fields, members, documentation, signatures and every
// reference are the gap -- the resolver does not carry them, so this names only what it does.
fn index_json(a: *mem.Arena, root: str, path: str, source: str, module_name: str, module_index: usize, symbols: []const resolve.Symbol, count: usize) -> (usize, err) {
    let (tokens, token_count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (2usize, scan_error) }
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 8usize + 8192usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize }
    let header_error = header(&out, "index")
    if header_error != ok { ret (2usize, header_error) }
    // The module itself is the first symbol, so every declaration's container is id 0.
    let module_error = index_module_record(&out, module_name)
    if module_error != ok { ret (2usize, module_error) }
    var emitted = 1usize
    var at = 0usize
    while at < count {
        let symbol = symbols[at]
        if symbol.module_index == module_index && symbol.kind != .Qualifier && symbol.kind != .Intrinsic {
            var name_index = symbol.token_start + 1usize
            if symbol.kind == .Extern { name_index += 1usize }
            if symbol.token_end == 0usize || symbol.token_end > token_count || name_index >= token_count { ret (2usize, parse.InvalidSyntax) }
            let record_error = index_symbol_record(&out, root, path, module_name, emitted, symbol, tokens[symbol.token_start], tokens[symbol.token_end - 1usize], tokens[name_index])
            if record_error != ok { ret (2usize, record_error) }
            emitted += 1usize
        }
        at += 1usize
    }
    let result_error = index_result(&out, emitted)
    if result_error != ok { ret (2usize, result_error) }
    ret (0usize, ok)
}

fn index_module_record(out: *Out, module_name: str) -> err {
    try text(out, "{\"record\":\"symbol\",\"id\":0,\"kind\":\"module\",\"name\":")
    try quoted(out, module_name)
    try text(out, ",\"qualified_name\":")
    try quoted(out, module_name)
    try text(out, ",\"module\":")
    try quoted(out, module_name)
    try text(out, ",\"signature\":null,\"span\":null,\"selection_span\":null,\"container_id\":null,\"attributes\":[],\"documentation\":null}")
    ret flush(out)
}

fn index_symbol_record(out: *Out, root: str, path: str, module_name: str, id: usize, symbol: resolve.Symbol, opener: lex.Token, closer: lex.Token, name_token: lex.Token) -> err {
    try text(out, "{\"record\":\"symbol\",\"id\":")
    try decimal(out, id)
    try text(out, ",\"kind\":")
    try quoted(out, index_kind_name(symbol.kind))
    try text(out, ",\"name\":")
    try quoted(out, symbol.name)
    try text(out, ",\"qualified_name\":")
    try index_qualified(out, module_name, symbol.name)
    try text(out, ",\"module\":")
    try quoted(out, module_name)
    try text(out, ",\"signature\":null,\"span\":")
    try span(out, root, path, opener.start, closer.end, opener.line, opener.column, closer.end_line, closer.end_column, opener.column_utf16, closer.end_column_utf16)
    try text(out, ",\"selection_span\":")
    try span(out, root, path, name_token.start, name_token.end, name_token.line, name_token.column, name_token.end_line, name_token.end_column, name_token.column_utf16, name_token.end_column_utf16)
    try text(out, ",\"container_id\":0,\"attributes\":[],\"documentation\":null}")
    ret flush(out)
}

fn index_result(out: *Out, symbols: usize) -> err {
    try text(out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"symbols\":")
    try decimal(out, symbols)
    try text(out, ",\"references\":0}}")
    ret flush(out)
}

// `dis --json` (D233): one `disassembly` record per function. The `text` is the
// function's machine bytes as space-separated lowercase hex -- a faithful listing of
// what code selection produced. Mnemonic (AT&T/Intel) disassembly is the gap.
fn disassembly_json(a: *mem.Arena, arch: str, os_name: str, builder: *nir.Builder, offsets: []const usize, machine: []const usize, machine_count: usize) -> err {
    let (storage, storage_error) = mem.alloc[u8](a, machine_count * 3usize + 8192usize)
    if storage_error != ok { ret storage_error }
    var out = Out { bytes: storage, count: 0usize }
    try header(&out, "dis")
    var at = 0usize
    while at < builder.function_count {
        let start = offsets[at]
        var stop = machine_count
        if at + 1usize < builder.function_count { stop = offsets[at + 1usize] }
        try text(&out, "{\"record\":\"disassembly\",\"symbol\":")
        let function = builder.functions[at]
        // module.function, the name a backtrace and the symbol table use (D206).
        if function.module_name.len != 0usize {
            try byte(&out, 34u8)
            try text(&out, function.module_name)
            try byte(&out, 46u8)
            try text(&out, function.name)
            try byte(&out, 34u8)
        } else {
            try quoted(&out, function.name)
        }
        try text(&out, ",\"target\":\"")
        try text(&out, arch)
        try byte(&out, 45u8)
        try text(&out, os_name)
        try text(&out, "\",\"text\":\"")
        var byte_at = start
        while byte_at < stop {
            if byte_at != start { try byte(&out, 32u8) }
            let value = machine[byte_at] & 255usize
            try byte(&out, hex_digit(value / 16usize))
            try byte(&out, hex_digit(value % 16usize))
            byte_at += 1usize
        }
        try text(&out, "\"}")
        try flush(&out)
        at += 1usize
    }
    try text(&out, "{\"record\":\"result\",\"ok\":true,\"exit_code\":0,\"data\":{\"functions\":")
    try decimal(&out, builder.function_count)
    try text(&out, "}}")
    ret flush(&out)
}

// The public name of a token kind, the registry of docs/grammar.ebnf.
fn kind_name(kind: lex.Kind) -> str {
    if kind == .Invalid { ret "INVALID" }
    if kind == .Eof { ret "EOF" }
    if kind == .Newline { ret "NEWLINE" }
    if kind == .Identifier { ret "IDENTIFIER" }
    if kind == .Integer { ret "INTEGER" }
    if kind == .Float { ret "FLOAT" }
    if kind == .String { ret "STRING" }
    if kind == .RawString { ret "RAW_STRING" }
    if kind == .Character { ret "CHARACTER" }
    if kind == .KwUse { ret "KW_USE" }
    if kind == .KwType { ret "KW_TYPE" }
    if kind == .KwConst { ret "KW_CONST" }
    if kind == .KwVar { ret "KW_VAR" }
    if kind == .KwLet { ret "KW_LET" }
    if kind == .KwFn { ret "KW_FN" }
    if kind == .KwRet { ret "KW_RET" }
    if kind == .KwIf { ret "KW_IF" }
    if kind == .KwElse { ret "KW_ELSE" }
    if kind == .KwWhile { ret "KW_WHILE" }
    if kind == .KwFor { ret "KW_FOR" }
    if kind == .KwIn { ret "KW_IN" }
    if kind == .KwSwitch { ret "KW_SWITCH" }
    if kind == .KwCase { ret "KW_CASE" }
    if kind == .KwDefault { ret "KW_DEFAULT" }
    if kind == .KwBreak { ret "KW_BREAK" }
    if kind == .KwContinue { ret "KW_CONTINUE" }
    if kind == .KwDefer { ret "KW_DEFER" }
    if kind == .KwTry { ret "KW_TRY" }
    if kind == .KwStruct { ret "KW_STRUCT" }
    if kind == .KwUnion { ret "KW_UNION" }
    if kind == .KwEnum { ret "KW_ENUM" }
    if kind == .KwError { ret "KW_ERROR" }
    if kind == .KwWhen { ret "KW_WHEN" }
    if kind == .KwTrue { ret "KW_TRUE" }
    if kind == .KwFalse { ret "KW_FALSE" }
    if kind == .KwNil { ret "KW_NIL" }
    if kind == .KwOk { ret "KW_OK" }
    if kind == .KwAs { ret "KW_AS" }
    if kind == .KwZero { ret "KW_ZERO" }
    if kind == .KwUndef { ret "KW_UNDEF" }
    if kind == .KwExtern { ret "KW_EXTERN" }
    if kind == .KwUnreachable { ret "KW_UNREACHABLE" }
    if kind == .KwShared { ret "KW_SHARED" }
    if kind == .PunctEllipsis { ret "PUNCT_ELLIPSIS" }
    if kind == .PunctRange { ret "PUNCT_RANGE" }
    if kind == .PunctArrow { ret "PUNCT_ARROW" }
    if kind == .PunctEqEq { ret "PUNCT_EQ_EQ" }
    if kind == .PunctBangEq { ret "PUNCT_BANG_EQ" }
    if kind == .PunctLtEq { ret "PUNCT_LT_EQ" }
    if kind == .PunctGtEq { ret "PUNCT_GT_EQ" }
    if kind == .PunctShiftLeft { ret "PUNCT_SHIFT_LEFT" }
    if kind == .PunctShiftRight { ret "PUNCT_SHIFT_RIGHT" }
    if kind == .PunctAddWrap { ret "PUNCT_ADD_WRAP" }
    if kind == .PunctSubWrap { ret "PUNCT_SUB_WRAP" }
    if kind == .PunctMulWrap { ret "PUNCT_MUL_WRAP" }
    if kind == .PunctAddAssign { ret "PUNCT_ADD_ASSIGN" }
    if kind == .PunctSubAssign { ret "PUNCT_SUB_ASSIGN" }
    if kind == .PunctMulAssign { ret "PUNCT_MUL_ASSIGN" }
    if kind == .PunctDivAssign { ret "PUNCT_DIV_ASSIGN" }
    if kind == .PunctRemAssign { ret "PUNCT_REM_ASSIGN" }
    if kind == .PunctAddWrapAssign { ret "PUNCT_ADD_WRAP_ASSIGN" }
    if kind == .PunctSubWrapAssign { ret "PUNCT_SUB_WRAP_ASSIGN" }
    if kind == .PunctMulWrapAssign { ret "PUNCT_MUL_WRAP_ASSIGN" }
    if kind == .PunctShiftLeftAssign { ret "PUNCT_SHIFT_LEFT_ASSIGN" }
    if kind == .PunctShiftRightAssign { ret "PUNCT_SHIFT_RIGHT_ASSIGN" }
    if kind == .PunctBitAndAssign { ret "PUNCT_BIT_AND_ASSIGN" }
    if kind == .PunctBitXorAssign { ret "PUNCT_BIT_XOR_ASSIGN" }
    if kind == .PunctBitOrAssign { ret "PUNCT_BIT_OR_ASSIGN" }
    if kind == .PunctAndAnd { ret "PUNCT_AND_AND" }
    if kind == .PunctOrOr { ret "PUNCT_OR_OR" }
    if kind == .PunctAt { ret "PUNCT_AT" }
    if kind == .PunctDot { ret "PUNCT_DOT" }
    if kind == .PunctComma { ret "PUNCT_COMMA" }
    if kind == .PunctColon { ret "PUNCT_COLON" }
    if kind == .PunctAssign { ret "PUNCT_ASSIGN" }
    if kind == .PunctLParen { ret "PUNCT_LPAREN" }
    if kind == .PunctRParen { ret "PUNCT_RPAREN" }
    if kind == .PunctLBracket { ret "PUNCT_LBRACKET" }
    if kind == .PunctRBracket { ret "PUNCT_RBRACKET" }
    if kind == .PunctLBrace { ret "PUNCT_LBRACE" }
    if kind == .PunctRBrace { ret "PUNCT_RBRACE" }
    if kind == .PunctStar { ret "PUNCT_STAR" }
    if kind == .PunctSlash { ret "PUNCT_SLASH" }
    if kind == .PunctPercent { ret "PUNCT_PERCENT" }
    if kind == .PunctPlus { ret "PUNCT_PLUS" }
    if kind == .PunctMinus { ret "PUNCT_MINUS" }
    if kind == .PunctLt { ret "PUNCT_LT" }
    if kind == .PunctGt { ret "PUNCT_GT" }
    if kind == .PunctAmp { ret "PUNCT_AMP" }
    if kind == .PunctCaret { ret "PUNCT_CARET" }
    if kind == .PunctPipe { ret "PUNCT_PIPE" }
    if kind == .PunctBang { ret "PUNCT_BANG" }
    if kind == .PunctTilde { ret "PUNCT_TILDE" }
    ret "PUNCT_UNDERSCORE"
}

fn trivia_name(kind: lex.TriviaKind) -> str {
    if kind == .Bom { ret "bom" }
    if kind == .Space { ret "space" }
    ret "comment"
}

// The `diagnostic` and `token` records of a token list: a diagnostic before each
// `INVALID` token, and a token record per token through `EOF`. The trivia text and
// the lexemes concatenate back to every original byte. Returns the exit code.
fn token_records(out: *Out, root: str, path: str, source: str, tokens: []const lex.Token) -> (usize, err) {
    var index = 0usize
    var diagnostics = 0usize
    while index < tokens.len {
        let token = tokens[index]
        if token.kind == .Invalid {
            let d1 = text(out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":")
            if d1 != ok { ret (2usize, d1) }
            let d2 = quoted(out, lex.invalid_code(source, token))
            if d2 != ok { ret (2usize, d2) }
            let d3 = text(out, ",\"message\":\"invalid token\",\"span\":")
            if d3 != ok { ret (2usize, d3) }
            let d4 = span(out, root, path, token.start, token.end, token.line, token.column, token.end_line, token.end_column, token.column_utf16, token.end_column_utf16)
            if d4 != ok { ret (2usize, d4) }
            let d5 = text(out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
            if d5 != ok { ret (2usize, d5) }
            let d6 = flush(out)
            if d6 != ok { ret (2usize, d6) }
            diagnostics += 1usize
        }
        let record_error = token_record(out, root, path, source, token, index)
        if record_error != ok { ret (2usize, record_error) }
        index += 1usize
    }
    if diagnostics != 0usize { ret (1usize, ok) }
    ret (0usize, ok)
}

fn token_record(out: *Out, root: str, path: str, source: str, token: lex.Token, index: usize) -> err {
    try text(out, "{\"record\":\"token\",\"index\":")
    try decimal(out, index)
    try text(out, ",\"kind\":")
    try quoted(out, kind_name(token.kind))
    try text(out, ",\"lexeme\":")
    if token.kind == .Invalid {
        try base64_object(out, source[token.start..token.end])
    } else {
        try quoted(out, source[token.start..token.end])
    }
    try text(out, ",\"span\":")
    try span(out, root, path, token.start, token.end, token.line, token.column, token.end_line, token.end_column, token.column_utf16, token.end_column_utf16)
    try text(out, ",\"leading_trivia\":[")
    var trivia_scanner = lex.trivia_init(source, token)
    var first_trivia = true
    while true {
        let item = lex.next_trivia(&trivia_scanner)
        if item.kind == .End { break }
        if !first_trivia { try byte(out, 44u8) }
        first_trivia = false
        try text(out, "{\"kind\":")
        try quoted(out, trivia_name(item.kind))
        try text(out, ",\"text\":")
        try quoted(out, source[item.start..item.end])
        try text(out, ",\"span\":")
        try span(out, root, path, item.start, item.end, item.line, item.column, item.end_line, item.end_column, item.column_utf16, item.end_column_utf16)
        try byte(out, 125u8)
    }
    try text(out, "]}")
    ret flush(out)
}

// Every token of the source, `EOF` last.
fn scan_all(a: *mem.Arena, source: str) -> ([]lex.Token, usize, usize, err) {
    let (tokens, tokens_error) = mem.alloc[lex.Token](a, source.len + 2usize)
    if tokens_error != ok { ret (tokens, 0usize, 0usize, tokens_error) }
    var count = 0usize
    var invalid = 0usize
    var scanner = lex.init(source)
    while true {
        let token = lex.next(&scanner)
        if count == tokens.len { ret (tokens, 0usize, 0usize, Capacity) }
        tokens[count] = token
        count += 1usize
        if token.kind == .Invalid { invalid += 1usize }
        if token.kind == .Eof { break }
    }
    ret (tokens, count, invalid, ok)
}

// `tokens --json`: the header, the token records, the result.
fn tokens_json(a: *mem.Arena, root: str, path: str, source: str) -> (usize, err) {
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 8usize + 4096usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize }
    let header_error = header(&out, "tokens")
    if header_error != ok { ret (2usize, header_error) }
    let (tokens, count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (2usize, scan_error) }
    let (exit_code, records_error) = token_records(&out, root, path, source, tokens[..count])
    if records_error != ok { ret (2usize, records_error) }
    let result_error = result(&out, invalid == 0usize, exit_code, count, invalid)
    if result_error != ok { ret (2usize, result_error) }
    ret (exit_code, ok)
}

// The public name of a syntax-node kind: the registry names the enum's own.
fn node_kind_name(kind: syntax.Kind) -> str {
    if kind == .File { ret "File" }
    if kind == .UseDecl { ret "UseDecl" }
    if kind == .Attribute { ret "Attribute" }
    if kind == .TypeDecl { ret "TypeDecl" }
    if kind == .ConstDecl { ret "ConstDecl" }
    if kind == .VarDecl { ret "VarDecl" }
    if kind == .ErrorDecl { ret "ErrorDecl" }
    if kind == .FnDecl { ret "FnDecl" }
    if kind == .ExternDecl { ret "ExternDecl" }
    if kind == .ComptimeParam { ret "ComptimeParam" }
    if kind == .Parameter { ret "Parameter" }
    if kind == .ReturnSpec { ret "ReturnSpec" }
    if kind == .StructType { ret "StructType" }
    if kind == .UnionType { ret "UnionType" }
    if kind == .EnumType { ret "EnumType" }
    if kind == .UnionEnumType { ret "UnionEnumType" }
    if kind == .FieldDecl { ret "FieldDecl" }
    if kind == .EnumMember { ret "EnumMember" }
    if kind == .UnionMember { ret "UnionMember" }
    if kind == .PointerType { ret "PointerType" }
    if kind == .SliceType { ret "SliceType" }
    if kind == .ArrayType { ret "ArrayType" }
    if kind == .FunctionType { ret "FunctionType" }
    if kind == .NamedType { ret "NamedType" }
    if kind == .Block { ret "Block" }
    if kind == .Binding { ret "Binding" }
    if kind == .BindingStmt { ret "BindingStmt" }
    if kind == .AssignmentStmt { ret "AssignmentStmt" }
    if kind == .CallStmt { ret "CallStmt" }
    if kind == .TryStmt { ret "TryStmt" }
    if kind == .ReturnStmt { ret "ReturnStmt" }
    if kind == .DeferStmt { ret "DeferStmt" }
    if kind == .NocheckStmt { ret "NocheckStmt" }
    if kind == .SharedVarStmt { ret "SharedVarStmt" }
    if kind == .BreakStmt { ret "BreakStmt" }
    if kind == .ContinueStmt { ret "ContinueStmt" }
    if kind == .IfStmt { ret "IfStmt" }
    if kind == .WhileStmt { ret "WhileStmt" }
    if kind == .ForStmt { ret "ForStmt" }
    if kind == .WhenStmt { ret "WhenStmt" }
    if kind == .SwitchStmt { ret "SwitchStmt" }
    if kind == .SwitchArm { ret "SwitchArm" }
    if kind == .UnaryExpr { ret "UnaryExpr" }
    if kind == .BinaryExpr { ret "BinaryExpr" }
    if kind == .FieldExpr { ret "FieldExpr" }
    if kind == .BracketPostfix { ret "BracketPostfix" }
    if kind == .CallExpr { ret "CallExpr" }
    if kind == .NameExpr { ret "NameExpr" }
    if kind == .MemberExpr { ret "MemberExpr" }
    if kind == .GroupExpr { ret "GroupExpr" }
    if kind == .AggregateLiteral { ret "AggregateLiteral" }
    if kind == .LiteralItem { ret "LiteralItem" }
    if kind == .LiteralExpr { ret "LiteralExpr" }
    ret "ErrorNode"
}

// One node of the syntax record: its kind, its span from its first token's start to
// its last token's end, its token range, and its children in order.
fn syntax_node(out: *Out, tree: *parse.Tree, tokens: []const lex.Token, node_index: usize, root: str, path: str, depth: usize) -> err {
    if depth > 512usize { ret Capacity }
    let node = tree.nodes[node_index]
    try text(out, "{\"kind\":")
    try quoted(out, node_kind_name(node.kind))
    try text(out, ",\"span\":")
    if node.token_end > node.token_start && node.token_end <= tokens.len {
        let first = tokens[node.token_start]
        let last = tokens[node.token_end - 1usize]
        try span(out, root, path, first.start, last.end, first.line, first.column, last.end_line, last.end_column, first.column_utf16, last.end_column_utf16)
    } else {
        var at_token = node.token_start
        if at_token >= tokens.len { at_token = tokens.len - 1usize }
        let here = tokens[at_token]
        try span(out, root, path, here.start, here.start, here.line, here.column, here.line, here.column, here.column_utf16, here.column_utf16)
    }
    try text(out, ",\"token_start\":")
    try decimal(out, node.token_start)
    try text(out, ",\"token_end\":")
    try decimal(out, node.token_end)
    try text(out, ",\"children\":[")
    var first_child = true
    if node.kind == .File && node_index == 0usize {
        // The root lists no children of its own: the top-level nodes are its, in order.
        var top = 1usize
        while top < tree.count {
            if tree.nodes[top].top_level {
                if !first_child { try byte(out, 44u8) }
                first_child = false
                try text(out, "{\"node\":")
                try syntax_node(out, tree, tokens, top, root, path, depth + 1usize)
                try byte(out, 125u8)
            }
            top += 1usize
        }
    } else {
        let end = node.first_child + node.child_count
        var at = node.first_child
        while at < end {
            if !first_child { try byte(out, 44u8) }
            first_child = false
            let child = tree.children[at]
            if child.node {
                try text(out, "{\"node\":")
                try syntax_node(out, tree, tokens, child.index, root, path, depth + 1usize)
                try byte(out, 125u8)
            } else {
                try text(out, "{\"token\":")
                try decimal(out, child.index)
                try byte(out, 125u8)
            }
            at += 1usize
        }
    }
    ret text(out, "]}")
}

// `parse --json`: the token records as `tokens` gives them, a syntax diagnostic where
// the parser stopped, one `syntax` record for the tree that exists, and the result.
fn parse_json(a: *mem.Arena, root: str, path: str, source: str) -> (usize, err) {
    let (storage, storage_error) = mem.alloc[u8](a, source.len * 8usize + 4096usize)
    if storage_error != ok { ret (2usize, storage_error) }
    var out = Out { bytes: storage, count: 0usize }
    let header_error = header(&out, "parse")
    if header_error != ok { ret (2usize, header_error) }
    let (tokens, count, invalid, scan_error) = scan_all(a, source)
    if scan_error != ok { ret (2usize, scan_error) }
    var diagnostics = invalid
    let (token_exit, token_records_error) = token_records(&out, root, path, source, tokens[..count])
    if token_records_error != ok { ret (2usize, token_records_error) }
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, count + 16usize)
    if nodes_error != ok { ret (2usize, nodes_error) }
    let (children, children_error) = mem.alloc[syntax.Child](a, count * 2usize + 16usize)
    if children_error != ok { ret (2usize, children_error) }
    var tree: parse.Tree = zero
    let init_error = parse.init_tree(&tree, nodes, children)
    if init_error != ok { ret (2usize, init_error) }
    let parse_error = parse.parse(&tree, source)
    if parse_error != ok {
        diagnostics += 1usize
        var at = tree.failure_token
        if !tree.has_failure { at = tokens[count - 1usize] }
        let d1 = text(&out, "{\"record\":\"diagnostic\",\"severity\":\"error\",\"code\":\"E-SYNTAX-9999\",\"message\":\"unexpected token\",\"span\":")
        if d1 != ok { ret (2usize, d1) }
        let d2 = span(&out, root, path, at.start, at.end, at.line, at.column, at.end_line, at.end_column, at.column_utf16, at.end_column_utf16)
        if d2 != ok { ret (2usize, d2) }
        let d3 = text(&out, ",\"parent\":null,\"related\":[],\"fixes\":[]}")
        if d3 != ok { ret (2usize, d3) }
        let d4 = flush(&out)
        if d4 != ok { ret (2usize, d4) }
    }
    // The tree can outgrow the record buffer the tokens used: one sized to it.
    let (tree_storage, tree_storage_error) = mem.alloc[u8](a, tree.count * 512usize + tree.child_count * 32usize + 4096usize)
    if tree_storage_error != ok { ret (2usize, tree_storage_error) }
    var tree_out = Out { bytes: tree_storage, count: 0usize }
    let s1 = text(&tree_out, "{\"record\":\"syntax\",\"root\":")
    if s1 != ok { ret (2usize, s1) }
    let s2 = syntax_node(&tree_out, &tree, tokens[..count], 0usize, root, path, 0usize)
    if s2 != ok { ret (2usize, s2) }
    let s3 = text(&tree_out, "}")
    if s3 != ok { ret (2usize, s3) }
    let s4 = flush(&tree_out)
    if s4 != ok { ret (2usize, s4) }
    var exit_code = 0usize
    if diagnostics != 0usize { exit_code = 1usize }
    let result_error = result(&out, diagnostics == 0usize, exit_code, count, diagnostics)
    if result_error != ok { ret (2usize, result_error) }
    ret (exit_code, ok)
}
