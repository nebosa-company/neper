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
use e.str
use e.gfx.geometry
use e.ui.input
use e.ui.widget
use e.ui.window

type Id = widget.ElementId
type Role = enum u8 { Application, Window, Group, Button, Checkbox, Radio, Text, TextField, Image, Link, List, ListItem, Table, Row, Cell, Slider, Progress, Scrollbar, Switch, Tab, TabList, Menu, MenuItem, Dialog, Alert, Heading, Status, Tooltip, Tree, TreeItem, Grid, RowHeader, ColumnHeader, Separator, AlertDialog, Listbox, Option, MenuItemCheckbox, Combobox, Region, Main }
type State = struct { disabled: bool, focused: bool, selected: bool, checked: bool, expanded: bool, hidden: bool, mixed: bool, busy: bool, invalid: bool, required: bool, read_only: bool, modal: bool, current: bool }
type Action = enum u8 { Focus, Press, Increment, Decrement, SetValue, Scroll, Dismiss, Expand, Collapse, Select, ShowMenu, SetSelection, Copy }
// Relationships to other nodes; an `Id` of generation 0 is none.
type Relations = struct { labelled_by: Id, described_by: Id, error_by: Id, controls: Id, active: Id }
type Live = enum u8 { Off, Polite, Assertive }
// A node's place in a collection: one-based row and column, 0 for none.
type Position = struct { row: u32, column: u32, row_count: u32, column_count: u32 }
type Node = struct { id: Id, role: Role, label: str, value: str, hint: str, state: State, bounds: geometry.Rect, actions: []const Action, children: []const Id, relations: Relations, live: Live, position: Position, level: u8, selection_start: usize, selection_end: usize }
type Tree = struct { root: Id, nodes: []const Node }
error Unsupported
error Invalid

// The state bits and action bits a `widget.Semantics` carries (D809).
const STATE_DISABLED: u32 = 1u32
const STATE_FOCUSED: u32 = 2u32
const STATE_SELECTED: u32 = 4u32
const STATE_CHECKED: u32 = 8u32
const STATE_EXPANDED: u32 = 16u32
const STATE_HIDDEN: u32 = 32u32
const STATE_MIXED: u32 = 64u32
const STATE_BUSY: u32 = 128u32
const STATE_INVALID: u32 = 256u32
const STATE_REQUIRED: u32 = 512u32
const STATE_READ_ONLY: u32 = 1024u32
const STATE_MODAL: u32 = 2048u32
const STATE_CURRENT: u32 = 4096u32
const ACTION_FOCUS: u32 = 1u32
const ACTION_PRESS: u32 = 2u32
const ACTION_INCREMENT: u32 = 4u32
const ACTION_DECREMENT: u32 = 8u32
const ACTION_SET_VALUE: u32 = 16u32
const ACTION_SCROLL: u32 = 32u32
const ACTION_DISMISS: u32 = 64u32
const ACTION_EXPAND: u32 = 128u32
const ACTION_COLLAPSE: u32 = 256u32
const ACTION_SELECT: u32 = 512u32
const ACTION_SHOW_MENU: u32 = 1024u32
const ACTION_SET_SELECTION: u32 = 2048u32
const ACTION_COPY: u32 = 4096u32

const ROLE_SEPARATOR: u8 = 33u8
const ROLE_ALERT_DIALOG: u8 = 34u8
const ROLE_LISTBOX: u8 = 35u8
const ROLE_OPTION: u8 = 36u8
const ROLE_MENU_ITEM_CHECKBOX: u8 = 37u8
const ROLE_COMBOBOX: u8 = 38u8
const ROLE_REGION: u8 = 39u8
const ROLE_MAIN: u8 = 40u8

// The widget kinds by tag, as `e.ui.widget` numbers them.
const KIND_TEXT: u8 = 4u8
const KIND_BUTTON: u8 = 5u8
const KIND_IMAGE: u8 = 6u8
const KIND_SCROLL: u8 = 7u8
const KIND_EDIT: u8 = 11u8

