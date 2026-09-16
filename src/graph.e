// Transitive source-module loading over the lossless parser's UseDecl nodes.

use e.mem
use e.os
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
    // The module's tree, parsed once when its imports are collected and kept at its
    // own size (D317): every pass reads it, none re-parses.
    tree: parse.Tree,
    has_tree: bool,
    // The tree is a header tree (D392): its non-generic functions have no bodies.
    // Only a module that is declared and never lowered has one -- a rebuilt module
    // is parsed again in full before any pass reads its bodies (`declare_late`), and
    // the comptime interpreter parses a callee's module for itself.
    headers_only: bool,
    first_import: usize,
    import_count: usize,
    visit_state: u8,
    // The manifest's digests (D323), hex, once computed or read from the artifact.
    sha256: str,
    interface_sha256: str,
    // The reproducible spelling (D337): section 2's identity as a path -- `src/` or
    // `lib/` under the project, `lib/` under the toolchain, the basename otherwise,
    // `/`-separated -- for what an image carries, so a build is the same wherever the
    // sources sit and however the operand was spelled.
    spelling: str,
}

fn spelling_of(a: *mem.Arena, g: *Graph, given: str) -> (str, err) {
    var prefix = ""
    var relative = ""
    // A leading `./` is the operand's spelling, not a directory: the project root is
    // discovered as `.` from `src/main.e` and `./src/main.e` alike.
    var path = given
    while path.len > 2usize && path[0usize] == 46u8 && (path[1usize] == 47u8 || path[1usize] == 92u8) { path = path[2usize..path.len] }
    let (src_relative, under_src) = project.relative_under(path, g.project.root, "src")
    let (lib_relative, under_lib) = project.relative_under(path, g.project.root, "lib")
    let (toolchain_relative, under_toolchain) = project.relative_under(path, g.toolchain_root, "lib")
    if under_src && g.project.has_sources {
        prefix = "src/"
        relative = src_relative
    } else {
        if under_lib && g.project.has_sources {
            prefix = "lib/"
            relative = lib_relative
        } else {
            if under_toolchain {
                prefix = "lib/"
                relative = toolchain_relative
            } else {
                var start = 0usize
                var scan = 0usize
                while scan < path.len {
                    if path[scan] == 47u8 || path[scan] == 92u8 { start = scan + 1usize }
                    scan += 1usize
                }
                relative = path[start..path.len]
            }
        }
    }
    let (spelled, spelled_error) = mem.alloc[u8](a, prefix.len + relative.len)
    if spelled_error != ok { ret ("", spelled_error) }
    var at = 0usize
    while at < prefix.len {
        spelled[at] = prefix[at]
        at += 1usize
    }
    var from = 0usize
    while from < relative.len {
        var c = relative[from]
        if c == 92u8 { c = 47u8 }
        spelled[at] = c
        at += 1usize
        from += 1usize
    }
    ret (spelled[0usize..at], ok)
}

type Graph = struct {
    modules: []Module,
    imports: []Import,
    token_scratch: []lex.Token,
    nodes: []syntax.Node,
    children: []u32,
    project: project.Project,
    toolchain_root: str,
    arch: str,
    os: str,
    count: usize,
    import_count: usize,
    failure_module: usize,
    failure_token: lex.Token,
    failure_reserved_name: bool,
    failure_too_deep: bool,
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
    // The source directories listed once (D321).
    listings: project.Listings,
    // The front end's workers and their assignment scratch (D321), and how many modules
    // have had their wave (D322): `begin` sets them up, `wave_imports` advances.
    workers: []Worker,
    assignment: []usize,
    list: []usize,
    // Which modules the next front wave parses as headers only (D392); empty means none.
    want_headers: []bool,
    // The hash of this compiler's executable (D398, H15), written into every artifact
    // and compared on every incremental load; zero when it could not be read.
    compiler_identity: usize,
    scanned: usize,
    // `-j N` (D331): how many workers any phase may run, none asked is the phase's
    // own count; and `--perturb`, the schedule turned around so the harness can ask
    // whether the image depends on it.
    jobs: usize,
    perturb: bool,
    // What every worker arena of every phase committed, summed (D339).
    worker_bytes: usize,
}

