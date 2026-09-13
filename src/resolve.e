// Module, lexical-scope and reference resolution.

use graph
use lex
use parse
use syntax

error Capacity
error DuplicateName
error QualifierCollision
error ReservedName
error UnknownMember
error ReservedLocal
error ModuleShadow
error DuplicateLocal
error UnknownName
error UnknownConvention
error UnknownType

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

type Local = struct {
    name: str,
    space: Namespace,
}

type Resolver = struct {
    symbols: []Symbol,
    tokens: []lex.Token,
    locals: []Local,
    count: usize,
    token_count: usize,
    local_count: usize,
    failure_module: usize,
    failure_token: lex.Token,
    failure_has_token: bool,
    failure_context_token: lex.Token,
    failure_has_context: bool,
    failure_name: str,
    failure_owner: str,
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

fn init(r: *Resolver, symbols: []Symbol, tokens: []lex.Token, locals: []Local) -> err {
    if symbols.len == 0usize || tokens.len == 0usize || locals.len == 0usize { ret Capacity }
    r.symbols = symbols
    r.tokens = tokens
    r.locals = locals
    r.count = 0usize
    r.token_count = 0usize
    r.local_count = 0usize
    r.failure_module = 0usize
    r.failure_has_token = false
    r.failure_has_context = false
    r.failure_name = ""
    r.failure_owner = ""
    ret ok
}

fn reserved(name: str) -> bool {
    ret same(name, "i8") || same(name, "i16") || same(name, "i32") || same(name, "i64") || same(name, "isize") || same(name, "u8") || same(name, "u16") || same(name, "u32") || same(name, "u64") || same(name, "usize") || same(name, "f16") || same(name, "bf16") || same(name, "f32") || same(name, "f64") || same(name, "bool") || same(name, "void") || same(name, "err") || same(name, "type") || same(name, "Vec") || same(name, "Mask") || same(name, "Atomic") || same(name, "target")
}

fn is_builtin_type(name: str) -> bool {
    if same(name, "target") { ret false }
    ret reserved(name) || same(name, "str")
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

fn kind_noun(kind: Kind) -> str {
    if kind == .Type { ret "type" }
    if kind == .Const { ret "const" }
    if kind == .Var { ret "var" }
    if kind == .Error { ret "error" }
    if kind == .Function { ret "function" }
    if kind == .Extern { ret "extern function" }
    if kind == .Qualifier { ret "use qualifier" }
    ret "compiler intrinsic"
}

// A declaration node starts with its keyword, so its first identifier token is the
// declared name. A qualifier symbol carries no tokens and reports without one.
fn symbol_name_token(r: *Resolver, symbol: Symbol) -> (lex.Token, bool) {
    var empty: lex.Token = zero
    if symbol.token_end <= symbol.token_start { ret (empty, false) }
    var at = symbol.token_start
    while at < symbol.token_end && at < r.token_count {
        if r.tokens[at].kind == .Identifier { ret (r.tokens[at], true) }
        at += 1usize
    }
    ret (empty, false)
}

fn record_symbol_failure(r: *Resolver, symbol: Symbol, owner: str) {
    let (token, has_token) = symbol_name_token(r, symbol)
    if !has_token { ret }
    r.failure_module = symbol.module_index
    r.failure_token = token
    r.failure_has_token = true
    r.failure_name = symbol.name
    r.failure_owner = owner
}

fn add(r: *Resolver, symbol: Symbol) -> err {
    if reserved(symbol.name) {
        if symbol.kind != .Qualifier || same(symbol.name, "target") {
            record_symbol_failure(r, symbol, "")
            ret ReservedName
        }
    }
    let (prior_index, duplicate) = find(r, symbol.module_index, symbol.name, symbol.space)
    if duplicate {
        if symbol.kind == .Qualifier || r.symbols[prior_index].kind == .Qualifier {
            record_symbol_failure(r, symbol, "")
            ret QualifierCollision
        }
        record_symbol_failure(r, symbol, kind_noun(r.symbols[prior_index].kind))
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
    try seed(r, g, "e.mem", "view", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "cast", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "bitcast", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "address_of", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "size_of", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "align_of", .Value, .Intrinsic)
    try seed(r, g, "e.str", "format", .Value, .Intrinsic)
    try seed(r, g, "e.str", "push_err", .Value, .Intrinsic)
    try seed(r, g, "e.meta", "kind", .Value, .Intrinsic)
    try seed(r, g, "e.meta", "array_len", .Value, .Intrinsic)
    try seed(r, g, "e.meta", "type_name", .Value, .Intrinsic)
    try seed(r, g, "e.meta", "element_type", .Value, .Intrinsic)
    try seed(r, g, "e.meta", "backing_type", .Value, .Intrinsic)
    try seed(r, g, "e.meta", "Field", .Type, .Type)
    try seed(r, g, "e.meta", "Member", .Type, .Type)
    try seed(r, g, "e.meta", "fields", .Value, .Intrinsic)
    try seed(r, g, "e.meta", "members", .Value, .Intrinsic)
    try seed(r, g, "e.meta", "get", .Value, .Intrinsic)
    try seed(r, g, "e.meta", "set", .Value, .Intrinsic)
    try seed(r, g, "e.io", "printf", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "stats", .Value, .Intrinsic)
    try seed(r, g, "e.mem", "Exhausted", .Value, .Error)
    try seed(r, g, "e.mem", "Stats", .Type, .Type)
    try seed(r, g, "e.os", "open", .Value, .Intrinsic)
    try seed(r, g, "e.math", "sqrt", .Value, .Intrinsic)
    try seed(r, g, "e.os", "read", .Value, .Intrinsic)
    try seed(r, g, "e.os", "write", .Value, .Intrinsic)
    try seed(r, g, "e.os", "close", .Value, .Intrinsic)
    try seed(r, g, "e.os", "seek", .Value, .Intrinsic)
    try seed(r, g, "e.os", "thread_create", .Value, .Intrinsic)
    try seed(r, g, "e.os", "thread_join", .Value, .Intrinsic)
    try seed(r, g, "e.os", "thread_detach", .Value, .Intrinsic)
    try seed(r, g, "e.os", "stdout", .Value, .Intrinsic)
    try seed(r, g, "e.os", "stderr", .Value, .Intrinsic)
    try seed(r, g, "e.os", "readdir", .Value, .Intrinsic)
    try seed(r, g, "e.os", "spawn", .Value, .Intrinsic)
    try seed(r, g, "e.os", "dlsym", .Value, .Intrinsic)
    try seed(r, g, "e.os", "wait", .Value, .Intrinsic)
    try seed(r, g, "e.os", "exit", .Value, .Intrinsic)
    try seed(r, g, "e.os", "args", .Value, .Intrinsic)
    try seed(r, g, "e.os", "reserve", .Value, .Intrinsic)
    try seed(r, g, "e.os", "commit", .Value, .Intrinsic)
    try seed(r, g, "e.os", "clock", .Value, .Intrinsic)
    // Section 5: `os.syscall` exists on Linux alone, so on any other target the name is
    // an unknown name like any other rather than something that fails when called.
    if same(g.os, "linux") { try seed(r, g, "e.os", "syscall", .Value, .Intrinsic) }
    try seed(r, g, "e.os", "wait_u32", .Value, .Intrinsic)
    try seed(r, g, "e.os", "wake_one_u32", .Value, .Intrinsic)
    try seed(r, g, "e.os", "wake_all_u32", .Value, .Intrinsic)
    try seed(r, g, "e.os", "NotFound", .Value, .Error)
    try seed(r, g, "e.os", "Denied", .Value, .Error)
    try seed(r, g, "e.os", "Exists", .Value, .Error)
    try seed(r, g, "e.os", "Interrupted", .Value, .Error)
    try seed(r, g, "e.os", "OutOfMemory", .Value, .Error)
    try seed(r, g, "e.os", "Failed", .Value, .Error)
    try seed(r, g, "e.os", "Timeout", .Value, .Error)
    try seed(r, g, "e.os", "WouldBlock", .Value, .Error)
    try seed(r, g, "e.os", "Unsupported", .Value, .Error)
    // Section 8. Every `e.atomic` function is an intrinsic lowered to one instruction,
    // comptime-generic on `T` inferred from its pointer -- so none is written in
    // `lib/e/atomic.e`, which declares only the `Ordering` they all take.
    try seed(r, g, "e.atomic", "init", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "load", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "store", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "xchg", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "cas", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "add", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "sub", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "and", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "or", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "xor", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "min", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "max", .Value, .Intrinsic)
    try seed(r, g, "e.atomic", "fence", .Value, .Intrinsic)
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
    if same(base, "mem") {
        var entry_at = node.token_start + 1usize
        var entry_state = 0usize
        var valid_entry = true
        while entry_at < node.token_end {
            let entry_token = r.tokens[entry_at]
            if entry_token.kind == .Newline {
                entry_at += 1usize
            } else {
                if entry_state == 0usize && entry_token.kind == .PunctDot {
                    entry_state = 1usize
                } else {
                    if entry_state == 1usize && entry_token.kind == .Identifier {
                        let entry_name = g.modules[module_index].text[entry_token.start..entry_token.end]
                        if same(entry_name, "Arena") {
                            entry_state = 2usize
                        } else {
                            valid_entry = false
                        }
                    } else {
                        valid_entry = false
                    }
                }
                entry_at += 1usize
            }
            if !valid_entry { break }
        }
        if valid_entry && entry_state == 2usize { ret ok }
    }
    var saw_dot = false
    var at = node.token_start + 1usize
    while at < node.token_end {
        let token = r.tokens[at]
        if token.kind == .PunctLBracket { break }
        if token.kind == .PunctDot { saw_dot = true }
        at += 1usize
    }
    if saw_dot {
        if same(base, "target") { ret ok }
        let (target_module, has_qualifier) = qualifier(r, module_index, base)
        if has_qualifier {
            // A trailing `()` means the member is a comptime function whose result is a type,
            // not a type itself, so it is looked for where a function lives. This is the
            // classification section 14's first invariant leaves here: the parser kept the
            // tokens without consulting the symbol table, and only this side can say which of
            // the two a path was.
            // The last two tokens, and nowhere else: a `(` inside the brackets belongs to an
            // ordinary argument, and `Foo[(N << 1u8) | 1usize]` is an instantiation.
            var names_a_value = false
            if node.token_end >= node.token_start + 2usize {
                if r.tokens[node.token_end - 2usize].kind == .PunctLParen && r.tokens[node.token_end - 1usize].kind == .PunctRParen { names_a_value = true }
            }
            at = node.token_start + 1usize
            while at < node.token_end {
                let token = r.tokens[at]
                if token.kind == .PunctLBracket { break }
                if token.kind == .Identifier {
                    let member = g.modules[module_index].text[token.start..token.end]
                    if !exported(r, target_module, member, !names_a_value) { ret UnknownMember }
                    ret ok
                }
                at += 1usize
            }
            ret UnknownMember
        }
        // `f.ty` where `f` is a binding, not a module: section 9's comptime `Field`
        // carries a type, so a value in scope may stand at the head of a type path.
        // Which member is legal there is the checker's to say -- it is the only side
        // that knows whether the binding is a `Field` at all.
        var value_index = r.local_count
        while value_index > 0usize {
            value_index = value_index - 1usize
            if r.locals[value_index].space == .Value && same(r.locals[value_index].name, base) { ret ok }
        }
    }
    var local_index = r.local_count
    while local_index > 0usize {
        local_index = local_index - 1usize
        if r.locals[local_index].space == .Type && same(r.locals[local_index].name, base) { ret ok }
    }
    let (type_index, has_type) = find(r, module_index, base, .Type)
    if has_type || is_builtin_type(base) { ret ok }
    ret UnknownType
}

fn validate_name(r: *Resolver, g: *graph.Graph, module_index: usize, node: syntax.Node) -> err {
    if node.token_start >= r.token_count { ret parse.InvalidSyntax }
    let token = r.tokens[node.token_start]
    if token.kind == .KwUnreachable { ret ok }
    if token.kind != .Identifier { ret parse.InvalidSyntax }
    let name = g.modules[module_index].text[token.start..token.end]
    var local_index = r.local_count
    while local_index > 0usize {
        local_index = local_index - 1usize
        if same(r.locals[local_index].name, name) { ret ok }
    }
    let (value_index, has_value) = find(r, module_index, name, .Value)
    if has_value { ret ok }
    let (type_index, has_type) = find(r, module_index, name, .Type)
    if has_type || is_builtin_type(name) || same(name, "target") { ret ok }
    r.failure_module = module_index
    r.failure_token = token
    r.failure_has_token = true
    ret UnknownName
}

fn module_name_owner(r: *Resolver, module_index: usize, name: str) -> (str, bool) {
    let (type_index, has_type) = find(r, module_index, name, .Type)
    if has_type { ret (kind_noun(r.symbols[type_index].kind), true) }
    let (value_index, has_value) = find(r, module_index, name, .Value)
    if has_value { ret (kind_noun(r.symbols[value_index].kind), true) }
    ret ("", false)
}

fn record_local_failure(r: *Resolver, module_index: usize, token: lex.Token, name: str, owner: str) {
    r.failure_module = module_index
    r.failure_token = token
    r.failure_has_token = true
    r.failure_name = name
    r.failure_owner = owner
}

// Spec section 5: a local or parameter may not reuse a module-scope name of its
// own module, a use qualifier, a builtin type name, or a name already bound in an
// active scope. Every rejection here records the offending token so the caller can
// report where the collision is.
fn add_local(r: *Resolver, g: *graph.Graph, module_index: usize, token: lex.Token, space: Namespace) -> err {
    let name = g.modules[module_index].text[token.start..token.end]
    if reserved(name) {
        record_local_failure(r, module_index, token, name, "")
        ret ReservedLocal
    }
    let (owner, taken) = module_name_owner(r, module_index, name)
    if taken {
        record_local_failure(r, module_index, token, name, owner)
        ret ModuleShadow
    }
    var i = 0usize
    while i < r.local_count {
        if same(r.locals[i].name, name) {
            record_local_failure(r, module_index, token, name, "")
            ret DuplicateLocal
        }
        i += 1usize
    }
    if r.local_count == r.locals.len { ret Capacity }
    r.locals[r.local_count] = Local { name: name, space: space }
    r.local_count += 1usize
    ret ok
}

fn add_first_name(r: *Resolver, g: *graph.Graph, module_index: usize, node: syntax.Node, space: Namespace) -> err {
    var at = node.token_start
    while at < node.token_end {
        let token = r.tokens[at]
        if token.kind == .Identifier {
            try add_local(r, g, module_index, token, space)
            ret ok
        }
        at += 1usize
    }
    if node.token_start < node.token_end && r.tokens[node.token_start].kind == .PunctEllipsis { ret ok }
    ret parse.InvalidSyntax
}

fn add_binding_names(r: *Resolver, g: *graph.Graph, module_index: usize, node: syntax.Node) -> err {
    var at = node.token_start
    while at < node.token_end {
        let token = r.tokens[at]
        if token.kind == .Identifier {
            try add_local(r, g, module_index, token, .Value)
        }
        at += 1usize
    }
    ret ok
}

fn add_for_names(r: *Resolver, g: *graph.Graph, module_index: usize, node: syntax.Node) -> err {
    var at = node.token_start + 1usize
    while at < node.token_end && r.tokens[at].kind != .KwIn {
        let token = r.tokens[at]
        if token.kind == .Identifier {
            try add_local(r, g, module_index, token, .Value)
        }
        at += 1usize
    }
    if at == node.token_end { ret parse.InvalidSyntax }
    ret ok
}

fn add_switch_capture(r: *Resolver, g: *graph.Graph, module_index: usize, node: syntax.Node) -> err {
    var at = node.token_start
    while at < node.token_end {
        if r.tokens[at].kind == .KwAs {
            at += 1usize
            while at < node.token_end {
                let token = r.tokens[at]
                if token.kind == .Identifier {
                    try add_local(r, g, module_index, token, .Value)
                    ret ok
                }
                at += 1usize
            }
            ret parse.InvalidSyntax
        }
        at += 1usize
    }
    ret ok
}

fn visit_children(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            try visit_scope_node(r, g, tree, module_index, tree.children[at].index)
        }
        at += 1usize
    }
    ret ok
}

fn visit_block(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let checkpoint = r.local_count
    let visit_error = visit_children(r, g, tree, module_index, node)
    r.local_count = checkpoint
    ret visit_error
}

fn visit_binding(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let end = node.first_child + node.child_count
    var binding_index = 0usize
    var has_binding = false
    var has_declared_type = false
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if tree.nodes[child_index].kind == .Binding {
                binding_index = child_index
                has_binding = true
            } else {
                let child = tree.nodes[child_index]
                if child.kind == .NamedType || child.kind == .PointerType || child.kind == .SliceType || child.kind == .ArrayType || child.kind == .FunctionType { has_declared_type = true }
                let child_error = visit_scope_node(r, g, tree, module_index, child_index)
                if child_error != ok {
                    if child_error == UnknownName && has_declared_type && node.token_start < r.token_count {
                        r.failure_context_token = r.tokens[node.token_start]
                        r.failure_has_context = true
                    }
                    ret child_error
                }
            }
        }
        at += 1usize
    }
    if !has_binding { ret parse.InvalidSyntax }
    ret add_binding_names(r, g, module_index, tree.nodes[binding_index])
}

