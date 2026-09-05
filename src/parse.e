// Bounded syntax parser. Grammar productions replace scan_delimited_decl
// incrementally while preserving this token cursor, tree, and recovery contract.

use lex
use syntax

error InvalidSyntax

type Tree = struct {
    nodes: []syntax.Node,
    children: []syntax.Child,
    count: usize,
    child_count: usize,
    errors: usize,
}

fn init_tree(tree: *Tree, nodes: []syntax.Node, children: []syntax.Child) -> err {
    if nodes.len == 0usize || children.len == 0usize { ret InvalidSyntax }
    tree.nodes = nodes
    tree.children = children
    tree.count = 0usize
    tree.child_count = 0usize
    tree.errors = 0usize
    ret ok
}

type Parser = struct {
    scanner: lex.Scanner,
    current: lex.Token,
    token_index: usize,
    declarations: usize,
    error_start: usize,
    last_node: usize,
    top_nodes: [256]usize,
    top_count: usize,
    tree: *Tree,
}

fn init(tree: *Tree, source: str) -> Parser {
    var p: Parser = zero
    var scanner = lex.init(source)
    p.scanner = scanner
    p.current = lex.next(&p.scanner)
    p.tree = tree
    p.tree.count = 1usize
    p.tree.child_count = 0usize
    p.tree.errors = 0usize
    p.tree.nodes[0usize] = syntax.node(.File, 0usize, 0usize, 1usize, 0usize)
    ret p
}

fn advance(p: *Parser) -> err {
    if p.current.kind == .Invalid { ret InvalidSyntax }
    if p.current.kind != .Eof {
        p.current = lex.next(&p.scanner)
        p.token_index += 1usize
    }
    if p.current.kind == .Invalid { ret InvalidSyntax }
    ret ok
}

fn add_child(p: *Parser, child: syntax.Child) -> err {
    if p.tree.child_count == p.tree.children.len { ret InvalidSyntax }
    p.tree.children[p.tree.child_count] = child
    p.tree.child_count += 1usize
    ret ok
}

fn add_node(p: *Parser, kind: syntax.Kind, token_start: usize, token_end: usize) -> err {
    if p.tree.count == p.tree.nodes.len { ret InvalidSyntax }
    let child_start = p.tree.child_count
    var token = token_start
    while token < token_end {
        try add_child(p, syntax.token_child(token))
        token += 1usize
    }
    p.last_node = p.tree.count
    p.tree.nodes[p.tree.count] = syntax.node(kind, token_start, token_end, child_start, token_end - token_start)
    p.tree.count += 1usize
    ret ok
}

fn add_top_node(p: *Parser, kind: syntax.Kind, token_start: usize, token_end: usize) -> err {
    if p.top_count == p.top_nodes.len { ret InvalidSyntax }
    try add_node(p, kind, token_start, token_end)
    p.top_nodes[p.top_count] = p.last_node
    p.top_count += 1usize
    ret ok
}

fn require(p: *Parser, expected: lex.Kind) -> err {
    if p.current.kind != expected { ret InvalidSyntax }
    try advance(p)
    ret ok
}

fn skip_separators(p: *Parser) -> err {
    while p.current.kind == .Newline {
        let scan_error = advance(p)
        if scan_error != ok { ret ok }
    }
    ret ok
}

fn finish_line(p: *Parser) -> err {
    if p.current.kind == .Eof { ret ok }
    if p.current.kind != .Newline { ret InvalidSyntax }
    try skip_separators(p)
    ret ok
}

fn parse_use(p: *Parser) -> err {
    let token_start = p.token_index
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
    try add_top_node(p, .UseDecl, token_start, p.token_index)
    try finish_line(p)
    ret ok
}

fn parse_error(p: *Parser) -> err {
    let token_start = p.token_index
    try require(p, .KwError)
    try require(p, .Identifier)
    try add_top_node(p, .ErrorDecl, token_start, p.token_index)
    try finish_line(p)
    ret ok
}

