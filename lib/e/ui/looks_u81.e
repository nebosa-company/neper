// Round 81, lane u: Android menu panel at its content width. navigation.e carries only the hooks.
// Source: Flutter menu_anchor.dart, `_MenuItemLabel` inside the vertical menu's `IntrinsicWidth`: a row is 12 padding, the
// label, 12, the shortcut (12, 24 icon for a submenu), 12 padding; the panel is the widest row, held to the M3 menu's
// 112 to 280 dp (md.comp.menu.container) and its divider is `Divider(height: 16)`.

fn row_width(label: f32, shortcut: f32, has_shortcut: bool, has_submenu: bool, slotted: bool) -> f32 {
    var w: f32 = 24.0 + label
    if slotted { w += 30.0 }
    if has_shortcut { w += 12.0 + shortcut }
    if has_submenu { w += 30.0 }
    ret w
}

fn panel_width(widest: f32) -> f32 {
    var w = f32(u32(widest + 0.999))
    if w < 112.0 { w = 112.0 }
    if w > 280.0 { w = 280.0 }
    ret w
}