fn visit_for(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let checkpoint = r.local_count
    let end = node.first_child + node.child_count
    var block_index = 0usize
    var has_block = false
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if tree.nodes[child_index].kind == .Block {
                block_index = child_index
                has_block = true
            } else {
                let child_error = visit_scope_node(r, g, tree, module_index, child_index)
                if child_error != ok {
                    r.local_count = checkpoint
                    ret child_error
                }
            }
        }
        at += 1usize
    }
    let names_error = add_for_names(r, g, module_index, node)
    if names_error != ok {
        r.local_count = checkpoint
        ret names_error
    }
    if !has_block {
        r.local_count = checkpoint
        ret parse.InvalidSyntax
    }
    let block_error = visit_block(r, g, tree, module_index, tree.nodes[block_index])
    r.local_count = checkpoint
    ret block_error
}

fn visit_switch_arm(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let checkpoint = r.local_count
    let end = node.first_child + node.child_count
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if !is_statement_node(tree.nodes[child_index].kind) {
                let child_error = visit_scope_node(r, g, tree, module_index, child_index)
                if child_error != ok {
                    r.local_count = checkpoint
                    ret child_error
                }
            }
        }
        at += 1usize
    }
    let capture_error = add_switch_capture(r, g, module_index, node)
    if capture_error != ok {
        r.local_count = checkpoint
        ret capture_error
    }
    at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            if is_statement_node(tree.nodes[child_index].kind) {
                let child_error = visit_scope_node(r, g, tree, module_index, child_index)
                if child_error != ok {
                    r.local_count = checkpoint
                    ret child_error
                }
            }
        }
        at += 1usize
    }
    r.local_count = checkpoint
    ret ok
}

