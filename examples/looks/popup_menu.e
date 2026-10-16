// The popup menu (TdxBarPopupMenu) in its states under every look: docs/ui/looks/<look>/popup_menu.png
// (static menus) and popup_menu-hover.png (a hovered row, which needs a pointer, and an open menu
// is modal, so each sheet of pointer-driven cells holds only that cell). Run from the repository
// root; see docs/ui/looks-howto.md. The commands are v3's Cards menu and grid context menu.

use e.mem
use e.str as strs
use e.ui.control
use e.ui.looks
use e.ui.navigation
use e.ui.style
use e.ui.widget

fn noop_submit(ctx: *void) -> err { ret ok }

fn actions_of(a: *mem.Arena) -> (*widget.Submit, err) {
    let (actions, actions_error) = mem.alloc[widget.Submit](a, 1usize)
    if actions_error != ok { ret (zero, actions_error) }
    actions[0usize] = widget.Submit { ctx: zero, invoke: noop_submit }
    ret (&actions[0usize], ok)
}

fn command(action: widget.Submit, label: str, shortcut: str, enabled: bool, separated: bool) -> navigation.BarCommand {
    var c: navigation.BarCommand = zero
    c.label = label
    c.shortcut = shortcut
    c.enabled = enabled
    c.separated = separated
    c.action = action
    ret c
}

fn picture(c: navigation.BarCommand, glyph: control.GlyphKind) -> navigation.BarCommand {
    var out = c
    out.pictured = true
    out.glyph = glyph
    ret out
}

// The grid's context menu: pictured commands, disabled ones, separators and shortcuts (C1).
fn plain(a: *mem.Arena, action: widget.Submit) -> ([]navigation.BarCommand, err) {
    let (list, list_error) = mem.alloc[navigation.BarCommand](a, 9usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = picture(command(action, "Add to Deck", "", false, false), .Add)
    list[1usize] = picture(command(action, "Add to Sideboard", "", false, false), .Add)
    list[2usize] = picture(command(action, "Add to Collection", "", true, true), .Add)
    list[3usize] = picture(command(action, "Add Foil to Collection", "", true, false), .Add)
    list[4usize] = picture(command(action, "Search...", "Ctrl+F", true, true), .Search)
    list[5usize] = picture(command(action, "Advanced Filter...", "Ctrl+Alt+F", true, false), .Filter)
    list[6usize] = picture(command(action, "Show Columns...", "Ctrl+Alt+C", true, true), .Settings)
    ret (list[0usize..7usize], ok)
}

// Checked and radio entries, a command with no picture, submenu arrows (EX1, AL1).
fn mixed(a: *mem.Arena, action: widget.Submit) -> ([]navigation.BarCommand, err) {
    let (list, list_error) = mem.alloc[navigation.BarCommand](a, 8usize)
    if list_error != ok { ret (zero, list_error) }
    list[0usize] = command(action, "Cut", "Ctrl+X", false, false)
    list[1usize] = command(action, "Paste", "Ctrl+V", true, false)
    list[2usize] = command(action, "Print", "", true, true)
    list[3usize] = command(action, "Export", "", true, false)
    list[3usize].submenu = list[2usize..3usize]
    list[2usize].submenu = list[2usize..3usize]
    list[4usize] = picture(command(action, "Footer", "", true, true), .Menu)
    list[4usize].checked = true
    list[5usize] = command(action, "Group Footers", "", false, false)
    list[6usize] = command(action, "Show Grid Lines", "", true, false)
    list[6usize].checkable = true
    list[6usize].checked = true
    list[7usize] = command(action, "Delete All", "Ctrl+Alt+Shift+Del", true, true)
    ret (list[0usize..8usize], ok)
}

// The menu hanging 2 below an anchor at (x, y) in a w x h cell.
fn hung(a: *mem.Arena, t: *const control.Theme, base: widget.Key, commands: []const navigation.BarCommand, x: f32, y: f32, w: f32, h: f32, action: *const widget.Submit) -> (widget.Node, err) {
    let (menu, menu_error) = navigation.bar_menu(a, base + 1u64, t, base, "Menu", commands, true, action)
    if menu_error != ok { ret (zero, menu_error) }
    let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
    if parts_error != ok { ret (zero, parts_error) }
    parts[0usize] = widget.box(base, control.sized_style(1.0, 1.0), zero)
    parts[1usize] = menu
    let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
    if row_error != ok { ret (zero, row_error) }
    row[0usize] = widget.stack(0u64, control.sized_style(1.0, 1.0), parts[0usize..2usize])
    ret (widget.padded(0u64, x, y, 0.0, 0.0, control.sized_style(w, h), row[0usize..1usize]), ok)
}

// Static sheet: the context menu, then the mixed one, then a cascade (the Export row open).
fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (first, first_error) = plain(a, *action)
    if first_error != ok { ret (0usize, first_error) }
    let (second, second_error) = mixed(a, *action)
    if second_error != ok { ret (0usize, second_error) }
    let (node_a, node_a_error) = hung(a, t, 100u64, first, 4.0, 0.0, 300.0, 250.0, action)
    if node_a_error != ok { ret (0usize, node_a_error) }
    let (node_b, node_b_error) = hung(a, t, 20000u64, second, 4.0, 0.0, 300.0, 250.0, action)
    if node_b_error != ok { ret (0usize, node_b_error) }
    cells[0usize] = looks.Cell { caption: "Commands, disabled, separators, shortcuts", node: node_a, drive: .None }
    cells[1usize] = looks.Cell { caption: "Checked, arrows, narrow", node: node_b, drive: .None }
    ret (2usize, ok)
}

