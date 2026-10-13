// Translate (D2232): the app behind the Translate icon, after Google Translate -- a From and a To language
// (six of them) with a swap button, a text box on the on-screen keyboard, a card with the translation, and
// a row of phrases to try. The language pickers list the six languages. Dark ground, cream cards and
// amber, like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on
// the bar at the bottom leaves the app.
// ponytail: there is no translation model and no network, so the translation is a SAMPLE phrase book of
// eight everyday phrases in six languages (English, Spanish, French, German, Italian, Portuguese): a text
// that is in the book comes out in the other language, anything else says it is not in the sample book.
// Real translation (an on-device model or a server on C117), more languages (including scripts the fonts
// do not cover yet), camera and voice input are queued as C137.
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text
use ui
use httpc
use vaultfs
use sysettings
use e.time

const NONE: usize = 99usize
const LANGS: usize = 8usize
const PHRASES: usize = 8usize
const MAIN_SCREEN: usize = 0usize
const PICK_SCREEN: usize = 1usize
const HISTORY_SCREEN: usize = 2usize
// (C167) The history keeps the last eight translations; a saved one stays when the list scrolls.
const HISTORY: usize = 8usize

type Entry = struct { src: [32]u8, src_len: usize, dst: [48]u8, dst_len: usize, from: usize, to: usize, saved: bool }

type State = struct {
    hist: [8]Entry,
    hist_total: usize,
    from: usize,
    to: usize,
    typed: ui.Field,
    // (C137) What the translation server answered for the last text it was asked: the text, the languages and the answer.
    remote_src: [64]u8,
    remote_src_len: usize,
    remote_from: usize,
    remote_to: usize,
    remote: [96]u8,
    remote_len: usize,
    screen: usize,
    picking_to: bool,
    hits: ui.Hits,
}

fn lang_name(index: usize) -> str {
    if index == 0usize { ret "English" }
    if index == 1usize { ret "Spanish" }
    if index == 2usize { ret "French" }
    if index == 3usize { ret "German" }
    if index == 4usize { ret "Italian" }
    if index == 5usize { ret "Portuguese" }
    if index == 6usize { ret "Russian" }
    ret "Greek"
}

