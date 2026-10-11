// Architecture rules over a module dependency graph, in the spirit of ArchUnit: build
// the graph (by hand, or with `uses` to read a source file's `use` lines), state rules
// as data, and `check` answers every violation with the module and the dependency that
// broke it. `assert_holds` is the suite assertion: it fails the running test with one
// line per violation.
//
// The rule vocabulary is deliberately small:
//   Layering    a module may depend only on modules of its own layer or below.
//   Forbid      modules under `from` must not depend on modules under `to`.
//   OnlyDepend  modules under `from` may depend only on modules under one of the
//               comma-separated prefixes in `to`.
//   NoCycles    no module is on a dependency cycle.
//   LayerRange  modules under `from` must have a layer within `lo..hi`.
//   Naming      modules whose layer is within `lo..hi` must be under the prefix `from`.
// "Under a prefix" is by name component: `e.fs` covers `e.fs` and `e.fs.watch`, not
// `e.fsx`. All storage is the caller's.

use e.mem
use e.str
use e.test

const NONE: u32 = 0xffffffffu32

type Graph = struct { names: []str, layers: []u8, deps_from: []u32, deps_to: []u32, mark: []u8, stack: []u32, modules: usize, edges: usize }
type RuleKind = enum u8 { Layering, Forbid, OnlyDepend, NoCycles, LayerRange, Naming }
type Rule = struct { kind: RuleKind, from: str, to: str, lo: u8, hi: u8 }
// `module` broke rule `rule` by depending on `other` (`NONE` when no dependency is
// involved: cycles, layer range, naming).
type Violation = struct { rule: usize, module: u32, other: u32 }
error TooSmall
error Unknown

// `mark` and `stack` hold at least `names.len` entries (cycle detection scratch).
fn graph(names: []str, layers: []u8, deps_from: []u32, deps_to: []u32, mark: []u8, stack: []u32) -> Graph {
    ret Graph { names: names, layers: layers, deps_from: deps_from, deps_to: deps_to, mark: mark, stack: stack, modules: 0usize, edges: 0usize }
}

fn add_module(g: *Graph, name: str, layer: u8) -> (u32, err) {
    if g.modules >= g.names.len || g.modules >= g.layers.len { ret (NONE, TooSmall) }
    g.names[g.modules] = name
    g.layers[g.modules] = layer
    g.modules += 1usize
    ret (u32(g.modules - 1usize), ok)
}

fn index_of(g: *const Graph, name: str) -> u32 {
    var i = 0usize
    while i < g.modules {
        if str.eq(g.names[i], name) { ret u32(i) }
        i += 1usize
    }
    ret NONE
}

// `from` depends on `to`; both must have been added.
fn add_dep(g: *Graph, from: str, to: str) -> err {
    let a = index_of(g, from)
    let b = index_of(g, to)
    if a == NONE || b == NONE { ret Unknown }
    if g.edges >= g.deps_from.len || g.edges >= g.deps_to.len { ret TooSmall }
    g.deps_from[g.edges] = a
    g.deps_to[g.edges] = b
    g.edges += 1usize
    ret ok
}

// The module paths named by the `use` lines of `source` (column-0 `use a.b.c`, with an
// optional ` as q`), as slices of it, up to `out.len`; answers how many were found.
fn uses(source: str, out: []str) -> usize {
    var n = 0usize
    var it = str.lines(source)
    while true {
        let (line, more) = str.split_next(&it)
        if !more { break }
        if str.starts_with(line, "use ") && n < out.len {
            var start = 4usize
            while start < line.len && line[start] == 32u8 { start += 1usize }
            var end = start
            while end < line.len && (str.is_ascii_alnum(line[end]) || line[end] == 95u8 || line[end] == 46u8) { end += 1usize }
            if end > start {
                out[n] = line[start..end]
                n += 1usize
            }
        }
    }
    ret n
}

// `name` is `prefix` or begins with `prefix` and a dot.
fn under(name: str, prefix: str) -> bool {
    if prefix.len == 0usize { ret true }
    if !str.starts_with(name, prefix) { ret false }
    ret name.len == prefix.len || name[prefix.len] == 46u8
}

// `name` is under one of the comma-separated prefixes.
fn under_any(name: str, prefixes: str) -> bool {
    var start = 0usize
    while start <= prefixes.len {
        var end = start
        while end < prefixes.len && prefixes[end] != 44u8 { end += 1usize }
        if end > start && under(name, str.trim(prefixes[start..end])) { ret true }
        start = end + 1usize
    }
    ret false
}

fn add_violation(out: []Violation, n: *usize, rule: usize, module: u32, other: u32) -> err {
    if *n >= out.len { ret TooSmall }
    out[*n] = Violation { rule: rule, module: module, other: other }
    *n += 1usize
    ret ok
}

// Is module `start` on a dependency cycle (does a path of dependencies return to it)?
fn on_cycle(g: *Graph, start: u32) -> bool {
    var i = 0usize
    while i < g.modules {
        g.mark[i] = 0u8
        i += 1usize
    }
    var top = 0usize
    g.stack[0usize] = start
    top = 1usize
    while top > 0usize {
        top -= 1usize
        let at = g.stack[top]
        var e = 0usize
        while e < g.edges {
            if g.deps_from[e] == at {
                let to = g.deps_to[e]
                if to == start { ret true }
                if g.mark[usize(to)] == 0u8 {
                    g.mark[usize(to)] = 1u8
                    g.stack[top] = to
                    top += 1usize
                }
            }
            e += 1usize
        }
    }
    ret false
}

