// Wallet (D2216): the app behind the Wallet icon, after Google Wallet -- a stack of cards with filter chips
// (All, Payment, Tickets, Bank, Docs, Other): payment cards (the network and the check digit come from
// e.valid), a boarding pass, an event ticket, a vaccination certificate, loyalty and transit cards, bank
// accounts (beneficiary, bank, IBAN checked by e.valid, an optional account id and bank address), and
// documents (a passport, a visa, a driving license, certificates, contracts) with a page for the scan. A
// tap on a card opens it; a plus button adds one on an on-screen keyboard; a card can be removed. Dark
// ground, coloured cards and amber, like the other apps (appkit.e, taps from the compositor, the five
// fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
// ponytail: every card is SAMPLE data (made-up names; a payment card keeps only its last four digits),
// kept in this process, so the stack is the sample again each time the app starts. The QR code and the
// barcode are drawn from a seed per card -- they look like codes and do not encode the card -- and a
// document has no scan yet: reading and writing real codes, scanning with the Camera, and keeping the
// cards encrypted in Secure are queued as C121.
use e.mem
use e.os
use e.valid
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text

const NONE: usize = 99usize
const MAX_CARDS: usize = 12usize
const MAX_HITS: usize = 96usize
const VALUE_WIDTH: usize = 36usize
const STACK_SCREEN: usize = 0usize
const DETAIL_SCREEN: usize = 1usize
const ADD_SCREEN: usize = 2usize
const PAYMENT: usize = 0usize
const PASS: usize = 1usize
const EVENT: usize = 2usize
const HEALTH: usize = 3usize
const LOYALTY: usize = 4usize
const TRANSIT: usize = 5usize
const BANK: usize = 6usize
const DOC: usize = 7usize
const DOC_TYPES: usize = 12usize

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
}

fn say_text(value: str) {
    var buffer: [40]u8 = zero
    var n = 0usize
    while n < value.len && n < 40usize {
        buffer[n] = value[n]
        n += 1usize
    }
    say(buffer[0usize..n])
}

// ----------------------------------------------------------------------------------------------
// Text helpers.