// A hovered row (Add Foil to Collection, the fourth) under the pointer at the cell's centre.
fn build_hover(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let (action, action_error) = actions_of(a)
    if action_error != ok { ret (0usize, action_error) }
    let (first, first_error) = plain(a, *action)
    if first_error != ok { ret (0usize, first_error) }
    let (node, node_error) = hung(a, t, 100u64, first, 150.0 - 100.0, 125.0 - 85.0, 300.0, 250.0, action)
    if node_error != ok { ret (0usize, node_error) }
    cells[0usize] = looks.Cell { caption: "Hover", node: node, drive: .Hover }
    ret (1usize, ok)
}

// ---- The main-menu popups as captured from v3 (docs/ui/looks/ref/windows/dialogs/menu-*): each menu is
// one string, items split by `|`, an item `flags;label;shortcut`. Flags: d disabled, s separator
// before, h group header, c checked, a submenu, p picture, u drop-down button. A `&` marks the
// mnemonic. One sheet per menu named popup_menu_<name>, the capture beside it as ref/windows/<name>.png.
type Spec = struct { name: str, items: str, limit: f32, w: f32, h: f32 }

fn has_flag(flags: str, flag: u8) -> bool {
    var i = 0usize
    while i < flags.len {
        if flags[i] == flag { ret true }
        i += 1usize
    }
    ret false
}

// Items of the spec text as commands (at most `room`); a submenu item gets a one-command submenu.
fn parse_items(a: *mem.Arena, action: widget.Submit, text: str, room: usize, sub: str) -> ([]navigation.BarCommand, err) {
    let (list, list_error) = mem.alloc[navigation.BarCommand](a, room + 1usize)
    if list_error != ok { ret (zero, list_error) }
    var rest = text
    var n = 0usize
    while rest.len > 0usize && n < room {
        let (item, tail, more) = strs.split_once(rest, "|")
        rest = tail
        if !more { rest = "" }
        let (flags, after_flags, _) = strs.split_once(item, ";")
        let (label, shortcut, _) = strs.split_once(after_flags, ";")
        var c = command(action, label, shortcut, !has_flag(flags, 100u8), has_flag(flags, 115u8))
        c.header = has_flag(flags, 104u8)
        c.checked = has_flag(flags, 99u8)
        c.split = has_flag(flags, 117u8)
        if has_flag(flags, 112u8) {
            c.pictured = true
            c.glyph = .Picture
        }
        // x: the highlighted row (a keyboard's selection in the captures).
        c.selected = has_flag(flags, 120u8)
        // k: the checked slot's dither takes the other phase (it follows the window's screen position).
        c.dither_flip = has_flag(flags, 107u8)
        if has_flag(flags, 97u8) { c.submenu = list[room..room + 1usize] }
        if has_flag(flags, 97u8) && sub.len > 0usize && c.selected {
            let (inner, inner_error) = parse_items(a, action, sub, 12usize, "")
            if inner_error != ok { ret (zero, inner_error) }
            c.submenu = inner
        }
        list[n] = c
        n += 1usize
    }
    list[room] = command(action, "Sub", "", true, false)
    ret (list[0usize..n], ok)
}

// The sheet's menus: one for a menu sheet, two for the composite `popup_menu_dialog`.
type Group = struct { specs: []Spec, sub: str }

