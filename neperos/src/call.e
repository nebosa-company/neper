// Call (D2222): the app behind the Phone icon, after the Pixel's phone -- a keypad with the number being
// dialled, a green call button and a delete key; Recents (outgoing, incoming and missed calls with how
// long ago); Contacts (an alphabetical list with a round initial, and a card with Call and Message); and
// the call screen (the name, "Calling...", then a timer, with Mute, Keypad, Speaker, Add call, Hold and
// a red End button). Dark ground, cream rows and amber, like the other apps (appkit.e, taps from the
// compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
// ponytail: there is no modem and no network, so a call is a DEMO: it "connects" after a second and the
// timer counts the input server's 500 ms ticks; a dialled number is matched against the sample contacts;
// the contacts and the recents live in this process. A real telephony stack, the contact store, voicemail
// and the in-call audio are queued as C127.
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use e.fmt.vcard as vcard
use appkit
use text
use ui
use vaultfs

const NONE: usize = 99usize
const KEYPAD_TAB: usize = 0usize
const RECENTS_TAB: usize = 1usize
const CONTACTS_TAB: usize = 2usize
const MAIN_SCREEN: usize = 0usize
const CONTACT_SCREEN: usize = 1usize
const CALL_SCREEN: usize = 2usize
const FORM_SCREEN: usize = 3usize
const MAX_CONTACTS: usize = 10usize
const MAX_RECENTS: usize = 16usize

type Contact = struct { name: [20]u8, name_len: usize, number: [12]u8, number_len: usize }

type Recent = struct { contact: usize, number: [12]u8, number_len: usize, direction: usize, ago: usize, used: bool }

type State = struct {
    contacts: [10]Contact,
    contact_total: usize,
    recents: [16]Recent,
    recent_total: usize,
    tab: usize,
    screen: usize,
    dial: ui.Field,
    open: usize,
    // (C127) The contact form: the name and the number being typed, the one in focus, and the contact being
    // edited (NONE for a new one).
    form_name: ui.Field,
    form_number: ui.Field,
    form_focus: usize,
    form_edit: usize,
    // The call: who (a contact or NONE) and the number dialled, the ticks since it began, the switches.
    callee: usize,
    number: [12]u8,
    number_len: usize,
    ticks: usize,
    muted: bool,
    speaker: bool,
    hits: ui.Hits,
}

fn add_contact(s: *State, name: str, number: str) {
    if s.contact_total >= MAX_CONTACTS { ret }
    var c: Contact = zero
    var i = 0usize
    while i < name.len && i < 20usize {
        c.name[i] = name[i]
        i += 1usize
    }
    c.name_len = i
    i = 0usize
    while i < number.len && i < 12usize {
        c.number[i] = number[i]
        i += 1usize
    }
    c.number_len = i
    s.contacts[s.contact_total] = c
    s.contact_total += 1usize
}

fn contact_name(a: *mem.Arena, s: *State, index: usize) -> str {
    ret ui.text_of(a, s.contacts[index].name[0usize..], s.contacts[index].name_len)
}

fn contact_number(a: *mem.Arena, s: *State, index: usize) -> str {
    ret ui.text_of(a, s.contacts[index].number[0usize..], s.contacts[index].number_len)
}

// The contact whose number is `digits`, or NONE.
// (C127) The contacts are kept in /contacts.vcf as vCards (the format Messages, Mail and Wallet can share): the
// display name and the number as a TEL.
fn save_contacts(a: *mem.Arena, s: *State) {
    var cards: [10]vcard.Card = zero
    var i = 0usize
    while i < s.contact_total {
        cards[i].name = contact_name(a, s, i)
        cards[i].family = ""
        cards[i].given = ""
        cards[i].org = ""
        cards[i].note = ""
        cards[i].tel[0usize] = contact_number(a, s, i)
        cards[i].tel_type[0usize] = "cell"
        cards[i].tel_count = 1usize
        i += 1usize
    }
    var buf: [4096]u8 = zero
    let (len, write_error) = vcard.write(cards[0usize..s.contact_total], buf[0usize..4096usize])
    if write_error != ok { ret }
    let kept = vaultfs.write_big("/contacts.vcf", mem.address_of(&buf[0usize]), len)
}

