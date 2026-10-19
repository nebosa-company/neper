// looks5-e: the top grid of the live v3 main window in every captured interaction state, one cell per state:
// docs/ui/looks/<look>/data_grid_top.png, compared with ref/windows/data_grid_top.png (the 576 x 215 crops of
// states/grid-*-main@1x.png at (216, 108), laid out as this sheet is). The card pool as plain rows (Swiftfoot Boots, the
// fourth row, current), the navigator with its first, previous, next and last record buttons and the horizontal thumb.
// States: header pressed (Name), navigator at rest, first, next and last button pressed, row selected with the grid
// focused, row selected with the grid not focused. Run from the repository root.

use e.data.table as table
use e.data.tablegroup as grp
use e.data.tableview as view
use e.gfx.paint
use e.mem
use e.str
use e.ui.control
use e.ui.datagrid as dg
use e.ui.gridlook as gl
use e.ui.layout as ui_layout
use e.ui.looks
use e.ui.style
use e.ui.widget

const ROWS: usize = 120283usize
const CELLS: usize = 32usize
const C_NAME: usize = 0usize
const C_ED: usize = 1usize
const C_COLOR: usize = 2usize
const C_TYPE: usize = 3usize
const C_RARITY: usize = 4usize
const C_FAV: usize = 5usize
// hidden: the groups' order (round 12: v3 lists the capture's last seven editions as MSH, HOC, HOB, SLZ, FRC, FRA, MBC)
const C_RANK: usize = 6usize

type App = struct {
    a: *mem.Arena,
    ready: bool,
    windows: bool,
    tbl: table.Table,
    views: [CELLS]view.View,
    groups: [CELLS]grp.Grouping,
    grids: [CELLS]dg.Grid,
    scratch: mem.Arena,
    first: usize,
    count: usize,
    light: bool
}

fn name_of(row: usize) -> str {
    if row == 9usize { ret "Dust to Dust" }
    if row == 10usize { ret "Euru, Acorn Scrounger" }
    let k = row % 9usize
    if k == 0usize { ret "Path of Ancestry" }
    if k == 1usize { ret "Exotic Orchard" }
    if k == 2usize { ret "Thought Vessel" }
    if k == 3usize { ret "Swiftfoot Boots" }
    if k == 4usize { ret "Mind Stone" }
    if k == 5usize { ret "Jeweled Amulet" }
    if k == 6usize { ret "Fellwar Stone" }
    if k == 7usize { ret "Chromatic Lantern" }
    ret "Chaos Warp"
}

fn type_of(row: usize) -> str {
    if row == 9usize { ret "Sorcery" }
    if row == 10usize { ret "Legendary Creature — Squirrel" }
    let k = row % 9usize
    if k == 0usize || k == 1usize { ret "Land" }
    if k == 3usize { ret "Artifact — Equipment" }
    if k == 8usize { ret "Instant" }
    ret "Artifact"
}

fn rarity_of(row: usize) -> str {
    if row == 9usize || row == 10usize { ret "U" }
    let k = row % 9usize
    if k == 0usize { ret "C" }
    if k == 1usize || k == 7usize || k == 8usize { ret "R" }
    ret "U"
}

fn color_of(row: usize) -> str {
    if row == 9usize { ret "W" }
    if row == 10usize { ret "M" }
    if row % 9usize == 8usize { ret "R" }
    ret "N"
}

// the editions of the grouped captures (hover-grid-grouped-rest): MBC holds the first 80 cards, the others follow
fn ed_of(row: usize) -> str {
    if row < 80usize { ret "MBC" }
    if row < 626usize { ret "MSH" }
    if row < 784usize { ret "HOC" }
    if row < 1120usize { ret "HOB" }
    if row < 1483usize { ret "SLZ" }
    if row < 1603usize { ret "FRC" }
    if row < 2173usize { ret "FRA" }
    let k = (row / 1200usize) % 90usize
    if k < 10usize { ret "Z0" }
    ret "Z1"
}

// round 12: about 690 other editions (Z000 ...) precede the seven, so the grouped list is long (its thumb at the minimum)
fn filler_names(a: *mem.Arena) -> ([]str, err) {
    let (names, names_error) = mem.alloc[str](a, 690usize)
    if names_error != ok { ret (zero, names_error) }
    var i = 0usize
    while i < 690usize {
        let (b, b_error) = str.builder(a, 4usize)
        if b_error != ok { ret (zero, b_error) }
        var sb = b
        if str.push(&sb, "Z") != ok { ret (zero, control.TooLarge) }
        if str.push_usize(&sb, 1000usize + i) != ok { ret (zero, control.TooLarge) }
        names[i] = str.done(&sb)
        i += 1usize
    }
    ret (names, ok)
}