fn join(a: *mem.Arena, first: str, second: str, third: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, first.len + second.len + third.len)
    if buffer_error != ok { ret first }
    var n = 0usize
    var i = 0usize
    while i < first.len {
        buffer[n] = first[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < second.len {
        buffer[n] = second[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < third.len {
        buffer[n] = third[i]
        n += 1usize
        i += 1usize
    }
    ret buffer[0usize..n]
}

fn text_of(a: *mem.Arena, bytes: []const u8, length: usize) -> str {
    let (copy, copy_error) = mem.alloc[u8](a, length + 1usize)
    if copy_error != ok { ret "" }
    var i = 0usize
    while i < length {
        copy[i] = bytes[i]
        i += 1usize
    }
    ret copy[0usize..length]
}

// Append `piece` to `buffer` at `at`; the new end.
fn emit(buffer: []u8, at: usize, piece: str) -> usize {
    var n = at
    var i = 0usize
    while i < piece.len && n < buffer.len {
        buffer[n] = piece[i]
        n += 1usize
        i += 1usize
    }
    ret n
}

fn emit_num(buffer: []u8, at: usize, value: usize) -> usize {
    var digits: [20]u8 = zero
    var d = 20usize
    var rest = value
    var open = true
    while open {
        d -= 1usize
        digits[d] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    ret emit(buffer, at, digits[d..20usize])
}

// The last four digits of a card number written with or without separators.
fn last_four(a: *mem.Arena, number: str) -> str {
    var found: [4]u8 = zero
    var count = 0usize
    var i = number.len
    while i > 0usize && count < 4usize {
        i -= 1usize
        let c = number[i]
        if c >= 48u8 && c <= 57u8 {
            found[3usize - count] = c
            count += 1usize
        }
    }
    if count == 0usize { ret "" }
    ret text_of(a, found[4usize - count..4usize], count)
}

// ----------------------------------------------------------------------------------------------
// State.

type Card = struct {
    title: [24]u8,
    title_len: usize,
    sub: [32]u8,
    sub_len: usize,
    kind: usize,
    color: usize,
    doc_type: usize,
    values: [180]u8,
    value_len: [5]usize,
    seed: usize,
    used: bool,
}

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    cards: [12]Card,
    screen: usize,
    filter: usize,
    open: usize,
    visible: [12]usize,
    visible_total: usize,
    // The add form: the kind chosen (an index into the six chips), the document type, the five fields
    // and the one in focus.
    pick: usize,
    doc_type: usize,
    fields: [180]u8,
    field_len: [5]usize,
    focus: usize,
    hits: [96]Hit,
    hit_total: usize,
}

fn make_card(title: str, sub: str, kind: usize, color: usize, seed: usize) -> Card {
    var c: Card = zero
    var i = 0usize
    while i < title.len && i < 24usize {
        c.title[i] = title[i]
        i += 1usize
    }
    c.title_len = i
    i = 0usize
    while i < sub.len && i < 32usize {
        c.sub[i] = sub[i]
        i += 1usize
    }
    c.sub_len = i
    c.kind = kind
    c.color = color
    c.seed = seed
    c.used = true
    ret c
}

fn put_value(c: *Card, slot: usize, value: str) {
    var i = 0usize
    while i < value.len && i < VALUE_WIDTH {
        c.values[slot * VALUE_WIDTH + i] = value[i]
        i += 1usize
    }
    c.value_len[slot] = i
}

fn add_card(s: *State, card_value: Card) -> usize {
    var i = 0usize
    while i < MAX_CARDS {
        if !s.cards[i].used {
            s.cards[i] = card_value
            ret i
        }
        i += 1usize
    }
    ret NONE
}

fn count_cards(s: *State) -> usize {
    var n = 0usize
    var i = 0usize
    while i < MAX_CARDS {
        if s.cards[i].used { n += 1usize }
        i += 1usize
    }
    ret n
}

// Does card kind `kind` belong under filter `filter` (0 All, 1 Payment, 2 Tickets, 3 Bank, 4 Docs, 5 Other)?
fn in_filter(filter: usize, kind: usize) -> bool {
    if filter == 0usize { ret true }
    if filter == 1usize { ret kind == PAYMENT }
    if filter == 2usize { ret kind == PASS || kind == EVENT || kind == TRANSIT }
    if filter == 3usize { ret kind == BANK }
    if filter == 4usize { ret kind == DOC }
    ret kind == HEALTH || kind == LOYALTY
}

fn filter_name(filter: usize) -> str {
    if filter == 0usize { ret "All" }
    if filter == 1usize { ret "Payment" }
    if filter == 2usize { ret "Tickets" }
    if filter == 3usize { ret "Bank" }
    if filter == 4usize { ret "Docs" }
    ret "Other"
}

fn kind_name(kind: usize) -> str {
    if kind == PAYMENT { ret "Payment" }
    if kind == PASS { ret "Boarding pass" }
    if kind == EVENT { ret "Event ticket" }
    if kind == HEALTH { ret "Health" }
    if kind == LOYALTY { ret "Loyalty" }
    if kind == TRANSIT { ret "Transit" }
    if kind == BANK { ret "Bank account" }
    ret "Document"
}

fn doc_name(index: usize) -> str {
    if index == 0usize { ret "Passport" }
    if index == 1usize { ret "Visa" }
    if index == 2usize { ret "Driving license" }
    if index == 3usize { ret "Birth certificate" }
    if index == 4usize { ret "Social security card" }
    if index == 5usize { ret "Marriage certificate" }
    if index == 6usize { ret "Notary act" }
    if index == 7usize { ret "Tax number certificate" }
    if index == 8usize { ret "Address certificate" }
    if index == 9usize { ret "Employment contract" }
    if index == 10usize { ret "Non-disclosure agreement" }
    ret "Vehicle registration"
}

fn detail_label(kind: usize, slot: usize) -> str {
    if kind == PAYMENT {
        if slot == 0usize { ret "Card" }
        if slot == 1usize { ret "Expires" }
        if slot == 2usize { ret "Network" }
        ret "Number check"
    }
    if kind == PASS {
        if slot == 0usize { ret "Route" }
        if slot == 1usize { ret "Flight" }
        if slot == 2usize { ret "Gate" }
        ret "Seat"
    }
    if kind == EVENT {
        if slot == 0usize { ret "Date" }
        if slot == 1usize { ret "Time" }
        if slot == 2usize { ret "Section" }
        ret "Seat"
    }
    if kind == HEALTH {
        if slot == 0usize { ret "Name" }
        if slot == 1usize { ret "Vaccine" }
        if slot == 2usize { ret "Doses" }
        ret "Issued by"
    }
    if kind == LOYALTY {
        if slot == 0usize { ret "Member" }
        if slot == 1usize { ret "Since" }
        if slot == 2usize { ret "Points" }
        ret "Number"
    }
    if kind == TRANSIT {
        if slot == 0usize { ret "Balance" }
        if slot == 1usize { ret "Zones" }
        if slot == 2usize { ret "Valid until" }
        ret "Card"
    }
    if kind == BANK {
        if slot == 0usize { ret "Beneficiary" }
        if slot == 1usize { ret "Bank" }
        if slot == 2usize { ret "IBAN" }
        if slot == 3usize { ret "Account ID" }
        ret "Bank address"
    }
    if slot == 0usize { ret "Holder" }
    if slot == 1usize { ret "Number" }
    if slot == 2usize { ret "Issued by" }
    ret "Valid until"
}

fn row_count(kind: usize) -> usize {
    if kind == BANK { ret 5usize }
    ret 4usize
}

fn value_of(a: *mem.Arena, c: Card, slot: usize) -> str {
    ret text_of(a, c.values[slot * VALUE_WIDTH..], c.value_len[slot])
}

fn title_of(a: *mem.Arena, c: Card) -> str {
    ret text_of(a, c.title[0usize..], c.title_len)
}

fn sub_of(a: *mem.Arena, c: Card) -> str {
    ret text_of(a, c.sub[0usize..], c.sub_len)
}

// A payment card from its name, number and expiry: the network and the check digit come from e.valid.
// Only the last four digits are kept.
fn payment_card(a: *mem.Arena, name: str, number: str, expiry: str, color: usize, seed: usize) -> Card {
    let brand = card_brand_label(number)
    let tail = join(a, "ending ", last_four(a, number), "")
    var c = make_card(name, join(a, brand, " ", tail), PAYMENT, color, seed)
    put_value(&c, 0usize, tail)
    put_value(&c, 1usize, expiry)
    put_value(&c, 2usize, brand)
    if valid.luhn(number) { put_value(&c, 3usize, "Valid") } else { put_value(&c, 3usize, "Check digit failed") }
    ret c
}

fn card_brand_label(number: str) -> str {
    ret valid.card_brand_name(valid.card_brand(number))
}

fn bank_card(beneficiary: str, bank: str, iban: str, account: str, address: str, color: usize, seed: usize) -> Card {
    var c = make_card(bank, beneficiary, BANK, color, seed)
    put_value(&c, 0usize, beneficiary)
    put_value(&c, 1usize, bank)
    put_value(&c, 2usize, iban)
    put_value(&c, 3usize, account)
    put_value(&c, 4usize, address)
    ret c
}

fn doc_card(doc_type: usize, holder: str, number: str, issuer: str, until: str, color: usize, seed: usize) -> Card {
    var c = make_card(doc_name(doc_type), holder, DOC, color, seed)
    c.doc_type = doc_type
    put_value(&c, 0usize, holder)
    put_value(&c, 1usize, number)
    put_value(&c, 2usize, issuer)
    put_value(&c, 3usize, until)
    ret c
}

fn plain_card(title: str, sub: str, kind: usize, color: usize, seed: usize, v0: str, v1: str, v2: str, v3: str) -> Card {
    var c = make_card(title, sub, kind, color, seed)
    put_value(&c, 0usize, v0)
    put_value(&c, 1usize, v1)
    put_value(&c, 2usize, v2)
    put_value(&c, 3usize, v3)
    ret c
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn cream() -> paint.Color {
    ret paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 }
}

fn ink() -> paint.Color {
    ret paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 }
}

fn muted() -> paint.Color {
    ret paint.Color { red: 0.36, green: 0.35, blue: 0.34, alpha: 1.0 }
}

fn light() -> paint.Color {
    ret paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 1.0 }
}

fn light_muted() -> paint.Color {
    ret paint.Color { red: 0.72, green: 0.72, blue: 0.74, alpha: 1.0 }
}

fn amber() -> paint.Color {
    ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }
}