// The contacts kept, if there are any (false leaves the list as it is).
fn load_contacts(a: *mem.Arena, s: *State) -> bool {
    var buf: [4096]u8 = zero
    let (n, found) = vaultfs.read_big("/contacts.vcf", mem.address_of(&buf[0usize]), 4096usize)
    if !found || n == 0usize { ret false }
    var cards: [10]vcard.Card = zero
    let (count, parse_error) = vcard.parse(a, buf[0usize..n], cards[0usize..10usize])
    if parse_error != ok || count == 0usize { ret false }
    s.contact_total = 0usize
    var i = 0usize
    while i < count {
        var number = ""
        if cards[i].tel_count > 0usize { number = cards[i].tel[0usize] }
        add_contact(s, cards[i].name, number)
        i += 1usize
    }
    ret true
}

fn find_contact(a: *mem.Arena, s: *State, digits: str) -> usize {
    var i = 0usize
    while i < s.contact_total {
        if ui.same(contact_number(a, s, i), digits) { ret i }
        i += 1usize
    }
    ret NONE
}

fn add_recent(s: *State, contact: usize, number: str, direction: usize, ago: usize) {
    // The newest first: everything moves down one.
    var k = MAX_RECENTS - 1usize
    while k > 0usize {
        s.recents[k] = s.recents[k - 1usize]
        k -= 1usize
    }
    var r: Recent = zero
    var i = 0usize
    while i < number.len && i < 12usize {
        r.number[i] = number[i]
        i += 1usize
    }
    r.number_len = i
    r.contact = contact
    r.direction = direction
    r.ago = ago
    r.used = true
    s.recents[0usize] = r
    if s.recent_total < MAX_RECENTS { s.recent_total += 1usize }
}

fn recent_number(a: *mem.Arena, r: Recent) -> str {
    ret ui.text_of(a, r.number[0usize..], r.number_len)
}

fn ago_text(a: *mem.Arena, ago: usize) -> str {
    if ago < 1usize { ret "Just now" }
    if ago < 60usize { ret ui.join(a, ui.number(a, ago), " min ago", "") }
    if ago < 1440usize { ret ui.join(a, ui.number(a, ago / 60usize), " hr ago", "") }
    if ago < 2880usize { ret "Yesterday" }
    ret ui.join(a, ui.number(a, ago / 1440usize), " days ago", "")
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn phone_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M6.6 10.8c1.4 2.8 3.8 5.1 6.6 6.6l2.2-2.2c.3-.3.7-.4 1-.2 1.1.4 2.3.6 3.6.6.6 0 1 .4 1 1V20c0 .6-.4 1-1 1C10.6 21 3 13.4 3 4c0-.6.4-1 1-1h3.5c.6 0 1 .4 1 1 0 1.3.2 2.5.6 3.6.1.3 0 .7-.2 1z' fill='currentColor'/></svg>"
}

