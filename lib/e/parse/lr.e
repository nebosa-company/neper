// LR parsing over an `e.parse.Grammar` in caller storage. `items` builds the
// LR(0) canonical collection (closure/goto from the augmented `S' -> start`,
// rule index `rule_count` with lhs `symbol_count`) into a `Collection`:
// state `s` is `items[set_start[s]..set_start[s + 1]]`, `trans[s * symbols
// + X]` is the goto state on `X` or `NONE`. `items1` builds the LR(1)
// collection, each item carrying its lookahead terminal (`$` is
// `g.terminals`). `slr_table` (LR(0) sets, FOLLOW lookaheads),
// `canonical_table` (LR(1) sets) and `lalr_table` (LR(1) sets merged on
// equal cores) fill ACTION `[state][terminal or $]` (a u32: value << 2 |
// tag, tags ERROR/SHIFT state/REDUCE rule/ACCEPT) and GOTO `[state][non-
// terminal - terminals]` (`NONE` when absent), answering (state count,
// conflict count); a conflicting cell keeps shift over reduce and the lower
// rule between reduces. `parse` drives the tables, answering the reduces in
// order (the rightmost derivation reversed).
// ponytail: a new state is found by comparing whole item sets against every
// earlier state; hash the kernels when a grammar has thousands of states.

use e.parse as base
use e.parse.ll as ll

type Item = struct { rule: u32, dot: u32, la: u32 }
type Collection = struct { items: []Item, set_start: []usize, trans: []u32, nullable: []bool, first: []u64, follow: []u64, states: usize, symbols: usize, used: usize }
error TooSmall
error Invalid

const NONE: u32 = 4294967295u32
const ERROR: u32 = 0u32
const SHIFT: u32 = 1u32
const REDUCE: u32 = 2u32
const ACCEPT: u32 = 3u32

// Storage for a collection: `nullable`, `first` and `follow` hold one entry
// per symbol (`symbol_count` of them; they also fix the symbol count), the
// item pool and `set_start` (state count + 1) bound the states, and
// `trans.len / symbols` bounds them too.
fn collection(pool: []Item, set_start: []usize, trans: []u32, nullable: []bool, first: []u64, follow: []u64) -> Collection {
    ret Collection { items: pool, set_start: set_start, trans: trans, nullable: nullable, first: first, follow: follow, states: 0usize, symbols: 0usize, used: 0usize }
}

fn tag(action: u32) -> u32 { ret action & 3u32 }
fn value(action: u32) -> u32 { ret action >> 2u32 }
fn encode(kind: u32, v: u32) -> u32 { ret (v << 2u32) | kind }

// The augmented grammar: rule `rule_count` is `S' -> start`.
fn body_len(g: *const base.Grammar, rule: usize) -> usize {
    if rule == base.rule_count(g) { ret 1usize }
    ret base.rule_len(g, rule)
}
fn body_symbol(g: *const base.Grammar, start: u32, rule: usize, k: usize) -> u32 {
    if rule == base.rule_count(g) { ret start }
    ret base.rule_symbol(g, rule, k)
}

fn add_item(c: *Collection, from: usize, it: Item) -> err {
    var m = from
    while m < c.used {
        if c.items[m].rule == it.rule && c.items[m].dot == it.dot && c.items[m].la == it.la { ret ok }
        m += 1usize
    }
    if c.used >= c.items.len { ret TooSmall }
    c.items[c.used] = it
    c.used += 1usize
    ret ok
}

