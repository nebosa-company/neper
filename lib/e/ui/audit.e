// `e.ui.audit` (D1601): an accessibility audit of a page of controls, run without a
// window through `e.ui.testing`'s harness. The caller's page is built and laid out
// at the size asked; then, over the semantic tree a screen reader would be given
// and the pixels a person would see:
//
// - every control has a name and a role of its own (WCAG 4.1.2);
// - every control takes a pointer 24 across, or stands far enough from the others
//   that a 24 circle on it meets none (2.5.8, and its spacing exception);
// - every text stands 4.5:1 against what is under it, 3:1 when it is large
//   (1.4.3), measured on the rendered pixels;
// - Tab reaches every control (2.1.1), never lets the focus fall to nothing or
//   stick (2.1.2), shows where the focus went (2.4.7), and brings it into view
//   (2.4.11).
//
// Each failure is a `Finding`: the check, the node's role, name and bounds, and a
// measure (a contrast ratio, a size). The audit finds what a machine can; it says
// nothing of whether a name is a good one, or of anything a person must judge.

use e.math
use e.mem
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.scene
use e.ui.accessibility
use e.ui.layout as ui_layout
use e.ui.testing
use e.ui.widget

type Check = enum u8 { Name, Role, Target, Contrast, Reach, FocusLost, FocusTrap, FocusVisible, FocusObscured }
type Finding = struct { check: Check, role: accessibility.Role, label: str, bounds: geometry.Rect, measure: f32 }
// The page: built afresh for every frame, as an app's builder is.
type Page = struct { ctx: *void, build: fn(*void, *widget.BuildContext) -> (widget.Node, err) }
// What to look at and with how much room: the surface's logical size, whether to
// walk the page with Tab and to measure its contrast, the most Tab stops walked,
// and the bytes a frame's tree may take.
type Options = struct { width: u32, height: u32, keyboard: bool, contrast: bool, max_stops: usize, frame_bytes: usize }
// A run's totals: the findings written and those there was no room for, the
// nodes of the tree, and the Tab stops walked.
type Report = struct { count: usize, dropped: usize, nodes: usize, stops: usize }
error TooLarge

const TREE_BYTES: usize = 16777216usize
const TEXT_BYTES: usize = 65536usize
const NAME_LIMIT: usize = 64usize

fn options() -> Options {
    ret Options { width: 1280u32, height: 800u32, keyboard: true, contrast: true, max_stops: 200usize, frame_bytes: 16777216usize }
}

// The check's name, for a report.
fn check_name(check: Check) -> str {
    let names: [9]str = [9]str{ "name", "role", "target", "contrast", "reach", "focus-lost", "focus-trap", "focus-visible", "focus-obscured" }
    ret names[usize(mem.bitcast[u8](check))]
}

// A role's name, for a report.
fn role_name(role: accessibility.Role) -> str {
    let names: [45]str = [45]str{ "Application", "Window", "Group", "Button", "Checkbox", "Radio", "Text", "TextField", "Image", "Link", "List", "ListItem", "Table", "Row", "Cell", "Slider", "Progress", "Scrollbar", "Switch", "Tab", "TabList", "Menu", "MenuItem", "Dialog", "Alert", "Heading", "Status", "Tooltip", "Tree", "TreeItem", "Grid", "RowHeader", "ColumnHeader", "Separator", "AlertDialog", "Listbox", "Option", "MenuItemCheckbox", "Combobox", "Region", "Main", "MenuBar", "MenuItemRadio", "TreeGrid", "SpinButton" }
    ret names[usize(mem.bitcast[u8](role))]
}

