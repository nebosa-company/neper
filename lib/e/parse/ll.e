// LL(1) over an `e.parse.Grammar` in caller storage: `nullable`, `first` and
// `follow` are the fixed-point sets (per-symbol bitsets of terminals, so
// terminals stay below 63; the end marker `$` is terminal id `g.terminals`
// and sits in `follow` and in the table's last column), `table` fills the
// predictive table `[non-terminal][terminal or $] -> rule` reporting the
// conflict count (0 means LL(1); a conflicting cell keeps the lowest rule),
// and `parse` drives it, answering the leftmost derivation as rule indices.
// The symbol count is `nullable.len` (`first_sets.len`, `follow_sets.len`):
// every symbol id, terminal or not, is below it.

use e.parse as base

error TooSmall
error Invalid

const NONE: u32 = 4294967295u32

// Bit `t` of the mask holds terminal `t`; bit `g.terminals` holds `$`.
fn bit(t: u32) -> u64 { ret 1u64 << t }

fn max_symbol(g: *const base.Grammar) -> usize {
    var n = usize(g.terminals)
    var i = 0usize
    while i < g.lhs.len {
        if usize(g.lhs[i]) + 1usize > n { n = usize(g.lhs[i]) + 1usize }
        i += 1usize
    }
    i = 0usize
    while i < g.rhs.len {
        if usize(g.rhs[i]) + 1usize > n { n = usize(g.rhs[i]) + 1usize }
        i += 1usize
    }
    ret n
}

// The number of symbols the grammar mentions (terminals included).
fn symbol_count(g: *const base.Grammar) -> usize { ret max_symbol(g) }

// `out[s]` is true when non-terminal `s` derives the empty string.
fn nullable(g: *const base.Grammar, out: []bool) -> err {
    if out.len < max_symbol(g) || g.terminals > 63u32 { ret Invalid }
    var s = 0usize
    while s < out.len {
        out[s] = false
        s += 1usize
    }
    let rules = base.rule_count(g)
    var changed = true
    while changed {
        changed = false
        var r = 0usize
        while r < rules {
            if !out[usize(g.lhs[r])] {
                var all = true
                var k = 0usize
                while k < base.rule_len(g, r) {
                    if !out[usize(base.rule_symbol(g, r, k))] { all = false }
                    k += 1usize
                }
                if all {
                    out[usize(g.lhs[r])] = true
                    changed = true
                }
            }
            r += 1usize
        }
    }
    ret ok
}

// FIRST of `rhs[from..]` of `rule`: (the terminal mask, whether every
// symbol of the range is nullable).
fn first_of(g: *const base.Grammar, nullable_set: []const bool, first_sets: []const u64, rule: usize, from: usize) -> (u64, bool) {
    var mask = 0u64
    var k = from
    while k < base.rule_len(g, rule) {
        let s = usize(base.rule_symbol(g, rule, k))
        mask |= first_sets[s]
        if !nullable_set[s] { ret (mask, false) }
        k += 1usize
    }
    ret (mask, true)
}

// `first_sets[s]` is the mask of terminals that may begin a sentence of `s`
// (a terminal's set is itself).
fn first(g: *const base.Grammar, nullable_set: []const bool, first_sets: []u64) -> err {
    if first_sets.len < nullable_set.len { ret TooSmall }
    var s = 0usize
    while s < first_sets.len {
        first_sets[s] = 0u64
        if s < usize(g.terminals) { first_sets[s] = bit(u32(s)) }
        s += 1usize
    }
    let rules = base.rule_count(g)
    var changed = true
    while changed {
        changed = false
        var r = 0usize
        while r < rules {
            let (mask, _) = first_of(g, nullable_set, first_sets, r, 0usize)
            let lhs = usize(g.lhs[r])
            if (first_sets[lhs] | mask) != first_sets[lhs] {
                first_sets[lhs] |= mask
                changed = true
            }
            r += 1usize
        }
    }
    ret ok
}

