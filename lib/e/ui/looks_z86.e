// Round 86, lane z: the Material font picker previews each family in its own face where the rig has one. The rig loads Roboto,
// Segoe UI and Tahoma only; a family it has no face for is shown by name alone (no sample drawn in a stand-in face). Off unless the
// picker turns it on, so every other picture is built as before.
use e.str as strs

var faces: bool = false

fn set_faces(on: bool) { faces = on }

fn faces_on() -> bool { ret faces }

// Whether the rig has a face for the family.
fn has_face(name: str) -> bool {
    ret strs.eq(name, "Roboto") || strs.eq(name, "Segoe UI") || strs.eq(name, "Tahoma")
}

// The id that leads the font chain for the family (0: the theme's own face, which is Roboto).
fn face_of(name: str) -> u32 {
    if strs.eq(name, "Segoe UI") { ret 7u32 }
    if strs.eq(name, "Tahoma") { ret 8u32 }
    ret 0u32
}

// The slant of a synthetic italic, as Flutter's fake italic (Skia's skewX of -1/4).
fn oblique() -> f32 { ret -0.25 }