fn soft() -> paint.Color {
    ret paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
}

// The face colours of the cards.
fn face_color(index: usize) -> paint.Color {
    let n = index % 10usize
    if n == 0usize { ret paint.Color { red: 0.16, green: 0.36, blue: 0.38, alpha: 1.0 } }
    if n == 1usize { ret paint.Color { red: 0.55, green: 0.34, blue: 0.20, alpha: 1.0 } }
    if n == 2usize { ret paint.Color { red: 0.24, green: 0.30, blue: 0.55, alpha: 1.0 } }
    if n == 3usize { ret paint.Color { red: 0.50, green: 0.25, blue: 0.40, alpha: 1.0 } }
    if n == 4usize { ret paint.Color { red: 0.20, green: 0.45, blue: 0.30, alpha: 1.0 } }
    if n == 5usize { ret paint.Color { red: 0.45, green: 0.40, blue: 0.20, alpha: 1.0 } }
    if n == 6usize { ret paint.Color { red: 0.30, green: 0.30, blue: 0.36, alpha: 1.0 } }
    if n == 7usize { ret paint.Color { red: 0.18, green: 0.30, blue: 0.46, alpha: 1.0 } }
    if n == 8usize { ret paint.Color { red: 0.45, green: 0.18, blue: 0.24, alpha: 1.0 } }
    ret paint.Color { red: 0.26, green: 0.38, blue: 0.24, alpha: 1.0 }
}

fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

fn hit(s: *State, id: usize, x: f32, y: f32, w: f32, h: f32) {
    if s.hit_total < MAX_HITS {
        s.hits[s.hit_total] = Hit { id: id, x: x, y: y, w: w, h: h }
        s.hit_total += 1usize
    }
}

fn put(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, 0.0, 0u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn clipped(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, width: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, width, 1u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, cx: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, cx - text.measure(a, font, size, line) / 2.0, y, c)
}

fn put_right(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, right: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, right - text.measure(a, font, size, line), y, c)
}

fn pill(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color, size: f32) -> err {
    try card(a, builder, x, y, w, h, h / 2.0, fill)
    try centred(a, builder, faces.jost, size, label, x + w / 2.0, y + h / 2.0 - size * 0.62, ink())
    hit(s, id, x, y, w, h)
    ret ok
}

fn back_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12H5M11 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn contactless_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M7 6c3 3.6 3 8.4 0 12M11.5 4c4.4 4.8 4.4 11.2 0 16M16 2c5.6 6 5.6 14 0 20' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'/></svg>"
}

// A card face at (x, y), 380 wide: the title, the line under it and the kind at the right; `tall` adds
// the lower half (a chip and the number for a payment card, the first two details for the others).
fn draw_face(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, c: Card, x: f32, y: f32, height: f32, tall: bool) -> err {
    try card(a, builder, x, y, 380.0, height, 20.0, face_color(c.color))
    try clipped(a, builder, faces.jost_bold, 20.0, title_of(a, c), x + 20.0, y + 14.0, 230.0, light())
    try clipped(a, builder, faces.grotesk, 13.0, sub_of(a, c), x + 20.0, y + 42.0, 250.0, paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 0.8 })
    try put_right(a, builder, faces.grotesk, 12.0, kind_name(c.kind), x + 364.0, y + 18.0, paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 0.8 })
    if tall {
        if c.kind == PAYMENT {
            try card(a, builder, x + 20.0, y + 66.0, 42.0, 30.0, 6.0, amber())
            try put(a, builder, faces.jost_bold, 24.0, value_of(a, c, 0usize), x + 20.0, y + height - 52.0, light())
        } else {
            try clipped(a, builder, faces.jost_bold, 26.0, value_of(a, c, 0usize), x + 20.0, y + height - 76.0, 340.0, light())
            try clipped(a, builder, faces.grotesk, 14.0, value_of(a, c, 1usize), x + 20.0, y + height - 38.0, 340.0, paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 0.85 })
        }
    }
    ret ok
}

