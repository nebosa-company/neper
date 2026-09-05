// Module-scope declaration collection and qualified reference resolution.

use graph
use lex
use parse
use syntax

error Capacity
error DuplicateName
error QualifierCollision
error ReservedName
error UnknownMember

type Namespace = enum u8 {
    Type,
    Value,
}

type Kind = enum u8 {
    Type,
    Const,
    Var,
    Error,
    Function,
    Extern,
    Qualifier,
    Intrinsic,
}

type Symbol = struct {
    name: str,
    kind: Kind,
    space: Namespace,
    module_index: usize,
    target_module: usize,
    token_start: usize,
    token_end: usize,
}

type Resolver = struct {
    symbols: []Symbol,
    tokens: []lex.Token,
    count: usize,
    token_count: usize,
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

fn init(r: *Resolver, symbols: []Symbol, tokens: []lex.Token) -> err {
    if symbols.len == 0usize || tokens.len == 0usize { ret Capacity }
    r.symbols = symbols
    r.tokens = tokens
    r.count = 0usize
    r.token_count = 0usize
    ret ok
}

fn reserved(name: str) -> bool {
    ret same(name, "i8") || same(name, "i16") || same(name, "i32") || same(name, "i64") || same(name, "isize") || same(name, "u8") || same(name, "u16") || same(name, "u32") || same(name, "u64") || same(name, "usize") || same(name, "f16") || same(name, "bf16") || same(name, "f32") || same(name, "f64") || same(name, "bool") || same(name, "void") || same(name, "err") || same(name, "type") || same(name, "Vec") || same(name, "Mask") || same(name, "Atomic") || same(name, "target")
}

fn last_segment(name: str) -> str {
    var at = name.len
    while at > 0usize {
        at = at - 1usize
        if name[at] == 46u8 { ret name[at + 1usize..] }
    }
    ret name
}

fn tokenize(r: *Resolver, text: str) -> err {
    var scanner = lex.init(text)
    r.token_count = 0usize
    while true {
        if r.token_count == r.tokens.len { ret Capacity }
        let token = lex.next(&scanner)
        if token.kind == .Invalid { ret lex.InvalidSource }
        r.tokens[r.token_count] = token
        r.token_count += 1usize
        if token.kind == .Eof { break }
    }
    ret ok
}

fn find(r: *Resolver, module_index: usize, name: str, space: Namespace) -> (usize, bool) {
    var i = 0usize
    while i < r.count {
        if r.symbols[i].module_index == module_index && r.symbols[i].space == space && same(r.symbols[i].name, name) {
            ret (i, true)
        }
        i += 1usize
    }
    ret (0usize, false)
}

fn add(r: *Resolver, symbol: Symbol) -> err {
    if reserved(symbol.name) {
        if symbol.kind != .Qualifier || same(symbol.name, "target") { ret ReservedName }
    }
    let (prior_index, duplicate) = find(r, symbol.module_index, symbol.name, symbol.space)
    if duplicate {
        if symbol.kind == .Qualifier || r.symbols[prior_index].kind == .Qualifier { ret QualifierCollision }
        ret DuplicateName
    }
    if r.count == r.symbols.len { ret Capacity }
    r.symbols[r.count] = symbol
    r.count += 1usize
    ret ok
}

fn declaration_kind(node_kind: syntax.Kind) -> (Kind, Namespace, bool) {
    if node_kind == .TypeDecl { ret (.Type, .Type, true) }
    if node_kind == .ConstDecl { ret (.Const, .Value, true) }
    if node_kind == .VarDecl { ret (.Var, .Value, true) }
    if node_kind == .ErrorDecl { ret (.Error, .Value, true) }
    if node_kind == .FnDecl { ret (.Function, .Value, true) }
    if node_kind == .ExternDecl { ret (.Extern, .Value, true) }
    ret (.Var, .Value, false)
}

fn declaration_name(r: *Resolver, text: str, node: syntax.Node) -> (str, err) {
    var name_index = node.token_start + 1usize
    if node.kind == .ExternDecl { name_index += 1usize }
    if name_index >= node.token_end || name_index >= r.token_count { ret ("", parse.InvalidSyntax) }
    let token = r.tokens[name_index]
    if token.kind != .Identifier { ret ("", parse.InvalidSyntax) }
    ret (text[token.start..token.end], ok)
}

fn collect_module(r: *Resolver, g: *graph.Graph, module_index: usize) -> err {
    if reserved(last_segment(g.modules[module_index].name)) { ret ReservedName }
    let import_end = g.modules[module_index].first_import + g.modules[module_index].import_count
    var import_index = g.modules[module_index].first_import
    while import_index < import_end {
        let item = g.imports[import_index]
        try add(r, Symbol { name: item.qualifier, kind: .Qualifier, space: .Value, module_index: module_index, target_module: item.target, token_start: 0usize, token_end: 0usize })
        import_index += 1usize
    }
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, g.nodes, g.children)
    try parse.parse(&tree, g.modules[module_index].text)
    try tokenize(r, g.modules[module_index].text)
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level {
            let (kind, space, is_declaration) = declaration_kind(node.kind)
            if is_declaration {
                let (name, name_error) = declaration_name(r, g.modules[module_index].text, node)
                if name_error != ok { ret name_error }
                try add(r, Symbol { name: name, kind: kind, space: space, module_index: module_index, target_module: module_index, token_start: node.token_start, token_end: node.token_end })
            }
        }
        node_index += 1usize
    }
    ret ok
}