fn rank_of(row: usize) -> i32 {
    if row >= 2173usize { ret 0i32 }
    if row < 80usize { ret 7i32 }
    if row < 626usize { ret 1i32 }
    if row < 784usize { ret 2i32 }
    if row < 1120usize { ret 3i32 }
    if row < 1483usize { ret 4i32 }
    if row < 1603usize { ret 5i32 }
    ret 6i32
}

// cells 25 and 27 to 30 show the grid grouped by Edition
fn grouped(k: usize) -> bool { ret k >= 25usize && k != 26usize && k < 31usize }

fn load(a: *mem.Arena, app: *App) -> err {
    var spec: [7]table.Spec = zero
    spec[C_FAV] = table.Spec { name: "Fav", kind: table.Kind.Bool, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_NAME] = table.Spec { name: "Name", kind: table.Kind.Dict, heap_bytes: 1024usize, dict_cap: 16usize }
    spec[C_ED] = table.Spec { name: "Edition", kind: table.Kind.Dict, heap_bytes: 8192usize, dict_cap: 1024usize }
    spec[C_RANK] = table.Spec { name: "Rank", kind: table.Kind.I32, heap_bytes: 0usize, dict_cap: 0usize }
    spec[C_COLOR] = table.Spec { name: "Color", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 4usize }
    spec[C_TYPE] = table.Spec { name: "Type", kind: table.Kind.Dict, heap_bytes: 256usize, dict_cap: 8usize }
    spec[C_RARITY] = table.Spec { name: "Rarity", kind: table.Kind.Dict, heap_bytes: 64usize, dict_cap: 4usize }
    let (fillers, fillers_error) = filler_names(a)
    if fillers_error != ok { ret fillers_error }
    let (made, made_error) = table.create(a, spec[0..], ROWS)
    if made_error != ok { ret made_error }
    app.tbl = made
    table.begin_load(&app.tbl)
    var row = 0usize
    while row < ROWS {
        let (got, append_error) = table.append_row(&app.tbl)
        if append_error != ok { ret append_error }
        try table.set_str(&app.tbl, C_NAME, got, name_of(row))
        if row >= 2173usize && app.windows {
            try table.set_str(&app.tbl, C_ED, got, fillers[((row - 2173usize) / 171usize) % 690usize])
        } else {
            try table.set_str(&app.tbl, C_ED, got, ed_of(row))
        }
        table.set_i32(&app.tbl, C_RANK, got, rank_of(row))
        try table.set_str(&app.tbl, C_COLOR, got, color_of(row))
        try table.set_str(&app.tbl, C_TYPE, got, type_of(row))
        try table.set_str(&app.tbl, C_RARITY, got, rarity_of(row))
        table.set_bool(&app.tbl, C_FAV, got, false)
        row += 1usize
    }
    table.end_load(&app.tbl)
    ret ok
}


