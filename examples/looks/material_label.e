// The Android look's labels: the Material 3 type scale (display, headline, title, body, label) in on-surface, then the
// colour states of a label: supporting (on-surface-variant), primary, error, disabled (38 %) and a link. Run from the
// repository root; docs/ui/looks/material/label.png.

use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget
use e.gfx.paint

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let captions = [16]str{ "Display small", "Headline medium", "Headline small", "Title large", "Title medium", "Title small", "Body large", "Body medium", "Body small", "Label large", "Label medium", "Supporting", "Primary", "Error", "Disabled", "Link" }
    let words = [16]str{ "Terminate", "Terminate", "Terminate", "Terminate", "Terminate", "Terminate", "Terminate the target", "Terminate the target", "Terminate the target", "Terminate", "Terminate", "Supporting text", "Last update today", "Name is required", "Font size", "Send email to Support" }
    let roles = [16]style.TextRole{ .DisplaySmall, .HeadlineMedium, .HeadlineSmall, .TitleLarge, .TitleMedium, .TitleSmall, .BodyLarge, .BodyMedium, .BodySmall, .LabelLarge, .LabelMedium, .BodyMedium, .BodyMedium, .BodySmall, .BodyLarge, .BodyMedium }
    var i = 0usize
    while i < 16usize {
        var options = control.text_options()
        options.role = roles[i]
        options.wrap = .None
        var color = style.color(t.tokens, .OnSurface)
        if i == 11usize { color = style.color(t.tokens, .OnSurfaceVariant) }
        if i == 12usize { color = style.color(t.tokens, .Primary) }
        if i == 13usize { color = style.color(t.tokens, .Error) }
        if i == 14usize { color = control.with_alpha(style.color(t.tokens, .OnSurface), t.tokens.states.disabled_content) }
        if i == 15usize { color = style.color(t.tokens, .Primary) }
        let (node, node_error) = control.colored_text(a, 0u64, words[i], t, options, color)
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: captions[i], node: node, drive: .None }
        i += 1usize
    }
    ret (16usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "label", cells: 16usize, columns: 4usize, cell_w: 260.0, cell_h: 56.0, ctx: zero, build: build }
    ret looks.run_material(a, &sheet)
}