fn qualifier(r: *Resolver, module_index: usize, name: str) -> (usize, bool) {
    let (symbol_index, found) = find(r, module_index, name, .Value)
    if !found || r.symbols[symbol_index].kind != .Qualifier { ret (0usize, false) }
    ret (r.symbols[symbol_index].target_module, true)
}

fn exported(r: *Resolver, module_index: usize, name: str, type_only: bool) -> bool {
    let (type_index, has_type) = find(r, module_index, name, .Type)
    if has_type { ret true }
    if type_only { ret false }
    let (value_index, has_value) = find(r, module_index, name, .Value)
    if !has_value { ret false }
    ret r.symbols[value_index].kind != .Qualifier
}

fn seed(r: *Resolver, g: *graph.Graph, module_name: str, name: str, space: Namespace, kind: Kind) -> err {
    let (module_index, found) = graph.find_module(g, module_name)
    if !found { ret ok }
    try add(r, Symbol { name: name, kind: kind, space: space, module_index: module_index, target_module: module_index, token_start: 0usize, token_end: 0usize })
    ret ok
}

fn seed_intrinsics(r: *Resolver, g: *graph.Graph) -> err {
    try seed(r, g, "e.mem", "alloc", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "mark", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "reset", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "stats", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "Exhausted", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "Stats", .Type, .Type)
    try seed(r, g, "e.os", "open", .Value, .Intrinsic)
    try seed(r, g, "e.os", "read", .Value, .Intrinsic)
    try seed(r, g, "e.os", "write", .Value, .Intrinsic)
    try seed(r, g, "e.os", "close", .Value, .Intrinsic)
    try seed(r, g, "e.os", "stdout", .Value, .Intrinsic)
    try seed(r, g, "e.os", "stderr", .Value, .Intrinsic)
    try seed(r, g, "e.os", "readdir", .Value, .Intrinsic)
    try seed(r, g, "e.os", "spawn", .Value, .Intrinsic)
    try seed(r, g, "e.os", "wait", .Value, .Intrinsic)
    try seed(r, g, "e.os", "exit", .Value, .Intrinsic)
    try seed(r, g, "e.os", "args", .Value, .Intrinsic)
    try seed(r, g, "e.os", "reserve", .Value, .Intrinsic)
    try seed(r, g, "e.os", "commit", .Value, .Intrinsic)
    try seed(r, g, "e.os", "clock", .Value, .Intrinsic)
    try seed(r, g, "e.os", "NotFound", .Value, .Intrinsic)
    try seed(r, g, "e.os", "Denied", .Value, .Intrinsic)
    try seed(r, g, "e.os", "Exists", .Value, .Intrinsic)
    try seed(r, g, "e.os", "Interrupted", .Value, .Intrinsic)
    try seed(r, g, "e.os", "OutOfMemory", .Value, .Intrinsic)
    try seed(r, g, "e.os", "Failed", .Value, .Intrinsic)
    try seed(r, g, "e.os", "Timeout", .Value, .Intrinsic)
    try seed(r, g, "e.os", "WouldBlock", .Value, .Intrinsic)
    try seed(r, g, "e.os", "Unsupported", .Value, .Intrinsic)
    ret ok
}