fn scan_delimited_decl(p: *Parser, decl_kind: lex.Kind, node_kind: syntax.Kind, token_start: usize) -> err {
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
            try add_top_node(p, node_kind, token_start, p.token_index)
            ret ok
        }
        if kind == .Newline && parens == 0usize && brackets == 0usize && braces == 0usize {
            if (decl_kind == .KwType || decl_kind == .KwConst) && !saw_assign { ret InvalidSyntax }
            if decl_kind == .KwFn && !saw_brace { ret InvalidSyntax }
            try add_top_node(p, node_kind, token_start, p.token_index)
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
    let token_start = p.token_index
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
    try add_top_node(p, .Attribute, token_start, p.token_index)
    try skip_separators(p)
    ret ok
}

fn is_scanned_decl(kind: lex.Kind) -> bool {
    ret kind == .KwType || kind == .KwConst || kind == .KwVar || kind == .KwFn || kind == .KwExtern
}

fn node_kind_for_decl(kind: lex.Kind) -> syntax.Kind {
    if kind == .KwType { ret .TypeDecl }
    if kind == .KwConst { ret .ConstDecl }
    if kind == .KwVar { ret .VarDecl }
    if kind == .KwFn { ret .FnDecl }
    ret .ExternDecl
}

fn parse_one(p: *Parser) -> err {
    while p.current.kind == .PunctAt { try parse_attribute(p) }
    p.error_start = p.token_index
    if p.current.kind == .KwUse {
        try parse_use(p)
    } else {
        if p.current.kind == .KwError {
            try parse_error(p)
        } else {
            if is_scanned_decl(p.current.kind) {
                let token_start = p.token_index
                let decl_kind = p.current.kind
                let node_kind = node_kind_for_decl(decl_kind)
                try advance(p)
                try scan_delimited_decl(p, decl_kind, node_kind, token_start)
            } else {
                ret InvalidSyntax
            }
        }
    }
    p.declarations += 1usize
    ret ok
}

fn recover_top(p: *Parser) -> err {
    while p.current.kind != .Newline && p.current.kind != .Eof {
        p.current = lex.next(&p.scanner)
        p.token_index += 1usize
    }
    while p.current.kind == .Newline {
        p.current = lex.next(&p.scanner)
        p.token_index += 1usize
    }
    ret ok
}

fn parse_file(p: *Parser) -> err {
    try skip_separators(p)
    while p.current.kind != .Eof {
        p.error_start = p.token_index
        let item_error = parse_one(p)
        if item_error != ok {
            p.tree.errors += 1usize
            let node_error = add_top_node(p, .ErrorNode, p.error_start, p.token_index + 1usize)
            if node_error != ok { ret node_error }
            try recover_top(p)
        }
    }
    if p.declarations == 0usize && p.tree.errors == 0usize {
        p.tree.errors = 1usize
        try add_top_node(p, .ErrorNode, p.token_index, p.token_index)
    }
    p.tree.nodes[0usize].token_end = p.token_index + 1usize
    p.tree.nodes[0usize].first_child = p.tree.child_count
    var token = 0usize
    var top = 0usize
    while top < p.top_count {
        let node_index = p.top_nodes[top]
        while token < p.tree.nodes[node_index].token_start {
            try add_child(p, syntax.token_child(token))
            token += 1usize
        }
        try add_child(p, syntax.node_child(node_index))
        token = p.tree.nodes[node_index].token_end
        top += 1usize
    }
    while token <= p.token_index {
        try add_child(p, syntax.token_child(token))
        token += 1usize
    }
    p.tree.nodes[0usize].child_count = p.tree.child_count - p.tree.nodes[0usize].first_child
    if p.tree.errors != 0usize { ret InvalidSyntax }
    ret ok
}

fn parse(tree: *Tree, source: str) -> err {
    if tree.nodes.len == 0usize || tree.children.len == 0usize { ret InvalidSyntax }
    var p = init(tree, source)
    ret parse_file(&p)
}

fn validate(source: str) -> err {
    var nodes: [16]syntax.Node = zero
    var children: [64]syntax.Child = zero
    var tree: Tree = zero
    try init_tree(&tree, nodes[..], children[..])
    ret parse(&tree, source)
}
