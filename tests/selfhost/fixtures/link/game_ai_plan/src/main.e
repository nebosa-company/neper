// `e.game.ai` game-tree search, MCTS, behaviour trees, GOAP, utility AI and boids. Every
// expected value comes from scratchpad/game_ai_plan/ref.py, an integer-exact replica.

use e.game.ai
use e.math.fixed
use e.algo.rand
use e.io
use e.mem
use e.os

// --- tic-tac-toe over a stack pool of states ------------------------------------------
type Ttt = struct { cells: []u8, side: []u8, top: usize, zob: []u64, lines: []u8 }

fn ttt_moves(t: *Ttt, s: u32, out: []u32) -> usize {
    let base = usize(s) * 9usize
    var n = 0usize
    var i = 0usize
    while i < 9usize {
        if t.cells[base + i] == 0u8 && n < out.len {
            out[n] = u32(i)
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

fn ttt_apply(t: *Ttt, s: u32, m: u32) -> u32 {
    let id = u32(t.top)
    let src = usize(s) * 9usize
    let dst = t.top * 9usize
    var i = 0usize
    while i < 9usize {
        t.cells[dst + i] = t.cells[src + i]
        i += 1usize
    }
    t.cells[dst + usize(m)] = t.side[usize(s)]
    t.side[t.top] = 3u8 - t.side[usize(s)]
    t.top += 1usize
    ret id
}

fn ttt_release(t: *Ttt, s: u32) {
    t.top = usize(s)
}

fn ttt_winner(t: *Ttt, s: u32) -> u8 {
    let base = usize(s) * 9usize
    var l = 0usize
    while l < 8usize {
        let a = t.cells[base + usize(t.lines[l * 3usize])]
        let b = t.cells[base + usize(t.lines[l * 3usize + 1usize])]
        let c = t.cells[base + usize(t.lines[l * 3usize + 2usize])]
        if a != 0u8 && a == b && b == c { ret a }
        l += 1usize
    }
    ret 0u8
}

fn ttt_terminal(t: *Ttt, s: u32) -> bool {
    if ttt_winner(t, s) != 0u8 { ret true }
    let base = usize(s) * 9usize
    var i = 0usize
    while i < 9usize {
        if t.cells[base + i] == 0u8 { ret false }
        i += 1usize
    }
    ret true
}

fn ttt_evaluate(t: *Ttt, s: u32) -> i32 {
    let w = ttt_winner(t, s)
    if w == 0u8 { ret 0i32 }
    if w == t.side[usize(s)] { ret 100i32 }
    ret -100i32
}

fn ttt_capture(t: *Ttt, s: u32, m: u32) -> bool {
    ret false
}

fn ttt_chance(t: *Ttt, s: u32, out: []u32, weights: []i32) -> usize {
    ret 0usize
}

fn ttt_zobrist(t: *Ttt, s: u32) -> u64 {
    let base = usize(s) * 9usize
    var h = 0u64
    var i = 0usize
    while i < 9usize {
        let p = t.cells[base + i]
        if p != 0u8 { h = h ^ t.zob[i * 2usize + usize(p) - 1usize] }
        i += 1usize
    }
    ret h
}

// --- capture game: take items; taking one worth 3 or more is a capture -------------------
type Cap = struct { mask: []u32, mine: []i32, theirs: []i32, top: usize, values: []i32 }

fn cap_moves(c: *Cap, s: u32, out: []u32) -> usize {
    var n = 0usize
    var i = 0usize
    while i < c.values.len {
        if (c.mask[usize(s)] & (1u32 << u32(i))) != 0u32 && n < out.len {
            out[n] = u32(i)
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

fn cap_apply(c: *Cap, s: u32, m: u32) -> u32 {
    let id = u32(c.top)
    c.mask[c.top] = c.mask[usize(s)] & ~(1u32 << m)
    c.mine[c.top] = c.theirs[usize(s)]
    c.theirs[c.top] = c.mine[usize(s)] + c.values[usize(m)]
    c.top += 1usize
    ret id
}

fn cap_release(c: *Cap, s: u32) {
    c.top = usize(s)
}

fn cap_terminal(c: *Cap, s: u32) -> bool {
    ret c.mask[usize(s)] == 0u32
}

fn cap_evaluate(c: *Cap, s: u32) -> i32 {
    ret c.mine[usize(s)] - c.theirs[usize(s)]
}

fn cap_capture(c: *Cap, s: u32, m: u32) -> bool {
    ret c.values[usize(m)] >= 3i32
}

fn cap_chance(c: *Cap, s: u32, out: []u32, weights: []i32) -> usize {
    ret 0usize
}

fn cap_zobrist(c: *Cap, s: u32) -> u64 {
    ret 0u64
}

// --- dice game: roll (chance, weights 1:2:1), then bank the roll or steal it --------------
type Dice = struct { me: []i32, opp: []i32, roll: []i32, turns: []i32, top: usize }

fn dice_moves(d: *Dice, s: u32, out: []u32) -> usize {
    out[0usize] = 0u32
    out[1usize] = 1u32
    ret 2usize
}

fn dice_push(d: *Dice, me: i32, opp: i32, roll: i32, turns: i32) -> u32 {
    let id = u32(d.top)
    d.me[d.top] = me
    d.opp[d.top] = opp
    d.roll[d.top] = roll
    d.turns[d.top] = turns
    d.top += 1usize
    ret id
}

fn dice_apply(d: *Dice, s: u32, m: u32) -> u32 {
    let i = usize(s)
    if m == 0u32 { ret dice_push(d, d.opp[i], d.me[i] + d.roll[i], 0i32, d.turns[i] - 1i32) }
    ret dice_push(d, d.opp[i] - d.roll[i], d.me[i] + 1i32, 0i32, d.turns[i] - 1i32)
}

fn dice_release(d: *Dice, s: u32) {
    d.top = usize(s)
}

fn dice_terminal(d: *Dice, s: u32) -> bool {
    ret d.turns[usize(s)] == 0i32
}

fn dice_evaluate(d: *Dice, s: u32) -> i32 {
    ret d.me[usize(s)] - d.opp[usize(s)]
}

fn dice_capture(d: *Dice, s: u32, m: u32) -> bool {
    ret false
}

fn dice_chance(d: *Dice, s: u32, out: []u32, weights: []i32) -> usize {
    let i = usize(s)
    if d.roll[i] != 0i32 || d.turns[i] == 0i32 { ret 0usize }
    out[0usize] = dice_push(d, d.me[i], d.opp[i], 1i32, d.turns[i])
    out[1usize] = dice_push(d, d.me[i], d.opp[i], 2i32, d.turns[i])
    out[2usize] = dice_push(d, d.me[i], d.opp[i], 3i32, d.turns[i])
    weights[0usize] = 1i32
    weights[1usize] = 2i32
    weights[2usize] = 1i32
    ret 3usize
}

fn dice_zobrist(d: *Dice, s: u32) -> u64 {
    ret 0u64
}

// --- behaviour tree leaves scripted per id --------------------------------------------------
type BtCtx = struct { script: []u8, offsets: []usize, lengths: []usize, calls: []usize }

fn bt_leaf(c: *BtCtx, id: u16) -> ai.Status {
    let i = usize(id)
    let v = c.script[c.offsets[i] + c.calls[i] % c.lengths[i]]
    c.calls[i] = c.calls[i] + 1usize
    if v == 0u8 { ret .Running }
    if v == 1u8 { ret .Success }
    ret .Failure
}

fn code(s: ai.Status) -> u8 {
    if s == .Running { ret 0u8 }
    if s == .Success { ret 1u8 }
    ret 2u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    // --- tic-tac-toe searches ------------------------------------------------------------
    var cells: [2700]u8 = zero
    var side: [300]u8 = zero
    var zob: [18]u64 = zero
    var lines = [24]u8{ 0u8, 1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 0u8, 3u8, 6u8, 1u8, 4u8, 7u8, 2u8, 5u8, 8u8, 0u8, 4u8, 8u8, 2u8, 4u8, 6u8 }
    var z = 12345u64
    var i = 0usize
    while i < 18usize {
        z = z *% 6364136223846793005u64 +% 1442695040888963407u64
        zob[i] = z
        i += 1usize
    }
    var t = Ttt { cells: cells[..], side: side[..], top: 1usize, zob: zob[..], lines: lines[..] }
    // X at 5, O at 6, X to move: the only winning move is 8.
    cells[5usize] = 1u8
    cells[6usize] = 2u8
    side[0usize] = 1u8
    let g = ai.Game[Ttt] { ctx: &t, moves: ttt_moves, apply: ttt_apply, release: ttt_release, evaluate: ttt_evaluate, is_terminal: ttt_terminal, is_capture: ttt_capture, chance_outcomes: ttt_chance, zobrist: ttt_zobrist }
    var move_slab: [128]u32 = zero
    var weight_slab: [128]i32 = zero
    var entries: [64]ai.TtEntry = zero
    var s = ai.Search { moves: move_slab[..], weights: weight_slab[..], max_moves: 9usize, nodes: 0u64, budget: 0u64, aborted: false, overflow: false, best: ai.NONE, tt: ai.Tt { entries: entries[0usize..0usize] } }

    let (mm_value, mm_move, mm_error) = ai.minimax[Ttt](&g, &s, 0u32, 9u32)
    if mm_error != ok || mm_value != 100i32 || mm_move != 8u32 { os.exit(1i32) }
    if s.nodes != 6900u64 || t.top != 1usize { os.exit(2i32) }
    let (ab_value, ab_move, ab_error) = ai.alpha_beta[Ttt](&g, &s, 0u32, 9u32)
    if ab_error != ok || ab_value != 100i32 || ab_move != 8u32 { os.exit(3i32) }
    if s.nodes != 1260u64 { os.exit(4i32) }
    let (pv_value, pv_move, pv_error) = ai.pvs[Ttt](&g, &s, 0u32, 9u32)
    if pv_error != ok || pv_value != 100i32 || pv_move != 8u32 { os.exit(5i32) }
    if s.nodes != 1248u64 { os.exit(6i32) }

    s.tt = ai.transposition_table(entries[..])
    let (id_value, id_move, id_depth, id_error) = ai.iterative_deepening[Ttt](&g, &s, 0u32, 9u32, 0u64)
    if id_error != ok || id_value != 100i32 || id_move != 8u32 || id_depth != 9u32 { os.exit(7i32) }
    if s.nodes != 1940u64 || t.top != 1usize { os.exit(8i32) }
    // The table remembers the root.
    let (root_entry, root_hit) = ai.tt_probe(&s.tt, ttt_zobrist(&t, 0u32))
    if !root_hit || root_entry.best != 8u32 || root_entry.depth != 9u32 { os.exit(9i32) }
    // A budget of 40 nodes finishes depth 2 and no more.
    s.tt = ai.transposition_table(entries[..])
    let (b_value, b_move, b_depth, b_error) = ai.iterative_deepening[Ttt](&g, &s, 0u32, 9u32, 40u64)
    if b_error != ok || b_value != 0i32 || b_move != 0u32 || b_depth != 2u32 { os.exit(10i32) }
    if s.nodes != 41u64 { os.exit(11i32) }
    // Too small for even depth 1 is a Budget error.
    s.tt = ai.transposition_table(entries[..])
    let (n_value, n_move, n_depth, n_error) = ai.iterative_deepening[Ttt](&g, &s, 0u32, 9u32, 5u64)
    if n_error != ai.Budget || n_depth != 0u32 { os.exit(12i32) }
    s.budget = 0u64
    s.tt = ai.Tt { entries: entries[0usize..0usize] }

    // Depth-limited from the empty board: the horizon is respected.
    cells[5usize] = 0u8
    cells[6usize] = 0u8
    let (e_value, e_move, e_error) = ai.minimax[Ttt](&g, &s, 0u32, 2u32)
    if e_error != ok || e_value != 0i32 || e_move != 0u32 || s.nodes != 82u64 { os.exit(13i32) }
    // A slab too small for the depth is a Size error, not a read past the end.
    s.max_moves = 9usize
    s.moves = move_slab[0usize..18usize]
    let (o_value, o_move, o_error) = ai.minimax[Ttt](&g, &s, 0u32, 3u32)
    if o_error != ai.Size { os.exit(14i32) }
    s.moves = move_slab[..]
    cells[5usize] = 1u8
    cells[6usize] = 2u8

    // --- MCTS: visit counts equal the replica after 200 iterations --------------------------
    var nodes: [256]ai.MctsNode = zero
    var mcts_moves: [9]u32 = zero
    var rollout: [9]u32 = zero
    var m = ai.Mcts { nodes: nodes[..], count: 0usize, moves: mcts_moves[..], rollout: rollout[..], c: 92682i32 }
    var r = rand.pcg64(42u64, 7u64)
    let (mc_move, mc_error) = ai.mcts[Ttt](&g, &m, 0u32, 200u32, &r)
    if mc_error != ok || mc_move != 8u32 { os.exit(15i32) }
    if m.count != 171usize || t.top != 1usize { os.exit(16i32) }
    if r.state != 3761979179459714833u64 { os.exit(17i32) }
    if nodes[0usize].visits != 200u32 { os.exit(18i32) }
    var visits = [7]u32{ 17u32, 6u32, 30u32, 13u32, 30u32, 4u32, 100u32 }
    var wins = [7]i32{ -2i32, -4i32, 4i32, -3i32, 4i32, -4i32, 46i32 }
    var child_moves = [7]u32{ 0u32, 1u32, 2u32, 3u32, 4u32, 7u32, 8u32 }
    i = 0usize
    while i < 7usize {
        let child = nodes[1usize + i]
        if child.move != child_moves[i] || child.visits != visits[i] || child.wins != wins[i] { os.exit(19i32) }
        i += 1usize
    }
    // A pool too small for the tree is a Size error.
    m.nodes = nodes[0usize..8usize]
    let (small_move, small_error) = ai.mcts[Ttt](&g, &m, 0u32, 200u32, &r)
    if small_error != ai.Size || t.top != 1usize { os.exit(20i32) }

    // --- quiescence on the capture game -------------------------------------------------------
    var masks: [16]u32 = zero
    var mine: [16]i32 = zero
    var theirs: [16]i32 = zero
    var values = [6]i32{ 1i32, 4i32, 2i32, 5i32, 3i32, 1i32 }
    var c = Cap { mask: masks[..], mine: mine[..], theirs: theirs[..], top: 1usize, values: values[..] }
    masks[0usize] = 63u32
    let cg = ai.Game[Cap] { ctx: &c, moves: cap_moves, apply: cap_apply, release: cap_release, evaluate: cap_evaluate, is_terminal: cap_terminal, is_capture: cap_capture, chance_outcomes: cap_chance, zobrist: cap_zobrist }
    let (c1_value, c1_move, c1_error) = ai.alpha_beta[Cap](&cg, &s, 0u32, 1u32)
    if c1_error != ok || c1_value != 5i32 || c1_move != 3u32 { os.exit(21i32) }
    let (q1_value, q1_move, q1_error) = ai.quiescence[Cap](&cg, &s, 0u32, 1u32)
    if q1_error != ok || q1_value != 4i32 || q1_move != 3u32 || s.nodes != 26u64 { os.exit(22i32) }
    let (q0_value, q0_move, q0_error) = ai.quiescence[Cap](&cg, &s, 0u32, 0u32)
    if q0_error != ok || q0_value != 4i32 || q0_move != 3u32 || s.nodes != 12u64 { os.exit(23i32) }
    let (cf_value, cf_move, cf_error) = ai.alpha_beta[Cap](&cg, &s, 0u32, 6u32)
    if cf_error != ok || cf_value != 2i32 || cf_move != 3u32 || c.top != 1usize { os.exit(24i32) }

    // --- expectimax on the dice game ----------------------------------------------------------
    var d_me: [32]i32 = zero
    var d_opp: [32]i32 = zero
    var d_roll: [32]i32 = zero
    var d_turns: [32]i32 = zero
    var d = Dice { me: d_me[..], opp: d_opp[..], roll: d_roll[..], turns: d_turns[..], top: 2usize }
    d_me[0usize] = 1i32
    d_turns[0usize] = 2i32
    d_me[1usize] = 1i32
    d_roll[1usize] = 2i32
    d_turns[1usize] = 2i32
    let dg = ai.Game[Dice] { ctx: &d, moves: dice_moves, apply: dice_apply, release: dice_release, evaluate: dice_evaluate, is_terminal: dice_terminal, is_capture: dice_capture, chance_outcomes: dice_chance, zobrist: dice_zobrist }
    s.max_moves = 3usize
    let (x_value, x_move, x_error) = ai.expectimax[Dice](&dg, &s, 0u32, 6u32)
    if x_error != ok || x_value != 1i32 || x_move != ai.NONE || s.nodes != 64u64 { os.exit(25i32) }
    let (y_value, y_move, y_error) = ai.expectimax[Dice](&dg, &s, 1u32, 6u32)
    if y_error != ok || y_value != 1i32 || y_move != 1u32 || s.nodes != 21u64 { os.exit(26i32) }
    let (w_value, w_move, w_error) = ai.expectimax[Dice](&dg, &s, 1u32, 1u32)
    if w_error != ok || w_value != 4i32 || w_move != 1u32 || s.nodes != 3u64 || d.top != 2usize { os.exit(27i32) }

    // --- behaviour tree with resumption -------------------------------------------------------
    var tree: [12]ai.BtNode = zero
    tree[0usize] = ai.BtNode { kind: .Repeat, first_child: 1u16, child_count: 1u16, id: 0u16, limit: 2u16 }
    tree[1usize] = ai.BtNode { kind: .Sequence, first_child: 2u16, child_count: 3u16, id: 0u16, limit: 0u16 }
    tree[2usize] = ai.BtNode { kind: .Leaf, first_child: 0u16, child_count: 0u16, id: 0u16, limit: 0u16 }
    tree[3usize] = ai.BtNode { kind: .Leaf, first_child: 0u16, child_count: 0u16, id: 1u16, limit: 0u16 }
    tree[4usize] = ai.BtNode { kind: .Inverter, first_child: 5u16, child_count: 1u16, id: 0u16, limit: 0u16 }
    tree[5usize] = ai.BtNode { kind: .Leaf, first_child: 0u16, child_count: 0u16, id: 2u16, limit: 0u16 }
    tree[6usize] = ai.BtNode { kind: .Selector, first_child: 7u16, child_count: 2u16, id: 0u16, limit: 0u16 }
    tree[7usize] = ai.BtNode { kind: .Leaf, first_child: 0u16, child_count: 0u16, id: 3u16, limit: 0u16 }
    tree[8usize] = ai.BtNode { kind: .Succeeder, first_child: 9u16, child_count: 1u16, id: 0u16, limit: 0u16 }
    tree[9usize] = ai.BtNode { kind: .Leaf, first_child: 0u16, child_count: 0u16, id: 4u16, limit: 0u16 }
    tree[10usize] = ai.BtNode { kind: .Repeat, first_child: 11u16, child_count: 1u16, id: 0u16, limit: 0u16 }
    tree[11usize] = ai.BtNode { kind: .Leaf, first_child: 0u16, child_count: 0u16, id: 0u16, limit: 0u16 }
    var script = [9]u8{ 1u8, 0u8, 1u8, 2u8, 2u8, 1u8, 2u8, 2u8, 0u8 }
    var offsets = [5]usize{ 0usize, 1usize, 3usize, 6usize, 7usize }
    var lengths = [5]usize{ 1usize, 2usize, 3usize, 1usize, 2usize }
    var calls: [5]usize = zero
    var bc = BtCtx { script: script[..], offsets: offsets[..], lengths: lengths[..], calls: calls[..] }
    var bt_state: [12]u16 = zero
    var expected = [6]u8{ 0u8, 0u8, 1u8, 0u8, 2u8, 0u8 }
    i = 0usize
    while i < 6usize {
        if code(ai.behavior_tick[BtCtx](tree[..], bt_state[..], 0u16, &bc, bt_leaf)) != expected[i] { os.exit(28i32) }
        i += 1usize
    }
    var expected2 = [3]u8{ 1u8, 0u8, 1u8 }
    i = 0usize
    while i < 3usize {
        if code(ai.behavior_tick[BtCtx](tree[..], bt_state[..], 6u16, &bc, bt_leaf)) != expected2[i] { os.exit(29i32) }
        i += 1usize
    }
    if code(ai.behavior_tick[BtCtx](tree[..], bt_state[..], 10u16, &bc, bt_leaf)) != 0u8 { os.exit(30i32) }
    if code(ai.behavior_tick[BtCtx](tree[..], bt_state[..], 10u16, &bc, bt_leaf)) != 0u8 { os.exit(31i32) }
    if calls[0usize] != 6usize || calls[1usize] != 7usize || calls[2usize] != 3usize || calls[3usize] != 2usize || calls[4usize] != 3usize { os.exit(32i32) }
    if bt_state[1usize] != 1u16 || bt_state[10usize] != 2u16 || bt_state[0usize] != 0u16 { os.exit(33i32) }
    if ai.behavior_tick[BtCtx](tree[..], bt_state[..], 99u16, &bc, bt_leaf) != .Failure { os.exit(34i32) }

    // --- GOAP: the wood chopper ------------------------------------------------------------------
    // bits: axe 1, wood 2, money 4, fire 8; actions: get_axe, chop, branches, sell, light.
    var actions: [5]ai.GoapAction = zero
    actions[0usize] = ai.GoapAction { pre_mask: 0u32, pre_value: 0u32, effect_mask: 1u32, effect_value: 1u32, cost: 2u32 }
    actions[1usize] = ai.GoapAction { pre_mask: 1u32, pre_value: 1u32, effect_mask: 2u32, effect_value: 2u32, cost: 1u32 }
    actions[2usize] = ai.GoapAction { pre_mask: 0u32, pre_value: 0u32, effect_mask: 2u32, effect_value: 2u32, cost: 5u32 }
    actions[3usize] = ai.GoapAction { pre_mask: 2u32, pre_value: 2u32, effect_mask: 6u32, effect_value: 4u32, cost: 1u32 }
    actions[4usize] = ai.GoapAction { pre_mask: 2u32, pre_value: 2u32, effect_mask: 8u32, effect_value: 8u32, cost: 1u32 }
    var g_states: [64]u32 = zero
    var g_cost: [64]u32 = zero
    var g_parent: [64]u32 = zero
    var g_action: [64]u32 = zero
    var g_closed: [64]u8 = zero
    var gs = ai.GoapScratch { states: g_states[..], cost: g_cost[..], parent: g_parent[..], action: g_action[..], closed: g_closed[..] }
    var plan: [8]u32 = zero
    let (p1_len, p1_cost, p1_error) = ai.goap_plan(0u32, 8u32, 8u32, actions[..], &gs, plan[..])
    if p1_error != ok || p1_len != 3usize || p1_cost != 4u32 { os.exit(35i32) }
    if plan[0usize] != 0u32 || plan[1usize] != 1u32 || plan[2usize] != 4u32 { os.exit(36i32) }
    let (p2_len, p2_cost, p2_error) = ai.goap_plan(0u32, 12u32, 12u32, actions[..], &gs, plan[..])
    if p2_error != ok || p2_len != 4usize || p2_cost != 5u32 { os.exit(37i32) }
    if plan[0usize] != 0u32 || plan[1usize] != 1u32 || plan[2usize] != 4u32 || plan[3usize] != 3u32 { os.exit(38i32) }
    let (p3_len, p3_cost, p3_error) = ai.goap_plan(12u32, 12u32, 12u32, actions[..], &gs, plan[..])
    if p3_error != ok || p3_len != 0usize || p3_cost != 0u32 { os.exit(39i32) }
    let (p4_len, p4_cost, p4_error) = ai.goap_plan(0u32, 16u32, 16u32, actions[..], &gs, plan[..])
    if p4_error != ai.Unreachable { os.exit(40i32) }
    let (p5_len, p5_cost, p5_error) = ai.goap_plan(0u32, 12u32, 12u32, actions[..], &gs, plan[0usize..2usize])
    if p5_error != ai.Size { os.exit(41i32) }

    // --- utility AI ------------------------------------------------------------------------------
    var cons: [4]ai.Consideration = zero
    cons[0usize] = ai.Consideration { curve: .Linear, input: 0u16, m: 65536i32, k: 0i32, b: 0i32, c: 0i32 }
    cons[1usize] = ai.Consideration { curve: .Quadratic, input: 1u16, m: -65536i32, k: 0i32, b: 65536i32, c: 0i32 }
    cons[2usize] = ai.Consideration { curve: .Logistic, input: 1u16, m: 65536i32, k: 524288i32, b: 0i32, c: 32768i32 }
    cons[3usize] = ai.Consideration { curve: .Linear, input: 0u16, m: -65536i32, k: 0i32, b: 65536i32, c: 0i32 }
    var choices: [3]ai.Choice = zero
    choices[0usize] = ai.Choice { first: 0u16, count: 2u16 }
    choices[1usize] = ai.Choice { first: 2u16, count: 1u16 }
    choices[2usize] = ai.Choice { first: 3u16, count: 1u16 }
    var inputs = [2]i32{ 49152i32, 16384i32 }
    let (u_choice, u_score) = ai.utility_select(choices[..], cons[..], inputs[..])
    if u_choice != 0usize || u_score != 46080i32 { os.exit(42i32) }
    inputs[0usize] = 16384i32
    inputs[1usize] = 49152i32
    let (u2_choice, u2_score) = ai.utility_select(choices[..], cons[..], inputs[..])
    if u2_choice != 1usize || u2_score != 57724i32 { os.exit(43i32) }
    if ai.exp_fx(0i64) != 65536i64 || ai.exp_fx(65536i64) != 178142i64 || ai.exp_fx(-65536i64) != 24109i64 { os.exit(44i32) }

    // --- boids -------------------------------------------------------------------------------------
    var flock: [4]ai.Agent = zero
    flock[0usize] = ai.Agent { x: 0i32, y: 0i32, vx: 65536i32, vy: 0i32, max_speed: 131072i32 }
    flock[1usize] = ai.Agent { x: 131072i32, y: 65536i32, vx: 0i32, vy: 65536i32, max_speed: 131072i32 }
    flock[2usize] = ai.Agent { x: -65536i32, y: 131072i32, vx: 65536i32, vy: 65536i32, max_speed: 131072i32 }
    flock[3usize] = ai.Agent { x: 1966080i32, y: 1966080i32, vx: -65536i32, vy: 0i32, max_speed: 131072i32 }
    let flocked = ai.boids(flock[..], 0usize, 327680i32, 65536i32, 32768i32, 16384i32)
    if flocked.x != -90492i32 || flocked.y != -153318i32 { os.exit(45i32) }
    let alone = ai.boids(flock[..], 3usize, 327680i32, 65536i32, 32768i32, 16384i32)
    if alone.x != 0i32 || alone.y != 0i32 { os.exit(46i32) }

    try io.print("game ai plan ok\n")
    ret ok
}