// round 18: v3's rarity icons (the shield with a question mark: black common, gold rare, grey uncommon), 15 x 17 px from the capture
// (ref/windows/data_grid_top.png rows 1 to 3); 'ZZZZZZ' is a transparent pixel so the icon takes the row's own fill
fn rarity_icon_c() -> str { ret "D4D4D49A9A9A6666664242425252527878788E8E8E929292868686656565373737393939575757868686C4C4C47272722D2D2D0B0B0B4B4B4B9F9F9FD0D0D0E7E7E7EBEBEBE3E3E3C6C6C68E8E8E2D2D2D0909091E1E1E4D4D4D444444080808212121ABABABE4E4E4EDEDEDEFEFEFEFEFEFEEEEEEEDEDEDE2E2E29494941919190303031414145C5C5C0A0A0A1C1C1CC0C0C0ECECECEFEFEFDEDEDE9D9D9DC9C9C9EBEBEBEEEEEEDEDEDE4F4F4F0808082626267E7E7E101010050505828282E2E2E2EFEFEFA2A2A2383838898989E2E2E2EFEFEFEEEEEE898989131313454545A6A6A6171717000000313131C8C8C8EDEDED6C6C6C1010106C6C6CDEDEDEEFEFEFEFEFEFA4A4A41818186B6B6BD0D0D0242424010101080808828282B9B9B94646461111118B8B8BE3E3E3EFEFEFEFEFEF999999161616999999E9E9E94848480707070000002F2F2F525252414141676767C6C6C6EBEBEBEFEFEFEBEBEB666666222222BFBFBFZZZZZZ838383111111000000070707282828868686C8C8C8E8E8E8EFEFEFEDEDEDB2B2B22D2D2D4D4D4DD5D5D5ZZZZZZC1C1C12424240202020000001D1D1DAEAEAEE7E7E7EFEFEFDFDFDFACACAC5050501010108D8D8DE4E4E4ZZZZZZE6E6E65656560909090000000808087C7C7CE1E1E1E5E5E58B8B8B4444441212122A2A2AC1C1C1ECECECZZZZZZZZZZZZA2A2A21B1B1B0101010101015F5F5FDCDCDCDFDFDF4242420D0D0D050505737373DDDDDDZZZZZZZZZZZZZZZZZZDADADA4E4E4E080808292929959595E4E4E4E6E6E66969690F0F0F292929B8B8B8EAEAEAZZZZZZZZZZZZZZZZZZZZZZZZA0A0A0202020575757CCCCCCEDEDEDEDEDEDA4A4A4242424797979DDDDDDZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZDCDCDC6161614B4B4BB2B2B2E9E9E9D9D9D97E7E7E525252C1C1C1EBEBEBZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZB6B6B64747475D5D5DB0B0B08888884B4B4B9B9B9BE3E3E3ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZE5E5E58C8C8C3333334F4F4F3A3A3A747474D5D5D5ZZZZZZZZZZZZZZZZZZZZZZZZ" }
fn rarity_icon_r() -> str { ret "F4F1E3DED2A6C9B66FBCA249C1AA58D0BE7FD7C994D9CB99D4C58CC8B46BB69B3BB79D3EC3AE5FD6C791EEE8D2CEBC7BB29631A4830CBEA54EDFD3A8F3EEDDFCFAF6FDFCFAFAF9F2EEE8D2D8CA96B1952FA38209AC8E21BFA854BBA249A38108AD8F22E3D9B5FBF9F3FEFEFDFFFFFFFFFFFFFFFFFEFEFEFCF9F8F0DBCD9CAA8B1AA17E03A88816C5AF61A4820AAB8C1EECE6CDFEFDFCFFFFFFF8F5EDDFD3A9F0EAD7FDFDFAFFFFFEF9F6ECBFA854A38209AF9128D2C185A68611A28005D4C48CFAF8F1FFFFFFE1D5AEB79C3DD7C894FAF8F1FFFFFFFFFEFED6C792A78714BBA249E1D7B1A98918A07D00B49936F0EAD5FEFEFDCBB874A78612CAB773F8F6EDFFFFFFFFFFFFE1D7AFA98A19CAB771F2EEDEAE9026A07E01A38209D4C48BEAE2C7BDA44CA78612D7C894FAF9F2FFFFFFFFFFFFDCD0A3A98918DDD0A3FDFCF9BCA34CA38007A07D00B49733C1AA58BAA045C9B46CEEE8D2FDFDFBFFFFFFFDFDFBC8B56EAE8F24ECE5CCZZZZZZD4C38BA78612A07D00A38108B0932BD5C58EEFEAD4FCFBF7FFFFFEFEFEFDE7DEBEB29631BEA651F5F1E3ZZZZZZEDE5CDAE9026A17E02A07D00AC8D20E6DCBAFCFBF7FFFFFFF9F6EEE5DBB9C1A957A78612D8C996FAF9F3ZZZZZZFCFAF5C2AB5BA4820AA07D00A38209D2C185F9F7F0FBF9F4D8CA96BCA24AA78713B1942CEDE6CEFEFDFCZZZZZZZZZZZZE0D5ACAB8B1DA07D01A07E01C6B165F7F4EAF9F6EEBBA147A5840EA27F05CEBB7AF8F5ECZZZZZZZZZZZZZZZZZZF7F4E9BFA753A38109B0932BDBCD9DFBF9F3FCFBF6CAB56FA6850FB0932BE9E1C3FDFCFAZZZZZZZZZZZZZZZZZZZZZZZZDFD4AAAD8E22C3AD5DF1ECDAFEFEFCFEFEFDE1D6AEAE9026CFBE80F7F5EBZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZF7F4EAC6B167BFA650E7DEBFFCFCF8F6F3E8D3C288C0A957ECE6CDFDFDFBZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZE8DFC1BDA34BC6B064E7DDBDD7C792BEA650DDD1A5FAF9F2ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZFBFAF4D7C894B59936C0A856B89C3ECEBC7BF4F0E2ZZZZZZZZZZZZZZZZZZZZZZZZ" }
fn rarity_icon_u() -> str { ret "E5E5E5CDCDCDB7B7B7A9A9A9AEAEAEBDBDBDC5C5C5C7C7C7C2C2C2B5B5B5A3A3A3A5A5A5B2B2B2C5C5C5DDDDDDBCBCBCA0A0A0919191AAAAAACDCDCDE1E1E1ECECECEDEDEDEAEAEADEDEDEC5C5C59E9E9E909090999999AEAEAEA8A8A88F8F8F999999D3D3D3EAEAEAEEEEEEEFEFEFEFEFEFEFEFEFEEEEEEE9E9E9C8C8C89696968D8D8D949494B2B2B2909090989898DCDCDCEEEEEEEFEFEFE8E8E8CECECEE0E0E0EDEDEDEFEFEFE8E8E8ACACAC8F8F8F9B9B9BC1C1C19393938E8E8EC3C3C3EAEAEAEFEFEFD0D0D0A4A4A4C6C6C6EAEAEAEFEFEFEEEEEEC4C4C4949494A8A8A8D0D0D09595958C8C8CA1A1A1DFDFDFEEEEEEB9B9B9939393B8B8B8E8E8E8EFEFEFEFEFEFD1D1D1969696B8B8B8E2E2E29B9B9B8C8C8C8F8F8FC3C3C3D9D9D9A9A9A9939393C5C5C5EAEAEAEFEFEFEFEFEFCCCCCC959595CACACAZZZZZZAAAAAA8F8F8F8C8C8CA1A1A1AFAFAFA7A7A7B5B5B5DEDEDEEDEDEDEFEFEFEEEEEEB7B7B79A9A9ADADADAZZZZZZC2C2C29393938C8C8C8F8F8F9D9D9DC3C3C3DEDEDEECECECEFEFEFEEEEEED7D7D79F9F9FABABABE4E4E4ZZZZZZDCDCDC9B9B9B8D8D8D8C8C8C999999D4D4D4ECECECEFEFEFE9E9E9D4D4D4AEAEAE939393C6C6C6EAEAEAZZZZZZEBEBEBAFAFAF9090908C8C8C8F8F8FC0C0C0E9E9E9EBEBEBC6C6C6A9A9A99494949D9D9DDCDCDCZZZZZZZZZZZZZZZZZZCECECE9797978C8C8C8C8C8CB3B3B3E7E7E7E8E8E8A7A7A79292928E8E8EBBBBBBE7E7E7ZZZZZZZZZZZZZZZZZZE6E6E6ACACAC8F8F8F9D9D9DC9C9C9EAEAEAEBEBEBB7B7B79292929C9C9CD8D8D8ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZCDCDCD999999B0B0B0E0E0E0EEEEEEEEEEEED0D0D09B9B9BBDBDBDE7E7E7ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZE6E6E6B3B3B3ABABABD6D6D6ECECECE6E6E6C1C1C1ADADADDBDBDBZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZD7D7D7A9A9A9B3B3B3D6D6D6C5C5C5ABABABCCCCCCEAEAEAZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZEBEBEBC5C5C5A1A1A1AEAEAEA5A5A5BBBBBBE4E4E4ZZZZZZZZZZZZZZZZZZZZZZZZ" }