// A worker's arena (D339): a reservation of its own, committed as it is touched --
// on Windows by the runtime's commit-on-touch handler, on Linux by the mapping -- so
// a worker charges what it uses, where a carve-out of the root arena charged its
// whole estimate (the root commits to its allocation offset, D306) and the
// two-million-line release build asked for more than a 16 GB machine holds (D338).
// What a worker allocated is added to `g.worker_bytes` when its phase ends, for
// `--stats`.
fn reserved_arena(a: *mem.Arena) -> (mem.Arena, err) {
    var none: mem.Arena = zero
    // One page short of the root's capacity: the mark by which the runtime tells a
    // reservation from the root, which it still commits to its offset.
    let capacity = mem.stats(a).capacity - 4096usize
    let (base, reserve_error) = os.reserve(capacity)
    if reserve_error != ok { ret (none, reserve_error) }
    // The host by the shape of its current directory (D348): `/` first is Linux.
    let (cwd, cwd_error) = os.current_dir(a)
    if cwd_error == ok && cwd.len != 0usize && cwd[0usize] == 47u8 {
        let commit_error = os.commit(base, capacity)
        if commit_error != ok { ret (none, commit_error) }
    }
    var arena: mem.Arena = zero
    arena.base = base
    arena.cap = capacity
    ret (arena, ok)
}

// The bytes a worker's arena reached, rounded up to the runtime's chunk: what it
// committed (D339).
fn arena_touched(arena: *mem.Arena) -> usize {
    let chunks = (mem.stats(arena).used + 1048575usize) / 1048576usize
    ret chunks * 1048576usize
}

// A phase's worker count under `-j N`.
fn worker_cap(g: *Graph, most: usize) -> usize {
    if g.jobs != 0usize && g.jobs < most { ret g.jobs }
    ret most
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
    let (children, children_error) = mem.alloc[u32](a, child_count)
    if children_error != ok { ret children_error }
    g.nodes = nodes
    g.children = children
    g.has_parsed = false
    ret ok
}

