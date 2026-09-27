// The UI Automation half of the screen-reader bridge (D1602), driven in process the
// way UI Automation drives it: WM_GETOBJECT's answer makes the window's store, a
// publish links the records, and the provider's methods -- called here directly,
// as UI Automation calls them through the tables -- navigate, name, place and act.
// A request lands in `accessibility_take` with its value, a secret field reads as
// its mask, and an element whose node is gone says so.

use e.io
use e.mem
use e.os

fn node(id: u32, parent: u32, role: u8, label: str, value: str, flags: u16, actions: u32) -> os.AccessibleNode {
    var n: os.AccessibleNode = zero
    n.id = id
    n.generation = 1u32
    n.parent = parent
    n.parent_generation = 1u32
    n.has_parent = parent != 0u32
    n.role = role
    n.label = label
    n.value = value
    n.flags = flags
    n.actions = actions
    n.x = f32(id) * 10.0
    n.y = 20.0
    n.width = 40.0
    n.height = 24.0
    ret n
}

// A BSTR's units against ASCII text; the length rides four bytes before them.
fn bstr_is(bits: usize, text: str) -> bool {
    if bits == 0usize { ret false }
    var pun: os.UiaUnitsPun = zero
    pun.bits = bits - 4usize
    let length_units = pun.units
    var length_pun: os.UiaWordPun = zero
    length_pun.bits = bits - 4usize
    if u32(length_pun.word.value & 4294967295usize) != u32(text.len * 2usize) { ret false }
    var at = 0usize
    while at < text.len {
        pun.bits = bits + at * 2usize
        if *pun.units != u16(text[at]) { ret false }
        at += 1usize
    }
    ret true
}

fn child(element: usize, direction: i32) -> usize {
    var out = os.UiaWord { value: 0usize }
    if os.uia_navigate(element, direction, &out) != 0i32 { ret 0usize }
    ret out.value
}

