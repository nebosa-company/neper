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

fn add_top_node(p: *Parser, kind: syntax.Kind, token_start: usize, token_end: usize) -> err {
    if p.top_count == p.top_nodes.len { ret InvalidSyntax }
    try add_node(p, kind, token_start, token_end)
    p.top_nodes[p.top_count] = p.last_node
    p.top_count += 1usize
    ret ok
}

fn add_top_parent(p: *Parser, kind: syntax.Kind, token_start: usize, token_end: usize, nested: []usize) -> err {
    if p.top_count == p.top_nodes.len { ret InvalidSyntax }
    try add_parent_node(p, kind, token_start, token_end, nested)
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

fn parse_parameter_node(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [1]usize = zero
    var nested_count = 0usize
    if p.current.kind == .PunctEllipsis {
        try advance(p)
    } else {
        try require(p, .Identifier)
        try require(p, .PunctColon)
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
    try require(p, .PunctColon)
    if p.current.kind == .KwType {
        try advance(p)
    } else {
        if p.current.kind == .KwFn {
            var look = p.scanner
            let following = lex.next(&look)
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

fn scan_return_spec(p: *Parser, is_extern: bool) -> err {
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
    ret kind == .Integer || kind == .Float || kind == .String || kind == .RawString || kind == .Character || kind == .KwTrue || kind == .KwFalse || kind == .KwNil || kind == .KwOk
}

fn parse_expression_node(p: *Parser) -> err {
    ret parse_binary_node(p, 1usize)
}

fn named_aggregate_follows(p: *Parser) -> bool {
    var look = p.scanner
    var pascal = identifier_is_pascal(p)
    var token = lex.next(&look)
    while token.kind == .PunctDot {
        token = lex.next(&look)
        if token.kind != .Identifier { ret false }
        let first = look.source[token.start]
        pascal = first >= 65u8 && first <= 90u8
        token = lex.next(&look)
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
    }
    ret pascal && token.kind == .PunctLBrace
}

fn identifier_is_pascal(p: *Parser) -> bool {
    let first = p.scanner.source[p.current.start]
    ret first >= 65u8 && first <= 90u8
}

fn parse_literal_item_node(p: *Parser) -> err {
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
        if identifier_is_pascal(p) {
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

fn scan_array_aggregate_type(p: *Parser) -> err {
    let token_start = p.token_index
    var parens = 0usize
    var brackets = 0usize
    if p.current.kind != .PunctStar && p.current.kind != .PunctLBracket && p.current.kind != .KwFn && p.current.kind != .KwExtern && p.current.kind != .KwType && p.current.kind != .Identifier { ret InvalidSyntax }
    while true {
        let kind = p.current.kind
        if kind == .Invalid || kind == .Eof || kind == .PunctRBrace { ret InvalidSyntax }
        if kind == .PunctLBrace && parens == 0usize && brackets == 0usize { break }
        if kind == .Newline {
            if parens == 0usize && brackets == 0usize { ret InvalidSyntax }
            try advance(p)
            continue
        }
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
        try advance(p)
    }
    if p.token_index == token_start || parens != 0usize || brackets != 0usize { ret InvalidSyntax }
    ret ok
}

fn parse_aggregate_literal_node(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [128]usize = zero
    var nested_count = 0usize
    if p.current.kind == .Identifier {
        try advance(p)
        while p.current.kind == .PunctDot {
            try advance(p)
            try require(p, .Identifier)
        }
        if p.current.kind == .PunctLBracket {
            try advance(p)
            try skip_separators(p)
            while p.current.kind != .PunctRBracket {
                try parse_expression_node(p)
                if nested_count == nested.len { ret InvalidSyntax }
                nested[nested_count] = p.last_node
                nested_count += 1usize
                try skip_separators(p)
                if p.current.kind == .PunctComma {
                    try advance(p)
                    try skip_separators(p)
                } else {
                    if p.current.kind != .PunctRBracket { ret InvalidSyntax }
                }
            }
            try advance(p)
        }
    } else {
        try require(p, .PunctLBracket)
        try skip_separators(p)
        if p.current.kind == .PunctUnderscore {
            try advance(p)
        } else {
            try parse_expression_node(p)
            nested[nested_count] = p.last_node
            nested_count += 1usize
        }
        try skip_separators(p)
        try require(p, .PunctRBracket)
        try scan_array_aggregate_type(p)
    }
    try require(p, .PunctLBrace)
    try skip_separators(p)
    if p.current.kind == .PunctRBrace { ret InvalidSyntax }
    while p.current.kind != .PunctRBrace {
        try parse_literal_item_node(p)
        if nested_count == nested.len { ret InvalidSyntax }
        nested[nested_count] = p.last_node
        nested_count += 1usize
        try skip_separators(p)
        if p.current.kind == .PunctComma {
            try advance(p)
            try skip_separators(p)
        } else {
            if p.current.kind != .PunctRBrace { ret InvalidSyntax }
        }
    }
    try advance(p)
    try add_parent_node(p, .AggregateLiteral, token_start, p.token_index, nested[..nested_count])
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
        try require(p, .Identifier)
        try add_node(p, .MemberExpr, token_start, p.token_index)
        ret ok
    }
    if p.current.kind == .PunctLParen {
        var nested: [1]usize = zero
        try advance(p)
        try skip_separators(p)
        try parse_expression_node(p)
        nested[0usize] = p.last_node
        try skip_separators(p)
        try require(p, .PunctRParen)
        try add_parent_node(p, .GroupExpr, token_start, p.token_index, nested[..])
        ret ok
    }
    ret InvalidSyntax
}

fn parse_call_postfix(p: *Parser, receiver: usize) -> err {
    let token_start = p.tree.nodes[receiver].token_start
    var nested: [33]usize = zero
    var nested_count = 1usize
    nested[0usize] = receiver
    try require(p, .PunctLParen)
    try skip_separators(p)
    while p.current.kind != .PunctRParen {
        try parse_expression_node(p)
        if nested_count == nested.len { ret InvalidSyntax }
        nested[nested_count] = p.last_node
        nested_count += 1usize
        try skip_separators(p)
        if p.current.kind == .PunctComma {
            try advance(p)
            try skip_separators(p)
        } else {
            if p.current.kind != .PunctRParen { ret InvalidSyntax }
        }
    }
    try advance(p)
    try add_parent_node(p, .CallExpr, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_bracket_postfix(p: *Parser, receiver: usize) -> err {
    let token_start = p.tree.nodes[receiver].token_start
    var nested: [34]usize = zero
    var nested_count = 1usize
    nested[0usize] = receiver
    try require(p, .PunctLBracket)
    try skip_separators(p)
    if p.current.kind == .PunctRange {
        try advance(p)
        try skip_separators(p)
        if p.current.kind != .PunctRBracket {
            try parse_expression_node(p)
            nested[nested_count] = p.last_node
            nested_count += 1usize
            try skip_separators(p)
        }
    } else {
        if p.current.kind != .PunctRBracket {
            try parse_expression_node(p)
            nested[nested_count] = p.last_node
            nested_count += 1usize
            try skip_separators(p)
            if p.current.kind == .PunctRange {
                try advance(p)
                try skip_separators(p)
                if p.current.kind != .PunctRBracket {
                    try parse_expression_node(p)
                    nested[nested_count] = p.last_node
                    nested_count += 1usize
                    try skip_separators(p)
                }
            } else {
                while p.current.kind == .PunctComma {
                    try advance(p)
                    try skip_separators(p)
                    if p.current.kind == .PunctRBracket { break }
                    try parse_expression_node(p)
                    if nested_count == nested.len { ret InvalidSyntax }
                    nested[nested_count] = p.last_node
                    nested_count += 1usize
                    try skip_separators(p)
                }
            }
        }
    }
    try skip_separators(p)
    try require(p, .PunctRBracket)
    try add_parent_node(p, .BracketPostfix, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_postfix_node(p: *Parser) -> err {
    try parse_primary_node(p)
    while p.current.kind == .PunctDot || p.current.kind == .PunctLParen || p.current.kind == .PunctLBracket {
        let receiver = p.last_node
        if p.current.kind == .PunctDot {
            let token_start = p.tree.nodes[receiver].token_start
            var nested: [1]usize = zero
            nested[0usize] = receiver
            try advance(p)
            try require(p, .Identifier)
            try add_parent_node(p, .FieldExpr, token_start, p.token_index, nested[..])
        } else {
            if p.current.kind == .PunctLParen {
                try parse_call_postfix(p, receiver)
            } else {
                try parse_bracket_postfix(p, receiver)
            }
        }
    }
    ret ok
}

fn parse_prefix_node(p: *Parser) -> err {
    if is_prefix_op(p.current.kind) {
        let token_start = p.token_index
        var nested: [1]usize = zero
        try advance(p)
        try parse_prefix_node(p)
        nested[0usize] = p.last_node
        try add_parent_node(p, .UnaryExpr, token_start, p.tree.nodes[p.last_node].token_end, nested[..])
        ret ok
    }
    ret parse_postfix_node(p)
}

fn parse_binary_node(p: *Parser, minimum: usize) -> err {
    try parse_prefix_node(p)
    var left = p.last_node
    while binary_precedence(p.current.kind) >= minimum {
        let precedence = binary_precedence(p.current.kind)
        var nested: [2]usize = zero
        nested[0usize] = left
        try advance(p)
        try parse_binary_node(p, precedence + 1usize)
        nested[1usize] = p.last_node
        try add_parent_node(p, .BinaryExpr, p.tree.nodes[left].token_start, p.tree.nodes[p.last_node].token_end, nested[..])
        left = p.last_node
        if precedence == 3usize && binary_precedence(p.current.kind) == 3usize { ret InvalidSyntax }
    }
    ret ok
}

fn parse_named_type_node(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [32]usize = zero
    var nested_count = 0usize
    try require(p, .Identifier)
    while p.current.kind == .PunctDot {
        try advance(p)
        try require(p, .Identifier)
    }
    if p.current.kind == .PunctLBracket {
        try advance(p)
        try skip_separators(p)
        while p.current.kind != .PunctRBracket {
            try parse_expression_node(p)
            if nested_count == nested.len { ret InvalidSyntax }
            nested[nested_count] = p.last_node
            nested_count += 1usize
            try skip_separators(p)
            if p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
            } else {
                if p.current.kind != .PunctRBracket { ret InvalidSyntax }
            }
        }
        try advance(p)
    }
    try add_parent_node(p, .NamedType, token_start, p.token_index, nested[..nested_count])
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
                try skip_separators(p)
                try require(p, .PunctColon)
                try skip_separators(p)
                if p.current.kind == .PunctEllipsis {
                    try advance(p)
                    try add_node(p, .Parameter, token_start, p.token_index)
                    ret ok
                }
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
    var nested: [32]usize = zero
    var nested_count = 0usize
    var type_count = 0usize
    if p.current.kind == .PunctLParen {
        try advance(p)
        try skip_separators(p)
        while p.current.kind != .PunctRParen {
            var has_type_node = false
            try parse_type_node(p, &has_type_node)
            type_count += 1usize
            if has_type_node {
                if nested_count == nested.len { ret InvalidSyntax }
                nested[nested_count] = p.last_node
                nested_count += 1usize
            }
            try skip_separators(p)
            if p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
            } else {
                if p.current.kind != .PunctRParen { ret InvalidSyntax }
            }
        }
        if type_count < 2usize { ret InvalidSyntax }
        try advance(p)
    } else {
        var has_type_node = false
        try parse_type_node(p, &has_type_node)
        type_count = 1usize
        if has_type_node {
            nested[0usize] = p.last_node
            nested_count = 1usize
        }
    }
    try add_parent_node(p, .ReturnSpec, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_function_type_node(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [64]usize = zero
    var nested_count = 0usize
    if p.current.kind == .KwExtern { try advance(p) }
    try require(p, .KwFn)
    try require(p, .PunctLParen)
    try skip_separators(p)
    while p.current.kind != .PunctRParen {
        try parse_type_parameter_node(p)
        if nested_count == nested.len { ret InvalidSyntax }
        nested[nested_count] = p.last_node
        nested_count += 1usize
        try skip_separators(p)
        if p.current.kind == .PunctComma {
            try advance(p)
            try skip_separators(p)
        } else {
            if p.current.kind != .PunctRParen { ret InvalidSyntax }
        }
    }
    try advance(p)
    if p.current.kind == .PunctArrow {
        try advance(p)
        try parse_type_return_spec_node(p)
        if nested_count == nested.len { ret InvalidSyntax }
        nested[nested_count] = p.last_node
        nested_count += 1usize
    }
    try add_parent_node(p, .FunctionType, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_type_node(p: *Parser, has_node: *bool) -> err {
    let token_start = p.token_index
    var nested: [2]usize = zero
    var nested_count = 0usize
    *has_node = true
    if p.current.kind == .PunctStar {
        try advance(p)
        if p.current.kind == .KwConst { try advance(p) }
        if p.current.kind == .KwShared { try advance(p) }
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
        try skip_separators(p)
        if p.current.kind == .PunctRBracket {
            try advance(p)
            if p.current.kind == .KwConst { try advance(p) }
            if p.current.kind == .KwShared { try advance(p) }
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
        try require(p, .PunctRBracket)
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
    var nested: [33]usize = zero
    var nested_count = 0usize
    try require(p, .KwRet)
    if p.current.kind == .PunctLParen {
        let group_start = p.token_index
        try advance(p)
        try skip_separators(p)
        if p.current.kind == .PunctRParen { ret InvalidSyntax }
        try parse_expression_node(p)
        nested[0usize] = p.last_node
        nested_count = 1usize
        try skip_separators(p)
        if p.current.kind == .PunctComma {
            while p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
                if p.current.kind == .PunctRParen { break }
                try parse_expression_node(p)
                if nested_count == nested.len { ret InvalidSyntax }
                nested[nested_count] = p.last_node
                nested_count += 1usize
                try skip_separators(p)
            }
            try require(p, .PunctRParen)
        } else {
            var grouped: [1]usize = zero
            grouped[0usize] = nested[0usize]
            try require(p, .PunctRParen)
            try add_parent_node(p, .GroupExpr, group_start, p.token_index, grouped[..])
            nested[0usize] = p.last_node
        }
    } else {
        if p.current.kind != .Newline && p.current.kind != .PunctRBrace {
            try parse_expression_node(p)
            nested[0usize] = p.last_node
            nested_count = 1usize
        }
    }
    if p.current.kind != .Newline && p.current.kind != .PunctRBrace { ret InvalidSyntax }
    try add_parent_node(p, .ReturnStmt, token_start, p.token_index, nested[..nested_count])
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

fn parse_expression_statement(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [2]usize = zero
    var nested_count = 1usize
    try parse_expression_node(p)
    nested[0usize] = p.last_node
    if is_assignment_op(p.current.kind) {
        try advance(p)
        let initializer_has_node = p.current.kind != .KwZero && p.current.kind != .KwUndef
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
    try parse_expression_node(p)
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
    try parse_expression_node(p)
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
    try parse_expression_node(p)
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
    let token_start = p.token_index
    var node_kind = statement_kind(p)
    var parens = 0usize
    var brackets = 0usize
    var braces = 0usize
    if node_kind == .ErrorNode { ret InvalidSyntax }
    if node_kind == .ReturnStmt { ret parse_return_statement(p) }
    if node_kind == .BindingStmt { ret parse_binding_statement(p) }
    if node_kind == .TryStmt { ret parse_try_statement(p) }
    if node_kind == .CallStmt { ret parse_expression_statement(p) }
    if node_kind == .IfStmt { ret parse_if_statement(p) }
    if node_kind == .WhileStmt { ret parse_while_statement(p) }
    if node_kind == .WhenStmt { ret parse_when_statement(p) }
    while true {
        let kind = p.current.kind
        if kind == .Invalid || kind == .Eof { ret InvalidSyntax }
        if kind == .PunctRBrace && braces == 0usize {
            if parens != 0usize || brackets != 0usize { ret InvalidSyntax }
            break
        }
        if kind == .Newline && parens == 0usize && brackets == 0usize && braces == 0usize { break }
        if is_assignment_op(kind) && node_kind == .CallStmt { node_kind = .AssignmentStmt }
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
        if kind == .PunctLBrace { braces += 1usize }
        if kind == .PunctRBrace {
            if braces == 0usize { ret InvalidSyntax }
            braces = braces - 1usize
        }
        try advance(p)
    }
    if p.token_index == token_start { ret InvalidSyntax }
    try add_node(p, node_kind, token_start, p.token_index)
    ret ok
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
    var nested: [128]usize = zero
    var nested_count = 0usize
    try require(p, .PunctLBrace)
    try skip_separators(p)
    while p.current.kind != .PunctRBrace {
        if p.current.kind == .Eof { ret InvalidSyntax }
        let statement_start = p.token_index
        let node_checkpoint = p.tree.count
        let child_checkpoint = p.tree.child_count
        let statement_error = parse_statement_node(p)
        if statement_error != ok {
            p.tree.count = node_checkpoint
            p.tree.child_count = child_checkpoint
            p.tree.errors += 1usize
            var error_end = p.token_index
            if p.current.kind == .Invalid || error_end == statement_start { error_end += 1usize }
            try add_node(p, .ErrorNode, statement_start, error_end)
            try recover_statement(p)
        } else {
            try skip_separators(p)
        }
        if nested_count == nested.len { ret InvalidSyntax }
        nested[nested_count] = p.last_node
        nested_count += 1usize
    }
    try advance(p)
    try add_parent_node(p, .Block, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_function(p: *Parser, is_extern: bool) -> err {
    let token_start = p.token_index
    var nested: [64]usize = zero
    var nested_count = 0usize
    if is_extern { try require(p, .KwExtern) }
    try require(p, .KwFn)
    try require(p, .Identifier)
    if p.current.kind == .PunctLBracket {
        try advance(p)
        try skip_separators(p)
        if p.current.kind == .PunctRBracket { ret InvalidSyntax }
        while p.current.kind != .PunctRBracket {
            try parse_comptime_node(p)
            if nested_count == nested.len { ret InvalidSyntax }
            nested[nested_count] = p.last_node
            nested_count += 1usize
            if p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
            } else {
                if p.current.kind != .PunctRBracket { ret InvalidSyntax }
            }
        }
        try advance(p)
    }
    try require(p, .PunctLParen)
    try skip_separators(p)
    while p.current.kind != .PunctRParen {
        try parse_parameter_node(p)
        if nested_count == nested.len { ret InvalidSyntax }
        nested[nested_count] = p.last_node
        nested_count += 1usize
        if p.current.kind == .PunctComma {
            try advance(p)
            try skip_separators(p)
        } else {
            if p.current.kind != .PunctRParen { ret InvalidSyntax }
        }
    }
    try advance(p)
    if p.current.kind == .PunctArrow {
        try advance(p)
        try scan_return_spec(p, is_extern)
        if nested_count == nested.len { ret InvalidSyntax }
        nested[nested_count] = p.last_node
        nested_count += 1usize
    }
    if is_extern {
        if p.current.kind == .PunctLBrace { ret InvalidSyntax }
    } else {
        try parse_block_node(p)
        if nested_count == nested.len { ret InvalidSyntax }
        nested[nested_count] = p.last_node
        nested_count += 1usize
    }
    let token_end = p.token_index
    if is_extern {
        try add_top_parent(p, .ExternDecl, token_start, token_end, nested[..nested_count])
    } else {
        try add_top_parent(p, .FnDecl, token_start, token_end, nested[..nested_count])
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
    var nested: [128]usize = zero
    var nested_count = 0usize
    var member_count = 0usize
    var member_kind = syntax.Kind.FieldDecl
    if rhs_kind == .EnumType { member_kind = .EnumMember }
    if rhs_kind == .UnionEnumType { member_kind = .UnionMember }
    if has_prefix {
        nested[0usize] = prefix_node
        nested_count = 1usize
    }
    try require(p, .PunctLBrace)
    try skip_separators(p)
    while p.current.kind != .PunctRBrace {
        try parse_type_member(p, member_kind)
        if nested_count == nested.len { ret InvalidSyntax }
        nested[nested_count] = p.last_node
        nested_count += 1usize
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
    try advance(p)
    try add_parent_node(p, rhs_kind, token_start, p.token_index, nested[..nested_count])
    ret ok
}

fn parse_type_declaration(p: *Parser) -> err {
    let token_start = p.token_index
    var nested: [64]usize = zero
    var nested_count = 0usize
    var has_rhs_node = false
    try require(p, .KwType)
    try require(p, .Identifier)
    if p.current.kind == .PunctLBracket {
        try advance(p)
        try skip_separators(p)
        if p.current.kind == .PunctRBracket { ret InvalidSyntax }
        while p.current.kind != .PunctRBracket {
            try parse_comptime_node(p)
            if nested_count == nested.len { ret InvalidSyntax }
            nested[nested_count] = p.last_node
            nested_count += 1usize
            if p.current.kind == .PunctComma {
                try advance(p)
                try skip_separators(p)
            } else {
                if p.current.kind != .PunctRBracket { ret InvalidSyntax }
            }
        }
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
    if has_rhs_node {
        if nested_count == nested.len { ret InvalidSyntax }
        nested[nested_count] = p.last_node
        nested_count += 1usize
    }
    let token_end = p.token_index
    try add_top_parent(p, .TypeDecl, token_start, token_end, nested[..nested_count])
    try finish_line(p)
    ret ok
}

fn scan_delimited_decl(p: *Parser, decl_kind: lex.Kind, node_kind: syntax.Kind, token_start: usize) -> err {
    var parens = 0usize
    var brackets = 0usize
    var braces = 0usize
    var saw_assign = false
    try require(p, .Identifier)
    while true {
        let kind = p.current.kind
        if kind == .Invalid { ret InvalidSyntax }
        if kind == .Eof {
            if parens != 0usize || brackets != 0usize || braces != 0usize { ret InvalidSyntax }
            if (decl_kind == .KwType || decl_kind == .KwConst) && !saw_assign { ret InvalidSyntax }
            try add_top_node(p, node_kind, token_start, p.token_index)
            ret ok
        }
        if kind == .Newline && parens == 0usize && brackets == 0usize && braces == 0usize {
            if (decl_kind == .KwType || decl_kind == .KwConst) && !saw_assign { ret InvalidSyntax }
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
    ret kind == .KwConst || kind == .KwVar
}

fn node_kind_for_decl(kind: lex.Kind) -> syntax.Kind {
    if kind == .KwConst { ret .ConstDecl }
    ret .VarDecl
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
            if p.current.kind == .KwFn {
                try parse_function(p, false)
            } else {
                if p.current.kind == .KwExtern {
                    try parse_function(p, true)
                } else {
                    if p.current.kind == .KwType {
                        try parse_type_declaration(p)
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