// A QR-looking square of 25 x 25 cells from `seed`, three finder squares in the corners: an svg.
fn qr_svg(a: *mem.Arena, seed: usize) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, 24000usize)
    if buffer_error != ok { ret "" }
    var n = 0usize
    n = emit(buffer, n, "<svg viewBox='0 0 25 25'><path d='")
    var state = seed + 7usize
    var row = 0usize
    while row < 25usize {
        var col = 0usize
        while col < 25usize {
            state = (state * 1103515245usize + 12345usize) & 2147483647usize
            var dark = ((state >> 12usize) & 1usize) == 1usize
            // The finder squares: a 7 x 7 ring with a 3 x 3 centre, in three corners.
            var fr = 99usize
            var fc = 99usize
            if row < 7usize && col < 7usize {
                fr = row
                fc = col
            } else if row < 7usize && col >= 18usize {
                fr = row
                fc = col - 18usize
            } else if row >= 18usize && col < 7usize {
                fr = row - 18usize
                fc = col
            }
            if fr != 99usize {
                dark = fr == 0usize || fr == 6usize || fc == 0usize || fc == 6usize || (fr >= 2usize && fr <= 4usize && fc >= 2usize && fc <= 4usize)
            } else if (row == 7usize && col < 8usize) || (col == 7usize && row < 8usize) || (row == 7usize && col >= 17usize) || (col == 17usize && row < 8usize) || (row == 17usize && col < 8usize) || (col == 7usize && row >= 17usize) {
                dark = false
            }
            if dark {
                n = emit(buffer, n, "M")
                n = emit_num(buffer, n, col)
                n = emit(buffer, n, " ")
                n = emit_num(buffer, n, row)
                n = emit(buffer, n, "h1v1h-1z")
            }
            col += 1usize
        }
        row += 1usize
    }
    n = emit(buffer, n, "' fill='currentColor'/></svg>")
    ret buffer[0usize..n]
}

// A barcode of bars of one to three units from `seed`, 120 units wide: an svg.
fn barcode_svg(a: *mem.Arena, seed: usize) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, 4000usize)
    if buffer_error != ok { ret "" }
    var n = 0usize
    n = emit(buffer, n, "<svg viewBox='0 0 120 30'><path d='")
    var state = seed + 3usize
    var x = 0usize
    var drawing = true
    while x < 118usize {
        state = (state * 1103515245usize + 12345usize) & 2147483647usize
        let width = 1usize + (state >> 14usize) % 3usize
        if drawing {
            n = emit(buffer, n, "M")
            n = emit_num(buffer, n, x)
            n = emit(buffer, n, " 0h")
            n = emit_num(buffer, n, width)
            n = emit(buffer, n, "v30h-")
            n = emit_num(buffer, n, width)
            n = emit(buffer, n, "z")
        }
        drawing = !drawing
        x += width
    }
    n = emit(buffer, n, "' fill='currentColor'/></svg>")
    ret buffer[0usize..n]
}

fn draw_stack(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try put(a, builder, faces.jost_bold, 34.0, "Wallet", 24.0, 24.0, light())
    // The filters.
    var chip = 0usize
    while chip < 6usize {
        var fill = soft()
        if chip == s.filter { fill = amber() }
        try pill(a, builder, s, faces, 200usize + chip, 16.0 + f32(chip) * 66.8, 76.0, 62.0, 34.0, filter_name(chip), fill, 13.0)
        chip += 1usize
    }
    // The cards of the filter, each lower than the one before and over its lower part.
    s.visible_total = 0usize
    var i = 0usize
    while i < MAX_CARDS {
        if s.cards[i].used && in_filter(s.filter, s.cards[i].kind) {
            s.visible[s.visible_total] = i
            s.visible_total += 1usize
        }
        i += 1usize
    }
    var pitch: f32 = 72.0
    if s.visible_total > 1usize { pitch = 450.0 / f32(s.visible_total - 1usize) }
    if pitch > 72.0 { pitch = 72.0 }
    if pitch < 40.0 { pitch = 40.0 }
    var pos = 0usize
    while pos < s.visible_total {
        let index = s.visible[pos]
        let y: f32 = 128.0 + f32(pos) * pitch
        let last = pos + 1usize == s.visible_total
        var height = pitch
        if last { height = 190.0 }
        // Only the last card is drawn whole: the others show their top strip.
        try draw_face(a, builder, faces, s.cards[index], 16.0, y, 190.0, last)
        hit(s, 100usize + index, 16.0, y, 380.0, height)
        pos += 1usize
    }
    if s.visible_total == 0usize {
        try centred(a, builder, faces.jost, 20.0, "No cards here yet", 206.0, 300.0, light_muted())
    }
    // The plus button.
    try card(a, builder, 252.0, 820.0, 144.0, 56.0, 28.0, amber())
    try card(a, builder, 274.0 - 9.0, 848.0 - 1.5, 18.0, 3.0, 1.5, ink())
    try card(a, builder, 274.0 - 1.5, 848.0 - 9.0, 3.0, 18.0, 1.5, ink())
    try put(a, builder, faces.jost, 17.0, "Add card", 298.0, 837.0, ink())
    hit(s, 150usize, 252.0, 820.0, 144.0, 56.0)
    ret ok
}

