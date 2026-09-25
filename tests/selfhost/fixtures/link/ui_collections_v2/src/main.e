// The v2 rows, lists, virtual list, grid view and virtual grid (D979, widget
// plan P5-12, docs/ux/components/Row, List, VirtualList, GridView, VirtualGrid)
// under the light theme at pointer density: a full-bleed list on `surface` with
// 8 above its `title-small` subheader, 48 and 64 tall rows between 1px
// `outline-variant` dividers, the selected row `secondary-container`, the
// disabled one out of reach, Up and Down moving the focus; a grouped list on
// `surface-container-low` with rounded corners, a title and a footnote; the
// compact empty state; a virtual list of 48 rows building only those in view,
// with the rounded thumb in `on-surface-variant` at 50%; a grid of 2 media tiles
// across 300 with the placeholder media, the check ring and the selected
// `secondary-container` tile with its `primary` check; a virtual grid of 1:1
// photo tiles 12 in and 4 apart.

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
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

const W: usize = 700usize

type Store = struct { presses: usize, list_offset: f32, grid_offset: f32, press: widget.Submit, files: [3]collection.RowItem, settings: [2]collection.RowItem, tiles: [3]collection.Tile }

fn on_press(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.presses += 1usize
    ret ok
}

fn set_list_scroll(ctx: *void, value: f32) -> err {
    let s = mem.cast[*Store](ctx)
    s.list_offset = value
    ret ok
}

fn set_grid_scroll(ctx: *void, value: f32) -> err {
    let s = mem.cast[*Store](ctx)
    s.grid_offset = value
    ret ok
}

fn number_count(ctx: *void) -> usize {
    ret 100usize
}

fn number_key(ctx: *void, index: usize) -> widget.Key {
    ret 4000u64 + u64(index)
}

fn number_item(ctx: *void, index: usize) -> collection.RowItem {
    ret collection.row_item("Number")
}

fn photo_count(ctx: *void) -> usize {
    ret 50usize
}

fn photo_key(ctx: *void, index: usize) -> widget.Key {
    ret 6000u64 + u64(index)
}

fn photo_tile(ctx: *void, index: usize) -> collection.Tile {
    var out = collection.tile_of_name("Photo")
    out.selected = index == 1usize
    ret out
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

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    var file_keys: [3]widget.Key = zero
    file_keys[0usize] = 101u64
    file_keys[1usize] = 102u64
    file_keys[2usize] = 103u64
    var full = collection.list_options()
    full.dividers = true
    full.subheader = "Today"
    full.width = 300.0
    let (files, e1) = collection.list_of(a, 1000u64, t, "Files", s.files[0usize..3usize], file_keys[..], full)
    var setting_keys: [2]widget.Key = zero
    setting_keys[0usize] = 201u64
    setting_keys[1usize] = 202u64
    var grouped = collection.list_options()
    grouped.grouped = true
    grouped.dividers = true
    grouped.title = "General"
    grouped.footnote = "Applies at once"
    grouped.width = 300.0
    let (settings, e2) = collection.list_of(a, 2000u64, t, "Settings", s.settings[0usize..2usize], setting_keys[..], grouped)
    var empty = collection.list_options()
    empty.empty_title = "No recent projects"
    empty.empty_message = "Projects you open appear here"
    empty.width = 300.0
    var no_items: []const collection.RowItem = zero
    var no_keys: []const widget.Key = zero
    let (nothing, e3) = collection.list_of(a, 3000u64, t, "Recent", no_items, no_keys, empty)
    var long = collection.virtual_list_options()
    long.dividers = true
    long.width = 300.0
    long.height = 144.0
    long.offset = s.list_offset
    long.change = widget.Change[f32] { ctx: mem.cast[*void](s), invoke: set_list_scroll }
    var none_ctx: *void = zero
    let (numbers, e4) = collection.virtual_list_of(a, 400u64, t, "Numbers", collection.RowSource { ctx: none_ctx, count: number_count, key: number_key, item: number_item }, long)
    var tile_keys: [3]widget.Key = zero
    tile_keys[0usize] = 501u64
    tile_keys[1usize] = 502u64
    tile_keys[2usize] = 503u64
    var laid = collection.grid_options()
    laid.selecting = true
    laid.width = 300.0
    let (tiles, e5) = collection.grid_view_of(a, 500u64, t, "Tiles", s.tiles[0usize..3usize], tile_keys[..], laid)
    var wall = collection.virtual_grid_options()
    wall.width = 300.0
    wall.height = 150.0
    wall.offset = s.grid_offset
    wall.change = widget.Change[f32] { ctx: mem.cast[*void](s), invoke: set_grid_scroll }
    let (photos, e6) = collection.virtual_grid_of(a, 600u64, t, "Photos", collection.TileSource { ctx: none_ctx, count: photo_count, key: photo_key, tile: photo_tile }, wall)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (zero, e1) }
    let (left, left_error) = mem.alloc[widget.Node](a, 4usize)
    if left_error != ok { ret (zero, left_error) }
    left[0usize] = files
    left[1usize] = settings
    left[2usize] = nothing
    left[3usize] = numbers
    let (right, right_error) = mem.alloc[widget.Node](a, 2usize)
    if right_error != ok { ret (zero, right_error) }
    right[0usize] = tiles
    right[1usize] = photos
    let (sides, sides_error) = mem.alloc[widget.Node](a, 2usize)
    if sides_error != ok { ret (zero, sides_error) }
    sides[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, style.defaults(), left[0usize..4usize])
    sides[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, style.defaults(), right[0usize..2usize])
    var page = style.defaults()
    page.width = style.Length { Px: 700.0 }
    page.height = style.Length { Px: 760.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 24.0 }, page, sides[0usize..2usize]), ok)
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

