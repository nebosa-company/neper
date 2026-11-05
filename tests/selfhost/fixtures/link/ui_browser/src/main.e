// `e.ui.browser` (browser tracker 7.1, 7.2): one browsing context as a control over `e.web.shell` and `e.web.page`.
// Navigation and the session history run through the control, `state` reports what a caller's chrome reads, a failed
// load leaves the error page, the renderer is bound once to each page (a reload's new page included), the pump is
// quiet on a static page, and a page tab hands out a canvas and a region.
use e.fs
use e.gfx.geometry as geo
use e.gfx.scene as scene
use e.gpu
use e.mem
use e.net.fetch as fetch
use e.os
use e.str
use e.text.fontset as fontset
use e.ui.accessibility as acc
use e.ui.browser as browser
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.web.shell as shell

const RED: u32 = 4294901760u32
const BLUE: u32 = 4278190335u32
const WHITE: u32 = 4294967295u32

fn pointer(x: f32, y: f32) -> input.Pointer {
    ret input.Pointer { window: zero, device: 0u32, pointer: 0u32, kind: .Mouse, position: geo.Point { x: x, y: y }, buttons: 1u32, changed: .Primary }
}

fn key(code: u32) -> input.KeyEvent {
    ret input.KeyEvent { window: zero, key: input.Key { physical: code, logical: code }, modifiers: zero, repeat: false }
}

fn data_page(a: *mem.Arena, title: str) -> str {
    let (s, e) = str.concat(a, "data:text/html,<title>", title)
    let (s2, e2) = str.concat(a, s, "</title><p>x</p>")
    ret s2
}