fn role_of(kind: u8) -> Role {
    if kind == KIND_TEXT { ret .Text }
    if kind == KIND_BUTTON { ret .Button }
    if kind == KIND_IMAGE { ret .Image }
    if kind == KIND_SCROLL { ret .List }
    if kind == KIND_EDIT { ret .TextField }
    ret .Group
}

// The role a semantics code names: the inverse of `role_code`.
fn role_of_code(code: u8) -> Role {
    var i = 1u8
    while i < 41u8 {
        let candidate = role_at(i)
        if role_code(candidate) == code { ret candidate }
        i += 1u8
    }
    ret .Group
}

fn role_at(i: u8) -> Role {
    if i == 1u8 { ret .Window }
    if i == 2u8 { ret .Group }
    if i == 3u8 { ret .Button }
    if i == 4u8 { ret .Checkbox }
    if i == 5u8 { ret .Radio }
    if i == 6u8 { ret .Text }
    if i == 7u8 { ret .TextField }
    if i == 8u8 { ret .Image }
    if i == 9u8 { ret .Link }
    if i == 10u8 { ret .List }
    if i == 11u8 { ret .ListItem }
    if i == 12u8 { ret .Table }
    if i == 13u8 { ret .Row }
    if i == 14u8 { ret .Cell }
    if i == 15u8 { ret .Slider }
    if i == 16u8 { ret .Progress }
    if i == 17u8 { ret .Scrollbar }
    if i == 18u8 { ret .Switch }
    if i == 19u8 { ret .Tab }
    if i == 20u8 { ret .TabList }
    if i == 21u8 { ret .Menu }
    if i == 22u8 { ret .MenuItem }
    if i == 23u8 { ret .Dialog }
    if i == 24u8 { ret .Alert }
    if i == 25u8 { ret .Heading }
    if i == 26u8 { ret .Status }
    if i == 27u8 { ret .Tooltip }
    if i == 28u8 { ret .Tree }
    if i == 29u8 { ret .TreeItem }
    if i == 30u8 { ret .Grid }
    if i == 31u8 { ret .RowHeader }
    if i == 32u8 { ret .ColumnHeader }
    if i == ROLE_SEPARATOR { ret .Separator }
    if i == ROLE_ALERT_DIALOG { ret .AlertDialog }
    if i == ROLE_LISTBOX { ret .Listbox }
    if i == ROLE_OPTION { ret .Option }
    if i == ROLE_MENU_ITEM_CHECKBOX { ret .MenuItemCheckbox }
    if i == ROLE_COMBOBOX { ret .Combobox }
    if i == ROLE_REGION { ret .Region }
    if i == ROLE_MAIN { ret .Main }
    ret .Application
}

fn state_of_bits(bits: u32) -> State {
    ret State { disabled: (bits & STATE_DISABLED) != 0u32, focused: (bits & STATE_FOCUSED) != 0u32, selected: (bits & STATE_SELECTED) != 0u32, checked: (bits & STATE_CHECKED) != 0u32, expanded: (bits & STATE_EXPANDED) != 0u32, hidden: (bits & STATE_HIDDEN) != 0u32, mixed: (bits & STATE_MIXED) != 0u32, busy: (bits & STATE_BUSY) != 0u32, invalid: (bits & STATE_INVALID) != 0u32, required: (bits & STATE_REQUIRED) != 0u32, read_only: (bits & STATE_READ_ONLY) != 0u32, modal: (bits & STATE_MODAL) != 0u32, current: (bits & STATE_CURRENT) != 0u32 }
}

fn action_bit(action: Action) -> u32 {
    if action == .Press { ret ACTION_PRESS }
    if action == .Increment { ret ACTION_INCREMENT }
    if action == .Decrement { ret ACTION_DECREMENT }
    if action == .SetValue { ret ACTION_SET_VALUE }
    if action == .Scroll { ret ACTION_SCROLL }
    if action == .Dismiss { ret ACTION_DISMISS }
    if action == .Expand { ret ACTION_EXPAND }
    if action == .Collapse { ret ACTION_COLLAPSE }
    if action == .Select { ret ACTION_SELECT }
    if action == .ShowMenu { ret ACTION_SHOW_MENU }
    if action == .SetSelection { ret ACTION_SET_SELECTION }
    if action == .Copy { ret ACTION_COPY }
    ret ACTION_FOCUS
}

