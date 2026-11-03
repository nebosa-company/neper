// Round 63 (x): helpers for the shared-control fixes. The sheet rig has no fixed-pitch font, so a Cupertino terminal list drew its
// rows in the proportional face. `mono_theme` adds Consolas (Menlo and SF Mono are not installed here, so it stands in) for that look.

use e.fs
use e.gfx.scene
use e.mem
use e.text.shape
use e.ui.control
use e.ui.looks
use e.ui.style
use e.ui.widget

var mono_bytes: []u8 = zero
var mono_read: bool = false
var droid_bytes: []u8 = zero
var droid_read: bool = false

// The theme itself, or for the Cupertino look a copy whose fonts carry Consolas as id 21 (registered with the rig's renderer).
fn mono_theme(a: *mem.Arena, t: *const control.Theme) -> (*const control.Theme, err) {
    // Round 85 (z): the Android look gets Cascadia Mono (id 22; Roboto Mono is not installed here and stands in the same way).
    let droid = t.tokens.profile == .MaterialLike
    if (t.tokens.profile != .CupertinoLike && !droid) || mem.address_of(t.runtime) == 0usize { ret (t, ok) }
    var path = "C:/Windows/Fonts/consola.ttf"
    var face_id = 21u32
    if droid {
        path = "C:/Windows/Fonts/CascadiaMono.ttf"
        face_id = 22u32
    }
    if droid && !droid_read {
        let (bytes, read_error) = fs.read_file(looks.stable(a), path, 16777216usize)
        if read_error != ok { ret (t, read_error) }
        droid_bytes = bytes
        droid_read = true
    }
    if !droid && !mono_read {
        let (bytes, read_error) = fs.read_file(looks.stable(a), path, 16777216usize)
        if read_error != ok { ret (t, read_error) }
        mono_bytes = bytes
        mono_read = true
    }
    var face = shape.Font { id: face_id, data: mono_bytes, face_index: 0u32 }
    if droid { face = shape.Font { id: face_id, data: droid_bytes, face_index: 0u32 } }
    let (state, state_error) = widget.state_of(t.runtime)
    if state_error != ok { ret (t, state_error) }
    try scene.register_font(state.renderer, face)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, t.fonts.len + 1usize)
    if fonts_error != ok { ret (t, fonts_error) }
    var i = 0usize
    while i < t.fonts.len {
        fonts[i] = t.fonts[i]
        i += 1usize
    }
    fonts[t.fonts.len] = face
    let (made, made_error) = mem.alloc[control.Theme](a, 1usize)
    if made_error != ok { ret (t, made_error) }
    made[0usize] = control.Theme { tokens: t.tokens, fonts: fonts[0usize..t.fonts.len + 1usize], language: t.language, runtime: t.runtime }
    ret (&made[0usize], ok)
}