fn find_label(t: *const acc.Tree, label: str) -> (usize, bool) {
    var i = 0usize
    while i < t.nodes.len {
        if str.eq(t.nodes[i].label, label) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn sized(w: f32, h: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: w }
    s.height = style.Length { Px: h }
    ret s
}

fn has_action(actions: []const acc.Action, want: acc.Action) -> bool {
    var i = 0usize
    while i < actions.len {
        if actions[i] == want { ret true }
        i += 1usize
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (made, me) = fontset.new(a)
    if me != ok { os.exit(1i32) }
    var fonts = made
    let (data, fe) = fs.read_file(a, "tests/browser/assets/ahem.ttf", 16777216usize)
    if fe != ok { os.exit(2i32) }
    if fontset.add(&fonts, "Ahem", 400u32, false, data, 0u32) != ok { os.exit(3i32) }
    fontset.set_generic(&fonts, "sans-serif", "Ahem")
    let (cl, ce) = fetch.client(a, fetch.default_config(""), 16usize)
    if ce != ok { os.exit(4i32) }
    var client = cl
    let (sh, se) = shell.new(a, &client, &fonts, 400.0f32, 200.0f32)
    if se != ok { os.exit(5i32) }
    let (t, e) = shell.open_tab(sh, "about:blank")
    if e != ok { os.exit(6i32) }
    var b = browser.attach(sh, t)
    // The new-tab state.
    var st = browser.state(&b)
    if !st.ready || !str.eq(st.title, "New tab") || !str.eq(st.url, "about:blank") { os.exit(20i32) }
    if st.can_back || st.can_forward || st.error_text.len != 0usize { os.exit(21i32) }
    if !browser.has_page(&b) { os.exit(22i32) }
    // A navigation through the control, then another; the history follows.
    if browser.navigate(&b, data_page(a, "one")) != ok { os.exit(23i32) }
    st = browser.state(&b)
    if !str.eq(st.title, "one") || !st.can_back || st.can_forward { os.exit(24i32) }
    if browser.navigate(&b, data_page(a, "two")) != ok { os.exit(25i32) }
    if !str.eq(browser.state(&b).title, "two") { os.exit(26i32) }
    if !browser.back(&b) { os.exit(27i32) }
    st = browser.state(&b)
    if !str.eq(st.title, "one") || !st.can_forward { os.exit(28i32) }
    if !browser.forward(&b) || !str.eq(browser.state(&b).title, "two") { os.exit(29i32) }
    if !browser.back(&b) || !str.eq(browser.state(&b).title, "one") { os.exit(30i32) }
    // A reload gives the tab a new page; the renderer is bound to it once and a second call changes nothing.
    browser.reload(&b)
    if !browser.has_page(&b) || !str.eq(browser.state(&b).title, "one") { os.exit(33i32) }
    if b.tab.pg.has_renderer { os.exit(34i32) }
    let (device, de) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if de != ok { os.exit(35i32) }
    let (q, qe) = gpu.queue(device)
    if qe != ok { os.exit(35i32) }
    let (rv, re) = scene.renderer(a, device, q, 8u32, 4u32)
    if re != ok { os.exit(36i32) }
    var renderer = rv
    browser.ensure_renderer(&b, &renderer)
    if !b.tab.pg.has_renderer { os.exit(37i32) }
    browser.ensure_renderer(&b, &renderer)
    if !b.tab.pg.has_renderer { os.exit(38i32) }
    // The pump is quiet on a static page and no timer is due.
    if browser.pump(&b, 0.0f64) { os.exit(39i32) }
    if browser.timer_due(&b, 0.0f64) { os.exit(40i32) }
    // The widgets a page tab hands to the caller.
    let c = browser.canvas(&b)
    if mem.address_of(c.ctx) == 0usize { os.exit(41i32) }
    let r = browser.region(&b)
    if !r.enabled { os.exit(42i32) }
    // Media preferences reach the page's style: the colour scheme picks the rule, reduced motion the height. The page is
    // loaded first (light, no preference), then the preference changes and the same page paints differently.
    let styled = "data:text/html,<style>body{margin:0;background:white}div{width:40px;height:20px;background:red}@media (prefers-color-scheme:dark){div{background:blue}}@media (prefers-reduced-motion:reduce){div{height:40px}}</style><div></div>"
    if browser.navigate(&b, styled) != ok { os.exit(50i32) }
    let side = 64usize
    let (frames, fre) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(side), u32(side), gpu.Format.Bgra8)
    if fre != ok { os.exit(51i32) }
    let (canvas, cve) = scene.target_of(a, frames)
    if cve != ok { os.exit(51i32) }
    let (pixels, pxe) = mem.alloc[u32](a, side * side)
    if pxe != ok { os.exit(52i32) }
    // Light, no reduced motion: a 20 px red block over a white body.
    let (bv, be) = scene.builder(a, 4096usize)
    if be != ok { os.exit(53i32) }
    var builder = bv
    let c0 = browser.canvas(&b)
    if c0.paint(c0.ctx, &builder, geo.rect(0.0, 0.0, 64.0, 64.0)) != ok { os.exit(53i32) }
    let (id0, ce0) = scene.compile(&renderer, scene.finish(&builder))
    if ce0 != ok { os.exit(53i32) }
    if scene.render(&renderer, id0, canvas, geo.Size { width: 64.0, height: 64.0 }) != ok { os.exit(53i32) }
    let (image0, im0) = gpu.presented(frames)
    if im0 != ok { os.exit(53i32) }
    if gpu.read_image(q, image0, pixels) != ok { os.exit(53i32) }
    if pixels[10usize * side + 10usize] != RED { os.exit(54i32) }
    if pixels[30usize * side + 10usize] != WHITE { os.exit(55i32) }
    // Dark and reduced motion: the block is blue and 40 px tall.
    browser.set_preferences(&b, true, true)
    let (bv2, be2) = scene.builder(a, 4096usize)
    if be2 != ok { os.exit(56i32) }
    var builder2 = bv2
    let c1 = browser.canvas(&b)
    if c1.paint(c1.ctx, &builder2, geo.rect(0.0, 0.0, 64.0, 64.0)) != ok { os.exit(56i32) }
    let (id1, ce1) = scene.compile(&renderer, scene.finish(&builder2))
    if ce1 != ok { os.exit(56i32) }
    if scene.render(&renderer, id1, canvas, geo.Size { width: 64.0, height: 64.0 }) != ok { os.exit(56i32) }
    let (image1, im1) = gpu.presented(frames)
    if im1 != ok { os.exit(56i32) }
    if gpu.read_image(q, image1, pixels) != ok { os.exit(56i32) }
    if pixels[10usize * side + 10usize] != BLUE { os.exit(57i32) }
    if pixels[30usize * side + 10usize] != BLUE { os.exit(58i32) }
    // A page loaded after the preference was set is laid out with it from the start.
    if browser.navigate(&b, styled) != ok || !browser.state(&b).ready { os.exit(59i32) }
    // The page's accessibility tree: roles and names from the document, numbered above the widget tree's slots.
    let content = "data:text/html,<h1>Title</h1><p>Hello<a href=/x>link</a></p><button>Go</button>"
    if browser.navigate(&b, content) != ok { os.exit(61i32) }
    let (tree, te) = browser.a11y_tree(&b, a)
    if te != ok || tree.nodes.len == 0usize { os.exit(62i32) }
    let (hi, hf) = find_label(&tree, "Title")
    if !hf || tree.nodes[hi].role != acc.Role.Heading || tree.nodes[hi].level != 1u8 { os.exit(63i32) }
    let (li, lf) = find_label(&tree, "link")
    if !lf || tree.nodes[li].role != acc.Role.Link || !str.eq(tree.nodes[li].hint, "/x") { os.exit(64i32) }
    let (bi, bf) = find_label(&tree, "Go")
    if !bf || tree.nodes[bi].role != acc.Role.Button { os.exit(65i32) }
    let (ti, tf) = find_label(&tree, "Hello")
    if !tf || tree.nodes[ti].role != acc.Role.Text { os.exit(66i32) }
    // The ids are the page's own slots, away from the widget tree's.
    if tree.nodes[hi].id.slot < 2147483648u32 { os.exit(67i32) }
    // A runtime that holds the semantics wrapper publishes the same document under the canvas: the builder splices
    // the provider's nodes in, so a screen reader sees the heading, not an empty custom widget.
    let (rt, rte) = widget.runtime(a, &renderer, widget.Limits { max_elements: 32usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 64usize })
    if rte != ok { os.exit(70i32) }
    var runtime = rt
    let (kids, kse) = mem.alloc[widget.Node](a, 1usize)
    if kse != ok { os.exit(70i32) }
    kids[0] = widget.Node { key: 2u64, kind: widget.Kind { Custom: browser.canvas(&b) }, style: sized(64.0, 64.0), children: zero }
    let root = widget.semantics(1u64, browser.semantics(&b), sized(64.0, 64.0), kids[0usize..1usize])
    let (widget_frame, wfe) = mem.alloc[u8](a, 262144usize)
    if wfe != ok { os.exit(71i32) }
    var frame = mem.arena_from(widget_frame)
    let (compiled, wre) = widget.reconcile(&runtime, &frame, root, ui_layout.Constraints { min_width: 0.0, max_width: 64.0, min_height: 0.0, max_height: 64.0 })
    if wre != ok { os.exit(72i32) }
    let (published, pe2) = acc.build(a, &runtime)
    if pe2 != ok { os.exit(72i32) }
    let (shown, shown_found) = find_label(&published, "Title")
    if !shown_found || published.nodes[shown].role != acc.Role.Heading { os.exit(73i32) }
    if published.nodes[shown].id.slot < 2147483648u32 { os.exit(74i32) }
    let (linked, linked_found) = find_label(&published, "link")
    if !linked_found || published.nodes[linked].role != acc.Role.Link { os.exit(75i32) }
    // The heading carries the box layout gave it, and the link offers a press.
    if published.nodes[shown].bounds.width <= 0.0 || published.nodes[shown].bounds.height <= 0.0 { os.exit(77i32) }
    if !has_action(published.nodes[linked].actions, acc.Action.Press) { os.exit(78i32) }
    if widget.close(&runtime) != ok { os.exit(76i32) }
    // Keyboard scrolling (7.3): a tap focuses the page's scroll region and PageDown reaches the scope above it, which
    // scrolls the document.
    let tall = "data:text/html,<div style=height:400px>text</div>"
    if browser.navigate(&b, tall) != ok { os.exit(80i32) }
    let (kt, kte) = widget.runtime(a, &renderer, widget.Limits { max_elements: 32usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 64usize })
    if kte != ok { os.exit(81i32) }
    var kruntime = kt
    let (canvas_kids, cke) = mem.alloc[widget.Node](a, 1usize)
    if cke != ok { os.exit(81i32) }
    canvas_kids[0] = widget.Node { key: 4u64, kind: widget.Kind { Custom: browser.canvas(&b) }, style: sized(64.0, 64.0), children: zero }
    let (sem_kids, sme) = mem.alloc[widget.Node](a, 1usize)
    if sme != ok { os.exit(81i32) }
    sem_kids[0] = widget.semantics(3u64, browser.semantics(&b), sized(64.0, 64.0), canvas_kids[0usize..1usize])
    let (scroll_kids, ske) = mem.alloc[widget.Node](a, 1usize)
    if ske != ok { os.exit(81i32) }
    scroll_kids[0] = widget.region(2u64, browser.region(&b), sized(64.0, 64.0), sem_kids[0usize..1usize])
    let kroot = widget.scope(1u64, widget.Scope { traps_focus: false, shortcuts: zero, default_action: zero, cancel_action: zero, keys: browser.keys(&b) }, sized(64.0, 64.0), scroll_kids[0usize..1usize])
    let (kframe_storage, kfe) = mem.alloc[u8](a, 262144usize)
    if kfe != ok { os.exit(81i32) }
    var kframe = mem.arena_from(kframe_storage)
    let (kcompiled, kre) = widget.reconcile(&kruntime, &kframe, kroot, ui_layout.Constraints { min_width: 0.0, max_width: 64.0, min_height: 0.0, max_height: 64.0 })
    if kre != ok { os.exit(82i32) }
    if widget.dispatch(&kruntime, input.Event { PointerDown: pointer(10.0, 10.0) }) != ok { os.exit(83i32) }
    if widget.dispatch(&kruntime, input.Event { PointerUp: pointer(10.0, 10.0) }) != ok { os.exit(83i32) }
    if widget.dispatch(&kruntime, input.Event { KeyDown: key(34u32) }) != ok { os.exit(84i32) }
    if b.tab.pg.view.scroll_y <= 0.0 { os.exit(85i32) }
    if widget.close(&kruntime) != ok { os.exit(86i32) }
    // A load the engine cannot do leaves the error page, and the history keeps the attempt.
    if browser.navigate(&b, "ftp://nowhere.test/file") != ok { os.exit(43i32) }
    st = browser.state(&b)
    if !st.ready || st.error_text.len == 0usize { os.exit(44i32) }
    if !browser.back(&b) || browser.state(&b).error_text.len != 0usize { os.exit(45i32) }
    ret ok
}
