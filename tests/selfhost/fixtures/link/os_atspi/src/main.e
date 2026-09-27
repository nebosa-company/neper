// The AT-SPI half of the screen-reader bridge (D1603), driven in process: the bus
// is left untried so nothing leaves the process, and each method call is built
// with the bridge's own writer, placed where the socket's bytes land, parsed and
// dispatched, and its reply parsed back. The application lists the window, the
// first call makes publishing start, and the published nodes answer their
// children, roles, states, text and actions; requests land in
// `accessibility_take` with their values, and paths whose node or window is
// gone say so.

use e.io
use e.mem
use e.os

var reply: [65536]u8 = zero
var reply_len: usize = 0usize

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

// The call in the writer's buffer, as if the socket had delivered it, dispatched;
// the reply copied out and parsed.
fn deliver() -> os.DMessage {
    os.d_finish()
    os.atspi_receive(os.atspi_out[0usize..os.atspi_out_len])
    var at = 0usize
    while at < os.atspi_out_len {
        reply[at] = os.atspi_out[at]
        at += 1usize
    }
    reply_len = os.atspi_out_len
    let (answer, answer_total, answered) = os.d_parse(reply[0usize..], 0usize, reply_len)
    if !answered { os.exit(91i32) }
    ret answer
}

fn call(object: str, interface: str, member: str, signature: str) {
    os.d_call(":1.0", object, interface, member, signature)
}

fn node_path(window: usize, id: u32) -> str {
    ret os.atspi_path(window, true, id, 1u32)
}

// The one text a reply carries.
fn text_of(m: *const os.DMessage) -> str {
    var c = os.r_body(m)
    ret os.r_text(reply[0usize..], &c)
}

fn u32_of(m: *const os.DMessage) -> u32 {
    var c = os.r_body(m)
    ret os.r_u32(reply[0usize..], &c)
}

fn delivered_u32() -> u32 {
    let m = deliver()
    ret u32_of(&m)
}

fn delivered_text() -> str {
    let m = deliver()
    ret text_of(&m)
}