// Every violation of `rules` over `g`, in rule then module order, into `out`;
// `TooSmall` when there are more (the first `out.len` stand, the count says how many).
fn scan(g: *Graph, rules: []const Rule, out: []Violation, n: *usize) -> err {
    var r = 0usize
    while r < rules.len {
        let rule = rules[r]
        if rule.kind == .Layering || rule.kind == .Forbid || rule.kind == .OnlyDepend {
            var e = 0usize
            while e < g.edges {
                let a = g.deps_from[e]
                let b = g.deps_to[e]
                var bad = false
                if rule.kind == .Layering { bad = g.layers[usize(b)] > g.layers[usize(a)] }
                if rule.kind == .Forbid { bad = under(g.names[usize(a)], rule.from) && under(g.names[usize(b)], rule.to) }
                if rule.kind == .OnlyDepend { bad = under(g.names[usize(a)], rule.from) && !under_any(g.names[usize(b)], rule.to) }
                if bad { try add_violation(out, n, r, a, b) }
                e += 1usize
            }
        }
        if rule.kind == .NoCycles || rule.kind == .LayerRange || rule.kind == .Naming {
            var m = 0usize
            while m < g.modules {
                var bad = false
                if rule.kind == .NoCycles { bad = on_cycle(g, u32(m)) }
                if rule.kind == .LayerRange { bad = under(g.names[m], rule.from) && (g.layers[m] < rule.lo || g.layers[m] > rule.hi) }
                if rule.kind == .Naming { bad = g.layers[m] >= rule.lo && g.layers[m] <= rule.hi && !under(g.names[m], rule.from) }
                if bad { try add_violation(out, n, r, u32(m), NONE) }
                m += 1usize
            }
        }
        r += 1usize
    }
    ret ok
}

fn check(g: *Graph, rules: []const Rule, out: []Violation) -> (usize, err) {
    var n = 0usize
    let scan_error = scan(g, rules, out, &n)
    ret (n, scan_error)
}

fn put(b: *str.Builder, s: str) {
    let discarded = str.push(b, s)
}

fn put_layer(b: *str.Builder, layer: u8) {
    let discarded = str.push_u8(b, layer)
}

// One violation as a line (no newline), into the builder.
fn put_violation(b: *str.Builder, g: *const Graph, rules: []const Rule, v: Violation) {
    let rule = rules[v.rule]
    let name = g.names[usize(v.module)]
    if rule.kind == .Layering {
        put(b, "layering: ")
        put(b, name)
        put(b, " (layer ")
        put_layer(b, g.layers[usize(v.module)])
        put(b, ") depends on ")
        put(b, g.names[usize(v.other)])
        put(b, " (layer ")
        put_layer(b, g.layers[usize(v.other)])
        put(b, ")")
    }
    if rule.kind == .Forbid {
        put(b, "forbidden: ")
        put(b, name)
        put(b, " depends on ")
        put(b, g.names[usize(v.other)])
        put(b, " (")
        put(b, rule.from)
        put(b, " must not depend on ")
        put(b, rule.to)
        put(b, ")")
    }
    if rule.kind == .OnlyDepend {
        put(b, "not allowed: ")
        put(b, name)
        put(b, " depends on ")
        put(b, g.names[usize(v.other)])
        put(b, " (")
        put(b, rule.from)
        put(b, " may depend only on ")
        put(b, rule.to)
        put(b, ")")
    }
    if rule.kind == .NoCycles {
        put(b, "cycle: ")
        put(b, name)
        put(b, " is on a dependency cycle")
    }
    if rule.kind == .LayerRange {
        put(b, "layer range: ")
        put(b, name)
        put(b, " is in layer ")
        put_layer(b, g.layers[usize(v.module)])
        put(b, ", expected ")
        put_layer(b, rule.lo)
        put(b, "..")
        put_layer(b, rule.hi)
    }
    if rule.kind == .Naming {
        put(b, "naming: ")
        put(b, name)
        put(b, " (layer ")
        put_layer(b, g.layers[usize(v.module)])
        put(b, ") must be under ")
        put(b, rule.from)
    }
}

// The violations as newline-terminated lines in `out` (cut when short).
fn describe(g: *const Graph, rules: []const Rule, vs: []const Violation, out: []u8) -> str {
    var holder = mem.arena_from(out)
    let (built, builder_error) = str.builder(&holder, out.len)
    if builder_error != ok { ret "" }
    var b = built
    var i = 0usize
    while i < vs.len {
        put_violation(&b, g, rules, vs[i])
        put(&b, "\n")
        i += 1usize
    }
    ret str.done(&b)
}

// `ok` when no rule is violated (up to `scratch.len` violations are collected);
// otherwise fails the running test with `describe`'s text built in `buf`.
fn assert_holds(g: *Graph, rules: []const Rule, scratch: []Violation, buf: []u8) -> err {
    let (n, check_error) = check(g, rules, scratch)
    if n == 0usize && check_error == ok { ret ok }
    ret test.fail(describe(g, rules, scratch[0..n], buf))
}
