// Transitive source-module loading over the lossless parser's UseDecl nodes.

use e.mem
use lex
use parse
use project
use source
use syntax

error Capacity
error DuplicateModule
error DuplicateQualifier
error ImportCycle

type Import = struct {
    name: str,
    qualifier: str,
    target: usize,
}

type Module = struct {
    name: str,
    path: str,
    text: str,
    // Where the text's lines begin (D315): tokens carry offsets, and a line is looked
    // up here when a diagnostic, a trap record or a tooling record asks.
    lines: []usize,
    // The module's tokens, scanned once when it is loaded (D316): every pass parses
    // from these, and the resolver's and checker's token tables point at them.
    tokens: []lex.Token,
    // Whether the scanner refused a byte: the parse reports it, a later pass refuses.
    has_invalid: bool,
    first_import: usize,
    import_count: usize,
    visit_state: u8,
}

type Graph = struct {
    modules: []Module,
    imports: []Import,
    token_scratch: []lex.Token,
    nodes: []syntax.Node,
    children: []syntax.Child,
    project: project.Project,
    toolchain_root: str,
    arch: str,
    os: str,
    count: usize,
    import_count: usize,
    failure_module: usize,
    failure_token: lex.Token,
    failure_reserved_name: bool,
    failure_barrier: bool,
    failure_keyword: lex.Token,
    has_failure: bool,
    // A `use` that names no module, or one that closes a cycle: the importing module
    // and the name, for the E-MODULE diagnostics (D215).
    failure_import: str,
    has_import_failure: bool,
    // Dependency order (D304): `visit`'s post-order, so every module follows the ones
    // it imports and the root is last. Recorded when `order` has room.
    order: []usize,
    order_count: usize,
    // The one tree the node pool holds (D304). Every parse into the pool goes through
    // `parse_module`, so a hit is always the tree still in the pool; the per-module
    // sweep asks for the same module phase after phase and parses it once.
    parsed: parse.Tree,
    parsed_module: usize,
    has_parsed: bool,
    // What the program measures (D306): every pool after loading is sized from these.
    total_bytes: usize,
    largest_bytes: usize,
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

// The tree pool holds one module at a time and is sized for the largest (D306): when a
// module needs more than it has, a larger one replaces it and the old one is left
// behind -- doubled each time, so what is left behind is under what is kept.
fn ensure_tree_pool(a: *mem.Arena, g: *Graph, bytes: usize) -> err {
    // A node per four bytes and a child per two, measured; twice that here.
    let nodes_needed = bytes / 2usize + 4096usize
    let children_needed = bytes + 8192usize
    if g.nodes.len >= nodes_needed && g.children.len >= children_needed { ret ok }
    var node_count = g.nodes.len * 2usize
    if node_count < nodes_needed { node_count = nodes_needed }
    var child_count = g.children.len * 2usize
    if child_count < children_needed { child_count = children_needed }
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, node_count)
    if nodes_error != ok { ret nodes_error }
    let (children, children_error) = mem.alloc[syntax.Child](a, child_count)
    if children_error != ok { ret children_error }
    g.nodes = nodes
    g.children = children
    g.has_parsed = false
    ret ok
}

// Scratch for one module's tokens as they are scanned, before the exact copy is taken:
// at most a token per byte, plus the end.
fn ensure_token_pool(a: *mem.Arena, g: *Graph, bytes: usize) -> err {
    let needed = bytes + 16usize
    if g.token_scratch.len >= needed { ret ok }
    var count = g.token_scratch.len * 2usize
    if count < needed { count = needed }
    let (scratch, scratch_error) = mem.alloc[lex.Token](a, count)
    if scratch_error != ok { ret scratch_error }
    g.token_scratch = scratch
    ret ok
}

// A module's tokens, scanned once into the scratch and kept at their own size.
fn scan_module(a: *mem.Arena, g: *Graph, module_index: usize) -> err {
    let text = g.modules[module_index].text
    try ensure_token_pool(a, g, text.len)
    var scanner = lex.init(text)
    var count = 0usize
    var invalid = false
    while true {
        if count == g.token_scratch.len { ret Capacity }
        let token = lex.next(&scanner)
        if token.kind == .Invalid { invalid = true }
        g.token_scratch[count] = token
        count += 1usize
        if token.kind == .Eof { break }
    }
    let (tokens, tokens_error) = mem.alloc[lex.Token](a, count)
    if tokens_error != ok { ret tokens_error }
    var at = 0usize
    while at < count {
        tokens[at] = g.token_scratch[at]
        at += 1usize
    }
    g.modules[module_index].tokens = tokens
    g.modules[module_index].has_invalid = invalid
    ret ok
}

fn init(g: *Graph, modules: []Module, imports: []Import, nodes: []syntax.Node, children: []syntax.Child) -> err {
    if modules.len == 0usize || imports.len == 0usize || nodes.len == 0usize || children.len == 0usize { ret Capacity }
    g.modules = modules
    g.imports = imports
    g.nodes = nodes
    g.children = children
    g.count = 0usize
    g.import_count = 0usize
    g.order = g.order[0usize..0usize]
    g.order_count = 0usize
    g.has_parsed = false
    g.total_bytes = 0usize
    g.largest_bytes = 0usize
    ret ok
}