fn delivered_kind() -> u8 {
    let m = deliver()
    ret m.kind
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

// The paths of an `a(so)` reply, joined by spaces after their common prefix.
fn children_are(m: *const os.DMessage, expected: str) -> bool {
    var c = os.r_body(m)
    let length = os.r_u32(reply[0usize..], &c)
    let end = c.at + usize(length)
    var joined: [256]u8 = zero
    var used = 0usize
    while c.at < end {
        os.r_pad(&c, 8usize)
        let bus_name = os.r_text(reply[0usize..], &c)
        let object = os.r_text(reply[0usize..], &c)
        let prefix = os.atspi_prefix()
        if object.len <= prefix.len { ret false }
        if used != 0usize {
            joined[used] = 32u8
            used += 1usize
        }
        var at = prefix.len
        while at < object.len && used < joined.len {
            joined[used] = object[at]
            used += 1usize
            at += 1usize
        }
    }
    ret same(joined[0usize..used], expected)
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Run with NO_AT_BRIDGE=1: no bus, so the dispatcher answers into its buffer
    // and nothing is sent.
    let options = os.WindowOptions { title: "neper os_atspi", width: 320u32, height: 200u32, resizable: true, visible: false, mode: .Windowed }
    let (w, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(2i32) }
    if os.atspi_state != os.ATSPI_ABSENT || os.atspi_in.len == 0usize { os.exit(1i32) }
    let slot = os.window_slot(u32(w.raw))
    if slot != 0usize { os.exit(32i32) }
    var nodes: [6]os.AccessibleNode = zero
    nodes[0] = node(1u32, 0u32, 2u8, "", "", 0u16, 1u32)
    nodes[1] = node(2u32, 1u32, 3u8, "Save", "", 0u16, 3u32)
    nodes[2] = node(3u32, 1u32, 7u8, "Name", "Ada", 0u16, 17u32)
    nodes[3] = node(4u32, 1u32, 7u8, "Password", "***", 8192u16, 17u32)
    nodes[4] = node(5u32, 1u32, 4u8, "Agree", "", 8u16, 3u32)
    nodes[5] = node(6u32, 5u32, 6u8, "Agree", "", 0u16, 1u32)
    // Nothing asked yet: a publish keeps nothing.
    if os.accessibility_publish(w, nodes[0..]) != ok || os.accessibility_listening(w) { os.exit(3i32) }
    // The application: its one child is the window's frame, named by its title.
    call("/org/a11y/atspi/accessible/root", "org.a11y.atspi.Accessible", "GetChildren", "")
    let listed = deliver()
    if listed.kind != 2u8 || !children_are(&listed, "0") { os.exit(4i32) }
    if !os.accessibility_listening(w) { os.exit(5i32) }
    call(os.atspi_path(slot, false, 0u32, 0u32), "org.freedesktop.DBus.Properties", "Get", "ss")
    os.d_text("org.a11y.atspi.Accessible")
    os.d_text("Name")
    let titled = deliver()
    var c = os.r_body(&titled)
    let variant = os.r_signature(reply[0usize..], &c)
    if titled.kind != 2u8 || !same(variant, "s") || !same(os.r_text(reply[0usize..], &c), "neper os_atspi") { os.exit(6i32) }
    // Published: the frame's child is the group, whose children come in order.
    if os.accessibility_publish(w, nodes[0..]) != ok { os.exit(7i32) }
    call(os.atspi_path(slot, false, 0u32, 0u32), "org.a11y.atspi.Accessible", "GetChildren", "")
    let framed = deliver()
    if !children_are(&framed, "0_1_1") { os.exit(8i32) }
    call(node_path(slot, 1u32), "org.a11y.atspi.Accessible", "GetChildren", "")
    let grouped = deliver()
    if !children_are(&grouped, "0_2_1 0_3_1 0_4_1 0_5_1") { os.exit(9i32) }
    // Roles: a button, an entry, a password field, a box.
    call(node_path(slot, 2u32), "org.a11y.atspi.Accessible", "GetRole", "")
    if delivered_u32() != 43u32 { os.exit(10i32) }
    call(node_path(slot, 3u32), "org.a11y.atspi.Accessible", "GetRole", "")
    if delivered_u32() != 79u32 { os.exit(11i32) }
    call(node_path(slot, 4u32), "org.a11y.atspi.Accessible", "GetRole", "")
    if delivered_u32() != 40u32 { os.exit(12i32) }
    call(node_path(slot, 5u32), "org.a11y.atspi.Accessible", "GetRole", "")
    if delivered_u32() != 7u32 { os.exit(13i32) }
    // States: the box is enabled, checkable and checked.
    call(node_path(slot, 5u32), "org.a11y.atspi.Accessible", "GetState", "")
    let stated = deliver()
    var c3 = os.r_body(&stated)
    let count = os.r_u32(reply[0usize..], &c3)
    let low = os.r_u32(reply[0usize..], &c3)
    let high = os.r_u32(reply[0usize..], &c3)
    if count != 8u32 || low & 256u32 == 0u32 || low & 16u32 == 0u32 || high & 512u32 == 0u32 { os.exit(14i32) }
    // Names and text.
    call(node_path(slot, 2u32), "org.freedesktop.DBus.Properties", "Get", "ss")
    os.d_text("org.a11y.atspi.Accessible")
    os.d_text("Name")
    let named = deliver()
    var c4 = os.r_body(&named)
    let named_variant = os.r_signature(reply[0usize..], &c4)
    if !same(os.r_text(reply[0usize..], &c4), "Save") { os.exit(15i32) }
    call(node_path(slot, 3u32), "org.a11y.atspi.Text", "GetText", "ii")
    os.d_i32(0i32)
    os.d_i32(-1i32)
    if !same(delivered_text(), "Ada") { os.exit(16i32) }
    call(node_path(slot, 4u32), "org.a11y.atspi.Text", "GetText", "ii")
    os.d_i32(0i32)
    os.d_i32(-1i32)
    if !same(delivered_text(), "***") { os.exit(17i32) }
    // Actions: the button clicks; the requests come back in order with values.
    call(node_path(slot, 2u32), "org.a11y.atspi.Action", "GetName", "i")
    os.d_i32(0i32)
    if !same(delivered_text(), "click") { os.exit(18i32) }
    call(node_path(slot, 2u32), "org.a11y.atspi.Action", "DoAction", "i")
    os.d_i32(0i32)
    if delivered_u32() != 1u32 { os.exit(19i32) }
    call(node_path(slot, 3u32), "org.a11y.atspi.EditableText", "SetTextContents", "s")
    var typed: [3]u8 = zero
    typed[0] = 71u8
    typed[1] = 195u8
    typed[2] = 169u8
    os.d_text(typed[0usize..3usize])
    if delivered_u32() != 1u32 { os.exit(20i32) }
    call(node_path(slot, 3u32), "org.a11y.atspi.Component", "GrabFocus", "")
    if delivered_u32() != 1u32 { os.exit(21i32) }
    let (first, has_first) = os.accessibility_take(w)
    if !has_first || first.id != 2u32 || first.action != 1u8 { os.exit(22i32) }
    let (second, has_second) = os.accessibility_take(w)
    if !has_second || second.id != 3u32 || second.action != 4u8 || second.value.len != 3usize || second.value[1] != 195u8 { os.exit(23i32) }
    let (third, has_third) = os.accessibility_take(w)
    if !has_third || third.id != 3u32 || third.action != 0u8 { os.exit(24i32) }
    let (_, has_fourth) = os.accessibility_take(w)
    if has_fourth { os.exit(25i32) }
    // Gone: a path nobody published, the button once republished without it,
    // and the frame once its window closes.
    call("/org/a11y/atspi/accessible/9_1_1", "org.a11y.atspi.Accessible", "GetRole", "")
    if delivered_kind() != 3u8 { os.exit(26i32) }
    nodes[1] = node(7u32, 1u32, 6u8, "Saved", "", 0u16, 1u32)
    if os.accessibility_publish(w, nodes[0..]) != ok { os.exit(27i32) }
    call(node_path(slot, 2u32), "org.a11y.atspi.Accessible", "GetRole", "")
    if delivered_kind() != 3u8 { os.exit(28i32) }
    call(node_path(slot, 7u32), "org.a11y.atspi.Accessible", "GetRole", "")
    if delivered_u32() != 29u32 { os.exit(29i32) }
    if os.window_close(w) != ok { os.exit(30i32) }
    call(os.atspi_path(slot, false, 0u32, 0u32), "org.a11y.atspi.Accessible", "GetRole", "")
    if delivered_kind() != 3u8 { os.exit(31i32) }
    try io.print("os atspi ok\n")
    ret ok
}