// Phrase `p` of the book in language `lang`.
fn phrase(lang: usize, p: usize) -> str {
    if lang == 0usize {
        if p == 0usize { ret "hello" }
        if p == 1usize { ret "good morning" }
        if p == 2usize { ret "thank you" }
        if p == 3usize { ret "how are you" }
        if p == 4usize { ret "where is the library" }
        if p == 5usize { ret "i would like a coffee" }
        if p == 6usize { ret "see you tomorrow" }
        ret "good night"
    }
    if lang == 1usize {
        if p == 0usize { ret "hola" }
        if p == 1usize { ret "buenos d\xC3\xADas" }
        if p == 2usize { ret "gracias" }
        if p == 3usize { ret "c\xC3\xB3mo est\xC3\xA1s" }
        if p == 4usize { ret "d\xC3\xB3nde est\xC3\xA1 la biblioteca" }
        if p == 5usize { ret "quisiera un caf\xC3\xA9" }
        if p == 6usize { ret "hasta ma\xC3\xB1ana" }
        ret "buenas noches"
    }
    if lang == 2usize {
        if p == 0usize { ret "bonjour" }
        if p == 1usize { ret "bon matin" }
        if p == 2usize { ret "merci" }
        if p == 3usize { ret "comment allez-vous" }
        if p == 4usize { ret "o\xC3\xB9 est la biblioth\xC3\xA8que" }
        if p == 5usize { ret "je voudrais un caf\xC3\xA9" }
        if p == 6usize { ret "\xC3\xA0 demain" }
        ret "bonne nuit"
    }
    if lang == 3usize {
        if p == 0usize { ret "hallo" }
        if p == 1usize { ret "guten morgen" }
        if p == 2usize { ret "danke" }
        if p == 3usize { ret "wie geht es dir" }
        if p == 4usize { ret "wo ist die bibliothek" }
        if p == 5usize { ret "ich m\xC3\xB6chte einen kaffee" }
        if p == 6usize { ret "bis morgen" }
        ret "gute nacht"
    }
    if lang == 4usize {
        if p == 0usize { ret "ciao" }
        if p == 1usize { ret "buongiorno" }
        if p == 2usize { ret "grazie" }
        if p == 3usize { ret "come stai" }
        if p == 4usize { ret "dov'\xC3\xA8 la biblioteca" }
        if p == 5usize { ret "vorrei un caff\xC3\xA8" }
        if p == 6usize { ret "a domani" }
        ret "buonanotte"
    }
    if lang == 6usize {
        if p == 0usize { ret "\xD0\xBF\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82" }
        if p == 1usize { ret "\xD0\xB4\xD0\xBE\xD0\xB1\xD1\x80\xD0\xBE\xD0\xB5 \xD1\x83\xD1\x82\xD1\x80\xD0\xBE" }
        if p == 2usize { ret "\xD1\x81\xD0\xBF\xD0\xB0\xD1\x81\xD0\xB8\xD0\xB1\xD0\xBE" }
        if p == 3usize { ret "\xD0\xBA\xD0\xB0\xD0\xBA \xD0\xB4\xD0\xB5\xD0\xBB\xD0\xB0" }
        if p == 4usize { ret "\xD0\xB3\xD0\xB4\xD0\xB5 \xD0\xB1\xD0\xB8\xD0\xB1\xD0\xBB\xD0\xB8\xD0\xBE\xD1\x82\xD0\xB5\xD0\xBA\xD0\xB0" }
        if p == 5usize { ret "\xD1\x8F \xD1\x85\xD0\xBE\xD1\x82\xD0\xB5\xD0\xBB \xD0\xB1\xD1\x8B \xD0\xBA\xD0\xBE\xD1\x84\xD0\xB5" }
        if p == 6usize { ret "\xD1\x83\xD0\xB2\xD0\xB8\xD0\xB4\xD0\xB8\xD0\xBC\xD1\x81\xD1\x8F \xD0\xB7\xD0\xB0\xD0\xB2\xD1\x82\xD1\x80\xD0\xB0" }
        ret "\xD1\x81\xD0\xBF\xD0\xBE\xD0\xBA\xD0\xBE\xD0\xB9\xD0\xBD\xD0\xBE\xD0\xB9 \xD0\xBD\xD0\xBE\xD1\x87\xD0\xB8"
    }
    if lang == 7usize {
        if p == 0usize { ret "\xCE\xB3\xCE\xB5\xCE\xB9\xCE\xB1 \xCF\x83\xCE\xBF\xCF\x85" }
        if p == 1usize { ret "\xCE\xBA\xCE\xB1\xCE\xBB\xCE\xB7\xCE\xBC\xCE\xAD\xCF\x81\xCE\xB1" }
        if p == 2usize { ret "\xCE\xB5\xCF\x85\xCF\x87\xCE\xB1\xCF\x81\xCE\xB9\xCF\x83\xCF\x84\xCF\x8E" }
        if p == 3usize { ret "\xCF\x84\xCE\xB9 \xCE\xBA\xCE\xAC\xCE\xBD\xCE\xB5\xCE\xB9\xCF\x82" }
        if p == 4usize { ret "\xCF\x80\xCE\xBF\xCF\x8D \xCE\xB5\xCE\xAF\xCE\xBD\xCE\xB1\xCE\xB9 \xCE\xB7 \xCE\xB2\xCE\xB9\xCE\xB2\xCE\xBB\xCE\xB9\xCE\xBF\xCE\xB8\xCE\xAE\xCE\xBA\xCE\xB7" }
        if p == 5usize { ret "\xCE\xB8\xCE\xB1 \xCE\xAE\xCE\xB8\xCE\xB5\xCE\xBB\xCE\xB1 \xCE\xAD\xCE\xBD\xCE\xB1\xCE\xBD \xCE\xBA\xCE\xB1\xCF\x86\xCE\xAD" }
        if p == 6usize { ret "\xCF\x84\xCE\xB1 \xCE\xBB\xCE\xAD\xCE\xBC\xCE\xB5 \xCE\xB1\xCF\x8D\xCF\x81\xCE\xB9\xCE\xBF" }
        ret "\xCE\xBA\xCE\xB1\xCE\xBB\xCE\xB7\xCE\xBD\xCF\x8D\xCF\x87\xCF\x84\xCE\xB1"
    }
    if p == 0usize { ret "ol\xC3\xA1" }
    if p == 1usize { ret "bom dia" }
    if p == 2usize { ret "obrigado" }
    if p == 3usize { ret "como est\xC3\xA1" }
    if p == 4usize { ret "onde fica a biblioteca" }
    if p == 5usize { ret "eu gostaria de um caf\xC3\xA9" }
    if p == 6usize { ret "at\xC3\xA9 amanh\xC3\xA3" }
    ret "boa noite"
}

