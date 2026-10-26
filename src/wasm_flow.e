// The WebAssembly back end's control flow (C183, D5213): a function's blocks written as
// structured `block`, `loop`, `if` and `br` instead of the dispatch loop, by Ramsey's
// translation ("Beyond Relooper", ICFP 2022). The dominator tree and a reverse postorder
// say where each block's code goes: a loop header opens a `loop`; a block with two or more
// forward predecessors (a merge) is the code that follows a `block` that holds its
// dominator, so a branch to it is a `br` out of that `block`; a block with one forward
// predecessor is written where that predecessor branches to it. A function whose graph is
// not reducible (a retreating edge to a block that does not dominate its source) keeps the
// dispatch loop of wasm_code.e, as does one with a block that does not end in a terminator.
//
// The walk is an explicit stack of actions rather than recursion, since a function may have
// thousands of blocks in a chain.
use e.mem
use nir
use wasm_code as w

const LABEL_LOOP: usize = 1usize
const LABEL_BLOCK: usize = 2usize
const LABEL_IF: usize = 3usize

const ACT_TREE: usize = 1usize
const ACT_WITHIN: usize = 2usize
const ACT_END_BLOCK: usize = 3usize
const ACT_END_LOOP: usize = 4usize
const ACT_END_IF: usize = 5usize
const ACT_BRANCH: usize = 6usize

// Block numbers are inside the function (0 is the entry). `rpo` and `idom` hold the number
// plus one so that zero means unset.
type Flow = struct {
    count: usize,
    first: usize,
    reached: usize,
    cursor: usize,
    rpo: []usize,
    order: []usize,
    idom: []usize,
    header: []usize,
    forward_in: []usize,
    pred_start: []usize,
    pred_list: []usize,
    child_start: []usize,
    fill: []usize,
    child_list: []usize,
    dfs_stack: []usize,
    dfs_edge: []usize,
    post: []usize,
    state: []usize,
    act_kind: []usize,
    act_a: []usize,
    act_b: []usize,
    acts: usize,
    ctx_kind: []usize,
    ctx_key: []usize,
    ctx_depth: usize,
    br_on: bool,
    br_end: usize,
    br_depth: usize,
    why: usize,
}

fn next_array(f: *Flow, words: []usize, size: usize) -> []usize {
    let start = f.cursor
    f.cursor = f.cursor + size
    ret words[start..start + size]
}

fn init_flow(g: *w.Gen, f: *Flow, function: nir.Function) -> err {
    let n = function.block_count
    f.count = n
    f.first = function.first_block
    let (words, words_error) = w.alloc_words(g, 48usize * n + 300usize)
    if words_error != ok { ret words_error }
    f.cursor = 0usize
    f.rpo = next_array(f, words, n + 2usize)
    f.order = next_array(f, words, n + 2usize)
    f.idom = next_array(f, words, n + 2usize)
    f.header = next_array(f, words, n + 2usize)
    f.forward_in = next_array(f, words, n + 2usize)
    f.pred_start = next_array(f, words, n + 2usize)
    f.pred_list = next_array(f, words, 2usize * n + 4usize)
    f.child_start = next_array(f, words, n + 2usize)
    f.fill = next_array(f, words, n + 2usize)
    f.child_list = next_array(f, words, n + 2usize)
    f.dfs_stack = next_array(f, words, n + 2usize)
    f.dfs_edge = next_array(f, words, n + 2usize)
    f.post = next_array(f, words, n + 2usize)
    f.state = next_array(f, words, n + 2usize)
    f.act_kind = next_array(f, words, 8usize * n + 64usize)
    f.act_a = next_array(f, words, 8usize * n + 64usize)
    f.act_b = next_array(f, words, 8usize * n + 64usize)
    f.ctx_kind = next_array(f, words, 4usize * n + 16usize)
    f.ctx_key = next_array(f, words, 4usize * n + 16usize)
    f.acts = 0usize
    f.ctx_depth = 0usize
    f.br_on = false
    f.why = 0usize
    ret ok
}

// ---- the graph -------------------------------------------------------------------

// How many successors `block` has and which: (0, ., .) for a return or a trap, (1, to, .)
// for a branch, (2, if true, if false) for a conditional one, and a count of 3 for a block
// that ends in anything else, or branches out of the function.
fn edges(g: *w.Gen, f: *Flow, block: usize) -> (usize, usize, usize) {
    let record = g.b.blocks[f.first + block]
    if record.instruction_count == 0usize { ret (3usize, 0usize, 0usize) }
    let last = g.b.instructions[record.first_instruction + record.instruction_count - 1usize]
    if last.opcode == .Return || last.opcode == .Trap || last.opcode == .Unreachable { ret (0usize, 0usize, 0usize) }
    if last.opcode == .Branch {
        if last.target < f.first || last.target >= f.first + f.count { ret (3usize, 0usize, 0usize) }
        ret (1usize, last.target - f.first, 0usize)
    }
    if last.opcode == .BranchIf {
        if last.target < f.first || last.target >= f.first + f.count || last.target2 < f.first || last.target2 >= f.first + f.count { ret (3usize, 0usize, 0usize) }
        ret (2usize, last.target - f.first, last.target2 - f.first)
    }
    ret (3usize, 0usize, 0usize)
}

