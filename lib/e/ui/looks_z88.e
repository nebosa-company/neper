// Round 88, lane z: switches the Material sheets set before a frame is built. Each is off unless a sheet app turns it on, so every
// other picture is built as before.

// A table's header takes the surface colour, as Flutter's DataTable header does (the rule under it is the divider).
var flat_head: bool = false

fn head_flat(on: bool) { flat_head = on }

fn head_is_flat() -> bool { ret flat_head }
