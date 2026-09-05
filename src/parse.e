// Bounded grammar-revision-1 syntax parser with a lossless tree and local recovery.

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
    error_node_checkpoint: usize,
    error_child_checkpoint: usize,
    error_errors_checkpoint: usize,
    error_declarations_checkpoint: usize,
    error_soft_checkpoint: usize,
    soft_depth: usize,
    soft_top_barrier: bool,
    block_expression: bool,
    block_expression_soft_depth: usize,
    last_node: usize,
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

fn add_parent_node(p: *Parser, kind: syntax.Kind, token_start: usize, token_end: usize, nested: []usize) -> err {
    if p.tree.count == p.tree.nodes.len { ret InvalidSyntax }
    let child_start = p.tree.child_count
    var token = token_start
    var child = 0usize
    while child < nested.len {
        let node_index = nested[child]
        if p.tree.nodes[node_index].token_start < token { ret InvalidSyntax }
        while token < p.tree.nodes[node_index].token_start {
            try add_child(p, syntax.token_child(token))
            token += 1usize
        }
        try add_child(p, syntax.node_child(node_index))
        p.tree.nodes[node_index].parented = true
        token = p.tree.nodes[node_index].token_end
        child += 1usize
    }
    while token < token_end {
        try add_child(p, syntax.token_child(token))
        token += 1usize
    }
    p.last_node = p.tree.count
    p.tree.nodes[p.tree.count] = syntax.node(kind, token_start, token_end, child_start, p.tree.child_count - child_start)
    p.tree.count += 1usize
    ret ok
}

fn add_parent_since(p: *Parser, kind: syntax.Kind, token_start: usize, token_end: usize, node_start: usize) -> err {
    if p.tree.count == p.tree.nodes.len || node_start > p.tree.count { ret InvalidSyntax }
    let child_start = p.tree.child_count
    var token = token_start
    var node_index = node_start
    while node_index < p.tree.count {
        if !p.tree.nodes[node_index].parented && !p.tree.nodes[node_index].top_level {
            if p.tree.nodes[node_index].token_start < token { ret InvalidSyntax }
            while token < p.tree.nodes[node_index].token_start {
                try add_child(p, syntax.token_child(token))
                token += 1usize
            }
            try add_child(p, syntax.node_child(node_index))
            p.tree.nodes[node_index].parented = true
            token = p.tree.nodes[node_index].token_end
        }
        node_index += 1usize
    }
    while token < token_end {
        try add_child(p, syntax.token_child(token))
        token += 1usize
    }
    p.last_node = p.tree.count
    p.tree.nodes[p.tree.count] = syntax.node(kind, token_start, token_end, child_start, p.tree.child_count - child_start)
    p.tree.count += 1usize
    ret ok
}

fn add_top_node(p: *Parser, kind: syntax.Kind, token_start: usize, token_end: usize) -> err {
    try add_node(p, kind, token_start, token_end)
    p.tree.nodes[p.last_node].top_level = true
    ret ok
}

fn add_top_parent(p: *Parser, kind: syntax.Kind, token_start: usize, token_end: usize, nested: []usize) -> err {
    try add_parent_node(p, kind, token_start, token_end, nested)
    p.tree.nodes[p.last_node].top_level = true
    ret ok
}

fn add_top_parent_since(p: *Parser, kind: syntax.Kind, token_start: usize, token_end: usize, node_start: usize) -> err {
    try add_parent_since(p, kind, token_start, token_end, node_start)
    p.tree.nodes[p.last_node].top_level = true
    ret ok
}

fn require(p: *Parser, expected: lex.Kind) -> err {
    if p.current.kind != expected { ret InvalidSyntax }
    try advance(p)
    ret ok
}

fn is_top_barrier(kind: lex.Kind) -> bool {
    ret kind == .KwUse || kind == .KwType || kind == .KwConst || kind == .KwVar || kind == .KwFn || kind == .KwError || kind == .KwExtern || kind == .PunctAt
}

fn soft_barrier_follows(p: *Parser) -> bool {
    var look = p.scanner
    var following = lex.next(&look)
    while following.kind == .Newline { following = lex.next(&look) }
    if following.kind == .Eof || following.kind == .KwCase || following.kind == .KwDefault { ret true }
    if following.column == 1usize && is_top_barrier(following.kind) {
        p.soft_top_barrier = true
        ret true
    }
    ret false
}

fn skip_separators(p: *Parser) -> err {
    while p.current.kind == .Newline {
        if p.soft_depth != 0usize && soft_barrier_follows(p) { ret InvalidSyntax }
        let scan_error = advance(p)
        if scan_error != ok { ret ok }
    }
    ret ok
}

fn enter_soft(p: *Parser) {
    p.soft_depth += 1usize
}

fn leave_soft(p: *Parser) -> err {
    if p.soft_depth == 0usize { ret InvalidSyntax }
    p.soft_depth = p.soft_depth - 1usize
    ret ok
}