// What a finding means, in a line.
fn check_meaning(check: Check) -> str {
    let meanings: [9]str = [9]str{ "a control with no accessible name (WCAG 4.1.2)", "a control exposed with a generic role (WCAG 4.1.2)", "a target under 24 x 24 with no room round it (WCAG 2.5.8)", "text under its contrast minimum (WCAG 1.4.3)", "a control Tab never reaches (WCAG 2.1.1)", "Tab left nothing focused (WCAG 2.1.1)", "Tab left the focus where it was (WCAG 2.1.2)", "the focus shows no change (WCAG 2.4.7)", "the focus stands outside the view (WCAG 2.4.11)" }
    ret meanings[usize(mem.bitcast[u8](check))]
}

type Run = struct { h: testing.Harness, runtime: *widget.Runtime, page: Page, frame: u64, width: u32, height: u32, frame_bytes: []u8, tree_bytes: []u8, start_bytes: []u8, shot_a: []u8, shot_b: []u8, text: mem.Arena, out: []Finding, count: usize, dropped: usize, max_stops: usize }

// Audit the page over `runtime` (a runtime of the caller's renderer, fonts
// registered as the app registers them): findings into `out`, the totals
// answered. `a` holds the harness and the run's buffers and the findings' names.
fn run(a: *mem.Arena, runtime: *widget.Runtime, page: Page, o: Options, out: []Finding) -> (Report, err) {
    let (h, h_error) = testing.harness(a, runtime, o.width, o.height, 1.0)
    if h_error != ok { ret (zero, h_error) }
    let shot_bytes = usize(o.width) * usize(o.height) * 8usize + 65536usize
    let (frame_bytes, frame_error) = mem.alloc[u8](a, o.frame_bytes)
    if frame_error != ok { ret (zero, TooLarge) }
    let (tree_bytes, tree_error) = mem.alloc[u8](a, TREE_BYTES)
    if tree_error != ok { ret (zero, TooLarge) }
    let (start_bytes, start_error) = mem.alloc[u8](a, TREE_BYTES)
    if start_error != ok { ret (zero, TooLarge) }
    let (shot_a, shot_a_error) = mem.alloc[u8](a, shot_bytes)
    if shot_a_error != ok { ret (zero, TooLarge) }
    let (shot_b, shot_b_error) = mem.alloc[u8](a, shot_bytes)
    if shot_b_error != ok { ret (zero, TooLarge) }
    let (text_bytes, text_error) = mem.alloc[u8](a, TEXT_BYTES)
    if text_error != ok { ret (zero, TooLarge) }
    var r: Run = zero
    r.h = h
    r.runtime = runtime
    r.page = page
    r.width = o.width
    r.height = o.height
    r.frame_bytes = frame_bytes
    r.tree_bytes = tree_bytes
    r.start_bytes = start_bytes
    r.shot_a = shot_a
    r.shot_b = shot_b
    r.text = mem.arena_from(text_bytes)
    r.out = out
    r.max_stops = o.max_stops
    // Two frames: the second is the one a control that waits a frame shows.
    let first_error = pump(&r)
    if first_error != ok { ret (zero, first_error) }
    let second_error = pump(&r)
    if second_error != ok { ret (zero, second_error) }
    var report: Report = zero
    let (nodes, static_error) = audit_page(&r, o.contrast)
    if static_error != ok { ret (zero, static_error) }
    report.nodes = nodes
    if o.keyboard {
        // The walk starts from nothing focused, as a page does when it opens.
        let cleared = widget.clear_focus(runtime)
        if cleared != ok { ret (zero, cleared) }
        let (stops, walk_error) = audit_keyboard(&r)
        if walk_error != ok { ret (zero, walk_error) }
        report.stops = stops
    }
    report.count = r.count
    report.dropped = r.dropped
    ret (report, ok)
}