fn draw_detail(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let c = s.cards[s.open]
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 28.0, 28.0, 28.0), light())
    hit(s, 500usize, 0.0, 14.0, 66.0, 56.0)
    try put(a, builder, faces.jost, 20.0, kind_name(c.kind), 64.0, 30.0, light_muted())
    try draw_face(a, builder, faces, c, 16.0, 76.0, 142.0, true)
    // The details.
    let rows = row_count(c.kind)
    let details_height: f32 = 12.0 + f32(rows) * 34.0
    try card(a, builder, 16.0, 230.0, 380.0, details_height, 20.0, cream())
    var slot = 0usize
    while slot < rows {
        let y: f32 = 240.0 + f32(slot) * 34.0
        var shown = value_of(a, c, slot)
        if shown.len == 0usize { shown = "-" }
        var size: f32 = 17.0
        if shown.len > 22usize { size = 13.0 }
        try put(a, builder, faces.grotesk, 13.0, detail_label(c.kind, slot), 34.0, y + 6.0, muted())
        try put_right(a, builder, faces.jost, size, shown, 378.0, y + 3.0, ink())
        slot += 1usize
    }
    let below: f32 = 230.0 + details_height + 14.0
    if c.kind == BANK {
        // The IBAN is checked by e.valid.
        let iban_ok = valid.iban(value_of(a, c, 2usize))
        var verdict = "IBAN check failed"
        var tone = paint.Color { red: 0.72, green: 0.22, blue: 0.18, alpha: 1.0 }
        if iban_ok {
            verdict = "IBAN is valid"
            tone = paint.Color { red: 0.13, green: 0.52, blue: 0.28, alpha: 1.0 }
        }
        try card(a, builder, 16.0, below, 380.0, 64.0, 20.0, cream())
        try centred(a, builder, faces.jost, 18.0, verdict, 206.0, below + 12.0, tone)
        try centred(a, builder, faces.grotesk, 12.0, "Country, length and check digits", 206.0, below + 38.0, muted())
    } else if c.kind == PAYMENT {
        try card(a, builder, 16.0, below, 380.0, 230.0, 20.0, cream())
        try svg.draw(a, builder, contactless_icon(), geometry.rect(166.0, below + 40.0, 80.0, 80.0), muted())
        try centred(a, builder, faces.jost, 18.0, "Hold near the reader to pay", 206.0, below + 140.0, ink())
        try centred(a, builder, faces.grotesk, 12.0, "Demo card, not usable for payments", 206.0, below + 172.0, muted())
    } else if c.kind == DOC {
        // The page of the scan: a sheet with lines of text, and what is missing.
        try card(a, builder, 16.0, below, 380.0, 250.0, 20.0, cream())
        try card(a, builder, 136.0, below + 18.0, 140.0, 140.0, 8.0, soft())
        var line = 0usize
        while line < 6usize {
            var w: f32 = 100.0
            if line % 3usize == 2usize { w = 70.0 }
            try card(a, builder, 152.0, below + 34.0 + f32(line) * 18.0, w, 6.0, 3.0, muted())
            line += 1usize
        }
        try centred(a, builder, faces.jost, 17.0, "No scan added yet", 206.0, below + 172.0, ink())
        try centred(a, builder, faces.grotesk, 12.0, "Scanning needs the Camera app", 206.0, below + 200.0, muted())
    } else if c.kind == LOYALTY || c.kind == TRANSIT {
        try card(a, builder, 16.0, below, 380.0, 230.0, 20.0, cream())
        try svg.draw(a, builder, barcode_svg(a, c.seed), geometry.rect(56.0, below + 24.0, 300.0, 120.0), ink())
        try centred(a, builder, faces.grotesk, 13.0, "Scan at the counter", 206.0, below + 160.0, muted())
        try centred(a, builder, faces.grotesk, 12.0, "Sample code, not scannable", 206.0, below + 186.0, muted())
    } else {
        try card(a, builder, 16.0, below, 380.0, 250.0, 20.0, cream())
        try svg.draw(a, builder, qr_svg(a, c.seed), geometry.rect(106.0, below + 12.0, 200.0, 200.0), ink())
        try centred(a, builder, faces.grotesk, 12.0, "Sample code, not scannable", 206.0, below + 222.0, muted())
    }
    try pill(a, builder, s, faces, 600usize, 16.0, 824.0, 150.0, 44.0, "Remove card", soft(), 16.0)
    ret ok
}

// ---- the keyboard (the same as SSH's): digits, three rows of letters, a row with - / space . and Enter.

fn number_label(n: usize) -> str {
    if n == 0usize { ret "0" }
    if n == 1usize { ret "1" }
    if n == 2usize { ret "2" }
    if n == 3usize { ret "3" }
    if n == 4usize { ret "4" }
    if n == 5usize { ret "5" }
    if n == 6usize { ret "6" }
    if n == 7usize { ret "7" }
    if n == 8usize { ret "8" }
    ret "9"
}