fn pic_cell(ctx: *void, a: *mem.Arena, t: *const control.Theme, row: usize, spec: usize, out: *widget.Node) -> err {
    if t.tokens.profile != .Windows || t.tokens.palette == .Dark || spec != 2usize { ret ok }
    var pix = rarity_icon_u()
    let r = rarity_of(row)
    if r[0usize] == 67u8 { pix = rarity_icon_c() }
    if r[0usize] == 82u8 { pix = rarity_icon_r() }
    let (icon, icon_error) = gl.pixels(a, pix, 15.0, 17.0)
    if icon_error != ok { ret icon_error }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret held_error }
    held[0usize] = icon
    *out = widget.padded(0u64, 2.0, 0.0, 0.0, 4.0, style.defaults(), held[0usize..1usize])
    ret ok
}

// every card of the capture is colourless (grey) but Chaos Warp (red)
fn ink(ctx: *void, row: usize) -> (paint.Color, bool) {
    if row == 9usize {
        let (white, has_white) = gl.card_ink(87u8)
        ret (white, has_white)
    }
    if row == 10usize {
        let (multi, has_multi) = gl.card_ink(77u8)
        ret (multi, has_multi)
    }
    if row % 9usize == 8usize {
        let (red, has_red) = gl.card_ink(82u8)
        ret (red, has_red)
    }
    let (grey, has_grey) = gl.card_ink(78u8)
    ret (grey, has_grey)
}