// One frame: the page built and laid out in the run's frame arena, then rendered.
fn pump(r: *Run) -> err {
    r.frame += 1u64
    let now = time.Instant { nanos: 1000000000i64 + i64(r.frame) * 16000000i64 }
    try testing.begin(&r.h, now)
    var context = widget.BuildContext { runtime: r.runtime, element: zero, frame: r.frame }
    let (root, build_error) = r.page.build(r.page.ctx, &context)
    if build_error != ok { ret build_error }
    let (s, state_error) = testing.state_of(&r.h)
    if state_error != ok { ret state_error }
    widget.set_frame_time(s.runtime, now)
    var frame = mem.arena_from(r.frame_bytes)
    let w = f32(r.width)
    let hh = f32(r.height)
    let (compiled, reconcile_error) = widget.reconcile(s.runtime, &frame, root, ui_layout.Constraints { min_width: 0.0, max_width: w, min_height: 0.0, max_height: hh })
    if reconcile_error != ok { ret reconcile_error }
    ret scene.render(widget.renderer_of(s.runtime), compiled, s.drawable, geometry.Size { width: w, height: hh })
}

fn tree_in(r: *Run, bytes: []u8) -> (accessibility.Tree, err) {
    var arena = mem.arena_from(bytes)
    let (t, t_error) = accessibility.build(&arena, r.runtime)
    ret (t, t_error)
}

fn shot_in(r: *Run, bytes: []u8) -> (image.Image, err) {
    var arena = mem.arena_from(bytes)
    let (shot, shot_error) = testing.snapshot(&r.h, &arena)
    ret (shot, shot_error)
}

// A finding written, its name copied out of the tree's storage.
fn note(r: *Run, check: Check, role: accessibility.Role, label: str, bounds: geometry.Rect, measure: f32) {
    if r.count >= r.out.len {
        r.dropped += 1usize
        ret
    }
    var kept = label
    if kept.len > NAME_LIMIT { kept = kept[0usize..NAME_LIMIT] }
    var copied = ""
    if kept.len > 0usize {
        let (bytes, bytes_error) = mem.alloc[u8](&r.text, kept.len)
        if bytes_error == ok {
            mem.copy[u8](bytes, kept)
            copied = bytes
        }
    }
    r.out[r.count] = Finding { check: check, role: role, label: copied, bounds: bounds, measure: measure }
    r.count += 1usize
}

fn note_node(r: *Run, check: Check, n: *const accessibility.Node, measure: f32) {
    note(r, check, n.role, n.label, n.bounds, measure)
}

fn has_action(n: *const accessibility.Node, wanted: accessibility.Action) -> bool {
    var i = 0usize
    while i < n.actions.len {
        if n.actions[i] == wanted { ret true }
        i += 1usize
    }
    ret false
}

// A node a person acts on: it presses, takes a value, steps, opens or selects,
// or its role says it is a control.
fn interactive(n: *const accessibility.Node) -> bool {
    if has_action(n, .Press) || has_action(n, .SetValue) || has_action(n, .Increment) || has_action(n, .Expand) || has_action(n, .Collapse) || has_action(n, .Select) || has_action(n, .ShowMenu) { ret true }
    let role = n.role
    ret role == .Button || role == .Checkbox || role == .Radio || role == .TextField || role == .Link || role == .Slider || role == .Switch || role == .Tab || role == .MenuItem || role == .MenuItemCheckbox || role == .MenuItemRadio || role == .Combobox || role == .Option || role == .TreeItem || role == .SpinButton
}

fn disabled_here(t: *const accessibility.Tree, index: usize) -> bool {
    var at = index
    var guard = 0usize
    while guard < 64usize {
        if t.nodes[at].state.disabled { ret true }
        let (parent, has_parent) = accessibility.tree_parent(t.nodes, t.nodes[at].id)
        if !has_parent { ret false }
        at = parent
        guard += 1usize
    }
    ret false
}

fn on_surface(r: *const Run, b: geometry.Rect) -> bool {
    ret b.width > 0.0 && b.height > 0.0 && b.x >= 0.0 && b.y >= 0.0 && b.x + b.width <= f32(r.width) && b.y + b.height <= f32(r.height)
}

