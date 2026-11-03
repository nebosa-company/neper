// Round 85, lane z: switches the Material sheets set before a frame is built. Each is off unless a sheet app turns it on, so every
// other picture is built as before.

// A virtual list's rows take the pointer's state layer (collection.row), for a sheet whose hover cell aims at a row.
var hover_rows: bool = false

fn rows_hover(on: bool) { hover_rows = on }
