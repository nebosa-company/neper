// Round 85, lane y: Cupertino-only sheet helpers. Plain values only (control imports the looks files, not the other way round).

use e.mem
use e.ui.style

error TooLarge

// Like looks_y84.tinted, and the keyboard ring takes the same blue at 80 % (the stock Cupertino ring is the accent at 55 %, about
// 2:1 on the ground); any other look gets `base` back unchanged.
fn tinted_ring(a: *mem.Arena, base: *const style.ThemeTokens, light: u32, dark: u32) -> (*const style.ThemeTokens, err) {
    if base.profile != .CupertinoLike { ret (base, ok) }
    let (copy, copy_error) = mem.alloc[style.ThemeTokens](a, 1usize)
    if copy_error != ok { ret (base, TooLarge) }
    copy[0usize] = *base
    var value = light
    if base.palette == .Dark { value = dark }
    style.puta(&copy[0usize], .Primary, value, 1.0)
    // the dark ring stays the light blue even where the fill is a darker one, so it holds 3:1 on the ground
    var ring = value
    if base.palette == .Dark { ring = 0x409CFFu32 }
    style.puta(&copy[0usize], .FocusRing, ring, 0.8)
    ret (&copy[0usize], ok)
}

// UIKit's opaque separator (the colour the translucent hairline composes to on the grouped ground): C6C6C8 light, 38383A dark;
// strong is the 3:1 rule for a divider that must be seen: 8A8A8E light, 6C6C70 dark.
fn separator(dark: bool, strong: bool) -> u32 {
    if strong {
        if dark { ret 0x6C6C70u32 }
        ret 0x8A8A8Eu32
    }
    if dark { ret 0x38383Au32 }
    ret 0xC6C6C8u32
}

// The grouped inset card face: secondarySystemGroupedBackground on the grouped ground (white light, 2C2C2E dark).
fn card_face(dark: bool) -> u32 {
    if dark { ret 0x2C2C2Eu32 }
    ret 0xFFFFFFu32
}