fn contains(outer: geometry.Rect, inner: geometry.Rect) -> bool {
    ret inner.x >= outer.x && inner.y >= outer.y && inner.x + inner.width <= outer.x + outer.width && inner.y + inner.height <= outer.y + outer.height
}

// Inside every scrolling ancestor: the tree keeps bounds the viewport clips.
fn unclipped(t: *const accessibility.Tree, index: usize) -> bool {
    let b = t.nodes[index].bounds
    var at = index
    var guard = 0usize
    while guard < 64usize {
        let (parent, has_parent) = accessibility.tree_parent(t.nodes, t.nodes[at].id)
        if !has_parent { ret true }
        let p = t.nodes[parent].bounds
        if has_action(&t.nodes[parent], .Scroll) && (b.x < p.x - 0.5 || b.y < p.y - 0.5 || b.x + b.width > p.x + p.width + 0.5 || b.y + b.height > p.y + p.height + 0.5) { ret false }
        at = parent
        guard += 1usize
    }
    ret true
}

fn undersized(n: *const accessibility.Node) -> bool {
    ret n.bounds.width < 24.0 || n.bounds.height < 24.0
}

// WCAG 2.5.8's spacing exception: a 24 circle on the target's centre meets no
// other target, nor another undersized target's circle.
fn spaced(t: *const accessibility.Tree, index: usize) -> bool {
    let b = t.nodes[index].bounds
    let cx = b.x + b.width * 0.5
    let cy = b.y + b.height * 0.5
    var j = 0usize
    while j < t.nodes.len {
        let o = &t.nodes[j]
        if j != index && interactive(o) && o.bounds.width > 0.0 && o.bounds.height > 0.0 && !contains(o.bounds, b) && !contains(b, o.bounds) {
            var nx = cx
            if nx < o.bounds.x { nx = o.bounds.x }
            if nx > o.bounds.x + o.bounds.width { nx = o.bounds.x + o.bounds.width }
            var ny = cy
            if ny < o.bounds.y { ny = o.bounds.y }
            if ny > o.bounds.y + o.bounds.height { ny = o.bounds.y + o.bounds.height }
            let dx = nx - cx
            let dy = ny - cy
            if dx * dx + dy * dy < 144.0 { ret false }
            if undersized(o) {
                let ox = o.bounds.x + o.bounds.width * 0.5 - cx
                let oy = o.bounds.y + o.bounds.height * 0.5 - cy
                if ox * ox + oy * oy < 576.0 { ret false }
            }
        }
        j += 1usize
    }
    ret true
}

fn linear(c: f32) -> f64 {
    let v = f64(c)
    if v <= 0.04045 { ret v / 12.92 }
    ret math.pow[f64]((v + 0.055) / 1.055, 2.4)
}

fn luminance(red: f32, green: f32, blue: f32) -> f64 {
    ret 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
}

fn ratio(l1: f64, l2: f64) -> f64 {
    if l1 > l2 { ret (l1 + 0.05) / (l2 + 0.05) }
    ret (l2 + 0.05) / (l1 + 0.05)
}

fn pixel_luminance(shot: image.Image, x: usize, y: usize) -> f64 {
    let at = y * shot.stride + x * 4usize
    ret luminance(f32(shot.pixels[at]) / 255.0, f32(shot.pixels[at + 1usize]) / 255.0, f32(shot.pixels[at + 2usize]) / 255.0)
}

