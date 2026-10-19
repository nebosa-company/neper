// The Android look's two text modes side by side (docs/ui/looks/android-text.md): ChromeWin (Chrome on Windows, the references) and
// AndroidSkia (a device's Skia over FreeType). No argument: the type scale of material_label.e in both modes. Argument `probe`: one
// black glyph per cell at several sizes, the sheet scripts/material/ftprobe.py checks against FreeType. Run from the repository root;
// writes docs/ui/looks/android-text/<sheet>_chromewin.png and <sheet>_androidskia.png (the script puts them side by side).

use e.fs
use e.gfx.paint
use e.gfx.scene
use e.mem
use e.str as strs
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn build_words(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [12]str{ "Display small", "Headline medium", "Title large", "Title medium", "Title small", "Body large", "Body medium", "Body small", "Label large", "Label medium", "Label small", "Supporting" }
    let words = [12]str{ "Terminate", "Terminate", "Terminate", "Terminate the", "Terminate the", "Terminate the target", "Terminate the target", "Terminate the target", "Terminate", "Terminate", "Terminate", "Supporting text" }
    let roles = [12]style.TextRole{ .DisplaySmall, .HeadlineMedium, .TitleLarge, .TitleMedium, .TitleSmall, .BodyLarge, .BodyMedium, .BodySmall, .LabelLarge, .LabelMedium, .LabelSmall, .BodyMedium }
    var i = 0usize
    while i < 12usize {
        var options = control.text_options()
        options.role = roles[i]
        options.wrap = .None
        var color = style.color(t.tokens, .OnSurface)
        if i == 11usize { color = style.color(t.tokens, .OnSurfaceVariant) }
        let (node, node_error) = control.colored_text(a, 0u64, words[i], t, options, color)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (12usize, ok)
}

// Sixteen glyphs at 11, 12, 14, 16, 22 and 28 px, then two-glyph words (the second pen is at a fraction of a pixel) at 14 and 16.
fn build_probe(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let glyphs = [16]str{ "A", "g", "R", "o", "e", "&", "1", "Q", "W", "y", "@", "%", "t", "s", "k", "8" }
    let words = [16]str{ "ao", "ii", "ty", "re", "ow", "ft", "il", "rk", "ao", "ii", "ty", "re", "ow", "ft", "il", "rk" }
    let sizes = [8]f32{ 11.0, 12.0, 14.0, 16.0, 22.0, 28.0, 14.0, 16.0 }
    let black = paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0 }
    var i = 0usize
    while i < 128usize {
        var options = control.text_options()
        options.role = .BodyMedium
        options.wrap = .None
        options.size = sizes[i / 16usize]
        var value = glyphs[i % 16usize]
        if i >= 96usize { value = words[i % 16usize] }
        let (node, node_error) = control.colored_text(a, 0u64, value, t, options, black)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: "", node: node, drive: .None }
        i += 1usize
    }
    ret (128usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var sheet = looks.Sheet { name: "words", cells: 12usize, columns: 4usize, cell_w: 220.0, cell_h: 56.0, ctx: zero, build: build_words }
    if args.len > 1usize && strs.eq(args[1usize], "probe") {
        sheet = looks.Sheet { name: "probe", cells: 128usize, columns: 16usize, cell_w: 44.0, cell_h: 40.0, ctx: zero, build: build_probe }
    }
    var mode = 0usize
    while mode < 2usize {
        let ra = looks.rig_scope(a)
        let (rig, open_error) = looks.open(ra, looks.sheet_width(&sheet), looks.sheet_height(&sheet), 1.0)
        if open_error != ok { ret open_error }
        looks.set_look(rig, .Material)
        var tail = "_chromewin"
        scene.set_text_aa(.ChromeWin)
        if mode == 1usize {
            tail = "_androidskia"
            scene.set_text_aa(.AndroidSkia)
        }
        let (folder, folder_error) = looks.path_of(ra, "android-text", "", "", 1.0, "")
        if folder_error != ok { ret folder_error }
        try fs.make_dirs(ra, folder)
        let (path, path_error) = looks.path_of(ra, "android-text", sheet.name, tail, 1.0, ".png")
        if path_error != ok { ret path_error }
        let (ours, render_error) = looks.render_sheet(rig, &sheet, path)
        if render_error != ok { ret render_error }
        looks.close_rig(rig)
        mode += 1usize
    }
    ret ok
}
