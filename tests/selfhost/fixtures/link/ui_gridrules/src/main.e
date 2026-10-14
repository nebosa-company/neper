// `e.ui.gridrules`: conditional formatting rules over a table. A ten-row table with known
// values checks every kind (cell-is, text, blank, above / below average, top / bottom with ties
// and percent, duplicate / unique on a number and on a dictionary, the two- and three-colour
// scale, the data bar and the icon set), the priority order, whole-row rules, the refresh after
// an edit and the refusals; then 150,000 rows check top-N and duplicates against a count made
// by the fixture itself. Every check has its own exit code.
use e.os
use e.mem
use e.data.table as table
use e.gfx.paint
use e.ui.style
use e.ui.gridrules as gr

const C_CMC: usize = 0usize
const C_RARITY: usize = 1usize
const C_NAME: usize = 2usize
const BIG: usize = 150000usize

fn mix(x: u64) -> u64 {
    var v = x *% 6364136223846793005u64 +% 1442695040888963407u64
    v = v ^ (v >> 29u64)
    v = v *% 6364136223846793005u64
    ret v ^ (v >> 32u64)
}

fn rarity_name(row: usize) -> str {
    if row == 0usize || row == 6usize { ret "Common" }
    if row == 3usize { ret "common" }
    if row == 2usize || row == 5usize { ret "Mythic" }
    if row == 9usize { ret "Uncommon" }
    ret "Rare"
}

fn card_name(row: usize) -> str {
    if row == 0usize || row == 9usize { ret "Bolt" }
    if row == 1usize { ret "Counterspell" }
    if row == 2usize { ret "Giant Growth" }
    if row == 3usize { ret "Lightning" }
    if row == 4usize { ret "Ancestral" }
    if row == 5usize { ret "Black Lotus" }
    if row == 6usize { ret "Lotus Petal" }
    if row == 7usize { ret "Time Walk" }
    ret "Mox Pearl"
}

fn cmc_of(row: usize) -> i32 {
    if row == 0usize || row == 9usize { ret 3i32 }
    if row == 1usize { ret 1i32 }
    if row == 2usize { ret 4i32 }
    if row == 4usize || row == 8usize { ret 5i32 }
    if row == 5usize { ret 9i32 }
    if row == 6usize { ret 2i32 }
    ret 6i32
}

fn small(a: *mem.Arena) -> table.Table {
    var spec: [3]table.Spec = zero
    spec[C_CMC] = table.Spec { name: "cmc", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_RARITY] = table.Spec { name: "rarity", kind: table.Kind.Dict, heap_bytes: 512usize, dict_cap: 16usize }
    spec[C_NAME] = table.Spec { name: "name", kind: table.Kind.Str, heap_bytes: 1024usize, dict_cap: 0usize }
    let (made, made_error) = table.create(a, spec[0..], 16usize)
    if made_error != ok { os.exit(1) }
    var t = made
    var row = 0usize
    while row < 10usize {
        let (got, append_error) = table.append_row(&t)
        if append_error != ok || got != row { os.exit(2) }
        if row == 3usize { table.set_null(&t, C_CMC, row) } else { table.set_i32(&t, C_CMC, row, cmc_of(row)) }
        if table.set_str(&t, C_RARITY, row, rarity_name(row)) != ok { os.exit(3) }
        if table.set_str(&t, C_NAME, row, card_name(row)) != ok { os.exit(4) }
        row += 1usize
    }
    ret t
}

fn ink_rule(column: usize, kind: gr.Kind) -> gr.Rule {
    var r = gr.rule(column, kind)
    r.has_ink = true
    r.ink = style.ColorRole.Error
    ret r
}

// Bit n is set when the rule set gives row n an ink.
fn inked(rs: *const gr.Rules, column: usize, rows: usize) -> u32 {
    var m = 0u32
    var row = 0usize
    while row < rows {
        if gr.format(rs, row, column).has_ink { m = m | (1u32 << u32(row)) }
        row += 1usize
    }
    ret m
}

// One rule over the small table: the mask of the rows it inks.
fn one(a: *mem.Arena, t: *table.Table, r: gr.Rule, code: i32) -> u32 {
    let (made, made_error) = gr.create(a, t, 4usize)
    if made_error != ok { os.exit(code) }
    var rs = made
    let (_at, add_error) = gr.add(a, &rs, r)
    if add_error != ok { os.exit(code + 1) }
    if gr.refresh(&rs, a) != ok { os.exit(code + 2) }
    ret inked(&rs, r.column, 10usize)
}