// The most frequent pixel of a rectangle -- the ground under a text -- as its
// luminance; none for a rectangle off the shot.
fn ground(shot: image.Image, x0: usize, y0: usize, x1: usize, y1: usize) -> (f64, bool) {
    var colours: [16]u32 = zero
    var counts: [16]usize = zero
    var used = 0usize
    var y = y0
    while y < y1 && y < usize(shot.height) {
        var x = x0
        while x < x1 && x < usize(shot.width) {
            let at = y * shot.stride + x * 4usize
            let p = u32(shot.pixels[at]) | (u32(shot.pixels[at + 1usize]) << 8u32) | (u32(shot.pixels[at + 2usize]) << 16u32)
            var k = 0usize
            var found = false
            while k < used {
                if colours[k] == p {
                    counts[k] += 1usize
                    found = true
                    break
                }
                k += 1usize
            }
            if !found && used < 16usize {
                colours[used] = p
                counts[used] = 1usize
                used += 1usize
            }
            x += 1usize
        }
        y += 1usize
    }
    if used == 0usize { ret (0.0, false) }
    var best = 0usize
    var k = 1usize
    while k < used {
        if counts[k] > counts[best] { best = k }
        k += 1usize
    }
    let p = colours[best]
    ret (luminance(f32(p & 255u32) / 255.0, f32((p >> 8u32) & 255u32) / 255.0, f32((p >> 16u32) & 255u32) / 255.0), true)
}

// The ink: the pixel of the rectangle that stands out most from the ground.
fn strongest(shot: image.Image, x0: usize, y0: usize, x1: usize, y1: usize, ground_luminance: f64) -> f64 {
    var best: f64 = 1.0
    var y = y0
    while y < y1 && y < usize(shot.height) {
        var x = x0
        while x < x1 && x < usize(shot.width) {
            let cr = ratio(pixel_luminance(shot, x, y), ground_luminance)
            if cr > best { best = cr }
            x += 1usize
        }
        y += 1usize
    }
    ret best
}

// Names, roles, targets and text contrast over the page as built; the tree's
// node count answered.
fn audit_page(r: *Run, contrast: bool) -> (usize, err) {
    let (t, t_error) = tree_in(r, r.tree_bytes)
    if t_error != ok { ret (0usize, t_error) }
    let (shot, shot_error) = shot_in(r, r.shot_a)
    if shot_error != ok { ret (0usize, shot_error) }
    var i = 0usize
    while i < t.nodes.len {
        let n = &t.nodes[i]
        let shown = on_surface(r, n.bounds)
        if interactive(n) && !disabled_here(&t, i) {
            let named = n.label.len > 0usize || n.relations.labelled_by.generation != 0u32
            if !named { note_node(r, .Name, n, 0.0) }
            if n.role == .Group || n.role == .Text || n.role == .Image { note_node(r, .Role, n, 0.0) }
            if shown && n.role != .Link && undersized(n) && !spaced(&t, i) {
                var least = n.bounds.width
                if n.bounds.height < least { least = n.bounds.height }
                note_node(r, .Target, n, least)
            }
        }
        if contrast && n.role == .Text && n.label.len > 0usize && shown && !disabled_here(&t, i) && unclipped(&t, i) {
            let x0 = usize(n.bounds.x)
            let y0 = usize(n.bounds.y)
            let x1 = usize(n.bounds.x + n.bounds.width)
            let y1 = usize(n.bounds.y + n.bounds.height)
            let (under, has_under) = ground(shot, x0, y0, x1, y1)
            if has_under {
                let cr = strongest(shot, x0, y0, x1, y1, under)
                // A text that draws nothing (ratio 1) is not seen at all: not a
                // contrast failure the pixels can show.
                var need: f64 = 4.5
                if n.bounds.height >= 30.0 { need = 3.0 }
                if cr > 1.01 && cr < need { note_node(r, .Contrast, n, f32(cr)) }
            }
        }
        i += 1usize
    }
    ret (t.nodes.len, ok)
}