fn visit_shared_var(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    try visit_children(r, g, tree, module_index, node)
    var at = node.token_start
    var saw_var = false
    while at < node.token_end {
        let token = r.tokens[at]
        if token.kind == .KwVar {
            saw_var = true
        } else {
            if saw_var && token.kind == .Identifier {
                ret add_local(r, g, module_index, token, .Value)
            }
        }
        at += 1usize
    }
    ret parse.InvalidSyntax
}

fn visit_defer(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let checkpoint = r.local_count
    let visit_error = visit_children(r, g, tree, module_index, node)
    r.local_count = checkpoint
    ret visit_error
}

// Spec section 5: `c` is the target's native C convention and the default, `sysv`
// and `win64` name the two x64 conventions explicitly, and `stdcall` is the Win32
// convention on x86-32 and `c` elsewhere. Anything else is a typo, and saying so here
// is the whole reason attributes are visited rather than skipped.
fn calling_convention(name: str) -> bool {
    ret same(name, "c") || same(name, "sysv") || same(name, "win64") || same(name, "stdcall")
}

fn attribute_name(r: *Resolver, g: *graph.Graph, module_index: usize, node: syntax.Node) -> str {
    let text = g.modules[module_index].text
    var at = node.token_start
    while at < node.token_end {
        if r.tokens[at].kind == .Identifier { ret text[r.tokens[at].start..r.tokens[at].end] }
        at += 1usize
    }
    ret ""
}

