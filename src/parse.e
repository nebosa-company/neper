// Structural parser foundation. Grammar productions will replace scan_decl
// incrementally while preserving this token cursor and error contract.

use lex
use syntax

error InvalidSyntax

type Summary = struct {
    root: syntax.Kind,
    declarations: usize,
}

type Parser = struct {
    scanner: lex.Scanner,
    current: lex.Token,
    declarations: usize,
}

fn init(source: str) -> Parser {
    var scanner = lex.init(source)
    let current = lex.next(&scanner)
    ret Parser { scanner: scanner, current: current, declarations: 0usize }
}

fn advance(p: *Parser) -> err {
    if p.current.kind == .Invalid { ret InvalidSyntax }
    if p.current.kind != .Eof { p.current = lex.next(&p.scanner) }
    if p.current.kind == .Invalid { ret InvalidSyntax }
    ret ok
}

fn require(p: *Parser, expected: lex.Kind) -> err {
    if p.current.kind != expected { ret InvalidSyntax }
    try advance(p)
    ret ok
}

fn skip_separators(p: *Parser) -> err {
    while p.current.kind == .Newline { try advance(p) }
    ret ok
}

fn finish_line(p: *Parser) -> err {
    if p.current.kind == .Eof { ret ok }
    if p.current.kind != .Newline { ret InvalidSyntax }
    try skip_separators(p)
    ret ok
}

fn parse_use(p: *Parser) -> err {
    try require(p, .KwUse)
    try require(p, .Identifier)
    while p.current.kind == .PunctDot {
        try advance(p)
        try require(p, .Identifier)
    }
    if p.current.kind == .KwAs {
        try advance(p)
        try require(p, .Identifier)
    }
    try finish_line(p)
    ret ok
}

fn parse_error(p: *Parser) -> err {
    try require(p, .KwError)
    try require(p, .Identifier)
    try finish_line(p)
    ret ok
}

fn scan_delimited_decl(p: *Parser, decl_kind: lex.Kind) -> err {
    var parens = 0usize
    var brackets = 0usize
    var braces = 0usize
    var saw_assign = false
    var saw_brace = false
    if decl_kind == .KwExtern {
        try require(p, .KwFn)
    }
    try require(p, .Identifier)
    while true {
        let kind = p.current.kind
        if kind == .Invalid { ret InvalidSyntax }
        if kind == .Eof {
            if parens != 0usize || brackets != 0usize || braces != 0usize { ret InvalidSyntax }
            if (decl_kind == .KwType || decl_kind == .KwConst) && !saw_assign { ret InvalidSyntax }
            if decl_kind == .KwFn && !saw_brace { ret InvalidSyntax }
            ret ok
        }
        if kind == .Newline && parens == 0usize && brackets == 0usize && braces == 0usize {
            if (decl_kind == .KwType || decl_kind == .KwConst) && !saw_assign { ret InvalidSyntax }
            if decl_kind == .KwFn && !saw_brace { ret InvalidSyntax }
            try skip_separators(p)
            ret ok
        }
        if kind == .PunctAssign { saw_assign = true }
        if kind == .PunctLParen { parens += 1usize }
        if kind == .PunctRParen {
            if parens == 0usize { ret InvalidSyntax }
            parens = parens - 1usize
        }
        if kind == .PunctLBracket { brackets += 1usize }
        if kind == .PunctRBracket {
            if brackets == 0usize { ret InvalidSyntax }
            brackets = brackets - 1usize
        }
        if kind == .PunctLBrace {
            braces += 1usize
            saw_brace = true
        }
        if kind == .PunctRBrace {
            if braces == 0usize { ret InvalidSyntax }
            braces = braces - 1usize
        }
        try advance(p)
    }
}

fn parse_attribute(p: *Parser) -> err {
    try require(p, .PunctAt)
    try require(p, .Identifier)
    if p.current.kind == .PunctLParen {
        var depth = 0usize
        while true {
            if p.current.kind == .Invalid || p.current.kind == .Eof || p.current.kind == .Newline {
                ret InvalidSyntax
            }
            if p.current.kind == .PunctLParen { depth += 1usize }
            if p.current.kind == .PunctRParen {
                if depth == 0usize { ret InvalidSyntax }
                depth = depth - 1usize
            }
            try advance(p)
            if depth == 0usize { break }
        }
    }
    if p.current.kind != .Newline { ret InvalidSyntax }
    try skip_separators(p)
    ret ok
}

fn is_scanned_decl(kind: lex.Kind) -> bool {
    ret kind == .KwType || kind == .KwConst || kind == .KwVar || kind == .KwFn || kind == .KwExtern
}

fn parse_file(p: *Parser) -> err {
    try skip_separators(p)
    while p.current.kind != .Eof {
        while p.current.kind == .PunctAt { try parse_attribute(p) }
        if p.current.kind == .KwUse {
            try parse_use(p)
        } else {
            if p.current.kind == .KwError {
                try parse_error(p)
            } else {
                if is_scanned_decl(p.current.kind) {
                    let decl_kind = p.current.kind
                    try advance(p)
                    try scan_delimited_decl(p, decl_kind)
                } else {
                    ret InvalidSyntax
                }
            }
        }
        p.declarations += 1usize
    }
    if p.declarations == 0usize { ret InvalidSyntax }
    ret ok
}

fn parse(source: str) -> (Summary, err) {
    var p = init(source)
    let parse_error = parse_file(&p)
    if parse_error != ok {
        ret (Summary { root: .ErrorNode, declarations: p.declarations }, parse_error)
    }
    ret (Summary { root: .File, declarations: p.declarations }, ok)
}

fn validate(source: str) -> err {
    let (_, parse_error) = parse(source)
    ret parse_error
}