fn skip_soft(p: *Parser) -> err {
    if p.soft_depth != 0usize { try skip_separators(p) }
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

fn parse_parameter_node(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [1]usize = zero
    var nested_count = 0usize
    if p.current.kind == .PunctEllipsis {
        try advance(p)
    } else {
        try require(p, .Identifier)
        try skip_soft(p)
        try require(p, .PunctColon)
        try skip_soft(p)
        if p.current.kind == .PunctEllipsis {
            try advance(p)
        } else {
            var has_type_node = false
            try parse_type_node(p, &has_type_node)
            if has_type_node {
                nested[0usize] = p.last_node
                nested_count = 1usize
            }
        }
    }
    try add_parent_node(p, .Parameter, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_comptime_node(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [1]usize = zero
    var nested_count = 0usize
    try require(p, .Identifier)
    try skip_soft(p)
    try require(p, .PunctColon)
    try skip_soft(p)
    if p.current.kind == .KwType {
        try advance(p)
    } else {
        if p.current.kind == .KwFn {
            var look = p.scanner
            var following = lex.next(&look)
            while following.kind == .Newline { following = lex.next(&look) }
            if following.kind != .PunctLParen {
                try advance(p)
            } else {
                var has_type_node = false
                try parse_type_node(p, &has_type_node)
                if has_type_node {
                    nested[0usize] = p.last_node
                    nested_count = 1usize
                }
            }
        } else {
            var has_type_node = false
            try parse_type_node(p, &has_type_node)
            if has_type_node {
                nested[0usize] = p.last_node
                nested_count = 1usize
            }
        }
    }
    try add_parent_node(p, .ComptimeParam, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_return_spec(p: *Parser, is_extern: bool) -> err {
    try parse_type_return_spec_node(p)
    if is_extern {
        if p.current.kind != .Newline && p.current.kind != .Eof { ret InvalidSyntax }
    } else {
        if p.current.kind != .PunctLBrace { ret InvalidSyntax }
    }
    ret ok
}

fn binary_precedence(kind: lex.Kind) -> usize {
    if kind == .PunctOrOr { ret 1usize }
    if kind == .PunctAndAnd { ret 2usize }
    if kind == .PunctEqEq || kind == .PunctBangEq || kind == .PunctLt || kind == .PunctLtEq || kind == .PunctGt || kind == .PunctGtEq { ret 3usize }
    if kind == .PunctPipe { ret 4usize }
    if kind == .PunctCaret { ret 5usize }
    if kind == .PunctAmp { ret 6usize }
    if kind == .PunctShiftLeft || kind == .PunctShiftRight { ret 7usize }
    if kind == .PunctPlus || kind == .PunctMinus || kind == .PunctAddWrap || kind == .PunctSubWrap { ret 8usize }
    if kind == .PunctStar || kind == .PunctSlash || kind == .PunctPercent || kind == .PunctMulWrap { ret 9usize }
    ret 0usize
}

fn is_prefix_op(kind: lex.Kind) -> bool {
    ret kind == .PunctMinus || kind == .PunctBang || kind == .PunctTilde || kind == .PunctAmp || kind == .PunctStar
}

fn is_literal(kind: lex.Kind) -> bool {
    ret kind == .Integer || kind == .Float || kind == .String || kind == .RawString || kind == .Character || kind == .KwTrue || kind == .KwFalse || kind == .KwNil || kind == .KwOk || kind == .KwZero || kind == .KwUndef
}

fn parse_expression_node(p: *Parser) -> err {
    try skip_soft(p)
    ret parse_binary_node(p, 1usize)
}

fn parse_block_expression_node(p: *Parser) -> err {
    let previous = p.block_expression
    let previous_depth = p.block_expression_soft_depth
    p.block_expression = true
    p.block_expression_soft_depth = p.soft_depth
    let result = parse_expression_node(p)
    p.block_expression = previous
    p.block_expression_soft_depth = previous_depth
    ret result
}

fn named_aggregate_follows(p: *Parser) -> bool {
    var look = p.scanner
    var pascal = identifier_is_pascal(p)
    var token = lex.next(&look)
    if p.soft_depth != 0usize {
        while token.kind == .Newline { token = lex.next(&look) }
    }
    while token.kind == .PunctDot {
        token = lex.next(&look)
        if p.soft_depth != 0usize {
            while token.kind == .Newline { token = lex.next(&look) }
        }
        if token.kind != .Identifier { ret false }
        pascal = token_is_pascal(p, token)
        token = lex.next(&look)
        if p.soft_depth != 0usize {
            while token.kind == .Newline { token = lex.next(&look) }
        }
    }
    if token.kind == .PunctLBracket {
        var depth = 1usize
        while depth != 0usize {
            token = lex.next(&look)
            if token.kind == .Invalid || token.kind == .Eof { ret false }
            if token.kind == .PunctLBracket { depth += 1usize }
            if token.kind == .PunctRBracket { depth = depth - 1usize }
        }
        token = lex.next(&look)
        if p.soft_depth != 0usize {
            while token.kind == .Newline { token = lex.next(&look) }
        }
    }
    if p.block_expression && p.soft_depth == p.block_expression_soft_depth && token.kind == .PunctLBrace {
        ret false
    }
    ret pascal && token.kind == .PunctLBrace
}

fn identifier_is_pascal(p: *Parser) -> bool {
    ret token_is_pascal(p, p.current)
}

fn token_is_pascal(p: *Parser, token: lex.Token) -> bool {
    if token.kind != .Identifier { ret false }
    let first = p.scanner.source[token.start]
    if first < 65u8 || first > 90u8 { ret false }
    if token.end == token.start + 1usize { ret true }
    var has_lower = false
    var i = token.start + 1usize
    while i < token.end {
        let byte = p.scanner.source[i]
        if byte == 95u8 { ret false }
        if byte >= 97u8 && byte <= 122u8 { has_lower = true }
        i += 1usize
    }
    ret has_lower
}

fn parse_literal_item_node(p: *Parser, allow_bare_member: bool) -> err {
    let token_start = p.token_index
    var nested: [1]usize = zero
    if p.current.kind == .Identifier {
        var look = p.scanner
        var following = lex.next(&look)
        while following.kind == .Newline { following = lex.next(&look) }
        if following.kind == .PunctColon {
            try advance(p)
            try skip_separators(p)
            try require(p, .PunctColon)
            try skip_separators(p)
            try parse_expression_node(p)
            nested[0usize] = p.last_node
            try add_parent_node(p, .LiteralItem, token_start, p.token_index, nested[..])
            ret ok
        }
        if allow_bare_member && identifier_is_pascal(p) {
            try advance(p)
            try add_node(p, .LiteralItem, token_start, p.token_index)
            ret ok
        }
    }
    try parse_expression_node(p)
    nested[0usize] = p.last_node
    try add_parent_node(p, .LiteralItem, token_start, p.token_index, nested[..])
    ret ok
}

fn parse_aggregate_literal_node(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    var allow_bare_member = false
    if p.current.kind == .Identifier {
        allow_bare_member = true
        try parse_named_type_node(p)
    } else {
        var has_type_node = false
        try parse_type_node(p, &has_type_node)
        if !has_type_node || p.tree.nodes[p.last_node].kind != .ArrayType { ret InvalidSyntax }
    }
    try require(p, .PunctLBrace)
    enter_soft(p)
    try skip_separators(p)
    if p.current.kind == .PunctRBrace { ret InvalidSyntax }
    while p.current.kind != .PunctRBrace {
        try parse_literal_item_node(p, allow_bare_member)
        try skip_separators(p)
        if p.current.kind == .PunctComma {
            try advance(p)
            try skip_separators(p)
        } else {
            if p.current.kind != .PunctRBrace { ret InvalidSyntax }
        }
    }
    try leave_soft(p)
    try advance(p)
    try add_parent_since(p, .AggregateLiteral, token_start, p.token_index, node_start)
    ret ok
}

fn parse_primary_node(p: *Parser) -> err {
    let token_start = p.token_index
    if is_literal(p.current.kind) {
        try advance(p)
        try add_node(p, .LiteralExpr, token_start, p.token_index)
        ret ok
    }
    if p.current.kind == .Identifier && named_aggregate_follows(p) {
        ret parse_aggregate_literal_node(p)
    }
    if p.current.kind == .PunctLBracket {
        ret parse_aggregate_literal_node(p)
    }
    if p.current.kind == .Identifier || p.current.kind == .KwUnreachable {
        try advance(p)
        try add_node(p, .NameExpr, token_start, p.token_index)
        ret ok
    }
    if p.current.kind == .PunctDot {
        try advance(p)
        try skip_soft(p)
        try require(p, .Identifier)
        try add_node(p, .MemberExpr, token_start, p.token_index)
        ret ok
    }
    if p.current.kind == .PunctLParen {
        var nested: [1]usize = zero
        try advance(p)
        enter_soft(p)
        try skip_separators(p)
        try parse_expression_node(p)
        nested[0usize] = p.last_node
        try skip_separators(p)
        try leave_soft(p)
        try require(p, .PunctRParen)
        try add_parent_node(p, .GroupExpr, token_start, p.token_index, nested[..])
        ret ok
    }
    ret InvalidSyntax
}

fn parse_call_postfix(p: *Parser, receiver: usize) -> err {
    let token_start = p.tree.nodes[receiver].token_start
    let node_start = receiver
    try require(p, .PunctLParen)
    enter_soft(p)
    try skip_separators(p)
    while p.current.kind != .PunctRParen {
        try parse_expression_node(p)
        try skip_separators(p)
        if p.current.kind == .PunctComma {
            try advance(p)
            try skip_separators(p)
        } else {
            if p.current.kind != .PunctRParen { ret InvalidSyntax }
        }
    }
    try leave_soft(p)
    try advance(p)
    try add_parent_since(p, .CallExpr, token_start, p.token_index, node_start)
    ret ok
}

fn bracket_argument_is_type(p: *Parser) -> bool {
    if p.current.kind == .KwFn || p.current.kind == .KwExtern { ret true }
    if p.current.kind == .PunctStar {
        var pointer_look = p.scanner
        var pointer_token = lex.next(&pointer_look)
        while pointer_token.kind == .Newline { pointer_token = lex.next(&pointer_look) }
        ret pointer_token.kind == .KwConst || pointer_token.kind == .KwShared
    }
    if p.current.kind != .PunctLBracket { ret false }
    var look = p.scanner
    var brackets = 1usize
    var parens = 0usize
    while true {
        let token = lex.next(&look)
        if token.kind == .Invalid || token.kind == .Eof { ret false }
        if token.kind == .PunctLBracket { brackets += 1usize }
        if token.kind == .PunctRBracket {
            if brackets == 0usize { ret true }
            brackets = brackets - 1usize
        }
        if token.kind == .PunctLParen { parens += 1usize }
        if token.kind == .PunctRParen && parens != 0usize { parens = parens - 1usize }
        if brackets == 0usize && parens == 0usize {
            if token.kind == .PunctLBrace { ret false }
            if token.kind == .PunctComma { ret true }
        }
    }
    ret false
}

fn parse_bracket_argument_node(p: *Parser) -> err {
    if bracket_argument_is_type(p) {
        var has_type_node = false
        try parse_type_node(p, &has_type_node)
        if !has_type_node { ret InvalidSyntax }
        ret ok
    }
    ret parse_expression_node(p)
}

fn parse_bracket_postfix(p: *Parser, receiver: usize) -> err {
    let token_start = p.tree.nodes[receiver].token_start
    let node_start = receiver
    try require(p, .PunctLBracket)
    enter_soft(p)
    try skip_separators(p)
    if p.current.kind == .PunctRange {
        try advance(p)
        try skip_separators(p)
        if p.current.kind != .PunctRBracket {
            try parse_bracket_argument_node(p)
            try skip_separators(p)
        }
    } else {
        if p.current.kind != .PunctRBracket {
            try parse_bracket_argument_node(p)
            try skip_separators(p)
            if p.current.kind == .PunctRange {
                try advance(p)
                try skip_separators(p)
                if p.current.kind != .PunctRBracket {
                    try parse_bracket_argument_node(p)
                    try skip_separators(p)
                }
            } else {
                while p.current.kind == .PunctComma {
                    try advance(p)
                    try skip_separators(p)
                    if p.current.kind == .PunctRBracket { break }
                    try parse_bracket_argument_node(p)
                    try skip_separators(p)
                }
            }
        }
    }
    try skip_separators(p)
    try leave_soft(p)
    try require(p, .PunctRBracket)
    try add_parent_since(p, .BracketPostfix, token_start, p.token_index, node_start)
    ret ok
}

fn parse_postfix_node(p: *Parser) -> err {
    try parse_primary_node(p)
    try skip_soft(p)
    while p.current.kind == .PunctDot || p.current.kind == .PunctLParen || p.current.kind == .PunctLBracket {
        let receiver = p.last_node
        if p.current.kind == .PunctDot {
            let token_start = p.tree.nodes[receiver].token_start
            var nested: [1]usize = zero
            nested[0usize] = receiver
            try advance(p)
            try skip_soft(p)
            try require(p, .Identifier)
            try add_parent_node(p, .FieldExpr, token_start, p.token_index, nested[..])
        } else {
            if p.current.kind == .PunctLParen {
                try parse_call_postfix(p, receiver)
            } else {
                try parse_bracket_postfix(p, receiver)
            }
        }
        try skip_soft(p)
    }
    ret ok
}

fn parse_prefix_node(p: *Parser) -> err {
    try skip_soft(p)
    if is_prefix_op(p.current.kind) {
        let token_start = p.token_index
        var nested: [1]usize = zero
        try advance(p)
        try skip_soft(p)
        try parse_prefix_node(p)
        nested[0usize] = p.last_node
        try add_parent_node(p, .UnaryExpr, token_start, p.tree.nodes[p.last_node].token_end, nested[..])
        ret ok
    }
    ret parse_postfix_node(p)
}

fn parse_binary_node(p: *Parser, minimum: usize) -> err {
    try skip_soft(p)
    try parse_prefix_node(p)
    var left = p.last_node
    try skip_soft(p)
    while binary_precedence(p.current.kind) >= minimum {
        let precedence = binary_precedence(p.current.kind)
        var nested: [2]usize = zero
        nested[0usize] = left
        try advance(p)
        try skip_soft(p)
        try parse_binary_node(p, precedence + 1usize)
        try skip_soft(p)
        nested[1usize] = p.last_node
        try add_parent_node(p, .BinaryExpr, p.tree.nodes[left].token_start, p.tree.nodes[p.last_node].token_end, nested[..])
        left = p.last_node
        if precedence == 3usize && binary_precedence(p.current.kind) == 3usize { ret InvalidSyntax }
    }
    ret ok
}

fn parse_named_type_node(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    try require(p, .Identifier)
    try skip_soft(p)
    while p.current.kind == .PunctDot {
        try advance(p)
        try skip_soft(p)
        try require(p, .Identifier)
        try skip_soft(p)
    }
    if p.current.kind == .PunctLBracket {
        try advance(p)
        enter_soft(p)
        try skip_separators(p)
        while p.current.kind != .PunctRBracket {
            try parse_expression_node(p)
            try skip_separators(p)
            if p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
            } else {
                if p.current.kind != .PunctRBracket { ret InvalidSyntax }
            }
        }
        try leave_soft(p)
        try advance(p)
    }
    try add_parent_since(p, .NamedType, token_start, p.token_index, node_start)
    ret ok
}

fn parse_type_parameter_node(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [1]usize = zero
    var nested_count = 0usize
    if p.current.kind == .PunctEllipsis {
        try advance(p)
    } else {
        if p.current.kind == .Identifier {
            var look = p.scanner
            var following = lex.next(&look)
            while following.kind == .Newline { following = lex.next(&look) }
            if following.kind == .PunctColon {
                try advance(p)
                try skip_soft(p)
                try require(p, .PunctColon)
                try skip_soft(p)
            }
        }
        var has_type_node = false
        try parse_type_node(p, &has_type_node)
        if has_type_node {
            nested[0usize] = p.last_node
            nested_count = 1usize
        }
    }
    try add_parent_node(p, .Parameter, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_type_return_spec_node(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    var type_count = 0usize
    if p.current.kind == .PunctLParen {
        try advance(p)
        enter_soft(p)
        try skip_separators(p)
        while p.current.kind != .PunctRParen {
            var has_type_node = false
            try parse_type_node(p, &has_type_node)
            type_count += 1usize
            try skip_separators(p)
            if p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
            } else {
                if p.current.kind != .PunctRParen { ret InvalidSyntax }
            }
        }
        if type_count < 2usize { ret InvalidSyntax }
        try leave_soft(p)
        try advance(p)
    } else {
        var has_type_node = false
        try parse_type_node(p, &has_type_node)
        type_count = 1usize
    }
    try add_parent_since(p, .ReturnSpec, token_start, p.token_index, node_start)
    ret ok
}

fn parse_function_type_node(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    if p.current.kind == .KwExtern {
        try advance(p)
        try skip_soft(p)
    }
    try require(p, .KwFn)
    try skip_soft(p)
    try require(p, .PunctLParen)
    enter_soft(p)
    try skip_separators(p)
    while p.current.kind != .PunctRParen {
        try parse_type_parameter_node(p)
        try skip_separators(p)
        if p.current.kind == .PunctComma {
            try advance(p)
            try skip_separators(p)
        } else {
            if p.current.kind != .PunctRParen { ret InvalidSyntax }
        }
    }
    try leave_soft(p)
    try advance(p)
    try skip_soft(p)
    if p.current.kind == .PunctArrow {
        try advance(p)
        try skip_soft(p)
        try parse_type_return_spec_node(p)
    }
    try add_parent_since(p, .FunctionType, token_start, p.token_index, node_start)
    ret ok
}

fn parse_type_node(p: *Parser, has_node: *bool) -> err {
    let token_start = p.token_index
    var nested: [2]usize = zero
    var nested_count = 0usize
    *has_node = true
    if p.current.kind == .PunctStar {
        try advance(p)
        try skip_soft(p)
        if p.current.kind == .KwConst { try advance(p) }
        try skip_soft(p)
        if p.current.kind == .KwShared { try advance(p) }
        try skip_soft(p)
        var has_inner = false
        try parse_type_node(p, &has_inner)
        if has_inner {
            nested[0usize] = p.last_node
            nested_count = 1usize
        }
        try add_parent_node(p, .PointerType, token_start, p.token_index, nested[..nested_count])
        ret ok
    }
    if p.current.kind == .PunctLBracket {
        try advance(p)
        enter_soft(p)
        try skip_separators(p)
        if p.current.kind == .PunctRBracket {
            try leave_soft(p)
            try advance(p)
            try skip_soft(p)
            if p.current.kind == .KwConst { try advance(p) }
            try skip_soft(p)
            if p.current.kind == .KwShared { try advance(p) }
            try skip_soft(p)
            var has_inner = false
            try parse_type_node(p, &has_inner)
            if has_inner {
                nested[0usize] = p.last_node
                nested_count = 1usize
            }
            try add_parent_node(p, .SliceType, token_start, p.token_index, nested[..nested_count])
            ret ok
        }
        if p.current.kind == .PunctUnderscore {
            try advance(p)
        } else {
            try parse_expression_node(p)
            nested[0usize] = p.last_node
            nested_count = 1usize
        }
        try skip_separators(p)
        try leave_soft(p)
        try require(p, .PunctRBracket)
        try skip_soft(p)
        var has_inner = false
        try parse_type_node(p, &has_inner)
        if has_inner {
            nested[nested_count] = p.last_node
            nested_count += 1usize
        }
        try add_parent_node(p, .ArrayType, token_start, p.token_index, nested[..nested_count])
        ret ok
    }
    if p.current.kind == .KwExtern || p.current.kind == .KwFn {
        ret parse_function_type_node(p)
    }
    if p.current.kind == .KwType {
        try advance(p)
        *has_node = false
        ret ok
    }
    if p.current.kind == .Identifier { ret parse_named_type_node(p) }
    ret InvalidSyntax
}

fn parse_return_statement(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    try require(p, .KwRet)
    if p.current.kind == .PunctLParen {
        let group_start = p.token_index
        let group_node_start = p.tree.count
        try advance(p)
        enter_soft(p)
        try skip_separators(p)
        if p.current.kind == .PunctRParen { ret InvalidSyntax }
        try parse_expression_node(p)
        try skip_separators(p)
        if p.current.kind == .PunctComma {
            while p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
                if p.current.kind == .PunctRParen { break }
                try parse_expression_node(p)
                try skip_separators(p)
            }
            try leave_soft(p)
            try require(p, .PunctRParen)
        } else {
            try leave_soft(p)
            try require(p, .PunctRParen)
            try add_parent_since(p, .GroupExpr, group_start, p.token_index, group_node_start)
        }
    } else {
        if p.current.kind != .Newline && p.current.kind != .PunctRBrace {
            try parse_expression_node(p)
        }
    }
    if p.current.kind != .Newline && p.current.kind != .PunctRBrace { ret InvalidSyntax }
    try add_parent_since(p, .ReturnStmt, token_start, p.token_index, node_start)
    ret ok
}

fn at_statement_end(p: *Parser) -> bool {
    ret p.current.kind == .Newline || p.current.kind == .PunctRBrace
}

fn parse_binding_node(p: *Parser) -> err {
    let token_start = p.token_index
    if p.current.kind == .Identifier || p.current.kind == .PunctUnderscore {
        try advance(p)
    } else {
        try require(p, .PunctLParen)
        enter_soft(p)
        try skip_separators(p)
        var items = 0usize
        while true {
            if p.current.kind != .Identifier && p.current.kind != .PunctUnderscore { ret InvalidSyntax }
            try advance(p)
            items += 1usize
            try skip_separators(p)
            if p.current.kind != .PunctComma { break }
            try advance(p)
            try skip_separators(p)
            if p.current.kind == .PunctRParen { break }
        }
        if items < 2usize { ret InvalidSyntax }
        try skip_separators(p)
        try leave_soft(p)
        try require(p, .PunctRParen)
    }
    try add_node(p, .Binding, token_start, p.token_index)
    ret ok
}

fn parse_initializer_node(p: *Parser) -> err {
    if p.current.kind == .KwZero || p.current.kind == .KwUndef {
        try advance(p)
        ret ok
    }
    if p.current.kind == .KwTry {
        try advance(p)
        try parse_postfix_node(p)
        if p.tree.nodes[p.last_node].kind != .CallExpr { ret InvalidSyntax }
        ret ok
    }
    ret parse_expression_node(p)
}

fn parse_binding_statement(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [3]usize = zero
    var nested_count = 1usize
    try advance(p)
    try parse_binding_node(p)
    nested[0usize] = p.last_node
    if p.current.kind == .PunctColon {
        try advance(p)
        var has_type_node = false
        try parse_type_node(p, &has_type_node)
        if has_type_node {
            nested[nested_count] = p.last_node
            nested_count += 1usize
        }
    }
    try require(p, .PunctAssign)
    let initializer_has_node = p.current.kind != .KwZero && p.current.kind != .KwUndef
    try parse_initializer_node(p)
    if initializer_has_node {
        nested[nested_count] = p.last_node
        nested_count += 1usize
    }
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_node(p, .BindingStmt, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_try_statement(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [1]usize = zero
    try require(p, .KwTry)
    try parse_postfix_node(p)
    if p.tree.nodes[p.last_node].kind != .CallExpr || !at_statement_end(p) { ret InvalidSyntax }
    nested[0usize] = p.last_node
    try add_parent_node(p, .TryStmt, token_start, p.token_index, nested[..])
    ret ok
}

fn tuple_assignment_follows(p: *Parser) -> bool {
    var look = p.scanner
    var parens = 1usize
    var brackets = 0usize
    var braces = 0usize
    var saw_comma = false
    while parens != 0usize {
        let token = lex.next(&look)
        if token.kind == .Invalid || token.kind == .Eof { ret false }
        if token.kind == .PunctLParen { parens += 1usize }
        if token.kind == .PunctRParen { parens = parens - 1usize }
        if token.kind == .PunctLBracket { brackets += 1usize }
        if token.kind == .PunctRBracket {
            if brackets == 0usize { ret false }
            brackets = brackets - 1usize
        }
        if token.kind == .PunctLBrace { braces += 1usize }
        if token.kind == .PunctRBrace {
            if braces == 0usize { ret false }
            braces = braces - 1usize
        }
        if token.kind == .PunctComma && parens == 1usize && brackets == 0usize && braces == 0usize { saw_comma = true }
    }
    if !saw_comma { ret false }
    let following = lex.next(&look)
    ret is_assignment_op(following.kind)
}

fn is_assignment_target_kind(kind: syntax.Kind) -> bool {
    ret kind == .NameExpr || kind == .FieldExpr || kind == .BracketPostfix || kind == .GroupExpr || kind == .UnaryExpr
}

fn parse_place_node(p: *Parser) -> err {
    if p.current.kind != .PunctStar { ret parse_postfix_node(p) }
    let token_start = p.token_index
    var nested: [1]usize = zero
    try advance(p)
    try skip_soft(p)
    try parse_place_node(p)
    nested[0usize] = p.last_node
    try add_parent_node(p, .UnaryExpr, token_start, p.tree.nodes[p.last_node].token_end, nested[..])
    ret ok
}

fn parse_tuple_assignment_statement(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    var place_count = 0usize
    try require(p, .PunctLParen)
    enter_soft(p)
    try skip_separators(p)
    while p.current.kind != .PunctRParen {
        try parse_place_node(p)
        if !is_assignment_target_kind(p.tree.nodes[p.last_node].kind) { ret InvalidSyntax }
        place_count += 1usize
        try skip_separators(p)
        if p.current.kind == .PunctComma {
            try advance(p)
            try skip_separators(p)
        } else {
            if p.current.kind != .PunctRParen { ret InvalidSyntax }
        }
    }
    if place_count < 2usize { ret InvalidSyntax }
    try leave_soft(p)
    try advance(p)
    if !is_assignment_op(p.current.kind) { ret InvalidSyntax }
    try advance(p)
    if p.current.kind == .KwUndef { ret InvalidSyntax }
    try parse_initializer_node(p)
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_since(p, .AssignmentStmt, token_start, p.token_index, node_start)
    ret ok
}

fn parse_expression_statement(p: *Parser) -> err {
    if p.current.kind == .PunctLParen && tuple_assignment_follows(p) {
        ret parse_tuple_assignment_statement(p)
    }
    let token_start = p.token_index
    var nested: [2]usize = zero
    var nested_count = 1usize
    let explicit_deref = p.current.kind == .PunctStar
    if explicit_deref {
        try parse_place_node(p)
    } else {
        try parse_expression_node(p)
    }
    nested[0usize] = p.last_node
    if is_assignment_op(p.current.kind) {
        if !is_assignment_target_kind(p.tree.nodes[p.last_node].kind) { ret InvalidSyntax }
        if p.tree.nodes[p.last_node].kind == .UnaryExpr && !explicit_deref { ret InvalidSyntax }
        try advance(p)
        if p.current.kind == .KwUndef { ret InvalidSyntax }
        let initializer_has_node = p.current.kind != .KwZero
        try parse_initializer_node(p)
        if initializer_has_node {
            nested[nested_count] = p.last_node
            nested_count += 1usize
        }
        if !at_statement_end(p) { ret InvalidSyntax }
        try add_parent_node(p, .AssignmentStmt, token_start, p.token_index, nested[..nested_count])
        ret ok
    }
    if p.tree.nodes[p.last_node].kind != .CallExpr || !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_node(p, .CallStmt, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_if_statement(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [3]usize = zero
    var nested_count = 0usize
    try require(p, .KwIf)
    try parse_block_expression_node(p)
    nested[nested_count] = p.last_node
    nested_count += 1usize
    try parse_block_node(p)
    nested[nested_count] = p.last_node
    nested_count += 1usize
    if p.current.kind == .KwElse {
        try advance(p)
        if p.current.kind == .KwIf {
            try parse_if_statement(p)
        } else {
            try parse_block_node(p)
        }
        nested[nested_count] = p.last_node
        nested_count += 1usize
    }
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_node(p, .IfStmt, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_while_statement(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [2]usize = zero
    try require(p, .KwWhile)
    try parse_block_expression_node(p)
    nested[0usize] = p.last_node
    try parse_block_node(p)
    nested[1usize] = p.last_node
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_node(p, .WhileStmt, token_start, p.token_index, nested[..])
    ret ok
}

fn parse_when_statement(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [3]usize = zero
    var nested_count = 2usize
    try require(p, .KwWhen)
    try parse_block_expression_node(p)
    nested[0usize] = p.last_node
    try parse_block_node(p)
    nested[1usize] = p.last_node
    if p.current.kind == .KwElse {
        try advance(p)
        try parse_block_node(p)
        nested[2usize] = p.last_node
        nested_count = 3usize
    }
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_node(p, .WhenStmt, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_for_statement(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [3]usize = zero
    var nested_count = 0usize
    try require(p, .KwFor)
    if p.current.kind != .Identifier && p.current.kind != .PunctUnderscore { ret InvalidSyntax }
    try advance(p)
    if p.current.kind == .PunctComma {
        try advance(p)
        if p.current.kind != .Identifier && p.current.kind != .PunctUnderscore { ret InvalidSyntax }
        try advance(p)
    }
    try require(p, .KwIn)
    try parse_expression_node(p)
    nested[nested_count] = p.last_node
    nested_count += 1usize
    if p.current.kind == .PunctRange {
        try advance(p)
        try parse_block_expression_node(p)
        nested[nested_count] = p.last_node
        nested_count += 1usize
    }
    try parse_block_node(p)
    nested[nested_count] = p.last_node
    nested_count += 1usize
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_node(p, .ForStmt, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_defer_statement(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [1]usize = zero
    try require(p, .KwDefer)
    if p.current.kind == .PunctLBrace {
        try parse_block_node(p)
    } else {
        let deferred_kind = statement_kind(p)
        if deferred_kind == .BindingStmt {
            try parse_binding_statement(p)
        } else {
            if deferred_kind != .CallStmt { ret InvalidSyntax }
            try parse_expression_statement(p)
        }
    }
    nested[0usize] = p.last_node
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_node(p, .DeferStmt, token_start, p.token_index, nested[..])
    ret ok
}

fn parse_nocheck_statement(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [1]usize = zero
    try require(p, .PunctAt)
    if p.current.kind != .Identifier || !lex.text_is(p.scanner.source, p.current.start, p.current.end, "nocheck") { ret InvalidSyntax }
    try advance(p)
    try parse_block_node(p)
    nested[0usize] = p.last_node
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_node(p, .NocheckStmt, token_start, p.token_index, nested[..])
    ret ok
}

fn parse_shared_var_statement(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [2]usize = zero
    var nested_count = 0usize
    try require(p, .KwShared)
    try require(p, .KwVar)
    try require(p, .Identifier)
    try require(p, .PunctColon)
    var has_type_node = false
    try parse_type_node(p, &has_type_node)
    if has_type_node {
        nested[nested_count] = p.last_node
        nested_count += 1usize
    }
    if p.current.kind == .PunctAssign {
        try advance(p)
        let initializer_has_node = p.current.kind != .KwZero && p.current.kind != .KwUndef
        try parse_initializer_node(p)
        if initializer_has_node {
            nested[nested_count] = p.last_node
            nested_count += 1usize
        }
    }
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_node(p, .SharedVarStmt, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_keyword_statement(p: *Parser, kind: syntax.Kind) -> err {
    let token_start = p.token_index
    try advance(p)
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_node(p, kind, token_start, p.token_index)
    ret ok
}

fn parse_switch_arm_node(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    if p.current.kind == .KwDefault {
        try advance(p)
    } else {
        try require(p, .KwCase)
        while true {
            try parse_expression_node(p)
            if p.current.kind != .PunctComma { break }
            try advance(p)
        }
        if p.current.kind == .KwAs {
            try advance(p)
            try require(p, .Identifier)
        }
    }
    try require(p, .PunctColon)
    if p.current.kind != .Newline { ret InvalidSyntax }
    var leading_separators = 0usize
    while p.current.kind == .Newline {
        try advance(p)
        leading_separators += 1usize
    }
    if leading_separators < 2usize && (p.current.kind == .KwCase || p.current.kind == .KwDefault || p.current.kind == .PunctRBrace) {
        ret InvalidSyntax
    }
    while p.current.kind != .KwCase && p.current.kind != .KwDefault && p.current.kind != .PunctRBrace {
        if p.current.kind == .Eof { ret InvalidSyntax }
        let statement_start = p.token_index
        let node_checkpoint = p.tree.count
        let child_checkpoint = p.tree.child_count
        let soft_checkpoint = p.soft_depth
        let statement_error = parse_statement_node(p)
        if statement_error != ok {
            p.tree.count = node_checkpoint
            p.tree.child_count = child_checkpoint
            p.soft_depth = soft_checkpoint
            if p.soft_top_barrier { ret InvalidSyntax }
            p.tree.errors += 1usize
            var error_end = p.token_index
            if p.current.kind == .Invalid || error_end == statement_start { error_end += 1usize }
            try add_node(p, .ErrorNode, statement_start, error_end)
            try recover_statement(p)
        } else {
            if p.current.kind != .Newline { ret InvalidSyntax }
            try skip_separators(p)
        }
    }
    try add_parent_since(p, .SwitchArm, token_start, p.token_index, node_start)
    ret ok
}

fn parse_switch_statement(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    var arm_count = 0usize
    try require(p, .KwSwitch)
    try parse_block_expression_node(p)
    try require(p, .PunctLBrace)
    try skip_separators(p)
    while p.current.kind != .PunctRBrace {
        if p.current.kind != .KwCase && p.current.kind != .KwDefault { ret InvalidSyntax }
        try parse_switch_arm_node(p)
        arm_count += 1usize
    }
    if arm_count == 0usize { ret InvalidSyntax }
    try advance(p)
    if !at_statement_end(p) { ret InvalidSyntax }
    try add_parent_since(p, .SwitchStmt, token_start, p.token_index, node_start)
    ret ok
}

fn is_assignment_op(kind: lex.Kind) -> bool {
    ret kind == .PunctAssign || kind == .PunctAddAssign || kind == .PunctSubAssign || kind == .PunctMulAssign || kind == .PunctDivAssign || kind == .PunctRemAssign || kind == .PunctAddWrapAssign || kind == .PunctSubWrapAssign || kind == .PunctMulWrapAssign || kind == .PunctShiftLeftAssign || kind == .PunctShiftRightAssign || kind == .PunctBitAndAssign || kind == .PunctBitXorAssign || kind == .PunctBitOrAssign
}

fn is_expression_start(kind: lex.Kind) -> bool {
    ret is_literal(kind) || kind == .Identifier || kind == .KwUnreachable || kind == .PunctDot || kind == .PunctLParen || kind == .PunctLBracket || is_prefix_op(kind)
}

fn statement_kind(p: *Parser) -> syntax.Kind {
    let kind = p.current.kind
    if kind == .KwLet || kind == .KwVar { ret .BindingStmt }
    if kind == .KwRet { ret .ReturnStmt }
    if kind == .KwTry { ret .TryStmt }
    if kind == .KwDefer { ret .DeferStmt }
    if kind == .KwBreak { ret .BreakStmt }
    if kind == .KwContinue { ret .ContinueStmt }
    if kind == .KwIf { ret .IfStmt }
    if kind == .KwWhile { ret .WhileStmt }
    if kind == .KwFor { ret .ForStmt }
    if kind == .KwWhen { ret .WhenStmt }
    if kind == .KwSwitch { ret .SwitchStmt }
    if kind == .KwShared { ret .SharedVarStmt }
    if kind == .PunctAt { ret .NocheckStmt }
    if is_expression_start(kind) { ret .CallStmt }
    ret .ErrorNode
}

fn parse_statement_node(p: *Parser) -> err {
    let node_kind = statement_kind(p)
    if node_kind == .ErrorNode { ret InvalidSyntax }
    if node_kind == .ReturnStmt { ret parse_return_statement(p) }
    if node_kind == .BindingStmt { ret parse_binding_statement(p) }
    if node_kind == .TryStmt { ret parse_try_statement(p) }
    if node_kind == .CallStmt { ret parse_expression_statement(p) }
    if node_kind == .IfStmt { ret parse_if_statement(p) }
    if node_kind == .WhileStmt { ret parse_while_statement(p) }
    if node_kind == .WhenStmt { ret parse_when_statement(p) }
    if node_kind == .ForStmt { ret parse_for_statement(p) }
    if node_kind == .DeferStmt { ret parse_defer_statement(p) }
    if node_kind == .NocheckStmt { ret parse_nocheck_statement(p) }
    if node_kind == .SharedVarStmt { ret parse_shared_var_statement(p) }
    if node_kind == .BreakStmt || node_kind == .ContinueStmt { ret parse_keyword_statement(p, node_kind) }
    if node_kind == .SwitchStmt { ret parse_switch_statement(p) }
    ret InvalidSyntax
}

fn recover_statement(p: *Parser) -> err {
    while p.current.kind != .Newline && p.current.kind != .PunctRBrace && p.current.kind != .Eof {
        p.current = lex.next(&p.scanner)
        p.token_index += 1usize
    }
    try skip_separators(p)
    ret ok
}

fn parse_block_node(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    try require(p, .PunctLBrace)
    try skip_separators(p)
    while p.current.kind != .PunctRBrace {
        if p.current.kind == .Eof { ret InvalidSyntax }
        let statement_start = p.token_index
        let node_checkpoint = p.tree.count
        let child_checkpoint = p.tree.child_count
        let soft_checkpoint = p.soft_depth
        let statement_error = parse_statement_node(p)
        if statement_error != ok {
            p.tree.count = node_checkpoint
            p.tree.child_count = child_checkpoint
            p.soft_depth = soft_checkpoint
            if p.soft_top_barrier { ret InvalidSyntax }
            p.tree.errors += 1usize
            var error_end = p.token_index
            if p.current.kind == .Invalid || error_end == statement_start { error_end += 1usize }
            try add_node(p, .ErrorNode, statement_start, error_end)
            try recover_statement(p)
        } else {
            try skip_separators(p)
        }
    }
    try advance(p)
    try add_parent_since(p, .Block, token_start, p.token_index, node_start)
    ret ok
}

fn parse_function(p: *Parser, is_extern: bool) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    if is_extern { try require(p, .KwExtern) }
    try require(p, .KwFn)
    try require(p, .Identifier)
    if p.current.kind == .PunctLBracket {
        try advance(p)
        enter_soft(p)
        try skip_separators(p)
        if p.current.kind == .PunctRBracket { ret InvalidSyntax }
        while p.current.kind != .PunctRBracket {
            try parse_comptime_node(p)
            try skip_soft(p)
            if p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
            } else {
                if p.current.kind != .PunctRBracket { ret InvalidSyntax }
            }
        }
        try leave_soft(p)
        try advance(p)
    }
    try require(p, .PunctLParen)
    enter_soft(p)
    try skip_separators(p)
    while p.current.kind != .PunctRParen {
        try parse_parameter_node(p)
        try skip_soft(p)
        if p.current.kind == .PunctComma {
            try advance(p)
            try skip_separators(p)
        } else {
            if p.current.kind != .PunctRParen { ret InvalidSyntax }
        }
    }
    try leave_soft(p)
    try advance(p)
    try skip_soft(p)
    if p.current.kind == .PunctArrow {
        try advance(p)
        try skip_soft(p)
        try parse_return_spec(p, is_extern)
    }
    if is_extern {
        if p.current.kind == .PunctLBrace { ret InvalidSyntax }
    } else {
        try parse_block_node(p)
    }
    let token_end = p.token_index
    if is_extern {
        try add_top_parent_since(p, .ExternDecl, token_start, token_end, node_start)
    } else {
        try add_top_parent_since(p, .FnDecl, token_start, token_end, node_start)
    }
    try finish_line(p)
    ret ok
}

fn parse_type_member(p: *Parser, member_kind: syntax.Kind) -> err {
    let token_start = p.token_index
    var nested: [1]usize = zero
    var nested_count = 0usize
    try require(p, .Identifier)
    try skip_separators(p)
    if member_kind == .FieldDecl {
        try require(p, .PunctColon)
        try skip_separators(p)
        var has_type_node = false
        try parse_type_node(p, &has_type_node)
        if has_type_node {
            nested[0usize] = p.last_node
            nested_count = 1usize
        }
    } else {
        if member_kind == .EnumMember {
            if p.current.kind == .PunctAssign {
                try advance(p)
                try skip_separators(p)
                try parse_expression_node(p)
                nested[0usize] = p.last_node
                nested_count = 1usize
            }
        } else {
            if p.current.kind == .PunctColon {
                try advance(p)
                try skip_separators(p)
                var has_type_node = false
                try parse_type_node(p, &has_type_node)
                if has_type_node {
                    nested[0usize] = p.last_node
                    nested_count = 1usize
                }
            }
        }
    }
    let token_end = p.token_index
    try add_parent_node(p, member_kind, token_start, token_end, nested[..nested_count])
    try skip_separators(p)
    if p.current.kind != .PunctComma && p.current.kind != .PunctRBrace { ret InvalidSyntax }
    ret ok
}

fn parse_type_body(p: *Parser, rhs_kind: syntax.Kind, token_start: usize, prefix_node: usize, has_prefix: bool) -> err {
    var node_start = p.tree.count
    var member_count = 0usize
    var member_kind = syntax.Kind.FieldDecl
    if rhs_kind == .EnumType { member_kind = .EnumMember }
    if rhs_kind == .UnionEnumType { member_kind = .UnionMember }
    if has_prefix { node_start = prefix_node }
    try require(p, .PunctLBrace)
    enter_soft(p)
    try skip_separators(p)
    while p.current.kind != .PunctRBrace {
        try parse_type_member(p, member_kind)
        member_count += 1usize
        if p.current.kind == .PunctComma {
            try advance(p)
            try skip_separators(p)
        } else {
            if p.current.kind != .PunctRBrace { ret InvalidSyntax }
        }
    }
    if (rhs_kind == .EnumType || rhs_kind == .UnionEnumType) && member_count == 0usize {
        ret InvalidSyntax
    }
    try leave_soft(p)
    try advance(p)
    try add_parent_since(p, rhs_kind, token_start, p.token_index, node_start)
    ret ok
}

fn parse_type_declaration(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    var has_rhs_node = false
    try require(p, .KwType)
    try require(p, .Identifier)
    if p.current.kind == .PunctLBracket {
        try advance(p)
        enter_soft(p)
        try skip_separators(p)
        if p.current.kind == .PunctRBracket { ret InvalidSyntax }
        while p.current.kind != .PunctRBracket {
            try parse_comptime_node(p)
            try skip_soft(p)
            if p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
            } else {
                if p.current.kind != .PunctRBracket { ret InvalidSyntax }
            }
        }
        try leave_soft(p)
        try advance(p)
    }
    try require(p, .PunctAssign)
    if p.current.kind == .KwStruct {
        let rhs_start = p.token_index
        try advance(p)
        try parse_type_body(p, .StructType, rhs_start, 0usize, false)
        has_rhs_node = true
    } else {
        if p.current.kind == .KwUnion {
            let rhs_start = p.token_index
            try advance(p)
            if p.current.kind == .KwEnum {
                try advance(p)
                var has_tag_node = false
                var tag_node = 0usize
                if p.current.kind != .PunctLBrace {
                    try parse_type_node(p, &has_tag_node)
                    if has_tag_node { tag_node = p.last_node }
                }
                try parse_type_body(p, .UnionEnumType, rhs_start, tag_node, has_tag_node)
                has_rhs_node = true
            } else {
                try parse_type_body(p, .UnionType, rhs_start, 0usize, false)
                has_rhs_node = true
            }
        } else {
            if p.current.kind == .KwEnum {
                let rhs_start = p.token_index
                try advance(p)
                var has_tag_node = false
                var tag_node = 0usize
                if p.current.kind != .PunctLBrace {
                    try parse_type_node(p, &has_tag_node)
                    if has_tag_node { tag_node = p.last_node }
                }
                try parse_type_body(p, .EnumType, rhs_start, tag_node, has_tag_node)
                has_rhs_node = true
            } else {
                try parse_type_node(p, &has_rhs_node)
            }
        }
    }
    let token_end = p.token_index
    try add_top_parent_since(p, .TypeDecl, token_start, token_end, node_start)
    try finish_line(p)
    ret ok
}

fn parse_value_declaration(p: *Parser, is_const: bool) -> err {
    let token_start = p.token_index
    var nested: [2]usize = zero
    var nested_count = 0usize
    if is_const {
        try require(p, .KwConst)
    } else {
        try require(p, .KwVar)
    }
    try require(p, .Identifier)
    if p.current.kind == .PunctColon {
        try advance(p)
        var has_type_node = false
        try parse_type_node(p, &has_type_node)
        if has_type_node {
            nested[nested_count] = p.last_node
            nested_count += 1usize
        }
    }
    if is_const {
        try require(p, .PunctAssign)
        try parse_expression_node(p)
        nested[nested_count] = p.last_node
        nested_count += 1usize
    } else {
        if p.current.kind == .PunctAssign {
            try advance(p)
            let initializer_has_node = p.current.kind != .KwZero && p.current.kind != .KwUndef
            try parse_initializer_node(p)
            if initializer_has_node {
                nested[nested_count] = p.last_node
                nested_count += 1usize
            }
        }
    }
    if p.current.kind != .Newline && p.current.kind != .Eof { ret InvalidSyntax }
    var node_kind = syntax.Kind.VarDecl
    if is_const { node_kind = .ConstDecl }
    try add_top_parent(p, node_kind, token_start, p.token_index, nested[..nested_count])
    try finish_line(p)
    ret ok
}

fn parse_attribute(p: *Parser) -> err {
    let token_start = p.token_index
    let node_start = p.tree.count
    try require(p, .PunctAt)
    try require(p, .Identifier)
    if p.current.kind == .PunctLParen {
        try advance(p)
        enter_soft(p)
        try skip_separators(p)
        while p.current.kind != .PunctRParen {
            try parse_expression_node(p)
            try skip_separators(p)
            if p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
            } else {
                if p.current.kind != .PunctRParen { ret InvalidSyntax }
            }
        }
        try leave_soft(p)
        try advance(p)
    }
    if p.current.kind != .Newline { ret InvalidSyntax }
    try add_top_parent_since(p, .Attribute, token_start, p.token_index, node_start)
    try advance(p)
    ret ok
}

fn parse_one(p: *Parser) -> err {
    var has_attributes = false
    while p.current.kind == .PunctAt {
        has_attributes = true
        try parse_attribute(p)
    }
    p.error_start = p.token_index
    p.error_node_checkpoint = p.tree.count
    p.error_child_checkpoint = p.tree.child_count
    p.error_errors_checkpoint = p.tree.errors
    p.error_declarations_checkpoint = p.declarations
    p.error_soft_checkpoint = p.soft_depth
    if p.current.kind == .KwUse {
        if has_attributes { ret InvalidSyntax }
        try parse_use(p)
    } else {
        if p.current.kind == .KwError {
            try parse_error(p)
        } else {
            if p.current.kind == .KwFn {
                try parse_function(p, false)
            } else {
                if p.current.kind == .KwExtern {
                    try parse_function(p, true)
                } else {
                    if p.current.kind == .KwType {
                        try parse_type_declaration(p)
                    } else {
                        if p.current.kind == .KwConst {
                            try parse_value_declaration(p, true)
                        } else {
                            if p.current.kind == .KwVar {
                                try parse_value_declaration(p, false)
                            } else {
                                ret InvalidSyntax
                            }
                        }
                    }
                }
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
        p.soft_top_barrier = false
        p.error_start = p.token_index
        p.error_node_checkpoint = p.tree.count
        p.error_child_checkpoint = p.tree.child_count
        p.error_errors_checkpoint = p.tree.errors
        p.error_declarations_checkpoint = p.declarations
        p.error_soft_checkpoint = p.soft_depth
        let item_error = parse_one(p)
        if item_error != ok {
            p.tree.count = p.error_node_checkpoint
            p.tree.child_count = p.error_child_checkpoint
            p.tree.errors = p.error_errors_checkpoint
            p.declarations = p.error_declarations_checkpoint
            p.soft_depth = p.error_soft_checkpoint
            p.soft_top_barrier = false
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
    var node_index = 1usize
    while node_index < p.tree.count {
        if p.tree.nodes[node_index].top_level {
            while token < p.tree.nodes[node_index].token_start {
                try add_child(p, syntax.token_child(token))
                token += 1usize
            }
            try add_child(p, syntax.node_child(node_index))
            token = p.tree.nodes[node_index].token_end
        }
        node_index += 1usize
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
