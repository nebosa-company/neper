// Branching dialogue: nodes, guarded choices, flags and counters (D249).
//
// A tree is two flat arrays and nothing else -- nodes, and the choices they own as a run
// inside one shared array. No pointers, no allocation, and a tree is therefore data a game
// can author, ship as a constant and hand straight to `start`. The mutable half is the
// `State`: where the conversation is, which flags have been set and what the counters
// hold, all in the caller's buffers.
//
// A choice carries its own guard, so whether an option is offered is part of the data
// rather than a branch in the game. A guard reads flags and counters only, which keeps
// evaluation total: no expression language, nothing that can fail to parse, and no way to
// write a condition the checker cannot see through. The cost is that arithmetic beyond
// "add to a counter" belongs to the game; that is the right trade for a stdlib module.

use e.mem
use e.str

type Op = enum u8 { Always, FlagSet, FlagClear, VarEq, VarGe, VarLt }

type Condition = struct {
    op: Op,
    key: u16,
    value: i32,
}

// `target` is the node to move to once this choice is taken; `set_flag` and `add_key`
// are the effects, and either may be `NONE` to mean no effect.
type Choice = struct {
    text: str,
    target: u16,
    show_if: Condition,
    set_flag: u16,
    add_key: u16,
    delta: i32,
}

// `then` is where a node with no choices continues; `END` finishes the conversation.
type Node = struct {
    text: str,
    speaker: u16,
    first_choice: u16,
    choice_count: u16,
    then: u16,
}

type Tree = struct {
    nodes: []const Node,
    choices: []const Choice,
}

type State = struct {
    at: u16,
    flags: []u64,
    vars: []i32,
    finished: bool,
}

error Invalid
error Bounds

const NONE: u16 = 65535u16
const END: u16 = 65535u16

fn always() -> Condition {
    ret Condition { op: .Always, key: 0u16, value: 0i32 }
}

fn start(s: *State, t: Tree, flags: []u64, vars: []i32) -> err {
    if t.nodes.len == 0usize { ret Invalid }
    var at = 0usize
    while at < flags.len {
        flags[at] = 0u64
        at += 1usize
    }
    at = 0usize
    while at < vars.len {
        vars[at] = 0i32
        at += 1usize
    }
    s.at = 0u16
    s.flags = flags
    s.vars = vars
    s.finished = false
    ret ok
}

fn flag(s: State, key: u16) -> bool {
    let index = usize(key)
    if index / 64usize >= s.flags.len { ret false }
    ret (s.flags[index / 64usize] & (1u64 << u32(index % 64usize))) != 0u64
}

fn set_flag(s: *State, key: u16) -> err {
    let index = usize(key)
    if index / 64usize >= s.flags.len { ret Bounds }
    s.flags[index / 64usize] = s.flags[index / 64usize] | (1u64 << u32(index % 64usize))
    ret ok
}

fn value(s: State, key: u16) -> i32 {
    if usize(key) >= s.vars.len { ret 0i32 }
    ret s.vars[usize(key)]
}

fn add_value(s: *State, key: u16, delta: i32) -> err {
    if usize(key) >= s.vars.len { ret Bounds }
    s.vars[usize(key)] = s.vars[usize(key)] + delta
    ret ok
}

// Total by construction: every operator reads state that always has an answer, so a
// guard cannot fail, only be false.
fn holds(s: State, c: Condition) -> bool {
    if c.op == .Always { ret true }
    if c.op == .FlagSet { ret flag(s, c.key) }
    if c.op == .FlagClear { ret !flag(s, c.key) }
    if c.op == .VarEq { ret value(s, c.key) == c.value }
    if c.op == .VarGe { ret value(s, c.key) >= c.value }
    ret value(s, c.key) < c.value
}

fn node(s: State, t: Tree) -> (Node, err) {
    var empty: Node = zero
    if s.finished { ret (empty, Invalid) }
    if usize(s.at) >= t.nodes.len { ret (empty, Bounds) }
    ret (t.nodes[usize(s.at)], ok)
}

// The choices of the current node whose guards hold, as indices into the tree's shared
// choice array, in the order they were authored.
fn available(s: State, t: Tree, out: []u16) -> (usize, err) {
    let (current, current_error) = node(s, t)
    if current_error != ok { ret (0usize, current_error) }
    var count = 0usize
    var at = 0usize
    while at < usize(current.choice_count) {
        let index = usize(current.first_choice) + at
        if index >= t.choices.len { ret (0usize, Bounds) }
        if holds(s, t.choices[index].show_if) {
            if count == out.len { ret (0usize, Bounds) }
            out[count] = u16(index)
            count += 1usize
        }
        at += 1usize
    }
    ret (count, ok)
}

// Take a choice by its index in the tree's choice array -- the value `available`
// returned, not its position in that answer, so a caller that filters again still
// refers to the same choice. A choice whose guard does not hold is refused.
fn choose(s: *State, t: Tree, choice: u16) -> err {
    if s.finished { ret Invalid }
    if usize(choice) >= t.choices.len { ret Bounds }
    let taken = t.choices[usize(choice)]
    if !holds(*s, taken.show_if) { ret Invalid }
    if taken.set_flag != NONE { try set_flag(s, taken.set_flag) }
    if taken.add_key != NONE { try add_value(s, taken.add_key, taken.delta) }
    if taken.target == END {
        s.finished = true
        ret ok
    }
    if usize(taken.target) >= t.nodes.len { ret Bounds }
    s.at = taken.target
    ret ok
}

// Continue a node that offers nothing to choose. A node with live choices is waiting for
// one, and advancing past it would silently skip the decision.
fn advance(s: *State, t: Tree) -> err {
    if s.finished { ret Invalid }
    let (current, current_error) = node(*s, t)
    if current_error != ok { ret current_error }
    var offered: [1]u16 = zero
    var live = 0usize
    var at = 0usize
    while at < usize(current.choice_count) {
        let index = usize(current.first_choice) + at
        if index >= t.choices.len { ret Bounds }
        if holds(*s, t.choices[index].show_if) { live += 1usize }
        at += 1usize
    }
    if live != 0usize { ret Invalid }
    if current.then == END {
        s.finished = true
        ret ok
    }
    if usize(current.then) >= t.nodes.len { ret Bounds }
    s.at = current.then
    ret ok
}

fn finished(s: State) -> bool {
    ret s.finished
}
