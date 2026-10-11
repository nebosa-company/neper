// The system theme and the settings every part follows (C126): dark or light ground, high contrast
// text, the font size, the 24-hour clock, the brightness, the lock screen and Do Not Disturb. It is one
// small word. The kernel puts it in the argument after the fonts of every full-screen app it launches
// (three letters, 'a' + a nibble each), `appkit.open` reads it, and what draws asks here: the palette
// functions of ui.e and the apps' own copies, the ground fills, `text.lay_out`, the brightness layer of
// `appkit.present` and the shell's.
//
// The word: bits 0-1 font size (0 small, 1 default, 2 large), bit 2 dark, bit 3 high contrast, bit 4
// 24-hour clock, bits 5-8 brightness (0 to 10), bits 9-10 screen lock (0 none, 1 swipe, 2 PIN), bit 11
// Do Not Disturb, bit 12 set (so 0 is "none given"). The shell holds the word and hands it to each app
// it launches; the Settings app returns it as its exit code.
// ponytail: the word reaches an app when it starts, so a change shows in apps opened after it (and at
// once in Settings); an app already open keeps its look until it is left. Brightness is a dimming layer
// over what an app draws, against the level the system starts at (7): a screen has no backlight here.
use e.gfx.paint

const SET: usize = 4096usize
const DARK_BIT: usize = 4usize
const CONTRAST_BIT: usize = 8usize
const HOUR24_BIT: usize = 16usize
const DND_BIT: usize = 2048usize
// font 1, dark, 24-hour, brightness 7, PIN lock, not disturbing.
const DEFAULT: usize = 5365usize

var word: usize = 5365usize

fn set(value: usize) {
    if value >= SET && value < SET * 2usize { word = value }
}

// Whether `value` is a word.
fn valid(value: usize) -> bool {
    ret value >= SET && value < SET * 2usize
}

// The three-letter argument the kernel hands an app, or any other string, which is ignored.
fn from_arg(arg: str) {
    if arg.len == 3usize && arg[0usize] >= 97u8 && arg[0usize] < 113u8 && arg[1usize] >= 97u8 && arg[1usize] < 113u8 && arg[2usize] >= 97u8 && arg[2usize] < 113u8 {
        set(SET + (usize(arg[0usize]) - 97usize) + (usize(arg[1usize]) - 97usize) * 16usize + (usize(arg[2usize]) - 97usize) * 256usize)
    }
}

fn word_of(dark: usize, contrast: usize, font: usize, hour24: usize, brightness: usize, lock: usize, dnd: usize) -> usize {
    var value = SET + font
    if dark != 0usize { value += DARK_BIT }
    if contrast != 0usize { value += CONTRAST_BIT }
    if hour24 != 0usize { value += HOUR24_BIT }
    value += brightness * 32usize
    value += lock * 512usize
    if dnd != 0usize { value += DND_BIT }
    ret value
}

// The word for the bytes Settings stored in /settings (settings.e's numbering: Brightness 4, Dark theme 5, Font
// size 8, Do Not Disturb 12, Screen lock 19, 24-hour format 20, High contrast text 21; one byte per value, 40
// values), or 0 when the file is not one: another length, or a value past 10.
fn stored_word(raw: []const u8) -> usize {
    if raw.len != 40usize { ret 0usize }
    var i = 0usize
    while i < raw.len {
        if raw[i] > 10u8 { ret 0usize }
        i += 1usize
    }
    var font = usize(raw[8usize])
    if font > 2usize { font = 1usize }
    var lock = usize(raw[19usize])
    if lock > 2usize { lock = 2usize }
    ret word_of(usize(raw[5usize]), usize(raw[21usize]), font, usize(raw[20usize]), usize(raw[4usize]), lock, usize(raw[12usize]))
}

// A setting's value before anything was chosen (settings.e's numbering); the Settings app, the settings server
// and Reset all start from here.
fn default_value(index: usize) -> usize {
    if index == 0usize || index == 1usize || index == 6usize || index == 7usize || index == 8usize { ret 1usize }
    if index == 4usize { ret 7usize }
    if index == 5usize { ret 1usize }
    if index == 9usize { ret 6usize }
    if index == 10usize { ret 8usize }
    if index == 11usize { ret 7usize }
    if index == 13usize || index == 15usize || index == 16usize || index == 17usize || index == 18usize { ret 1usize }
    if index == 19usize { ret 2usize }
    if index == 20usize || index == 24usize || index == 25usize { ret 1usize }
    // The notification switches, one per app (Stocks is off).
    if index >= 26usize && index < 34usize {
        if index == 31usize { ret 0usize }
        ret 1usize
    }
    ret 0usize
}

fn is_dark() -> bool {
    ret (word & DARK_BIT) != 0usize
}

fn high_contrast() -> bool {
    ret (word & CONTRAST_BIT) != 0usize
}

fn is_24h() -> bool {
    ret (word & HOUR24_BIT) != 0usize
}

fn do_not_disturb() -> bool {
    ret (word & DND_BIT) != 0usize
}

// 0 none, 1 swipe, 2 PIN.
fn screen_lock() -> usize {
    ret (word >> 9usize) & 3usize
}

fn brightness_step() -> usize {
    ret (word >> 5usize) & 15usize
}

// How much black goes over the screen: nothing at the level the system starts at (7) or above, and 0.07 more
// for each step below it, to 0.49 at step 0.
fn dim_alpha() -> f32 {
    let step = brightness_step()
    if step >= 7usize { ret 0.0 }
    ret f32(7usize - step) * 0.07
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
