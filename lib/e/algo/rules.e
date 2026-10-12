// A forward-chaining production-rule engine in the shape of Drools and CLIPS (L161): a Rete
// network over working-memory facts, a small rule DSL and decision tables compiled to rules.
//
// A fact is a kind (an interned name) and up to six `i64` fields; symbols are interned to `i64`
// so a name compares like a number. Asserting a fact that is already in working memory is a
// no-op (set semantics, Drools' equality mode). The network is an alpha stage and a beta chain:
// every condition's constant tests select an alpha memory (identical tests share one memory), and
// every rule is a chain of join nodes that hold the partial matches (tokens) of its conditions so
// far. A fact assert right-activates the nodes it reaches and only the new combinations are
// built; a retract kills the tokens that contain the fact. A `not` condition is a negative node:
// it counts the facts that block each token and passes it on at zero, in both directions.
//
// Conflict resolution: higher salience first, then recency (the match whose fact ids, taken in
// descending order, are lexicographically larger; a longer list wins a tie), then specificity (the
// number of constrained arguments), then rule declaration order. A match fires at most once
// (refraction); a match that is broken and made again is a new match and fires again. `fire`
// runs the best activation until the agenda is empty, `halt` runs or the limit is reached.
//
// Right-hand sides are data, not callbacks: `assert kind(terms)` (a term is a constant, a bound
// variable, or a variable plus a variable or a constant), `retract n` (the fact matched by the
// n-th condition) and `halt`. The DSL:
//
//     rule grand salience 5          // salience is optional, default 0
//     when parent(?x, ?y) parent(?y, ?z) not blocked(?x, _)
//     then assert grandparent(?x, ?z)
//     end
//
// An argument is `_` (anything), `?v` (bind, or equal to the earlier binding), an integer or a
// `:symbol` (equal to it), or an optional `?v` followed by one of `== != < <= > >=` and an integer,
// symbol or `?w` bound earlier. A variable that first appears inside a `not` is local to it.
//
// Decision tables (`add_table`): each row becomes one rule over the input kind with one test per
// non-`ANY_CELL` cell and an `assert` of the row's output; with `first_hit` a marker fact and a
// `not` make the first matching row (by row order) the only one that fires for an input fact.
//
// Limits (the engine's storage is fixed at `init`): tokens are never reclaimed (`Full` when the
// pool is spent); the agenda is a scan of the terminal tokens, linear in the token pool; there is
// no beta prefix sharing between rules (alpha memories are shared) and no `exists`/`forall`/`or`.

use e.mem

const NONE: u32 = 4294967295u32
const MAX_ARGS: usize = 6usize
const MAX_CONDS: usize = 6usize
const MAX_ACTS: usize = 6usize
const MAX_VARS: usize = 12usize
const OP_ANY: u8 = 0u8
const OP_EQ: u8 = 1u8
const OP_NE: u8 = 2u8
const OP_LT: u8 = 3u8
const OP_LE: u8 = 4u8
const OP_GT: u8 = 5u8
const OP_GE: u8 = 6u8
const ACT_ASSERT: u8 = 1u8
const ACT_RETRACT: u8 = 2u8
const ACT_HALT: u8 = 3u8
const AT_CONST: u8 = 0u8
const AT_VAR: u8 = 1u8
const AT_ADD_VAR: u8 = 2u8
const AT_ADD_CONST: u8 = 3u8

type Term = struct { bind: i32, first: bool, op: u8, rv: i32, v: i64 }
type Cond = struct { kind: u32, neg: bool, n: u32, alpha: u32, terms: [6]Term }
type ATerm = struct { op: u8, a: i64, b: i64 }
type Act = struct { op: u8, kind: u32, n: u32, cond: u32, terms: [6]ATerm }
type Rule = struct { name: str, salience: i32, nconds: u32, nacts: u32, node0: u32, specificity: u32, nvars: u32, conds: [6]Cond, acts: [6]Act }
type Fact = struct { kind: u32, alive: bool, f: [6]i64 }
type Token = struct { rule: u32, level: u32, next: u32, blocked: u32, alive: bool, fired: bool, path: [7]u32, facts: [6]u32, vars: [12]i64 }
type Alpha = struct { kind: u32, n: u32, head: u32, tests: [6]Term }
type Entry = struct { fact: u32, next: u32 }
type Node = struct { head: u32 }
type Limits = struct { facts: usize, tokens: usize, rules: usize, alphas: usize, entries: usize, names: usize, log: usize }
type Engine = struct { a: *mem.Arena, facts: []Fact, nfacts: usize, tokens: []Token, ntokens: usize, entries: []Entry, nentries: usize, alphas: []Alpha, nalphas: usize, nodes: []Node, nnodes: usize, rules: []Rule, nrules: usize, syms: []str, nsyms: usize, kinds: []str, nkinds: usize, log: []u32, nlog: usize, halted: bool }
type Column = struct { field: u32, op: u8 }
type Table = struct { name: str, in_kind: str, out_kind: str, in_arity: usize, out_arity: usize, cols: []const Column, rows: usize, cells: []const i64, outs: []const i64, first_hit: bool, salience: i32 }
type Parser = struct { src: str, pos: usize, vars: [12]str, nvars: usize }

