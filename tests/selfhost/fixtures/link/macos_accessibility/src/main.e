// Published accessibility trees are per window: two windows retain different groups and buttons, and each action reaches only its
// own `accessibility_take`. macOS only; the corpus runs it on a Mac.
use e.mem
use e.os

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn text_of(object: usize, key: str) -> usize {
    ret os.msg0(object, os.cocoa_sel(key))
}

fn equals(object: usize, expected: str) -> bool {
    if object == 0usize { ret false }
    var buffer: [64]u8 = zero
    let length = os.cocoa_read_text(object, buffer[..])
    if length != expected.len { ret false }
    var at = 0usize
    while at < length {
        if buffer[at] != expected[at] { ret false }
        at += 1usize
    }
    ret true
}

fn main(a: *mem.Arena) -> err {
    var options: os.WindowOptions = zero
    options.title = "Neper: accessibility"
    options.width = 300u32
    options.height = 200u32
    options.visible = true
    let (window, open_error) = os.window_open(a, options)
    if open_error != ok { os.exit(2i32) }
    var nodes: [3]os.AccessibleNode = zero
    nodes[0usize].id = 1u32
    nodes[0usize].generation = 1u32
    nodes[0usize].role = 2u8
    nodes[0usize].label = "Panel"
    nodes[0usize].width = 300.0f32
    nodes[0usize].height = 200.0f32
    nodes[1usize].id = 2u32
    nodes[1usize].generation = 1u32
    nodes[1usize].parent = 1u32
    nodes[1usize].parent_generation = 1u32
    nodes[1usize].has_parent = true
    nodes[1usize].role = 3u8
    nodes[1usize].label = "OK"
    nodes[1usize].x = 10.0f32
    nodes[1usize].y = 10.0f32
    nodes[1usize].width = 80.0f32
    nodes[1usize].height = 30.0f32
    nodes[2usize].id = 3u32
    nodes[2usize].generation = 1u32
    nodes[2usize].parent = 1u32
    nodes[2usize].parent_generation = 1u32
    nodes[2usize].has_parent = true
    nodes[2usize].role = 6u8
    nodes[2usize].label = "Hello"
    nodes[2usize].value = "world"
    if os.accessibility_publish(window, nodes[..]) != ok { os.exit(3i32) }
    let (handle, view, native_error) = os.window_native(window)
    if native_error != ok { os.exit(4i32) }
    let top = os.msg0(view, os.cocoa_sel("accessibilityChildren\x00"))
    if top == 0usize || os.msg0(top, os.cocoa_sel("count\x00")) != 1usize { os.exit(5i32) }
    let group = os.msg1(top, os.cocoa_sel("objectAtIndex:\x00"), 0usize)
    let kids = os.msg0(group, os.cocoa_sel("accessibilityChildren\x00"))
    if kids == 0usize || os.msg0(kids, os.cocoa_sel("count\x00")) != 2usize { os.exit(6i32) }
    let button = os.msg1(kids, os.cocoa_sel("objectAtIndex:\x00"), 0usize)
    if !equals(os.msg0(button, os.cocoa_sel("accessibilityRole\x00")), "AXButton") { os.exit(7i32) }
    if !equals(os.msg0(button, os.cocoa_sel("accessibilityLabel\x00")), "OK") { os.exit(8i32) }
    say("tree ok\n")
    var second_options: os.WindowOptions = zero
    second_options.title = "Neper: accessibility other"
    second_options.width = 300u32
    second_options.height = 200u32
    let (second, second_open_error) = os.window_open(a, second_options)
    if second_open_error != ok { os.exit(9i32) }
    var second_nodes: [2]os.AccessibleNode = zero
    second_nodes[0usize].id = 10u32
    second_nodes[0usize].generation = 1u32
    second_nodes[0usize].role = 2u8
    second_nodes[0usize].label = "Other panel"
    second_nodes[0usize].width = 300.0f32
    second_nodes[0usize].height = 200.0f32
    second_nodes[1usize].id = 20u32
    second_nodes[1usize].generation = 1u32
    second_nodes[1usize].parent = 10u32
    second_nodes[1usize].parent_generation = 1u32
    second_nodes[1usize].has_parent = true
    second_nodes[1usize].role = 3u8
    second_nodes[1usize].label = "Other OK"
    second_nodes[1usize].width = 80.0f32
    second_nodes[1usize].height = 30.0f32
    if os.accessibility_publish(second, second_nodes[..]) != ok { os.exit(10i32) }
    let (second_handle, second_view, second_native_error) = os.window_native(second)
    if second_native_error != ok { os.exit(11i32) }
    let second_top = os.msg0(second_view, os.cocoa_sel("accessibilityChildren\x00"))
    if second_top == 0usize || os.msg0(second_top, os.cocoa_sel("count\x00")) != 1usize { os.exit(12i32) }
    let second_group = os.msg1(second_top, os.cocoa_sel("objectAtIndex:\x00"), 0usize)
    let second_kids = os.msg0(second_group, os.cocoa_sel("accessibilityChildren\x00"))
    if second_kids == 0usize || os.msg0(second_kids, os.cocoa_sel("count\x00")) != 1usize { os.exit(13i32) }
    let second_button = os.msg1(second_kids, os.cocoa_sel("objectAtIndex:\x00"), 0usize)
    if !equals(os.msg0(second_button, os.cocoa_sel("accessibilityLabel\x00")), "Other OK") { os.exit(14i32) }
    // Publishing the second tree must leave the first tree and its callback registration intact.
    if os.msg0(top, os.cocoa_sel("count\x00")) != 1usize || !equals(os.msg0(button, os.cocoa_sel("accessibilityLabel\x00")), "OK") { os.exit(15i32) }
    let pressed = os.msg0(button, os.cocoa_sel("accessibilityPerformPress\x00"))
    let (request, any) = os.accessibility_take(window)
    if !any || request.id != 2u32 || request.action != 1u8 { os.exit(16i32) }
    let pressed_second = os.msg0(second_button, os.cocoa_sel("accessibilityPerformPress\x00"))
    let (wrong, leaked) = os.accessibility_take(window)
    if leaked { os.exit(17i32) }
    let (second_request, second_any) = os.accessibility_take(second)
    if !second_any || second_request.id != 20u32 || second_request.action != 1u8 { os.exit(18i32) }
    say("press ok\n")
    say("accessibility ok\n")
    ret ok
}