// Postorder from the entry by an explicit walk; the blocks it never reaches are dead.
fn depth_first(g: *w.Gen, f: *Flow) -> bool {
    var depth = 1usize
    f.dfs_stack[0usize] = 0usize
    f.dfs_edge[0usize] = 0usize
    f.state[0usize] = 1usize
    var posted = 0usize
    while depth > 0usize {
        let block = f.dfs_stack[depth - 1usize]
        let k = f.dfs_edge[depth - 1usize]
        let (successors, first, second) = edges(g, f, block)
        if successors == 3usize { ret false }
        if k < successors {
            f.dfs_edge[depth - 1usize] = k + 1usize
            var next = first
            if k == 1usize { next = second }
            if f.state[next] == 0usize {
                f.state[next] = 1usize
                f.dfs_stack[depth] = next
                f.dfs_edge[depth] = 0usize
                depth += 1usize
            }
        } else {
            f.state[block] = 2usize
            f.post[posted] = block
            posted += 1usize
            depth = depth - 1usize
        }
    }
    f.reached = posted
    var at = 0usize
    while at < posted {
        let block = f.post[posted - 1usize - at]
        f.order[at] = block
        f.rpo[block] = at + 1usize
        at += 1usize
    }
    ret true
}

fn build_preds(g: *w.Gen, f: *Flow) {
    var at = 0usize
    while at < f.reached {
        let (successors, first, second) = edges(g, f, f.order[at])
        if successors >= 1usize { f.pred_start[first] += 1usize }
        if successors == 2usize { f.pred_start[second] += 1usize }
        at += 1usize
    }
    var sum = 0usize
    var block = 0usize
    while block < f.count {
        let degree = f.pred_start[block]
        f.pred_start[block] = sum
        f.fill[block] = sum
        sum = sum + degree
        block += 1usize
    }
    f.pred_start[f.count] = sum
    at = 0usize
    while at < f.reached {
        let from = f.order[at]
        let (successors, first, second) = edges(g, f, from)
        if successors >= 1usize {
            f.pred_list[f.fill[first]] = from
            f.fill[first] += 1usize
        }
        if successors == 2usize {
            f.pred_list[f.fill[second]] = from
            f.fill[second] += 1usize
        }
        at += 1usize
    }
}

// The nearest common dominator of two blocks that both have one so far.
fn meet(f: *Flow, left: usize, right: usize) -> usize {
    var x = left
    var y = right
    while x != y {
        while f.rpo[x] > f.rpo[y] { x = f.idom[x] - 1usize }
        while f.rpo[y] > f.rpo[x] { y = f.idom[y] - 1usize }
    }
    ret x
}

// Cooper, Harvey and Kennedy's iteration over the reverse postorder.
fn dominators(f: *Flow) {
    f.idom[0usize] = 1usize
    var changed = true
    while changed {
        changed = false
        var at = 1usize
        while at < f.reached {
            let block = f.order[at]
            var chosen = 0usize
            var p = f.pred_start[block]
            while p < f.pred_start[block + 1usize] {
                let pred = f.pred_list[p]
                if f.idom[pred] != 0usize {
                    if chosen == 0usize {
                        chosen = pred + 1usize
                    } else {
                        chosen = meet(f, chosen - 1usize, pred) + 1usize
                    }
                }
                p += 1usize
            }
            if chosen != f.idom[block] {
                f.idom[block] = chosen
                changed = true
            }
            at += 1usize
        }
    }
}

// A retreating edge has to go to a block that dominates its source; then the graph is
// reducible. Marks the loop headers and counts each block's forward edges.
fn classify(g: *w.Gen, f: *Flow) -> bool {
    var at = 0usize
    while at < f.reached {
        let from = f.order[at]
        let (successors, first, second) = edges(g, f, from)
        var k = 0usize
        while k < successors {
            var to = first
            if k == 1usize { to = second }
            if f.rpo[to] <= f.rpo[from] {
                var x = from
                while f.rpo[x] > f.rpo[to] { x = f.idom[x] - 1usize }
                if x != to { ret false }
                f.header[to] = 1usize
            } else {
                f.forward_in[to] += 1usize
            }
            k += 1usize
        }
        at += 1usize
    }
    ret true
}