error Full
error TooMany
error BadRule
error Syntax
error NotFound

fn any_cell() -> i64 { ret -9223372036854775807i64 - 1i64 }

// ---- construction ---------------------------------------------------------------------

fn init(a: *mem.Arena, lim: Limits) -> (Engine, err) {
    var e: Engine = zero
    e.a = a
    let (facts, e1) = mem.alloc[Fact](a, lim.facts)
    if e1 != ok { ret (e, e1) }
    let (tokens, e2) = mem.alloc[Token](a, lim.tokens)
    if e2 != ok { ret (e, e2) }
    let (entries, e3) = mem.alloc[Entry](a, lim.entries)
    if e3 != ok { ret (e, e3) }
    let (alphas, e4) = mem.alloc[Alpha](a, lim.alphas)
    if e4 != ok { ret (e, e4) }
    let (nodes, e5) = mem.alloc[Node](a, lim.rules * 7usize)
    if e5 != ok { ret (e, e5) }
    let (rules, e6) = mem.alloc[Rule](a, lim.rules)
    if e6 != ok { ret (e, e6) }
    let (syms, e7) = mem.alloc[str](a, lim.names)
    if e7 != ok { ret (e, e7) }
    let (kinds, e8) = mem.alloc[str](a, lim.names)
    if e8 != ok { ret (e, e8) }
    let (log, e9) = mem.alloc[u32](a, lim.log)
    if e9 != ok { ret (e, e9) }
    e.facts = facts
    e.tokens = tokens
    e.entries = entries
    e.alphas = alphas
    e.nodes = nodes
    e.rules = rules
    e.syms = syms
    e.kinds = kinds
    e.log = log
    ret (e, ok)
}

fn dup(a: *mem.Arena, s: str) -> (str, err) {
    if s.len == 0usize { ret ("", ok) }
    let (buf, alloc_error) = mem.alloc[u8](a, s.len)
    if alloc_error != ok { ret ("", alloc_error) }
    var i = 0usize
    while i < s.len {
        buf[i] = s[i]
        i += 1usize
    }
    ret (buf[0usize..s.len], ok)
}

