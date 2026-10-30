// A published tree as VoiceOver would meet it: three nodes (a group holding a button and a text) become elements; the window's view
// answers the group as its child, the group answers the two, the button says AXButton and "OK", and pressing it through the
// accessibility API reaches `accessibility_take` as a press of node 2. macOS only; the corpus runs it on a Mac.
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
    let pressed = os.msg0(button, os.cocoa_sel("accessibilityPerformPress\x00"))
    let (request, any) = os.accessibility_take(window)
    if !any || request.id != 2u32 || request.action != 1u8 { os.exit(9i32) }
    let (again, more) = os.accessibility_take(window)
    if more { os.exit(10i32) }
    say("press ok\n")
    say("accessibility ok\n")
    ret ok
}
