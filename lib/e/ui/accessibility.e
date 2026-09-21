// `e.ui.accessibility` (D802): the semantic tree of a widget runtime, built from the
// elements it retains -- every live element a node with the same identity, its role
// from its kind, its label the text it holds or the text its first child does, its
// bounds the last laid out -- published through the reviewed `e.os` bridge and
// acted on through the same action system the widgets use. Paint-only decorations
// are not here: a box with nothing but a background is a `Group` the way a flex is,
// and a widget kind that says nothing more is a `Group` too.
//
// The host bridge is not written yet, so `publish` is `Unsupported` on every host;
// the framework does not claim accessibility until it is, and says so here.

use e.mem
use e.os
use e.gfx.geometry
use e.ui.input
use e.ui.widget
use e.ui.window

type Id = widget.ElementId
type Role = enum u8 { Application, Window, Group, Button, Checkbox, Radio, Text, TextField, Image, Link, List, ListItem, Table, Row, Cell, Slider, Progress, Scrollbar }
type State = struct { disabled: bool, focused: bool, selected: bool, checked: bool, expanded: bool, hidden: bool }
type Action = enum u8 { Focus, Press, Increment, Decrement, SetValue, Scroll }
type Node = struct { id: Id, role: Role, label: str, value: str, hint: str, state: State, bounds: geometry.Rect, actions: []const Action, children: []const Id }
type Tree = struct { root: Id, nodes: []const Node }
error Unsupported
error Invalid

// The widget kinds by tag, as `e.ui.widget` numbers them.
const KIND_TEXT: u8 = 4u8
const KIND_BUTTON: u8 = 5u8
const KIND_IMAGE: u8 = 6u8
const KIND_SCROLL: u8 = 7u8

fn role_of(kind: u8) -> Role {
    if kind == KIND_TEXT { ret .Text }
    if kind == KIND_BUTTON { ret .Button }
    if kind == KIND_IMAGE { ret .Image }
    if kind == KIND_SCROLL { ret .List }
    ret .Group
}

// A copy of `text` into `a`, so the tree retains nothing of the runtime's.
fn copy_text(a: *mem.Arena, text: str) -> (str, err) {
    if text.len == 0usize { ret ("", ok) }
    let (bytes, bytes_error) = mem.alloc[u8](a, text.len)
    if bytes_error != ok { ret ("", bytes_error) }
    mem.copy[u8](bytes, text)
    ret (bytes, ok)
}

fn build(a: *mem.Arena, runtime: *const widget.Runtime) -> (Tree, err) {
    let (root, has_root) = widget.root_of(runtime)
    if !has_root { ret (zero, Invalid) }
    let count = widget.element_count(runtime)
    // One node per live element, in slot order; a table from slot to node index.
    let (nodes, nodes_error) = mem.alloc[Node](a, count)
    if nodes_error != ok { ret (zero, nodes_error) }
    let (index_of, index_error) = mem.alloc[usize](a, count)
    if index_error != ok { ret (zero, index_error) }
    var produced = 0usize
    var slot = 0usize
    while slot < count {
        let (summary, live) = widget.summary_at(runtime, slot)
        index_of[slot] = count
        if live {
            var node: Node = zero
            node.id = summary.id
            node.role = role_of(summary.kind)
            node.bounds = summary.bounds
            node.state = State { disabled: !summary.enabled, focused: summary.focused, selected: false, checked: false, expanded: false, hidden: false }
            var label = summary.text
            // A button's label is the text it holds.
            if summary.kind == KIND_BUTTON && summary.has_child {
                let (child, has_child) = widget.summary_at(runtime, usize(summary.first_child.slot))
                if has_child && child.kind == KIND_TEXT { label = child.text }
            }
            let (copied, copy_error) = copy_text(a, label)
            if copy_error != ok { ret (zero, copy_error) }
            node.label = copied
            node.value = ""
            node.hint = ""
            // Every node can take focus; an enabled action can be pressed; a scroll scrolls.
            var action_count = 1usize
            if summary.has_action && summary.enabled { action_count += 1usize }
            if summary.kind == KIND_SCROLL { action_count += 1usize }
            let (actions, actions_error) = mem.alloc[Action](a, action_count)
            if actions_error != ok { ret (zero, actions_error) }
            actions[0usize] = .Focus
            var at = 1usize
            if summary.has_action && summary.enabled {
                actions[at] = .Press
                at += 1usize
            }
            if summary.kind == KIND_SCROLL { actions[at] = .Scroll }
            node.actions = actions
            // Children in order, through the sibling links.
            var child_count = 0usize
            var child_slot = summary.first_child
            var has_more = summary.has_child
            while has_more {
                child_count += 1usize
                let (child, live_child) = widget.summary_at(runtime, usize(child_slot.slot))
                if !live_child { break }
                has_more = child.has_sibling
                child_slot = child.next_sibling
            }
            let (children, children_error) = mem.alloc[Id](a, child_count)
            if children_error != ok { ret (zero, children_error) }
            child_slot = summary.first_child
            has_more = summary.has_child
            var filled = 0usize
            while has_more && filled < child_count {
                let (child, live_child) = widget.summary_at(runtime, usize(child_slot.slot))
                if !live_child { break }
                children[filled] = child.id
                filled += 1usize
                has_more = child.has_sibling
                child_slot = child.next_sibling
            }
            node.children = children[0usize..filled]
            index_of[slot] = produced
            nodes[produced] = node
            produced += 1usize
        }
        slot += 1usize
    }
    ret (Tree { root: root, nodes: nodes[0usize..produced] }, ok)
}