// Each block's dominator-tree children that are merges, in reverse postorder.
fn build_children(f: *Flow) {
    var at = 1usize
    while at < f.reached {
        let block = f.order[at]
        if f.forward_in[block] >= 2usize { f.child_start[f.idom[block] - 1usize] += 1usize }
        at += 1usize
    }
    var sum = 0usize
    var block_at = 0usize
    while block_at < f.count {
        let degree = f.child_start[block_at]
        f.child_start[block_at] = sum
        f.fill[block_at] = sum
        sum = sum + degree
        block_at += 1usize
    }
    f.child_start[f.count] = sum
    at = 1usize
    while at < f.reached {
        let block = f.order[at]
        if f.forward_in[block] >= 2usize {
            let parent = f.idom[block] - 1usize
            f.child_list[f.fill[parent]] = block
            f.fill[parent] += 1usize
        }
        at += 1usize
    }
}

fn analyze(g: *w.Gen, f: *Flow) -> bool {
    if !depth_first(g, f) {
        f.why = 2usize
        ret false
    }
    build_preds(g, f)
    dominators(f)
    if !classify(g, f) {
        f.why = 1usize
        ret false
    }
    build_children(f)
    ret true
}

// ---- the translation -------------------------------------------------------------

fn push_action(g: *w.Gen, f: *Flow, kind: usize, a: usize, b: usize) -> err {
    if f.acts >= f.act_kind.len { ret w.fail(g, "the structured walk outgrew its stack") }
    f.act_kind[f.acts] = kind
    f.act_a[f.acts] = a
    f.act_b[f.acts] = b
    f.acts += 1usize
    ret ok
}

fn push_label(f: *Flow, kind: usize, key: usize) {
    f.ctx_kind[f.ctx_depth] = kind
    f.ctx_key[f.ctx_depth] = key
    f.ctx_depth += 1usize
}

// How many labels out the nearest enclosing one of this kind and key is.
fn label_depth(f: *Flow, kind: usize, key: usize) -> usize {
    var at = f.ctx_depth
    while at > 0usize {
        at = at - 1usize
        if f.ctx_kind[at] == kind && f.ctx_key[at] == key { ret f.ctx_depth - 1usize - at }
    }
    ret f.ctx_depth
}

// Whether the edge is a `br`: a retreating edge to a loop header, or an edge to a merge.
fn jumps(f: *Flow, from: usize, to: usize) -> bool {
    ret f.rpo[to] <= f.rpo[from] || f.forward_in[to] >= 2usize
}

fn jump_depth(f: *Flow, from: usize, to: usize) -> usize {
    if f.rpo[to] <= f.rpo[from] { ret label_depth(f, LABEL_LOOP, to) }
    ret label_depth(f, LABEL_BLOCK, to)
}

fn emit_br(g: *w.Gen, f: *Flow, depth: usize) {
    w.op(g, 12usize)
    w.put_uleb(&g.code, depth)
    f.br_on = true
    f.br_end = g.code.count
    f.br_depth = depth
}

fn emit_br_if(g: *w.Gen, depth: usize) {
    w.op(g, 13usize)
    w.put_uleb(&g.code, depth)
}

// A `br 0` that ends a `block` or an `if` goes to the end that follows it anyway.
fn drop_trailing_br(g: *w.Gen, f: *Flow) {
    if f.br_on && f.br_end == g.code.count && f.br_depth == 0usize { g.code.count = g.code.count - 2usize }
    f.br_on = false
}

fn close_label(g: *w.Gen, f: *Flow) {
    w.block_end(g)
    f.ctx_depth = f.ctx_depth - 1usize
}

fn emit_node(g: *w.Gen, f: *Flow, function: nir.Function, x: usize) -> err {
    let block = g.b.blocks[f.first + x]
    let last_at = block.first_instruction + block.instruction_count - 1usize
    g.fr_block = x
    g.current = function
    var at = block.first_instruction
    while at < last_at {
        try w.emit_folded(g, g.b.instructions[at], at, 0usize)
        at += 1usize
    }
    let last = g.b.instructions[last_at]
    if last.opcode == .Branch {
        if g.fold_count != 0usize { ret w.fail(g, "a value was left on the operand stack at the end of its block") }
        ret push_action(g, f, ACT_BRANCH, last.target - f.first, x)
    }
    if last.opcode != .BranchIf {
        try w.emit_folded(g, last, last_at, 0usize)
        if g.fold_count != 0usize { ret w.fail(g, "a value was left on the operand stack at the end of its block") }
        ret ok
    }
    try w.emit_folded(g, last, last_at, 1usize)
    if g.fold_count != 0usize { ret w.fail(g, "a value was left on the operand stack at the end of its block") }
    let on_true = last.target - f.first
    let on_false = last.target2 - f.first
    if jumps(f, x, on_true) {
        emit_br_if(g, jump_depth(f, x, on_true))
        ret push_action(g, f, ACT_BRANCH, on_false, x)
    }
    if jumps(f, x, on_false) {
        w.op(g, 69usize)
        emit_br_if(g, jump_depth(f, x, on_false))
        ret push_action(g, f, ACT_BRANCH, on_true, x)
    }
    // Both arms are written inline. The true arm never falls out of its `if`, since every
    // path of a translated block ends in a branch, a return or a trap, so the false arm
    // can follow the `end` instead of nesting in an `else`.
    w.block_if(g)
    push_label(f, LABEL_IF, 0usize)
    try push_action(g, f, ACT_BRANCH, on_false, x)
    try push_action(g, f, ACT_END_IF, 0usize, 0usize)
    ret push_action(g, f, ACT_BRANCH, on_true, x)
}