// `follow_sets[s]` is the mask of terminals (and `$`) that may follow
// non-terminal `s` in a sentential form of `start`.
fn follow(g: *const base.Grammar, start: u32, nullable_set: []const bool, first_sets: []const u64, follow_sets: []u64) -> err {
    if follow_sets.len < nullable_set.len { ret TooSmall }
    var s = 0usize
    while s < follow_sets.len {
        follow_sets[s] = 0u64
        s += 1usize
    }
    follow_sets[usize(start)] = bit(g.terminals)
    let rules = base.rule_count(g)
    var changed = true
    while changed {
        changed = false
        var r = 0usize
        while r < rules {
            var k = 0usize
            while k < base.rule_len(g, r) {
                let sym = usize(base.rule_symbol(g, r, k))
                if sym >= usize(g.terminals) {
                    var (mask, all) = first_of(g, nullable_set, first_sets, r, k + 1usize)
                    if all { mask |= follow_sets[usize(g.lhs[r])] }
                    if (follow_sets[sym] | mask) != follow_sets[sym] {
                        follow_sets[sym] |= mask
                        changed = true
                    }
                }
                k += 1usize
            }
            r += 1usize
        }
    }
    ret ok
}

// Fill `out[(A - terminals) * (terminals + 1) + a]` with the rule to apply
// on non-terminal `A` seeing terminal `a` (`a == terminals` is `$`), `NONE`
// where none; computes the three sets into the scratch arrays on the way.
// Answers the conflict count.
fn table(g: *const base.Grammar, start: u32, nullable_set: []bool, first_sets: []u64, follow_sets: []u64, out: []u32) -> (usize, err) {
    let e = nullable(g, nullable_set)
    if e != ok { ret (0usize, e) }
    let first_error = first(g, nullable_set, first_sets)
    if first_error != ok { ret (0usize, first_error) }
    let follow_error = follow(g, start, nullable_set, first_sets, follow_sets)
    if follow_error != ok { ret (0usize, follow_error) }
    let cols = usize(g.terminals) + 1usize
    let cells = (nullable_set.len - usize(g.terminals)) * cols
    if out.len < cells { ret (0usize, TooSmall) }
    var i = 0usize
    while i < cells {
        out[i] = NONE
        i += 1usize
    }
    var conflicts = 0usize
    let rules = base.rule_count(g)
    var r = 0usize
    while r < rules {
        var (mask, all) = first_of(g, nullable_set, first_sets, r, 0usize)
        if all { mask |= follow_sets[usize(g.lhs[r])] }
        var a = 0usize
        while a < cols {
            if ((mask >> u32(a)) & 1u64) == 1u64 {
                let cell = (usize(g.lhs[r]) - usize(g.terminals)) * cols + a
                if out[cell] == NONE {
                    out[cell] = u32(r)
                } else if out[cell] != u32(r) {
                    conflicts += 1usize
                }
            }
            a += 1usize
        }
        r += 1usize
    }
    ret (conflicts, ok)
}

// Parse `sentence` (terminal ids) from `start` with `tbl` from `table`;
// `stack` holds the pending symbols, `out_rules` receives the rules applied
// in leftmost order. Answers the rule count; `Invalid` on a rejected input.
fn parse(g: *const base.Grammar, start: u32, tbl: []const u32, sentence: []const u32, stack: []u32, out_rules: []u32) -> (usize, err) {
    if stack.len < 2usize { ret (0usize, TooSmall) }
    let cols = usize(g.terminals) + 1usize
    stack[0usize] = NONE
    stack[1usize] = start
    var depth = 2usize
    var i = 0usize
    var n = 0usize
    while true {
        depth -= 1usize
        let top = stack[depth]
        var a = g.terminals
        if i < sentence.len { a = sentence[i] }
        if a > g.terminals { ret (n, Invalid) }
        if top == NONE {
            if i != sentence.len { ret (n, Invalid) }
            ret (n, ok)
        }
        if top < g.terminals {
            if top != a { ret (n, Invalid) }
            i += 1usize
            continue
        }
        let r = tbl[(usize(top) - usize(g.terminals)) * cols + usize(a)]
        if r == NONE { ret (n, Invalid) }
        if n >= out_rules.len { ret (n, TooSmall) }
        out_rules[n] = r
        n += 1usize
        let len = base.rule_len(g, usize(r))
        if depth + len > stack.len { ret (n, TooSmall) }
        var k = len
        while k > 0usize {
            k -= 1usize
            stack[depth] = base.rule_symbol(g, usize(r), k)
            depth += 1usize
        }
    }
    ret (n, ok)
}