// Close the set at `items[from..used]` in place.
fn closure(g: *const base.Grammar, start: u32, c: *Collection, from: usize, lr1: bool) -> err {
    let rules = base.rule_count(g)
    var j = from
    while j < c.used {
        let it = c.items[j]
        let rule = usize(it.rule)
        if usize(it.dot) < body_len(g, rule) {
            let sym = body_symbol(g, start, rule, usize(it.dot))
            if sym >= g.terminals {
                var mask = 0u64
                if lr1 {
                    if rule == rules {
                        mask = 1u64 << it.la
                    } else {
                        let (m, all) = ll.first_of(g, c.nullable, c.first, rule, usize(it.dot) + 1usize)
                        mask = m
                        if all { mask |= 1u64 << it.la }
                    }
                }
                var r = 0usize
                while r < rules {
                    if g.lhs[r] == sym {
                        if lr1 {
                            var a = 0u32
                            while a <= g.terminals {
                                if ((mask >> a) & 1u64) == 1u64 {
                                    let e = add_item(c, from, Item { rule: u32(r), dot: 0u32, la: a })
                                    if e != ok { ret e }
                                }
                                a += 1u32
                            }
                        } else {
                            let e = add_item(c, from, Item { rule: u32(r), dot: 0u32, la: NONE })
                            if e != ok { ret e }
                        }
                    }
                    r += 1usize
                }
            }
        }
        j += 1usize
    }
    ret ok
}

fn same_set(c: *const Collection, s: usize, from: usize) -> bool {
    let lo = c.set_start[s]
    let hi = c.set_start[s + 1usize]
    if hi - lo != c.used - from { ret false }
    var j = from
    while j < c.used {
        var m = lo
        var found = false
        while m < hi {
            if c.items[m].rule == c.items[j].rule && c.items[m].dot == c.items[j].dot && c.items[m].la == c.items[j].la { found = true }
            m += 1usize
        }
        if !found { ret false }
        j += 1usize
    }
    ret true
}

fn build(g: *const base.Grammar, start: u32, c: *Collection, lr1: bool) -> err {
    let symbols = ll.symbol_count(g)
    if g.terminals > 63u32 || start < g.terminals || usize(start) >= symbols { ret Invalid }
    if c.nullable.len < symbols || c.first.len < symbols || c.set_start.len < 2usize || c.trans.len < symbols { ret TooSmall }
    let e = ll.nullable(g, c.nullable)
    if e != ok { ret e }
    let first_error = ll.first(g, c.nullable, c.first)
    if first_error != ok { ret first_error }
    c.symbols = symbols
    c.used = 0usize
    c.states = 1usize
    c.set_start[0usize] = 0usize
    var la = NONE
    if lr1 { la = g.terminals }
    let seed = add_item(c, 0usize, Item { rule: u32(base.rule_count(g)), dot: 0u32, la: la })
    if seed != ok { ret seed }
    let close_error = closure(g, start, c, 0usize, lr1)
    if close_error != ok { ret close_error }
    c.set_start[1usize] = c.used
    var s = 0usize
    while s < c.states {
        var x = 0u32
        while usize(x) < symbols {
            let from = c.used
            var j = c.set_start[s]
            while j < c.set_start[s + 1usize] {
                let it = c.items[j]
                if usize(it.dot) < body_len(g, usize(it.rule)) && body_symbol(g, start, usize(it.rule), usize(it.dot)) == x {
                    let add_error = add_item(c, from, Item { rule: it.rule, dot: it.dot + 1u32, la: it.la })
                    if add_error != ok { ret add_error }
                }
                j += 1usize
            }
            var to = NONE
            if c.used > from {
                let kernel_error = closure(g, start, c, from, lr1)
                if kernel_error != ok { ret kernel_error }
                var t = 0usize
                while t < c.states && to == NONE {
                    if same_set(c, t, from) { to = u32(t) }
                    t += 1usize
                }
                if to == NONE {
                    if c.states + 1usize >= c.set_start.len || (c.states + 1usize) * symbols > c.trans.len { ret TooSmall }
                    to = u32(c.states)
                    c.states += 1usize
                    c.set_start[c.states] = c.used
                } else {
                    c.used = from
                }
            }
            c.trans[s * symbols + usize(x)] = to
            x += 1u32
        }
        s += 1usize
    }
    ret ok
}

// The LR(0) canonical collection (items carry `la == NONE`).
fn items(g: *const base.Grammar, start: u32, c: *Collection) -> err {
    let e = build(g, start, c, false)
    ret e
}

