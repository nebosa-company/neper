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

// control.password_field_with centres its reveal button on a field of the Neper height (control height + 16), which leaves it 5 to 7 px
// low on the 22 px Windows edit and the 34 px Cupertino one. Same widget tree with the field's real height; the other looks pass
// straight through.
fn password_fitted(a: *mem.Arena, key: widget.Key, t: *const control.Theme, label: str, buffer: []u8, len: usize, change: widget.Change[str], submit: widget.Submit, options: control.FieldOptions, revealed: bool, reveal: *const widget.Submit) -> (widget.Node, err) {
    var field_h: f32 = 0.0
    if t.tokens.profile == .Windows { field_h = 22.0 }
    if t.tokens.profile == .CupertinoLike { field_h = 34.0 }
    if field_h == 0.0 {
        let (plain, plain_error) = control.password_field_with(a, key, t, label, buffer, len, change, submit, options, revealed, reveal)
        ret (plain, plain_error)
    }
    let side = t.tokens.sizes.control_sm
    var roomy = options
    roomy.rows = 1u32
    roomy.end_space = control.max_zero(side - 8.0)
    let (editor, editor_error) = control.field(a, key, t, label, buffer, len, change, submit, roomy, !revealed)
    if editor_error != ok { ret (zero, editor_error) }
    let state = control.control_state(t, key + 1u64, true, revealed)
    var ink = style.color(t.tokens, .OnSurfaceVariant)
    var eye: control.GlyphKind = .Visibility
    if revealed {
        ink = style.color(t.tokens, .Primary)
        eye = .VisibilityOff
    }
    let (mark, mark_error) = control.icon_square(a, ink, eye, t.tokens.sizes.icon_sm)
    if mark_error != ok { ret (zero, mark_error) }
    let (held, held_error) = mem.alloc[widget.Node](a, 4usize)
    if held_error != ok { ret (zero, held_error) }
    held[0usize] = mark
    var disc = control.sized_style(side, side)
    disc.radius = side * 0.5
    disc.background = paint.Brush { Solid: control.with_alpha(ink, control.state_opacity(t, state)) }
    held[1usize] = widget.aligned(0u64, .Center, .Center, disc, held[0usize..1usize])
    held[2usize] = widget.region(key + 1u64, widget.Region { gesture: widget.GestureAction { ctx: mem.cast[*void](reveal), invoke: control.press_tap }, gestures: 1u8 | 4u8, enabled: true, focusable: false }, style.defaults(), held[1usize..2usize])
    var sem: widget.Semantics = zero
    sem.role = 3u8
    sem.label = "Show password"
    sem.actions = accessibility.ACTION_PRESS
    sem.on_action = widget.Change[u32] { ctx: mem.cast[*void](reveal), invoke: control.reveal_semantic_action }
    if revealed { sem.states = accessibility.STATE_CHECKED }
    held[3usize] = widget.semantics(0u64, sem, style.defaults(), held[2usize..3usize])
    let (layers, layers_error) = mem.alloc[widget.Node](a, 2usize)
    if layers_error != ok { ret (zero, layers_error) }
    layers[0usize] = editor
    layers[1usize] = widget.positioned(0u64, options.width - 4.0 - side, control.max_zero((field_h - side) * 0.5), style.defaults(), held[3usize..4usize])
    ret (widget.stack(0u64, style.defaults(), layers[0usize..2usize]), ok)
}