fn arrow_icon(direction: usize) -> str {
    if direction == 0usize { ret "<svg viewBox='0 0 24 24'><path d='M7 17L17 7M9 7h8v8' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M17 7L7 17M7 9v8h8' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn avatar(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, cx: f32, cy: f32, radius: f32, name: str, index: usize) -> err {
    try ui.disc(a, builder, cx, cy, radius, ui.tint(index))
    if name.len > 0usize {
        let (one, one_error) = mem.alloc[u8](a, 1usize)
        if one_error != ok { ret one_error }
        one[0usize] = name[0usize]
        try ui.centred(a, builder, faces.jost_bold, radius * 0.95, one[0usize..1usize], cx, cy - radius * 0.62, ui.ink())
    }
    ret ok
}

fn digit_label(k: usize) -> str {
    if k < 9usize { ret ui.number_label(k + 1usize) }
    if k == 9usize { ret "*" }
    if k == 10usize { ret "0" }
    ret "#"
}

fn letters_under(k: usize) -> str {
    if k == 1usize { ret "ABC" }
    if k == 2usize { ret "DEF" }
    if k == 3usize { ret "GHI" }
    if k == 4usize { ret "JKL" }
    if k == 5usize { ret "MNO" }
    if k == 6usize { ret "PQRS" }
    if k == 7usize { ret "TUV" }
    if k == 8usize { ret "WXYZ" }
    ret ""
}

fn draw_tabs(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 0.0, 828.0, 412.0, 68.0, 0.0, paint.Color { red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0 })
    var tab = 0usize
    while tab < 3usize {
        var label = "Keypad"
        if tab == 1usize { label = "Recents" }
        if tab == 2usize { label = "Contacts" }
        var tone = ui.light_muted()
        if tab == s.tab { tone = ui.amber() }
        let cx: f32 = 68.0 + f32(tab) * 138.0
        try ui.disc(a, builder, cx, 848.0, 6.0, tone)
        try ui.centred(a, builder, faces.jost, 14.0, label, cx, 862.0, tone)
        ui.hit(&s.hits, 300usize + tab, cx - 68.0, 828.0, 136.0, 68.0)
        tab += 1usize
    }
    ret ok
}

fn draw_keypad(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let typed = ui.field_text(a, &s.dial)
    try ui.centred(a, builder, faces.jost_bold, 36.0, typed, 206.0, 90.0, ui.light())
    if typed.len == 0usize { try ui.centred(a, builder, faces.grotesk, 13.0, "Enter a number", 206.0, 140.0, ui.light_muted()) }
    var k = 0usize
    while k < 12usize {
        let col = k % 3usize
        let row = k / 3usize
        let cx: f32 = 82.0 + f32(col) * 124.0
        let cy: f32 = 236.0 + f32(row) * 90.0
        try ui.disc(a, builder, cx, cy, 36.0, paint.Color { red: 0.17, green: 0.18, blue: 0.21, alpha: 1.0 })
        try ui.centred(a, builder, faces.jost, 30.0, digit_label(k), cx, cy - 22.0, ui.light())
        if letters_under(k).len > 0usize { try ui.centred(a, builder, faces.grotesk, 10.0, letters_under(k), cx, cy + 10.0, ui.light_muted()) }
        ui.hit(&s.hits, 100usize + k, cx - 38.0, cy - 38.0, 76.0, 76.0)
        k += 1usize
    }
    try ui.disc(a, builder, 206.0, 640.0, 36.0, paint.Color { red: 0.30, green: 0.70, blue: 0.40, alpha: 1.0 })
    try svg.draw(a, builder, phone_icon(), geometry.rect(190.0, 624.0, 32.0, 32.0), ui.cream())
    ui.hit(&s.hits, 121usize, 168.0, 602.0, 76.0, 76.0)
    if s.dial.len > 0usize {
        try ui.put(a, builder, faces.jost, 16.0, "Delete", 322.0, 630.0, ui.light_muted())
        ui.hit(&s.hits, 120usize, 300.0, 610.0, 90.0, 60.0)
    }
    ret ok
}