// The LR(1) canonical collection.
fn items1(g: *const base.Grammar, start: u32, c: *Collection) -> err {
    let e = build(g, start, c, true)
    ret e
}

fn set_action(action: []u32, cell: usize, kind: u32, v: u32, conflicts: usize) -> usize {
    let wanted = encode(kind, v)
    let current = action[cell]
    if current == ERROR || current == wanted {
        action[cell] = wanted
        ret conflicts
    }
    if tag(current) == REDUCE && (kind == SHIFT || (kind == REDUCE && v < value(current))) { action[cell] = wanted }
    ret conflicts + 1usize
}

// Fill ACTION/GOTO for `states` merged states from the collection; `merged`
// maps every collection state to its table state; `slr` takes reduce
// lookaheads from `c.follow`, else from the item.
fn fill(g: *const base.Grammar, start: u32, c: *const Collection, merged: []const u32, states: usize, slr: bool, action: []u32, gotos: []u32) -> (usize, err) {
    let cols = usize(g.terminals) + 1usize
    let nts = c.symbols - usize(g.terminals)
    if action.len < states * cols || gotos.len < states * nts { ret (0usize, TooSmall) }
    var i = 0usize
    while i < states * cols {
        action[i] = ERROR
        i += 1usize
    }
    i = 0usize
    while i < states * nts {
        gotos[i] = NONE
        i += 1usize
    }
    var conflicts = 0usize
    var s = 0usize
    while s < c.states {
        let ms = usize(merged[s])
        var j = c.set_start[s]
        while j < c.set_start[s + 1usize] {
            let it = c.items[j]
            let rule = usize(it.rule)
            if usize(it.dot) < body_len(g, rule) {
                let x = body_symbol(g, start, rule, usize(it.dot))
                let to = merged[usize(c.trans[s * c.symbols + usize(x)])]
                if x < g.terminals {
                    conflicts = set_action(action, ms * cols + usize(x), SHIFT, to, conflicts)
                } else {
                    gotos[ms * nts + usize(x) - usize(g.terminals)] = to
                }
            } else if rule == base.rule_count(g) {
                conflicts = set_action(action, ms * cols + usize(g.terminals), ACCEPT, 0u32, conflicts)
            } else if slr {
                var a = 0u32
                while a <= g.terminals {
                    if ((c.follow[usize(g.lhs[rule])] >> a) & 1u64) == 1u64 { conflicts = set_action(action, ms * cols + usize(a), REDUCE, it.rule, conflicts) }
                    a += 1u32
                }
            } else {
                conflicts = set_action(action, ms * cols + usize(it.la), REDUCE, it.rule, conflicts)
            }
            j += 1usize
        }
        s += 1usize
    }
    ret (conflicts, ok)
}

// The identity state map for the unmerged tables.
fn identity(merged: []u32, states: usize) -> err {
    if merged.len < states { ret TooSmall }
    var s = 0usize
    while s < states {
        merged[s] = u32(s)
        s += 1usize
    }
    ret ok
}

// SLR(1): LR(0) sets, reduce on FOLLOW; `merged.len >= states` is scratch.
// Answers (states, conflicts).
fn slr_table(g: *const base.Grammar, start: u32, c: *Collection, merged: []u32, action: []u32, gotos: []u32) -> (usize, usize, err) {
    let e = build(g, start, c, false)
    if e != ok { ret (0usize, 0usize, e) }
    if c.follow.len < c.symbols { ret (0usize, 0usize, TooSmall) }
    let follow_error = ll.follow(g, start, c.nullable, c.first, c.follow)
    if follow_error != ok { ret (0usize, 0usize, follow_error) }
    let id_error = identity(merged, c.states)
    if id_error != ok { ret (0usize, 0usize, id_error) }
    let (conflicts, fill_error) = fill(g, start, c, merged, c.states, true, action, gotos)
    ret (c.states, conflicts, fill_error)
}

