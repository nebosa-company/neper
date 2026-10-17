// ECMAScript modules (browser tracker 5.12): source text module records, linking (import and export resolution, namespace
// objects, live bindings through alias bindings of the importer's environment), evaluation with top-level await, dynamic
// `import()` and `import.meta`.
//
// The host supplies `it.module_loader` (resolve a specifier against the referring module, fetch, answer the parsed record
// made by `new_module`); everything else lives here. Evaluation runs the modules of a graph in dependency order; a module with
// top-level `await` runs as an async body and the modules after it wait for its promise.

use e.data.list as list
use e.js.ast as ast
use e.js.interp as js
use e.js.parser as jsparse
use e.mem
use e.str

type Import = struct { request: usize, import_name: str, local: str }

// `request` is -1 for a local export, else the index of the module it comes from; `import_name` is "*" for a namespace.
type Export = struct { export_name: str, local: str, request: i64, import_name: str }

type Module = struct {
    url: str, prog: *ast.Program, env: *js.Env,
    requested: list.List[str], deps: list.List[*Module],
    imports: list.List[Import], locals: list.List[Export], indirects: list.List[Export], stars: list.List[usize],
    status: u8, has_tla: bool, namespace: *js.Obj, has_ns: bool,
    failure: js.Value, failed: bool, eval_promise: *js.Obj, has_eval_promise: bool, meta: *js.Obj, has_meta: bool
}

// Module statuses.
const S_NEW: u8 = 0u8
const S_LINKING: u8 = 1u8
const S_LINKED: u8 = 2u8
const S_EVALUATING: u8 = 3u8
const S_EVALUATED: u8 = 4u8

fn module_of(p: *void) -> *Module { ret mem.cast[*Module](p) }

fn arg(args: []const js.Value, i: usize) -> js.Value {
    if i < args.len { ret args[i] }
    ret js.undefv()
}

// --- collecting the module's imports and exports

fn pattern_names(prog: *const ast.Program, id: u32, out: *list.List[str]) -> err {
    if id == ast.NONE { ret ok }
    let n = prog.nodes[usize(id)]
    if n.kind == ast.N_IDENT {
        try list.push[str](out, n.text)
    } else if n.kind == ast.N_ARRAY || n.kind == ast.N_OBJECT {
        var i = 0usize
        while i < usize(n.b) {
            try pattern_names(prog, prog.kids[usize(n.a) + i], out)
            i += 1usize
        }
    } else if n.kind == ast.N_PROP {
        try pattern_names(prog, n.b, out)
    } else if n.kind == ast.N_ASSIGN || n.kind == ast.N_SPREAD {
        try pattern_names(prog, n.a, out)
    }
    ret ok
}

// Names a top-level declaration binds: (names, lexical).
fn declared_names(prog: *const ast.Program, sid: u32, out: *list.List[str]) -> (bool, err) {
    let sn = prog.nodes[usize(sid)]
    if sn.kind == ast.N_VAR {
        var d = 0usize
        while d < usize(sn.b) {
            let dn = prog.nodes[usize(prog.kids[usize(sn.a) + d])]
            try pattern_names(prog, dn.a, out)
            d += 1usize
        }
        ret (sn.op != ast.D_VAR, ok)
    }
    if sn.kind == ast.N_FUNC || sn.kind == ast.N_CLASS {
        try list.push[str](out, sn.text)
        ret (true, ok)
    }
    ret (false, ok)
}

fn find_request(m: *Module, spec: str) -> usize {
    var i = 0usize
    while i < m.requested.len {
        if str.eq(m.requested.items[i], spec) { ret i }
        i += 1usize
    }
    ret m.requested.len
}

fn add_request(it: *js.Interp, m: *Module, spec: str) -> (usize, err) {
    let at = find_request(m, spec)
    if at < m.requested.len { ret (at, ok) }
    try list.push[str](&m.requested, spec)
    ret (m.requested.len - 1usize, ok)
}