fn action_at(i: usize) -> Action {
    if i == 1usize { ret .Press }
    if i == 2usize { ret .Increment }
    if i == 3usize { ret .Decrement }
    if i == 4usize { ret .SetValue }
    if i == 5usize { ret .Scroll }
    if i == 6usize { ret .Dismiss }
    if i == 7usize { ret .Expand }
    if i == 8usize { ret .Collapse }
    if i == 9usize { ret .Select }
    if i == 10usize { ret .ShowMenu }
    if i == 11usize { ret .SetSelection }
    if i == 12usize { ret .Copy }
    ret .Focus
}

// The actions of a bit set, in declaration order, into `a`.
fn actions_of_bits(a: *mem.Arena, bits: u32) -> ([]const Action, err) {
    var count = 0usize
    var i = 0usize
    while i < 13usize {
        if (bits & action_bit(action_at(i))) != 0u32 { count += 1usize }
        i += 1usize
    }
    let (actions, actions_error) = mem.alloc[Action](a, count)
    if actions_error != ok { ret (zero, actions_error) }
    var n = 0usize
    i = 0usize
    while i < 13usize {
        if (bits & action_bit(action_at(i))) != 0u32 {
            actions[n] = action_at(i)
            n += 1usize
        }
        i += 1usize
    }
    ret (actions, ok)
}

// The element a semantics relationship names by key, or the none Id.
fn related(runtime: *const widget.Runtime, key: widget.Key) -> Id {
    if key == 0u64 { ret zero }
    let (found, count) = widget.find_by_key(mem.cast[*widget.State](runtime.state), key)
    if count == 0usize { ret zero }
    ret found
}

