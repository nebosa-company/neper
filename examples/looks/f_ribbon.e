// navigation.ribbon under all ten looks: docs/ui/looks/<look>/ribbon.png. An Office style ribbon with a quick-access bar,
// tabs (Home, Insert, View) and the groups of the current tab: Home current, Insert current, with the contextual Table
// Tools tabs shown, collapsed, and a command hovered or pressed.
// Derived from the shared tokens; no platform reference is captured. Run from the repository root.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.looks_f
use e.ui.looks_y85
use e.ui.navigation
use e.ui.overlay
use e.ui.widget

fn no_press(ctx: *void) -> err { ret ok }

fn command(label: str, glyph: control.GlyphKind, large: bool, press: widget.Submit) -> navigation.RibbonCommand {
    var c: navigation.RibbonCommand = zero
    c.label = label
    c.glyph = glyph
    c.action = press
    c.enabled = true
    c.large = large
    ret c
}

fn build(ctx: *void, a: *mem.Arena, base: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    // Cupertino only: quick-bar and tab text take the increased-contrast blue; other looks get their own tokens back.
    let (tokens, tokens_error) = looks_y85.tinted_ring(a, base.tokens, 0x0040DDu32, 0x409CFFu32)
    if tokens_error != ok { ret (0usize, tokens_error) }
    var themed = *base
    themed.tokens = tokens
    let t = &themed
    let captions = [6]str{ "Home", "Insert", "Contextual tabs", "Collapsed", "Command hovered", "Command pressed" }
    let press = widget.Submit { ctx: zero, invoke: no_press }
    let (picks, picks_error) = mem.alloc[widget.Submit](a, 5usize)
    if picks_error != ok { ret (0usize, picks_error) }
    var k = 0usize
    while k < 5usize {
        picks[k] = press
        k += 1usize
    }
    let (quick, quick_error) = mem.alloc[navigation.Action](a, 3usize)
    if quick_error != ok { ret (0usize, quick_error) }
    quick[0usize] = navigation.Action { label: "Save", action: press, icon: zero, enabled: true }
    quick[1usize] = navigation.Action { label: "Undo", action: press, icon: zero, enabled: true }
    quick[2usize] = navigation.Action { label: "Redo", action: press, icon: zero, enabled: false }
    let (clip, clip_error) = mem.alloc[navigation.RibbonCommand](a, 3usize)
    let (font, font_error) = mem.alloc[navigation.RibbonCommand](a, 3usize)
    let (tables, tables_error) = mem.alloc[navigation.RibbonCommand](a, 2usize)
    let (zoom, zoom_error) = mem.alloc[navigation.RibbonCommand](a, 1usize)
    if clip_error != ok || font_error != ok || tables_error != ok || zoom_error != ok { ret (0usize, clip_error) }
    clip[0usize] = command("Paste", .Add, true, press)
    clip[1usize] = command("Cut", .Cross, false, press)
    clip[2usize] = command("Copy", .Check, false, press)
    font[0usize] = command("Bold", .Edit, false, press)
    font[0usize].toggle = true
    font[0usize].checked = true
    font[1usize] = command("Italic", .Edit, false, press)
    font[2usize] = command("Underline", .Edit, false, press)
    tables[0usize] = command("Table", .Calendar, true, press)
    tables[1usize] = command("Picture", .Picture, true, press)
    zoom[0usize] = command("Zoom", .Visibility, true, press)
    let (g_home, g_home_error) = mem.alloc[navigation.RibbonGroup](a, 2usize)
    let (g_insert, g_insert_error) = mem.alloc[navigation.RibbonGroup](a, 1usize)
    let (g_view, g_view_error) = mem.alloc[navigation.RibbonGroup](a, 1usize)
    let (tabs, tabs_error) = mem.alloc[navigation.RibbonTab](a, 5usize)
    if g_home_error != ok || g_insert_error != ok || g_view_error != ok || tabs_error != ok { ret (0usize, tabs_error) }
    g_home[0usize] = navigation.RibbonGroup { label: "Clipboard", commands: clip[0usize..3usize], launcher: press, launcher_label: "Clipboard options" }
    g_home[1usize] = navigation.RibbonGroup { label: "Font", commands: font[0usize..3usize], launcher: zero, launcher_label: "" }
    g_insert[0usize] = navigation.RibbonGroup { label: "Tables", commands: tables[0usize..2usize], launcher: zero, launcher_label: "" }
    g_view[0usize] = navigation.RibbonGroup { label: "Zoom", commands: zoom[0usize..1usize], launcher: zero, launcher_label: "" }
    var i = 0usize
    while i < 6usize {
        let context = i == 2usize
        tabs[0usize] = navigation.RibbonTab { label: "Home", groups: g_home[0usize..2usize], context: "", visible: true }
        tabs[1usize] = navigation.RibbonTab { label: "Insert", groups: g_insert[0usize..1usize], context: "", visible: true }
        tabs[2usize] = navigation.RibbonTab { label: "View", groups: g_view[0usize..1usize], context: "", visible: true }
        tabs[3usize] = navigation.RibbonTab { label: "Design", groups: g_insert[0usize..1usize], context: "Table Tools", visible: context }
        tabs[4usize] = navigation.RibbonTab { label: "Layout", groups: g_view[0usize..1usize], context: "Table Tools", visible: context }
        var options = navigation.ribbon_options()
        options.selected = 0usize
        if i == 1usize { options.selected = 1usize }
        if i == 2usize { options.selected = 3usize }
        options.collapsed = i == 3usize
        options.picks = picks[0usize..5usize]
        options.collapse = press
        options.dismiss = press
        options.quick = quick[0usize..3usize]
        options.width = 640.0
        let (node, node_error) = navigation.ribbon(a, u64((i + 1usize) * 1000usize), t, tabs[0usize..5usize], options)
        if node_error != ok { ret (0usize, node_error) }
        var drive: looks.Drive = .None
        if i == 4usize || i == 5usize {
            drive = .Hover
            looks.aim(i, -270.0, 0.0)
        }
        if i == 5usize { drive = .Press }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: drive }
        i += 1usize
    }
    ret (6usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "ribbon", cells: 6usize, columns: 2usize, cell_w: 660.0, cell_h: 190.0, ctx: zero, build: build }
    ret looks_f.run_ten(a, &sheet)
}
