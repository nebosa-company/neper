// `e.ui.style` and `e.ui.layout`: the default style validates and every bad field
// is refused; `constrain` clamps; a flex row grows its flexible children into a
// bounded width, shrinks over one, places leftover by every main alignment and
// cross alignment, and keeps desired sizes under an unbounded limit; a grid
// resolves fixed, auto and flexible tracks with gaps and refuses too many
// children; contradictory limits are `Invalid` and gaps past the bound `Overflow`.

use e.gfx.geometry
use e.gfx.paint
use e.io
use e.mem
use e.os
use e.ui.layout
use e.ui.style

fn near(x: f32, y: f32) -> bool {
    let d = x - y
    ret d < 0.001 && d > -0.001
}

fn rect_is(r: geometry.Rect, x: f32, y: f32, w: f32, h: f32) -> bool {
    ret near(r.x, x) && near(r.y, y) && near(r.width, w) && near(r.height, h)
}

fn limits(min_w: f32, max_w: f32, min_h: f32, max_h: f32) -> layout.Constraints {
    ret layout.Constraints { min_width: min_w, max_width: max_w, min_height: min_h, max_height: max_h }
}

fn child(w: f32, h: f32, flex: f32) -> layout.Child {
    ret layout.Child { desired: geometry.Size { width: w, height: h }, flex: flex }
}