fn validate_attribute(r: *Resolver, g: *graph.Graph, module_index: usize, node: syntax.Node) -> err {
    let name = attribute_name(r, g, module_index, node)
    if !same(name, "cc") { ret ok }
    let text = g.modules[module_index].text
    var at = node.token_start
    var seen_name = false
    while at < node.token_end {
        if r.tokens[at].kind == .Identifier {
            if seen_name {
                let convention = text[r.tokens[at].start..r.tokens[at].end]
                if !calling_convention(convention) {
                    record_local_failure(r, module_index, r.tokens[at], convention, "")
                    ret UnknownConvention
                }
                ret ok
            }
            seen_name = true
        }
        at += 1usize
    }
    ret ok
}

fn visit_scope_node(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node_index: usize) -> err {
    let node = tree.nodes[node_index]
    // An attribute's arguments are parsed as expressions but are not values: `c` in
    // `@cc(c)` names a calling convention, not something in scope. Resolving them as
    // values reported `unknown value name` at every `@cc`, so the whole attribute is
    // validated here and not descended into.
    if node.kind == .Attribute { ret validate_attribute(r, g, module_index, node) }
    if node.kind == .NameExpr { ret validate_name(r, g, module_index, node) }
    if node.kind == .NamedType {
        // `target.Arch` / `target.Os` (D223) name no module.
        let type_token = r.tokens[node.token_start]
        if type_token.kind == .Identifier && same(g.modules[module_index].text[type_token.start..type_token.end], "target") && node.token_end >= node.token_start + 3usize {
            let member_token = r.tokens[node.token_end - 1usize]
            let member = g.modules[module_index].text[member_token.start..member_token.end]
            if member_token.kind == .Identifier && (same(member, "Arch") || same(member, "Os")) { ret ok }
        }
        try validate_named_type(r, g, module_index, node)
        ret visit_children(r, g, tree, module_index, node)
    }
    if node.kind == .FieldExpr {
        // `target.arch` / `target.os` (D223): section 2's namespace, no declaration.
        let (target_receiver, has_target_receiver) = first_node_child(tree, node)
        if has_target_receiver && tree.nodes[target_receiver].kind == .NameExpr {
            let target_token = r.tokens[tree.nodes[target_receiver].token_start]
            if target_token.kind == .Identifier && same(g.modules[module_index].text[target_token.start..target_token.end], "target") { ret ok }
        }
        try validate_field(r, g, tree, module_index, node)
    }
    if node.kind == .Block { ret visit_block(r, g, tree, module_index, node) }
    // `when`'s condition names section 6's `target` namespace, which is no declaration:
    // the checker evaluates it, and only the blocks are scope (D216).
    if node.kind == .WhenStmt { ret visit_when(r, g, tree, module_index, node) }
    if node.kind == .BindingStmt { ret visit_binding(r, g, tree, module_index, node) }
    if node.kind == .ForStmt { ret visit_for(r, g, tree, module_index, node) }
    if node.kind == .SwitchArm { ret visit_switch_arm(r, g, tree, module_index, node) }
    if node.kind == .SharedVarStmt { ret visit_shared_var(r, g, tree, module_index, node) }
    if node.kind == .DeferStmt { ret visit_defer(r, g, tree, module_index, node) }
    ret visit_children(r, g, tree, module_index, node)
}