fn step_tree(g: *w.Gen, f: *Flow, x: usize) -> err {
    if f.header[x] == 1usize {
        w.op(g, 3usize)
        w.op(g, 64usize)
        push_label(f, LABEL_LOOP, x)
        try push_action(g, f, ACT_END_LOOP, 0usize, 0usize)
    }
    ret push_action(g, f, ACT_WITHIN, x, 0usize)
}

// The merge children of `x`, the one with the highest reverse postorder number outermost:
// `block { within(x, k + 1) }` and then that child's own tree.
fn step_within(g: *w.Gen, f: *Flow, function: nir.Function, x: usize, k: usize) -> err {
    let merges = f.child_start[x + 1usize] - f.child_start[x]
    if k >= merges { ret emit_node(g, f, function, x) }
    let y = f.child_list[f.child_start[x] + (merges - 1usize - k)]
    w.op(g, 2usize)
    w.op(g, 64usize)
    push_label(f, LABEL_BLOCK, y)
    try push_action(g, f, ACT_TREE, y, 0usize)
    try push_action(g, f, ACT_END_BLOCK, 0usize, 0usize)
    ret push_action(g, f, ACT_WITHIN, x, k + 1usize)
}

fn step_branch(g: *w.Gen, f: *Flow, to: usize, from: usize) -> err {
    if jumps(f, from, to) {
        emit_br(g, f, jump_depth(f, from, to))
        ret ok
    }
    ret push_action(g, f, ACT_TREE, to, 0usize)
}

fn emit_structured(g: *w.Gen, f: *Flow, function: nir.Function) -> err {
    try push_action(g, f, ACT_TREE, 0usize, 0usize)
    while f.acts > 0usize {
        f.acts = f.acts - 1usize
        let kind = f.act_kind[f.acts]
        let a = f.act_a[f.acts]
        let b = f.act_b[f.acts]
        if ACT_TREE == kind { try step_tree(g, f, a) }
        if ACT_WITHIN == kind { try step_within(g, f, function, a, b) }
        if ACT_BRANCH == kind { try step_branch(g, f, a, b) }
        if ACT_END_BLOCK == kind || ACT_END_IF == kind {
            drop_trailing_br(g, f)
            close_label(g, f)
        }
        if ACT_END_LOOP == kind {
            f.br_on = false
            close_label(g, f)
        }
    }
    ret ok
}

// ---- a function --------------------------------------------------------------------

fn note_dispatch(g: *w.Gen, f: *Flow, function: nir.Function) {
    g.dispatch_count += 1usize
    if f.why == 1usize { g.irreducible_count += 1usize }
    if g.dispatch_count > 20usize { ret }
    w.put_text(&g.stats, "dispatch ")
    w.put_text(&g.stats, function.module_name)
    w.put_text(&g.stats, ".")
    w.put_text(&g.stats, function.name)
    w.put_text(&g.stats, " (")
    if f.why == 1usize { w.put_text(&g.stats, "irreducible") }
    if f.why == 2usize { w.put_text(&g.stats, "a block that does not end in a branch, return or trap") }
    if f.why == 0usize { w.put_text(&g.stats, "asked for") }
    w.put_text(&g.stats, ", ")
    w.put_decimal(&g.stats, function.block_count)
    w.put_text(&g.stats, " blocks)\n")
}

// The body of `function_index`: its locals, prologue and blocks, appended to the code
// section with its size.
fn emit_function(g: *w.Gen, function_index: usize) -> err {
    let mark = mem.mark(g.a)
    var f: Flow = zero
    try w.begin_function(g, function_index)
    let function = g.b.functions[function_index]
    try init_flow(g, &f, function)
    if !g.force_dispatch && function.block_count != 0usize && analyze(g, &f) {
        try emit_structured(g, &f, function)
        g.structured_count += 1usize
    } else {
        note_dispatch(g, &f, function)
        try w.emit_blocks(g, function)
    }
    try w.finish_function(g)
    mem.reset(g.a, mark)
    ret ok
}
