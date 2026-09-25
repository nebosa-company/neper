// The v2 page view, carousel, pull to refresh, swipe actions and reorderable
// list (D982, widget plan P5-12, docs/ux/components/PageView, Carousel,
// PullToRefresh, SwipeActions, ReorderableList) under the light theme: a
// `radius-md` page view whose tonal Next button shows under the pointer, whose
// strip follows a reading-direction drag and turns past half its width; a multi-browse carousel of
// a 256 large, a 200 medium and a 56 small item under a header with outlined
// Previous and Next; a pointer refresh button with F5 and a busy bar, and a
// touch pull whose content follows the damped pull under an indicator armed
// past 80 that refreshes on release and rests 12 down while refreshing; a row
// that slides over its 80 wide action tiles, opens past 40%, closes on Escape,
// runs Delete on a full swipe and offers hover buttons; and a reorderable list
// whose dragged row lifts over a `surface-container-low` gap as the others
// make room.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.collection
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

const W: usize = 900usize

type Store = struct { page: usize, slide: usize, refreshing: bool, at_top: bool, refreshes: usize, revealed: bool, archives: usize, deletes: usize, presses: usize, moves: usize, moved: collection.Reorder, refresh: widget.Submit, press: widget.Submit, slides: [5]collection.CarouselItem, actions: [2]collection.SwipeAction, rows: [3]collection.RowItem }

fn on_page(ctx: *void, value: usize) -> err {
    let s = mem.cast[*Store](ctx)
    s.page = value
    ret ok
}

fn on_slide(ctx: *void, value: usize) -> err {
    let s = mem.cast[*Store](ctx)
    s.slide = value
    ret ok
}

fn on_refresh(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.refreshes += 1usize
    ret ok
}

fn on_press(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.presses += 1usize
    ret ok
}

fn on_archive(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.archives += 1usize
    ret ok
}

fn on_delete(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.deletes += 1usize
    ret ok
}

fn on_reveal(ctx: *void, value: bool) -> err {
    let s = mem.cast[*Store](ctx)
    s.revealed = value
    ret ok
}

fn on_move(ctx: *void, value: collection.Reorder) -> err {
    let s = mem.cast[*Store](ctx)
    s.moves += 1usize
    s.moved = value
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
}

fn tinted(t: *const control.Theme, role: style.ColorRole, w: f32, h: f32) -> widget.Node {
    var box_style = control.sized_style(w, h)
    box_style.background = paint.Brush { Solid: style.color(t.tokens, role) }
    ret widget.box(0u64, box_style, zero)
}

fn build(a: *mem.Arena, t: *const control.Theme, touch: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let ctx = mem.cast[*void](s)
    let (pages, pages_error) = mem.alloc[widget.Node](a, 3usize)
    if pages_error != ok { ret (zero, pages_error) }
    pages[0usize] = tinted(t, .PrimaryContainer, 240.0, 120.0)
    pages[1usize] = tinted(t, .TertiaryContainer, 240.0, 120.0)
    pages[2usize] = tinted(t, .ErrorContainer, 240.0, 120.0)
    var viewing = collection.page_view_options()
    viewing.label = "Intro"
    viewing.width = 240.0
    viewing.height = 120.0
    let (view, e1) = collection.page_view_of(a, 100u64, t, pages[0usize..3usize], s.page, widget.Change[usize] { ctx: ctx, invoke: on_page }, viewing)
    var slide_keys: [5]widget.Key = zero
    var i = 0usize
    while i < 5usize {
        slide_keys[i] = 211u64 + u64(i)
        i += 1usize
    }
    var browsing = collection.carousel_options()
    browsing.title = "Recent"
    browsing.width = 560.0
    let (strip, e2) = collection.carousel_of(a, 200u64, t, "Recent", s.slides[0usize..5usize], slide_keys[..], s.slide, widget.Change[usize] { ctx: ctx, invoke: on_slide }, browsing)
    var pulling = collection.pull_options()
    pulling.label = "Refresh builds"
    pulling.width = 240.0
    pulling.height = 120.0
    let (desk, e3) = collection.pull_to_refresh_of(a, 300u64, t, tinted(t, .SecondaryContainer, 240.0, 200.0), s.refreshing, &s.refresh, pulling)
    pulling.height = 160.0
    pulling.at_top = s.at_top
    let (phone, e4) = collection.pull_to_refresh_of(a, 400u64, touch, tinted(t, .TertiaryContainer, 240.0, 200.0), s.refreshing, &s.refresh, pulling)
    var swiping = collection.swipe_options()
    swiping.width = 300.0
    swiping.height = 56.0
    let (row, e5) = collection.swipe_actions_of(a, 500u64, t, widget.box(0u64, control.sized_style(10.0, 10.0), zero), s.actions[0usize..2usize], s.revealed, widget.Change[bool] { ctx: ctx, invoke: on_reveal }, swiping)
    var row_keys: [3]widget.Key = zero
    row_keys[0usize] = 611u64
    row_keys[1usize] = 612u64
    row_keys[2usize] = 613u64
    let (ordered, e6) = collection.reorderable_list_of(a, 600u64, t, "Priorities", s.rows[0usize..3usize], row_keys[..], widget.Change[collection.Reorder] { ctx: ctx, invoke: on_move }, 280.0)
    var touch_keys: [3]widget.Key = zero
    touch_keys[0usize] = 631u64
    touch_keys[1usize] = 632u64
    touch_keys[2usize] = 633u64
    let (touch_ordered, e7) = collection.reorderable_list_of(a, 620u64, touch, "Touch priorities", s.rows[0usize..3usize], touch_keys[..], widget.Change[collection.Reorder] { ctx: ctx, invoke: on_move }, 280.0)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (zero, e1) }
    let (left, left_error) = mem.alloc[widget.Node](a, 4usize)
    if left_error != ok { ret (zero, left_error) }
    left[0usize] = view
    left[1usize] = desk
    left[2usize] = phone
    left[3usize] = ordered
    let (right, right_error) = mem.alloc[widget.Node](a, 3usize)
    if right_error != ok { ret (zero, right_error) }
    right[0usize] = strip
    right[1usize] = row
    right[2usize] = touch_ordered
    let (sides, sides_error) = mem.alloc[widget.Node](a, 2usize)
    if sides_error != ok { ret (zero, sides_error) }
    var left_style = style.defaults()
    left_style.width = style.Length { Px: 280.0 }
    sides[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, left_style, left[0usize..4usize])
    sides[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, style.defaults(), right[0usize..3usize])
    var page = style.defaults()
    page.width = style.Length { Px: 900.0 }
    page.height = style.Length { Px: 780.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 16.0 }, page, sides[0usize..2usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * W + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn focused_is(h: *testing.Harness, key: widget.Key) -> bool {
    let (id, has) = testing.focused(h)
    ret has && id.slot == testing.by_key(h, key).element.slot
}

fn tab_to(h: *testing.Harness, key: widget.Key) -> bool {
    var tabs = 0usize
    while !focused_is(h, key) && tabs < 80usize {
        if testing.tab(h, false) != ok { ret false }
        tabs += 1usize
    }
    ret focused_is(h, key)
}

fn press(h: *testing.Harness, x: f32, y: f32) -> bool {
    ret testing.send(h, input.Event { PointerDown: testing.pointer_at(x, y) }) == ok
}

fn move_to(h: *testing.Harness, x: f32, y: f32) -> bool {
    ret testing.send(h, input.Event { PointerMove: testing.pointer_at(x, y) }) == ok
}

fn release(h: *testing.Harness, x: f32, y: f32) -> bool {
    ret testing.send(h, input.Event { PointerUp: testing.pointer_at(x, y) }) == ok
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        let n = tree.nodes[i]
        if n.role == role && n.label.len == label.len {
            var same = true
            var k = 0usize
            while k < label.len {
                if n.label[k] != label[k] { same = false }
                k += 1usize
            }
            if same { ret (n, true) }
        }
        i += 1usize
    }
    ret (zero, false)
}