fn is_statement_node(kind: syntax.Kind) -> bool {
    ret kind == .BindingStmt || kind == .AssignmentStmt || kind == .CallStmt || kind == .TryStmt || kind == .ReturnStmt || kind == .DeferStmt || kind == .NocheckStmt || kind == .SharedVarStmt || kind == .BreakStmt || kind == .ContinueStmt || kind == .IfStmt || kind == .WhileStmt || kind == .ForStmt || kind == .WhenStmt || kind == .SwitchStmt || kind == .ErrorNode
}

fn comptime_space(r: *Resolver, node: syntax.Node) -> Namespace {
    var at = node.token_start
    while at < node.token_end {
        if r.tokens[at].kind == .KwType { ret .Type }
        at += 1usize
    }
    ret .Value
}

fn validate_declaration_scope(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    r.local_count = 0usize
    let end = node.first_child + node.child_count
    var block_index = 0usize
    var has_block = false
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            let child = tree.nodes[child_index]
            if child.kind == .ComptimeParam {
                try visit_children(r, g, tree, module_index, child)
                try add_first_name(r, g, module_index, child, comptime_space(r, child))
            }
            if child.kind == .Block {
                block_index = child_index
                has_block = true
            }
        }
        at += 1usize
    }
    at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            let child = tree.nodes[child_index]
            if child.kind == .Parameter {
                try visit_children(r, g, tree, module_index, child)
                try add_first_name(r, g, module_index, child, .Value)
            }
        }
        at += 1usize
    }
    at = node.first_child
    while at < end {
        if tree.children[at].node {
            let child_index = tree.children[at].index
            let child = tree.nodes[child_index]
            if child.kind != .ComptimeParam && child.kind != .Parameter && child.kind != .Block {
                try visit_scope_node(r, g, tree, module_index, child_index)
            }
        }
        at += 1usize
    }
    if has_block { try visit_block(r, g, tree, module_index, tree.nodes[block_index]) }
    r.local_count = 0usize
    ret ok
}