fn letter_row(row: usize) -> str {
    if row == 0usize { ret "qwertyuiop" }
    if row == 1usize { ret "asdfghjkl" }
    ret "zxcvbnm"
}

fn key_cap(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, label: str, fill: paint.Color) -> err {
    try card(a, builder, x, y + 2.0, w, 48.0, 10.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.35 })
    try card(a, builder, x, y, w, 48.0, 10.0, fill)
    try centred(a, builder, faces.grotesk, 20.0, label, x + w / 2.0, y + 24.0 - 12.0, ink())
    hit(s, id, x, y, w, 48.0)
    ret ok
}

fn draw_keyboard(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var d = 0usize
    while d < 10usize {
        try key_cap(a, builder, s, faces, 1100usize + d, 18.0 + f32(d) * 38.0, 500.0, 34.0, number_label((d + 1usize) % 10usize), soft())
        d += 1usize
    }
    var row = 0usize
    while row < 3usize {
        let letters = letter_row(row)
        var x0: f32 = 18.0
        if row == 1usize { x0 = 37.0 }
        if row == 2usize { x0 = 18.0 + 52.0 }
        var k = 0usize
        while k < letters.len {
            let ch = usize(letters[k])
            let (one, one_error) = mem.alloc[u8](a, 1usize)
            if one_error != ok { ret one_error }
            one[0usize] = letters[k]
            try key_cap(a, builder, s, faces, 1000usize + ch - 97usize, x0 + f32(k) * 38.0, 558.0 + f32(row) * 58.0, 34.0, one[0usize..1usize], cream())
            k += 1usize
        }
        row += 1usize
    }
    try key_cap(a, builder, s, faces, 1201usize, 18.0 + 52.0 + 7.0 * 38.0, 558.0 + 2.0 * 58.0, 52.0, "DEL", soft())
    try key_cap(a, builder, s, faces, 1203usize, 18.0, 732.0, 44.0, "-", soft())
    try key_cap(a, builder, s, faces, 1204usize, 68.0, 732.0, 44.0, "/", soft())
    try key_cap(a, builder, s, faces, 1200usize, 118.0, 732.0, 130.0, "space", cream())
    try key_cap(a, builder, s, faces, 1202usize, 254.0, 732.0, 44.0, ".", soft())
    try key_cap(a, builder, s, faces, 1205usize, 304.0, 732.0, 90.0, "Enter", amber())
    ret ok
}

// ---- the add form.

// The card kind a chip stands for.
fn pick_kind(pick: usize) -> usize {
    if pick == 0usize { ret PAYMENT }
    if pick == 1usize { ret EVENT }
    if pick == 2usize { ret HEALTH }
    if pick == 3usize { ret LOYALTY }
    if pick == 4usize { ret BANK }
    ret DOC
}

fn pick_label(pick: usize) -> str {
    if pick == 0usize { ret "Payment" }
    if pick == 1usize { ret "Ticket" }
    if pick == 2usize { ret "Health" }
    if pick == 3usize { ret "Loyalty" }
    if pick == 4usize { ret "Bank" }
    ret "Document"
}

// The fields a kind asks for: how many, and each one's label ("" for the document type selector).
fn slot_count(pick: usize) -> usize {
    if pick == 3usize { ret 2usize }
    if pick == 4usize || pick == 5usize { ret 5usize }
    ret 3usize
}

fn slot_label(pick: usize, slot: usize) -> str {
    if pick == 0usize {
        if slot == 0usize { ret "Card name" }
        if slot == 1usize { ret "Card number" }
        ret "Expiry (MM/YY)"
    }
    if pick == 1usize {
        if slot == 0usize { ret "Event" }
        if slot == 1usize { ret "Date" }
        ret "Seat"
    }
    if pick == 2usize {
        if slot == 0usize { ret "Certificate" }
        if slot == 1usize { ret "Holder" }
        ret "Issued by"
    }
    if pick == 3usize {
        if slot == 0usize { ret "Store" }
        ret "Member number"
    }
    if pick == 4usize {
        if slot == 0usize { ret "Beneficiary" }
        if slot == 1usize { ret "Bank" }
        if slot == 2usize { ret "IBAN" }
        if slot == 3usize { ret "Account ID (optional)" }
        ret "Bank address (optional)"
    }
    if slot == 0usize { ret "Type" }
    if slot == 1usize { ret "Holder" }
    if slot == 2usize { ret "Number" }
    if slot == 3usize { ret "Issued by" }
    ret "Valid until"
}

fn field_text(a: *mem.Arena, s: *State, slot: usize) -> str {
    ret text_of(a, s.fields[slot * VALUE_WIDTH..], s.field_len[slot])
}

