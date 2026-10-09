// e.ui.sheet geometry (D2283, L090) against brute-force models: seeded random axes (default sizes, overrides, hidden lines),
// merges, frozen lines and viewports are laid out both by the library (prefix sums, binary search) and by plain loops over
// a materialised matrix, and the two must agree on line positions, the line under a position, the merge holding a cell,
// every cell that draws in a viewport and its rectangle, which cell a point hits, the selection grown over merges,
// keyboard navigation over merges and hidden lines, and the scroll offsets that reveal a cell. Hand cases pin the
// refusals (overlapping, single-cell and out-of-range merges, a merge across the freeze lines) and the sizes of a
// million-row sheet.
use e.io
use e.mem
use e.os
use e.gfx.geometry
use e.ui.sheet as sh

type Rng = struct { state: u64 }

fn next(r: *Rng) -> u64 {
    r.state = (r.state * 1664525u64 + 1013904223u64) % 4294967296u64
    ret r.state / 256u64
}

fn below(r: *Rng, n: usize) -> usize {
    ret usize(next(r) % u64(n))
}

fn fail(code: i32) -> err {
    let _ = io.print("ui sheet geometry failed at ")
    var digits: [6]u8 = zero
    digits[0] = u8(48i32 + code / 10000i32)
    digits[1] = u8(48i32 + (code / 1000i32) % 10i32)
    digits[2] = u8(48i32 + (code / 100i32) % 10i32)
    digits[3] = u8(48i32 + (code / 10i32) % 10i32)
    digits[4] = u8(48i32 + code % 10i32)
    let _ = io.print(digits[..5])
    let _ = io.print("\n")
    os.exit(code)
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

// ---- a materialised model of a sheet ----

type Model = struct { rows: usize, cols: usize, row_size: [64]f32, col_size: [32]f32, owner_row: [2048]usize, owner_col: [2048]usize, span_rows: [2048]usize, span_cols: [2048]usize, frozen_rows: usize, frozen_cols: usize }

fn naive_start(sizes: []const f32, i: usize) -> f32 {
    var s: f32 = 0.0
    var k = 0usize
    while k < i {
        s += sizes[k]
        k += 1usize
    }
    ret s
}

fn naive_index(sizes: []const f32, count: usize, pos: f32) -> usize {
    var visible_first = 0usize
    while visible_first + 1usize < count && sizes[visible_first] == 0.0 { visible_first += 1usize }
    if pos <= 0.0 { ret visible_first }
    var last = count - 1usize
    while last > 0usize && sizes[last] == 0.0 { last -= 1usize }
    var i = 0usize
    var start: f32 = 0.0
    while i < count {
        if sizes[i] > 0.0 && pos >= start && pos < start + sizes[i] { ret i }
        start += sizes[i]
        i += 1usize
    }
    ret last
}

fn model_cell(m: *Model, r: usize, c: usize) -> usize { ret r * 32usize + c }

fn build_axis(a: *mem.Arena, rng: *Rng, count: usize, default_size: f32, sizes: []f32) -> (sh.Axis, err) {
    let (list, list_error) = mem.alloc[sh.Override](a, count + 1usize)
    if list_error != ok { ret (zero, list_error) }
    var n = 0usize
    var i = 0usize
    while i < count {
        sizes[i] = default_size
        if below(rng, 5usize) == 0usize {
            var size = f32(below(rng, 9usize)) * 8.0
            if below(rng, 4usize) != 0usize && size == 0.0 { size = 24.0 }
            sizes[i] = size
            list[n] = sh.Override { index: i, size: size }
            n += 1usize
        }
        i += 1usize
    }
    let (made, made_error) = sh.axis(a, count, default_size, list[0usize..n])
    ret (made, made_error)
}

fn main(a: *mem.Arena) -> err {
    var rng = Rng { state: 2026102u64 }
    var round = 0usize
    while round < 120usize {
        let mark = mem.mark(a)
        let rows = 1usize + below(&rng, 60usize)
        let cols = 1usize + below(&rng, 30usize)
        var row_sizes: [64]f32 = zero
        var col_sizes: [32]f32 = zero
        let default_row = f32(16 + below(&rng, 3usize) * 8)
        let default_col = f32(40 + below(&rng, 3usize) * 16)
        let (row_axis, row_error) = build_axis(a, &rng, rows, default_row, row_sizes[0..])
        let (col_axis, col_error) = build_axis(a, &rng, cols, default_col, col_sizes[0..])
        if row_error != ok || col_error != ok { ret fail(1i32) }
        // axes
        var i = 0usize
        while i <= rows {
            if !near(sh.axis_start(row_axis, i), naive_start(row_sizes[0..], i)) { ret fail(100i32 + i32(round)) }
            if i < rows && !near(sh.axis_size(row_axis, i), row_sizes[i]) { ret fail(300i32 + i32(round)) }
            i += 1usize
        }
        i = 0usize
        while i <= cols {
            if !near(sh.axis_start(col_axis, i), naive_start(col_sizes[0..], i)) { ret fail(500i32 + i32(round)) }
            i += 1usize
        }
        if !near(sh.axis_total(row_axis), naive_start(row_sizes[0..], rows)) { ret fail(700i32 + i32(round)) }
        var probe = 0usize
        while probe < 40usize {
            let pos = f32(below(&rng, 4000usize)) * 0.5 - 20.0
            if sh.axis_index_at(row_axis, pos) != naive_index(row_sizes[0..], rows, pos) { ret fail(1000i32 + i32(round)) }
            if sh.axis_index_at(col_axis, pos) != naive_index(col_sizes[0..], cols, pos) { ret fail(1300i32 + i32(round)) }
            probe += 1usize
        }
        // merges: random rectangles kept when they overlap nothing and are at least two cells
        var occupied: [2048]u8 = zero
        let (list, list_error) = mem.alloc[sh.Merge](a, 24usize)
        if list_error != ok { ret fail(2i32) }
        var count = 0usize
        var tries = 0usize
        var frozen_rows = below(&rng, 3usize)
        var frozen_cols = below(&rng, 3usize)
        if frozen_rows > rows { frozen_rows = rows }
        if frozen_cols > cols { frozen_cols = cols }
        while tries < 40usize && count < 12usize {
            tries += 1usize
            let r0 = below(&rng, rows)
            let c0 = below(&rng, cols)
            let h = 1usize + below(&rng, 4usize)
            let w = 1usize + below(&rng, 4usize)
            if r0 + h > rows || c0 + w > cols || h * w < 2usize { continue }
            if (r0 < frozen_rows && r0 + h > frozen_rows) || (c0 < frozen_cols && c0 + w > frozen_cols) { continue }
            var clash = false
            var rr = r0
            while rr < r0 + h {
                var cc = c0
                while cc < c0 + w {
                    if occupied[rr * 32usize + cc] != 0u8 { clash = true }
                    cc += 1usize
                }
                rr += 1usize
            }
            if clash { continue }
            rr = r0
            while rr < r0 + h {
                var cc = c0
                while cc < c0 + w {
                    occupied[rr * 32usize + cc] = 1u8
                    cc += 1usize
                }
                rr += 1usize
            }
            list[count] = sh.Merge { row: r0, col: c0, rows: h, cols: w }
            count += 1usize
        }
        let (merge_set, merge_error) = sh.merges(a, list[0usize..count], rows, cols)
        if merge_error != ok { ret fail(3i32) }
        let (g, grid_error) = sh.grid(row_axis, col_axis, merge_set, frozen_rows, frozen_cols)
        if grid_error != ok { ret fail(4i32) }
        // every cell's owner against the matrix
        var r = 0usize
        while r < rows {
            var c = 0usize
            while c < cols {
                let o = sh.owner(g, r, c)
                var expect_row = r
                var expect_col = c
                var expect_rows = 1usize
                var expect_cols = 1usize
                var m = 0usize
                while m < count {
                    let mg = list[m]
                    if r >= mg.row && r < mg.row + mg.rows && c >= mg.col && c < mg.col + mg.cols {
                        expect_row = mg.row
                        expect_col = mg.col
                        expect_rows = mg.rows
                        expect_cols = mg.cols
                    }
                    m += 1usize
                }
                if o.row != expect_row || o.col != expect_col || o.rows != expect_rows || o.cols != expect_cols { ret fail(1600i32 + i32(round)) }
                c += 1usize
            }
            r += 1usize
        }
        // viewports
        var view_round = 0usize
        while view_round < 6usize {
            let width = f32(60 + below(&rng, 500usize))
            let height = f32(40 + below(&rng, 400usize))
            let header_w = f32(below(&rng, 3usize) * 20)
            let header_h = f32(below(&rng, 3usize) * 12)
            var view = sh.View { x: f32(below(&rng, 600usize)), y: f32(below(&rng, 600usize)), width: width, height: height, header_width: header_w, header_height: header_h }
            let (cx, cy) = sh.clamp_scroll(g, view)
            let (max_x, max_y) = sh.scroll_limits(g, view)
            if cx < 0.0 || cy < 0.0 || cx > max_x + 0.001 || cy > max_y + 0.001 { ret fail(1900i32 + i32(round)) }
            if view.x <= max_x && !near(cx, view.x) && view.x >= 0.0 { ret fail(2000i32 + i32(round)) }
            view.x = cx
            view.y = cy
            let frozen_w = naive_start(col_sizes[0..], frozen_cols)
            let frozen_h = naive_start(row_sizes[0..], frozen_rows)
            let (cells, cells_error) = sh.visible_cells(a, g, view)
            if cells_error != ok { ret fail(5i32) }
            // brute force: every owner whose rectangle meets the viewport
            var seen: [2048]u8 = zero
            var expected = 0usize
            var br = 0usize
            while br < rows {
                var bc = 0usize
                while bc < cols {
                    let o = sh.owner(g, br, bc)
                    if o.row == br && o.col == bc {
                        var x = naive_start(col_sizes[0..], bc)
                        if bc >= frozen_cols { x = x - view.x }
                        var y = naive_start(row_sizes[0..], br)
                        if br >= frozen_rows { y = y - view.y }
                        let w = naive_start(col_sizes[0..], bc + o.cols) - naive_start(col_sizes[0..], bc)
                        let h = naive_start(row_sizes[0..], br + o.rows) - naive_start(row_sizes[0..], br)
                        let under_columns = bc >= frozen_cols && (x + w <= frozen_w || width <= frozen_w)
                        let under_rows = br >= frozen_rows && (y + h <= frozen_h || height <= frozen_h)
                        if x < width && x + w > 0.0 && y < height && y + h > 0.0 && w > 0.0 && h > 0.0 && !under_columns && !under_rows {
                            expected += 1usize
                            seen[br * 32usize + bc] = 1u8
                        }
                    }
                    bc += 1usize
                }
                br += 1usize
            }
            // the frozen part overlays the scrolled part: brute force counts scrolled cells under the freeze lines too,
            // as the library does (the renderer clips); a cell is listed once and at the naive rectangle
            if cells.len != expected { ret fail(2300i32 + i32(round) * 10i32 + i32(view_round)) }
            var k = 0usize
            while k < cells.len {
                let cr = cells[k]
                if seen[cr.row * 32usize + cr.col] != 1u8 { ret fail(3600i32 + i32(round)) }
                var x = naive_start(col_sizes[0..], cr.col)
                if cr.col >= frozen_cols { x = x - view.x }
                var y = naive_start(row_sizes[0..], cr.row)
                if cr.row >= frozen_rows { y = y - view.y }
                if !near(cr.rect.x, x) || !near(cr.rect.y, y) { ret fail(3800i32 + i32(round)) }
                k += 1usize
            }
            // points inside drawn cells hit them (where nothing frozen lies over them)
            k = 0usize
            while k < cells.len {
                let cr = cells[k]
                var left = cr.rect.x
                var top = cr.rect.y
                var right = cr.rect.x + cr.rect.width
                var bottom = cr.rect.y + cr.rect.height
                if cr.col >= frozen_cols && left < frozen_w { left = frozen_w }
                if cr.row >= frozen_rows && top < frozen_h { top = frozen_h }
                if right > width { right = width }
                if bottom > height { bottom = height }
                if left < right && top < bottom {
                    let px = (left + right) * 0.5 + header_w
                    let py = (top + bottom) * 0.5 + header_h
                    let hit = sh.hit_test(g, view, px, py)
                    if hit.region != .Cell || hit.row != cr.row || hit.col != cr.col { ret fail(4000i32 + i32(round)) }
                }
                k += 1usize
            }
            // headers, the corner and outside
            if header_w > 0.0 && header_h > 0.0 && sh.hit_test(g, view, header_w * 0.5, header_h * 0.5).region != .Corner { ret fail(4300i32 + i32(round)) }
            if header_h > 0.0 && sh.hit_test(g, view, header_w + 1.0, header_h * 0.5).region != .ColumnHeader { ret fail(4400i32 + i32(round)) }
            if header_w > 0.0 && sh.hit_test(g, view, header_w * 0.5, header_h + 1.0).region != .RowHeader { ret fail(4500i32 + i32(round)) }
            if sh.hit_test(g, view, -1.0, 5.0).region != .Outside || sh.hit_test(g, view, header_w + width, header_h + 1.0).region != .Outside { ret fail(4600i32 + i32(round)) }
            // reveal: a cell shown stays, a cell revealed is shown
            let rr = below(&rng, rows)
            let cc = below(&rng, cols)
            let (rx, ry) = sh.reveal(g, view, rr, cc)
            let moved = sh.View { x: rx, y: ry, width: width, height: height, header_width: header_w, header_height: header_h }
            let (mx, my) = sh.clamp_scroll(g, moved)
            if !near(mx, rx) || !near(my, ry) { ret fail(4700i32 + i32(round)) }
            let shown = sh.cell_rect(g, moved, rr, cc)
            var fits_x = shown.rect.width <= width - frozen_w + 0.001
            var fits_y = shown.rect.height <= height - frozen_h + 0.001
            if shown.col >= frozen_cols && fits_x && (shown.rect.x < frozen_w - 0.001 || shown.rect.x + shown.rect.width > width + 0.001) && shown.rect.width > 0.0 { ret fail(4800i32 + i32(round)) }
            if shown.row >= frozen_rows && fits_y && (shown.rect.y < frozen_h - 0.001 || shown.rect.y + shown.rect.height > height + 0.001) && shown.rect.height > 0.0 { ret fail(4900i32 + i32(round)) }
            view_round += 1usize
        }
        // selection ranges: whole merges, containing both ends
        var sel_round = 0usize
        while sel_round < 20usize {
            let s = sh.Selection { row: below(&rng, rows), col: below(&rng, cols), anchor_row: below(&rng, rows), anchor_col: below(&rng, cols) }
            let range = sh.selection_range(g, s)
            let last_row = range.row + range.rows - 1usize
            let last_col = range.col + range.cols - 1usize
            if s.row < range.row || s.row > last_row || s.anchor_row < range.row || s.anchor_row > last_row || s.col < range.col || s.col > last_col || s.anchor_col < range.col || s.anchor_col > last_col { ret fail(5000i32 + i32(round)) }
            var m = 0usize
            while m < count {
                let mg = list[m]
                let inside_all = mg.row >= range.row && mg.row + mg.rows - 1usize <= last_row && mg.col >= range.col && mg.col + mg.cols - 1usize <= last_col
                let touches = mg.row <= last_row && mg.row + mg.rows > range.row && mg.col <= last_col && mg.col + mg.cols > range.col
                if touches && !inside_all { ret fail(5200i32 + i32(round)) }
                m += 1usize
            }
            // minimal: shrinking any side would cut a merge or drop an end
            sel_round += 1usize
        }
        // navigation against the matrix
        var nav_round = 0usize
        while nav_round < 30usize {
            let start_row = below(&rng, rows)
            let start_col = below(&rng, cols)
            let s0 = sh.Selection { row: start_row, col: start_col, anchor_row: start_row, anchor_col: start_col }
            let here = sh.owner(g, start_row, start_col)
            // rightwards: the next visible column past the merge, same row
            var col = here.col
            var found_col = false
            var c2 = here.col + here.cols
            while c2 < cols && !found_col {
                if col_sizes[c2] > 0.0 {
                    col = c2
                    found_col = true
                }
                c2 += 1usize
            }
            let moved = sh.navigate(g, s0, .Right, false, 5usize)
            let expect = sh.owner(g, here.row, col)
            if moved.row != expect.row || moved.col != expect.col { ret fail(5400i32 + i32(round)) }
            if moved.anchor_row != moved.row || moved.anchor_col != moved.col { ret fail(5600i32 + i32(round)) }
            // upwards: the previous visible row above the merge's top
            var up_row = here.row
            var found_up = false
            var r2 = here.row
            while r2 > 0usize && !found_up {
                r2 -= 1usize
                if row_sizes[r2] > 0.0 {
                    up_row = r2
                    found_up = true
                }
            }
            let up = sh.navigate(g, s0, .Up, false, 5usize)
            let expect_up = sh.owner(g, up_row, here.col)
            if up.row != expect_up.row || up.col != expect_up.col { ret fail(5800i32 + i32(round)) }
            // extending keeps the anchor
            let wide = sh.navigate(g, s0, .Right, true, 5usize)
            if wide.anchor_row != start_row || wide.anchor_col != start_col { ret fail(6000i32 + i32(round)) }
            // first and last
            let top_left = sh.navigate(g, s0, .First, false, 5usize)
            let first_r = naive_index(row_sizes[0..], rows, 0.0)
            let first_c = naive_index(col_sizes[0..], cols, 0.0)
            let expect_first = sh.owner(g, first_r, first_c)
            if top_left.row != expect_first.row || top_left.col != expect_first.col { ret fail(6200i32 + i32(round)) }
            nav_round += 1usize
        }
        mem.reset(a, mark)
        round += 1usize
    }
    // ---- hand cases ----
    let none: [0]sh.Override = zero
    let (small_rows, e1) = sh.axis(a, 10usize, 20.0, none[0..])
    let (small_cols, e2) = sh.axis(a, 6usize, 50.0, none[0..])
    if e1 != ok || e2 != ok { ret fail(7000i32) }
    let overlapping = [2]sh.Merge{ sh.Merge { row: 1usize, col: 1usize, rows: 2usize, cols: 2usize }, sh.Merge { row: 2usize, col: 2usize, rows: 2usize, cols: 2usize } }
    let (_, clash) = sh.merges(a, overlapping[0..], 10usize, 6usize)
    let single = [1]sh.Merge{ sh.Merge { row: 1usize, col: 1usize, rows: 1usize, cols: 1usize } }
    let (_, lone) = sh.merges(a, single[0..], 10usize, 6usize)
    let outside = [1]sh.Merge{ sh.Merge { row: 8usize, col: 1usize, rows: 3usize, cols: 1usize } }
    let (_, past) = sh.merges(a, outside[0..], 10usize, 6usize)
    if clash != sh.Invalid || lone != sh.Invalid || past != sh.Invalid { ret fail(7001i32) }
    let across = [1]sh.Merge{ sh.Merge { row: 0usize, col: 1usize, rows: 2usize, cols: 1usize } }
    let (across_set, across_error) = sh.merges(a, across[0..], 10usize, 6usize)
    if across_error != ok { ret fail(7002i32) }
    let (_, freeze_error) = sh.grid(small_rows, small_cols, across_set, 1usize, 0usize)
    if freeze_error != sh.Invalid { ret fail(7003i32) }
    let bad_sizes = [2]sh.Override{ sh.Override { index: 3usize, size: 10.0 }, sh.Override { index: 3usize, size: 12.0 } }
    let (_, dup_error) = sh.axis(a, 10usize, 20.0, bad_sizes[0..])
    let negative = [1]sh.Override{ sh.Override { index: 3usize, size: -1.0 } }
    let (_, neg_error) = sh.axis(a, 10usize, 20.0, negative[0..])
    let (_, zero_default) = sh.axis(a, 10usize, 0.0, none[0..])
    if dup_error != sh.Invalid || neg_error != sh.Invalid || zero_default != sh.Invalid { ret fail(7004i32) }
    // a million rows: sizes without a table
    let tall = [3]sh.Override{ sh.Override { index: 10usize, size: 60.0 }, sh.Override { index: 500000usize, size: 0.0 }, sh.Override { index: 999999usize, size: 40.0 } }
    let (million, million_error) = sh.axis(a, 1000000usize, 20.0, tall[0..])
    if million_error != ok { ret fail(7005i32) }
    if !near(sh.axis_total(million), 20000040.0) { ret fail(7006i32) }
    if !near(sh.axis_start(million, 11usize), 11.0 * 20.0 + 40.0) || sh.axis_index_at(million, sh.axis_start(million, 700000usize) + 3.0) != 700000usize { ret fail(7007i32) }
    if sh.axis_index_at(million, sh.axis_start(million, 500000usize)) != 500001usize { ret fail(7008i32) }
    // a worked example: 6 columns of 50, rows of 20 with row 2 hidden and row 3 tall, a 2 by 2 merge at (1, 1) and frozen row 1
    let row_over = [2]sh.Override{ sh.Override { index: 2usize, size: 0.0 }, sh.Override { index: 3usize, size: 40.0 } }
    let (hand_rows, hr_error) = sh.axis(a, 10usize, 20.0, row_over[0..])
    let two = [1]sh.Merge{ sh.Merge { row: 1usize, col: 1usize, rows: 2usize, cols: 2usize } }
    let (two_set, two_error) = sh.merges(a, two[0..], 10usize, 6usize)
    let (hand, hand_error) = sh.grid(hand_rows, small_cols, two_set, 1usize, 1usize)
    if hr_error != ok || two_error != ok || hand_error != ok { ret fail(7009i32) }
    let view = sh.View { x: 0.0, y: 0.0, width: 200.0, height: 100.0, header_width: 30.0, header_height: 20.0 }
    let merged = sh.cell_rect(hand, view, 2usize, 2usize)
    if merged.row != 1usize || merged.col != 1usize || !near(merged.rect.x, 50.0) || !near(merged.rect.y, 20.0) || !near(merged.rect.width, 100.0) || !near(merged.rect.height, 20.0) { ret fail(7010i32) }
    let tall_cell = sh.cell_rect(hand, view, 3usize, 0usize)
    if !near(tall_cell.rect.y, 40.0) || !near(tall_cell.rect.height, 40.0) { ret fail(7011i32) }
    let scrolled = sh.View { x: 25.0, y: 20.0, width: 200.0, height: 100.0, header_width: 30.0, header_height: 20.0 }
    let moved_cell = sh.cell_rect(hand, scrolled, 3usize, 3usize)
    if !near(moved_cell.rect.x, 125.0) || !near(moved_cell.rect.y, 20.0) { ret fail(7012i32) }
    let frozen_cell = sh.cell_rect(hand, scrolled, 0usize, 0usize)
    if !near(frozen_cell.rect.x, 0.0) || !near(frozen_cell.rect.y, 0.0) { ret fail(7013i32) }
    // navigation across the merge: Right from (1, 1) lands on (1, 3), Down from it on (3, 1) -- row 2 is hidden and covered
    let start = sh.Selection { row: 2usize, col: 2usize, anchor_row: 2usize, anchor_col: 2usize }
    let right = sh.navigate(hand, start, .Right, false, 3usize)
    if right.row != 1usize || right.col != 3usize { ret fail(7014i32) }
    let down = sh.navigate(hand, start, .Down, false, 3usize)
    if down.row != 3usize || down.col != 1usize { ret fail(7015i32) }
    try io.print("ui sheet geometry ok\n")
    ret ok
}