fn set_order(g: *Graph, order: []usize) {
    g.order = order
    g.order_count = 0usize
}

// The module's tree, parsed into the pool unless it is what the pool already holds.
fn parse_module(g: *Graph, module_index: usize, tree: *parse.Tree) -> err {
    if g.has_parsed && g.parsed_module == module_index {
        *tree = g.parsed
        ret ok
    }
    g.has_parsed = false
    try parse.init_tree(tree, g.nodes, g.children)
    let parse_error = parse.parse_tokens(tree, g.modules[module_index].text, g.modules[module_index].tokens)
    if parse_error != ok { ret parse_error }
    g.parsed = *tree
    g.parsed_module = module_index
    g.has_parsed = true
    ret ok
}

fn find_module(g: *Graph, name: str) -> (usize, bool) {
    var i = 0usize
    while i < g.count {
        if same(g.modules[i].name, name) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn has_module(g: *Graph, name: str) -> bool {
    let (index, found) = find_module(g, name)
    ret found
}

fn extract_import(a: *mem.Arena, text: str, node: syntax.Node) -> (Import, err) {
    var scanner = lex.init(text)
    var token = lex.next(&scanner)
    var token_index = 0usize
    while token_index < node.token_start {
        token = lex.next(&scanner)
        token_index += 1usize
    }
    if token.kind != .KwUse { ret (Import { name: "", qualifier: "", target: 0usize }, parse.InvalidSyntax) }
    var module_length = 0usize
    var qualifier = ""
    var after_as = false
    while token_index < node.token_end {
        if token.kind == .KwAs {
            after_as = true
        } else {
            if token.kind == .Identifier {
                if after_as {
                    qualifier = text[token.start..token.end]
                } else {
                    module_length += token.end - token.start
                    qualifier = text[token.start..token.end]
                }
            } else {
                if token.kind == .PunctDot && !after_as { module_length += 1usize }
            }
        }
        token = lex.next(&scanner)
        token_index += 1usize
    }
    if module_length == 0usize || qualifier.len == 0usize { ret (Import { name: "", qualifier: "", target: 0usize }, parse.InvalidSyntax) }
    let (name, allocation_error) = mem.alloc[u8](a, module_length)
    if allocation_error != ok { ret (Import { name: "", qualifier: "", target: 0usize }, allocation_error) }
    scanner = lex.init(text)
    token = lex.next(&scanner)
    token_index = 0usize
    while token_index < node.token_start {
        token = lex.next(&scanner)
        token_index += 1usize
    }
    var written = 0usize
    after_as = false
    while token_index < node.token_end {
        if token.kind == .KwAs {
            after_as = true
        } else {
            if token.kind == .Identifier && !after_as {
                var i = token.start
                while i < token.end {
                    name[written] = text[i]
                    written += 1usize
                    i += 1usize
                }
            } else {
                if token.kind == .PunctDot && !after_as {
                    name[written] = 46u8
                    written += 1usize
                }
            }
        }
        token = lex.next(&scanner)
        token_index += 1usize
    }
    if written != module_length { ret (Import { name: "", qualifier: "", target: 0usize }, parse.InvalidSyntax) }
    ret (Import { name: name, qualifier: qualifier, target: 0usize }, ok)
}

fn collect_imports(a: *mem.Arena, g: *Graph, module_index: usize) -> err {
    var tree: parse.Tree = zero
    try ensure_tree_pool(a, g, g.modules[module_index].text.len)
    g.has_parsed = false
    try parse.init_tree(&tree, g.nodes, g.children)
    let parse_error = parse.parse_tokens(&tree, g.modules[module_index].text, g.modules[module_index].tokens)
    if parse_error != ok {
        // Every module is parsed here first, so this is where a syntax error is
        // seen with the module still in hand to name it.
        if !g.has_failure && tree.has_failure {
            g.failure_module = module_index
            g.failure_token = tree.failure_token
            g.failure_reserved_name = tree.failure_reserved_name
            g.failure_barrier = tree.failure_count != 0usize && tree.failure_barriers[0usize]
            if g.failure_barrier { g.failure_keyword = tree.failure_keywords[0usize] }
            g.has_failure = true
        }
        ret parse_error
    }
    let first_import = g.import_count
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .UseDecl {
            if g.import_count == g.imports.len { ret Capacity }
            let (item, import_error) = extract_import(a, g.modules[module_index].text, node)
            if import_error != ok { ret import_error }
            var prior = first_import
            while prior < g.import_count {
                if same(g.imports[prior].qualifier, item.qualifier) { ret DuplicateQualifier }
                prior += 1usize
            }
            g.imports[g.import_count] = item
            g.import_count += 1usize
        }
        node_index += 1usize
    }
    g.modules[module_index].first_import = first_import
    g.modules[module_index].import_count = g.import_count - first_import
    ret ok
}

fn resolve_source(a: *mem.Arena, g: *Graph, name: str) -> (str, err) {
    var lib_path = ""
    var src_path = ""
    var has_lib = false
    var has_src = false
    if g.project.has_sources {
        let (candidate_lib, lib_error) = project.select_source(a, g.project.root, "lib", name, g.arch, g.os)
        if lib_error == ok {
            lib_path = candidate_lib
            has_lib = true
        } else {
            if lib_error != project.ModuleNotFound { ret ("", lib_error) }
        }
        let (candidate_src, src_error) = project.select_source(a, g.project.root, "src", name, g.arch, g.os)
        if src_error == ok {
            src_path = candidate_src
            has_src = true
        } else {
            if src_error != project.ModuleNotFound { ret ("", src_error) }
        }
    }
    if has_lib && has_src { ret ("", DuplicateModule) }
    if has_lib { ret (lib_path, ok) }
    if has_src { ret (src_path, ok) }
    let (toolchain_path, toolchain_error) = project.select_source(a, g.toolchain_root, "lib", name, g.arch, g.os)
    if toolchain_error != ok { ret ("", toolchain_error) }
    ret (toolchain_path, ok)
}

fn add_module(a: *mem.Arena, g: *Graph, name: str, path: str) -> (usize, err) {
    if g.count == g.modules.len { ret (0usize, Capacity) }
    let (text, load_error) = source.load(a, path)
    if load_error != ok { ret (0usize, load_error) }
    let index = g.count
    let (lines, lines_error) = lex.line_starts(a, text)
    if lines_error != ok { ret (0usize, lines_error) }
    var no_tokens: [1]lex.Token = zero
    g.modules[index] = Module { name: name, path: path, text: text, lines: lines, tokens: no_tokens[0usize..0usize], has_invalid: false, first_import: 0usize, import_count: 0usize, visit_state: 0u8 }
    g.count += 1usize
    let scan_error = scan_module(a, g, index)
    if scan_error != ok { ret (0usize, scan_error) }
    g.total_bytes += text.len
    if text.len > g.largest_bytes { g.largest_bytes = text.len }
    ret (index, ok)
}

fn visit(g: *Graph, module_index: usize) -> err {
    g.modules[module_index].visit_state = 1u8
    let end = g.modules[module_index].first_import + g.modules[module_index].import_count
    var i = g.modules[module_index].first_import
    while i < end {
        let target_module = g.imports[i].target
        if g.modules[target_module].visit_state == 1u8 {
            g.failure_module = module_index
            g.failure_import = g.imports[i].name
            g.has_import_failure = true
            ret ImportCycle
        }
        if g.modules[target_module].visit_state == 0u8 {
            let visit_error = visit(g, target_module)
            if visit_error != ok { ret visit_error }
        }
        i += 1usize
    }
    g.modules[module_index].visit_state = 2u8
    if g.order_count < g.order.len {
        g.order[g.order_count] = module_index
        g.order_count += 1usize
    }
    ret ok
}

// `project_root` names the project explicitly; empty, it is discovered from the operand
// (spec section 2). A file outside the project -- a generated test runner -- is built
// as part of it that way (D263).
fn load(a: *mem.Arena, g: *Graph, root_path: str, toolchain_root: str, arch: str, os: str, project_root: str) -> err {
    if !project.valid_arch(arch) || !project.valid_os(os) || !project.valid_target(arch, os) { ret project.InvalidTarget }
    var discovered = project.explicit(project_root)
    if project_root.len == 0usize {
        let (found, discovery_error) = project.discover(a, root_path)
        if discovery_error != ok { ret discovery_error }
        discovered = found
    }
    let (root_name, name_error) = project.module_name(a, discovered, root_path)
    if name_error != ok { ret name_error }
    g.project = discovered
    g.toolchain_root = toolchain_root
    g.arch = arch
    g.os = os
    g.count = 0usize
    g.import_count = 0usize
    let (root_index, root_error) = add_module(a, g, root_name, root_path)
    if root_error != ok { ret root_error }
    var module_index = 0usize
    while module_index < g.count {
        try collect_imports(a, g, module_index)
        let end = g.modules[module_index].first_import + g.modules[module_index].import_count
        var import_index = g.modules[module_index].first_import
        while import_index < end {
            let (existing, found) = find_module(g, g.imports[import_index].name)
            if found {
                g.imports[import_index].target = existing
            } else {
                let (path, resolve_error) = resolve_source(a, g, g.imports[import_index].name)
                if resolve_error != ok {
                    g.failure_module = module_index
                    g.failure_import = g.imports[import_index].name
                    g.has_import_failure = true
                    ret resolve_error
                }
                let (added_module, add_error) = add_module(a, g, g.imports[import_index].name, path)
                if add_error != ok { ret add_error }
                g.imports[import_index].target = added_module
            }
            import_index += 1usize
        }
        module_index += 1usize
    }
    var i = 0usize
    while i < g.count {
        if g.modules[i].visit_state == 0u8 {
            let cycle_error = visit(g, i)
            if cycle_error != ok { ret cycle_error }
        }
        i += 1usize
    }
    ret ok
}