fn first_node_child(tree: *parse.Tree, node: syntax.Node) -> (usize, bool) {
    let end = node.first_child + node.child_count
    var i = node.first_child
    while i < end {
        if tree.children[i].node { ret (tree.children[i].index, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn validate_field(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let (receiver_index, has_receiver) = first_node_child(tree, node)
    if !has_receiver || tree.nodes[receiver_index].kind != .NameExpr { ret ok }
    let receiver = tree.nodes[receiver_index]
    if receiver.token_start >= r.token_count { ret parse.InvalidSyntax }
    let base_token = r.tokens[receiver.token_start]
    if base_token.kind != .Identifier { ret ok }
    let base = g.modules[module_index].text[base_token.start..base_token.end]
    let (target_module, has_qualifier) = qualifier(r, module_index, base)
    if !has_qualifier { ret ok }
    var at = node.token_end
    while at > node.token_start {
        at = at - 1usize
        if r.tokens[at].kind == .Identifier {
            let member = g.modules[module_index].text[r.tokens[at].start..r.tokens[at].end]
            if !exported(r, target_module, member, false) { ret UnknownMember }
            ret ok
        }
    }
    ret parse.InvalidSyntax
}

fn validate_named_type(r: *Resolver, g: *graph.Graph, module_index: usize, node: syntax.Node) -> err {
    if node.token_start >= r.token_count { ret parse.InvalidSyntax }
    let first = r.tokens[node.token_start]
    if first.kind != .Identifier { ret parse.InvalidSyntax }
    let base = g.modules[module_index].text[first.start..first.end]
    let (target_module, has_qualifier) = qualifier(r, module_index, base)
    if !has_qualifier { ret ok }
    var saw_dot = false
    var at = node.token_start + 1usize
    while at < node.token_end {
        let token = r.tokens[at]
        if token.kind == .PunctLBracket { break }
        if token.kind == .PunctDot {
            saw_dot = true
        } else {
            if saw_dot && token.kind == .Identifier {
                let member = g.modules[module_index].text[token.start..token.end]
                if !exported(r, target_module, member, true) { ret UnknownMember }
                ret ok
            }
        }
        at += 1usize
    }
    ret UnknownMember
}

fn validate_module(r: *Resolver, g: *graph.Graph, module_index: usize) -> err {
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, g.nodes, g.children)
    try parse.parse(&tree, g.modules[module_index].text)
    try tokenize(r, g.modules[module_index].text)
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.kind == .FieldExpr {
            try validate_field(r, g, &tree, module_index, node)
        } else {
            if node.kind == .NamedType { try validate_named_type(r, g, module_index, node) }
        }
        node_index += 1usize
    }
    ret ok
}

fn collect(r: *Resolver, g: *graph.Graph) -> err {
    r.count = 0usize
    try seed_intrinsics(r, g)
    var module_index = 0usize
    while module_index < g.count {
        try collect_module(r, g, module_index)
        module_index += 1usize
    }
    module_index = 0usize
    while module_index < g.count {
        try validate_module(r, g, module_index)
        module_index += 1usize
    }
    ret ok
}