fn field(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, slot: usize, y: f32) -> err {
    try put(a, builder, faces.grotesk, 12.0, slot_label(s.pick, slot), 20.0, y - 15.0, light_muted())
    // The document type is chosen, not typed.
    if s.pick == 5usize && slot == 0usize {
        try card(a, builder, 16.0, y, 380.0, 40.0, 14.0, amber())
        try clipped(a, builder, faces.jost, 18.0, doc_name(s.doc_type), 32.0, y + 8.0, 300.0, ink())
        try put_right(a, builder, faces.grotesk, 12.0, "tap to change", 380.0, y + 14.0, ink())
        hit(s, 1340usize, 16.0, y, 380.0, 40.0)
        ret ok
    }
    let value = field_text(a, s, slot)
    if s.focus == slot { try card(a, builder, 14.0, y - 2.0, 384.0, 44.0, 16.0, amber()) }
    try card(a, builder, 16.0, y, 380.0, 40.0, 14.0, cream())
    try clipped(a, builder, faces.jost, 17.0, value, 32.0, y + 9.0, 340.0, ink())
    if s.focus == slot {
        var caret_x: f32 = 32.0
        if value.len > 0usize { caret_x = 32.0 + text.measure(a, faces.jost, 17.0, value) + 2.0 }
        if caret_x > 372.0 { caret_x = 372.0 }
        try card(a, builder, caret_x, y + 8.0, 2.0, 24.0, 1.0, amber())
    }
    hit(s, 1500usize + slot, 16.0, y, 380.0, 40.0)
    ret ok
}

fn draw_add(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try put(a, builder, faces.jost_bold, 28.0, "Add to Wallet", 24.0, 12.0, light())
    var chip = 0usize
    while chip < 6usize {
        var fill = soft()
        if chip == s.pick { fill = amber() }
        try pill(a, builder, s, faces, 1320usize + chip, 16.0 + f32(chip % 3usize) * 132.0, 54.0 + f32(chip / 3usize) * 38.0, 124.0, 32.0, pick_label(chip), fill, 15.0)
        chip += 1usize
    }
    var slot = 0usize
    while slot < slot_count(s.pick) {
        try field(a, builder, s, faces, slot, 154.0 + f32(slot) * 56.0)
        slot += 1usize
    }
    try pill(a, builder, s, faces, 1300usize, 16.0, 436.0, 186.0, 46.0, "Save", amber(), 17.0)
    try pill(a, builder, s, faces, 1302usize, 210.0, 436.0, 186.0, 46.0, "Cancel", soft(), 17.0)
    try draw_keyboard(a, builder, s, faces)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    if s.screen == STACK_SCREEN {
        try draw_stack(a, builder, s, faces)
    } else if s.screen == DETAIL_SCREEN {
        try draw_detail(a, builder, s, faces)
    } else {
        try draw_add(a, builder, s, faces)
    }
    try card(a, builder, 156.0, 906.0, 100.0, 5.0, 2.5, paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 })
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

fn type_byte(s: *State, byte: u8) {
    let slot = s.focus
    if s.pick == 5usize && slot == 0usize { ret }
    if s.field_len[slot] >= VALUE_WIDTH { ret }
    var b = byte
    if b >= 97u8 && b <= 122u8 {
        // An IBAN is upper case; any other field starts with a capital.
        if s.pick == 4usize && slot == 2usize { b = b - 32u8 } else if s.field_len[slot] == 0usize { b = b - 32u8 }
    }
    s.fields[slot * VALUE_WIDTH + s.field_len[slot]] = b
    s.field_len[slot] += 1usize
}

fn backspace(s: *State) {
    if s.field_len[s.focus] > 0usize { s.field_len[s.focus] -= 1usize }
}

fn open_add(s: *State) {
    s.screen = ADD_SCREEN
    s.pick = 0usize
    s.doc_type = 0usize
    s.focus = 0usize
    var i = 0usize
    while i < 5usize {
        s.field_len[i] = 0usize
        i += 1usize
    }
}

// Is there enough to save: the name, and for a bank the IBAN, for a document the holder?
fn can_save(s: *State) -> bool {
    if s.pick == 5usize { ret s.field_len[1usize] > 0usize }
    if s.pick == 4usize { ret s.field_len[0usize] > 0usize && s.field_len[1usize] > 0usize && s.field_len[2usize] > 0usize }
    if s.pick == 0usize { ret s.field_len[0usize] > 0usize && s.field_len[1usize] > 0usize }
    ret s.field_len[0usize] > 0usize
}