fn same(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

// A symbol's `i64` (its index in the symbol table); the same name is the same number.
fn intern_symbol(e: *Engine, name: str) -> (i64, err) {
    var i = 0usize
    while i < e.nsyms {
        if same(e.syms[i], name) { ret (i64(i), ok) }
        i += 1usize
    }
    if e.nsyms >= e.syms.len { ret (0i64, Full) }
    let (copy, dup_error) = dup(e.a, name)
    if dup_error != ok { ret (0i64, dup_error) }
    e.syms[e.nsyms] = copy
    e.nsyms += 1usize
    ret (i64(e.nsyms - 1usize), ok)
}

fn intern_kind(e: *Engine, name: str) -> (u32, err) {
    var i = 0usize
    while i < e.nkinds {
        if same(e.kinds[i], name) { ret (u32(i), ok) }
        i += 1usize
    }
    if e.nkinds >= e.kinds.len { ret (NONE, Full) }
    let (copy, dup_error) = dup(e.a, name)
    if dup_error != ok { ret (NONE, dup_error) }
    e.kinds[e.nkinds] = copy
    e.nkinds += 1usize
    ret (u32(e.nkinds - 1usize), ok)
}

// ---- matching -------------------------------------------------------------------------

fn compare(op: u8, x: i64, y: i64) -> bool {
    if op == OP_EQ { ret x == y }
    if op == OP_NE { ret x != y }
    if op == OP_LT { ret x < y }
    if op == OP_LE { ret x <= y }
    if op == OP_GT { ret x > y }
    if op == OP_GE { ret x >= y }
    ret true
}

// Tests a fact against a condition, binding variables into `vars` (a working copy).
fn match_cond(c: Cond, f: Fact, vars: []i64) -> bool {
    if c.kind != f.kind { ret false }
    var j = 0usize
    while j < usize(c.n) {
        let tm = c.terms[j]
        let val = f.f[j]
        if tm.op != OP_ANY {
            var rhs = tm.v
            if tm.rv >= 0i32 { rhs = vars[usize(tm.rv)] }
            if !compare(tm.op, val, rhs) { ret false }
        }
        if tm.bind >= 0i32 {
            if tm.first {
                vars[usize(tm.bind)] = val
            } else {
                if vars[usize(tm.bind)] != val { ret false }
            }
        }
        j += 1usize
    }
    ret true
}

// The constant tests only: what an alpha memory decides.
fn alpha_pass(al: Alpha, f: Fact) -> bool {
    if al.kind != f.kind { ret false }
    var j = 0usize
    while j < usize(al.n) {
        let tm = al.tests[j]
        if tm.op != OP_ANY && !compare(tm.op, f.f[j], tm.v) { ret false }
        j += 1usize
    }
    ret true
}

fn new_token(e: *Engine, rule_index: u32, parent: u32) -> (u32, err) {
    if e.ntokens >= e.tokens.len { ret (NONE, Full) }
    let id = u32(e.ntokens)
    e.ntokens += 1usize
    var t: Token = zero
    var level = 0u32
    if parent != NONE {
        t = e.tokens[usize(parent)]
        level = t.level + 1u32
    } else {
        var j = 0usize
        while j < MAX_ARGS {
            t.facts[j] = NONE
            j += 1usize
        }
    }
    t.rule = rule_index
    t.level = level
    t.alive = true
    t.fired = false
    t.blocked = 0u32
    t.path[usize(level)] = id
    let node = usize(e.rules[usize(rule_index)].node0) + usize(level)
    t.next = e.nodes[node].head
    e.nodes[node].head = id
    e.tokens[usize(id)] = t
    ret (id, ok)
}

fn kill_below(e: *Engine, tid: u32) {
    let t = e.tokens[usize(tid)]
    let ri = usize(t.rule)
    let n = usize(e.rules[ri].nconds)
    let node0 = usize(e.rules[ri].node0)
    var lvl = usize(t.level) + 1usize
    while lvl <= n {
        var it = e.nodes[node0 + lvl].head
        while it != NONE {
            if e.tokens[usize(it)].path[usize(t.level)] == tid { e.tokens[usize(it)].alive = false }
            it = e.tokens[usize(it)].next
        }
        lvl += 1usize
    }
}

// A live token at level L has matched conditions 0..L; extend it through the next condition.
fn propagate(e: *Engine, tid: u32) -> err {
    let t = e.tokens[usize(tid)]
    let ri = usize(t.rule)
    if t.level >= e.rules[ri].nconds { ret ok }
    let c = e.rules[ri].conds[usize(t.level)]
    let head = e.alphas[usize(c.alpha)].head
    if c.neg {
        let (nid, nerr) = new_token(e, t.rule, tid)
        if nerr != ok { ret nerr }
        var blockers = 0u32
        var it = head
        while it != NONE {
            let en = e.entries[usize(it)]
            it = en.next
            let fact = e.facts[usize(en.fact)]
            if fact.alive {
                var vars = e.tokens[usize(nid)].vars
                if match_cond(c, fact, vars[0..]) { blockers += 1u32 }
            }
        }
        e.tokens[usize(nid)].blocked = blockers
        if blockers == 0u32 { ret propagate(e, nid) }
        ret ok
    }
    var it = head
    while it != NONE {
        let en = e.entries[usize(it)]
        it = en.next
        let fact = e.facts[usize(en.fact)]
        if fact.alive {
            var vars = t.vars
            if match_cond(c, fact, vars[0..]) {
                let (nid, nerr) = new_token(e, t.rule, tid)
                if nerr != ok { ret nerr }
                e.tokens[usize(nid)].vars = vars
                e.tokens[usize(nid)].facts[usize(t.level)] = en.fact
                try propagate(e, nid)
            }
        }
    }
    ret ok
}

// ---- rules ----------------------------------------------------------------------------

fn same_alpha(al: Alpha, kind_id: u32, n: u32, tests: [6]Term) -> bool {
    if al.kind != kind_id || al.n != n { ret false }
    var j = 0usize
    while j < usize(n) {
        let x = al.tests[j]
        let y = tests[j]
        if x.op != y.op { ret false }
        if x.op != OP_ANY && x.v != y.v { ret false }
        j += 1usize
    }
    ret true
}

// Compiles a rule into the network; facts already asserted activate it at once.
fn add_rule(e: *Engine, rule_in: Rule) -> err {
    var r = rule_in
    if r.nconds == 0u32 || usize(r.nconds) > MAX_CONDS || usize(r.nacts) > MAX_ACTS { ret BadRule }
    if e.nrules >= e.rules.len { ret Full }
    var bound: [12]bool = zero
    var spec = 0u32
    var maxvar = 0u32
    var ci = 0usize
    while ci < usize(r.nconds) {
        var c = r.conds[ci]
        if c.kind == NONE || usize(c.n) > MAX_ARGS { ret BadRule }
        var local = bound
        var tests: [6]Term = zero
        var j = 0usize
        while j < usize(c.n) {
            var tm = c.terms[j]
            if tm.bind >= 0i32 {
                if usize(tm.bind) >= MAX_VARS { ret BadRule }
                tm.first = !local[usize(tm.bind)]
                local[usize(tm.bind)] = true
                if u32(tm.bind) + 1u32 > maxvar { maxvar = u32(tm.bind) + 1u32 }
                spec += 1u32
            }
            if tm.rv >= 0i32 {
                if usize(tm.rv) >= MAX_VARS || !local[usize(tm.rv)] { ret BadRule }
            }
            if tm.op != OP_ANY { spec += 1u32 }
            c.terms[j] = tm
            if tm.op != OP_ANY && tm.rv < 0i32 { tests[j] = Term { bind: -1i32, first: false, op: tm.op, rv: -1i32, v: tm.v } } else { tests[j] = Term { bind: -1i32, first: false, op: OP_ANY, rv: -1i32, v: 0i64 } }
            j += 1usize
        }
        if !c.neg { bound = local }
        // The alpha memory: an existing one with the same constant tests, or a new one.
        var found = NONE
        var k = 0usize
        while k < e.nalphas {
            if same_alpha(e.alphas[k], c.kind, c.n, tests) {
                found = u32(k)
                break
            }
            k += 1usize
        }
        if found == NONE {
            if e.nalphas >= e.alphas.len { ret Full }
            var al: Alpha = zero
            al.kind = c.kind
            al.n = c.n
            al.head = NONE
            al.tests = tests
            found = u32(e.nalphas)
            e.alphas[e.nalphas] = al
            e.nalphas += 1usize
            var fi = 0usize
            while fi < e.nfacts {
                if e.facts[fi].alive && alpha_pass(al, e.facts[fi]) {
                    if e.nentries >= e.entries.len { ret Full }
                    e.entries[e.nentries] = Entry { fact: u32(fi), next: e.alphas[usize(found)].head }
                    e.alphas[usize(found)].head = u32(e.nentries)
                    e.nentries += 1usize
                }
                fi += 1usize
            }
        }
        c.alpha = found
        r.conds[ci] = c
        ci += 1usize
    }
    var ai = 0usize
    while ai < usize(r.nacts) {
        let ac = r.acts[ai]
        if ac.op == ACT_ASSERT {
            if ac.kind == NONE || usize(ac.n) > MAX_ARGS { ret BadRule }
            var j = 0usize
            while j < usize(ac.n) {
                let at = ac.terms[j]
                if at.op != AT_CONST {
                    if at.a < 0i64 || at.a >= i64(MAX_VARS) || !bound[usize(at.a)] { ret BadRule }
                }
                if at.op == AT_ADD_VAR {
                    if at.b < 0i64 || at.b >= i64(MAX_VARS) || !bound[usize(at.b)] { ret BadRule }
                }
                j += 1usize
            }
        } else {
            if ac.op == ACT_RETRACT {
                if usize(ac.cond) >= usize(r.nconds) || r.conds[usize(ac.cond)].neg { ret BadRule }
            } else {
                if ac.op != ACT_HALT { ret BadRule }
            }
        }
        ai += 1usize
    }
    if e.nnodes + usize(r.nconds) + 1usize > e.nodes.len { ret Full }
    r.node0 = u32(e.nnodes)
    r.specificity = spec
    r.nvars = maxvar
    var ni = 0usize
    while ni <= usize(r.nconds) {
        e.nodes[e.nnodes + ni] = Node { head: NONE }
        ni += 1usize
    }
    e.nnodes += usize(r.nconds) + 1usize
    let rule_index = u32(e.nrules)
    e.rules[e.nrules] = r
    e.nrules += 1usize
    let (root, root_error) = new_token(e, rule_index, NONE)
    if root_error != ok { ret root_error }
    ret propagate(e, root)
}

// ---- working memory -------------------------------------------------------------------

fn find_fact(e: *Engine, f: Fact) -> u32 {
    var i = 0usize
    while i < e.nfacts {
        let g = e.facts[i]
        if g.alive && g.kind == f.kind {
            var j = 0usize
            var eq = true
            while j < MAX_ARGS {
                if g.f[j] != f.f[j] {
                    eq = false
                    break
                }
                j += 1usize
            }
            if eq { ret u32(i) }
        }
        i += 1usize
    }
    ret NONE
}

fn right_activate(e: *Engine, ri: usize, ci: usize, fid: u32) -> err {
    let c = e.rules[ri].conds[ci]
    let fact = e.facts[usize(fid)]
    let node0 = usize(e.rules[ri].node0)
    if c.neg {
        var it = e.nodes[node0 + ci + 1usize].head
        while it != NONE {
            let tid = it
            it = e.tokens[usize(tid)].next
            if e.tokens[usize(tid)].alive {
                var vars = e.tokens[usize(tid)].vars
                if match_cond(c, fact, vars[0..]) {
                    e.tokens[usize(tid)].blocked += 1u32
                    if e.tokens[usize(tid)].blocked == 1u32 { kill_below(e, tid) }
                }
            }
        }
        ret ok
    }
    var it = e.nodes[node0 + ci].head
    while it != NONE {
        let tid = it
        it = e.tokens[usize(tid)].next
        let t = e.tokens[usize(tid)]
        if t.alive && t.blocked == 0u32 {
            var vars = t.vars
            if match_cond(c, fact, vars[0..]) {
                let (nid, nerr) = new_token(e, u32(ri), tid)
                if nerr != ok { ret nerr }
                e.tokens[usize(nid)].vars = vars
                e.tokens[usize(nid)].facts[ci] = fid
                try propagate(e, nid)
            }
        }
    }
    ret ok
}

// Asserts a fact; the answer is its id and whether it is new.
fn assert_fact(e: *Engine, kind_id: u32, args: []const i64) -> (u32, bool, err) {
    if args.len > MAX_ARGS { ret (NONE, false, TooMany) }
    var f: Fact = zero
    f.kind = kind_id
    f.alive = true
    var j = 0usize
    while j < args.len {
        f.f[j] = args[j]
        j += 1usize
    }
    let existing = find_fact(e, f)
    if existing != NONE { ret (existing, false, ok) }
    if e.nfacts >= e.facts.len { ret (NONE, false, Full) }
    let id = u32(e.nfacts)
    e.facts[e.nfacts] = f
    e.nfacts += 1usize
    var ai = 0usize
    while ai < e.nalphas {
        if alpha_pass(e.alphas[ai], f) {
            if e.nentries >= e.entries.len { ret (id, true, Full) }
            e.entries[e.nentries] = Entry { fact: id, next: e.alphas[ai].head }
            e.alphas[ai].head = u32(e.nentries)
            e.nentries += 1usize
        }
        ai += 1usize
    }
    var ri = 0usize
    while ri < e.nrules {
        var ci = usize(e.rules[ri].nconds)
        while ci > 0usize {
            ci -= 1usize
            let al = e.alphas[usize(e.rules[ri].conds[ci].alpha)]
            if alpha_pass(al, f) {
                let ra_error = right_activate(e, ri, ci, id)
                if ra_error != ok { ret (id, true, ra_error) }
            }
        }
        ri += 1usize
    }
    ret (id, true, ok)
}

fn retract(e: *Engine, fid: u32) -> err {
    if usize(fid) >= e.nfacts || !e.facts[usize(fid)].alive { ret NotFound }
    e.facts[usize(fid)].alive = false
    var i = 0usize
    while i < e.ntokens {
        if e.tokens[i].alive {
            var j = 0usize
            while j < MAX_ARGS {
                if e.tokens[i].facts[j] == fid { e.tokens[i].alive = false }
                j += 1usize
            }
        }
        i += 1usize
    }
    let fact = e.facts[usize(fid)]
    var ri = 0usize
    while ri < e.nrules {
        var ci = 0usize
        while ci < usize(e.rules[ri].nconds) {
            let c = e.rules[ri].conds[ci]
            if c.neg && alpha_pass(e.alphas[usize(c.alpha)], fact) {
                var it = e.nodes[usize(e.rules[ri].node0) + ci + 1usize].head
                while it != NONE {
                    let tid = it
                    it = e.tokens[usize(tid)].next
                    if e.tokens[usize(tid)].alive && e.tokens[usize(tid)].blocked > 0u32 {
                        var vars = e.tokens[usize(tid)].vars
                        if match_cond(c, fact, vars[0..]) {
                            e.tokens[usize(tid)].blocked -= 1u32
                            if e.tokens[usize(tid)].blocked == 0u32 {
                                let pr_error = propagate(e, tid)
                                if pr_error != ok { ret pr_error }
                            }
                        }
                    }
                }
            }
            ci += 1usize
        }
        ri += 1usize
    }
    ret ok
}

fn count(e: *Engine, kind_id: u32) -> usize {
    var n = 0usize
    var i = 0usize
    while i < e.nfacts {
        if e.facts[i].alive && e.facts[i].kind == kind_id { n += 1usize }
        i += 1usize
    }
    ret n
}

// Whether the exact fact (missing fields zero) is in working memory.
fn has(e: *Engine, kind_id: u32, args: []const i64) -> bool {
    var f: Fact = zero
    f.kind = kind_id
    var j = 0usize
    while j < args.len && j < MAX_ARGS {
        f.f[j] = args[j]
        j += 1usize
    }
    ret find_fact(e, f) != NONE
}

// ---- the agenda -----------------------------------------------------------------------

fn sorted_ids(t: Token, n: u32, out: []u32) -> usize {
    var cnt = 0usize
    var j = 0usize
    while j < usize(n) {
        let id = t.facts[j]
        if id != NONE {
            var k = cnt
            while k > 0usize && out[k - 1usize] < id {
                out[k] = out[k - 1usize]
                k -= 1usize
            }
            out[k] = id
            cnt += 1usize
        }
        j += 1usize
    }
    ret cnt
}

// Whether activation `x` is strictly preferred to `y`.
fn better(e: *Engine, x: u32, y: u32) -> bool {
    let tx = e.tokens[usize(x)]
    let ty = e.tokens[usize(y)]
    let sx = e.rules[usize(tx.rule)].salience
    let sy = e.rules[usize(ty.rule)].salience
    if sx != sy { ret sx > sy }
    var ix: [6]u32 = zero
    var iy: [6]u32 = zero
    let nx = sorted_ids(tx, e.rules[usize(tx.rule)].nconds, ix[0..])
    let ny = sorted_ids(ty, e.rules[usize(ty.rule)].nconds, iy[0..])
    var k = 0usize
    while k < nx && k < ny {
        if ix[k] != iy[k] { ret ix[k] > iy[k] }
        k += 1usize
    }
    if nx != ny { ret nx > ny }
    let px = e.rules[usize(tx.rule)].specificity
    let py = e.rules[usize(ty.rule)].specificity
    if px != py { ret px > py }
    ret tx.rule < ty.rule
}

fn eval_term(at: ATerm, vars: [12]i64) -> i64 {
    if at.op == AT_VAR { ret vars[usize(at.a)] }
    if at.op == AT_ADD_VAR { ret vars[usize(at.a)] + vars[usize(at.b)] }
    if at.op == AT_ADD_CONST { ret vars[usize(at.a)] + at.b }
    ret at.a
}

fn run_actions(e: *Engine, tid: u32) -> err {
    let t = e.tokens[usize(tid)]
    let ri = usize(t.rule)
    var ai = 0usize
    while ai < usize(e.rules[ri].nacts) {
        let ac = e.rules[ri].acts[ai]
        if ac.op == ACT_ASSERT {
            var args: [6]i64 = zero
            var j = 0usize
            while j < usize(ac.n) {
                args[j] = eval_term(ac.terms[j], t.vars)
                j += 1usize
            }
            let (id, fresh, assert_error) = assert_fact(e, ac.kind, args[0..usize(ac.n)])
            if assert_error != ok { ret assert_error }
        } else {
            if ac.op == ACT_RETRACT {
                let fid = t.facts[usize(ac.cond)]
                if fid != NONE && e.facts[usize(fid)].alive {
                    try retract(e, fid)
                }
            } else {
                e.halted = true
            }
        }
        ai += 1usize
    }
    ret ok
}

// Fires the best activation until none is left, a rule halts, or `limit` have fired; the
// number fired. The rule index of each firing is appended to the log (`fired_rule`).
fn fire(e: *Engine, limit: usize) -> (usize, err) {
    var fired = 0usize
    e.halted = false
    while fired < limit && !e.halted {
        var best = NONE
        var i = 0usize
        while i < e.ntokens {
            let t = e.tokens[i]
            if t.alive && !t.fired && t.blocked == 0u32 && t.level == e.rules[usize(t.rule)].nconds {
                if best == NONE || better(e, u32(i), best) { best = u32(i) }
            }
            i += 1usize
        }
        if best == NONE { break }
        e.tokens[usize(best)].fired = true
        if e.nlog < e.log.len {
            e.log[e.nlog] = e.tokens[usize(best)].rule
            e.nlog += 1usize
        }
        fired += 1usize
        let run_error = run_actions(e, best)
        if run_error != ok { ret (fired, run_error) }
    }
    ret (fired, ok)
}

fn fired_rule(e: *Engine, n: usize) -> u32 {
    if n >= e.nlog { ret NONE }
    ret e.log[n]
}

// ---- decision tables ------------------------------------------------------------------

fn bind_term(var_index: usize) -> Term {
    ret Term { bind: i32(var_index), first: false, op: OP_ANY, rv: -1i32, v: 0i64 }
}

fn const_aterm(v: i64) -> ATerm { ret ATerm { op: AT_CONST, a: v, b: 0i64 } }

fn var_aterm(index: usize) -> ATerm { ret ATerm { op: AT_VAR, a: i64(index), b: 0i64 } }

// One rule per row; see the header for the first-hit marker.
fn add_table(e: *Engine, t: Table) -> err {
    if t.in_arity == 0usize || t.in_arity > MAX_ARGS || t.out_arity > MAX_ARGS { ret BadRule }
    if t.cells.len != t.rows * t.cols.len || t.outs.len != t.rows * t.out_arity { ret BadRule }
    let (in_id, in_error) = intern_kind(e, t.in_kind)
    if in_error != ok { ret in_error }
    let (out_id, out_error) = intern_kind(e, t.out_kind)
    if out_error != ok { ret out_error }
    var marker_id = NONE
    if t.first_hit {
        let (mid, marker_error) = intern_kind(e, t.name)
        if marker_error != ok { ret marker_error }
        marker_id = mid
    }
    // Occurrence index of each column on its field: the pattern that carries its test.
    var occ: [16]u32 = zero
    var seen: [6]u32 = zero
    var pats = 1u32
    var ci = 0usize
    while ci < t.cols.len {
        if ci >= 16usize || usize(t.cols[ci].field) >= t.in_arity { ret BadRule }
        let fld = usize(t.cols[ci].field)
        occ[ci] = seen[fld]
        seen[fld] += 1u32
        if seen[fld] > pats { pats = seen[fld] }
        ci += 1usize
    }
    var row = 0usize
    while row < t.rows {
        var r: Rule = zero
        r.name = t.name
        r.salience = t.salience - i32(row)
        var p = 0usize
        while p < usize(pats) {
            var c: Cond = zero
            c.kind = in_id
            c.n = u32(t.in_arity)
            var j = 0usize
            while j < t.in_arity {
                c.terms[j] = bind_term(j)
                j += 1usize
            }
            var k = 0usize
            while k < t.cols.len {
                let cell = t.cells[row * t.cols.len + k]
                if usize(occ[k]) == p && cell != any_cell() {
                    c.terms[usize(t.cols[k].field)].op = t.cols[k].op
                    c.terms[usize(t.cols[k].field)].v = cell
                }
                k += 1usize
            }
            r.conds[p] = c
            p += 1usize
        }
        r.nconds = pats
        if t.first_hit {
            var nc: Cond = zero
            nc.kind = marker_id
            nc.neg = true
            nc.n = u32(t.in_arity)
            var j = 0usize
            while j < t.in_arity {
                nc.terms[j] = bind_term(j)
                j += 1usize
            }
            r.conds[usize(pats)] = nc
            r.nconds = pats + 1u32
        }
        var act: Act = zero
        act.op = ACT_ASSERT
        act.kind = out_id
        act.n = u32(t.out_arity)
        var o = 0usize
        while o < t.out_arity {
            act.terms[o] = const_aterm(t.outs[row * t.out_arity + o])
            o += 1usize
        }
        r.acts[0] = act
        r.nacts = 1u32
        if t.first_hit {
            var mk: Act = zero
            mk.op = ACT_ASSERT
            mk.kind = marker_id
            mk.n = u32(t.in_arity)
            var j2 = 0usize
            while j2 < t.in_arity {
                mk.terms[j2] = var_aterm(j2)
                j2 += 1usize
            }
            r.acts[1] = mk
            r.nacts = 2u32
        }
        try add_rule(e, r)
        row += 1usize
    }
    ret ok
}

// ---- the rule DSL ---------------------------------------------------------------------

fn is_word_char(c: u8) -> bool {
    ret (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || (c >= 48u8 && c <= 57u8) || c == 95u8 || c == 46u8
}

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn skip(p: *Parser) {
    while p.pos < p.src.len {
        let c = p.src[p.pos]
        if c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 {
            p.pos += 1usize
        } else {
            if c == 47u8 && p.pos + 1usize < p.src.len && p.src[p.pos + 1usize] == 47u8 {
                while p.pos < p.src.len && p.src[p.pos] != 10u8 { p.pos += 1usize }
            } else {
                break
            }
        }
    }
}

// Consumes a punctuation string.
fn accept(p: *Parser, s: str) -> bool {
    skip(p)
    if p.pos + s.len > p.src.len { ret false }
    var i = 0usize
    while i < s.len {
        if p.src[p.pos + i] != s[i] { ret false }
        i += 1usize
    }
    p.pos += s.len
    ret true
}

// Consumes a keyword that is not the start of a longer word.
fn accept_kw(p: *Parser, s: str) -> bool {
    skip(p)
    if p.pos + s.len > p.src.len { ret false }
    var i = 0usize
    while i < s.len {
        if p.src[p.pos + i] != s[i] { ret false }
        i += 1usize
    }
    if p.pos + s.len < p.src.len && is_word_char(p.src[p.pos + s.len]) { ret false }
    p.pos += s.len
    ret true
}

fn expect(p: *Parser, s: str) -> err {
    if !accept(p, s) { ret Syntax }
    ret ok
}

fn word(p: *Parser) -> (str, err) {
    skip(p)
    let start = p.pos
    while p.pos < p.src.len && is_word_char(p.src[p.pos]) { p.pos += 1usize }
    if p.pos == start { ret ("", Syntax) }
    ret (p.src[start..p.pos], ok)
}

fn integer(p: *Parser) -> (i64, err) {
    skip(p)
    var neg = false
    if p.pos < p.src.len && p.src[p.pos] == 45u8 {
        neg = true
        p.pos += 1usize
    }
    let start = p.pos
    var v = 0i64
    while p.pos < p.src.len && is_digit(p.src[p.pos]) {
        v = v * 10i64 + i64(p.src[p.pos] - 48u8)
        p.pos += 1usize
    }
    if p.pos == start { ret (0i64, Syntax) }
    if neg { ret (0i64 - v, ok) }
    ret (v, ok)
}

fn var_slot(p: *Parser, name: str) -> (i32, err) {
    var i = 0usize
    while i < p.nvars {
        if same(p.vars[i], name) { ret (i32(i), ok) }
        i += 1usize
    }
    if p.nvars >= MAX_VARS { ret (-1i32, BadRule) }
    p.vars[p.nvars] = name
    p.nvars += 1usize
    ret (i32(p.nvars - 1usize), ok)
}

fn parse_op(p: *Parser) -> u8 {
    if accept(p, "==") { ret OP_EQ }
    if accept(p, "!=") { ret OP_NE }
    if accept(p, "<=") { ret OP_LE }
    if accept(p, ">=") { ret OP_GE }
    if accept(p, "<") { ret OP_LT }
    if accept(p, ">") { ret OP_GT }
    ret OP_ANY
}

// An integer or a `:symbol`.
fn parse_const(e: *Engine, p: *Parser) -> (i64, err) {
    if accept(p, ":") {
        let (name, word_error) = word(p)
        if word_error != ok { ret (0i64, word_error) }
        let (sym_id, sym_error) = intern_symbol(e, name)
        ret (sym_id, sym_error)
    }
    let (num, num_error) = integer(p)
    ret (num, num_error)
}

fn parse_term(e: *Engine, p: *Parser) -> (Term, err) {
    var tm = Term { bind: -1i32, first: false, op: OP_ANY, rv: -1i32, v: 0i64 }
    skip(p)
    if p.pos >= p.src.len { ret (tm, Syntax) }
    let c = p.src[p.pos]
    if c == 95u8 && (p.pos + 1usize >= p.src.len || !is_word_char(p.src[p.pos + 1usize])) {
        p.pos += 1usize
        ret (tm, ok)
    }
    if c == 63u8 {
        p.pos += 1usize
        let (name, word_error) = word(p)
        if word_error != ok { ret (tm, word_error) }
        let (slot, slot_error) = var_slot(p, name)
        if slot_error != ok { ret (tm, slot_error) }
        tm.bind = slot
    }
    let op = parse_op(p)
    if op != OP_ANY {
        tm.op = op
        if accept(p, "?") {
            let (name, word_error) = word(p)
            if word_error != ok { ret (tm, word_error) }
            let (slot, slot_error) = var_slot(p, name)
            if slot_error != ok { ret (tm, slot_error) }
            tm.rv = slot
        } else {
            let (v, const_error) = parse_const(e, p)
            if const_error != ok { ret (tm, const_error) }
            tm.v = v
        }
        ret (tm, ok)
    }
    if tm.bind >= 0i32 { ret (tm, ok) }
    let (v2, const_error2) = parse_const(e, p)
    if const_error2 != ok { ret (tm, const_error2) }
    tm.op = OP_EQ
    tm.v = v2
    ret (tm, ok)
}

fn parse_cond(e: *Engine, p: *Parser, neg: bool) -> (Cond, err) {
    var c: Cond = zero
    c.neg = neg
    let (name, word_error) = word(p)
    if word_error != ok { ret (c, word_error) }
    let (kid, kind_error) = intern_kind(e, name)
    if kind_error != ok { ret (c, kind_error) }
    c.kind = kid
    try expect(p, "(")
    if accept(p, ")") { ret (c, ok) }
    while true {
        if usize(c.n) >= MAX_ARGS { ret (c, TooMany) }
        let (tm, term_error) = parse_term(e, p)
        if term_error != ok { ret (c, term_error) }
        c.terms[usize(c.n)] = tm
        c.n += 1u32
        if accept(p, ")") { break }
        try expect(p, ",")
    }
    ret (c, ok)
}

fn parse_aterm(e: *Engine, p: *Parser) -> (ATerm, err) {
    var at = ATerm { op: AT_CONST, a: 0i64, b: 0i64 }
    if accept(p, "?") {
        let (name, word_error) = word(p)
        if word_error != ok { ret (at, word_error) }
        let (slot, slot_error) = var_slot(p, name)
        if slot_error != ok { ret (at, slot_error) }
        at.op = AT_VAR
        at.a = i64(slot)
        if accept(p, "+") {
            if accept(p, "?") {
                let (name2, word_error2) = word(p)
                if word_error2 != ok { ret (at, word_error2) }
                let (slot2, slot_error2) = var_slot(p, name2)
                if slot_error2 != ok { ret (at, slot_error2) }
                at.op = AT_ADD_VAR
                at.b = i64(slot2)
            } else {
                let (k, int_error) = integer(p)
                if int_error != ok { ret (at, int_error) }
                at.op = AT_ADD_CONST
                at.b = k
            }
        } else {
            skip(p)
            if p.pos < p.src.len && p.src[p.pos] == 45u8 {
                let (k2, int_error2) = integer(p)
                if int_error2 != ok { ret (at, int_error2) }
                at.op = AT_ADD_CONST
                at.b = k2
            }
        }
        ret (at, ok)
    }
    let (v, const_error) = parse_const(e, p)
    if const_error != ok { ret (at, const_error) }
    at.a = v
    ret (at, ok)
}

fn parse_rule(e: *Engine, p: *Parser) -> err {
    var r: Rule = zero
    p.nvars = 0usize
    let (name, name_error) = word(p)
    if name_error != ok { ret name_error }
    let (copy, dup_error) = dup(e.a, name)
    if dup_error != ok { ret dup_error }
    r.name = copy
    if accept_kw(p, "salience") {
        let (s, sal_error) = integer(p)
        if sal_error != ok { ret sal_error }
        r.salience = i32(s)
    }
    if !accept_kw(p, "when") { ret Syntax }
    while !accept_kw(p, "then") {
        if usize(r.nconds) >= MAX_CONDS { ret TooMany }
        let neg = accept_kw(p, "not")
        let (c, cond_error) = parse_cond(e, p, neg)
        if cond_error != ok { ret cond_error }
        r.conds[usize(r.nconds)] = c
        r.nconds += 1u32
    }
    while !accept_kw(p, "end") {
        if usize(r.nacts) >= MAX_ACTS { ret TooMany }
        var ac: Act = zero
        if accept_kw(p, "assert") {
            let (name2, word_error) = word(p)
            if word_error != ok { ret word_error }
            let (kid, kind_error) = intern_kind(e, name2)
            if kind_error != ok { ret kind_error }
            ac.op = ACT_ASSERT
            ac.kind = kid
            try expect(p, "(")
            if !accept(p, ")") {
                while true {
                    if usize(ac.n) >= MAX_ARGS { ret TooMany }
                    let (at, term_error) = parse_aterm(e, p)
                    if term_error != ok { ret term_error }
                    ac.terms[usize(ac.n)] = at
                    ac.n += 1u32
                    if accept(p, ")") { break }
                    try expect(p, ",")
                }
            }
        } else {
            if accept_kw(p, "retract") {
                let (idx, idx_error) = integer(p)
                if idx_error != ok { ret idx_error }
                if idx < 0i64 || idx > 5i64 { ret BadRule }
                ac.op = ACT_RETRACT
                ac.cond = u32(idx)
            } else {
                if accept_kw(p, "halt") {
                    ac.op = ACT_HALT
                } else {
                    ret Syntax
                }
            }
        }
        r.acts[usize(r.nacts)] = ac
        r.nacts += 1u32
    }
    ret add_rule(e, r)
}

// Parses and adds every rule in `src`.
fn load(e: *Engine, src: str) -> err {
    var p: Parser = zero
    p.src = src
    while true {
        skip(&p)
        if p.pos >= src.len { break }
        if !accept_kw(&p, "rule") { ret Syntax }
        try parse_rule(e, &p)
    }
    ret ok
}