fn build_menu(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let group = mem.cast[*Group](ctx)
    var room = 64usize
    if t.tokens.profile != .Windows { room = 14usize }
    var i = 0usize
    while i < group.specs.len {
        let spec = &group.specs[i]
        let (action, action_error) = actions_of(a)
        if action_error != ok { ret (0usize, action_error) }
        let (commands, commands_error) = parse_items(a, *action, spec.items, room, group.sub)
        if commands_error != ok { ret (0usize, commands_error) }
        let anchor = 20u64 + 100u64 * u64(i)
        let (menu, menu_error) = navigation.bar_menu_limited(a, anchor + 1u64, t, anchor, "Menu", commands, true, action, spec.limit)
        if menu_error != ok { ret (0usize, menu_error) }
        let (parts, parts_error) = mem.alloc[widget.Node](a, 2usize)
        if parts_error != ok { ret (0usize, parts_error) }
        parts[0usize] = widget.box(anchor, control.sized_style(1.0, 1.0), zero)
        parts[1usize] = menu
        let (row, row_error) = mem.alloc[widget.Node](a, 1usize)
        if row_error != ok { ret (0usize, row_error) }
        row[0usize] = widget.stack(0u64, control.sized_style(1.0, 1.0), parts[0usize..2usize])
        var box_w = spec.w + 20.0
        var box_h = spec.h + 20.0
        // The composite sheet: the cells sit 227 apart and 618 tall, as the captures are pasted in the reference.
        if group.specs.len > 1usize {
            box_w = 217.0
            box_h = 618.0
        }
        cells[i] = looks.Cell { caption: spec.name, node: widget.padded(0u64, 4.0, 0.0, 0.0, 0.0, control.sized_style(box_w, box_h), row[0usize..1usize]), drive: .None }
        i += 1usize
    }
    ret (group.specs.len, ok)
}

fn menu_specs(a: *mem.Arena) -> ([]Spec, err) {
    let (specs, specs_error) = mem.alloc[Spec](a, 10usize)
    if specs_error != ok { ret (zero, specs_error) }
    specs[0usize] = Spec { name: "popup_menu_file", limit: 0.0, w: 251.0, h: 580.0, items: "dp;&New...;Ctrl+N|dp;&Open...;Ctrl+O|dpa;&Reopen;|dps;&Save;Ctrl+S|dp;Save &As...;|dp;Sav&e All;Ctrl+Shift+S|dp;&Close;|dp;C&lose All;Ctrl+Shift+F4|dp;&Delete Deck;|dps;&Properties...;Ctrl+I|dp;Deck &Legality...;F6|dp;&Statistics...;F7|p;Print Proxies...;|h;Mode;|;Deck from Card Pool;Ctrl+F2|c;Collection from Card Pool;Ctrl+F3|;Deck from Collection;Ctrl+F4|p;To&ggle Mode;F12|;To&ggle Mode in Reverse;Shift+F12|ps;&Import...;|p;Update Prices...;|ps;Full Screen;Shift+F11|p;&Minimize;Ctrl+Alt+M|p;Minimize and &Lock;Ctrl+Alt+L|p;Stay on Top;|s; ;" }
    specs[1usize] = Spec { name: "popup_menu_cards", limit: 0.0, w: 217.0, h: 496.0, items: "dp;&Add to Deck;|dp;Add &4 to Deck;Ctrl+Ins|dp;Add to Sideboard;|dp;&Remove from Deck;Del|dps;&Add to Collection;|dp;Add &Foil to Collection;|dp;Remove from Collection;Del|dps;&Increase Quantity;Num +|dp;&Toggle Quantity;Ctrl+Alt+T|dp;&Decrease Quantity;Num -|d;Batch Update Selected...;|dp;Delete All;Ctrl+Alt+Shift+Del|dps;Cu&t;Ctrl+X|dp;&Copy;Ctrl+C|dp;&Paste;Ctrl+V|dp;S&elect All;Ctrl+A|sa;&Print;|a;&Export;|a;Copy as Text;|p;&Lock Collection;|dps;Next Deck;Ctrl+Right|dp;Previous Deck;Ctrl+Left" }
    specs[2usize] = Spec { name: "popup_menu_search", limit: 0.0, w: 227.0, h: 488.0, items: "p;&Filter Top...;F3|p;&Filter Bottom...;Shift+F3|p;&Advanced Filter...;Ctrl+Alt+F|p;Reset All Filters;|h;General Filter;|p;&Show Latest Reprints Only;|dpck;All Cards;|p;MTG Online Only;|;Wa&gic the Homebrew Only;|h;Search;|p;&Search...;Ctrl+F|dp;&Next;Ctrl+Down|dp;&Previous;Ctrl+Up|dp;&Cancel;Ctrl+Shift+F|h;Go to;|p;&First;|p;Pre&vious Page;|p;&Previous Card;|p;&Next Card;|p;Ne&xt Page;|p;&Last;|ps;To&ggle Bookmark;Ctrl+Shift+1|dp;Go to Bookmark;Ctrl+1" }
    specs[3usize] = Spec { name: "popup_menu_view", limit: 618.0, w: 214.0, h: 618.0, items: "h;Sort Order;|p;Sort by Edition & Card Name;|p;Sort by Card Name & Edition;|p;Sort...;|p;Clear Sort Order;|h;Group By;|;Group by Edition;|;Group by Type;|;Group by Color;|;Group by Rarity;|;Remove Grouping;|h;Cards;|pc;&Legality;Ctrl+L|p;&Card Rules;Ctrl+T|p;Show Columns...;Ctrl+Alt+C|p;Best &Fit (all columns);|p;Columns Auto &Width;|pc;Show &Group Box;|p;Full &Expand;|p;Full &Collapse;|pc;Show &Header;|pc;Show &Indicator;|pu;Show Grid &Lines;|;Conditional Formattin&g...;|pc;Show Summary Footer;|pc;Show &Navigator;|sa;&Toolbars;|c;&Status Bar;|p;Legend;|p;Navigator;" }
    specs[4usize] = Spec { name: "popup_menu_cardart", limit: 0.0, w: 189.0, h: 332.0, items: "h;Card Art;|p;Preview...;|;Open Containing Folder;|p;&Export...;|;Copy to Clipboard;|h;Size;|;480 x 680 Pixels;|;312 x 445 Pixels;|c;200 x 285 Pixels;|;&Resize to Fit;Ctrl+Alt+A|spc;Ali&gn Left;|p;Ali&gn Right;|p;&Top;|pc;&Bottom;|s;Download All Art...;" }
    specs[5usize] = Spec { name: "popup_menu_online", limit: 0.0, w: 162.0, h: 86.0, items: "dp;&Gatherer...;Ctrl+G|dp;&Boardgames Rules...;|dp;eBay Sales...;|dp;Google Images...;" }
    specs[6usize] = Spec { name: "popup_menu_reports", limit: 0.0, w: 228.0, h: 206.0, items: "dp;Deck &Registration Sheet 2021...;|dp;Deck Registration Sheet 1999...;|dp;Deck &Availability...;|dp;Deck Combos...;|ps;&Missing Set Cards...;|p;&Combos from Collection...;|p;&Edition Availability...;|p;Card &Quantities...;|ps;Scorepad...;" }
    specs[7usize] = Spec { name: "popup_menu_tools", limit: 0.0, w: 255.0, h: 166.0, items: ";&Locate My Collection...;|;Check Collection Inte&grity;|;&Backup Collection...;|s;Open Installation Folder...;|;Open Configuration Folder...;|;Open My Decks Folder...;Ctrl+Alt+F|ps;Options;F10" }
    specs[8usize] = Spec { name: "popup_menu_admin", limit: 0.0, w: 100.0, h: 26.0, items: "p;&Debug...;" }
    specs[9usize] = Spec { name: "popup_menu_help", limit: 0.0, w: 191.0, h: 216.0, items: "p;MTG Studio &Help...;F1|p;&Discord Channel...;|p;&Game Rules...;|p;&Version History...;|p;Check for Update...;|ps;MTG Studio H&omepage...;|p;&Bug Report...;|p;&Request a Feature...;|;Report Missing Card...;|p;&About MTG Studio;" }
    ret (specs, ok)
}