// The card the add form describes.
fn built_card(a: *mem.Arena, s: *State) -> Card {
    let f0 = field_text(a, s, 0usize)
    let f1 = field_text(a, s, 1usize)
    let f2 = field_text(a, s, 2usize)
    let f3 = field_text(a, s, 3usize)
    let f4 = field_text(a, s, 4usize)
    let seed = 1000usize + s.field_len[0usize] * 31usize + s.field_len[1usize] * 17usize
    let color = count_cards(s)
    if s.pick == 0usize { ret payment_card(a, f0, f1, f2, color, seed) }
    if s.pick == 1usize { ret plain_card(f0, f1, EVENT, 3usize, seed, f1, "-", f2, "-") }
    if s.pick == 2usize { ret plain_card(f0, "Certificate", HEALTH, 4usize, seed, f1, "-", "-", f2) }
    if s.pick == 3usize { ret plain_card(f0, join(a, "No. ", last_four(a, f1), ""), LOYALTY, 5usize, seed, f0, "-", "0", f1) }
    if s.pick == 4usize { ret bank_card(f0, f1, f2, f3, f4, 7usize, seed) }
    ret doc_card(s.doc_type, f1, f2, f3, f4, 8usize, seed)
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == STACK_SCREEN {
        if id >= 200usize && id < 206usize {
            s.filter = id - 200usize
            say("wallet filter ")
            say(filter_name(s.filter))
            say("\n")
            ret true
        }
        if id >= 100usize && id < 100usize + MAX_CARDS {
            if s.cards[id - 100usize].used {
                s.open = id - 100usize
                s.screen = DETAIL_SCREEN
                say("wallet opened ")
                say_text(title_of(a, s.cards[s.open]))
                say("\n")
                if s.cards[s.open].kind == BANK {
                    if valid.iban(value_of(a, s.cards[s.open], 2usize)) { say("wallet iban valid\n") } else { say("wallet iban invalid\n") }
                }
                ret true
            }
            ret false
        }
        if id == 150usize {
            if count_cards(s) < MAX_CARDS { open_add(s) }
            ret true
        }
        ret false
    }
    if s.screen == DETAIL_SCREEN {
        if id == 500usize {
            s.screen = STACK_SCREEN
            say("wallet back\n")
            ret true
        }
        if id == 600usize {
            s.cards[s.open].used = false
            s.screen = STACK_SCREEN
            say("wallet removed\n")
            ret true
        }
        ret false
    }
    // The add form.
    if id >= 1000usize && id < 1026usize {
        type_byte(s, u8(97usize + id - 1000usize))
        ret true
    }
    if id >= 1100usize && id < 1110usize {
        type_byte(s, u8(48usize + (id - 1100usize + 1usize) % 10usize))
        ret true
    }
    if id == 1200usize {
        type_byte(s, 32u8)
        ret true
    }
    if id == 1201usize {
        backspace(s)
        ret true
    }
    if id == 1202usize {
        type_byte(s, 46u8)
        ret true
    }
    if id == 1203usize {
        type_byte(s, 45u8)
        ret true
    }
    if id == 1204usize {
        type_byte(s, 47u8)
        ret true
    }
    if id == 1205usize {
        if s.focus + 1usize < slot_count(s.pick) { s.focus += 1usize }
        ret true
    }
    if id >= 1500usize && id < 1505usize {
        s.focus = id - 1500usize
        ret true
    }
    if id >= 1320usize && id < 1326usize {
        s.pick = id - 1320usize
        s.focus = 0usize
        if s.pick == 5usize { s.focus = 1usize }
        ret true
    }
    if id == 1340usize {
        s.doc_type = (s.doc_type + 1usize) % DOC_TYPES
        ret true
    }
    if id == 1300usize {
        if can_save(s) {
            let index = add_card(s, built_card(a, s))
            if index != NONE { say("wallet added\n") }
            s.screen = STACK_SCREEN
            s.filter = 0usize
        }
        ret true
    }
    if id == 1302usize {
        s.screen = STACK_SCREEN
        ret true
    }
    ret false
}

fn hit_at(s: *State, x: f32, y: f32) -> usize {
    var i = s.hit_total
    while i > 0usize {
        i -= 1usize
        let h = s.hits[i]
        if x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h { ret h.id }
    }
    ret NONE
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "wallet")
    if kit_error != ok {
        say("wallet open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("wallet fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.open = NONE
    // The sample cards. The two payment cards use published test numbers; the network is worked out from
    // the number, and only the last four digits stay on the card.
    let visa = "4111 1111 1111 1111"
    let master = "5500 0000 0000 0004"
    let c1 = add_card(&s, payment_card(a, "Neper Bank", visa, "09/29", 0usize, 11usize))
    let c2 = add_card(&s, payment_card(a, "Atlas Card", master, "02/28", 1usize, 12usize))
    say("wallet brand ")
    say(card_brand_label(visa))
    say("\n")
    say("wallet brand ")
    say(card_brand_label(master))
    say("\n")
    let c3 = add_card(&s, plain_card("Skyline Air", "Fri, Oct 16 - 11:35", PASS, 2usize, 13usize, "SFO to NRT", "SK 108", "B22", "14A"))
    let c4 = add_card(&s, plain_card("Harbor Jazz Night", "Sat, Oct 17 - 8:00 PM", EVENT, 3usize, 14usize, "Sat, Oct 17", "8:00 PM", "C", "Row 9, 12"))
    let c5 = add_card(&s, plain_card("Vaccination", "Certificate", HEALTH, 4usize, 15usize, "Sam Rivera", "mRNA", "3 of 3", "Health Authority"))
    let c6 = add_card(&s, plain_card("City Library", "Member card", LOYALTY, 5usize, 16usize, "Sam Rivera", "2019", "120", "2204 8831"))
    let c7 = add_card(&s, plain_card("Metro Pass", "Zones 1-3", TRANSIT, 6usize, 17usize, "$18.50", "1-3", "Nov 30", "5530 1207"))
    let c8 = add_card(&s, bank_card("Sam Rivera", "Neper Bank", "DE89 3704 0044 0532 0130 00", "0532013000", "Neper Platz 1, 10115 Berlin", 7usize, 18usize))
    let c9 = add_card(&s, doc_card(0usize, "Sam Rivera", "X1234567", "Passport Office", "Mar 2031", 8usize, 19usize))
    let c10 = add_card(&s, doc_card(1usize, "Sam Rivera", "V-884201", "Consulate General", "Dec 2027", 9usize, 20usize))
    let c11 = add_card(&s, doc_card(2usize, "Sam Rivera", "D 5530 1207", "Motor Vehicles", "Jun 2029", 2usize, 21usize))
    let c12 = add_card(&s, doc_card(11usize, "Sam Rivera", "KX 21 NTR", "Motor Vehicles", "Aug 2027", 6usize, 22usize))
    if !show(a, &kit, &s) {
        say("wallet present failed\n")
        ret ok
    }
    say("wallet shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            say("wallet home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    say("wallet present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