// The parsed tree copied out of the pool at its own size, and the module marked as
// holding it (D317).
fn keep_tree(a: *mem.Arena, g: *Graph, module_index: usize, tree: *parse.Tree) -> err {
    let (nodes, nodes_error) = mem.alloc[syntax.Node](a, tree.count + 1usize)
    if nodes_error != ok { ret nodes_error }
    let (children, children_error) = mem.alloc[u32](a, usize(tree.child_count) + 1usize)
    if children_error != ok { ret children_error }
    var at = 0usize
    while at < tree.count {
        nodes[at] = tree.nodes[at]
        at += 1usize
    }
    at = 0usize
    while at < usize(tree.child_count) {
        children[at] = tree.children[at]
        at += 1usize
    }
    var kept = *tree
    kept.nodes = nodes[0usize..tree.count]
    kept.children = children[0usize..tree.child_count]
    g.modules[module_index].tree = kept
    g.modules[module_index].has_tree = true
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

fn init(g: *Graph, modules: []Module, imports: []Import, nodes: []syntax.Node, children: []u32) -> err {
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
    if g.modules[module_index].has_tree {
        *tree = g.modules[module_index].tree
        ret ok
    }
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

// A `use` from the module's own tokens (D316, D321): it lexed the text from its start
// up to the node, per import.
fn extract_import(a: *mem.Arena, text: str, tokens: []const lex.Token, node: syntax.Node) -> (Import, err) {
    let none = Import { name: "", qualifier: "", target: 0usize }
    if usize(node.token_start) >= usize(node.token_end) || usize(node.token_end) > tokens.len { ret (none, parse.InvalidSyntax) }
    if tokens[usize(node.token_start)].kind != .KwUse { ret (none, parse.InvalidSyntax) }
    var module_length = 0usize
    var qualifier = ""
    var after_as = false
    var at = usize(node.token_start)
    while at < usize(node.token_end) {
        let token = tokens[at]
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
        at += 1usize
    }
    if module_length == 0usize || qualifier.len == 0usize { ret (none, parse.InvalidSyntax) }
    let (name, allocation_error) = mem.alloc[u8](a, module_length)
    if allocation_error != ok { ret (none, allocation_error) }
    var written = 0usize
    after_as = false
    at = usize(node.token_start)
    while at < usize(node.token_end) {
        let token = tokens[at]
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
        at += 1usize
    }
    if written != module_length { ret (none, parse.InvalidSyntax) }
    ret (Import { name: name, qualifier: qualifier, target: 0usize }, ok)
}

// The module parsed into the pool and kept, on the main thread: what a worker does in
// its own arena (D321), for the modules a wave's workers did not finish.
fn parse_into_pool(a: *mem.Arena, g: *Graph, module_index: usize) -> err {
    var tree: parse.Tree = zero
    try ensure_tree_pool(a, g, g.modules[module_index].text.len)
    g.has_parsed = false
    try parse.init_tree(&tree, g.nodes, g.children)
    let headers = module_index < g.want_headers.len && g.want_headers[module_index]
    var parse_error = ok
    if headers {
        parse_error = parse.parse_tokens_headers(&tree, g.modules[module_index].text, g.modules[module_index].tokens)
    } else {
        parse_error = parse.parse_tokens(&tree, g.modules[module_index].text, g.modules[module_index].tokens)
    }
    if parse_error == ok {
        try keep_tree(a, g, module_index, &tree)
        g.modules[module_index].headers_only = headers
    }
    if parse_error != ok {
        // Every module is parsed here first, so this is where a syntax error is
        // seen with the module still in hand to name it.
        record_failure(g, module_index, &tree)
        ret parse_error
    }
    ret ok
}

fn record_failure(g: *Graph, module_index: usize, tree: *parse.Tree) {
    if g.has_failure || !tree.has_failure { ret }
    g.failure_module = module_index
    g.failure_token = tree.failure_token
    g.failure_reserved_name = tree.failure_reserved_name
    g.failure_too_deep = tree.failure_too_deep
    g.failure_barrier = tree.failure_count != 0usize && tree.failure_barriers[0usize]
    if g.failure_barrier { g.failure_keyword = tree.failure_keywords[0usize] }
    g.has_failure = true
}

fn collect_imports(a: *mem.Arena, g: *Graph, module_index: usize) -> err {
    if !g.modules[module_index].has_tree { ret parse.InvalidSyntax }
    let tree = g.modules[module_index].tree
    let first_import = g.import_count
    var node_index = 1usize
    while node_index < tree.count {
        let node = tree.nodes[node_index]
        if node.top_level && node.kind == .UseDecl {
            if g.import_count == g.imports.len { ret Capacity }
            let (item, import_error) = extract_import(a, g.modules[module_index].text, g.modules[module_index].tokens, node)
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
        let (candidate_lib, lib_error) = project.select_source(a, &g.listings, g.project.root, "lib", name, g.arch, g.os)
        if lib_error == ok {
            lib_path = candidate_lib
            has_lib = true
        } else {
            if lib_error != project.ModuleNotFound { ret ("", lib_error) }
        }
        let (candidate_src, src_error) = project.select_source(a, &g.listings, g.project.root, "src", name, g.arch, g.os)
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
    let (toolchain_path, toolchain_error) = project.select_source(a, &g.listings, g.toolchain_root, "lib", name, g.arch, g.os)
    if toolchain_error != ok { ret ("", toolchain_error) }
    ret (toolchain_path, ok)
}

// A module by name and path; its text, line table, tokens and tree come with the
// wave that scans it (D321).
fn add_module(a: *mem.Arena, g: *Graph, name: str, path: str) -> (usize, err) {
    if g.count == g.modules.len { ret (0usize, Capacity) }
    let index = g.count
    var no_tokens: [1]lex.Token = zero
    var no_lines: [1]usize = zero
    var no_tree: parse.Tree = zero
    let (spelling, spelling_error) = spelling_of(a, g, path)
    if spelling_error != ok { ret (0usize, spelling_error) }
    g.modules[index] = Module { name: name, path: path, text: "", lines: no_lines[0usize..0usize], tokens: no_tokens[0usize..0usize], has_invalid: false, tree: no_tree, has_tree: false, headers_only: false, first_import: 0usize, import_count: 0usize, visit_state: 0u8, sha256: "", interface_sha256: "", spelling: spelling }
    g.count += 1usize
    ret (index, ok)
}

// The front end of one module on the main thread, out of the pools: what a worker
// does, for the modules a wave's workers did not finish.
fn scan_and_parse(a: *mem.Arena, g: *Graph, module_index: usize) -> err {
    let (lines, lines_error) = lex.line_starts(a, g.modules[module_index].text)
    if lines_error != ok { ret lines_error }
    g.modules[module_index].lines = lines
    try scan_module(a, g, module_index)
    ret parse_into_pool(a, g, module_index)
}

// The front end in waves (D321): every module a wave discovered is scanned and parsed by
// one of a few workers, each into an arena of its own carved from the program's, while
// the main thread does nothing but wait. A worker writes only its own modules' slots and
// allocates only from its own arena, so nothing is shared that is written, and no lock
// exists. The wave's imports are then walked on the main thread, in module order -- the
// order the one-at-a-time loop discovered modules in, so the indices are the same --
// and what they name is the next wave. A worker that ran out of its arena or found a
// module too dense for its scratch leaves the rest of its modules to the main thread,
// which does them one at a time out of the pools; a syntax error is the lowest module's.
const FRONT_WORKERS: usize = 8usize

type Worker = struct {
    g: *Graph,
    arena: mem.Arena,
    modules: []usize,
    count: usize,
    token_scratch: []lex.Token,
    nodes: []syntax.Node,
    children: []u32,
    // Where the worker stopped, if it did: the module and why. A syntax failure keeps
    // the tree's account of it for the graph to name.
    stopped: bool,
    stopped_at: usize,
    failure: err,
    syntax_failure: bool,
    failure_tree: parse.Tree,
}

fn worker_module(w: *Worker, module_index: usize) -> err {
    let text = w.g.modules[module_index].text
    let (lines, lines_error) = lex.line_starts(&w.arena, text)
    if lines_error != ok { ret lines_error }
    w.g.modules[module_index].lines = lines
    var scanner = lex.init(text)
    var count = 0usize
    var invalid = false
    while true {
        if count == w.token_scratch.len { ret Capacity }
        let token = lex.next(&scanner)
        if token.kind == .Invalid { invalid = true }
        w.token_scratch[count] = token
        count += 1usize
        if token.kind == .Eof { break }
    }
    let (tokens, tokens_error) = mem.alloc[lex.Token](&w.arena, count)
    if tokens_error != ok { ret tokens_error }
    var at = 0usize
    while at < count {
        tokens[at] = w.token_scratch[at]
        at += 1usize
    }
    w.g.modules[module_index].tokens = tokens
    w.g.modules[module_index].has_invalid = invalid
    var tree: parse.Tree = zero
    try parse.init_tree(&tree, w.nodes, w.children)
    // A module wanted as headers only (D392) is parsed without its function bodies.
    let headers = module_index < w.g.want_headers.len && w.g.want_headers[module_index]
    var parse_error = ok
    if headers {
        parse_error = parse.parse_tokens_headers(&tree, text, tokens)
    } else {
        parse_error = parse.parse_tokens(&tree, text, tokens)
    }
    if parse_error != ok {
        if tree.has_failure {
            w.syntax_failure = true
            w.failure_tree = tree
        }
        ret parse_error
    }
    try keep_tree(&w.arena, w.g, module_index, &tree)
    w.g.modules[module_index].headers_only = headers
    ret ok
}

fn worker_entry(w: *Worker) {
    var at = 0usize
    while at < w.count {
        let module_index = w.modules[at]
        let module_error = worker_module(w, module_index)
        if module_error != ok {
            w.stopped = true
            w.stopped_at = at
            w.failure = module_error
            ret
        }
        at += 1usize
    }
}

// The kept token, line and tree bytes per text byte, measured with room: a token per
// five bytes, a node per four and a child per two. A denser module exhausts the
// worker's arena and falls back to the main thread.
fn worker_arena_bytes(text_bytes: usize) -> usize {
    ret text_bytes * 16usize + 65536usize
}

// The front end over a list of modules (D322): a wave's modules, or the unchanged
// modules a hot build finds it needs after all.
fn front_modules(a: *mem.Arena, g: *Graph, modules: []const usize) -> err {
    let wave_count = modules.len
    if wave_count == 0usize { ret ok }
    let workers = g.workers
    let assignment = g.assignment
    var worker_count = wave_count
    if worker_count > workers.len { worker_count = workers.len }
    // Each module goes to the worker with the least text so far, largest first, so the
    // wave takes about as long as its share and not as long as its largest few
    // modules together. The assignment array holds each worker's modules in list
    // order, in worker-major runs, then the list's modules by size, then each list
    // position's worker.
    let capacity = g.modules.len
    let order = assignment[capacity..capacity + wave_count]
    let owner = assignment[capacity * 2usize..capacity * 2usize + wave_count]
    var loads: [64]usize = zero
    var worker_at = 0usize
    while worker_at < worker_count {
        loads[worker_at] = 0usize
        worker_at += 1usize
    }
    var order_at = 0usize
    while order_at < wave_count {
        order[order_at] = order_at
        order_at += 1usize
    }
    order_at = 0usize
    while order_at < wave_count {
        var best = order_at
        var scan = order_at + 1usize
        while scan < wave_count {
            if g.modules[modules[order[scan]]].text.len > g.modules[modules[order[best]]].text.len { best = scan }
            scan += 1usize
        }
        let swap = order[order_at]
        order[order_at] = order[best]
        order[best] = swap
        var lightest = 0usize
        worker_at = 1usize
        while worker_at < worker_count {
            if loads[worker_at] < loads[lightest] { lightest = worker_at }
            worker_at += 1usize
        }
        loads[lightest] += g.modules[modules[order[order_at]]].text.len
        owner[order[order_at]] = lightest
        order_at += 1usize
    }
    worker_at = 0usize
    var filled = 0usize
    while worker_at < worker_count {
        var bytes = 0usize
        var largest = 0usize
        let first = filled
        var list_at = 0usize
        while list_at < wave_count {
            if owner[list_at] == worker_at {
                let module_at = modules[list_at]
                assignment[filled] = module_at
                filled += 1usize
                bytes += g.modules[module_at].text.len
                if g.modules[module_at].text.len > largest { largest = g.modules[module_at].text.len }
            }
            list_at += 1usize
        }
        workers[worker_at].g = g
        workers[worker_at].modules = assignment[first..filled]
        workers[worker_at].count = filled - first
        workers[worker_at].stopped = false
        workers[worker_at].syntax_failure = false
        workers[worker_at].failure = ok
        // One reservation per worker for every wave (D339): what a wave parsed stays.
        if workers[worker_at].arena.cap == 0usize {
            let (arena, arena_error) = reserved_arena(a)
            if arena_error != ok { ret arena_error }
            workers[worker_at].arena = arena
        }
        // The scratch grows to the largest module the worker has seen, out of the
        // program's arena; a token per two bytes is the densest text it handles.
        let tokens_needed = largest / 2usize + 64usize
        if workers[worker_at].token_scratch.len < tokens_needed {
            let (scratch, scratch_error) = mem.alloc[lex.Token](a, tokens_needed)
            if scratch_error != ok { ret scratch_error }
            workers[worker_at].token_scratch = scratch
        }
        let nodes_needed = largest / 2usize + 4096usize
        if workers[worker_at].nodes.len < nodes_needed {
            let (nodes, nodes_error) = mem.alloc[syntax.Node](a, nodes_needed)
            if nodes_error != ok { ret nodes_error }
            workers[worker_at].nodes = nodes
        }
        let children_needed = largest + 8192usize
        if workers[worker_at].children.len < children_needed {
            let (children, children_error) = mem.alloc[u32](a, children_needed)
            if children_error != ok { ret children_error }
            workers[worker_at].children = children
        }
        worker_at += 1usize
    }
    // The workers after the first run on threads of their own; the first runs here. A
    // thread that cannot be started runs here too, after the others.
    var threads: [64]os.Thread = zero
    var started: [64]bool = zero
    worker_at = 1usize
    while worker_at < worker_count {
        started[worker_at] = false
        let (thread, spawn_error) = os.thread_create[Worker](worker_entry, &workers[worker_at], 4194304usize)
        if spawn_error == ok {
            threads[worker_at] = thread
            started[worker_at] = true
        }
        worker_at += 1usize
    }
    worker_entry(&workers[0usize])
    worker_at = 1usize
    while worker_at < worker_count {
        if started[worker_at] {
            try os.thread_join(threads[worker_at])
        } else {
            worker_entry(&workers[worker_at])
        }
        worker_at += 1usize
    }
    // What the workers left: a syntax failure is the lowest such module's, reported as
    // the one-at-a-time loop would have; any other stop hands the worker's remaining
    // modules to the main thread.
    var lowest_failure = g.count
    var lowest_worker = 0usize
    worker_at = 0usize
    while worker_at < worker_count {
        if workers[worker_at].stopped && workers[worker_at].syntax_failure {
            let failed = workers[worker_at].modules[workers[worker_at].stopped_at]
            if failed < lowest_failure {
                lowest_failure = failed
                lowest_worker = worker_at
            }
        }
        worker_at += 1usize
    }
    if lowest_failure < g.count {
        record_failure(g, lowest_failure, &workers[lowest_worker].failure_tree)
        ret workers[lowest_worker].failure
    }
    worker_at = 0usize
    while worker_at < worker_count {
        if workers[worker_at].stopped {
            var remaining = workers[worker_at].stopped_at
            while remaining < workers[worker_at].count {
                try scan_and_parse(a, g, workers[worker_at].modules[remaining])
                remaining += 1usize
            }
        }
        worker_at += 1usize
    }
    ret ok
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
// The loader in steps (D322), so a hot build can put its artifacts between them: a
// module unchanged since its artifact takes its imports from the artifact and is not
// parsed unless something that changed imports it.
fn begin(a: *mem.Arena, g: *Graph, root_path: str, toolchain_root: str, arch: str, host_os: str, project_root: str) -> err {
    if !project.valid_arch(arch) || !project.valid_os(host_os) || !project.valid_target(arch, host_os) { ret project.InvalidTarget }
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
    g.os = host_os
    g.count = 0usize
    g.import_count = 0usize
    g.scanned = 0usize
    let (root_index, root_error) = add_module(a, g, root_name, root_path)
    if root_error != ok { ret root_error }
    let (workers, workers_error) = mem.alloc[Worker](a, worker_cap(g, FRONT_WORKERS))
    if workers_error != ok { ret workers_error }
    var clear_at = 0usize
    while clear_at < workers.len {
        var blank: Worker = zero
        workers[clear_at] = blank
        clear_at += 1usize
    }
    g.workers = workers
    let (assignment, assignment_error) = mem.alloc[usize](a, g.modules.len * 3usize)
    if assignment_error != ok { ret assignment_error }
    g.assignment = assignment
    let (list, list_error) = mem.alloc[usize](a, g.modules.len)
    if list_error != ok { ret list_error }
    g.list = list
    let (want_headers, want_headers_error) = mem.alloc[bool](a, g.modules.len)
    if want_headers_error != ok { ret want_headers_error }
    var headers_at = 0usize
    while headers_at < want_headers.len {
        want_headers[headers_at] = false
        headers_at += 1usize
    }
    g.want_headers = want_headers
    ret ok
}

// The texts of the modules discovered since the last wave.
fn wave_texts(a: *mem.Arena, g: *Graph, wave_start: usize, wave_end: usize) -> err {
    var module_index = wave_start
    while module_index < wave_end {
        let (text, load_error) = source.load(a, g.modules[module_index].path)
        if load_error != ok { ret load_error }
        g.modules[module_index].text = text
        g.total_bytes += text.len
        if text.len > g.largest_bytes { g.largest_bytes = text.len }
        module_index += 1usize
    }
    ret ok
}

// An import a module's artifact recorded (D322), in place of parsing it: a module's
// imports are added together, before any other module's.
fn add_import(g: *Graph, module_index: usize, name: str, qualifier: str) -> err {
    if g.import_count == g.imports.len { ret Capacity }
    if g.modules[module_index].import_count == 0usize {
        g.modules[module_index].first_import = g.import_count
    } else {
        if g.modules[module_index].first_import + g.modules[module_index].import_count != g.import_count { ret Capacity }
    }
    g.imports[g.import_count] = Import { name: name, qualifier: qualifier, target: 0usize }
    g.import_count += 1usize
    g.modules[module_index].import_count += 1usize
    ret ok
}

// The wave's imports, in module order -- the order the one-at-a-time loop discovered
// modules in, so the indices are the same -- and what they name is the next wave. A
// parsed module's come from its tree; an unparsed one's were added already.
fn wave_imports(a: *mem.Arena, g: *Graph, wave_start: usize, wave_end: usize) -> err {
    var module_index = wave_start
    while module_index < wave_end {
        if g.modules[module_index].has_tree { try collect_imports(a, g, module_index) }
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
    g.scanned = wave_end
    ret ok
}

fn finish(g: *Graph) -> err {
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

fn load(a: *mem.Arena, g: *Graph, root_path: str, toolchain_root: str, arch: str, host_os: str, project_root: str) -> err {
    try begin(a, g, root_path, toolchain_root, arch, host_os, project_root)
    while g.scanned < g.count {
        let wave_start = g.scanned
        let wave_end = g.count
        try wave_texts(a, g, wave_start, wave_end)
        var module_index = wave_start
        while module_index < wave_end {
            g.list[module_index - wave_start] = module_index
            module_index += 1usize
        }
        try front_modules(a, g, g.list[0usize..wave_end - wave_start])
        try wave_imports(a, g, wave_start, wave_end)
    }
    ret finish(g)
}
