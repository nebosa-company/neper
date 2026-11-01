// Round 62, worker a: sheet helpers for the controls drawn in all ten looks (icon button, toggle button, split button, speed dial,
// link, range slider, rating, dial, password field, search field, autocomplete). Nothing here is used by the library itself.

use e.gfx.paint
use e.mem
use e.ui.accessibility
use e.ui.adwicon_l2 as adwicon
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

// control.icon_button wants a loaded texture and a rig has none, so the picture is a glyph of the control kit (a 16 px mark under
// Windows, the style's icon size elsewhere); Linux uses the Adwaita symbolic icon, Material its own icon button.
fn icon_button_glyph(a: *mem.Arena, key: widget.Key, t: *const control.Theme, kind: control.GlyphKind, label: str, action: *const widget.Submit, options: control.ButtonOptions) -> (widget.Node, err) {
    if t.tokens.profile == .Linux {
        let (gtk, gtk_error) = control.button_with_svg(a, key, t, adwicon.edit_copy(), "", action, options)
        ret (gtk, gtk_error)
    }
    if t.tokens.profile == .MaterialLike {
        let (droid, droid_error) = control.material_icon_button(a, key, t, kind, label, action, options.variant, options.enabled, false)
        ret (droid, droid_error)
    }
    if t.tokens.profile == .Windows {
        let state = control.control_state(t, key, options.enabled, false)
        let (mark, mark_error) = control.icon_square(a, style.windows_resolve(t.tokens, options.variant, state).foreground, kind, 16.0)
        if mark_error != ok { ret (zero, mark_error) }
        var sized = options
        sized.width = 32.0
        sized.height = 24.0
        let (win, win_error) = control.windows_button(a, key, t, label, mark, true, false, false, zero, action, sized)
        ret (win, win_error)
    }
    let state = control.control_state(t, key, options.enabled, false)
    let (look, size) = control.icon_look(t, style.resolve(t.tokens, options.variant, state), options.variant, options.enabled)
    let (mark, mark_error) = control.icon_square(a, look.foreground, kind, size)
    if mark_error != ok { ret (zero, mark_error) }
    let (node, node_error) = control.pressable(a, key, t, 3u8, label, look, options.enabled, false, action, mark)
    ret (node, node_error)
}

// The sheet under every look: Neper, Windows and Windows dark (and Neper dark), Linux, Cupertino and Material, each Light and Dark.
fn run_every(a: *mem.Arena, s: *const looks.Sheet) -> err {
    try looks.run_all(a, s)
    try looks.run_linux(a, s)
    try looks.run_cupertino(a, s)
    ret looks.run_material(a, s)
}
