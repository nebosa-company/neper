use e.mem
use e.os
use e.ui.control
use e.ui.style

fn main(a: *mem.Arena, args: []str) -> err {
    var tokens = style.reference(.Light)
    tokens.profile = .Windows
    let theme = control.Theme { tokens: &tokens, fonts: zero, language: "", runtime: zero }
    var full_storage: [16384]u8 = zero
    var full = mem.arena_from(full_storage[..])
    let (_, full_error) = control.windows_scroll_bar_disabled(&full, &theme, true, 80.0)
    if full_error != ok { os.exit(1i32) }
    let used = mem.mark(&full)
    if used == 0usize || used >= full_storage.len { os.exit(2i32) }
    var tight_storage: [16384]u8 = zero
    var tight = mem.arena_from(tight_storage[0usize..used - 1usize])
    let (_, tight_error) = control.windows_scroll_bar_disabled(&tight, &theme, true, 80.0)
    if tight_error != control.TooLarge { os.exit(3i32) }
    ret ok
}