// Lower case ASCII, for comparing what was typed with the book.
fn lowered(a: *mem.Arena, value: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, value.len + 1usize)
    if buffer_error != ok { ret value }
    var i = 0usize
    while i < value.len {
        var c = value[i]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        buffer[i] = c
        i += 1usize
    }
    ret buffer[0usize..value.len]
}

// The code the translation server knows a language by.
fn lang_code(index: usize) -> str {
    if index == 0usize { ret "en" }
    if index == 1usize { ret "es" }
    if index == 2usize { ret "fr" }
    if index == 3usize { ret "de" }
    if index == 4usize { ret "it" }
    if index == 5usize { ret "pt" }
    if index == 6usize { ret "ru" }
    ret "el"
}

// Ask the server to translate the typed text (spaces as %20; only letters and spaces are sent): true when it did.
fn ask_server(a: *mem.Arena, s: *State) -> bool {
    let value = lowered(a, ui.field_text(a, &s.typed))
    if value.len == 0usize || value.len > 60usize { ret false }
    var path: [160]u8 = zero
    var n = 0usize
    let head = ui.join(a, ui.join(a, "/translate?from=", lang_code(s.from), "&to="), lang_code(s.to), "&q=")
    var i = 0usize
    while i < head.len {
        path[n] = head[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < value.len && n + 3usize < 160usize {
        let c = value[i]
        if c == 32u8 {
            path[n] = 37u8
            path[n + 1usize] = 50u8
            path[n + 2usize] = 48u8
            n += 3usize
        } else if c >= 97u8 && c <= 122u8 {
            path[n] = c
            n += 1usize
        }
        i += 1usize
    }
    let (reply, get_error) = httpc.get(a, "neper.test", ui.text_of(a, path[0usize..], n), "")
    if get_error != ok || reply.status != 200usize { ret false }
    var k = 0usize
    while k < reply.body.len && k < 96usize {
        s.remote[k] = reply.body[k]
        k += 1usize
    }
    s.remote_len = k
    k = 0usize
    while k < value.len && k < 64usize {
        s.remote_src[k] = value[k]
        k += 1usize
    }
    s.remote_src_len = k
    s.remote_from = s.from
    s.remote_to = s.to
    ui.say("translate server ")
    say_safe(ui.text_of(a, s.remote[0usize..], s.remote_len))
    ui.say("\n")
    ret true
}

// The server's answer for the text now typed, when it was asked for exactly this text and these languages.
fn remote_answer(a: *mem.Arena, s: *State) -> str {
    let value = lowered(a, ui.field_text(a, &s.typed))
    if s.remote_len > 0usize && s.remote_from == s.from && s.remote_to == s.to && ui.same(value, ui.text_of(a, s.remote_src[0usize..], s.remote_src_len)) {
        ret ui.text_of(a, s.remote[0usize..], s.remote_len)
    }
    ret ""
}

// The serial log is ASCII (the harness decodes it as text): a text with bytes above 127 is logged as its length.
fn say_safe(value: str) {
    var plain = true
    var i = 0usize
    while i < value.len {
        if value[i] >= 128u8 { plain = false }
        i += 1usize
    }
    if plain {
        ui.say_text(value)
    } else {
        ui.say("(")
        ui.say_num(value.len)
        ui.say(" bytes)")
    }
}

// The phrase of the book that `value` is in language `lang`, or NONE.
fn find(a: *mem.Arena, lang: usize, value: str) -> usize {
    let probe = lowered(a, value)
    var p = 0usize
    while p < PHRASES {
        if ui.same(probe, phrase(lang, p)) { ret p }
        p += 1usize
    }
    ret NONE
}

// ----------------------------------------------------------------------------------------------
// (C167) The history and the saved phrases, kept in /translate: eight entries of 88 bytes (from, to, saved, the two
// lengths, then the text and its translation).
const ENTRY_BYTES: usize = 88usize

fn same_entry(e: *Entry, src: str, from: usize, to: usize) -> bool {
    if e.src_len != src.len || e.from != from || e.to != to { ret false }
    var i = 0usize
    while i < src.len {
        if e.src[i] != src[i] { ret false }
        i += 1usize
    }
    ret true
}

fn save_history(s: *State) {
    var raw: [704]u8 = zero
    var i = 0usize
    while i < s.hist_total {
        let at = i * ENTRY_BYTES
        raw[at] = u8(s.hist[i].from)
        raw[at + 1usize] = u8(s.hist[i].to)
        if s.hist[i].saved { raw[at + 2usize] = 1u8 }
        raw[at + 3usize] = u8(s.hist[i].src_len)
        raw[at + 4usize] = u8(s.hist[i].dst_len)
        var k = 0usize
        while k < s.hist[i].src_len {
            raw[at + 8usize + k] = s.hist[i].src[k]
            k += 1usize
        }
        k = 0usize
        while k < s.hist[i].dst_len {
            raw[at + 40usize + k] = s.hist[i].dst[k]
            k += 1usize
        }
        i += 1usize
    }
    let kept = vaultfs.write_big("/translate", mem.address_of(&raw[0usize]), s.hist_total * ENTRY_BYTES)
}

fn load_history(s: *State) -> usize {
    var raw: [704]u8 = zero
    let (got, found) = vaultfs.read_big("/translate", mem.address_of(&raw[0usize]), 704usize)
    if !found { ret 0usize }
    let count = got / ENTRY_BYTES
    var i = 0usize
    while i < count && i < HISTORY {
        let at = i * ENTRY_BYTES
        let src_len = usize(raw[at + 3usize])
        let dst_len = usize(raw[at + 4usize])
        if src_len <= 32usize && dst_len <= 48usize && usize(raw[at]) < LANGS && usize(raw[at + 1usize]) < LANGS {
            s.hist[i].from = usize(raw[at])
            s.hist[i].to = usize(raw[at + 1usize])
            s.hist[i].saved = raw[at + 2usize] != 0u8
            s.hist[i].src_len = src_len
            s.hist[i].dst_len = dst_len
            var k = 0usize
            while k < src_len {
                s.hist[i].src[k] = raw[at + 8usize + k]
                k += 1usize
            }
            k = 0usize
            while k < dst_len {
                s.hist[i].dst[k] = raw[at + 40usize + k]
                k += 1usize
            }
            s.hist_total += 1usize
        }
        i += 1usize
    }
    ret s.hist_total
}

// Put a translation first in the history (a repeat moves to the front and keeps its star); when the list is full the
// oldest entry that is not saved falls off (the last one when all are saved).
fn remember(s: *State, src: str, dst: str) {
    if src.len == 0usize || src.len > 32usize || dst.len == 0usize || dst.len > 48usize { ret }
    var found = HISTORY
    var i = 0usize
    while i < s.hist_total {
        if same_entry(&s.hist[i], src, s.from, s.to) { found = i }
        i += 1usize
    }
    var entry: Entry = zero
    var from_slot = 0usize
    if found < HISTORY {
        entry = s.hist[found]
        from_slot = found
    } else {
        var n = 0usize
        while n < src.len {
            entry.src[n] = src[n]
            n += 1usize
        }
        entry.src_len = src.len
        n = 0usize
        while n < dst.len {
            entry.dst[n] = dst[n]
            n += 1usize
        }
        entry.dst_len = dst.len
        entry.from = s.from
        entry.to = s.to
        entry.saved = false
        if s.hist_total < HISTORY {
            from_slot = s.hist_total
            s.hist_total += 1usize
        } else {
            from_slot = HISTORY - 1usize
            var j = HISTORY - 1usize
            var picked = false
            while j > 0usize && !picked {
                if !s.hist[j].saved {
                    from_slot = j
                    picked = true
                }
                j -= 1usize
            }
        }
    }
    var k = from_slot
    while k > 0usize {
        s.hist[k] = s.hist[k - 1usize]
        k -= 1usize
    }
    s.hist[0usize] = entry
    save_history(s)
}

// The translation shown for the text now typed: the phrase book's, else the server's answer for exactly this text.
fn current_output(a: *mem.Arena, s: *State) -> str {
    let value = ui.field_text(a, &s.typed)
    if value.len == 0usize { ret "" }
    let at = find(a, s.from, value)
    if at != NONE { ret phrase(s.to, at) }
    ret remote_answer(a, s)
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn swap_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M7 4L3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7' fill='none' stroke='currentColor' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn draw_main(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.pill(a, builder, &s.hits, faces, 100usize, 16.0, 24.0, 150.0, 44.0, lang_name(s.from), ui.cream(), 17.0)
    try ui.disc(a, builder, 206.0, 46.0, 22.0, ui.amber())
    try svg.draw(a, builder, swap_icon(), geometry.rect(194.0, 34.0, 24.0, 24.0), ui.ink())
    ui.hit(&s.hits, 102usize, 180.0, 24.0, 52.0, 44.0)
    try ui.pill(a, builder, &s.hits, faces, 101usize, 246.0, 24.0, 150.0, 44.0, lang_name(s.to), ui.cream(), 17.0)
    // The text box.
    let value = ui.field_text(a, &s.typed)
    try ui.card(a, builder, 16.0, 86.0, 380.0, 150.0, 20.0, ui.cream())
    if value.len == 0usize { try ui.put(a, builder, faces.jost, 20.0, "Type text", 32.0, 102.0, ui.muted()) } else {
        let (box, box_error) = ui.wrapped(a, builder, faces.jost, 22.0, value, 32.0, 100.0, 348.0, 3u32, ui.ink())
        if box_error != ok { ret box_error }
    }
    // The phrases to try.
    var chip = 0usize
    while chip < 3usize {
        var p = 0usize
        if chip == 1usize { p = 2usize }
        if chip == 2usize { p = 7usize }
        let label = phrase(s.from, p)
        try ui.pill(a, builder, &s.hits, faces, 200usize + p, 24.0 + f32(chip) * 118.0, 192.0, 112.0, 34.0, label, ui.soft(), 13.0)
        chip += 1usize
    }
    // The translation.
    try ui.card(a, builder, 16.0, 252.0, 380.0, 150.0, 20.0, paint.Color { red: 0.16, green: 0.17, blue: 0.20, alpha: 1.0 })
    try ui.put(a, builder, faces.grotesk, 12.0, lang_name(s.to), 32.0, 264.0, ui.light_muted())
    var out = current_output(a, s)
    if value.len > 0usize && out.len == 0usize { out = "Not in the phrase book: Done asks the server" }
    var tone = ui.amber()
    if out.len > 28usize { tone = ui.light_muted() }
    if out.len > 0usize {
        let (box, box_error) = ui.wrapped(a, builder, faces.jost, 24.0, out, 32.0, 290.0, 348.0, 3u32, tone)
        if box_error != ok { ret box_error }
    }
    // (C167) Save the pair (a star in the history), copy the translation, open the history.
    var starred = false
    if s.hist_total > 0usize && value.len > 0usize && same_entry(&s.hist[0usize], lowered(a, value), s.from, s.to) { starred = s.hist[0usize].saved }
    var save_label = "Save"
    if starred { save_label = "Saved" }
    try ui.pill(a, builder, &s.hits, faces, 400usize, 32.0, 364.0, 100.0, 30.0, save_label, ui.soft(), 14.0)
    try ui.pill(a, builder, &s.hits, faces, 401usize, 150.0, 364.0, 100.0, 30.0, "Copy", ui.soft(), 14.0)
    try ui.pill(a, builder, &s.hits, faces, 402usize, 268.0, 364.0, 112.0, 30.0, "History", ui.soft(), 14.0)
    try ui.keyboard(a, builder, &s.hits, faces, "Done")
    ret ok
}

// The history: newest first, the saved ones in amber; a tap loads the pair, a second tap on the loaded one stars it.
fn draw_history(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 28.0, "History", 24.0, 20.0, ui.light())
    if s.hist_total == 0usize {
        try ui.put(a, builder, faces.jost, 18.0, "Nothing translated yet", 24.0, 90.0, ui.light_muted())
    }
    var i = 0usize
    while i < s.hist_total {
        let y: f32 = 80.0 + f32(i) * 70.0
        var fill = ui.cream()
        if s.hist[i].saved { fill = ui.amber() }
        try ui.card(a, builder, 16.0, y, 380.0, 62.0, 16.0, fill)
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, lang_name(s.hist[i].from), " to ", lang_name(s.hist[i].to)), 32.0, y + 6.0, ui.muted())
        try ui.put(a, builder, faces.jost, 17.0, ui.text_of(a, s.hist[i].src[0usize..], s.hist[i].src_len), 32.0, y + 24.0, ui.ink())
        try ui.put_right(a, builder, faces.jost, 17.0, ui.text_of(a, s.hist[i].dst[0usize..], s.hist[i].dst_len), 380.0, y + 24.0, ui.ink())
        ui.hit(&s.hits, 500usize + i, 16.0, y, 380.0, 62.0)
        i += 1usize
    }
    try ui.pill(a, builder, &s.hits, faces, 410usize, 106.0, 800.0, 200.0, 56.0, "Back", ui.amber(), 20.0)
    ret ok
}