fn tap_key(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let (b, found) = bounds(h, runtime, key)
    if !found { ret false }
    ret testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
}

fn focused_is(h: *testing.Harness, key: widget.Key) -> bool {
    let (id, has) = testing.focused(h)
    ret has && id.slot == testing.by_key(h, key).element.slot
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
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
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 1200usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 40u16, max_commands: 4096usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 700u32, 760u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.press = widget.Submit { ctx: mem.cast[*void](s), invoke: on_press }
    s.files[0usize] = collection.row_item("Alpha")
    s.files[0usize].has_leading = true
    s.files[0usize].leading = .Picture
    s.files[0usize].meta = "2 min"
    s.files[1usize] = collection.row_item("Beta")
    s.files[1usize].supporting = "Approved build 4128"
    s.files[1usize].selected = true
    s.files[1usize].check = true
    s.files[2usize] = collection.row_item("Gamma")
    s.files[2usize].disabled = true
    s.settings[0usize] = collection.row_item("Appearance")
    s.settings[0usize].has_trailing = true
    s.settings[0usize].trailing = .ChevronRight
    s.settings[1usize] = collection.row_item("Sound")
    s.tiles[0usize] = collection.tile_of_name("Alpha tile")
    s.tiles[0usize].meta = "Edited today"
    s.tiles[1usize] = collection.tile_of_name("Beta tile")
    s.tiles[1usize].selected = true
    s.tiles[2usize] = collection.tile_of_name("Gamma tile")
    var i = 0usize
    while i < 3usize {
        s.files[i].action = s.press
        s.tiles[i].action = s.press
        i += 1usize
    }
    s.settings[0usize].action = s.press
    s.settings[1usize].action = s.press
    let (frame_storage, storage_error) = mem.alloc[u8](a, 4194304usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&f, &theme, s)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    let background = style.color(&tokens, .Background)
    // The full-bleed list: `surface` with 8 above the subheader; rows 48 and 64
    // tall between 1px `outline-variant` dividers; Beta `secondary-container`.
    let (files, has_files) = bounds(&harness, &runtime, 1000u64)
    let (alpha, has_alpha) = bounds(&harness, &runtime, 101u64)
    let (beta, has_beta) = bounds(&harness, &runtime, 102u64)
    let (gamma, has_gamma) = bounds(&harness, &runtime, 103u64)
    if !has_files || !has_alpha || !has_beta || !has_gamma { os.exit(13i32) }
    if !near(alpha.height, 48.0) || !near(beta.height, 64.0) || !near(gamma.height, 48.0) || !near(alpha.width, 300.0) || !near(alpha.y, files.y + 32.0) { os.exit(14i32) }
    if !is_color(shot, at(files.x + 150.0, files.y + 4.0), background) || testing.by_text(&harness, "Today").count != 1usize { os.exit(15i32) }
    if !near(beta.y, alpha.y + 49.0) || !is_color(shot, at(beta.x + 150.0, beta.y - 0.5), style.color(&tokens, .OutlineVariant)) { os.exit(16i32) }
    if !is_color(shot, at(beta.x + 150.0, beta.y + 32.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(alpha.x + 150.0, alpha.y + 24.0), background) { os.exit(17i32) }
    // The leading glyph sits 16 in; the tree names the rows and marks them.
    let (list_node, has_list) = find(tree, .List, "Files")
    let (beta_node, has_beta_node) = find(tree, .ListItem, "Beta")
    let (gamma_node, has_gamma_node) = find(tree, .ListItem, "Gamma")
    if !has_list || list_node.position.row_count != 3u32 || !has_beta_node || !beta_node.state.selected || beta_node.position.row != 2u32 || !same(beta_node.hint, "Approved build 4128") { os.exit(18i32) }
    if !has_gamma_node || !gamma_node.state.disabled { os.exit(19i32) }
    // A tap runs the row's action; Tab reaches the first row and Down, Home move
    // the focus.
    if !tap_key(&harness, &runtime, 101u64) || s.presses != 1usize { os.exit(20i32) }
    if testing.tab(&harness, false) != ok { os.exit(21i32) }
    var tabs = 0usize
    while !focused_is(&harness, 101u64) && tabs < 60usize {
        if testing.tab(&harness, false) != ok { os.exit(21i32) }
        tabs += 1usize
    }
    if !focused_is(&harness, 101u64) { os.exit(22i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 102u64) { os.exit(23i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !focused_is(&harness, 101u64) { os.exit(24i32) }
    // The grouped list: `surface-container-low`, rounded, its title and footnote.
    let (group, has_group) = bounds(&harness, &runtime, 2000u64)
    if !has_group || !is_color(shot, at(group.x + 150.0, group.y + 24.0), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(group.x + 0.5, group.y + 0.5), background) { os.exit(25i32) }
    if testing.by_text(&harness, "General").count != 1usize || testing.by_text(&harness, "Applies at once").count != 1usize { os.exit(26i32) }
    let (sound, has_sound) = bounds(&harness, &runtime, 202u64)
    if !has_sound || !is_color(shot, at(sound.x + 8.0, sound.y - 0.5), style.color(&tokens, .SurfaceContainerLow)) || !is_color(shot, at(sound.x + 20.0, sound.y - 0.5), style.color(&tokens, .OutlineVariant)) { os.exit(27i32) }
    // The empty state in place of the rows.
    if testing.by_text(&harness, "No recent projects").count == 0usize { os.exit(28i32) }
    // The virtual list: 48 rows, only those in view built; a list of 100 in the
    // tree; the thumb 4 wide 2 from the edge in `on-surface-variant` at 50%.
    let (view, has_view) = bounds(&harness, &runtime, 400u64)
    if !has_view || !near(view.height, 144.0) || testing.by_key(&harness, 4000u64).count != 1usize || testing.by_key(&harness, 4005u64).count != 1usize || testing.by_key(&harness, 4006u64).count != 0usize || testing.by_key(&harness, 4050u64).count != 0usize { os.exit(29i32) }
    let (numbers, has_numbers) = find(tree, .List, "Numbers")
    if !has_numbers || numbers.position.row_count != 100u32 { os.exit(30i32) }
    let (first_row, has_first_row) = bounds(&harness, &runtime, 4000u64)
    if !has_first_row || !near(first_row.height, 47.0) || !is_color(shot, at(view.x + 150.0, view.y + 47.5), style.color(&tokens, .OutlineVariant)) { os.exit(31i32) }
    let half = style.mix(background, style.color(&tokens, .OnSurfaceVariant), 0.5)
    if !is_color(shot, at(view.x + 296.0, view.y + 16.0), half) || !is_color(shot, at(view.x + 299.5, view.y + 16.0), background) || is_color(shot, at(view.x + 296.0, view.y + 40.0), half) { os.exit(32i32) }
    // Virtual-list keys move by stable source index. A target beyond the built
    // window asks for the minimum offset, then receives focus after the rebuild.
    if widget.focus(&runtime, testing.by_key(&harness, 4000u64).element) != ok { os.exit(45i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 4001u64) { os.exit(46i32) }
    if testing.press_key(&harness, 34u32, zero) != ok || !focused_is(&harness, 4003u64) || !near(s.list_offset, 48.0) { os.exit(47i32) }
    f = mem.arena_from(frame_storage)
    let (root_2, build_2_error) = build(&f, &theme, s)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 1100000000i64 }) != ok { os.exit(48i32) }
    if testing.by_key(&harness, 4006u64).count != 1usize || testing.by_key(&harness, 4007u64).count != 0usize { os.exit(56i32) }
    if testing.press_key(&harness, 33u32, zero) != ok || !focused_is(&harness, 4001u64) { os.exit(49i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !near(s.list_offset, 4656.0) || focused_is(&harness, 4099u64) { os.exit(50i32) }
    f = mem.arena_from(frame_storage)
    let (root_3, build_3_error) = build(&f, &theme, s)
    if build_3_error != ok || testing.pump(&harness, root_3, time.Instant { nanos: 1200000000i64 }) != ok || !focused_is(&harness, 4099u64) { os.exit(51i32) }
    if testing.by_key(&harness, 4094u64).count != 1usize || testing.by_key(&harness, 4093u64).count != 0usize { os.exit(57i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || !focused_is(&harness, 4098u64) { os.exit(52i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !near(s.list_offset, 0.0) || focused_is(&harness, 4000u64) { os.exit(53i32) }
    f = mem.arena_from(frame_storage)
    let (root_4, build_4_error) = build(&f, &theme, s)
    if build_4_error != ok || testing.pump(&harness, root_4, time.Instant { nanos: 1300000000i64 }) != ok || !focused_is(&harness, 4000u64) { os.exit(54i32) }
    // The grid: two tiles of 146 across 300, 8 apart; the third on the next row.
    let (one, has_one) = bounds(&harness, &runtime, 501u64)
    let (two, has_two) = bounds(&harness, &runtime, 502u64)
    let (three, has_three) = bounds(&harness, &runtime, 503u64)
    if !has_one || !has_two || !has_three || !near(one.width, 146.0) || !near(two.x, one.x + 154.0) || !near(three.y, one.y + one.height + 8.0) { os.exit(33i32) }
    let (tiles, has_tiles) = find(tree, .Grid, "Tiles")
    let (beta_tile, has_beta_tile) = find(tree, .Cell, "Beta tile")
    if !has_tiles || tiles.position.column_count != 2u32 || tiles.position.row_count != 2u32 || !has_beta_tile || !beta_tile.state.selected { os.exit(34i32) }
    // An unselected tile: placeholder media in `surface-container-highest`, the
    // check ring, the caption on `surface-container-low`.
    if !is_color(shot, at(one.x + 120.0, one.y + 10.0), style.color(&tokens, .SurfaceContainerHighest)) || !is_color(shot, at(one.x + 9.0, one.y + 20.0), style.color(&tokens, .OnSurfaceVariant)) { os.exit(35i32) }
    if !is_color(shot, at(one.x + 70.0, one.y + 115.0), style.color(&tokens, .SurfaceContainerLow)) { os.exit(36i32) }
    // The selected tile: `secondary-container` round media inset 8 and the
    // `primary` check 12 from the corner.
    if !is_color(shot, at(two.x + 4.0, two.y + 60.0), style.color(&tokens, .SecondaryContainer)) || !is_color(shot, at(two.x + 70.0, two.y + 60.0), style.color(&tokens, .SurfaceContainerHighest)) { os.exit(37i32) }
    if !is_color(shot, at(two.x + 14.5, two.y + 24.0), style.color(&tokens, .Primary)) { os.exit(38i32) }
    if !tap_key(&harness, &runtime, 503u64) || s.presses != 2usize { os.exit(39i32) }
    // The virtual grid: 1:1 photo tiles 136 across, 12 in and 4 apart.
    let (wall, has_wall) = bounds(&harness, &runtime, 600u64)
    let (first_photo, has_first_photo) = bounds(&harness, &runtime, 6000u64)
    let (second_photo, has_second_photo) = bounds(&harness, &runtime, 6001u64)
    if !has_wall || !has_first_photo || !has_second_photo || !near(first_photo.x, wall.x + 12.0) || !near(first_photo.width, 136.0) || !near(first_photo.height, 136.0) || !near(second_photo.x, first_photo.x + 140.0) { os.exit(40i32) }
    if testing.by_key(&harness, 6040u64).count != 0usize { os.exit(41i32) }
    let (photos, has_photos) = find(tree, .Grid, "Photos")
    if !has_photos || photos.position.column_count != 2u32 || photos.position.row_count != 25u32 { os.exit(42i32) }
    if !is_color(shot, at(first_photo.x + 5.0, first_photo.y + 60.0), style.color(&tokens, .SurfaceContainerHighest)) || !is_color(shot, at(second_photo.x + 4.0, second_photo.y + 60.0), style.color(&tokens, .SecondaryContainer)) { os.exit(43i32) }
    // Virtual-grid arrows preserve the column, Page keys move a viewport of
    // rows, and an unbuilt end receives focus after the caller scrolls/rebuilds.
    if widget.focus(&runtime, testing.by_key(&harness, 6000u64).element) != ok { os.exit(58i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !focused_is(&harness, 6001u64) { os.exit(59i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 6003u64) || !near(s.grid_offset, 130.0) { os.exit(60i32) }
    if testing.press_key(&harness, 37u32, zero) != ok || !focused_is(&harness, 6002u64) { os.exit(61i32) }
    if testing.press_key(&harness, 34u32, zero) != ok || !focused_is(&harness, 6004u64) || !near(s.grid_offset, 270.0) { os.exit(62i32) }
    if testing.press_key(&harness, 33u32, zero) != ok || !focused_is(&harness, 6002u64) || !near(s.grid_offset, 130.0) { os.exit(63i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !near(s.grid_offset, 3350.0) || focused_is(&harness, 6049u64) { os.exit(64i32) }
    f = mem.arena_from(frame_storage)
    let (root_5, build_5_error) = build(&f, &theme, s)
    if build_5_error != ok || testing.pump(&harness, root_5, time.Instant { nanos: 1400000000i64 }) != ok || !focused_is(&harness, 6049u64) { os.exit(65i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || !focused_is(&harness, 6047u64) || !near(s.grid_offset, 3220.0) { os.exit(66i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !focused_is(&harness, 6049u64) { os.exit(70i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || !focused_is(&harness, 6047u64) || !near(s.grid_offset, 3220.0) { os.exit(71i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !near(s.grid_offset, 0.0) || focused_is(&harness, 6000u64) { os.exit(67i32) }
    f = mem.arena_from(frame_storage)
    let (root_6, build_6_error) = build(&f, &theme, s)
    if build_6_error != ok || testing.pump(&harness, root_6, time.Instant { nanos: 1500000000i64 }) != ok || !focused_is(&harness, 6000u64) { os.exit(68i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(69i32) }
    try io.print("ui collections v2 ok\n")
    ret ok
}