fn specs_of(a: *mem.Arena, indent: f32) -> ([]dg.ColumnSpec, err) {
    // round 12: the grouped capture's thumb is 145 px against 160: its content is 119 px wider than the plain grid's (15 of them the indent)
    var extra_power: f32 = 0.0
    if indent > 0.0 { extra_power = 104.0 }
    let (specs, specs_error) = mem.alloc[dg.ColumnSpec](a, 10usize)
    if specs_error != ok { ret (zero, specs_error) }
    let sk = grp.SummaryKind.Rows
    specs[0usize] = dg.ColumnSpec { title: "", width: 12.0, column: C_NAME, kind: dg.CellKind.Indicator, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[1usize] = dg.ColumnSpec { title: "Favorite", width: 23.0 + indent, column: C_FAV, kind: dg.CellKind.Star, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[2usize] = dg.ColumnSpec { title: "", width: 21.0, column: C_NAME, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[3usize] = dg.ColumnSpec { title: "Name", width: 150.0, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[4usize] = dg.ColumnSpec { title: "Edition", width: 70.0, column: C_ED, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[5usize] = dg.ColumnSpec { title: "Color", width: 60.0, column: C_COLOR, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[6usize] = dg.ColumnSpec { title: "Type", width: 150.0, column: C_TYPE, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[7usize] = dg.ColumnSpec { title: "Rarity", width: 50.0, column: C_RARITY, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    specs[8usize] = dg.ColumnSpec { title: "", width: 24.0, column: C_NAME, kind: dg.CellKind.Picture, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    // the columns beyond the pane: the navigator's thumb says the content is wider
    specs[9usize] = dg.ColumnSpec { title: "Power", width: 586.0 + extra_power, column: C_NAME, kind: dg.CellKind.Text, decimals: 0u8, summary: -1, summary_kind: sk, filter: false, editable: false, choice: false }
    ret (specs, ok)
}

fn setup(app: *App) -> err {
    let a = app.a
    try load(a, app)
    let (scratch_bytes, scratch_error) = mem.alloc[u8](a, 16777216usize)
    if scratch_error != ok { ret scratch_error }
    app.scratch = mem.arena_from(scratch_bytes)
    var order: [1]view.Key = zero
    order[0usize] = view.column_key(C_NAME, false, true)
    var none: [1]grp.GroupLevel = zero
    var k = app.first
    while k < app.first + app.count {
        let (v, v_error) = view.create(a, &app.tbl)
        if v_error != ok { ret v_error }
        app.views[k] = v
        let (g, g_error) = grp.create(a, &app.views[k], 1024usize)
        if g_error != ok { ret g_error }
        app.groups[k] = g
        // the rows stay in load order: no key
        var levels: [1]grp.GroupLevel = zero
        levels[0usize] = grp.GroupLevel { column: C_ED, descending: false, fold: true }
        if grouped(k) {
            try grp.group_by(&app.groups[k], levels[0usize..1usize], order[0usize..1usize], &app.scratch)
            // round 12: the groups in the capture's order (the hidden rank), the last seven in view
            if app.windows {
                var rank_spec: [1]grp.SummarySpec = zero
                rank_spec[0usize] = grp.SummarySpec { column: C_RANK }
                try grp.apply_summaries(&app.groups[k], rank_spec[0usize..1usize], a)
                try grp.sort_groups_by_summary(&app.groups[k], 0usize, 0usize, grp.SummaryKind.Min, false, &app.scratch)
            }
        } else {
            try grp.group_by(&app.groups[k], none[0usize..0usize], order[0usize..0usize], &app.scratch)
        }
        // round 12: a grouped grid's first column takes the 15 px group indent
        var indent: f32 = 0.0
        if grouped(k) && app.windows { indent = 15.0 }
        let (specs, specs_error) = specs_of(a, indent)
        if specs_error != ok { ret specs_error }
        var events = dg.no_events()
        events.custom_cell = pic_cell
        let (made, made_error) = dg.create(a, &app.tbl, &app.groups[k], specs, events, u64(1000000 + k * 1000000))
        if made_error != ok { ret made_error }
        app.grids[k] = made
        var look = gl.v3()
        look.header_height = 22.0
        // the live capture's frame: white header, so a lighter inner top line
        look.ring_top_i = gl.rgb(0xD0D2D5u32)
        look.ring_left_o = gl.rgb(0x90949Cu32)
        look.ring_left_i = gl.rgb(0xEFF0F1u32)
        look.foot_set = true
        look.foot_drift = 1.0
        look.foot_g1 = gl.rgb(0xE3E3E3u32)
        look.foot_g2 = gl.rgb(0xF2F2F2u32)
        look.foot_w1 = gl.rgb(0xE9E9E9u32)
        look.foot_w2 = gl.rgb(0xE8E8E8u32)
        // looks11-g1: the live column lines as alpha blends (same fit as the states sheet, data_grid.e setup_states)
        if app.windows {
            look.soft_a0 = 0.75
            look.soft_x0 = 206.0
            look.soft_slope = 0.0 - 0.00055
            look.header_line = gl.rgb(0xF5F5F5u32)
            look.nav_rule = true
            // round 13: the grouped sheets' thumb is the 17 px minimum at the top of the track (live captures)
            if k >= 25usize && k < 31usize {
                look.thumb_len = 17.0
                look.thumb_top = 0.0
                look.bar_up = 34.0
                // the scrolled-to-the-end captures (View > Group by with the last group current) have the thumb at the foot of the track
                // round 17: cell 25 (the Hover 8 sheet's second grid) is also scrolled to the end
                if k >= 27usize || k == 25usize { look.thumb_top = 136.0 }
            }
        }
        // the View > Group by captures: group rows carry their counts, the group box is shown
        if k >= 25usize && k < 31usize { look.group_counts = true }
        // round 12: the pointer states (hover and pressed grabs) show the solid focus rectangle on the current group row; the first two cells are at rest
        if k == 27usize || k == 28usize || k == 30usize { look.group_solid = true }
        // round 31: the Windows light frame, bar ends and foot line are drawn (Look.ring_model), not stamped, in both palettes
        if app.windows {
            look.ring_model = 1u8
            look.ring_gy = 0.0
            look.ring_w = 576.0
            look.ring_h = 213.0
            if k >= 25usize && k < 31usize {
                look.ring_head_end = 35.0
                look.ring_top_i = gl.rgb(0xC6C8CCu32)
                // the thumb stands over the group box in the captures that are not scrolled to the end
                if k < 27usize && k != 25usize { look.ring_thumb = 1u8 }
            }
            look.ring_bar = 1u8
        }
        dg.set_look(&app.grids[k], look)
        if k >= 25usize && k < 31usize { dg.show_group_box(&app.grids[k], true) }
        dg.set_row_ink(&app.grids[k], zero, ink)
        dg.set_grid_lines(&app.grids[k], dg.GridLines.Both)
        dg.show_navigator(&app.grids[k], true)
        if app.windows { dg.show_footer(&app.grids[k], false) }
        dg.set_pane_hint(&app.grids[k], 573.0)
        app.grids[k].aligns[4usize] = 2u8
        app.grids[k].aligns[5usize] = 2u8
        app.grids[k].aligns[7usize] = 2u8
        app.grids[k].has_position = true
        app.grids[k].position = 3usize
        app.grids[k].has_selection = true
        app.grids[k].selected_row = 3usize
        // the hover grabs start from the grid at rest with its first row current (hover-main-rest: 1 of 120283)
        if k >= 10usize {
            app.grids[k].position = 0usize
            app.grids[k].selected_row = 0usize
        }
        if grouped(k) {
            // grouped: the current entry is the seventh group row, no card is selected
            app.grids[k].position = 6usize
            app.grids[k].has_selection = false
            if app.windows {
                app.grids[k].position = grp.visible_len(&app.groups[k]) - 1usize
                dg.set_tail_gap(&app.grids[k], 4.0)
                app.grids[k].offset = dg.entry_top(&app.grids[k], grp.visible_len(&app.groups[k]) - 7usize) + 2.0
            }
        }
        // focused: the cells 0 to 5 (the capture's grid had the focus: dotted row rectangle); the last one is not
        dg.set_forced_focus(&app.grids[k], k != 6usize)
        // round 12: the live header marks the picture column (outlined down triangle) and, grouped, the Edition column; Name is not marked
        if grouped(k) { dg.show_sort(&app.grids[k], 4usize, false) } else if app.windows { dg.show_sort(&app.grids[k], 10usize, false) } else { dg.show_sort(&app.grids[k], 3usize, false) }
        if app.windows {
            app.grids[k].extra_sort[0usize] = 2usize
            app.grids[k].extra_desc[0usize] = true
            app.grids[k].extra_count = 1usize
        }
        // the lower arrow held down scrolls the rows (the capture shows two rows gone)
        if k == 9usize { app.grids[k].offset = 38.0 }
        k += 1usize
    }
    ret ok
}

fn cell_of(a: *mem.Arena, t: *const control.Theme, grid: *dg.Grid) -> (widget.Node, err) {
    let (body, body_error) = dg.build(a, grid, t, grid_height(t))
    if body_error != ok { ret (zero, body_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 1usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = body
    var face = looks.size_style(576.0, 213.0)
    face.padding = style.EdgeLengths { left: style.Length { Px: 0.0 }, top: style.Length { Px: 0.0 }, right: style.Length { Px: 0.0 }, bottom: style.Length { Px: 0.0 } }
    face.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, face, held[0usize..1usize]), ok)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let app = mem.cast[*App](ctx)
    if app.ready && (app.windows != (t.tokens.profile == .Windows) || app.light != (t.tokens.palette != .Dark)) { app.ready = false }
    if !app.ready {
        app.windows = t.tokens.profile == .Windows
        app.light = t.tokens.palette != .Dark
        try setup(app)
        app.ready = true
    }
    let captions = [CELLS]str{ "Header pressed (Name)", "Navigator at rest", "First pressed", "Next pressed", "Last pressed", "Row selected, grid focused", "Row selected, grid not focused", "Vertical thumb pressed", "Horizontal thumb pressed", "Lower arrow pressed", "Hover: Name header", "Hover: Edition header", "Hover: Color header", "Hover: Type header", "Hover: Rarity header", "Hover: star header", "Hover: next button", "Hover: last button", "Hover: filter button", "Hover: vertical thumb", "Hover: upper arrow", "Hover: lower arrow", "Hover: horizontal thumb", "Rest, first row selected", "Hover: a row", "Grouped by Edition, at rest", "Group box shown, not grouped", "Hover: Edition header, grouped", "Hover: Name header, grouped", "Edition chip pressed", "Hover: a group row", "Hover: the bar's track" }
    var i = app.first
    while i < app.first + app.count {
        let (node, node_error) = cell_of(a, t, &app.grids[i])
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        // the pointer goes to the control that is pressed: the Name header, the first, next or last record button
        if i == 0usize {
            drive = .Press
            looks.aim(i - app.first, 100.0 - 288.0, 12.0 - 106.5)
        }
        if i == 2usize {
            drive = .Press
            looks.aim(i - app.first, 12.0 - 288.0, 199.0 - 106.5)
        }
        if i == 3usize {
            // round 17: the live "Next pressed" grab shows the button at rest (v3 had not drawn the press yet), so the cell is not driven
            drive = .None
        }
        if i == 4usize {
            drive = .Press
            looks.aim(i - app.first, 192.0 - 288.0, 199.0 - 106.5)
        }
        if i == 7usize {
            drive = .Press
            looks.aim(i - app.first, 783.0 - 216.0 - 288.0, 135.0 - 109.0 - 106.5)
        }
        if i == 8usize {
            drive = .Press
            looks.aim(i - app.first, 323.0 - 288.0, 201.0 - 106.5)
        }
        if i == 9usize {
            drive = .Press
            looks.aim(i - app.first, 783.0 - 216.0 - 288.0, 187.0 - 106.5)
        }
        if i >= 10usize && i < 23usize {
            // the pointer over: the header cells, the navigator buttons, the bar's thumb and arrows (cell coordinates)
            drive = .Hover
            var px: f32 = 100.0
            var py: f32 = 11.0
            if i == 11usize { px = 242.0 }
            if i == 12usize { px = 307.0 }
            if i == 13usize { px = 412.0 }
            if i == 14usize { px = 512.0 }
            if i == 15usize { px = 24.0 }
            if i == 16usize {
                px = 148.0
                py = 199.0
            }
            if i == 17usize {
                px = 170.0
                py = 199.0
            }
            if i == 18usize {
                px = 214.0
                py = 199.0
            }
            if i == 19usize {
                px = 567.0
                py = 26.0
            }
            if i == 20usize {
                px = 567.0
                py = 10.0
            }
            if i == 21usize {
                px = 567.0
                py = 180.0
            }
            if i == 22usize {
                px = 323.0
                py = 201.0
            }
            looks.aim(i - app.first, px - 288.0, py - 106.5)
        }
        if i == 24usize {
            drive = .Hover
            looks.aim(i - app.first, 300.0 - 288.0, 60.0 - 106.5)
        }
        if i == 31usize {
            drive = .Hover
            looks.aim(i - app.first, 567.0 - 288.0, 100.0 - 106.5)
        }
        if i >= 27usize && i < 31usize {
            // the grouped grids: the pointer over a header (the group box takes 34 px more at the top)
            drive = .Hover
            var gx: f32 = 242.0
            var gy: f32 = 46.0
            if i == 28usize { gx = 100.0 }
            if i == 29usize {
                drive = .Press
                gx = 35.0
                gy = 17.0
            }
            if i == 30usize {
                gx = 150.0
                gy = 80.0
            }
            looks.aim(i - app.first, gx - 288.0, gy - 106.5)
        }
        cells[i - app.first] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (app.count, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (apps, apps_error) = mem.alloc[App](a, 1usize)
    if apps_error != ok { ret apps_error }
    var seed: App = zero
    seed.a = a
    // the sheet is run in parts (the rig holds a limited number of nodes): `data_grid_top.exe 1` is cells 0 to 2 ...
    var name = "data_grid_top"
    seed.first = 0usize
    seed.count = 2usize
    if args.len > 1usize && args[1usize][0usize] != 115u8 && args[1usize][0usize] != 112u8 {
        // the part number: one or two digits
        var part = usize(args[1usize][0usize] - 48u8)
        if args[1usize].len > 1usize { part = part * 10usize + usize(args[1usize][1usize] - 48u8) }
        seed.first = part * 2usize
        seed.count = 2usize
        if seed.first + 2usize > CELLS { seed.count = CELLS - seed.first }
        let names = [16]str{ "data_grid_top", "data_grid_top2", "data_grid_top3", "data_grid_top4", "data_grid_top5", "data_grid_hover", "data_grid_hover2", "data_grid_hover3", "data_grid_hover4", "data_grid_hover5", "data_grid_hover6", "data_grid_hover7", "data_grid_hover8", "data_grid_group", "data_grid_group2", "data_grid_group3" }
        name = names[part]
    }
    apps[0usize] = seed
    if args.len > 1usize && args[1usize][0usize] == 115u8 {
        // `data_grid_top.exe states`: the selected-row grid, its top 179 px are the live grab docs/ui/looks/ref/windows/states/grid-row-selected-focused-main)
        seed.first = 1usize
        seed.count = 1usize
        apps[0usize] = seed
        let quick = looks.Sheet { name: "data_grid_states", cells: 1usize, columns: 1usize, cell_w: 576.0, cell_h: 213.0, ctx: mem.cast[*void](&apps[0usize]), build: build }
        ret looks.run_all(a, &quick)
    }
    if args.len > 1usize && args[1usize][0usize] == 112u8 {
        // `data_grid_top.exe pressed`: the header-pressed grid (the top 24 px are the live grab)
        seed.first = 0usize
        seed.count = 1usize
        apps[0usize] = seed
        let pressed = looks.Sheet { name: "data_grid_states_pressed", cells: 1usize, columns: 1usize, cell_w: 576.0, cell_h: 213.0, ctx: mem.cast[*void](&apps[0usize]), build: build }
        ret looks.run_all(a, &pressed)
    }
    let sheet = looks.Sheet { name: name, cells: seed.count, columns: 2usize, cell_w: 576.0, cell_h: 213.0, ctx: mem.cast[*void](&apps[0usize]), build: build }
    ret looks.run_all(a, &sheet)
}

// looks11-g1: the Windows grid's footer is off and its navigator rule overlapped by the buttons: the live body is one pixel taller
fn grid_height(t: *const control.Theme) -> f32 {
    if t.tokens.profile == .Windows { ret 240.0 }
    ret 239.0
}
