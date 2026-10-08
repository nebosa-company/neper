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

const NONE: usize = 99usize
const LANGS: usize = 6usize
const PHRASES: usize = 8usize
const MAIN_SCREEN: usize = 0usize
const PICK_SCREEN: usize = 1usize

type State = struct {
    from: usize,
    to: usize,
    typed: ui.Field,
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
    ret "Portuguese"
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
    var out = ""
    if value.len > 0usize {
        let at = find(a, s.from, value)
        if at != NONE { out = phrase(s.to, at) } else { out = "Not in the sample phrase book" }
    }
    var tone = ui.amber()
    if out.len > 28usize { tone = ui.light_muted() }
    if out.len > 0usize {
        let (box, box_error) = ui.wrapped(a, builder, faces.jost, 24.0, out, 32.0, 290.0, 348.0, 3u32, tone)
        if box_error != ok { ret box_error }
    }
    try ui.keyboard(a, builder, &s.hits, faces, "Done")
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
    if s.screen == MAIN_SCREEN { try draw_main(a, builder, s, faces) } else { try draw_pick(a, builder, s, faces) }
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
        ui.say_text(phrase(s.to, at))
        ui.say("\n")
    }
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
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
        if id == 1205usize { ret true }
        let changed = ui.field_key(&s.typed, id, false)
        if changed { report(a, s) }
        ret changed
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