// Whether the element or one above it says it is hidden.
fn hidden_at(runtime: *const widget.Runtime, slot: usize) -> bool {
    var at = slot
    while true {
        let (summary, live) = widget.summary_at(runtime, at)
        if !live { ret false }
        if summary.has_semantics && (summary.semantics.hidden || (summary.semantics.states & STATE_HIDDEN) != 0u32) { ret true }
        if !summary.has_parent { ret false }
        at = usize(summary.parent.slot)
    }
    ret false
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
        if live && !hidden_at(runtime, slot) {
            var node: Node = zero
            node.id = summary.id
            node.role = role_of(summary.kind)
            node.bounds = summary.bounds
            var bits = 0u32
            if !summary.enabled { bits = bits | STATE_DISABLED }
            if summary.focused { bits = bits | STATE_FOCUSED }
            if summary.read_only { bits = bits | STATE_READ_ONLY }
            var action_mask = ACTION_FOCUS
            if summary.has_action && summary.enabled { action_mask = action_mask | ACTION_PRESS }
            if summary.kind == KIND_SCROLL { action_mask = action_mask | ACTION_SCROLL }
            if summary.kind == KIND_EDIT {
                action_mask = action_mask | ACTION_SET_SELECTION
                if !summary.read_only { action_mask = action_mask | ACTION_SET_VALUE }
                node.selection_start = summary.selection_start
                node.selection_end = summary.selection_end
            }
            var value = summary.value
            var hint: str = ""
            var label = summary.text
            if summary.has_semantics {
                let sm = summary.semantics
                if sm.role != 0u8 { node.role = role_of_code(sm.role) }
                bits = bits | sm.states
                action_mask = action_mask | sm.actions
                if sm.label.len != 0usize { label = sm.label }
                if sm.value.len != 0usize { value = sm.value }
                hint = sm.hint
                node.relations = Relations { labelled_by: related(runtime, sm.labelled_by), described_by: related(runtime, sm.described_by), error_by: related(runtime, sm.error_by), controls: related(runtime, sm.controls), active: related(runtime, sm.active) }
                if sm.live == 1u8 { node.live = .Polite }
                if sm.live == 2u8 { node.live = .Assertive }
                node.position = Position { row: sm.row, column: sm.column, row_count: sm.row_count, column_count: sm.column_count }
                node.level = sm.level
            }
            node.state = state_of_bits(bits)
            // A button's label is the text it holds.
            if summary.kind == KIND_BUTTON && summary.has_child {
                let (child, has_child) = widget.summary_at(runtime, usize(summary.first_child.slot))
                if has_child && child.kind == KIND_TEXT { label = child.text }
            }
            let (copied, copy_error) = copy_text(a, label)
            if copy_error != ok { ret (zero, copy_error) }
            node.label = copied
            let (copied_value, value_error) = copy_text(a, value)
            if value_error != ok { ret (zero, value_error) }
            node.value = copied_value
            let (copied_hint, hint_error) = copy_text(a, hint)
            if hint_error != ok { ret (zero, hint_error) }
            node.hint = copied_hint
            // Every node can take focus; an enabled action can be pressed; a scroll
            // scrolls; an editor takes a value and a selection; semantics add theirs.
            let (actions, actions_error) = actions_of_bits(a, action_mask)
            if actions_error != ok { ret (zero, actions_error) }
            node.actions = actions
            // Children in order, through the sibling links; hidden ones left out.
            var child_count = 0usize
            var child_slot = summary.first_child
            var has_more = summary.has_child
            while has_more {
                let (child, live_child) = widget.summary_at(runtime, usize(child_slot.slot))
                if !live_child { break }
                if !hidden_at(runtime, usize(child_slot.slot)) { child_count += 1usize }
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
                if !hidden_at(runtime, usize(child_slot.slot)) {
                    children[filled] = child.id
                    filled += 1usize
                }
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
    if role == .Switch { ret 18u8 }
    if role == .Tab { ret 19u8 }
    if role == .TabList { ret 20u8 }
    if role == .Menu { ret 21u8 }
    if role == .MenuItem { ret 22u8 }
    if role == .Dialog { ret 23u8 }
    if role == .Alert { ret 24u8 }
    if role == .Heading { ret 25u8 }
    if role == .Status { ret 26u8 }
    if role == .Tooltip { ret 27u8 }
    if role == .Tree { ret 28u8 }
    if role == .TreeItem { ret 29u8 }
    if role == .Grid { ret 30u8 }
    if role == .RowHeader { ret 31u8 }
    if role == .ColumnHeader { ret 32u8 }
    if role == .Separator { ret ROLE_SEPARATOR }
    if role == .AlertDialog { ret ROLE_ALERT_DIALOG }
    if role == .Listbox { ret ROLE_LISTBOX }
    if role == .Option { ret ROLE_OPTION }
    if role == .MenuItemCheckbox { ret ROLE_MENU_ITEM_CHECKBOX }
    if role == .Combobox { ret ROLE_COMBOBOX }
    if role == .Region { ret ROLE_REGION }
    if role == .Main { ret ROLE_MAIN }
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

fn action_bits(actions: []const Action) -> u32 {
    var bits = 0u32
    var i = 0usize
    while i < actions.len {
        bits = bits | action_bit(actions[i])
        i += 1usize
    }
    ret bits
}

// The tree flattened into the bridge's records and handed to the host: every node
// once, its parent found from the children lists; nothing of the tree is kept.
fn publish(window_value: window.Id, t: *const Tree) -> err {
    let (state, window_error) = window.state_by_id(window_value)
    if window_error != ok { ret Invalid }
    var storage: [256]os.AccessibleNode = zero
    if t.nodes.len > storage.len { ret Invalid }
    var i = 0usize
    while i < t.nodes.len {
        let n = &t.nodes[i]
        storage[i] = os.AccessibleNode { id: n.id.slot, parent: 0u32, has_parent: false, role: role_code(n.role), label: n.label, value: n.value, hint: n.hint, flags: flags_of(n.state), actions: action_bits(n.actions), x: n.bounds.x, y: n.bounds.y, width: n.bounds.width, height: n.bounds.height }
        i += 1usize
    }
    i = 0usize
    while i < t.nodes.len {
        let n = &t.nodes[i]
        var c = 0usize
        while c < n.children.len {
            var k = 0usize
            while k < t.nodes.len {
                if t.nodes[k].id.slot == n.children[c].slot && t.nodes[k].id.generation == n.children[c].generation {
                    storage[k].parent = n.id.slot
                    storage[k].has_parent = true
                }
                k += 1usize
            }
            c += 1usize
        }
        i += 1usize
    }
    let published = os.accessibility_publish(state.handle, storage[0usize..t.nodes.len])
    if published == os.Unsupported { ret Unsupported }
    if published != ok { ret Invalid }
    ret ok
}

// A platform request routed through the widgets: focus is the runtime's, a press is a
// pointer down at the element's centre through dispatch, a value and a selection
// (`value` as "start:end") reach an editor, and the rest reach the element's
// semantics as their bit when it offers them.
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
    if action == .SetValue {
        if widget.edit_set(runtime, id, value) == ok { ret ok }
    }
    if action == .SetSelection {
        var colon = value.len
        var i = 0usize
        while i < value.len {
            if value[i] == 58u8 && colon == value.len { colon = i }
            i += 1usize
        }
        if colon == value.len { ret Invalid }
        let (start, start_error) = str.parse_u64(value[0usize..colon])
        let (end, end_error) = str.parse_u64(value[colon + 1usize..value.len])
        if start_error != ok || end_error != ok { ret Invalid }
        if widget.edit_select(runtime, id, usize(start), usize(end)) == ok { ret ok }
    }
    if action == .Copy && widget.edit_copy_child(runtime, id) == ok { ret ok }
    if widget.semantic_action(runtime, id, action_bit(action)) == ok { ret ok }
    ret Unsupported
}

// ------------------------------------------------ the tree and the order (D904)

// The accessibility tree, built from the runtime; `build` under the name
// docs/algos.md gives the construction.
fn tree(a: *mem.Arena, runtime: *const widget.Runtime) -> (Tree, err) {
    let (built, build_error) = build(a, runtime)
    ret (built, build_error)
}

// The focusable elements in document order -- the runtime's preorder, which is
// the order Tab travels, since no element carries an index of its own here; what
// is focusable is the runtime's own answer, the one its Tab uses.
fn focus_order(a: *mem.Arena, runtime: *const widget.Runtime) -> ([]Id, err) {
    var nothing: []Id = zero
    let (root, has_root) = widget.root_of(runtime)
    if !has_root { ret (nothing, ok) }
    var stack: [256]u32 = zero
    var depth = 0usize
    stack[0usize] = root.slot
    depth = 1usize
    var order: [256]Id = zero
    var count = 0usize
    while depth > 0usize {
        depth -= 1usize
        let slot = stack[depth]
        let (summary, has_summary) = widget.summary_at(runtime, usize(slot))
        if !has_summary { continue }
        if summary.focusable && count < 256usize {
            order[count] = summary.id
            count += 1usize
        }
        // Children pushed last first so that the first child is visited next.
        var children: [64]u32 = zero
        var child_count = 0usize
        var child = summary.first_child
        var has_child = summary.has_child
        while has_child && child_count < 64usize {
            children[child_count] = child.slot
            child_count += 1usize
            let (child_summary, has_child_summary) = widget.summary_at(runtime, usize(child.slot))
            if !has_child_summary { break }
            has_child = child_summary.has_sibling
            child = child_summary.next_sibling
        }
        while child_count > 0usize && depth < 256usize {
            child_count -= 1usize
            stack[depth] = children[child_count]
            depth += 1usize
        }
    }
    let (copy, allocation_error) = mem.alloc[Id](a, count)
    if allocation_error != ok { ret (nothing, allocation_error) }
    var at = 0usize
    while at < count {
        copy[at] = order[at]
        at += 1usize
    }
    ret (copy[0usize..count], ok)
}