fn draw_recents(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 30.0, "Recents", 20.0, 22.0, ui.light())
    var i = 0usize
    while i < s.recent_total && i < 10usize {
        let r = s.recents[i]
        let y: f32 = 84.0 + f32(i) * 70.0
        var name = recent_number(a, r)
        if r.contact != NONE { name = contact_name(a, s, r.contact) }
        try ui.card(a, builder, 16.0, y + 2.0, 380.0, 64.0, 18.0, ui.cream())
        try avatar(a, builder, faces, 50.0, y + 34.0, 20.0, name, i)
        var name_color = ui.ink()
        if r.direction == 2usize { name_color = ui.loss() }
        try ui.clipped(a, builder, faces.jost, 18.0, name, 84.0, y + 10.0, 230.0, name_color)
        var how = "Outgoing"
        if r.direction == 1usize { how = "Incoming" }
        if r.direction == 2usize { how = "Missed" }
        try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, how, ", ", ago_text(a, r.ago)), 84.0, y + 38.0, ui.muted())
        var tone = ui.muted()
        if r.direction == 2usize { tone = ui.loss() }
        try svg.draw(a, builder, arrow_icon(r.direction), geometry.rect(346.0, y + 22.0, 24.0, 24.0), tone)
        ui.hit(&s.hits, 400usize + i, 16.0, y + 2.0, 380.0, 64.0)
        i += 1usize
    }
    ret ok
}

fn draw_contacts(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 30.0, "Contacts", 20.0, 22.0, ui.light())
    try ui.pill(a, builder, &s.hits, faces, 520usize, 300.0, 24.0, 96.0, 36.0, "New", ui.amber(), 15.0)
    var i = 0usize
    while i < s.contact_total {
        let y: f32 = 84.0 + f32(i) * 70.0
        try ui.card(a, builder, 16.0, y + 2.0, 380.0, 64.0, 18.0, ui.cream())
        try avatar(a, builder, faces, 50.0, y + 34.0, 20.0, contact_name(a, s, i), i)
        try ui.put(a, builder, faces.jost, 18.0, contact_name(a, s, i), 84.0, y + 10.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 13.0, contact_number(a, s, i), 84.0, y + 38.0, ui.muted())
        ui.hit(&s.hits, 500usize + i, 16.0, y + 2.0, 380.0, 64.0)
        i += 1usize
    }
    ret ok
}

fn draw_contact(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 600usize, 0.0, 10.0, 66.0, 56.0)
    try avatar(a, builder, faces, 206.0, 160.0, 56.0, contact_name(a, s, s.open), s.open)
    try ui.centred(a, builder, faces.jost_bold, 30.0, contact_name(a, s, s.open), 206.0, 236.0, ui.light())
    try ui.centred(a, builder, faces.grotesk, 15.0, contact_number(a, s, s.open), 206.0, 282.0, ui.light_muted())
    try ui.pill(a, builder, &s.hits, faces, 601usize, 56.0, 340.0, 140.0, 52.0, "Call", ui.amber(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 602usize, 232.0, 340.0, 140.0, 52.0, "Message", ui.soft(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 603usize, 56.0, 416.0, 140.0, 44.0, "Edit", ui.soft(), 16.0)
    try ui.pill(a, builder, &s.hits, faces, 604usize, 232.0, 416.0, 140.0, 44.0, "Delete", ui.soft(), 16.0)
    ret ok
}

// The contact form: a name and a number on the on-screen keyboard.
fn draw_form(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 800usize, 0.0, 10.0, 66.0, 56.0)
    var title = "New contact"
    if s.form_edit != NONE { title = "Edit contact" }
    try ui.put(a, builder, faces.jost_bold, 24.0, title, 62.0, 20.0, ui.light())
    var label_tone = ui.light_muted()
    if s.form_focus == 0usize { label_tone = ui.amber() }
    try ui.put(a, builder, faces.grotesk, 12.0, "Name", 20.0, 74.0, label_tone)
    try ui.card(a, builder, 16.0, 92.0, 380.0, 50.0, 14.0, ui.cream())
    try ui.put(a, builder, faces.jost, 20.0, ui.field_text(a, &s.form_name), 30.0, 104.0, ui.ink())
    ui.hit(&s.hits, 810usize, 16.0, 92.0, 380.0, 50.0)
    label_tone = ui.light_muted()
    if s.form_focus == 1usize { label_tone = ui.amber() }
    try ui.put(a, builder, faces.grotesk, 12.0, "Number", 20.0, 156.0, label_tone)
    try ui.card(a, builder, 16.0, 174.0, 380.0, 50.0, 14.0, ui.cream())
    try ui.put(a, builder, faces.jost, 20.0, ui.field_text(a, &s.form_number), 30.0, 186.0, ui.ink())
    ui.hit(&s.hits, 811usize, 16.0, 174.0, 380.0, 50.0)
    var enter = "Next"
    if s.form_focus == 1usize { enter = "Save" }
    try ui.keyboard(a, builder, &s.hits, faces, enter)
    ret ok
}

