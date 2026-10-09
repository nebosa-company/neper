// `e.algo.schedule.dependency_order` (Kahn with an id tie-break, `target[...]` set matching, and refusals) against
// scripts/dependency_order_reference.py, a literal Python transcription of petcow's `topo_order`: the six hand
// cases of petcow's tests (linear chain, diamond, nodes without dependencies sorted by id, a cycle, an unknown
// dependency, a `for_each` set) and a few hundred seeded random graphs -- some acyclic, some with cycles, unknown
// targets, self references, repeated dependencies and duplicate ids -- each with the reference's order or refusal.
// A line is `G <node> <node> ... = <result>`; a node is `id:dep,dep`; the result is `O i i i` (the order), `U node
// dep` (unknown dependency), `S node dep` (self dependency) or `C i i i` (the stuck nodes of a cycle).
use e.algo.schedule
use e.io
use e.mem
use e.os

// The text of a line is split on spaces into tokens held as slices of the line.
fn next_token(line: str, at: usize) -> (str, usize) {
    var p = at
    while p < line.len && line[p] == 32u8 { p += 1usize }
    let start = p
    while p < line.len && line[p] != 32u8 { p += 1usize }
    ret (line[start..p], p)
}

fn number(token: str) -> usize {
    var v = 0usize
    var i = 0usize
    while i < token.len {
        v = v * 10usize + usize(token[i] - 48u8)
        i += 1usize
    }
    ret v
}

fn same_text(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

// One line; 0 when the library agrees with it.
fn check(a: *mem.Arena, line: str) -> u8 {
    var nodes: [16]schedule.DependencyNode = zero
    var pool: [96]str = zero
    var pooled = 0usize
    var count = 0usize
    var at = 2usize
    var done = false
    while !done {
        let (token, after) = next_token(line, at)
        at = after
        if same_text(token, "=") {
            done = true
        } else {
            // id:dep,dep
            var colon = 0usize
            while token[colon] != 58u8 { colon += 1usize }
            let first = pooled
            var p = colon + 1usize
            while p < token.len {
                var q = p
                while q < token.len && token[q] != 44u8 { q += 1usize }
                pool[pooled] = token[p..q]
                pooled += 1usize
                p = q + 1usize
            }
            nodes[count] = schedule.DependencyNode { id: token[0usize..colon], depends_on: pool[first..pooled] }
            count += 1usize
        }
    }
    let (kind, after_kind) = next_token(line, at)
    var rest = after_kind
    let mark = mem.mark(a)
    let (result, e) = schedule.dependency_order(a, nodes[0usize..count])
    var verdict = 0u8
    if same_text(kind, "O") {
        if e != ok { verdict = 1u8 } else if result.order.len != count { verdict = 2u8 } else {
            var i = 0usize
            while i < count {
                let (token, after) = next_token(line, rest)
                rest = after
                if result.order[i] != number(token) { verdict = 3u8 }
                i += 1usize
            }
        }
    } else if same_text(kind, "U") || same_text(kind, "S") {
        let (node_token, after_node) = next_token(line, rest)
        let (dep_token, after_dep) = next_token(line, after_node)
        var want = schedule.UnknownDependency
        if same_text(kind, "S") { want = schedule.SelfDependency }
        if e != want { verdict = 4u8 } else if result.node != number(node_token) || result.dep != number(dep_token) { verdict = 5u8 } else if result.order.len != 0usize { verdict = 6u8 }
    } else {
        if e != schedule.Cycle { verdict = 7u8 } else {
            var i = 0usize
            var more = true
            while more {
                let (token, after) = next_token(line, rest)
                rest = after
                if token.len == 0usize {
                    more = false
                } else {
                    if i >= result.stuck.len || result.stuck[i] != number(token) { verdict = 8u8 }
                    i += 1usize
                }
            }
            if i != result.stuck.len { verdict = 9u8 }
            if result.order.len != 0usize { verdict = 10u8 }
        }
    }
    mem.reset(a, mark)
    ret verdict
}

fn run(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let verdict = check(a, text[start..i])
            if verdict != 0u8 { ret 20u8 + verdict }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    // An empty graph has the empty order.
    let none: []schedule.DependencyNode = zero
    let (empty, empty_error) = schedule.dependency_order(a, none)
    if empty_error != ok || empty.order.len != 0usize { os.exit(1i32) }
    //__VECTOR_CALLS__
    try io.print("algo schedule dependency order ok")
    ret ok
}