fn import_of(m: *Module, local: str) -> (usize, bool) {
    var i = 0usize
    while i < m.imports.len {
        if str.eq(m.imports.items[i].local, local) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn has_name(names: *const list.List[str], name: str) -> bool {
    var i = 0usize
    while i < names.len {
        if str.eq(names.items[i], name) { ret true }
        i += 1usize
    }
    ret false
}

// Reads the import and export declarations; throws a SyntaxError for the static errors modules add.
fn collect(it: *js.Interp, m: *Module) -> err {
    let prog = m.prog
    let root = prog.nodes[usize(prog.root)]
    var lexical = try list.init[str](it.a, 16usize)
    var vars = try list.init[str](it.a, 16usize)
    var seen_exports = try list.init[str](it.a, 16usize)
    // Pass 1: imports and the declared names.
    var i = 0usize
    while i < usize(root.b) {
        let sid = prog.kids[usize(root.a) + i]
        let sn = prog.nodes[usize(sid)]
        i += 1usize
        if sn.kind == ast.N_IMPORT {
            let (req, re) = add_request(it, m, sn.text)
            if re != ok { ret js.throw_range(it, "out of memory") }
            var k = 0usize
            while k < usize(sn.b) {
                let spec = prog.nodes[usize(prog.kids[usize(sn.a) + k])]
                var iname = spec.text
                if spec.op == 2u8 { iname = "*" }
                try list.push[Import](&m.imports, Import { request: req, import_name: iname, local: spec.text2 })
                k += 1usize
            }
            continue
        }
        var inner = sid
        if sn.kind == ast.N_EXPORT && (sn.op == ast.X_DECL || sn.op == ast.X_DEFAULT_DECL) { inner = sn.a }
        let ik = prog.nodes[usize(inner)].kind
        if ik == ast.N_VAR || ik == ast.N_FUNC || ik == ast.N_CLASS {
            var tmp = try list.init[str](it.a, 4usize)
            let (is_lex, de) = declared_names(prog, inner, &tmp)
            if de != ok { ret js.throw_range(it, "out of memory") }
            var t = 0usize
            while t < tmp.len {
                if is_lex { try list.push[str](&lexical, tmp.items[t]) } else { try list.push[str](&vars, tmp.items[t]) }
                t += 1usize
            }
        }
    }
    // var names (including those of nested blocks) come from the hoist list.
    var h = 0usize
    while h < usize(root.hoist_count) {
        let hid = prog.kids[usize(root.hoist_first) + h]
        try list.push[str](&vars, prog.nodes[usize(hid)].text)
        h += 1usize
    }
    // Lexical names must be unique and not clash with var names or imports.
    var a1 = 0usize
    while a1 < lexical.len {
        let nm = lexical.items[a1]
        var b1 = a1 + 1usize
        var dup = false
        while b1 < lexical.len {
            if str.eq(lexical.items[b1], nm) { dup = true }
            b1 += 1usize
        }
        // var statements put their names into `lexical` above only when lexical; `declared_names` returns the flag per statement.
        if dup { ret js.throw_syntax(it, js.str_concat3(it, "Identifier '", nm, "' has already been declared")) }
        a1 += 1usize
    }
    var im = 0usize
    while im < m.imports.len {
        let loc = m.imports.items[im].local
        var jm = im + 1usize
        while jm < m.imports.len {
            if str.eq(m.imports.items[jm].local, loc) { ret js.throw_syntax(it, js.str_concat3(it, "Identifier '", loc, "' has already been declared")) }
            jm += 1usize
        }
        if has_name(&lexical, loc) || has_name(&vars, loc) { ret js.throw_syntax(it, js.str_concat3(it, "Identifier '", loc, "' has already been declared")) }
        im += 1usize
    }
    var vi = 0usize
    while vi < vars.len {
        if has_name(&lexical, vars.items[vi]) { ret js.throw_syntax(it, js.str_concat3(it, "Identifier '", vars.items[vi], "' has already been declared")) }
        vi += 1usize
    }
    // Pass 2: exports.
    i = 0usize
    while i < usize(root.b) {
        let sid2 = prog.kids[usize(root.a) + i]
        let sn2 = prog.nodes[usize(sid2)]
        i += 1usize
        if sn2.kind != ast.N_EXPORT { continue }
        if sn2.op == ast.X_DECL {
            var names = try list.init[str](it.a, 4usize)
            let (lx, ne) = declared_names(prog, sn2.a, &names)
            var k2 = 0usize
            while k2 < names.len {
                try add_export_name(it, &seen_exports, names.items[k2])
                try list.push[Export](&m.locals, Export { export_name: names.items[k2], local: names.items[k2], request: -1i64, import_name: "" })
                k2 += 1usize
            }
        } else if sn2.op == ast.X_DEFAULT_DECL || sn2.op == ast.X_DEFAULT_EXPR {
            try add_export_name(it, &seen_exports, "default")
            var local = "*default*"
            if sn2.op == ast.X_DEFAULT_DECL && prog.nodes[usize(sn2.a)].text.len > 0usize { local = prog.nodes[usize(sn2.a)].text }
            try list.push[Export](&m.locals, Export { export_name: "default", local: local, request: -1i64, import_name: "" })
        } else if sn2.op == ast.X_STAR {
            let (req2, re2) = add_request(it, m, sn2.text)
            if re2 != ok { ret js.throw_range(it, "out of memory") }
            try list.push[usize](&m.stars, req2)
        } else if sn2.op == ast.X_STAR_AS {
            let (req3, re3) = add_request(it, m, sn2.text)
            if re3 != ok { ret js.throw_range(it, "out of memory") }
            try add_export_name(it, &seen_exports, sn2.text2)
            try list.push[Export](&m.indirects, Export { export_name: sn2.text2, local: "", request: i64(req3), import_name: "*" })
        } else if sn2.op == ast.X_LIST {
            var req4 = 0usize
            if sn2.c == 1u32 {
                let (rq, rqe) = add_request(it, m, sn2.text)
                if rqe != ok { ret js.throw_range(it, "out of memory") }
                req4 = rq
            }
            var k3 = 0usize
            while k3 < usize(sn2.b) {
                let sp = prog.nodes[usize(prog.kids[usize(sn2.a) + k3])]
                k3 += 1usize
                try add_export_name(it, &seen_exports, sp.text2)
                if sn2.c == 1u32 {
                    try list.push[Export](&m.indirects, Export { export_name: sp.text2, local: "", request: i64(req4), import_name: sp.text })
                    continue
                }
                let (ix, is_import) = import_of(m, sp.text)
                if is_import {
                    let ie = m.imports.items[ix]
                    if str.eq(ie.import_name, "*") {
                        try list.push[Export](&m.locals, Export { export_name: sp.text2, local: sp.text, request: -1i64, import_name: "" })
                    } else {
                        try list.push[Export](&m.indirects, Export { export_name: sp.text2, local: "", request: i64(ie.request), import_name: ie.import_name })
                    }
                } else {
                    if !has_name(&lexical, sp.text) && !has_name(&vars, sp.text) { ret js.throw_syntax(it, js.str_concat3(it, "Export '", sp.text, "' is not defined in module")) }
                    try list.push[Export](&m.locals, Export { export_name: sp.text2, local: sp.text, request: -1i64, import_name: "" })
                }
            }
        }
    }
    ret ok
}

fn add_export_name(it: *js.Interp, names: *list.List[str], name: str) -> err {
    if has_name(names, name) { ret js.throw_syntax(it, js.str_concat3(it, "Duplicate export of '", name, "'")) }
    try list.push[str](names, name)
    ret ok
}

// --- creating modules

fn find(it: *js.Interp, url: str) -> (*Module, bool) {
    var i = 0usize
    while i < it.modules.len {
        let m = module_of(it.modules.items[i])
        if str.eq(m.url, url) { ret (m, true) }
        i += 1usize
    }
    ret (zero, false)
}

// Parses `source` as a module named `url` and registers it; a syntax error is thrown as a SyntaxError.
fn new_module(it: *js.Interp, url: str, source: str) -> (*Module, err) {
    let (parsed, pe) = jsparse.parse_module(it.a, source)
    if pe != ok { ret (zero, js.throw_syntax(it, js.str_concat3(it, "SyntaxError: ", parsed.message, ""))) }
    let (cell, ce) = mem.alloc[Module](it.a, 1usize)
    if ce != ok { ret (zero, js.throw_range(it, "out of memory")) }
    var blank: Module = zero
    cell[0usize] = blank
    let m = &cell[0usize]
    let (pc, pce) = mem.alloc[ast.Program](it.a, 1usize)
    if pce != ok { ret (zero, js.throw_range(it, "out of memory")) }
    pc[0usize] = parsed.program
    pc[0usize].url = url
    pc[0usize].module = mem.cast[*void](m)
    m.prog = &pc[0usize]
    m.url = url
    m.has_tla = (parsed.program.nodes[usize(parsed.program.root)].flags & ast.F_ASYNC) != 0u16
    let (rq, rqe) = list.init[str](it.a, 4usize)
    let (dp, dpe) = list.init[*Module](it.a, 4usize)
    let (im, ime) = list.init[Import](it.a, 8usize)
    let (lc, lce) = list.init[Export](it.a, 8usize)
    let (ind, inde) = list.init[Export](it.a, 4usize)
    let (st, ste) = list.init[usize](it.a, 2usize)
    if rqe != ok || dpe != ok || ime != ok || lce != ok || inde != ok || ste != ok { ret (zero, js.throw_range(it, "out of memory")) }
    m.requested = rq
    m.deps = dp
    m.imports = im
    m.locals = lc
    m.indirects = ind
    m.stars = st
    m.env = js.new_env(it, it.global_env)
    m.env.is_var = true
    let ce2 = collect(it, m)
    if ce2 != ok { ret (zero, ce2) }
    try list.push[*void](&it.modules, mem.cast[*void](m))
    ret (m, ok)
}

// --- export resolution

type Resolved = struct { found: bool, ambiguous: bool, module: *Module, binding: str, is_ns: bool }

type VisitedKey = struct { module: *Module, name: str }

fn visited(set: *list.List[VisitedKey], m: *Module, name: str) -> bool {
    var i = 0usize
    while i < set.len {
        if set.items[i].module == m && str.eq(set.items[i].name, name) { ret true }
        i += 1usize
    }
    ret false
}

fn resolve_export(it: *js.Interp, m: *Module, name: str, set: *list.List[VisitedKey]) -> (Resolved, err) {
    var none: Resolved = zero
    if visited(set, m, name) { ret (none, ok) }
    try list.push[VisitedKey](set, VisitedKey { module: m, name: name })
    var i = 0usize
    while i < m.locals.len {
        if str.eq(m.locals.items[i].export_name, name) {
            ret (Resolved { found: true, ambiguous: false, module: m, binding: m.locals.items[i].local, is_ns: false }, ok)
        }
        i += 1usize
    }
    var j = 0usize
    while j < m.indirects.len {
        let ex = m.indirects.items[j]
        if str.eq(ex.export_name, name) {
            let dep = m.deps.items[usize(ex.request)]
            if str.eq(ex.import_name, "*") {
                ret (Resolved { found: true, ambiguous: false, module: dep, binding: "", is_ns: true }, ok)
            }
            let (r, re) = resolve_export(it, dep, ex.import_name, set)
            ret (r, re)
        }
        j += 1usize
    }
    if str.eq(name, "default") { ret (none, ok) }
    var star = none
    var k = 0usize
    while k < m.stars.len {
        let dep2 = m.deps.items[m.stars.items[k]]
        let (r2, re2) = resolve_export(it, dep2, name, set)
        if re2 != ok { ret (none, re2) }
        if r2.ambiguous { ret (r2, ok) }
        if r2.found {
            if !star.found {
                star = r2
            } else if star.module != r2.module || star.is_ns != r2.is_ns || !str.eq(star.binding, r2.binding) {
                ret (Resolved { found: false, ambiguous: true, module: m, binding: "", is_ns: false }, ok)
            }
        }
        k += 1usize
    }
    ret (star, ok)
}

fn resolve(it: *js.Interp, m: *Module, name: str) -> (Resolved, err) {
    let (sl, se) = list.init[VisitedKey](it.a, 8usize)
    if se != ok { ret (zero, js.throw_range(it, "out of memory")) }
    var set = sl
    let (r, e) = resolve_export(it, m, name, &set)
    ret (r, e)
}

fn exported_names(it: *js.Interp, m: *Module, seen: *list.List[*Module], out: *list.List[str]) -> err {
    var s = 0usize
    while s < seen.len {
        if seen.items[s] == m { ret ok }
        s += 1usize
    }
    try list.push[*Module](seen, m)
    var i = 0usize
    while i < m.locals.len {
        if !has_name(out, m.locals.items[i].export_name) { try list.push[str](out, m.locals.items[i].export_name) }
        i += 1usize
    }
    var j = 0usize
    while j < m.indirects.len {
        if !has_name(out, m.indirects.items[j].export_name) { try list.push[str](out, m.indirects.items[j].export_name) }
        j += 1usize
    }
    var k = 0usize
    while k < m.stars.len {
        let dep = m.deps.items[m.stars.items[k]]
        var star_names = try list.init[str](it.a, 8usize)
        try exported_names(it, dep, seen, &star_names)
        var q = 0usize
        while q < star_names.len {
            if !str.eq(star_names.items[q], "default") && !has_name(out, star_names.items[q]) { try list.push[str](out, star_names.items[q]) }
            q += 1usize
        }
        k += 1usize
    }
    ret ok
}

// The module namespace object.
fn namespace_of(it: *js.Interp, m: *Module) -> (*js.Obj, err) {
    if m.has_ns { ret (m.namespace, ok) }
    // The object exists before its entries do: `export * as ns` of the module itself needs it.
    let (dc, dce) = mem.alloc[js.NsData](it.a, 1usize)
    if dce != ok { ret (zero, js.throw_range(it, "out of memory")) }
    let o = js.new_obj(it, js.C_NAMESPACE, js.null_obj())
    o.has_proto = false
    o.extensible = false
    o.data = mem.cast[*void](&dc[0usize])
    dc[0usize].entries = js.zero_entries()
    m.namespace = o
    m.has_ns = true
    var seen = try list.init[*Module](it.a, 4usize)
    var names = try list.init[str](it.a, 8usize)
    try exported_names(it, m, &seen, &names)
    let (entries, ee) = mem.alloc[js.NsEntry](it.a, names.len + 1usize)
    if ee != ok { ret (zero, js.throw_range(it, "out of memory")) }
    var n = 0usize
    var i = 0usize
    while i < names.len {
        let (r, re) = resolve(it, m, names.items[i])
        if re != ok { ret (zero, re) }
        if r.found {
            var en: js.NsEntry = zero
            en.name = names.items[i]
            en.binding = r.binding
            en.env = r.module.env
            en.is_ns = r.is_ns
            if r.is_ns {
                let (nso, nse) = namespace_of(it, r.module)
                if nse != ok { ret (zero, nse) }
                en.ns_value = js.obj_value(nso)
            }
            // Insertion by name, in UTF-16 code unit order.
            var at = n
            while at > 0usize && js.compare_utf16(entries[at - 1usize].name, en.name) > 0i32 {
                entries[at] = entries[at - 1usize]
                at -= 1usize
            }
            entries[at] = en
            n += 1usize
        }
        i += 1usize
    }
    dc[0usize].entries = entries[0usize..n]
    ret (o, ok)
}

// --- linking

fn load_dependencies(it: *js.Interp, m: *Module) -> err {
    while m.deps.len < m.requested.len {
        let spec = m.requested.items[m.deps.len]
        let (mp, le) = it.module_loader(it, m.url, spec)
        if le != ok { ret le }
        try list.push[*Module](&m.deps, module_of(mp))
    }
    ret ok
}

fn instantiate(it: *js.Interp, m: *Module) -> err {
    // Indirect exports must resolve.
    var j = 0usize
    while j < m.indirects.len {
        let (r, re) = resolve(it, m, m.indirects.items[j].export_name)
        if re != ok { ret re }
        if !r.found { ret js.throw_syntax(it, js.str_concat3(it, "The module does not provide the export '", m.indirects.items[j].export_name, "'")) }
        j += 1usize
    }
    // Imports.
    var i = 0usize
    while i < m.imports.len {
        let im = m.imports.items[i]
        let dep = m.deps.items[im.request]
        if str.eq(im.import_name, "*") {
            let (nso, nse) = namespace_of(it, dep)
            if nse != ok { ret nse }
            try js.declare(it, m.env, im.local, js.obj_value(nso), js.B_CONST)
        } else {
            let (r, re) = resolve(it, dep, im.import_name)
            if re != ok { ret re }
            if !r.found { ret js.throw_syntax(it, js.str_concat3(it, "The requested module does not provide an export named '", im.import_name, "'")) }
            if r.is_ns {
                let (nso2, nse2) = namespace_of(it, r.module)
                if nse2 != ok { ret nse2 }
                try js.declare(it, m.env, im.local, js.obj_value(nso2), js.B_CONST)
            } else {
                try list.push[js.Binding](&m.env.vars, js.Binding { name: im.local, value: js.str_value(r.binding), flags: js.B_ALIAS, target: r.module.env })
            }
        }
        i += 1usize
    }
    // Declarations: var names, then functions (created now so cycles can call them), `let`/`const`/`class` start uninitialised.
    let prog = m.prog
    let root = prog.nodes[usize(prog.root)]
    var h = 0usize
    while h < usize(root.hoist_count) {
        let hid = prog.kids[usize(root.hoist_first) + h]
        try js.declare_var(it, m.env, prog.nodes[usize(hid)].text)
        h += 1usize
    }
    var f: js.Frame = zero
    f.prog = prog
    f.env = m.env
    f.this_val = js.undefv()
    f.has_this = true
    f.strict = true
    f.args = js.zero_args()
    f.new_target = js.undefv()
    try js.hoist_declarations_in(it, &f, root.a, root.b, js.null_env())
    // The binding of `export default <expression>`.
    var k = 0usize
    while k < usize(root.b) {
        let sn = prog.nodes[usize(prog.kids[usize(root.a) + k])]
        if sn.kind == ast.N_EXPORT && sn.op == ast.X_DEFAULT_EXPR { try js.declare(it, m.env, "*default*", js.undefv(), js.B_TDZ) }
        k += 1usize
    }
    ret ok
}

fn link_inner(it: *js.Interp, m: *Module, stack: *list.List[*Module]) -> err {
    if m.status != S_NEW { ret ok }
    m.status = S_LINKING
    try list.push[*Module](stack, m)
    try load_dependencies(it, m)
    var i = 0usize
    while i < m.deps.len {
        try link_inner(it, m.deps.items[i], stack)
        i += 1usize
    }
    try instantiate(it, m)
    m.status = S_LINKED
    ret ok
}

// Loads and links `m` and everything it imports. On failure the modules that were being linked go back to unlinked.
fn link(it: *js.Interp, m: *Module) -> err {
    var stack = try list.init[*Module](it.a, 8usize)
    let e = link_inner(it, m, &stack)
    if e != ok {
        var i = 0usize
        while i < stack.len {
            if stack.items[i].status == S_LINKING { stack.items[i].status = S_NEW }
            i += 1usize
        }
    }
    ret e
}

// --- evaluation

type EvalState = struct { mods: list.List[*Module], pos: usize, promise: *js.Obj }

fn module_frame(m: *Module) -> js.Frame {
    var f: js.Frame = zero
    f.prog = m.prog
    f.env = m.env
    f.this_val = js.undefv()
    f.has_this = true
    f.strict = true
    f.args = js.zero_args()
    f.new_target = js.undefv()
    ret f
}

fn collect_order(m: *Module, seen: *list.List[*Module], out: *list.List[*Module]) -> err {
    var s = 0usize
    while s < seen.len {
        if seen.items[s] == m { ret ok }
        s += 1usize
    }
    try list.push[*Module](seen, m)
    var i = 0usize
    while i < m.deps.len {
        try collect_order(m.deps.items[i], seen, out)
        i += 1usize
    }
    try list.push[*Module](out, m)
    ret ok
}

fn fail_from(it: *js.Interp, es: *EvalState, reason: js.Value) {
    var i = es.pos
    while i < es.mods.len {
        let mm = es.mods.items[i]
        if mm.status != S_EVALUATED {
            mm.failure = reason
            mm.failed = true
            mm.status = S_EVALUATED
        }
        i += 1usize
    }
    let r = js.promise_reject(it, es.promise, reason)
}

fn tla_done(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let es = mem.cast[*EvalState](it.callee.data)
    es.mods.items[es.pos].status = S_EVALUATED
    es.pos += 1usize
    run_from(it, es)
    ret (js.undefv(), ok)
}

fn tla_failed(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let es = mem.cast[*EvalState](it.callee.data)
    fail_from(it, es, arg(args, 0usize))
    ret (js.undefv(), ok)
}

fn run_from(it: *js.Interp, es: *EvalState) {
    while es.pos < es.mods.len {
        let mm = es.mods.items[es.pos]
        if mm.status == S_EVALUATED {
            if mm.failed {
                fail_from(it, es, mm.failure)
                ret
            }
            es.pos += 1usize
            continue
        }
        mm.status = S_EVALUATING
        var f = module_frame(mm)
        if !mm.has_tla {
            let (c, e) = js.exec_module_statements(it, &f, mm.prog.root)
            if e != ok {
                if e == js.Throw {
                    fail_from(it, es, it.thrown)
                } else {
                    fail_from(it, es, js.undefv())
                }
                ret
            }
            mm.status = S_EVALUATED
            es.pos += 1usize
            continue
        }
        // Top-level await: the body runs as an async function body; the next module waits for its promise.
        var n: ast.Node = zero
        n.flags = ast.F_ASYNC
        n.c = mm.prog.root
        it.pending_module_body = true
        let (pv, pe) = js.make_suspendable(it, js.null_obj(), f, n)
        it.pending_module_body = false
        if pe != ok {
            fail_from(it, es, it.thrown)
            ret
        }
        let on_ful = js.make_native(it, "", 1u32, tla_done)
        on_ful.data = mem.cast[*void](es)
        let on_rej = js.make_native(it, "", 1u32, tla_failed)
        on_rej.data = mem.cast[*void](es)
        let te = js.promise_then_raw(it, js.as_object(pv), js.obj_value(on_ful), js.obj_value(on_rej))
        ret
    }
    js.promise_fulfill(it, es.promise, js.undefv())
}

// Evaluates `m` and its dependencies; answers a promise that settles when evaluation has finished.
fn evaluate(it: *js.Interp, m: *Module) -> (js.Value, err) {
    if m.has_eval_promise { ret (js.obj_value(m.eval_promise), ok) }
    let (p, pe) = js.new_promise(it)
    if pe != ok { ret (js.undefv(), pe) }
    m.eval_promise = p
    m.has_eval_promise = true
    let (cell, ce) = mem.alloc[EvalState](it.a, 1usize)
    if ce != ok { ret (js.undefv(), js.throw_range(it, "out of memory")) }
    let es = &cell[0usize]
    var seen = try list.init[*Module](it.a, 8usize)
    es.mods = try list.init[*Module](it.a, 8usize)
    try collect_order(m, &seen, &es.mods)
    es.pos = 0usize
    es.promise = p
    run_from(it, es)
    ret (js.obj_value(p), ok)
}

// --- import.meta and dynamic import

fn meta_of(it: *js.Interp, m: *Module) -> (js.Value, err) {
    if m.has_meta { ret (js.obj_value(m.meta), ok) }
    let o = js.new_obj(it, js.C_OBJECT, js.null_obj())
    o.has_proto = false
    try js.set_named(it, o, "url", js.str_value(m.url))
    m.meta = o
    m.has_meta = true
    ret (js.obj_value(o), ok)
}

fn import_resolved(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let me = it.callee
    let m = module_of(me.data)
    let (nso, ne) = namespace_of(it, m)
    if ne != ok {
        let re = js.promise_reject(it, me.aux, it.thrown)
        ret (js.undefv(), ok)
    }
    let r = js.promise_resolve_with(it, me.aux, js.obj_value(nso))
    ret (js.undefv(), ok)
}

fn import_rejected(it: *js.Interp, this_val: js.Value, args: []const js.Value) -> (js.Value, err) {
    let me = it.callee
    let r = js.promise_reject(it, me.aux, arg(args, 0usize))
    ret (js.undefv(), ok)
}

fn reject_with_thrown(it: *js.Interp, p: *js.Obj) -> (js.Value, err) {
    let r = js.promise_reject(it, p, it.thrown)
    ret (js.obj_value(p), ok)
}

fn hook(it: *js.Interp, op: u8, v: js.Value, prog: *const ast.Program) -> (js.Value, err) {
    if op == 2u8 {
        if !prog.is_module { ret (js.undefv(), js.throw_syntax(it, "import.meta is only valid in modules")) }
        let (mv, me) = meta_of(it, module_of(prog.module))
        ret (mv, me)
    }
    let (p, pe) = js.new_promise(it)
    if pe != ok { ret (js.undefv(), pe) }
    let (spec, se) = js.to_string(it, v)
    if se != ok {
        if se == js.Throw {
            let (r1, e1) = reject_with_thrown(it, p)
            ret (r1, e1)
        }
        ret (js.undefv(), se)
    }
    let (mp, le) = it.module_loader(it, prog.url, spec)
    if le != ok {
        if le == js.Throw {
            let (r2, e2) = reject_with_thrown(it, p)
            ret (r2, e2)
        }
        ret (js.undefv(), le)
    }
    let m = module_of(mp)
    let lk = link(it, m)
    if lk != ok {
        if lk == js.Throw {
            let (r3, e3) = reject_with_thrown(it, p)
            ret (r3, e3)
        }
        ret (js.undefv(), lk)
    }
    let (evp, ee) = evaluate(it, m)
    if ee != ok { ret (js.undefv(), ee) }
    let on_ful = js.make_native(it, "", 1u32, import_resolved)
    on_ful.data = mem.cast[*void](m)
    on_ful.aux = p
    let on_rej = js.make_native(it, "", 1u32, import_rejected)
    on_rej.aux = p
    let te = js.promise_then_raw(it, js.as_object(evp), js.obj_value(on_ful), js.obj_value(on_rej))
    ret (js.obj_value(p), ok)
}

// Turns on modules for a realm: `loader` resolves a specifier against the referring module's url and answers a registered
// module (see `new_module` and `find`).
fn install(it: *js.Interp, loader: js.ModuleLoader) -> err {
    let (l, le) = list.init[*void](it.a, 8usize)
    if le != ok { ret le }
    it.modules = l
    it.module_loader = loader
    it.module_hook = hook
    it.has_modules = true
    ret ok
}

// Runs a module the host has already registered: link, evaluate, run the job queue; answers the promise of its evaluation.
fn run_module(it: *js.Interp, m: *Module) -> (js.Value, err) {
    let le = link(it, m)
    if le != ok { ret (js.undefv(), le) }
    let (p, ee) = evaluate(it, m)
    ret (p, ee)
}