fn validate_top_levels(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize) -> err {
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level {
            if node.kind == .FnDecl || node.kind == .ExternDecl || node.kind == .TypeDecl {
                try validate_declaration_scope(r, g, tree, module_index, node)
            } else {
                r.local_count = 0usize
                try visit_scope_node(r, g, tree, module_index, node_index)
            }
        }
        node_index += 1usize
    }
    ret ok
}

fn validate_module(r: *Resolver, g: *graph.Graph, module_index: usize) -> err {
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, g.nodes, g.children)
    try parse.parse(&tree, g.modules[module_index].text)
    try tokenize(r, g.modules[module_index].text)
    try validate_top_levels(r, g, &tree, module_index)
    ret ok
}

fn collect(r: *Resolver, g: *graph.Graph) -> err {
    r.count = 0usize
    r.failure_has_token = false
    r.failure_has_context = false
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

fn visit_when(r: *Resolver, g: *graph.Graph, tree: *parse.Tree, module_index: usize, node: syntax.Node) -> err {
    let end = node.first_child + node.child_count
    var first = true
    var at = node.first_child
    while at < end {
        if tree.children[at].node {
            if !first { try visit_scope_node(r, g, tree, module_index, tree.children[at].index) }
            first = false
        }
        at += 1usize
    }
    ret ok
}