fn name_is(element: usize, text: str) -> bool {
    var v: os.UiaVariant = zero
    if os.uia_property(element - 8usize, 30005i32, &v) != 0i32 || v.kind != 8u16 { ret false }
    ret bstr_is(v.value, text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let options = os.WindowOptions { title: "neper os_uia", width: 320u32, height: 200u32, resizable: true, visible: false, mode: .Windowed }
    let (w, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(1i32) }
    // Nothing asked: a publish keeps nothing, and nothing is listening.
    var nodes: [6]os.AccessibleNode = zero
    nodes[0] = node(1u32, 0u32, 2u8, "", "", 0u16, 1u32)
    nodes[1] = node(2u32, 1u32, 3u8, "Save", "", 0u16, 3u32)
    nodes[2] = node(3u32, 1u32, 7u8, "Name", "Ada", 0u16, 17u32)
    nodes[3] = node(4u32, 1u32, 7u8, "Password", "***", 8192u16, 17u32)
    nodes[4] = node(5u32, 1u32, 4u8, "Agree", "", 8u16, 3u32)
    nodes[5] = node(6u32, 5u32, 6u8, "Agree", "", 0u16, 1u32)
    if os.accessibility_publish(w, nodes[0..]) != ok || os.accessibility_listening(w) { os.exit(2i32) }
    // WM_GETOBJECT for the root, as UI Automation sends it.
    let (answer, answered) = os.uia_answer(w.raw, 0usize, -25isize)
    if !answered || !os.accessibility_listening(w) { os.exit(3i32) }
    if os.accessibility_publish(w, nodes[0..]) != ok { os.exit(4i32) }
    let slot = os.window_slot(w.raw)
    let root = os.uia_root_element(slot, 1usize)
    // The root's one child is the group; its children come in order.
    let group = child(root, 3i32)
    if group == 0usize || child(root, 4i32) != group { os.exit(5i32) }
    let save = child(group, 3i32)
    if !name_is(save, "Save") || child(save, 2i32) != 0usize { os.exit(6i32) }
    let name_field = child(save, 1i32)
    if !name_is(name_field, "Name") || child(name_field, 2i32) != save { os.exit(7i32) }
    let password = child(name_field, 1i32)
    let agree = child(password, 1i32)
    if !name_is(agree, "Agree") || child(agree, 1i32) != 0usize || child(group, 4i32) != agree { os.exit(8i32) }
    if child(save, 0i32) != group || child(group, 0i32) != root { os.exit(9i32) }
    // Control types, and the text inside a box is presentational.
    var v: os.UiaVariant = zero
    if os.uia_property(save - 8usize, 30003i32, &v) != 0i32 || v.kind != 3u16 || v.value != 50000usize { os.exit(10i32) }
    if os.uia_property(agree - 8usize, 30003i32, &v) != 0i32 || v.value != 50002usize { os.exit(11i32) }
    let inner = child(agree, 3i32)
    if os.uia_property(inner - 8usize, 30016i32, &v) != 0i32 || v.kind != 11u16 || v.value != 0usize { os.exit(12i32) }
    if os.uia_property(group - 8usize, 30016i32, &v) != 0i32 || v.kind != 11u16 || v.value != 0usize { os.exit(13i32) }
    if os.uia_property(save - 8usize, 30016i32, &v) != 0i32 || v.kind != 0u16 { os.exit(14i32) }
    // The secret field is a password, and its value is the mask it was handed.
    if os.uia_property(password - 8usize, 30019i32, &v) != 0i32 || v.kind != 11u16 || v.value != 65535usize { os.exit(15i32) }
    // Patterns: a button invokes, a field has a value, a box toggles.
    var pattern = os.UiaWord { value: 0usize }
    if os.uia_pattern(save - 8usize, 10000i32, &pattern) != 0i32 || pattern.value != save - 8usize + 24usize { os.exit(16i32) }
    if os.uia_pattern(save - 8usize, 10002i32, &pattern) != 0i32 || pattern.value != 0usize { os.exit(17i32) }
    if os.uia_pattern(agree - 8usize, 10015i32, &pattern) != 0i32 || pattern.value == 0usize { os.exit(18i32) }
    var state = os.UiaInt { value: 9i32 }
    if os.uia_toggle_state(pattern.value, &state) != 0i32 || state.value != 1i32 { os.exit(19i32) }
    if os.uia_pattern(name_field - 8usize, 10002i32, &pattern) != 0i32 || pattern.value == 0usize { os.exit(20i32) }
    var text = os.UiaWord { value: 0usize }
    if os.uia_value(pattern.value, &text) != 0i32 || !bstr_is(text.value, "Ada") { os.exit(21i32) }
    // Screen bounds: the client origin plus the logical box at the window's scale.
    var rect: os.UiaRect = zero
    if os.uia_bounds(save, &rect) != 0i32 || rect.width < 40.0 || rect.height < 24.0 { os.exit(22i32) }
    // Actions become requests, in order, with the value a SetValue carries.
    let invoked = os.uia_invoke(save - 8usize + 24usize)
    var typed: [4]u16 = zero
    typed[0] = 71u16
    typed[1] = 233u16
    typed[2] = 111u16
    let set = os.uia_set_value(pattern.value, &typed[0usize])
    let focused = os.uia_set_focus(name_field)
    let (first, has_first) = os.accessibility_take(w)
    if invoked != 0i32 || !has_first || first.id != 2u32 || first.generation != 1u32 || first.action != 1u8 { os.exit(23i32) }
    let (second, has_second) = os.accessibility_take(w)
    if set != 0i32 || !has_second || second.id != 3u32 || second.action != 4u8 || second.value.len != 4usize || second.value[1] != 195u8 || second.value[2] != 169u8 { os.exit(24i32) }
    let (third, has_third) = os.accessibility_take(w)
    if focused != 0i32 || !has_third || third.id != 3u32 || third.action != 0u8 { os.exit(25i32) }
    let (_, has_fourth) = os.accessibility_take(w)
    if has_fourth { os.exit(26i32) }
    // Focus: the focused record is what the root reports.
    nodes[2].flags = 2u16
    if os.accessibility_publish(w, nodes[0..]) != ok { os.exit(27i32) }
    var focus = os.UiaWord { value: 0usize }
    if os.uia_focus(root + 8usize, &focus) != 0i32 || focus.value != name_field { os.exit(28i32) }
    // Republished without the button: its element is gone, and the rest relink.
    nodes[1] = node(7u32, 1u32, 6u8, "Saved", "", 0u16, 1u32)
    if os.accessibility_publish(w, nodes[0..]) != ok { os.exit(29i32) }
    if os.uia_property(save - 8usize, 30005i32, &v) != mem.bitcast[i32](os.UIA_E_ELEMENT_NOT_AVAILABLE) { os.exit(30i32) }
    if !name_is(child(group, 3i32), "Saved") { os.exit(31i32) }
    // Closed: UI Automation is handed nothing more, and the elements say so.
    if os.window_close(w) != ok || os.accessibility_listening(w) { os.exit(32i32) }
    if os.uia_property(name_field - 8usize, 30005i32, &v) != mem.bitcast[i32](os.UIA_E_ELEMENT_NOT_AVAILABLE) { os.exit(33i32) }
    try io.print("os uia ok\n")
    ret ok
}
