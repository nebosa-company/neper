use lex
use graph
use e.mem

// The module-scope declarations nothing names: `check --unused-code`. A declaration is
// a `fn`, `const`, `type`, `error` or `var` at brace depth 0 that opens its line. Its
// name is named when an identifier spelling it stands anywhere in the loaded modules
// beyond the declarations themselves, so a local, a field or another module's
// declaration of the same name counts as naming it: the answer errs toward "used".
// Left out: `main`, `extern`, anything an attribute line precedes, and a function
// spelled `<type>_<word>`, which a protocol finds by name.

type Found = struct {
    module: usize,
    token: usize,
    kind: u8,
}

fn slot(text: str) -> usize {
    var h = 0usize
    var at = 0usize
    while at < text.len {
        h = (h * 31usize + usize(text[at])) & 1048575usize
        at += 1usize
    }
    ret h
}

fn line_start(tokens: []const lex.Token, at: usize) -> usize {
    var k = at
    while k > 0usize && tokens[k - 1usize].kind != .Newline { k = k - 1usize }
    ret k
}

fn decl_kind(kind: lex.Kind) -> usize {
    if kind == .KwFn { ret 1usize }
    if kind == .KwConst { ret 2usize }
    if kind == .KwType { ret 3usize }
    if kind == .KwError { ret 4usize }
    if kind == .KwVar { ret 5usize }
    ret 0usize
}

fn attributed(tokens: []const lex.Token, at: usize) -> bool {
    if at == 0usize { ret false }
    let above = line_start(tokens, at - 1usize)
    ret above < tokens.len && tokens[above].kind == .PunctAt
}

fn folded_same(a: str, b: str) -> bool {
    var i = 0usize
    var j = 0usize
    while true {
        while i < a.len && a[i] == 95u8 { i += 1usize }
        while j < b.len && b[j] == 95u8 { j += 1usize }
        if i == a.len || j == b.len { ret i == a.len && j == b.len }
        var x = a[i]
        var y = b[j]
        if x >= 65u8 && x <= 90u8 { x += 32u8 }
        if y >= 65u8 && y <= 90u8 { y += 32u8 }
        if x != y { ret false }
        i += 1usize
        j += 1usize
    }
    ret false
}

// A protocol function is `<type>_<word>` for a type declared in the module.
fn protocol_fn(source: str, tokens: []const lex.Token, name: str) -> bool {
    var cut = name.len
    while cut > 0usize && name[cut - 1usize] != 95u8 { cut = cut - 1usize }
    if cut < 2usize { ret false }
    let prefix = name[0usize..cut - 1usize]
    var at = 0usize
    while at + 1usize < tokens.len {
        if tokens[at].kind == .KwType && tokens[at + 1usize].kind == .Identifier && folded_same(prefix, lex.token_text(source, tokens[at + 1usize])) { ret true }
        at += 1usize
    }
    ret false
}

fn in_toolchain_lib(path: str, root: str) -> bool {
    if path.len < root.len + 5usize { ret false }
    ret graph.same(path[0usize..root.len], root) && graph.same(path[root.len..root.len + 5usize], "/lib/")
}

// Fills `out` with the unnamed declarations of the modules outside the toolchain's
// `lib/`, up to its length; returns the count.
fn find(a: *mem.Arena, g: *graph.Graph, out: []Found) -> (usize, err) {
    let (total, total_error) = mem.alloc[usize](a, 1048576usize)
    if total_error != ok { ret (0usize, total_error) }
    let (declared, declared_error) = mem.alloc[usize](a, 1048576usize)
    if declared_error != ok { ret (0usize, declared_error) }
    let (found, found_error) = mem.alloc[Found](a, 65536usize)
    if found_error != ok { ret (0usize, found_error) }
    var zero_at = 0usize
    while zero_at < 1048576usize {
        total[zero_at] = 0usize
        declared[zero_at] = 0usize
        zero_at += 1usize
    }
    var candidates = 0usize
    var module_at = 0usize
    while module_at < g.count {
        let source = g.modules[module_at].text
        let tokens = g.modules[module_at].tokens
        var depth = 0usize
        var at = 0usize
        while at < tokens.len {
            let kind = tokens[at].kind
            if kind == .Identifier {
                let s = slot(lex.token_text(source, tokens[at]))
                total[s] += 1usize
            }
            if kind == .PunctLBrace { depth += 1usize }
            if kind == .PunctRBrace && depth > 0usize { depth = depth - 1usize }
            let what = decl_kind(kind)
            if what != 0usize && depth == 0usize && at + 1usize < tokens.len && tokens[at + 1usize].kind == .Identifier && line_start(tokens, at) == at && !attributed(tokens, at) && candidates < 65536usize {
                found[candidates] = Found { module: module_at, token: at, kind: u8(what) }
                candidates += 1usize
                let d = slot(lex.token_text(source, tokens[at + 1usize]))
                declared[d] += 1usize
            }
            at += 1usize
        }
        module_at += 1usize
    }
    var count = 0usize
    var pick = 0usize
    while pick < candidates && count < out.len {
        let item = found[pick]
        let module = g.modules[item.module]
        let name = lex.token_text(module.text, module.tokens[item.token + 1usize])
        let s = slot(name)
        if total[s] == declared[s] && !in_toolchain_lib(module.path, g.toolchain_root) && !graph.same(name, "main") && !(item.kind == 1u8 && protocol_fn(module.text, module.tokens, name)) {
            out[count] = item
            count += 1usize
        }
        pick += 1usize
    }
    ret (count, ok)
}
