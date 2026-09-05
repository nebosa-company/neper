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
    first_import: usize,
    import_count: usize,
    visit_state: u8,
}

type Graph = struct {
    modules: []Module,
    imports: []Import,
    nodes: []syntax.Node,
    children: []syntax.Child,
    project: project.Project,
    toolchain_root: str,
    arch: str,
    os: str,
    count: usize,
    import_count: usize,
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

fn init(g: *Graph, modules: []Module, imports: []Import, nodes: []syntax.Node, children: []syntax.Child) -> err {
    if modules.len == 0usize || imports.len == 0usize || nodes.len == 0usize || children.len == 0usize { ret Capacity }
    g.modules = modules
    g.imports = imports
    g.nodes = nodes
    g.children = children
    g.count = 0usize
    g.import_count = 0usize
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
    try parse.init_tree(&tree, g.nodes, g.children)
    let parse_error = parse.parse(&tree, g.modules[module_index].text)
    if parse_error != ok { ret parse_error }
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
    g.modules[index] = Module { name: name, path: path, text: text, first_import: 0usize, import_count: 0usize, visit_state: 0u8 }
    g.count += 1usize
    ret (index, ok)
}

fn visit(g: *Graph, module_index: usize) -> err {
    g.modules[module_index].visit_state = 1u8
    let end = g.modules[module_index].first_import + g.modules[module_index].import_count
    var i = g.modules[module_index].first_import
    while i < end {
        let target = g.imports[i].target
        if g.modules[target].visit_state == 1u8 { ret ImportCycle }
        if g.modules[target].visit_state == 0u8 {
            let visit_error = visit(g, target)
            if visit_error != ok { ret visit_error }
        }
        i += 1usize
    }
    g.modules[module_index].visit_state = 2u8
    ret ok
}

fn load(a: *mem.Arena, g: *Graph, root_path: str, toolchain_root: str, arch: str, os: str) -> err {
    if !project.valid_arch(arch) || !project.valid_os(os) || !project.valid_target(arch, os) { ret project.InvalidTarget }
    let (discovered, discovery_error) = project.discover(a, root_path)
    if discovery_error != ok { ret discovery_error }
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
                if resolve_error != ok { ret resolve_error }
                let (target, add_error) = add_module(a, g, g.imports[import_index].name, path)
                if add_error != ok { ret add_error }
                g.imports[import_index].target = target
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