// The role's declared value, for the bridge's record.
fn role_code(role: Role) -> u8 {
    if role == .Window { ret 1u8 }
    if role == .Group { ret 2u8 }
    if role == .Button { ret 3u8 }
    if role == .Checkbox { ret 4u8 }
    if role == .Radio { ret 5u8 }
    if role == .Text { ret 6u8 }
    if role == .TextField { ret 7u8 }
    if role == .Image { ret 8u8 }
    if role == .Link { ret 9u8 }
    if role == .List { ret 10u8 }
    if role == .ListItem { ret 11u8 }
    if role == .Table { ret 12u8 }
    if role == .Row { ret 13u8 }
    if role == .Cell { ret 14u8 }
    if role == .Slider { ret 15u8 }
    if role == .Progress { ret 16u8 }
    if role == .Scrollbar { ret 17u8 }
    ret 0u8
}

fn flags_of(state: State) -> u8 {
    var bits = 0u8
    if state.disabled { bits = bits | 1u8 }
    if state.focused { bits = bits | 2u8 }
    if state.selected { bits = bits | 4u8 }
    if state.checked { bits = bits | 8u8 }
    if state.expanded { bits = bits | 16u8 }
    if state.hidden { bits = bits | 32u8 }
    ret bits
}

fn action_bits(actions: []const Action) -> u8 {
    var bits = 0u8
    var i = 0usize
    while i < actions.len {
        let action = actions[i]
        var bit = 1u8
        if action == .Press { bit = 2u8 }
        if action == .Increment { bit = 4u8 }
        if action == .Decrement { bit = 8u8 }
        if action == .SetValue { bit = 16u8 }
        if action == .Scroll { bit = 32u8 }
        bits = bits | bit
        i += 1usize
    }
    ret bits
}

// The tree flattened into the bridge's records and handed to the host: every node
// once, its parent found from the children lists; nothing of the tree is kept.
fn publish(window_value: window.Id, tree: *const Tree) -> err {
    let (state, window_error) = window.state_by_id(window_value)
    if window_error != ok { ret Invalid }
    var storage: [256]os.AccessibleNode = zero
    if tree.nodes.len > storage.len { ret Invalid }
    var i = 0usize
    while i < tree.nodes.len {
        let n = &tree.nodes[i]
        storage[i] = os.AccessibleNode { id: n.id.slot, parent: 0u32, has_parent: false, role: role_code(n.role), label: n.label, value: n.value, hint: n.hint, flags: flags_of(n.state), actions: action_bits(n.actions), x: n.bounds.x, y: n.bounds.y, width: n.bounds.width, height: n.bounds.height }
        i += 1usize
    }
    i = 0usize
    while i < tree.nodes.len {
        let n = &tree.nodes[i]
        var c = 0usize
        while c < n.children.len {
            var k = 0usize
            while k < tree.nodes.len {
                if tree.nodes[k].id.slot == n.children[c].slot && tree.nodes[k].id.generation == n.children[c].generation {
                    storage[k].parent = n.id.slot
                    storage[k].has_parent = true
                }
                k += 1usize
            }
            c += 1usize
        }
        i += 1usize
    }
    let published = os.accessibility_publish(state.handle, storage[0usize..tree.nodes.len])
    if published == os.Unsupported { ret Unsupported }
    if published != ok { ret Invalid }
    ret ok
}

// A platform request routed through the widgets: focus is the runtime's, a press is a
// pointer down at the element's centre through dispatch, the rest are `Unsupported`
// until a widget kind carries a value.
fn perform(runtime: *widget.Runtime, id: Id, action: Action, value: str) -> err {
    let (bounds, has_bounds) = widget.bounds_of(runtime, id)
    if !has_bounds { ret Invalid }
    if action == .Focus {
        if widget.focus(runtime, id) != ok { ret Invalid }
        ret ok
    }
    if action == .Press {
        let centre = geometry.Point { x: bounds.x + bounds.width * 0.5, y: bounds.y + bounds.height * 0.5 }
        let pointer = input.Pointer { window: zero, device: 0u32, pointer: 0u32, kind: .Mouse, position: centre, buttons: 1u32, changed: .Primary }
        if widget.dispatch(runtime, input.Event { PointerDown: pointer }) != ok { ret Invalid }
        var released = pointer
        released.buttons = 0u32
        if widget.dispatch(runtime, input.Event { PointerUp: released }) != ok { ret Invalid }
        ret ok
    }
    ret Unsupported
}