fn near(x: f32, y: f32) -> bool {
    var d = x - y
    if d < 0.0f32 { d = 0.0f32 - d }
    ret d < 0.001f32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var t = small(a)
    // cell-is on a number: greater than 5; between 2 and 4 (bounds in either order)
    var r = ink_rule(C_CMC, gr.Kind.CellIs)
    r.op = gr.Op.Gt
    r.a = 5.0f64
    if one(a, &t, r, 10) != 0b0010100000u32 { os.exit(13) }
    r.op = gr.Op.Between
    r.a = 4.0f64
    r.b = 2.0f64
    if one(a, &t, r, 14) != 0b1001000101u32 { os.exit(17) }
    // text on a heap string and on a dictionary
    r = ink_rule(C_NAME, gr.Kind.Text)
    r.op = gr.Op.Ends
    r.text = "LT"
    if one(a, &t, r, 20) != 0b1000000001u32 { os.exit(23) }
    r.op = gr.Op.Contains
    r.text = "lotus"
    if one(a, &t, r, 24) != 0b0001100000u32 { os.exit(27) }
    r.fold = false
    if one(a, &t, r, 28) != 0u32 { os.exit(31) }
    r = ink_rule(C_RARITY, gr.Kind.Text)
    r.op = gr.Op.Begins
    r.text = "co"
    if one(a, &t, r, 32) != 0b0001001001u32 { os.exit(35) }
    r.op = gr.Op.Contains
    r.text = "mm"
    if one(a, &t, r, 36) != 0b1001001001u32 { os.exit(39) }
    r = ink_rule(C_RARITY, gr.Kind.CellIs)
    r.op = gr.Op.Eq
    r.text = "rare"
    if one(a, &t, r, 40) != 0b0110010010u32 { os.exit(43) }
    r.fold = false
    if one(a, &t, r, 44) != 0u32 { os.exit(47) }
    // blank
    if one(a, &t, ink_rule(C_CMC, gr.Kind.Blank), 50) != 0b0000001000u32 { os.exit(53) }
    // above and below the average (38 / 9)
    if one(a, &t, ink_rule(C_CMC, gr.Kind.Above), 54) != 0b0110110000u32 { os.exit(57) }
    if one(a, &t, ink_rule(C_CMC, gr.Kind.Below), 58) != 0b1001000111u32 { os.exit(61) }
    // top and bottom, ties kept, and a percent
    r = ink_rule(C_CMC, gr.Kind.Top)
    r.count = 2usize
    if one(a, &t, r, 62) != 0b0010100000u32 { os.exit(65) }
    r.count = 3usize
    if one(a, &t, r, 66) != 0b0110110000u32 { os.exit(69) }
    r.count = 20usize
    r.percent = true
    if one(a, &t, r, 70) != 0b0010100000u32 { os.exit(73) }
    r = ink_rule(C_CMC, gr.Kind.Bottom)
    r.count = 2usize
    if one(a, &t, r, 74) != 0b0001000010u32 { os.exit(77) }
    // duplicates and uniques on a number and on a dictionary
    if one(a, &t, ink_rule(C_CMC, gr.Kind.Duplicate), 80) != 0b1000010000u32 | 0b0100000001u32 { os.exit(83) }
    if one(a, &t, ink_rule(C_CMC, gr.Kind.Unique), 84) != 0b0011100110u32 { os.exit(87) }
    if one(a, &t, ink_rule(C_RARITY, gr.Kind.Unique), 88) != 0b1000001000u32 { os.exit(91) }
    if one(a, &t, ink_rule(C_RARITY, gr.Kind.Duplicate), 92) != 0b0111110111u32 { os.exit(95) }
    // scales, bars and icons
    let red = paint.rgba(1.0f32, 0.0f32, 0.0f32, 1.0f32)
    let yellow = paint.rgba(1.0f32, 1.0f32, 0.0f32, 1.0f32)
    let green = paint.rgba(0.0f32, 1.0f32, 0.0f32, 1.0f32)
    let (made, made_error) = gr.create(a, &t, 8usize)
    if made_error != ok { os.exit(100) }
    var rs = made
    var scale = gr.rule(C_CMC, gr.Kind.Scale)
    scale.low = red
    scale.mid = yellow
    scale.high = green
    scale.three = true
    let (_s, scale_error) = gr.add(a, &rs, scale)
    if scale_error != ok { os.exit(101) }
    var bar = gr.rule(C_CMC, gr.Kind.Bar)
    bar.fill = paint.rgba(0.0f32, 0.0f32, 1.0f32, 1.0f32)
    let (_b, bar_error) = gr.add(a, &rs, bar)
    if bar_error != ok { os.exit(102) }
    var icons = gr.rule(C_CMC, gr.Kind.Icons)
    let (_i, icon_error) = gr.add(a, &rs, icons)
    if icon_error != ok { os.exit(103) }
    if gr.refresh(&rs, a) != ok { os.exit(104) }
    let low_cell = gr.format(&rs, 1usize, C_CMC)
    let mid_cell = gr.format(&rs, 4usize, C_CMC)
    let high_cell = gr.format(&rs, 5usize, C_CMC)
    if !low_cell.has_fill || !near(low_cell.fill.red, 1.0f32) || !near(low_cell.fill.green, 0.0f32) { os.exit(105) }
    if !mid_cell.has_fill || !near(mid_cell.fill.red, 1.0f32) || !near(mid_cell.fill.green, 1.0f32) { os.exit(106) }
    if !high_cell.has_fill || !near(high_cell.fill.red, 0.0f32) || !near(high_cell.fill.green, 1.0f32) { os.exit(107) }
    if !low_cell.has_bar || !near(low_cell.bar, 0.0f32) || !near(mid_cell.bar, 0.5f32) || !near(high_cell.bar, 1.0f32) { os.exit(108) }
    if low_cell.icon != 1u8 || mid_cell.icon != 2u8 || high_cell.icon != 3u8 || high_cell.buckets != 3u8 { os.exit(109) }
    // a blank cell takes no range look
    if gr.format(&rs, 3usize, C_CMC).has_fill || gr.format(&rs, 3usize, C_CMC).icon != 0u8 { os.exit(110) }
    // a two-colour scale is the straight blend
    var two = gr.rule(C_CMC, gr.Kind.Scale)
    two.low = red
    two.high = green
    let (made2, made2_error) = gr.create(a, &t, 2usize)
    if made2_error != ok { os.exit(111) }
    var rs2 = made2
    let (_t2, two_error) = gr.add(a, &rs2, two)
    if two_error != ok || gr.refresh(&rs2, a) != ok { os.exit(112) }
    let blend = gr.format(&rs2, 4usize, C_CMC)
    if !near(blend.fill.red, 0.5f32) || !near(blend.fill.green, 0.5f32) { os.exit(113) }
    // a Percent bound is a share of the way from the lowest to the highest value: 75% .. 100% of
    // a range whose middle cell sits at 50% leaves the middle cell empty and the top cell full
    var pct = gr.rule(C_CMC, gr.Kind.Bar)
    pct.fill = paint.rgba(0.0f32, 0.0f32, 1.0f32, 1.0f32)
    pct.has_min = true
    pct.min_value = 75.0
    pct.min_pct = true
    pct.has_max = true
    pct.max_value = 100.0
    pct.max_pct = true
    let (made_pct, made_pct_error) = gr.create(a, &t, 2usize)
    if made_pct_error != ok { os.exit(147) }
    var rs_pct = made_pct
    let (_pb, pct_error) = gr.add(a, &rs_pct, pct)
    if pct_error != ok || gr.refresh(&rs_pct, a) != ok { os.exit(148) }
    if !near(gr.format(&rs_pct, 4usize, C_CMC).bar, 0.0f32) || !near(gr.format(&rs_pct, 5usize, C_CMC).bar, 1.0f32) { os.exit(149) }
    // a Percentile bound is the value that far up the sorted values: 0 and 100 are the lowest and the
    // highest, so the bar of the lowest cell is empty and of the highest full
    var ptile = gr.rule(C_CMC, gr.Kind.Bar)
    ptile.fill = paint.rgba(0.0f32, 0.0f32, 1.0f32, 1.0f32)
    ptile.has_min = true
    ptile.min_value = 0.0
    ptile.min_ptile = true
    ptile.has_max = true
    ptile.max_value = 100.0
    ptile.max_ptile = true
    let (made_pt, made_pt_error) = gr.create(a, &t, 2usize)
    if made_pt_error != ok { os.exit(150) }
    var rs_pt = made_pt
    let (_pt, pt_error) = gr.add(a, &rs_pt, ptile)
    if pt_error != ok || gr.refresh(&rs_pt, a) != ok { os.exit(151) }
    if !near(gr.format(&rs_pt, 1usize, C_CMC).bar, 0.0f32) || !near(gr.format(&rs_pt, 5usize, C_CMC).bar, 1.0f32) { os.exit(152) }
    // Bar direction Right To Left (the style window) reaches the cell's look
    if gr.format(&rs_pt, 5usize, C_CMC).bar_rtl { os.exit(156) }
    var rtl = gr.rule(C_CMC, gr.Kind.Bar)
    rtl.fill = paint.rgba(0.0f32, 0.0f32, 1.0f32, 1.0f32)
    rtl.bar_rtl = true
    let (made_rtl, made_rtl_error) = gr.create(a, &t, 2usize)
    if made_rtl_error != ok { os.exit(157) }
    var rs_rtl = made_rtl
    let (_rtl, rtl_error) = gr.add(a, &rs_rtl, rtl)
    if rtl_error != ok || gr.refresh(&rs_rtl, a) != ok { os.exit(158) }
    if !gr.format(&rs_rtl, 5usize, C_CMC).bar_rtl { os.exit(159) }
    // the bar's Fill mode Solid and Border style reach the cell's format
    var styled = gr.rule(C_CMC, gr.Kind.Bar)
    styled.bar_solid = true
    styled.bar_border = true
    let (made_sty, made_sty_error) = gr.create(a, &t, 2usize)
    if made_sty_error != ok { os.exit(153) }
    var rs_sty = made_sty
    let (_sty, sty_error) = gr.add(a, &rs_sty, styled)
    if sty_error != ok || gr.refresh(&rs_sty, a) != ok { os.exit(154) }
    let sty_look = gr.format(&rs_sty, 5usize, C_CMC)
    if !sty_look.has_bar || !sty_look.bar_solid || !sty_look.bar_border { os.exit(155) }
    // priority: the first rule that sets a field wins; the other field still merges in
    let (made3, made3_error) = gr.create(a, &t, 4usize)
    if made3_error != ok { os.exit(114) }
    var rs3 = made3
    var first = gr.rule(C_CMC, gr.Kind.CellIs)
    first.op = gr.Op.Gt
    first.a = 5.0f64
    first.has_ink = true
    first.ink = style.ColorRole.Error
    var second = gr.rule(C_CMC, gr.Kind.CellIs)
    second.op = gr.Op.Gt
    second.a = 2.0f64
    second.has_ink = true
    second.ink = style.ColorRole.Success
    second.bold = true
    let (_f, first_error) = gr.add(a, &rs3, first)
    let (_g, second_error) = gr.add(a, &rs3, second)
    if first_error != ok || second_error != ok || gr.refresh(&rs3, a) != ok { os.exit(115) }
    let nine = gr.format(&rs3, 5usize, C_CMC)
    let four = gr.format(&rs3, 2usize, C_CMC)
    if nine.ink != style.ColorRole.Error || !nine.bold { os.exit(116) }
    if four.ink != style.ColorRole.Success || !four.bold { os.exit(117) }
    if gr.format(&rs3, 1usize, C_CMC).has_ink || gr.format(&rs3, 1usize, C_CMC).bold { os.exit(118) }
    // a whole-row rule formats the other columns of the row too, and no other row
    var wide = ink_rule(C_CMC, gr.Kind.CellIs)
    wide.op = gr.Op.Gt
    wide.a = 5.0f64
    wide.whole_row = true
    let (made4, made4_error) = gr.create(a, &t, 2usize)
    if made4_error != ok { os.exit(119) }
    var rs4 = made4
    let (_w, wide_error) = gr.add(a, &rs4, wide)
    if wide_error != ok || gr.refresh(&rs4, a) != ok { os.exit(120) }
    if !gr.format(&rs4, 5usize, C_NAME).has_ink || !gr.format(&rs4, 5usize, C_RARITY).has_ink || gr.format(&rs4, 4usize, C_NAME).has_ink { os.exit(121) }
    // an edit and a refresh move the statistics: row 1 becomes the largest
    let (made5, made5_error) = gr.create(a, &t, 2usize)
    if made5_error != ok { os.exit(122) }
    var rs5 = made5
    var top = ink_rule(C_CMC, gr.Kind.Top)
    top.count = 1usize
    let (_p, top_error) = gr.add(a, &rs5, top)
    if top_error != ok || gr.refresh(&rs5, a) != ok { os.exit(123) }
    if inked(&rs5, C_CMC, 10usize) != 0b0000100000u32 { os.exit(124) }
    table.set_i32(&t, C_CMC, 1usize, 12i32)
    if gr.refresh(&rs5, a) != ok { os.exit(125) }
    if inked(&rs5, C_CMC, 10usize) != 0b0000000010u32 { os.exit(126) }
    // refusals: a text rule on a number, a numeric rule on a string, a missing column, too many
    var bad = gr.rule(C_CMC, gr.Kind.Text)
    bad.op = gr.Op.Contains
    let (_x, bad_error) = gr.add(a, &rs5, bad)
    if bad_error != gr.BadRule { os.exit(127) }
    let (_y, str_error) = gr.add(a, &rs5, gr.rule(C_NAME, gr.Kind.Duplicate))
    if str_error != gr.BadRule { os.exit(128) }
    let (_z, column_error) = gr.add(a, &rs5, gr.rule(9usize, gr.Kind.Blank))
    if column_error != gr.BadColumn { os.exit(129) }
    let (_u, fits_error) = gr.add(a, &rs5, gr.rule(C_CMC, gr.Kind.Blank))
    if fits_error != ok { os.exit(130) }
    let (_v, full_error) = gr.add(a, &rs5, gr.rule(C_CMC, gr.Kind.Blank))
    if full_error != gr.TooMany { os.exit(131) }
    // 150,000 rows: top 100 and duplicates against a count of the fixture's own
    var spec: [1]table.Spec = zero
    spec[0usize] = table.Spec { name: "v", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    let (bigmade, big_error) = table.create(a, spec[0..], BIG)
    if big_error != ok { os.exit(140) }
    var big = bigmade
    var counts: [3000]u32 = zero
    var row = 0usize
    while row < BIG {
        let (_got, append_error) = table.append_row(&big)
        if append_error != ok { os.exit(141) }
        let v = i32(mix(u64(row) + 7u64) % 3000u64)
        table.set_i32(&big, 0usize, row, v)
        counts[usize(v)] += 1u32
        row += 1usize
    }
    let (made6, made6_error) = gr.create(a, &big, 4usize)
    if made6_error != ok { os.exit(142) }
    var rs6 = made6
    var top100 = ink_rule(0usize, gr.Kind.Top)
    top100.count = 100usize
    var dup = ink_rule(0usize, gr.Kind.Duplicate)
    dup.has_ink = false
    dup.has_fill = true
    dup.fill = red
    let (_a1, a1_error) = gr.add(a, &rs6, top100)
    let (_a2, a2_error) = gr.add(a, &rs6, dup)
    if a1_error != ok || a2_error != ok { os.exit(143) }
    if gr.refresh(&rs6, a) != ok { os.exit(144) }
    // the 100th largest by counting down from the top of the value range
    var seen = 0usize
    var cut = 2999usize
    while cut > 0usize && seen < 100usize {
        seen += usize(counts[cut])
        if seen < 100usize { cut -= 1usize }
    }
    var want_top = 0usize
    var want_dup = 0usize
    var got_top = 0usize
    var got_dup = 0usize
    row = 0usize
    while row < BIG {
        let v = usize(table.get_i32(&big, 0usize, row))
        if v >= cut { want_top += 1usize }
        if counts[v] > 1u32 { want_dup += 1usize }
        let look = gr.format(&rs6, row, 0usize)
        if look.has_ink { got_top += 1usize }
        if look.has_fill { got_dup += 1usize }
        row += 1usize
    }
    if got_top != want_top || got_top < 100usize { os.exit(145) }
    if got_dup != want_dup || want_dup == 0usize { os.exit(146) }
    os.exit(0)
    ret ok
}