// The captured interaction states (docs/ui/looks/ref/windows/states/menu-*, copied as ref/windows/popup_menu_sel_*,
// popup_menu_sub_*): one sheet per line of `state_data`, fields name@w@h@limit@items@sub. A flag x is the
// highlighted row; in a parent the highlighted `a` row carries the items of `sub`.
fn run_states(a: *mem.Arena, only: str) -> err {
    var rest = state_data()
    while rest.len > 0usize {
        let (line, tail, more) = strs.split_once(rest, "#")
        rest = tail
        if !more { rest = "" }
        let (name, r1, _) = strs.split_once(line, "@")
        let (ws, r2, _) = strs.split_once(r1, "@")
        let (hs, r3, _) = strs.split_once(r2, "@")
        let (limit_text, r4, _) = strs.split_once(r3, "@")
        let (items, sub, _) = strs.split_once(r4, "@")
        if only.len > 0usize && !strs.eq(only, name) { continue }
        let (w, _) = strs.parse_u64(ws)
        let (h, _) = strs.parse_u64(hs)
        let (limit, _) = strs.parse_u64(limit_text)
        let (specs, specs_error) = mem.alloc[Spec](a, 1usize)
        if specs_error != ok { ret specs_error }
        specs[0usize] = Spec { name: name, items: items, limit: f32(limit), w: f32(w), h: f32(h) }
        let (group, group_error) = mem.alloc[Group](a, 1usize)
        if group_error != ok { ret group_error }
        group[0usize].specs = specs
        group[0usize].sub = sub
        let sheet = looks.Sheet { name: name, cells: 1usize, columns: 1usize, cell_w: f32(w) + 20.0, cell_h: f32(h) + 20.0, ctx: mem.cast[*void](&group[0usize]), build: build_menu }
        try looks.run_all(a, &sheet)
    }
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    // An argument names one sheet to render.
    var only = ""
    if args.len > 1usize { only = args[1usize] }
    if only.len == 0usize || strs.eq(only, "popup_menu") {
        let states = looks.Sheet { name: "popup_menu", cells: 2usize, columns: 2usize, cell_w: 300.0, cell_h: 250.0, ctx: zero, build: build }
        try looks.run_all(a, &states)
    }
    if only.len == 0usize || strs.eq(only, "popup_menu-hover") {
        let hover = looks.Sheet { name: "popup_menu-hover", cells: 1usize, columns: 1usize, cell_w: 300.0, cell_h: 250.0, ctx: zero, build: build_hover }
        try looks.run_all(a, &hover)
    }
    if only.len > 0usize && (strs.starts_with(only, "popup_menu_sel_") || strs.starts_with(only, "popup_menu_sub_")) || strs.eq(only, "popup_menu_reports_deck_mode") {
        try run_states(a, only)
        ret ok
    }
    let (specs, specs_error) = menu_specs(a)
    if specs_error != ok { ret specs_error }
    // The control's own sheet: the Cards and the View menu side by side (ref/windows/popup_menu_dialog.png
    // is those two captures pasted together).
    if only.len == 0usize || strs.eq(only, "popup_menu_dialog") {
        let (pair, pair_error) = mem.alloc[Spec](a, 2usize)
        if pair_error != ok { ret pair_error }
        pair[0usize] = specs[1usize]
        pair[1usize] = specs[3usize]
        let (group, group_error) = mem.alloc[Group](a, 1usize)
        if group_error != ok { ret group_error }
        group[0usize].specs = pair
        let both = looks.Sheet { name: "popup_menu_dialog", cells: 2usize, columns: 2usize, cell_w: 217.0, cell_h: 618.0, ctx: mem.cast[*void](&group[0usize]), build: build_menu }
        try looks.run_all(a, &both)
    }
    var i = 0usize
    while i < specs.len {
        if only.len == 0usize || strs.eq(only, specs[i].name) {
            let (group, group_error) = mem.alloc[Group](a, 1usize)
            if group_error != ok { ret group_error }
            group[0usize].specs = specs[i..i + 1usize]
            let menu = looks.Sheet { name: specs[i].name, cells: 1usize, columns: 1usize, cell_w: specs[i].w + 20.0, cell_h: specs[i].h + 20.0, ctx: mem.cast[*void](&group[0usize]), build: build_menu }
            try looks.run_all(a, &menu)
        }
        i += 1usize
    }
    ret ok
}
// ---- generated states (see run_states): lines split by #, fields by @
fn state_data() -> str { ret "popup_menu_sel_cardart_1@189@332@0@h;Card Art;|xp;Preview...;|;Open Containing Folder;|p;&Export...;|;Copy to Clipboard;|h;Size;|;480 x 680 Pixels;|;312 x 445 Pixels;|c;200 x 285 Pixels;|;&Resize to Fit;Ctrl+Alt+A|spc;Ali&gn Left;|p;Ali&gn Right;|p;&Top;|pc;&Bottom;|s;Download All Art...;@#popup_menu_sel_cardart_3@189@332@0@h;Card Art;|p;Preview...;|;Open Containing Folder;|xp;&Export...;|;Copy to Clipboard;|h;Size;|;480 x 680 Pixels;|;312 x 445 Pixels;|c;200 x 285 Pixels;|;&Resize to Fit;Ctrl+Alt+A|spc;Ali&gn Left;|p;Ali&gn Right;|p;&Top;|pc;&Bottom;|s;Download All Art...;@#popup_menu_sel_cards_1@217@496@0@xdp;&Add to Deck;|dp;Add &4 to Deck;Ctrl+Ins|dp;Add to Sideboard;|dp;&Remove from Deck;Del|ps;&Add to Collection;|p;Add &Foil to Collection;|dp;Remove from Collection;Del|dps;&Increase Quantity;Num +|dp;&Toggle Quantity;Ctrl+Alt+T|dp;&Decrease Quantity;Num -|d;Batch Update Selected...;|dp;Delete All;Ctrl+Alt+Shift+Del|dps;Cu&t;Ctrl+X|dp;&Copy;Ctrl+C|dp;&Paste;Ctrl+V|p;S&elect All;Ctrl+A|sa;&Print;|a;&Export;|a;Copy as Text;|p;&Lock Collection;|dps;Next Deck;Ctrl+Right|dp;Previous Deck;Ctrl+Left@#popup_menu_sel_cards_4@217@496@0@dp;&Add to Deck;|dp;Add &4 to Deck;Ctrl+Ins|dp;Add to Sideboard;|xdp;&Remove from Deck;Del|ps;&Add to Collection;|p;Add &Foil to Collection;|dp;Remove from Collection;Del|dps;&Increase Quantity;Num +|dp;&Toggle Quantity;Ctrl+Alt+T|dp;&Decrease Quantity;Num -|d;Batch Update Selected...;|dp;Delete All;Ctrl+Alt+Shift+Del|dps;Cu&t;Ctrl+X|dp;&Copy;Ctrl+C|dp;&Paste;Ctrl+V|p;S&elect All;Ctrl+A|sa;&Print;|a;&Export;|a;Copy as Text;|p;&Lock Collection;|dps;Next Deck;Ctrl+Right|dp;Previous Deck;Ctrl+Left@#popup_menu_sel_file_1@251@580@0@xdp;&New...;Ctrl+N|dp;&Open...;Ctrl+O|dpa;&Reopen;|dps;&Save;Ctrl+S|dp;Save &As...;|dp;Sav&e All;Ctrl+Shift+S|dp;&Close;|dp;C&lose All;Ctrl+Shift+F4|dp;&Delete Deck;|dps;&Properties...;Ctrl+I|dp;Deck &Legality...;F6|dp;&Statistics...;F7|dp;Print Proxies...;|h;Mode;|;Deck from Card Pool;Ctrl+F2|c;Collection from Card Pool;Ctrl+F3|;Deck from Collection;Ctrl+F4|p;To&ggle Mode;F12|;To&ggle Mode in Reverse;Shift+F12|ps;&Import...;|p;Update Prices...;|ps;Full Screen;Shift+F11|p;&Minimize;Ctrl+Alt+M|p;Minimize and &Lock;Ctrl+Alt+L|p;Stay on Top;|s; ;@#popup_menu_sel_file_24@251@580@0@dp;&New...;Ctrl+N|dp;&Open...;Ctrl+O|dpa;&Reopen;|dps;&Save;Ctrl+S|dp;Save &As...;|dp;Sav&e All;Ctrl+Shift+S|dp;&Close;|dp;C&lose All;Ctrl+Shift+F4|dp;&Delete Deck;|dps;&Properties...;Ctrl+I|dp;Deck &Legality...;F6|dp;&Statistics...;F7|dp;Print Proxies...;|h;Mode;|;Deck from Card Pool;Ctrl+F2|c;Collection from Card Pool;Ctrl+F3|;Deck from Collection;Ctrl+F4|p;To&ggle Mode;F12|;To&ggle Mode in Reverse;Shift+F12|ps;&Import...;|p;Update Prices...;|ps;Full Screen;Shift+F11|p;&Minimize;Ctrl+Alt+M|p;Minimize and &Lock;Ctrl+Alt+L|xp;Stay on Top;|s; ;@#popup_menu_sel_help_1@191@216@0@xp;MTG Studio &Help...;F1|p;&Discord Channel...;|p;&Game Rules...;|p;&Version History...;|p;Check for Update...;|ps;MTG Studio H&omepage...;|p;&Bug Report...;|p;&Request a Feature...;|;Report Missing Card...;|p;&About MTG Studio;@#popup_menu_sel_help_4@191@216@0@p;MTG Studio &Help...;F1|p;&Discord Channel...;|p;&Game Rules...;|xp;&Version History...;|p;Check for Update...;|ps;MTG Studio H&omepage...;|p;&Bug Report...;|p;&Request a Feature...;|;Report Missing Card...;|p;&About MTG Studio;@#popup_menu_sel_online_1@162@86@0@xp;&Gatherer...;Ctrl+G|p;&Boardgames Rules...;|p;eBay Sales...;|p;Google Images...;@#popup_menu_sel_reports_1@228@206@0@xdp;Deck &Registration Sheet 2021...;|dp;Deck Registration Sheet 1999...;|dp;Deck &Availability...;|dp;Deck Combos...;|ps;&Missing Set Cards...;|p;&Combos from Collection...;|p;&Edition Availability...;|p;Card &Quantities...;|ps;Scorepad...;@#popup_menu_sel_reports_4@228@206@0@dp;Deck &Registration Sheet 2021...;|dp;Deck Registration Sheet 1999...;|dp;Deck &Availability...;|xdp;Deck Combos...;|ps;&Missing Set Cards...;|p;&Combos from Collection...;|p;&Edition Availability...;|p;Card &Quantities...;|ps;Scorepad...;@#popup_menu_sel_search_1@227@488@0@xp;&Filter Top...;F3|p;&Filter Bottom...;Shift+F3|p;&Advanced Filter...;Ctrl+Alt+F|p;Reset All Filters;|h;General Filter;|p;&Show Latest Reprints Only;|dpck;All Cards;|p;MTG Online Only;|;Wa&gic the Homebrew Only;|h;Search;|p;&Search...;Ctrl+F|dp;&Next;Ctrl+Down|dp;&Previous;Ctrl+Up|dp;&Cancel;Ctrl+Shift+F|h;Go to;|p;&First;|p;Pre&vious Page;|p;&Previous Card;|p;&Next Card;|p;Ne&xt Page;|p;&Last;|ps;To&ggle Bookmark;Ctrl+Shift+1|dp;Go to Bookmark;Ctrl+1@#popup_menu_sel_search_5@227@488@0@p;&Filter Top...;F3|p;&Filter Bottom...;Shift+F3|p;&Advanced Filter...;Ctrl+Alt+F|p;Reset All Filters;|h;General Filter;|xp;&Show Latest Reprints Only;|dpck;All Cards;|p;MTG Online Only;|;Wa&gic the Homebrew Only;|h;Search;|p;&Search...;Ctrl+F|dp;&Next;Ctrl+Down|dp;&Previous;Ctrl+Up|dp;&Cancel;Ctrl+Shift+F|h;Go to;|p;&First;|p;Pre&vious Page;|p;&Previous Card;|p;&Next Card;|p;Ne&xt Page;|p;&Last;|ps;To&ggle Bookmark;Ctrl+Shift+1|dp;Go to Bookmark;Ctrl+1@#popup_menu_sel_tools_1@255@166@0@x;&Locate My Collection...;|;Check Collection Inte&grity;|;&Backup Collection...;|s;Open Installation Folder...;|;Open Configuration Folder...;|;Open My Decks Folder...;Ctrl+Alt+F|ps;Options;F10@#popup_menu_sel_tools_3@255@166@0@;&Locate My Collection...;|;Check Collection Inte&grity;|x;&Backup Collection...;|s;Open Installation Folder...;|;Open Configuration Folder...;|;Open My Decks Folder...;Ctrl+Alt+F|ps;Options;F10@#popup_menu_sel_view_1@214@626@0@h;Sort Order;|xp;Sort by Edition & Card Name;|p;Sort by Card Name & Edition;|p;Sort...;|p;Clear Sort Order;|h;Group By;|;Group by Edition;|;Group by Type;|;Group by Color;|;Group by Rarity;|;Remove Grouping;|h;Cards;|p;&Legality;Ctrl+L|p;&Card Rules;Ctrl+T|p;Show Columns...;Ctrl+Alt+C|p;Best &Fit (all columns);|p;Columns Auto &Width;|p;Show &Group Box;|p;Full &Expand;|p;Full &Collapse;|pc;Show &Header;|pc;Show &Indicator;|pu;Show Grid &Lines;|;Conditional Formattin&g...;|p;Show Summary Footer;|pc;Show &Navigator;|sa;&Toolbars;|c;&Status Bar;|p;Legend;|p;Messages;Ctrl+M@#popup_menu_sel_view_5@214@626@0@h;Sort Order;|p;Sort by Edition & Card Name;|p;Sort by Card Name & Edition;|p;Sort...;|p;Clear Sort Order;|h;Group By;|x;Group by Edition;|;Group by Type;|;Group by Color;|;Group by Rarity;|;Remove Grouping;|h;Cards;|p;&Legality;Ctrl+L|p;&Card Rules;Ctrl+T|p;Show Columns...;Ctrl+Alt+C|p;Best &Fit (all columns);|p;Columns Auto &Width;|p;Show &Group Box;|p;Full &Expand;|p;Full &Collapse;|pc;Show &Header;|pc;Show &Indicator;|pu;Show Grid &Lines;|;Conditional Formattin&g...;|p;Show Summary Footer;|pc;Show &Navigator;|sa;&Toolbars;|c;&Status Bar;|p;Legend;|p;Messages;Ctrl+M@#popup_menu_reports_deck_mode@228@206@0@p;Deck &Registration Sheet 2021...;|p;Deck Registration Sheet 1999...;|p;Deck &Availability...;|p;Deck Combos...;|ps;&Missing Set Cards...;|p;&Combos from Collection...;|p;&Edition Availability...;|p;Card &Quantities...;|ps;Scorepad...;@#popup_menu_sub_cards_export_child@130@126@0@xp;&HTML;Ctrl+E|p;&PDF;|p;&Excel;|p;CSV;|p;&Plain Text;|p;&Xml;@#popup_menu_sub_cards_export_parent@217@496@0@dp;&Add to Deck;|dp;Add &4 to Deck;Ctrl+Ins|dp;Add to Sideboard;|dp;&Remove from Deck;Del|ps;&Add to Collection;|p;Add &Foil to Collection;|dp;Remove from Collection;Del|dps;&Increase Quantity;Num +|dp;&Toggle Quantity;Ctrl+Alt+T|dp;&Decrease Quantity;Num -|d;Batch Update Selected...;|dp;Delete All;Ctrl+Alt+Shift+Del|dps;Cu&t;Ctrl+X|dp;&Copy;Ctrl+C|dp;&Paste;Ctrl+V|p;S&elect All;Ctrl+A|sa;&Print;|xa;&Export;|a;Copy as Text;|p;&Lock Collection;|dps;Next Deck;Ctrl+Right|dp;Previous Deck;Ctrl+Left@p;&HTML;Ctrl+E|p;&PDF;|p;&Excel;|p;CSV;|p;&Plain Text;|p;&Xml;#popup_menu_sub_cards_print_child@216@86@0@xp;&Print;Ctrl+P|p;Page &Setup...;|p;P&rint Preview...;Ctrl+Shift+P|p;&Designer...;Alt+P@#popup_menu_sub_cards_print_parent@217@496@0@dp;&Add to Deck;|dp;Add &4 to Deck;Ctrl+Ins|dp;Add to Sideboard;|dp;&Remove from Deck;Del|ps;&Add to Collection;|p;Add &Foil to Collection;|dp;Remove from Collection;Del|dps;&Increase Quantity;Num +|dp;&Toggle Quantity;Ctrl+Alt+T|dp;&Decrease Quantity;Num -|d;Batch Update Selected...;|dp;Delete All;Ctrl+Alt+Shift+Del|dps;Cu&t;Ctrl+X|dp;&Copy;Ctrl+C|dp;&Paste;Ctrl+V|p;S&elect All;Ctrl+A|xsa;&Print;|a;&Export;|a;Copy as Text;|p;&Lock Collection;|dps;Next Deck;Ctrl+Right|dp;Previous Deck;Ctrl+Left@p;&Print;Ctrl+P|p;Page &Setup...;|p;P&rint Preview...;Ctrl+Shift+P|p;&Designer...;Alt+P#popup_menu_sub_view_show_grid_lines_child@105@86@0@kxpc;&Both;|p;&Horizontal;|p;&Vertical;|p;&None;@#popup_menu_sub_view_show_grid_lines_parent@214@626@0@h;Sort Order;|p;Sort by Edition & Card Name;|p;Sort by Card Name & Edition;|p;Sort...;|p;Clear Sort Order;|h;Group By;|;Group by Edition;|;Group by Type;|;Group by Color;|;Group by Rarity;|;Remove Grouping;|h;Cards;|p;&Legality;Ctrl+L|p;&Card Rules;Ctrl+T|p;Show Columns...;Ctrl+Alt+C|p;Best &Fit (all columns);|p;Columns Auto &Width;|p;Show &Group Box;|p;Full &Expand;|p;Full &Collapse;|pc;Show &Header;|pc;Show &Indicator;|xpu;Show Grid &Lines;|;Conditional Formattin&g...;|p;Show Summary Footer;|pc;Show &Navigator;|sa;&Toolbars;|c;&Status Bar;|p;Legend;|p;Messages;Ctrl+M@pc;&Both;|p;&Horizontal;|p;&Vertical;|p;&None;#popup_menu_sub_view_toolbars_child@119@216@0@kxc;&Standard;|c;&Cards;|c;&Search;|;&Edit;|;E&xtended;|;&View;|;&Actions;|;&Navigator;|;&Deck;|s;&Customize...;@#popup_menu_sub_view_toolbars_parent@214@626@0@h;Sort Order;|p;Sort by Edition & Card Name;|p;Sort by Card Name & Edition;|p;Sort...;|p;Clear Sort Order;|h;Group By;|;Group by Edition;|;Group by Type;|;Group by Color;|;Group by Rarity;|;Remove Grouping;|h;Cards;|p;&Legality;Ctrl+L|p;&Card Rules;Ctrl+T|p;Show Columns...;Ctrl+Alt+C|p;Best &Fit (all columns);|p;Columns Auto &Width;|p;Show &Group Box;|p;Full &Expand;|p;Full &Collapse;|pc;Show &Header;|pc;Show &Indicator;|pu;Show Grid &Lines;|;Conditional Formattin&g...;|p;Show Summary Footer;|pc;Show &Navigator;|xsa;&Toolbars;|c;&Status Bar;|p;Legend;|p;Messages;Ctrl+M@c;&Standard;|c;&Cards;|c;&Search;|;&Edit;|;E&xtended;|;&View;|;&Actions;|;&Navigator;|;&Deck;|s;&Customize...;" }