fn politely_says(h: *testing.Harness, label: str) -> bool {
    let (tree, tree_error) = testing.semantics(h)
    if tree_error != ok { ret false }
    let (said, has_said) = find(tree, .Status, label)
    ret has_said && said.live == .Polite
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let tokens = style.reference(.Light)
    let touch_tokens = style.adapt(&tokens, style.Adaptation { size: .Expanded, capabilities: style.Capabilities { hover: false, fine_pointer: false, keyboard: false, touch: true, pen: false, resizable: false, multi_window: false, insets: zero }, profile: .Touch })
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 1200usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 40u16, max_commands: 4096usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let touch = control.Theme { tokens: &touch_tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 900u32, 780u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    let ctx = mem.cast[*void](s)
    s.refresh = widget.Submit { ctx: ctx, invoke: on_refresh }
    s.press = widget.Submit { ctx: ctx, invoke: on_press }
    s.at_top = true
    s.slides[0usize] = collection.carousel_item("Builds")
    s.slides[0usize].tone = .Primary
    s.slides[1usize] = collection.carousel_item("Tests")
    s.slides[1usize].tone = .Secondary
    s.slides[2usize] = collection.carousel_item("Docs")
    s.slides[2usize].tone = .Tertiary
    s.slides[3usize] = collection.carousel_item("Logs")
    s.slides[4usize] = collection.carousel_item("Assets")
    var i = 0usize
    while i < 5usize {
        s.slides[i].action = s.press
        i += 1usize
    }
    s.actions[0usize] = collection.SwipeAction { label: "Archive", glyph: .Check, tone: .Neutral, action: widget.Submit { ctx: ctx, invoke: on_archive } }
    s.actions[1usize] = collection.SwipeAction { label: "Delete", glyph: .Cross, tone: .Destructive, action: widget.Submit { ctx: ctx, invoke: on_delete } }
    s.rows[0usize] = collection.row_item("First")
    s.rows[1usize] = collection.row_item("Second")
    s.rows[2usize] = collection.row_item("Third")
    i = 0usize
    while i < 3usize {
        s.rows[i].action = s.press
        i += 1usize
    }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 8388608usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let background = style.color(&tokens, .Background)
    let (root, build_error) = build(&f, &theme, &touch, s)
    if build_error != ok || testing.pump(&harness, root, now) != ok { os.exit(9i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(10i32) }
    // The page view: 240 x 120 with `radius-md` corners over the page; the
    // indicator 12 below; no buttons until the pointer comes.
    let (view, has_view) = bounds(&harness, &runtime, 100u64)
    if !has_view || !near(view.width, 240.0) || !near(view.height, 120.0) { os.exit(11i32) }
    if !is_color(shot, at(view.x + 120.0, view.y + 60.0), style.color(&tokens, .PrimaryContainer)) || !is_color(shot, at(view.x + 0.5, view.y + 0.5), background) { os.exit(12i32) }
    let (dots, has_dots) = bounds(&harness, &runtime, 104u64)
    if !has_dots || !near(dots.y, view.y + 132.0) || testing.by_key(&harness, 102u64).count != 0usize { os.exit(13i32) }
    // Under the pointer the tonal Next shows 12 in from the end, and turns.
    if testing.hover(&harness, view.x + 120.0, view.y + 60.0) != ok { os.exit(14i32) }
    let (root_2, build_2_error) = build(&f, &theme, &touch, s)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(15i32) }
    let (shot_2, shot_2_error) = testing.snapshot(&harness, a)
    if shot_2_error != ok { os.exit(16i32) }
    let (next, has_next) = bounds(&harness, &runtime, 102u64)
    if !has_next || testing.by_key(&harness, 101u64).count != 0usize || !near(next.x, view.x + 188.0) || !near(next.y, view.y + 40.0) { os.exit(17i32) }
    if !is_color(shot_2, at(next.x + 6.0, next.y + 20.0), style.color(&tokens, .SecondaryContainer)) { os.exit(18i32) }
    if testing.tap(&harness, next.x + 20.0, next.y + 20.0) != ok || s.page != 1usize { os.exit(19i32) }
    // A drag moves the strip: the next page comes in from the end; the release
    // past half the width turns.
    let (root_3, build_3_error) = build(&f, &theme, &touch, s)
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(20i32) }
    if !press(&harness, view.x + 200.0, view.y + 100.0) || !move_to(&harness, view.x + 150.0, view.y + 100.0) || !move_to(&harness, view.x + 120.0, view.y + 100.0) { os.exit(21i32) }
    let (root_4, build_4_error) = build(&f, &theme, &touch, s)
    if build_4_error != ok || testing.pump(&harness, root_4, now) != ok { os.exit(22i32) }
    let (shot_4, shot_4_error) = testing.snapshot(&harness, a)
    if shot_4_error != ok { os.exit(23i32) }
    if !is_color(shot_4, at(view.x + 220.0, view.y + 100.0), style.color(&tokens, .ErrorContainer)) || !is_color(shot_4, at(view.x + 150.0, view.y + 100.0), style.color(&tokens, .TertiaryContainer)) || !is_color(shot_4, at(view.x + 170.0, view.y + 100.0), style.color(&tokens, .ErrorContainer)) { os.exit(24i32) }
    if !move_to(&harness, view.x + 60.0, view.y + 100.0) || !release(&harness, view.x + 60.0, view.y + 100.0) || s.page != 2usize { os.exit(25i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(26i32) }
    let (intro, has_intro) = find(tree, .Group, "Intro")
    if !has_intro || intro.live != .Polite { os.exit(27i32) }
    // The carousel: 16 in, a 256 large, a 200 medium and a 56 small item 8
    // apart, `radius-md`, tone-filled; outlined Previous (disabled) and Next.
    let (large, has_large) = bounds(&harness, &runtime, 211u64)
    let (medium, has_medium) = bounds(&harness, &runtime, 212u64)
    let (small, has_small) = bounds(&harness, &runtime, 213u64)
    let (strip, has_strip) = bounds(&harness, &runtime, 200u64)
    if !has_large || !has_medium || !has_small || !has_strip || testing.by_key(&harness, 214u64).count != 0usize { os.exit(28i32) }
    if !near(large.x, strip.x + 16.0) || !near(large.width, 256.0) || !near(large.height, 200.0) || !near(medium.x, large.x + 264.0) || !near(medium.width, 200.0) || !near(small.width, 56.0) { os.exit(29i32) }
    if !is_color(shot, at(large.x + 128.0, large.y + 100.0), style.color(&tokens, .PrimaryContainer)) || !is_color(shot, at(medium.x + 100.0, medium.y + 100.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(large.x + 0.5, large.y + 0.5), background) { os.exit(30i32) }
    let (previous_button, has_previous_button) = find(tree, .Button, "Previous")
    let (next_button, has_next_button) = find(tree, .Button, "Next")
    if !has_previous_button || !previous_button.state.disabled || !has_next_button || next_button.state.disabled { os.exit(31i32) }
    let (forward, has_forward) = bounds(&harness, &runtime, 202u64)
    if !has_forward || !near(forward.width, 40.0) || testing.tap(&harness, forward.x + 20.0, forward.y + 20.0) != ok || s.slide != 1usize { os.exit(32i32) }
    if testing.tap(&harness, large.x + 128.0, large.y + 100.0) != ok || s.presses != 1usize { os.exit(33i32) }
    // The pointer refresh: a 40 button at the end, F5 from within; refreshing,
    // the button is disabled and the busy bar shows.
    let (again, has_again) = bounds(&harness, &runtime, 301u64)
    let (desk, has_desk) = bounds(&harness, &runtime, 300u64)
    if !has_again || !has_desk || !near(again.width, 40.0) || !near(again.x + 40.0, desk.x + 240.0) { os.exit(34i32) }
    if testing.tap(&harness, again.x + 20.0, again.y + 20.0) != ok || s.refreshes != 1usize { os.exit(35i32) }
    if !tab_to(&harness, 301u64) || testing.press_key(&harness, 116u32, zero) != ok || s.refreshes != 2usize { os.exit(36i32) }
    // The touch pull: 150 of travel is a pull of 95, armed; the indicator
    // `primary-container`; the release refreshes.
    let (phone, has_phone) = bounds(&harness, &runtime, 400u64)
    if !has_phone || !press(&harness, phone.x + 120.0, phone.y + 20.0) || !move_to(&harness, phone.x + 120.0, phone.y + 60.0) || !move_to(&harness, phone.x + 120.0, phone.y + 170.0) { os.exit(37i32) }
    let (root_5, build_5_error) = build(&f, &theme, &touch, s)
    if build_5_error != ok || testing.pump(&harness, root_5, now) != ok { os.exit(38i32) }
    let (shot_5, shot_5_error) = testing.snapshot(&harness, a)
    if shot_5_error != ok { os.exit(39i32) }
    if !is_color(shot_5, at(phone.x + 104.0, phone.y + 41.0), style.color(&tokens, .PrimaryContainer)) || !is_color(shot_5, at(phone.x + 10.0, phone.y + 90.0), background) || !is_color(shot_5, at(phone.x + 10.0, phone.y + 100.0), style.color(&tokens, .TertiaryContainer)) { os.exit(40i32) }
    if !release(&harness, phone.x + 120.0, phone.y + 170.0) || s.refreshes != 3usize { os.exit(41i32) }
    s.refreshing = true
    let (root_6, build_6_error) = build(&f, &theme, &touch, s)
    if build_6_error != ok || testing.pump(&harness, root_6, now) != ok { os.exit(42i32) }
    let (shot_6, shot_6_error) = testing.snapshot(&harness, a)
    if shot_6_error != ok { os.exit(43i32) }
    if !is_color(shot_6, at(phone.x + 104.0, phone.y + 32.0), style.color(&tokens, .SurfaceContainerHigh)) || !is_color(shot_6, at(phone.x + 10.0, phone.y + 70.0), style.color(&tokens, .TertiaryContainer)) || !is_color(shot_6, at(phone.x + 10.0, phone.y + 60.0), background) { os.exit(44i32) }
    if testing.by_key(&harness, 303u64).count == 0usize { os.exit(45i32) }
    let (tree_6, tree_6_error) = testing.semantics(&harness)
    if tree_6_error != ok { os.exit(46i32) }
    let (busy, has_busy) = find(tree_6, .Button, "Refresh builds")
    if !has_busy || !busy.state.disabled { os.exit(47i32) }
    s.refreshing = false
    s.at_top = false
    let (root_not_top, root_not_top_error) = build(&f, &theme, &touch, s)
    if root_not_top_error != ok || testing.pump(&harness, root_not_top, now) != ok { os.exit(76i32) }
    let (not_top, has_not_top) = bounds(&harness, &runtime, 400u64)
    if !has_not_top || testing.drag(&harness, geometry.Point { x: not_top.x + 120.0, y: not_top.y + 20.0 }, geometry.Point { x: not_top.x + 120.0, y: not_top.y + 170.0 }, 4usize) != ok || s.refreshes != 3usize { os.exit(77i32) }
    s.at_top = true
    // Swipe actions: nothing behind a closed row; a drag past 40% of 160 opens
    // it, the tiles 80 wide in `secondary-container` and `error`; Escape closes;
    // a full swipe runs Delete.
    let (row, has_row) = bounds(&harness, &runtime, 500u64)
    if !has_row || !is_color(shot, at(row.x + 290.0, row.y + 5.0), background) { os.exit(48i32) }
    if !press(&harness, row.x + 250.0, row.y + 50.0) || !move_to(&harness, row.x + 200.0, row.y + 50.0) || !move_to(&harness, row.x + 150.0, row.y + 50.0) || !release(&harness, row.x + 150.0, row.y + 50.0) || !s.revealed { os.exit(49i32) }
    let (root_7, build_7_error) = build(&f, &theme, &touch, s)
    if build_7_error != ok || testing.pump(&harness, root_7, now) != ok { os.exit(50i32) }
    let (shot_7, shot_7_error) = testing.snapshot(&harness, a)
    if shot_7_error != ok { os.exit(51i32) }
    let (slid, has_slid) = bounds(&harness, &runtime, 500u64)
    if !has_slid || !near(slid.x, row.x - 160.0) || !is_color(shot_7, at(row.x + 290.0, row.y + 5.0), style.color(&tokens, .Error)) || !is_color(shot_7, at(row.x + 150.0, row.y + 5.0), style.color(&tokens, .SecondaryContainer)) { os.exit(52i32) }
    // A revealed tile runs and closes the row.
    if testing.tap(&harness, row.x + 180.0, row.y + 28.0) != ok || s.archives != 1usize || s.revealed { os.exit(78i32) }
    let (root_tile_closed, root_tile_closed_error) = build(&f, &theme, &touch, s)
    if root_tile_closed_error != ok || testing.pump(&harness, root_tile_closed, now) != ok { os.exit(79i32) }
    if !press(&harness, row.x + 250.0, row.y + 50.0) || !move_to(&harness, row.x + 200.0, row.y + 50.0) || !move_to(&harness, row.x + 150.0, row.y + 50.0) || !release(&harness, row.x + 150.0, row.y + 50.0) || !s.revealed { os.exit(80i32) }
    let (root_tile_open, root_tile_open_error) = build(&f, &theme, &touch, s)
    if root_tile_open_error != ok || testing.pump(&harness, root_tile_open, now) != ok { os.exit(81i32) }
    if !tab_to(&harness, 500u64) || testing.press_key(&harness, 27u32, zero) != ok || s.revealed { os.exit(53i32) }
    let (root_8, build_8_error) = build(&f, &theme, &touch, s)
    if build_8_error != ok || testing.pump(&harness, root_8, now) != ok { os.exit(54i32) }
    if !press(&harness, row.x + 280.0, row.y + 50.0) || !move_to(&harness, row.x + 230.0, row.y + 50.0) || !move_to(&harness, row.x + 60.0, row.y + 50.0) || !release(&harness, row.x + 60.0, row.y + 50.0) || s.deletes != 1usize || s.revealed { os.exit(55i32) }
    // Under the pointer the actions are hover buttons at the row's end.
    if testing.hover(&harness, row.x + 100.0, row.y + 28.0) != ok { os.exit(56i32) }
    let (root_9, build_9_error) = build(&f, &theme, &touch, s)
    if build_9_error != ok || testing.pump(&harness, root_9, now) != ok { os.exit(57i32) }
    let (archive, has_archive) = bounds(&harness, &runtime, 508u64)
    if !has_archive || !near(archive.width, 32.0) || !near(archive.x, row.x + 300.0 - 8.0 - 68.0) || testing.tap(&harness, archive.x + 16.0, archive.y + 16.0) != ok || s.archives != 2usize { os.exit(58i32) }
    // (D1200) The row names its tiles as accessibility actions; performing one
    // runs it, and a name the row does not offer is refused.
    let (swipe_tree, swipe_tree_error) = testing.semantics(&harness)
    if swipe_tree_error != ok { os.exit(156i32) }
    var swipe_node: accessibility.Node = zero
    var swipe_nodes = 0usize
    var sn = 0usize
    while sn < swipe_tree.nodes.len {
        let candidate = swipe_tree.nodes[sn]
        if candidate.role == .ListItem && candidate.names.len == 2usize && mem.eq[u8](candidate.names[0usize], "Archive") && mem.eq[u8](candidate.names[1usize], "Delete") {
            swipe_node = candidate
            swipe_nodes += 1usize
        }
        sn += 1usize
    }
    if swipe_nodes != 1usize { os.exit(157i32) }
    if accessibility.perform_named(&runtime, swipe_node.id, "Delete") != ok || s.deletes != 2usize || s.revealed { os.exit(158i32) }
    if accessibility.perform_named(&runtime, swipe_node.id, "Share") == ok || s.archives != 2usize { os.exit(159i32) }
    // The reorderable list: 48 rows, the handle 12 in; a drag of 60 lifts the
    // first row 8 in over the gap where it would land, the second moving up;
    // the release reports 0 to 1; Ctrl+Down moves the focused row.
    let (list_box, has_list_box) = bounds(&harness, &runtime, 600u64)
    let (grip, has_grip) = bounds(&harness, &runtime, 601u64)
    if !has_list_box || !has_grip || !near(grip.x, list_box.x + 12.0) || !near(grip.width, 32.0) { os.exit(59i32) }
    let handle_pixel = at(grip.x + 12.0, grip.y + 14.0)
    if is_color(shot, handle_pixel, style.color(&tokens, .OnSurfaceVariant)) || testing.hover(&harness, grip.x + 16.0, grip.y + 16.0) != ok { os.exit(123i32) }
    let (root_handle, root_handle_error) = build(&f, &theme, &touch, s)
    if root_handle_error != ok || testing.pump(&harness, root_handle, now) != ok { os.exit(124i32) }
    let (shot_handle, shot_handle_error) = testing.snapshot(&harness, a)
    if shot_handle_error != ok || (shot_handle.pixels[handle_pixel] == shot.pixels[handle_pixel] && shot_handle.pixels[handle_pixel + 1usize] == shot.pixels[handle_pixel + 1usize] && shot_handle.pixels[handle_pixel + 2usize] == shot.pixels[handle_pixel + 2usize]) { os.exit(125i32) }
    if !press(&harness, grip.x + 16.0, grip.y + 16.0) || !move_to(&harness, grip.x + 16.0, grip.y + 40.0) || !move_to(&harness, grip.x + 16.0, grip.y + 76.0) { os.exit(60i32) }
    let (root_10, build_10_error) = build(&f, &theme, &touch, s)
    if build_10_error != ok || testing.pump(&harness, root_10, now) != ok { os.exit(61i32) }
    let (shot_10, shot_10_error) = testing.snapshot(&harness, a)
    if shot_10_error != ok { os.exit(62i32) }
    let (lifted, has_lifted) = bounds(&harness, &runtime, 611u64)
    let (second, has_second) = bounds(&harness, &runtime, 612u64)
    if !has_lifted || !has_second || !near(lifted.x, list_box.x + 8.0) || !near(lifted.y, list_box.y + 60.0) || !near(lifted.width, 264.0) || !near(second.y, list_box.y) { os.exit(63i32) }
    if !is_color(shot_10, at(list_box.x + 4.0, list_box.y + 50.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot_10, at(list_box.x + 40.0, list_box.y + 48.0), style.color(&tokens, .Primary)) || !is_color(shot_10, at(list_box.x + 200.0, list_box.y + 84.0), style.layer(style.color(&tokens, .SurfaceContainerHigh), style.color(&tokens, .OnSurface), 0.16)) { os.exit(64i32) }
    if !release(&harness, grip.x + 16.0, grip.y + 76.0) || s.moves != 1usize || s.moved.from != 0usize || s.moved.to != 1usize { os.exit(65i32) }
    let (root_11, build_11_error) = build(&f, &theme, &touch, s)
    if build_11_error != ok || testing.pump(&harness, root_11, now) != ok { os.exit(66i32) }
    if !press(&harness, grip.x + 16.0, grip.y + 16.0) || !move_to(&harness, grip.x + 16.0, list_box.y - 8.0) || !release(&harness, grip.x + 16.0, list_box.y - 8.0) || s.moves != 1usize { os.exit(126i32) }
    let (root_outside, root_outside_error) = build(&f, &theme, &touch, s)
    if root_outside_error != ok || testing.pump(&harness, root_outside, now) != ok || !politely_says(&harness, "Move cancelled") { os.exit(127i32) }
    let beside = list_box.x + list_box.width + 8.0
    if !press(&harness, grip.x + 16.0, grip.y + 16.0) || !move_to(&harness, beside, grip.y + 76.0) || !release(&harness, beside, grip.y + 76.0) || s.moves != 1usize { os.exit(134i32) }
    let (root_beside, root_beside_error) = build(&f, &theme, &touch, s)
    if root_beside_error != ok || testing.pump(&harness, root_beside, now) != ok || !politely_says(&harness, "Move cancelled") { os.exit(135i32) }
    var control_held: input.Modifiers = zero
    control_held.control = true
    if !tab_to(&harness, 612u64) || testing.press_key(&harness, 40u32, control_held) != ok || s.moves != 2usize || s.moved.from != 1usize || s.moved.to != 2usize { os.exit(67i32) }
    let (root_direct, root_direct_error) = build(&f, &theme, &touch, s)
    if root_direct_error != ok || testing.pump(&harness, root_direct, now) != ok || !politely_says(&harness, "Second, moved to position 3 of 3") { os.exit(133i32) }
    // Space picks up the focused row without reporting a move. Arrows and the
    // ends move its gap; Space or Enter drops once, while Escape cancels.
    if !tab_to(&harness, 611u64) || testing.press_key(&harness, 32u32, zero) != ok || s.moves != 2usize { os.exit(106i32) }
    let (root_key_pick, root_key_pick_error) = build(&f, &theme, &touch, s)
    if root_key_pick_error != ok || testing.pump(&harness, root_key_pick, now) != ok { os.exit(107i32) }
    let (shot_key_pick, shot_key_pick_error) = testing.snapshot(&harness, a)
    if shot_key_pick_error != ok || !is_color(shot_key_pick, at(list_box.x + 200.0, list_box.y + 24.0), style.color(&tokens, .SecondaryContainer)) { os.exit(128i32) }
    if !politely_says(&harness, "First, picked up, position 1 of 3") { os.exit(132i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || testing.press_key(&harness, 35u32, zero) != ok || s.moves != 2usize { os.exit(108i32) }
    let (root_key_last, root_key_last_error) = build(&f, &theme, &touch, s)
    if root_key_last_error != ok || testing.pump(&harness, root_key_last, now) != ok { os.exit(109i32) }
    if !politely_says(&harness, "First, moved to position 3 of 3") { os.exit(129i32) }
    let (key_lifted, has_key_lifted) = bounds(&harness, &runtime, 611u64)
    let (key_last, has_key_last) = bounds(&harness, &runtime, 613u64)
    if !has_key_lifted || !has_key_last { os.exit(110i32) }
    if !near(key_lifted.x, list_box.x + 8.0) { os.exit(120i32) }
    if !near(key_lifted.y, list_box.y + 96.0) { os.exit(121i32) }
    if !near(key_last.y, list_box.y + 48.0) { os.exit(122i32) }
    if testing.press_key(&harness, 32u32, zero) != ok || s.moves != 3usize || s.moved.from != 0usize || s.moved.to != 2usize { os.exit(111i32) }
    let (root_key_dropped, root_key_dropped_error) = build(&f, &theme, &touch, s)
    if root_key_dropped_error != ok || testing.pump(&harness, root_key_dropped, now) != ok { os.exit(112i32) }
    if !politely_says(&harness, "First, dropped at position 3 of 3") { os.exit(130i32) }
    if !tab_to(&harness, 612u64) || testing.press_key(&harness, 32u32, zero) != ok { os.exit(113i32) }
    let (root_key_second, root_key_second_error) = build(&f, &theme, &touch, s)
    if root_key_second_error != ok || testing.pump(&harness, root_key_second, now) != ok { os.exit(114i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || testing.press_key(&harness, 36u32, zero) != ok || testing.press_key(&harness, 27u32, zero) != ok || s.moves != 3usize { os.exit(115i32) }
    let (root_key_cancelled, root_key_cancelled_error) = build(&f, &theme, &touch, s)
    if root_key_cancelled_error != ok || testing.pump(&harness, root_key_cancelled, now) != ok { os.exit(116i32) }
    if !politely_says(&harness, "Move cancelled") { os.exit(131i32) }
    if !tab_to(&harness, 612u64) || testing.press_key(&harness, 32u32, zero) != ok { os.exit(117i32) }
    let (root_key_enter, root_key_enter_error) = build(&f, &theme, &touch, s)
    if root_key_enter_error != ok || testing.pump(&harness, root_key_enter, now) != ok { os.exit(118i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || testing.press_key(&harness, 13u32, zero) != ok || s.moves != 4usize || s.moved.from != 1usize || s.moved.to != 0usize { os.exit(119i32) }
    // (D1196) A secondary press on a row opens its Move menu at the pointer; a
    // command reports one move and closes it. Shift+F10 opens the focused row's
    // menu with the impossible moves disabled, and Escape closes it unmoved.
    let (root_menu_rest, root_menu_rest_error) = build(&f, &theme, &touch, s)
    if root_menu_rest_error != ok || testing.pump(&harness, root_menu_rest, now) != ok { os.exit(136i32) }
    let (second_row, has_second_row) = bounds(&harness, &runtime, 612u64)
    if !has_second_row { os.exit(137i32) }
    var secondary = testing.pointer_at(second_row.x + 120.0, second_row.y + 20.0)
    secondary.buttons = 2u32
    secondary.changed = .Secondary
    if testing.send(&harness, input.Event { PointerDown: secondary }) != ok { os.exit(138i32) }
    secondary.buttons = 0u32
    if testing.send(&harness, input.Event { PointerUp: secondary }) != ok || s.moves != 4usize { os.exit(139i32) }
    let (root_menu, root_menu_error) = build(&f, &theme, &touch, s)
    if root_menu_error != ok || testing.pump(&harness, root_menu, now) != ok { os.exit(140i32) }
    let (menu_tree, menu_tree_error) = testing.semantics(&harness)
    if menu_tree_error != ok { os.exit(141i32) }
    let (to_top, has_to_top) = find(menu_tree, .MenuItem, "Move to top")
    let (down_item, has_down_item) = find(menu_tree, .MenuItem, "Move down")
    if !has_to_top || !has_down_item || to_top.state.disabled || down_item.state.disabled || !near(to_top.bounds.x, second_row.x + 122.0) { os.exit(142i32) }
    if testing.tap(&harness, to_top.bounds.x + 20.0, to_top.bounds.y + to_top.bounds.height * 0.5) != ok || s.moves != 5usize || s.moved.from != 1usize || s.moved.to != 0usize { os.exit(143i32) }
    let (root_menu_done, root_menu_done_error) = build(&f, &theme, &touch, s)
    if root_menu_done_error != ok || testing.pump(&harness, root_menu_done, now) != ok || testing.by_role(&harness, .Menu).count != 0usize || !politely_says(&harness, "Second, moved to position 1 of 3") { os.exit(144i32) }
    var shifted: input.Modifiers = zero
    shifted.shift = true
    if !tab_to(&harness, 611u64) || testing.press_key(&harness, 65479u32, shifted) != ok { os.exit(145i32) }
    let (root_key_menu, root_key_menu_error) = build(&f, &theme, &touch, s)
    if root_key_menu_error != ok || testing.pump(&harness, root_key_menu, now) != ok { os.exit(146i32) }
    let (key_menu_tree, key_menu_tree_error) = testing.semantics(&harness)
    if key_menu_tree_error != ok { os.exit(147i32) }
    let (up_item, has_up_item) = find(key_menu_tree, .MenuItem, "Move up")
    let (top_item, has_top_item) = find(key_menu_tree, .MenuItem, "Move to top")
    if !has_up_item || !has_top_item || !up_item.state.disabled || !top_item.state.disabled { os.exit(148i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || s.moves != 5usize { os.exit(149i32) }
    let (root_key_menu_done, root_key_menu_done_error) = build(&f, &theme, &touch, s)
    if root_key_menu_done_error != ok || testing.pump(&harness, root_key_menu_done, now) != ok || testing.by_role(&harness, .Menu).count != 0usize { os.exit(150i32) }
    // (D1197) Each row names only the moves it can make; performing one reports
    // it and announces it, and a move the row does not name is refused.
    let (named_tree, named_tree_error) = testing.semantics(&harness)
    if named_tree_error != ok { os.exit(151i32) }
    let (first_named, has_first_named) = find(named_tree, .ListItem, "First")
    let (second_named, has_second_named) = find(named_tree, .ListItem, "Second")
    if !has_first_named || !has_second_named || first_named.names.len != 2usize || !mem.eq[u8](first_named.names[0usize], "Move down") || !mem.eq[u8](first_named.names[1usize], "Move to bottom") || second_named.names.len != 4usize || !mem.eq[u8](second_named.names[2usize], "Move to top") { os.exit(152i32) }
    if accessibility.perform_named(&runtime, first_named.id, "Move up") == ok || s.moves != 5usize { os.exit(153i32) }
    if accessibility.perform_named(&runtime, second_named.id, "Move to bottom") != ok || s.moves != 6usize || s.moved.from != 1usize || s.moved.to != 2usize { os.exit(154i32) }
    let (root_named, root_named_error) = build(&f, &theme, &touch, s)
    if root_named_error != ok || testing.pump(&harness, root_named, now) != ok || !politely_says(&harness, "Second, moved to position 3 of 3") { os.exit(155i32) }
    // In a right-to-left theme the PageView's physical strip, buttons,
    // chevrons, drag and horizontal keys mirror while page indices stay logical.
    s.page = 1usize
    var rtl_tokens = style.reference(.Light)
    rtl_tokens.direction = .RightToLeft
    let rtl_theme = control.Theme { tokens: &rtl_tokens, fonts: fonts, language: "", runtime: &runtime }
    if testing.hover(&harness, view.x + 120.0, view.y + 60.0) != ok { os.exit(82i32) }
    let (root_rtl, root_rtl_error) = build(&f, &rtl_theme, &touch, s)
    if root_rtl_error != ok || testing.pump(&harness, root_rtl, now) != ok { os.exit(83i32) }
    let (rtl_shot, rtl_shot_error) = testing.snapshot(&harness, a)
    let (rtl_previous, has_rtl_previous) = bounds(&harness, &runtime, 101u64)
    let (rtl_next, has_rtl_next) = bounds(&harness, &runtime, 102u64)
    let rtl_ink = style.color(&rtl_tokens, .OnSecondaryContainer)
    if rtl_shot_error != ok || !has_rtl_previous || !has_rtl_next || !near(rtl_previous.x, view.x + 188.0) || !near(rtl_next.x, view.x + 12.0) || !is_color(rtl_shot, at(rtl_previous.x + 18.0, rtl_previous.y + 16.0), rtl_ink) || is_color(rtl_shot, at(rtl_previous.x + 22.0, rtl_previous.y + 16.0), rtl_ink) || !is_color(rtl_shot, at(rtl_next.x + 21.0, rtl_next.y + 16.0), rtl_ink) || is_color(rtl_shot, at(rtl_next.x + 18.0, rtl_next.y + 16.0), rtl_ink) { os.exit(84i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 100u64).element) != ok || testing.press_key(&harness, 37u32, zero) != ok || s.page != 2usize { os.exit(85i32) }
    s.page = 1usize
    if testing.press_key(&harness, 39u32, zero) != ok || s.page != 0usize { os.exit(86i32) }
    s.page = 1usize
    if !press(&harness, view.x + 60.0, view.y + 100.0) || !move_to(&harness, view.x + 120.0, view.y + 100.0) || !move_to(&harness, view.x + 150.0, view.y + 100.0) { os.exit(87i32) }
    let (root_rtl_drag, root_rtl_drag_error) = build(&f, &rtl_theme, &touch, s)
    if root_rtl_drag_error != ok || testing.pump(&harness, root_rtl_drag, now) != ok { os.exit(88i32) }
    let (rtl_drag, rtl_drag_error) = testing.snapshot(&harness, a)
    if rtl_drag_error != ok || !is_color(rtl_drag, at(view.x + 20.0, view.y + 100.0), style.color(&rtl_tokens, .ErrorContainer)) || !is_color(rtl_drag, at(view.x + 100.0, view.y + 100.0), style.color(&rtl_tokens, .TertiaryContainer)) { os.exit(89i32) }
    if !move_to(&harness, view.x + 200.0, view.y + 100.0) || !release(&harness, view.x + 200.0, view.y + 100.0) || s.page != 2usize { os.exit(90i32) }
    // Touch lift scales the row to 102% and moves it 4 up without changing its
    // layout or hit bounds; the transform wrapper stays present across the drag.
    let (touch_list, has_touch_list) = bounds(&harness, &runtime, 620u64)
    let (touch_grip, has_touch_grip) = bounds(&harness, &runtime, 621u64)
    if !has_touch_list || !has_touch_grip || !near(touch_grip.x, touch_list.x + 196.0) || !near(touch_grip.width, 48.0) { os.exit(100i32) }
    s.moves = 0usize
    if !press(&harness, touch_grip.x + 24.0, touch_grip.y + 24.0) || !move_to(&harness, touch_grip.x + 24.0, touch_grip.y + 48.0) || !move_to(&harness, touch_grip.x + 24.0, touch_grip.y + 84.0) { os.exit(101i32) }
    let (root_touch, root_touch_error) = build(&f, &rtl_theme, &touch, s)
    if root_touch_error != ok || testing.pump(&harness, root_touch, now) != ok { os.exit(102i32) }
    let (touch_shot, touch_shot_error) = testing.snapshot(&harness, a)
    let (touch_lifted, has_touch_lifted) = bounds(&harness, &runtime, 631u64)
    let (touch_second, has_touch_second) = bounds(&harness, &runtime, 632u64)
    if touch_shot_error != ok || !has_touch_lifted || !has_touch_second || !near(touch_lifted.x, touch_list.x + 8.0) || !near(touch_lifted.y, touch_list.y + 60.0) || !near(touch_lifted.width, 264.0) || !near(touch_second.y, touch_list.y) { os.exit(103i32) }
    let touch_ground = style.layer(style.color(&touch_tokens, .SurfaceContainerHigh), style.color(&touch_tokens, .OnSurface), 0.16)
    if !is_color(touch_shot, at(touch_list.x + 4.0, touch_list.y + 60.0), style.color(&touch_tokens, .SurfaceContainerLow)) || !is_color(touch_shot, at(touch_list.x + 200.0, touch_list.y + 88.0), touch_ground) || !is_color(touch_shot, at(touch_lifted.x + touch_lifted.width * 0.5, touch_lifted.y - 3.0), touch_ground) { os.exit(104i32) }
    if !release(&harness, touch_grip.x + 24.0, touch_grip.y + 84.0) || s.moves != 1usize || s.moved.from != 0usize || s.moved.to != 1usize { os.exit(105i32) }
    // (D1210) A 500 ms hold on a touch row opens its Move menu below the row and
    // eats the release; a command reports one move and closes it.
    let (root_touch_rest, root_touch_rest_error) = build(&f, &rtl_theme, &touch, s)
    if root_touch_rest_error != ok || testing.pump(&harness, root_touch_rest, now) != ok { os.exit(171i32) }
    let hold_start = time.Instant { nanos: now.nanos + 1000000000i64 }
    if testing.begin(&harness, hold_start) != ok || !press(&harness, touch_list.x + 80.0, touch_list.y + 28.0) { os.exit(160i32) }
    let (root_hold, root_hold_error) = build(&f, &rtl_theme, &touch, s)
    if root_hold_error != ok || testing.pump(&harness, root_hold, hold_start) != ok || testing.by_role(&harness, .Menu).count != 0usize { os.exit(161i32) }
    let hold_due = time.Instant { nanos: hold_start.nanos + 500000000i64 }
    if testing.begin(&harness, hold_due) != ok { os.exit(162i32) }
    let (root_held, root_held_error) = build(&f, &rtl_theme, &touch, s)
    if root_held_error != ok || testing.pump(&harness, root_held, hold_due) != ok { os.exit(163i32) }
    if !release(&harness, touch_list.x + 80.0, touch_list.y + 28.0) || s.moves != 1usize { os.exit(164i32) }
    let (root_touch_menu, root_touch_menu_error) = build(&f, &rtl_theme, &touch, s)
    if root_touch_menu_error != ok || testing.pump(&harness, root_touch_menu, hold_due) != ok { os.exit(165i32) }
    let (touch_menu_tree, touch_menu_tree_error) = testing.semantics(&harness)
    if touch_menu_tree_error != ok { os.exit(166i32) }
    let (touch_down, has_touch_down) = find(touch_menu_tree, .MenuItem, "Move down")
    let (touch_up, has_touch_up) = find(touch_menu_tree, .MenuItem, "Move up")
    if !has_touch_down || !has_touch_up || !touch_up.state.disabled || touch_down.bounds.y < touch_list.y + 56.0 { os.exit(167i32) }
    if testing.tap(&harness, touch_down.bounds.x + 20.0, touch_down.bounds.y + touch_down.bounds.height * 0.5) != ok || s.moves != 2usize || s.moved.from != 0usize || s.moved.to != 1usize { os.exit(168i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(68i32) }
    try io.print("ui collections4 v2 ok\n")
    ret ok
}
