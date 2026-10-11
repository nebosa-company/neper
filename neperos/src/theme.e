// The system theme (C126): what Settings chose that every app follows -- dark or light ground, high
// contrast text, and the font size. It is one small word. The kernel puts it in the last argument of
// every full-screen app it launches (one letter, 'a' + the low four bits), `appkit.open` reads it, and
// the palette functions of ui.e and the apps' own copies, the ground fills and `text.lay_out` ask here.
//
// The word: bits 0-1 font size (0 small, 1 default, 2 large), bit 2 dark, bit 3 high contrast, bit 4 set
// (so 0 is "none given"). The shell holds the word and hands it to each app it launches; the Settings
// app returns it as its exit code.
// ponytail: the word reaches an app when it starts, so a change shows in apps opened after it (and at
// once in Settings); an app already open keeps its look until it is left.
use e.gfx.paint

const SET: usize = 16usize
const DARK_BIT: usize = 4usize
const CONTRAST_BIT: usize = 8usize
const DEFAULT: usize = 21usize

var word: usize = 21usize

fn set(value: usize) {
    if value >= SET && value < 32usize { word = value }
}

// The one-letter argument the kernel hands an app, or any other string, which is ignored.
fn from_arg(arg: str) {
    if arg.len == 1usize && arg[0usize] >= 97u8 && arg[0usize] < 113u8 {
        set(SET + usize(arg[0usize]) - 97usize)
    }
}

fn word_of(dark: usize, contrast: usize, font: usize) -> usize {
    var value = SET + font
    if dark != 0usize { value += DARK_BIT }
    if contrast != 0usize { value += CONTRAST_BIT }
    ret value
}

// The word for the bytes Settings stored in /settings (settings.e's numbering: Dark theme 5, Font size 8, High
// contrast text 21; one byte per value, 40 values), or 0 when the file is not one: another length, or a value
// past 10.
fn stored_word(raw: []const u8) -> usize {
    if raw.len != 40usize { ret 0usize }
    var i = 0usize
    while i < raw.len {
        if raw[i] > 10u8 { ret 0usize }
        i += 1usize
    }
    ret word_of(usize(raw[5usize]), usize(raw[21usize]), usize(raw[8usize]))
}

fn is_dark() -> bool {
    ret (word & DARK_BIT) != 0usize
}

fn high_contrast() -> bool {
    ret (word & CONTRAST_BIT) != 0usize
}

fn font_scale() -> f32 {
    let step = word & 3usize
    if step == 0usize { ret 0.9 }
    if step == 2usize { ret 1.15 }
    ret 1.0
}

// Text on the ground: light on dark, dark on light.
fn light() -> paint.Color {
    if is_dark() {
        if high_contrast() { ret paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 } }
        ret paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 1.0 }
    }
    if high_contrast() { ret paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0 } }
    ret paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 }
}

fn light_muted() -> paint.Color {
    if high_contrast() { ret light() }
    if is_dark() { ret paint.Color { red: 0.72, green: 0.72, blue: 0.74, alpha: 1.0 } }
    ret paint.Color { red: 0.36, green: 0.35, blue: 0.34, alpha: 1.0 }
}

// Secondary text on the cream cards.
fn muted() -> paint.Color {
    if high_contrast() { ret paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0 } }
    ret paint.Color { red: 0.36, green: 0.35, blue: 0.34, alpha: 1.0 }
}

// An app's dark ground, or its light counterpart; a bright ground (the flashlight's glow) is left alone.
fn ground_color(red: f32, green: f32, blue: f32, alpha: f32) -> paint.Color {
    if is_dark() || red > 0.2 || green > 0.2 || blue > 0.2 {
        ret paint.Color { red: red, green: green, blue: blue, alpha: alpha }
    }
    ret paint.Color { red: 1.0 - red * 0.55, green: 1.0 - green * 0.55, blue: 1.0 - blue * 0.55, alpha: alpha }
}