// Canonical LR(1); `merged.len >= states` is scratch. Answers (states, conflicts).
fn canonical_table(g: *const base.Grammar, start: u32, c: *Collection, merged: []u32, action: []u32, gotos: []u32) -> (usize, usize, err) {
    let e = build(g, start, c, true)
    if e != ok { ret (0usize, 0usize, e) }
    let id_error = identity(merged, c.states)
    if id_error != ok { ret (0usize, 0usize, id_error) }
    let (conflicts, fill_error) = fill(g, start, c, merged, c.states, false, action, gotos)
    ret (c.states, conflicts, fill_error)
}

// Every item of `s` has a core (rule, dot) in `t` and back.
fn same_core(c: *const Collection, s: usize, t: usize) -> bool {
    var pass = 0usize
    while pass < 2usize {
        var from = s
        var into = t
        if pass == 1usize {
            from = t
            into = s
        }
        var j = c.set_start[from]
        while j < c.set_start[from + 1usize] {
            var found = false
            var m = c.set_start[into]
            while m < c.set_start[into + 1usize] {
                if c.items[m].rule == c.items[j].rule && c.items[m].dot == c.items[j].dot { found = true }
                m += 1usize
            }
            if !found { ret false }
            j += 1usize
        }
        pass += 1usize
    }
    ret true
}

// LALR(1): the LR(1) collection with equal-core states merged; `merged`
// (`len >= LR(1) states`) receives the state map. Answers (states, conflicts).
fn lalr_table(g: *const base.Grammar, start: u32, c: *Collection, merged: []u32, action: []u32, gotos: []u32) -> (usize, usize, err) {
    let e = build(g, start, c, true)
    if e != ok { ret (0usize, 0usize, e) }
    if merged.len < c.states { ret (0usize, 0usize, TooSmall) }
    var count = 0usize
    var s = 0usize
    while s < c.states {
        var m = NONE
        var t = 0usize
        while t < s && m == NONE {
            if same_core(c, t, s) { m = merged[t] }
            t += 1usize
        }
        if m == NONE {
            m = u32(count)
            count += 1usize
        }
        merged[s] = m
        s += 1usize
    }
    let (conflicts, fill_error) = fill(g, start, c, merged, count, false, action, gotos)
    ret (count, conflicts, fill_error)
}

// Drive ACTION/GOTO over `sentence` (terminal ids); `stack` holds states,
// `out_rules` receives each reduce's rule. Answers the reduce count;
// `Invalid` on a rejected input.
fn parse(g: *const base.Grammar, action: []const u32, gotos: []const u32, sentence: []const u32, stack: []u32, out_rules: []u32) -> (usize, err) {
    if stack.len < 1usize { ret (0usize, TooSmall) }
    let cols = usize(g.terminals) + 1usize
    let nts = ll.symbol_count(g) - usize(g.terminals)
    stack[0usize] = 0u32
    var depth = 1usize
    var i = 0usize
    var n = 0usize
    while true {
        var a = g.terminals
        if i < sentence.len { a = sentence[i] }
        if a > g.terminals { ret (n, Invalid) }
        let act = action[usize(stack[depth - 1usize]) * cols + usize(a)]
        let kind = tag(act)
        if kind == SHIFT {
            if depth >= stack.len { ret (n, TooSmall) }
            stack[depth] = value(act)
            depth += 1usize
            i += 1usize
        } else if kind == REDUCE {
            let rule = usize(value(act))
            let len = base.rule_len(g, rule)
            if len >= depth { ret (n, Invalid) }
            depth -= len
            let to = gotos[usize(stack[depth - 1usize]) * nts + usize(g.lhs[rule]) - usize(g.terminals)]
            if to == NONE { ret (n, Invalid) }
            stack[depth] = to
            depth += 1usize
            if n >= out_rules.len { ret (n, TooSmall) }
            out_rules[n] = u32(rule)
            n += 1usize
        } else if kind == ACCEPT {
            ret (n, ok)
        } else {
            ret (n, Invalid)
        }
    }
    ret (n, ok)
}