fn draw_call(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var name = ui.text_of(a, s.number[0usize..], s.number_len)
    if s.callee != NONE { name = contact_name(a, s, s.callee) }
    try avatar(a, builder, faces, 206.0, 150.0, 56.0, name, s.callee)
    try ui.centred(a, builder, faces.jost_bold, 30.0, name, 206.0, 226.0, ui.light())
    var status = "Calling..."
    if s.ticks >= 2usize { status = ui.join(a, ui.number(a, (s.ticks - 2usize) / 120usize), ":", ui.two(a, ((s.ticks - 2usize) / 2usize) % 60usize)) }
    try ui.centred(a, builder, faces.jost, 20.0, status, 206.0, 276.0, ui.light_muted())
    try ui.centred(a, builder, faces.grotesk, 12.0, "Demo call, no network yet", 206.0, 312.0, ui.light_muted())
    var row = 0usize
    while row < 2usize {
        var col = 0usize
        while col < 3usize {
            let n = row * 3usize + col
            var label = "Mute"
            if n == 1usize { label = "Keypad" }
            if n == 2usize { label = "Speaker" }
            if n == 3usize { label = "Add call" }
            if n == 4usize { label = "Hold" }
            if n == 5usize { label = "Record" }
            var fill = paint.Color { red: 0.17, green: 0.18, blue: 0.21, alpha: 1.0 }
            if n == 0usize && s.muted { fill = ui.amber() }
            if n == 2usize && s.speaker { fill = ui.amber() }
            let cx: f32 = 82.0 + f32(col) * 124.0
            let cy: f32 = 420.0 + f32(row) * 110.0
            try ui.disc(a, builder, cx, cy, 34.0, fill)
            var tone = ui.light()
            if fill.red > 0.5 { tone = ui.ink() }
            try ui.centred(a, builder, faces.grotesk, 13.0, label, cx, cy - 8.0, tone)
            ui.hit(&s.hits, 700usize + n, cx - 36.0, cy - 36.0, 72.0, 72.0)
            col += 1usize
        }
        row += 1usize
    }
    try ui.disc(a, builder, 206.0, 700.0, 38.0, paint.Color { red: 0.85, green: 0.25, blue: 0.22, alpha: 1.0 })
    try svg.draw(a, builder, phone_icon(), geometry.rect(190.0, 684.0, 32.0, 32.0), ui.cream())
    ui.hit(&s.hits, 710usize, 166.0, 660.0, 80.0, 80.0)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == CALL_SCREEN {
        try draw_call(a, builder, s, faces)
    } else if s.screen == CONTACT_SCREEN {
        try draw_contact(a, builder, s, faces)
    } else if s.screen == FORM_SCREEN {
        try draw_form(a, builder, s, faces)
    } else {
        if s.tab == KEYPAD_TAB { try draw_keypad(a, builder, s, faces) }
        if s.tab == RECENTS_TAB { try draw_recents(a, builder, s, faces) }
        if s.tab == CONTACTS_TAB { try draw_contacts(a, builder, s, faces) }
        try draw_tabs(a, builder, s, faces)
    }
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

fn start_call(a: *mem.Arena, s: *State, callee: usize, number: str) {
    s.callee = callee
    var i = 0usize
    while i < number.len && i < 12usize {
        s.number[i] = number[i]
        i += 1usize
    }
    s.number_len = i
    s.ticks = 0usize
    s.muted = false
    s.speaker = false
    s.screen = CALL_SCREEN
    ui.say("call dialed ")
    ui.say_text(number)
    ui.say("\n")
}

fn end_call(a: *mem.Arena, s: *State) {
    add_recent(s, s.callee, ui.text_of(a, s.number[0usize..], s.number_len), 0usize, 0usize)
    ui.say("call ended ")
    ui.say_num(s.ticks / 2usize)
    ui.say("s\n")
    s.screen = MAIN_SCREEN
    s.dial.len = 0usize
}

// What a tap on button `id` did: true when the screen changed.
// Save the form's contact (a new one or the edited one) and go back to the list. False when a field is empty.
fn save_form(a: *mem.Arena, s: *State) -> bool {
    if s.form_name.len == 0usize || s.form_number.len == 0usize { ret false }
    let name = ui.field_text(a, &s.form_name)
    let number = ui.field_text(a, &s.form_number)
    if s.form_edit == NONE {
        if s.contact_total >= MAX_CONTACTS { ret false }
        add_contact(s, name, number)
    } else {
        var c: Contact = zero
        var i = 0usize
        while i < name.len && i < 20usize {
            c.name[i] = name[i]
            i += 1usize
        }
        c.name_len = i
        i = 0usize
        while i < number.len && i < 12usize {
            c.number[i] = number[i]
            i += 1usize
        }
        c.number_len = i
        s.contacts[s.form_edit] = c
    }
    save_contacts(a, s)
    ui.say("call contact saved ")
    ui.say_text(name)
    ui.say("\n")
    s.screen = MAIN_SCREEN
    s.tab = CONTACTS_TAB
    ret true
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == FORM_SCREEN {
        if id == 800usize {
            s.screen = MAIN_SCREEN
            ret true
        }
        if id == 810usize {
            s.form_focus = 0usize
            ret true
        }
        if id == 811usize {
            s.form_focus = 1usize
            ret true
        }
        if id == 1205usize {
            if s.form_focus == 0usize {
                s.form_focus = 1usize
                ret true
            }
            ret save_form(a, s)
        }
        if ui.is_key(id) {
            if s.form_focus == 0usize {
                if s.form_name.len < 20usize || id == 1201usize { ret ui.field_key(&s.form_name, id, s.form_name.len == 0usize) }
            } else if s.form_number.len < 12usize || id == 1201usize {
                ret ui.field_key(&s.form_number, id, false)
            }
        }
        ret false
    }
    if s.screen == CALL_SCREEN {
        if id == 710usize {
            end_call(a, s)
            ret true
        }
        if id == 700usize {
            s.muted = !s.muted
            ret true
        }
        if id == 702usize {
            s.speaker = !s.speaker
            ret true
        }
        ret false
    }
    if s.screen == CONTACT_SCREEN {
        if id == 600usize {
            s.screen = MAIN_SCREEN
            ret true
        }
        if id == 601usize {
            start_call(a, s, s.open, contact_number(a, s, s.open))
            ret true
        }
        if id == 603usize {
            s.form_edit = s.open
            s.form_name.len = 0usize
            s.form_number.len = 0usize
            let name = contact_name(a, s, s.open)
            let number = contact_number(a, s, s.open)
            var i = 0usize
            while i < name.len {
                s.form_name.bytes[i] = name[i]
                i += 1usize
            }
            s.form_name.len = name.len
            i = 0usize
            while i < number.len {
                s.form_number.bytes[i] = number[i]
                i += 1usize
            }
            s.form_number.len = number.len
            s.form_focus = 0usize
            s.screen = FORM_SCREEN
            ret true
        }
        if id == 604usize {
            let name = contact_name(a, s, s.open)
            var k = s.open
            while k + 1usize < s.contact_total {
                s.contacts[k] = s.contacts[k + 1usize]
                k += 1usize
            }
            s.contact_total -= 1usize
            save_contacts(a, s)
            ui.say("call contact deleted ")
            ui.say_text(name)
            ui.say("\n")
            s.screen = MAIN_SCREEN
            ret true
        }
        ret false
    }
    if id >= 300usize && id < 303usize {
        s.tab = id - 300usize
        ui.say("call tab ")
        if s.tab == 0usize { ui.say("Keypad\n") }
        if s.tab == 1usize { ui.say("Recents\n") }
        if s.tab == 2usize { ui.say("Contacts\n") }
        ret true
    }
    if s.tab == KEYPAD_TAB {
        if id >= 100usize && id < 112usize {
            let k = id - 100usize
            var b = u8(49usize + k)
            if k == 9usize { b = 42u8 }
            if k == 10usize { b = 48u8 }
            if k == 11usize { b = 35u8 }
            if s.dial.len < 12usize { ui.field_type(&s.dial, b, false) }
            ret true
        }
        if id == 120usize {
            ui.field_back(&s.dial)
            ret true
        }
        if id == 121usize {
            if s.dial.len > 0usize {
                let number = ui.field_text(a, &s.dial)
                start_call(a, s, find_contact(a, s, number), number)
                ret true
            }
            ret false
        }
        ret false
    }
    if s.tab == RECENTS_TAB && id >= 400usize && id < 416usize {
        let r = s.recents[id - 400usize]
        if r.used { start_call(a, s, r.contact, recent_number(a, r)) }
        ret true
    }
    if s.tab == CONTACTS_TAB && id == 520usize {
        if s.contact_total >= MAX_CONTACTS { ret false }
        s.form_edit = NONE
        s.form_name.len = 0usize
        s.form_number.len = 0usize
        s.form_focus = 0usize
        s.screen = FORM_SCREEN
        ret true
    }
    if s.tab == CONTACTS_TAB && id >= 500usize && id < 510usize {
        s.open = id - 500usize
        s.screen = CONTACT_SCREEN
        ui.say("call contact ")
        ui.say_text(contact_name(a, s, s.open))
        ui.say("\n")
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "call")
    if kit_error != ok {
        ui.say("call open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("call fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.open = NONE
    s.callee = NONE
    add_contact(&s, "Maya Chen", "5550101")
    add_contact(&s, "Alex Rivera", "5550102")
    add_contact(&s, "Dad", "5550103")
    add_contact(&s, "Priya", "5550104")
    add_contact(&s, "City Library", "5550105")
    add_contact(&s, "Sam", "5550106")
    add_contact(&s, "Dr. Okafor", "5550107")
    // What was kept replaces the sample contacts; on a disk with none the samples are written.
    if load_contacts(a, &s) {
        ui.say("call contacts loaded ")
        ui.say_text(ui.number(a, s.contact_total))
        ui.say(" ")
        ui.say_text(contact_name(a, &s, 0usize))
        ui.say("\n")
    } else {
        save_contacts(a, &s)
    }
    add_recent(&s, 5usize, "5550106", 0usize, 2900usize)
    add_recent(&s, 3usize, "5550104", 1usize, 1500usize)
    add_recent(&s, 2usize, "5550103", 2usize, 300usize)
    add_recent(&s, 0usize, "5550101", 0usize, 95usize)
    add_recent(&s, 1usize, "5550102", 1usize, 14usize)
    if !show(a, &kit, &s) {
        ui.say("call present failed\n")
        ret ok
    }
    ui.say("call shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            // The call connects after a second; its timer follows the ticks.
            if s.screen == CALL_SCREEN {
                s.ticks += 1usize
                if s.ticks == 2usize { ui.say("call connected\n") }
                if s.ticks >= 2usize && s.ticks % 2usize == 0usize || s.ticks == 2usize {
                    if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
                } else {
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            ui.say("call home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("call present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
