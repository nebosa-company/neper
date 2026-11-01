// Round 79, lane q: the Android look's menu bar and menu. New code lives here; navigation.e carries only the hooks.
// Numbers: Flutter's MenuBar defaults (menu_anchor.dart, _MenuBarDefaultsM3 / _MenuButtonDefaultsM3 / _MenuDefaultsM3):
// surface-container, elevation 3, 4 px corners, buttons at least 64 x 48 with 8 px side padding, state layers 8 % hover and
// 10 % pressed or focused, menu panel 8 px top and bottom padding, rows 48 high (M3 md.comp.menu.list-item.container.height).

use e.ui.control
use e.ui.style

fn is_material(t: *const control.Theme) -> bool {
    ret t.tokens.profile == .MaterialLike
}

// The bar: a 48 high surface-container strip with 4 px corners and the level 3 shadow.
fn bar_style(t: *const control.Theme) -> style.Style {
    var o = control.surface_options(t)
    o.background = .SurfaceContainer
    o.elevation = 0u8
    o.radius = 4.0
    o.padding = 0.0
    var s = control.surface_style(t, o)
    s.shade = 3u8
    s.width = style.Length { Percent: 100.0 }
    s.height = style.Length { Px: 48.0 }
    let ends = style.Length { Px: 4.0 }
    let flat = style.Length { Px: 0.0 }
    s.padding = style.EdgeLengths { left: ends, top: flat, right: ends, bottom: flat }
    ret s
}

// A top-level title: square, 64 x 48 at least, 12 px side padding (_scaledPadding, standard density), hover 8 %, pressed or open 10 % of on-surface.
fn title_look(t: *const control.Theme, look: *style.ResolvedControl, opened: bool, state: style.ControlState) {
    let ink = style.color(t.tokens, .OnSurface)
    var a: f32 = 0.0
    if state.focus_visible { a = 0.10 }
    if state.hovered { a = 0.08 }
    if opened || state.pressed { a = 0.10 }
    look.background = control.with_alpha(ink, a)
    look.foreground = ink
    look.radius = 0.0
    look.padding = 12.0
    look.padding_y = 0.0
    look.min_height = 48.0
    look.min_width = 64.0
}