fn row(along: layout.MainAlign, cross: layout.CrossAlign, gap: f32) -> layout.Flex {
    ret layout.Flex { axis: .Horizontal, main: along, cross: cross, gap: gap }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Style: the defaults validate; each field has a way to fail.
    var s = style.defaults()
    if style.validate(&s) != ok { os.exit(1i32) }
    s.opacity = 1.5
    if style.validate(&s) != style.Invalid { os.exit(2i32) }
    s = style.defaults()
    s.padding.left = style.Length { Px: -1.0 }
    if style.validate(&s) != style.Invalid { os.exit(3i32) }
    s = style.defaults()
    s.margin.left = style.Length { Px: -4.0 }
    if style.validate(&s) != ok { os.exit(4i32) }
    s.min_width = style.Length { Px: 10.0 }
    s.max_width = style.Length { Px: 5.0 }
    if style.validate(&s) != style.Invalid { os.exit(5i32) }
    s = style.defaults()
    s.width = style.Length { Percent: 50.0 }
    s.height = style.Length { Flex: 2.0 }
    if style.validate(&s) != ok { os.exit(6i32) }
    s.background = paint.Brush { Solid: paint.rgba(2.0, 0.0, 0.0, 1.0) }
    if style.validate(&s) != style.Invalid { os.exit(7i32) }
    let inf = mem.bitcast[f32](2139095040u32)
    s = style.defaults()
    s.width = style.Length { Px: inf }
    if style.validate(&s) != style.Invalid { os.exit(8i32) }

    // constrain clamps both axes.
    let clamped = layout.constrain(geometry.Size { width: 500.0, height: 2.0 }, limits(10.0, 100.0, 5.0, 50.0))
    if !near(clamped.width, 100.0) || !near(clamped.height, 5.0) { os.exit(9i32) }

    // Flex: two rigid children and one flexible fill 100 wide with a gap of 5.
    let kids: [3]layout.Child = [3]layout.Child{ child(20.0, 10.0, 0.0), child(30.0, 30.0, 1.0), child(10.0, 20.0, 0.0) }
    let (filled, filled_error) = layout.flex(a, row(.Start, .Start, 5.0), limits(0.0, 100.0, 0.0, 100.0), kids[0..])
    if filled_error != ok || !near(filled.size.width, 100.0) || !near(filled.size.height, 30.0) || filled.children.len != 3usize { os.exit(10i32) }
    if !rect_is(filled.children[0], 0.0, 0.0, 20.0, 10.0) || !rect_is(filled.children[1], 25.0, 0.0, 60.0, 30.0) || !rect_is(filled.children[2], 90.0, 0.0, 10.0, 20.0) { os.exit(11i32) }
    // Two flexible children share by weight.
    let weighted: [2]layout.Child = [2]layout.Child{ child(0.0, 10.0, 1.0), child(0.0, 10.0, 3.0) }
    let (shared_out, shared_error) = layout.flex(a, row(.Start, .Start, 0.0), limits(0.0, 80.0, 0.0, 80.0), weighted[0..])
    if shared_error != ok || !near(shared_out.children[0].width, 20.0) || !near(shared_out.children[1].width, 60.0) || !near(shared_out.children[1].x, 20.0) { os.exit(12i32) }
    // Over the bound: shrink in proportion.
    let wide: [2]layout.Child = [2]layout.Child{ child(60.0, 10.0, 0.0), child(20.0, 10.0, 0.0) }
    let (shrunk, shrunk_error) = layout.flex(a, row(.Start, .Start, 0.0), limits(0.0, 40.0, 0.0, 40.0), wide[0..])
    if shrunk_error != ok || !near(shrunk.size.width, 40.0) || !near(shrunk.children[0].width, 30.0) || !near(shrunk.children[1].width, 10.0) || !near(shrunk.children[1].x, 30.0) { os.exit(13i32) }
    // Rigid children under a wide bound: the leftover goes where `main` says.
    let rigid: [2]layout.Child = [2]layout.Child{ child(10.0, 10.0, 0.0), child(10.0, 10.0, 0.0) }
    let (ended, ended_error) = layout.flex(a, row(.End, .Start, 0.0), limits(50.0, 50.0, 0.0, 10.0), rigid[0..])
    if ended_error != ok || !near(ended.size.width, 50.0) || !near(ended.children[0].x, 30.0) || !near(ended.children[1].x, 40.0) { os.exit(14i32) }
    let (centred, centred_error) = layout.flex(a, row(.Center, .Start, 0.0), limits(50.0, 50.0, 0.0, 10.0), rigid[0..])
    if centred_error != ok || !near(centred.children[0].x, 15.0) { os.exit(15i32) }
    let (between, between_error) = layout.flex(a, row(.SpaceBetween, .Start, 0.0), limits(50.0, 50.0, 0.0, 10.0), rigid[0..])
    if between_error != ok || !near(between.children[0].x, 0.0) || !near(between.children[1].x, 40.0) { os.exit(16i32) }
    let (around, around_error) = layout.flex(a, row(.SpaceAround, .Start, 0.0), limits(50.0, 50.0, 0.0, 10.0), rigid[0..])
    if around_error != ok || !near(around.children[0].x, 7.5) || !near(around.children[1].x, 32.5) { os.exit(17i32) }
    let (evenly, evenly_error) = layout.flex(a, row(.SpaceEvenly, .Start, 0.0), limits(50.0, 50.0, 0.0, 10.0), rigid[0..])
    if evenly_error != ok || !near(evenly.children[0].x, 10.0) || !near(evenly.children[1].x, 30.0) { os.exit(18i32) }
    // Cross alignment: end, centre and stretch against the tallest child.
    let (cross_end, cross_end_error) = layout.flex(a, row(.Start, .End, 0.0), limits(0.0, 100.0, 0.0, 100.0), kids[0..])
    if cross_end_error != ok || !near(cross_end.children[0].y, 20.0) || !near(cross_end.children[2].y, 10.0) { os.exit(19i32) }
    let (cross_centre, cross_centre_error) = layout.flex(a, row(.Start, .Center, 0.0), limits(0.0, 100.0, 0.0, 100.0), kids[0..])
    if cross_centre_error != ok || !near(cross_centre.children[0].y, 10.0) { os.exit(20i32) }
    let (stretched, stretched_error) = layout.flex(a, row(.Start, .Stretch, 0.0), limits(0.0, 100.0, 0.0, 100.0), kids[0..])
    if stretched_error != ok || !near(stretched.children[0].height, 30.0) || !near(stretched.children[2].height, 30.0) { os.exit(21i32) }
    // A column: the axes swap.
    let column = layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 2.0 }
    let (stacked, stacked_error) = layout.flex(a, column, limits(0.0, 100.0, 0.0, 100.0), rigid[0..])
    if stacked_error != ok || !near(stacked.size.width, 10.0) || !near(stacked.size.height, 22.0) || !near(stacked.children[1].y, 12.0) { os.exit(22i32) }
    // Unbounded: flexible children keep their desired size and the row hugs them.
    let (loose, loose_error) = layout.flex(a, row(.Start, .Start, 5.0), limits(0.0, inf, 0.0, inf), kids[0..])
    if loose_error != ok || !near(loose.size.width, 70.0) || !near(loose.children[1].width, 30.0) { os.exit(23i32) }
    // No children: the minimum.
    let (empty, empty_error) = layout.flex(a, row(.Start, .Start, 0.0), limits(7.0, 100.0, 3.0, 100.0), kids[0usize..0usize])
    if empty_error != ok || !near(empty.size.width, 7.0) || !near(empty.size.height, 3.0) || empty.children.len != 0usize { os.exit(24i32) }
    // Refusals: a minimum above its maximum, a negative gap, gaps past the bound.
    let (_, contradictory) = layout.flex(a, row(.Start, .Start, 0.0), limits(60.0, 50.0, 0.0, 10.0), rigid[0..])
    if contradictory != layout.Invalid { os.exit(25i32) }
    let (_, negative_gap) = layout.flex(a, row(.Start, .Start, -1.0), limits(0.0, 50.0, 0.0, 10.0), rigid[0..])
    if negative_gap != layout.Invalid { os.exit(26i32) }
    let (_, too_tight) = layout.flex(a, row(.Start, .Start, 30.0), limits(0.0, 20.0, 0.0, 10.0), rigid[0..])
    if too_tight != layout.Overflow { os.exit(27i32) }
    let bad_child: [1]layout.Child = [1]layout.Child{ child(-1.0, 10.0, 0.0) }
    let (_, bad_child_error) = layout.flex(a, row(.Start, .Start, 0.0), limits(0.0, 20.0, 0.0, 10.0), bad_child[0..])
    if bad_child_error != layout.Invalid { os.exit(28i32) }

    // Grid: columns fixed 20, auto, flex 1 and flex 1 across 100 with gaps of 4;
    // rows auto and fixed 15 with a gap of 2. The auto column is its widest child.
    let columns: [4]layout.GridTrack = [4]layout.GridTrack{ layout.GridTrack { Px: 20.0 }, .Auto, layout.GridTrack { Flex: 1.0 }, layout.GridTrack { Flex: 1.0 } }
    let rows: [2]layout.GridTrack = [2]layout.GridTrack{ .Auto, layout.GridTrack { Px: 15.0 } }
    let spec = layout.Grid { columns: columns[0..], rows: rows[0..], column_gap: 4.0, row_gap: 2.0 }
    let cells: [6]layout.Child = [6]layout.Child{ child(5.0, 8.0, 0.0), child(12.0, 6.0, 0.0), child(1.0, 1.0, 0.0), child(1.0, 1.0, 0.0), child(1.0, 1.0, 0.0), child(30.0, 1.0, 0.0) }
    let (g, g_error) = layout.grid(a, spec, limits(0.0, 100.0, 0.0, 100.0), cells[0..])
    if g_error != ok || g.children.len != 6usize || !near(g.size.width, 100.0) || !near(g.size.height, 25.0) { os.exit(29i32) }
    if !rect_is(g.children[0], 0.0, 0.0, 20.0, 8.0) || !rect_is(g.children[1], 24.0, 0.0, 30.0, 8.0) || !rect_is(g.children[2], 58.0, 0.0, 19.0, 8.0) || !rect_is(g.children[3], 81.0, 0.0, 19.0, 8.0) { os.exit(30i32) }
    if !rect_is(g.children[4], 0.0, 10.0, 20.0, 15.0) || !rect_is(g.children[5], 24.0, 10.0, 30.0, 15.0) { os.exit(31i32) }
    // Fewer children than cells is fine; more is Overflow; no columns is Invalid;
    // fixed tracks past the bound overflow; an unbounded limit leaves flex tracks empty.
    let (partial, partial_error) = layout.grid(a, spec, limits(0.0, 100.0, 0.0, 100.0), cells[0usize..2usize])
    if partial_error != ok || partial.children.len != 2usize || !near(partial.size.height, 25.0) { os.exit(32i32) }
    let many: [9]layout.Child = [9]layout.Child{ child(1.0, 1.0, 0.0), child(1.0, 1.0, 0.0), child(1.0, 1.0, 0.0), child(1.0, 1.0, 0.0), child(1.0, 1.0, 0.0), child(1.0, 1.0, 0.0), child(1.0, 1.0, 0.0), child(1.0, 1.0, 0.0), child(1.0, 1.0, 0.0) }
    let (_, too_many) = layout.grid(a, spec, limits(0.0, 100.0, 0.0, 100.0), many[0..])
    if too_many != layout.Overflow { os.exit(33i32) }
    let (_, no_columns) = layout.grid(a, layout.Grid { columns: columns[0usize..0usize], rows: rows[0..], column_gap: 0.0, row_gap: 0.0 }, limits(0.0, 100.0, 0.0, 100.0), cells[0usize..1usize])
    if no_columns != layout.Invalid { os.exit(34i32) }
    let (_, too_wide) = layout.grid(a, spec, limits(0.0, 20.0, 0.0, 100.0), cells[0..])
    if too_wide != layout.Overflow { os.exit(35i32) }
    let (hugged, hugged_error) = layout.grid(a, spec, limits(0.0, inf, 0.0, inf), cells[0..])
    if hugged_error != ok || !near(hugged.size.width, 62.0) || !near(hugged.children[2].width, 0.0) { os.exit(36i32) }

    try io.print("ui core ok\n")
    ret ok
}