fn draw_pick(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var title = "Translate from"
    if s.picking_to { title = "Translate to" }
    try ui.put(a, builder, faces.jost_bold, 28.0, title, 24.0, 20.0, ui.light())
    var i = 0usize
    while i < LANGS {
        let y: f32 = 90.0 + f32(i) * 56.0
        var current = s.from
        if s.picking_to { current = s.to }
        var fill = ui.cream()
        if i == current { fill = ui.amber() }
        try ui.card(a, builder, 16.0, y, 380.0, 48.0, 14.0, fill)
        try ui.put(a, builder, faces.jost, 18.0, lang_name(i), 34.0, y + 12.0, ui.ink())
        ui.hit(&s.hits, 300usize + i, 16.0, y, 380.0, 48.0)
        i += 1usize
    }
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == MAIN_SCREEN { try draw_main(a, builder, s, faces) }
    if s.screen == PICK_SCREEN { try draw_pick(a, builder, s, faces) }
    if s.screen == HISTORY_SCREEN { try draw_history(a, builder, s, faces) }
    try ui.handle(a, builder)
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

fn report(a: *mem.Arena, s: *State) {
    let value = ui.field_text(a, &s.typed)
    let at = find(a, s.from, value)
    if at != NONE {
        ui.say("translate result ")
        say_safe(phrase(s.to, at))
        ui.say("\n")
        remember(s, phrase(s.from, at), phrase(s.to, at))
    }
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == HISTORY_SCREEN {
        if id == 410usize {
            s.screen = MAIN_SCREEN
            ret true
        }
        if id >= 500usize && id < 500usize + HISTORY {
            let n = id - 500usize
            if n < s.hist_total {
                // A tap on an entry loads it; a tap on the entry that is already loaded stars it.
                let current = lowered(a, ui.field_text(a, &s.typed))
                if same_entry(&s.hist[n], current, s.from, s.to) {
                    s.hist[n].saved = !s.hist[n].saved
                    save_history(s)
                    if s.hist[n].saved { ui.say("translate saved ") } else { ui.say("translate unsaved ") }
                    say_safe(ui.text_of(a, s.hist[n].dst[0usize..], s.hist[n].dst_len))
                    ui.say("\n")
                } else {
                    s.from = s.hist[n].from
                    s.to = s.hist[n].to
                    s.typed.len = 0usize
                    var k = 0usize
                    while k < s.hist[n].src_len {
                        ui.field_type(&s.typed, s.hist[n].src[k], false)
                        k += 1usize
                    }
                    ui.say("translate loaded ")
                    say_safe(ui.text_of(a, s.hist[n].src[0usize..], s.hist[n].src_len))
                    ui.say("\n")
                }
                s.screen = MAIN_SCREEN
                ret true
            }
        }
        ret false
    }
    if s.screen == PICK_SCREEN {
        if id >= 300usize && id < 300usize + LANGS {
            if s.picking_to {
                s.to = id - 300usize
                ui.say("translate to ")
                ui.say(lang_name(s.to))
                ui.say("\n")
            } else {
                s.from = id - 300usize
                ui.say("translate from ")
                ui.say(lang_name(s.from))
                ui.say("\n")
            }
            s.screen = MAIN_SCREEN
            report(a, s)
            ret true
        }
        ret false
    }
    if ui.is_key(id) {
        if id == 1205usize {
            // Done: a text the book does not have goes to the translation server.
            if s.typed.len > 0usize && find(a, s.from, ui.field_text(a, &s.typed)) == NONE {
                let asked = ask_server(a, s)
                if asked { remember(s, lowered(a, ui.field_text(a, &s.typed)), ui.text_of(a, s.remote[0usize..], s.remote_len)) }
            }
            ret true
        }
        let changed = ui.field_key(&s.typed, id, false)
        if changed { report(a, s) }
        ret changed
    }
    if id == 400usize {
        // Save: the pair on show is starred in the history (a second tap takes the star off).
        let value = lowered(a, ui.field_text(a, &s.typed))
        if s.hist_total > 0usize && same_entry(&s.hist[0usize], value, s.from, s.to) {
            s.hist[0usize].saved = !s.hist[0usize].saved
            save_history(s)
            if s.hist[0usize].saved { ui.say("translate saved ") } else { ui.say("translate unsaved ") }
            say_safe(ui.text_of(a, s.hist[0usize].dst[0usize..], s.hist[0usize].dst_len))
            ui.say("\n")
            ret true
        }
        ret false
    }
    if id == 401usize {
        // Copy: the translation goes to the system clipboard (owner 5), which clears itself after the time Settings sets.
        let words = current_output(a, s)
        if words.len == 0usize { ret false }
        let (wall, wall_error) = time.now()
        var now_s = 0usize
        if wall_error == ok { now_s = usize(wall.nanos / 1000000000i64) }
        let taken = sysettings.clip_set(5usize, now_s, words)
        ui.say("translate copied ")
        ui.say_num(words.len)
        ui.say("\n")
        ret false
    }
    if id == 402usize {
        s.screen = HISTORY_SCREEN
        ui.say("translate history ")
        ui.say_num(s.hist_total)
        ui.say("\n")
        ret true
    }
    if id == 100usize {
        s.picking_to = false
        s.screen = PICK_SCREEN
        ret true
    }
    if id == 101usize {
        s.picking_to = true
        s.screen = PICK_SCREEN
        ret true
    }
    if id == 102usize {
        let t = s.from
        s.from = s.to
        s.to = t
        s.typed.len = 0usize
        ui.say("translate swap\n")
        ret true
    }
    if id >= 200usize && id < 200usize + PHRASES {
        let p = id - 200usize
        s.typed.len = 0usize
        let words = phrase(s.from, p)
        var i = 0usize
        while i < words.len {
            ui.field_type(&s.typed, words[i], false)
            i += 1usize
        }
        ui.say("translate phrase ")
        ui.say_text(phrase(0usize, p))
        ui.say("\n")
        report(a, s)
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "translate")
    if kit_error != ok {
        ui.say("translate open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("translate fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.from = 0usize
    s.to = 1usize
    let kept = load_history(&s)
    if kept > 0usize {
        ui.say("translate history loaded ")
        ui.say_num(kept)
        ui.say("\n")
    }
    if !show(a, &kit, &s) {
        ui.say("translate present failed\n")
        ret ok
    }
    ui.say("translate shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            ui.say("translate home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("translate present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
