// `e.ui.style`'s theme tokens (D805, widget plan P0-01): the three reference
// palettes validate and differ where they should; a colour and a text role are
// looked up; a control's look resolves under each state -- filled, outlined and
// plain, pressed, hovered, focused, disabled, invalid, read-only, selected; the
// size class breakpoints; and the adaptation of a theme to a touch host, a dense
// desktop and a compact width. A broken theme is refused.

use e.io
use e.math
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.ui.style

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn same_color(a: paint.Color, b: paint.Color) -> bool {
    ret near(a.red, b.red) && near(a.green, b.green) && near(a.blue, b.blue) && near(a.alpha, b.alpha)
}

// WCAG 2 relative luminance and contrast ratio.
fn channel(c: f32) -> f32 {
    if c <= 0.04045 { ret c / 12.92 }
    ret math.pow[f32]((c + 0.055) / 1.055, 2.4)
}

fn luminance(c: paint.Color) -> f32 {
    ret 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
}

fn ratio(a: paint.Color, b: paint.Color) -> f32 {
    let x = luminance(a) + 0.05
    let y = luminance(b) + 0.05
    if x > y { ret x / y }
    ret y / x
}

// The v2 pairs (D937): content on its container holds `need` in a palette; the
// outline and the focus ring hold 3:1 on the grounds they are drawn on.
fn pairs_hold(t: *const style.ThemeTokens, need: f32) -> bool {
    var grounds: [6]style.ColorRole = zero
    grounds[0] = .Background
    grounds[1] = .SurfaceContainerLowest
    grounds[2] = .SurfaceContainerLow
    grounds[3] = .SurfaceContainer
    grounds[4] = .SurfaceContainerHigh
    grounds[5] = .SurfaceContainerHighest
    var i = 0usize
    while i < grounds.len {
        if ratio(style.color(t, .OnSurface), style.color(t, grounds[i])) < need { ret false }
        if ratio(style.color(t, .Outline), style.color(t, grounds[i])) < 3.0 { ret false }
        i += 1usize
    }
    if ratio(style.color(t, .OnSurfaceVariant), style.color(t, .SurfaceContainerHighest)) < need { ret false }
    if ratio(style.color(t, .OnPrimary), style.color(t, .Primary)) < need { ret false }
    if ratio(style.color(t, .OnPrimaryContainer), style.color(t, .PrimaryContainer)) < need { ret false }
    if ratio(style.color(t, .OnSecondaryContainer), style.color(t, .SecondaryContainer)) < need { ret false }
    if ratio(style.color(t, .OnError), style.color(t, .Error)) < need { ret false }
    if ratio(style.color(t, .OnErrorContainer), style.color(t, .ErrorContainer)) < need { ret false }
    if ratio(style.color(t, .InverseOnSurface), style.color(t, .InverseSurface)) < need { ret false }
    if ratio(style.color(t, .FocusRing), style.color(t, .Background)) < 3.0 { ret false }
    if ratio(style.color(t, .FocusRing), style.color(t, .PrimaryContainer)) < 3.0 { ret false }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let light = style.reference(.Light)
    let dark = style.reference(.Dark)
    let contrast = style.reference(.HighContrast)
    if style.validate_theme(&light) != ok || style.validate_theme(&dark) != ok || style.validate_theme(&contrast) != ok { os.exit(1i32) }
    if light.palette != .Light || light.profile != .Neper || light.direction != .LeftToRight { os.exit(2i32) }
    // Roles: a dark background is dark, a light one light; text contrasts each.
    if !(style.color(&dark, .Background).red < 0.2) || !(style.color(&light, .Background).red > 0.9) { os.exit(3i32) }
    if !(style.color(&dark, .Text).red > 0.8) || !(style.color(&light, .Text).red < 0.2) { os.exit(4i32) }
    if !(contrast.borders.hairline > light.borders.hairline) { os.exit(5i32) }
    let heading = style.text_style(&light, .Heading)
    let body = style.text_style(&light, .Body)
    if !(heading.size > body.size) || heading.weight < body.weight || !near(body.line_height, 20.0) { os.exit(6i32) }
    // Resolution: filled takes primary/on-primary; outlined the surface with a
    // border; plain no background; pressed moves toward the background, hover
    // toward the text; focus draws the ring; disabled halves; invalid borders in
    // the error colour; read-only mutes; selected tints.
    var rest: style.ControlState = zero
    let filled = style.resolve(&light, .Filled, rest)
    if !same_color(filled.background, style.color(&light, .Primary)) || !same_color(filled.foreground, style.color(&light, .OnPrimary)) || !near(filled.border_width, 0.0) || !near(filled.opacity, 1.0) || !near(filled.focus_ring, 0.0) { os.exit(7i32) }
    let outlined = style.resolve(&light, .Outlined, rest)
    if !same_color(outlined.background, style.color(&light, .Surface)) || !near(outlined.border_width, light.borders.regular) || !same_color(outlined.border, style.color(&light, .Border)) { os.exit(8i32) }
    let plain = style.resolve(&light, .Plain, rest)
    if !near(plain.background.alpha, 0.0) || !same_color(plain.foreground, style.color(&light, .Primary)) { os.exit(9i32) }
    var pressed: style.ControlState = zero
    pressed.pressed = true
    let pressed_look = style.resolve(&light, .Filled, pressed)
    if !(pressed_look.background.red > filled.background.red) { os.exit(10i32) }
    var hovered: style.ControlState = zero
    hovered.hovered = true
    let hovered_look = style.resolve(&light, .Filled, hovered)
    if !(hovered_look.background.blue < filled.background.blue) || same_color(hovered_look.background, pressed_look.background) { os.exit(11i32) }
    var focused: style.ControlState = zero
    focused.focused = true
    if !near(style.resolve(&light, .Filled, focused).focus_ring, light.metrics.focus_ring) { os.exit(12i32) }
    var disabled: style.ControlState = zero
    disabled.disabled = true
    if !near(style.resolve(&light, .Filled, disabled).opacity, 0.5) { os.exit(13i32) }
    var invalid: style.ControlState = zero
    invalid.invalid = true
    let invalid_look = style.resolve(&light, .Plain, invalid)
    if !same_color(invalid_look.border, style.color(&light, .Error)) || !near(invalid_look.border_width, light.borders.regular) { os.exit(14i32) }
    var read_only: style.ControlState = zero
    read_only.read_only = true
    if !same_color(style.resolve(&light, .Filled, read_only).foreground, style.color(&light, .TextMuted)) { os.exit(15i32) }
    var selected: style.ControlState = zero
    selected.selected = true
    if same_color(style.resolve(&light, .Outlined, selected).background, outlined.background) { os.exit(16i32) }
    // Size classes at the shared breakpoints.
    if style.size_class(320.0) != .Compact || style.size_class(599.9) != .Compact || style.size_class(600.0) != .Medium || style.size_class(839.0) != .Medium || style.size_class(840.0) != .Expanded { os.exit(17i32) }
    // Adaptation: a touch host grows the targets; a dense desktop shrinks them; a
    // compact width tightens the spacing; the profile is recorded.
    let touch = style.adapt(&light, style.Adaptation { size: .Expanded, capabilities: style.Capabilities { hover: false, fine_pointer: false, keyboard: false, touch: true, pen: false, resizable: false, multi_window: false, insets: geometry.Insets { left: 0.0, top: 24.0, right: 0.0, bottom: 34.0 } }, profile: .Neper })
    if !near(touch.metrics.hit_target, light.sizes.target_touch) || !near(touch.metrics.hit_target, 48.0) || !near(touch.metrics.control_height, light.sizes.control_md) || !(touch.spacing.md > light.spacing.md) || touch.profile != .Neper { os.exit(18i32) }
    let dense = style.adapt(&light, style.Adaptation { size: .Expanded, capabilities: style.Capabilities { hover: true, fine_pointer: true, keyboard: true, touch: false, pen: false, resizable: true, multi_window: true, insets: zero }, profile: .DesktopDense })
    if !near(dense.metrics.control_height, 24.0) || !(dense.spacing.lg < light.spacing.lg) || dense.profile != .DesktopDense { os.exit(19i32) }
    let compact = style.adapt(&light, style.Adaptation { size: .Compact, capabilities: style.Capabilities { hover: true, fine_pointer: true, keyboard: true, touch: false, pen: false, resizable: true, multi_window: false, insets: zero }, profile: .Neper })
    if !near(compact.spacing.xl, light.spacing.lg) || !near(compact.metrics.hit_target, light.metrics.hit_target) { os.exit(20i32) }
    if style.validate_theme(&touch) != ok || style.validate_theme(&dense) != ok || style.validate_theme(&compact) != ok { os.exit(21i32) }
    // A broken theme: a line height below its size, a spacing out of order.
    var broken = light
    broken.text[0].line_height = 8.0
    if style.validate_theme(&broken) != style.Invalid { os.exit(22i32) }
    var disordered = light
    disordered.spacing.xs = 100.0
    if style.validate_theme(&disordered) != style.Invalid { os.exit(23i32) }
    try io.print("ui theme ok\n")
    ret ok
}
