// The Cupertino label (TcxLabel): docs/ui/looks/cupertino/label.png (and cupertino-dark). The iOS text styles in the
// theme's type scale (SF Pro sizes set in Segoe UI): body, secondary label, footnote, caption, headline, title, large title,
// a tappable link, the link while held, a disabled label, the grouped-list section header and the macOS form label.

use e.gfx.paint
use e.mem
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

fn word(a: *mem.Arena, t: *const control.Theme, i: usize, value: str, role: style.TextRole, ink: paint.Color, size: f32, weight: u32) -> (widget.Node, err) {
    var options = control.text_options()
    options.role = role
    options.wrap = .None
    options.size = size
    options.weight = weight
    let (made, made_error) = control.colored_text(a, u64(i + 1usize), value, t, options, ink)
    ret (made, made_error)
}

fn build(ctx: *void, a: *mem.Arena, t: *const control.Theme, cells: []looks.Cell) -> (usize, err) {
    let names = [12]str{ "Body 17", "Secondary label", "Footnote 13", "Caption 12", "Headline 17 semibold", "Title 2 22", "Large title 34 bold", "Link", "Link, pressed", "Disabled", "Section header", "macOS form label 13" }
    let ink = style.color(t.tokens, .Text)
    let muted = style.color(t.tokens, .TextMuted)
    let blue = style.color(t.tokens, .Primary)
    var dim = ink
    dim.alpha = 0.3
    var blue_held = blue
    blue_held.alpha = 0.35
    let values = [12]str{ "Row Color", "Last update on October 10, 2026", "Updated 3 minutes ago", "Source: Scryfall", "Deck Properties", "Interface", "Library", "Send email to Support", "Send email to Support", "Font Size", "COLOR SCHEME", "Card Name:" }
    let roles = [12]style.TextRole{ .Body, .Body, .BodySmall, .Caption, .Heading, .Title, .DisplayLarge, .Body, .Body, .Body, .BodySmall, .BodySmall }
    let inks = [12]paint.Color{ ink, muted, muted, muted, ink, ink, ink, blue, blue_held, dim, muted, ink }
    let sizes = [12]f32{ 0.0, 0.0, 13.0, 0.0, 0.0, 0.0, 34.0, 0.0, 0.0, 0.0, 13.0, 13.0 }
    let weights = [12]u32{ 0u32, 0u32, 0u32, 0u32, 0u32, 0u32, 700u32, 0u32, 0u32, 0u32, 0u32, 0u32 }
    var i = 0usize
    while i < 12usize {
        let (node, node_error) = word(a, t, i, values[i], roles[i], inks[i], sizes[i], weights[i])
        if node_error != ok { ret (0usize, node_error) }
        cells[i] = looks.Cell { caption: names[i], node: node, drive: .None }
        i += 1usize
    }
    ret (12usize, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sheet = looks.Sheet { name: "label", cells: 12usize, columns: 3usize, cell_w: 270.0, cell_h: 46.0, ctx: zero, build: build }
    ret looks.run_cupertino(a, &sheet)
}
