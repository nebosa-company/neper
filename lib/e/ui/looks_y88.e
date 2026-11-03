// Round 88, lane y: Cupertino-only values. Plain values only (control imports this file, not the other way round).

// The avatar presence badge: the control draws the dot 4 smaller than this size (ring pad), so 16 gives the iOS 12 pt dot, 14 a 10 pt one.
fn badge_size(size: f32) -> f32 {
    if size <= 32.0 { ret 14.0 }
    ret 16.0
}

// How far the ringed badge hangs past the disc's lower right corner, so it stands off the initials.
fn badge_hang(size: f32) -> f32 {
    if size <= 32.0 { ret 5.0 }
    ret 6.0
}
