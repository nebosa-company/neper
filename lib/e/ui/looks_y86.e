// Round 86, lane y: Cupertino-only values for the generic rows. Plain values only (control and navigation import this file).

// A chosen list row (a command palette or switcher row): the accent that white text holds 4.5:1 on, like the data grid's chosen row.
fn row_select(dark: bool) -> u32 {
    if dark { ret 0x0B57D0u32 }
    ret 0x0A60FFu32
}

// The chosen document tab's face on the strip: white on the light strip, 636366 on the dark one.
fn tab_face(dark: bool) -> u32 {
    if dark { ret 0x636366u32 }
    ret 0xFFFFFFu32
}