// Whether the pixels round a control changed: 24 out, as a field shows its focus on
// its frame, which stands round the editor that holds it.
fn region_differs(p: image.Image, q: image.Image, bounds: geometry.Rect) -> bool {
    let reach: f32 = 24.0
    var x0 = 0usize
    var y0 = 0usize
    if bounds.x > reach { x0 = usize(bounds.x - reach) }
    if bounds.y > reach { y0 = usize(bounds.y - reach) }
    let x1 = usize(bounds.x + bounds.width + reach)
    let y1 = usize(bounds.y + bounds.height + reach)
    var y = y0
    while y < y1 && y < usize(p.height) {
        var x = x0
        while x < x1 && x < usize(p.width) {
            let at = y * p.stride + x * 4usize
            if p.pixels[at] != q.pixels[at] || p.pixels[at + 1usize] != q.pixels[at + 1usize] || p.pixels[at + 2usize] != q.pixels[at + 2usize] { ret true }
            x += 1usize
        }
        y += 1usize
    }
    ret false
}

fn find_node(t: *const accessibility.Tree, id: widget.ElementId) -> (usize, bool) {
    var i = 0usize
    while i < t.nodes.len {
        if t.nodes[i].id.slot == id.slot && t.nodes[i].id.generation == id.generation { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// The tree's node for the focused element: its wrapper's, when it is folded.
fn node_id(r: *const Run, element: widget.ElementId) -> widget.ElementId {
    let (wrapper, folded) = accessibility.folded_into(r.runtime, usize(element.slot))
    if !folded { ret element }
    let (outer, _) = widget.summary_at(r.runtime, wrapper)
    ret outer.id
}

fn in_stops(stops: []const widget.ElementId, id: accessibility.Id) -> bool {
    var k = 0usize
    while k < stops.len {
        if stops[k].slot == id.slot && stops[k].generation == id.generation { ret true }
        k += 1usize
    }
    ret false
}

fn subtree_reached(t: *const accessibility.Tree, index: usize, stops: []const widget.ElementId, depth: usize) -> bool {
    if in_stops(stops, t.nodes[index].id) { ret true }
    if depth > 24usize { ret false }
    var c = 0usize
    while c < t.nodes[index].children.len {
        let (child, has_child) = find_node(t, t.nodes[index].children[c])
        if has_child && subtree_reached(t, child, stops, depth + 1usize) { ret true }
        c += 1usize
    }
    ret false
}

// Whether a node of `role` in the subtree took a stop.
fn role_reached(t: *const accessibility.Tree, index: usize, role: accessibility.Role, stops: []const widget.ElementId, depth: usize) -> bool {
    if t.nodes[index].role == role && in_stops(stops, t.nodes[index].id) { ret true }
    if depth > 24usize { ret false }
    var c = 0usize
    while c < t.nodes[index].children.len {
        let (child, has_child) = find_node(t, t.nodes[index].children[c])
        if has_child && role_reached(t, child, role, stops, depth + 1usize) { ret true }
        c += 1usize
    }
    ret false
}

// Reached: the node, a node inside it or one it stands in took a stop, or a
// sibling of its own role did -- a composite (a radio group, a tab strip, a
// list's options) is one stop and its arrows.
fn reached(t: *const accessibility.Tree, index: usize, stops: []const widget.ElementId) -> bool {
    if subtree_reached(t, index, stops, 0usize) { ret true }
    var at = index
    var guard = 0usize
    while guard < 32usize {
        let (up, has_up) = accessibility.tree_parent(t.nodes, t.nodes[at].id)
        if !has_up { break }
        if in_stops(stops, t.nodes[up].id) { ret true }
        at = up
        guard += 1usize
    }
    let role = t.nodes[index].role
    // A generic group beside another is no composite, only a layout.
    if role == .Group || role == .Text || role == .Image || role == .Region || role == .Main || role == .Application || role == .Window { ret false }
    // Inside a composite -- a calendar's grid, a list, a menu -- one stop of the
    // same role reaches all its kind, rows apart as a calendar's days are.
    at = index
    guard = 0usize
    while guard < 8usize {
        let (up, has_up) = accessibility.tree_parent(t.nodes, t.nodes[at].id)
        if !has_up { break }
        let kind = t.nodes[up].role
        if kind == .Grid || kind == .Table || kind == .TreeGrid || kind == .Tree || kind == .List || kind == .Listbox || kind == .TabList || kind == .Menu || kind == .MenuBar {
            ret role_reached(t, up, role, stops, 0usize)
        }
        at = up
        guard += 1usize
    }
    let (parent, has_parent) = accessibility.tree_parent(t.nodes, t.nodes[index].id)
    if !has_parent { ret false }
    var c = 0usize
    while c < t.nodes[parent].children.len {
        let (sibling, has_sibling) = find_node(t, t.nodes[parent].children[c])
        if has_sibling && sibling != index && t.nodes[sibling].role == role && subtree_reached(t, sibling, stops, 0usize) { ret true }
        c += 1usize
    }
    ret false
}

fn tab_and_settle(r: *Run) -> err {
    try testing.tab(&r.h, false)
    try pump(r)
    ret pump(r)
}

// Tab through the page until the focus comes round: every stop must show and
// stand in view, the focus must not fall to nothing nor stick, and every control
// must be reached. The stops walked answered.
fn audit_keyboard(r: *Run) -> (usize, err) {
    let (start, start_error) = tree_in(r, r.start_bytes)
    if start_error != ok { ret (0usize, start_error) }
    let (stops, stops_error) = mem.alloc[widget.ElementId](&r.text, r.max_stops)
    if stops_error != ok { ret (0usize, TooLarge) }
    let (before, before_error) = shot_in(r, r.shot_a)
    if before_error != ok { ret (0usize, before_error) }
    var previous = before
    var use_b = true
    var count = 0usize
    var last: widget.ElementId = zero
    // The last stop's node, which a focus lost from it is reported against.
    var last_role: accessibility.Role = .Application
    var last_label = ""
    var last_bounds: geometry.Rect = zero
    while count < r.max_stops {
        let settled = tab_and_settle(r)
        if settled != ok { ret (count, settled) }
        var (focus, has_focus) = testing.focused(&r.h)
        if !has_focus {
            // The first Tab of a page with nothing focused may land anywhere; after
            // a stop, a Tab that leaves nothing focused has lost the focus.
            if count > 0usize { note(r, .FocusLost, last_role, last_label, last_bounds, f32(count)) }
            let resettled = tab_and_settle(r)
            if resettled != ok { ret (count, resettled) }
            let (again, again_has) = testing.focused(&r.h)
            if !again_has { break }
            focus = again
        }
        let id = node_id(r, focus)
        if count > 0usize && id.slot == last.slot && id.generation == last.generation {
            note(r, .FocusTrap, last_role, last_label, last_bounds, f32(count))
            break
        }
        var cycled = false
        var k = 0usize
        while k < count {
            if stops[k].slot == id.slot && stops[k].generation == id.generation { cycled = true }
            k += 1usize
        }
        if cycled { break }
        stops[count] = id
        count += 1usize
        last = id
        var bytes = r.shot_a
        if use_b { bytes = r.shot_b }
        use_b = !use_b
        let (now_shot, now_error) = shot_in(r, bytes)
        if now_error != ok { ret (count, now_error) }
        let (t, t_error) = tree_in(r, r.tree_bytes)
        if t_error != ok { ret (count, t_error) }
        let (at, found) = find_node(&t, id)
        if found {
            let n = &t.nodes[at]
            last_role = n.role
            last_label = n.label
            last_bounds = n.bounds
            if !on_surface(r, n.bounds) {
                note_node(r, .FocusObscured, n, 0.0)
            } else if !region_differs(previous, now_shot, n.bounds) {
                note_node(r, .FocusVisible, n, 0.0)
            }
        }
        previous = now_shot
    }
    var i = 0usize
    while i < start.nodes.len {
        let n = &start.nodes[i]
        if interactive(n) && !disabled_here(&start, i) && !reached(&start, i, stops[0usize..count]) { note_node(r, .Reach, n, 0.0) }
        i += 1usize
    }
    ret (count, ok)
}
