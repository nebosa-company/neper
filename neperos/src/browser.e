// Browser (D2224): the app behind the Browser icon, after Chrome -- an address bar (a lock and the site, or
// the text typed; anything that is not a site is a search), pages with headings, paragraphs, pictures,
// code and links you can follow, a bottom bar with Back, Forward, Home, Tabs (with the number open) and
// Reload, and a tab switcher with a card per tab, New tab and close. Dark ground, cream pages and amber,
// like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the
// bar at the very bottom leaves the app.
// ponytail: there is no network, so the web is SAMPLE pages that live in the app: a start page, neper.dev,
// news.example, docs.example, weather.example, search results, and "can't be reached" for anything else.
// A real engine (HTTP over TLS, HTML and CSS layout, images, forms, cookies, downloads) is queued as C129.
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
use scenes

const NONE: usize = 99usize
const MAX_TABS: usize = 4usize
const HISTORY: usize = 10usize
const BROWSE_SCREEN: usize = 0usize
const ENTRY_SCREEN: usize = 1usize
const TABS_SCREEN: usize = 2usize
const START: usize = 0usize
const NEPER: usize = 1usize
const NEWS: usize = 2usize
const DOCS: usize = 3usize
const RESULTS: usize = 4usize
const ERROR: usize = 5usize
const WEATHER: usize = 6usize

type Tab = struct {
    pages: [10]usize,
    count: usize,
    at: usize,
    query: [32]u8,
    query_len: usize,
    used: bool,
}

type State = struct {
    tabs: [4]Tab,
    tab_total: usize,
    current: usize,
    screen: usize,
    typed: ui.Field,
    hits: ui.Hits,
}

fn page_host(page: usize) -> str {
    if page == START { ret "Start page" }
    if page == NEPER { ret "neper.dev" }
    if page == NEWS { ret "news.example" }
    if page == DOCS { ret "docs.example" }
    if page == RESULTS { ret "search.example" }
    if page == WEATHER { ret "weather.example" }
    ret "Can't be reached"
}

fn page_title(page: usize) -> str {
    if page == START { ret "New tab" }
    if page == NEPER { ret "Neper" }
    if page == NEWS { ret "News" }
    if page == DOCS { ret "Neper docs" }
    if page == RESULTS { ret "Search" }
    if page == WEATHER { ret "Weather" }
    ret "Error"
}

// The page of a typed address, or RESULTS for a search, ERROR for a site that does not exist here.
fn resolve(typed: str) -> usize {
    var lowered: [64]u8 = zero
    var n = 0usize
    var has_space = false
    var has_dot = false
    var i = 0usize
    while i < typed.len && n < 64usize {
        var c = typed[i]
        if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
        if c == 32u8 { has_space = true }
        if c == 46u8 { has_dot = true }
        lowered[n] = c
        n += 1usize
        i += 1usize
    }
    var text_lower = lowered[0usize..n]
    // Without the scheme.
    if n >= 8usize && ui.same(text_lower[0usize..8usize], "https://") { text_lower = text_lower[8usize..n] }
    if text_lower.len >= 7usize && ui.same(text_lower[0usize..7usize], "http://") { text_lower = text_lower[7usize..text_lower.len] }
    if ui.same(text_lower, "neper.dev") { ret NEPER }
    if ui.same(text_lower, "news.example") { ret NEWS }
    if ui.same(text_lower, "docs.example") { ret DOCS }
    if ui.same(text_lower, "weather.example") { ret WEATHER }
    if ui.same(text_lower, "start") { ret START }
    if has_space || !has_dot { ret RESULTS }
    ret ERROR
}

fn current_tab(s: *State) -> *Tab {
    ret &s.tabs[s.current]
}

fn current_page(s: *State) -> usize {
    let t = s.tabs[s.current]
    ret t.pages[t.at]
}

// Go to `page` in the current tab: the pages after the current one are forgotten.
fn go(s: *State, page: usize) {
    var t = &s.tabs[s.current]
    var at = t.at + 1usize
    if t.count == 0usize { at = 0usize }
    if at >= HISTORY {
        var k = 1usize
        while k < HISTORY {
            t.pages[k - 1usize] = t.pages[k]
            k += 1usize
        }
        at = HISTORY - 1usize
    }
    t.pages[at] = page
    t.at = at
    t.count = at + 1usize
    ui.say("browser go ")
    ui.say(page_host(page))
    ui.say("\n")
}

fn new_tab(s: *State) -> bool {
    if s.tab_total >= MAX_TABS { ret false }
    var t: Tab = zero
    t.pages[0usize] = START
    t.count = 1usize
    t.used = true
    s.tabs[s.tab_total] = t
    s.current = s.tab_total
    s.tab_total += 1usize
    ui.say("browser tab new\n")
    ret true
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn lock_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><rect x='5' y='11' width='14' height='10' rx='2' fill='currentColor'/><path d='M8 11V8a4 4 0 0 1 8 0v3' fill='none' stroke='currentColor' stroke-width='2'/></svg>"
}

fn chevron(left: bool) -> str {
    if left { ret "<svg viewBox='0 0 24 24'><path d='M15 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M9 5l7 7-7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn home_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M4 11l8-7 8 7v9h-5v-6H9v6H4z' fill='currentColor'/></svg>"
}

fn reload_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12a8 8 0 1 1-2.5-5.8M20 4v5h-5' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn picture(a: *mem.Arena, builder: *scene.Builder, doc: str, r: geometry.Rect, c: paint.Color) -> err {
    let save: scene.Command = .Save
    try scene.push(builder, save)
    try scene.push(builder, scene.Command { Clip: scene.Clip { Rect: r } })
    try svg.draw(a, builder, doc, r, c)
    let restore: scene.Command = .Restore
    try scene.push(builder, restore)
    ret ok
}

// A link drawn as an amber pill; its target is its id.
fn link(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, label: str) -> err {
    ret ui.pill(a, builder, &s.hits, faces, id, x, y, w, 44.0, label, ui.amber(), 16.0)
}

fn draw_start(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.centred(a, builder, faces.jost_bold, 40.0, "Neper", 206.0, 106.0, ui.light())
    try ui.card(a, builder, 16.0, 170.0, 380.0, 52.0, 26.0, ui.cream())
    try ui.put(a, builder, faces.jost, 17.0, "Search or type a web address", 40.0, 184.0, ui.muted())
    ui.hit(&s.hits, 700usize, 16.0, 170.0, 380.0, 52.0)
    var tile = 0usize
    while tile < 4usize {
        var label = "Neper"
        var host = "neper.dev"
        if tile == 1usize {
            label = "News"
            host = "news.example"
        }
        if tile == 2usize {
            label = "Docs"
            host = "docs.example"
        }
        if tile == 3usize {
            label = "Weather"
            host = "weather.example"
        }
        let x: f32 = 16.0 + f32(tile % 2usize) * 196.0
        let y: f32 = 250.0 + f32(tile / 2usize) * 112.0
        try ui.card(a, builder, x, y, 184.0, 96.0, 20.0, ui.cream())
        try ui.disc(a, builder, x + 36.0, y + 34.0, 18.0, ui.tint(tile))
        try ui.centred(a, builder, faces.jost_bold, 17.0, label[0usize..1usize], x + 36.0, y + 24.0, ui.ink())
        try ui.put(a, builder, faces.jost, 18.0, label, x + 66.0, y + 22.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 12.0, host, x + 16.0, y + 66.0, ui.muted())
        ui.hit(&s.hits, 400usize + tile, x, y, 184.0, 96.0)
        tile += 1usize
    }
    ret ok
}

fn draw_neper(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 16.0, 92.0, 380.0, 640.0, 20.0, ui.cream())
    let (h, h_error) = ui.wrapped(a, builder, faces.jost_bold, 28.0, "Neper: one language for the whole stack", 32.0, 108.0, 348.0, 3u32, ui.ink())
    if h_error != ok { ret h_error }
    let (p1, p1_error) = ui.wrapped(a, builder, faces.jost, 17.0, "A compiled, systems-level language with its own toolchain, its own libraries and its own operating system. Small programs start in milliseconds and big ones check in seconds.", 32.0, 214.0, 348.0, 6u32, ui.muted())
    if p1_error != ok { ret p1_error }
    let (p2, p2_error) = ui.wrapped(a, builder, faces.jost, 17.0, "This page is a sample: the browser has no network yet, so the web here is a handful of pages kept in the app.", 32.0, 350.0, 348.0, 4u32, ui.muted())
    if p2_error != ok { ret p2_error }
    try link(a, builder, s, faces, 410usize, 32.0, 520.0, 160.0, "Read the docs")
    try link(a, builder, s, faces, 411usize, 204.0, 520.0, 160.0, "Latest news")
    ret ok
}

fn draw_news(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 16.0, 92.0, 380.0, 660.0, 20.0, ui.cream())
    try picture(a, builder, scenes.scene_svg(a, 3usize, 4usize, 5usize, false, 380usize, 200usize), geometry.rect(16.0, 92.0, 380.0, 200.0), ui.light())
    let (h, h_error) = ui.wrapped(a, builder, faces.jost_bold, 26.0, "City lights return to the old harbour", 32.0, 306.0, 348.0, 3u32, ui.ink())
    if h_error != ok { ret h_error }
    try ui.put(a, builder, faces.grotesk, 12.0, "By the news desk, 2 hours ago", 32.0, 388.0, ui.muted())
    let (p, p_error) = ui.wrapped(a, builder, faces.jost, 17.0, "After three years of work the waterfront district switched its lamps back on this week. Residents gathered on the pier as the towers lit up one by one.", 32.0, 416.0, 348.0, 8u32, ui.ink())
    if p_error != ok { ret p_error }
    try link(a, builder, s, faces, 412usize, 32.0, 640.0, 180.0, "More stories")
    ret ok
}

fn draw_docs(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 16.0, 92.0, 380.0, 660.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.jost_bold, 26.0, "The Neper guide", 32.0, 108.0, ui.ink())
    try ui.card(a, builder, 32.0, 160.0, 348.0, 170.0, 12.0, paint.Color { red: 0.12, green: 0.13, blue: 0.16, alpha: 1.0 })
    try ui.put(a, builder, faces.grotesk, 14.0, "fn main() -> err {", 46.0, 174.0, paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 })
    try ui.put(a, builder, faces.grotesk, 14.0, "    let name = \"Neper\"", 46.0, 200.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 14.0, "    say(name)", 46.0, 226.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 14.0, "    ret ok", 46.0, 252.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 14.0, "}", 46.0, 278.0, paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 })
    var row = 0usize
    while row < 4usize {
        var label = "Getting started"
        if row == 1usize { label = "Types and values" }
        if row == 2usize { label = "Errors and try" }
        if row == 3usize { label = "The standard library" }
        let y: f32 = 352.0 + f32(row) * 56.0
        try ui.card(a, builder, 32.0, y, 348.0, 46.0, 14.0, ui.soft())
        try ui.put(a, builder, faces.jost, 17.0, label, 48.0, y + 12.0, ui.ink())
        ui.hit(&s.hits, 420usize + row, 32.0, y, 348.0, 46.0)
        row += 1usize
    }
    ret ok
}

fn draw_weather(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.card(a, builder, 16.0, 92.0, 380.0, 400.0, 20.0, ui.cream())
    try ui.put(a, builder, faces.jost_bold, 26.0, "Forecast", 32.0, 108.0, ui.ink())
    try ui.put(a, builder, faces.jost_bold, 64.0, "18\xC2\xB0", 32.0, 156.0, ui.ink())
    try ui.put(a, builder, faces.jost, 20.0, "Partly cloudy in Seattle", 32.0, 250.0, ui.muted())
    try picture(a, builder, scenes.scene_svg(a, 4usize, 3usize, 5usize, false, 348usize, 130usize), geometry.rect(32.0, 300.0, 348.0, 130.0), ui.light())
    ret ok
}

fn draw_results(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let t = s.tabs[s.current]
    try ui.put(a, builder, faces.jost_bold, 22.0, ui.join(a, "Results for ", ui.text_of(a, t.query[0usize..], t.query_len), ""), 20.0, 92.0, ui.light())
    var row = 0usize
    while row < 3usize {
        var title = "Neper: one language for the whole stack"
        var host = "neper.dev"
        if row == 1usize {
            title = "City lights return to the old harbour"
            host = "news.example"
        }
        if row == 2usize {
            title = "The Neper guide"
            host = "docs.example"
        }
        let y: f32 = 136.0 + f32(row) * 112.0
        try ui.card(a, builder, 16.0, y, 380.0, 100.0, 18.0, ui.cream())
        try ui.put(a, builder, faces.grotesk, 12.0, host, 32.0, y + 12.0, ui.muted())
        let (box, box_error) = ui.wrapped(a, builder, faces.jost, 18.0, title, 32.0, y + 34.0, 348.0, 2u32, ui.ink())
        if box_error != ok { ret box_error }
        ui.hit(&s.hits, 430usize + row, 16.0, y, 380.0, 100.0)
        row += 1usize
    }
    ret ok
}

fn draw_error(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.centred(a, builder, faces.jost_bold, 26.0, "This site can't be reached", 206.0, 220.0, ui.light())
    try ui.centred(a, builder, faces.jost, 17.0, "There is no network yet.", 206.0, 270.0, ui.light_muted())
    try ui.centred(a, builder, faces.jost, 17.0, "Only the sample sites open here.", 206.0, 300.0, ui.light_muted())
    try ui.pill(a, builder, &s.hits, faces, 440usize, 106.0, 360.0, 200.0, 48.0, "Go to start page", ui.amber(), 17.0)
    ret ok
}

fn draw_toolbar(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let t = s.tabs[s.current]
    try ui.card(a, builder, 0.0, 828.0, 412.0, 68.0, 0.0, paint.Color { red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0 })
    var back_tone = ui.light()
    if t.at == 0usize { back_tone = paint.Color { red: 0.4, green: 0.4, blue: 0.43, alpha: 1.0 } }
    var forward_tone = ui.light()
    if t.at + 1usize >= t.count { forward_tone = paint.Color { red: 0.4, green: 0.4, blue: 0.43, alpha: 1.0 } }
    try svg.draw(a, builder, chevron(true), geometry.rect(38.0, 850.0, 24.0, 24.0), back_tone)
    ui.hit(&s.hits, 800usize, 10.0, 828.0, 80.0, 68.0)
    try svg.draw(a, builder, chevron(false), geometry.rect(118.0, 850.0, 24.0, 24.0), forward_tone)
    ui.hit(&s.hits, 801usize, 90.0, 828.0, 80.0, 68.0)
    try svg.draw(a, builder, home_icon(), geometry.rect(194.0, 850.0, 24.0, 24.0), ui.light())
    ui.hit(&s.hits, 802usize, 170.0, 828.0, 72.0, 68.0)
    try ui.card(a, builder, 272.0, 851.0, 24.0, 22.0, 6.0, ui.light())
    try ui.centred(a, builder, faces.jost_bold, 14.0, ui.number(a, s.tab_total), 284.0, 853.0, ui.ink())
    ui.hit(&s.hits, 803usize, 242.0, 828.0, 80.0, 68.0)
    try svg.draw(a, builder, reload_icon(), geometry.rect(350.0, 850.0, 24.0, 24.0), ui.light())
    ui.hit(&s.hits, 804usize, 322.0, 828.0, 90.0, 68.0)
    ret ok
}

fn draw_browse(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let page = current_page(s)
    // The address bar.
    try ui.card(a, builder, 16.0, 22.0, 380.0, 46.0, 23.0, ui.cream())
    if page == START {
        try ui.put(a, builder, faces.jost, 17.0, "Search or type a web address", 40.0, 33.0, ui.muted())
    } else {
        try svg.draw(a, builder, lock_icon(), geometry.rect(32.0, 34.0, 20.0, 20.0), ui.muted())
        try ui.put(a, builder, faces.jost, 17.0, page_host(page), 62.0, 33.0, ui.ink())
    }
    ui.hit(&s.hits, 700usize, 16.0, 22.0, 380.0, 46.0)
    if page == START { try draw_start(a, builder, s, faces) }
    if page == NEPER { try draw_neper(a, builder, s, faces) }
    if page == NEWS { try draw_news(a, builder, s, faces) }
    if page == DOCS { try draw_docs(a, builder, s, faces) }
    if page == WEATHER { try draw_weather(a, builder, s, faces) }
    if page == RESULTS { try draw_results(a, builder, s, faces) }
    if page == ERROR { try draw_error(a, builder, s, faces) }
    try draw_toolbar(a, builder, s, faces)
    ret ok
}

fn draw_entry(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let value = ui.field_text(a, &s.typed)
    try ui.card(a, builder, 14.0, 20.0, 384.0, 54.0, 27.0, ui.amber())
    try ui.card(a, builder, 16.0, 22.0, 380.0, 50.0, 25.0, ui.cream())
    try ui.clipped(a, builder, faces.jost, 18.0, value, 36.0, 35.0, 340.0, ui.ink())
    var caret_x: f32 = 36.0
    if value.len > 0usize { caret_x = 36.0 + text.measure(a, faces.jost, 18.0, value) + 2.0 }
    if caret_x > 372.0 { caret_x = 372.0 }
    try ui.card(a, builder, caret_x, 33.0, 2.0, 26.0, 1.0, ui.amber())
    try ui.put(a, builder, faces.grotesk, 12.0, "Suggestions", 24.0, 96.0, ui.light_muted())
    var row = 0usize
    while row < 4usize {
        var site = "neper.dev"
        if row == 1usize { site = "news.example" }
        if row == 2usize { site = "docs.example" }
        if row == 3usize { site = "weather.example" }
        let y: f32 = 120.0 + f32(row) * 56.0
        try ui.card(a, builder, 16.0, y, 380.0, 48.0, 14.0, ui.cream())
        try ui.put(a, builder, faces.jost, 17.0, site, 36.0, y + 12.0, ui.ink())
        ui.hit(&s.hits, 450usize + row, 16.0, y, 380.0, 48.0)
        row += 1usize
    }
    try ui.keyboard(a, builder, &s.hits, faces, "Go")
    ret ok
}

fn draw_tabs(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 28.0, ui.join(a, ui.number(a, s.tab_total), " tabs", ""), 24.0, 22.0, ui.light())
    var i = 0usize
    while i < s.tab_total {
        let t = s.tabs[i]
        let x: f32 = 16.0 + f32(i % 2usize) * 196.0
        let y: f32 = 84.0 + f32(i / 2usize) * 230.0
        var rim = ui.soft()
        if i == s.current { rim = ui.amber() }
        try ui.card(a, builder, x - 2.0, y - 2.0, 188.0, 218.0, 20.0, rim)
        try ui.card(a, builder, x, y, 184.0, 214.0, 18.0, ui.cream())
        let page = t.pages[t.at]
        try ui.clipped(a, builder, faces.jost, 15.0, page_title(page), x + 14.0, y + 10.0, 120.0, ui.ink())
        try ui.put(a, builder, faces.grotesk, 11.0, page_host(page), x + 14.0, y + 34.0, ui.muted())
        try ui.card(a, builder, x + 14.0, y + 60.0, 156.0, 130.0, 10.0, ui.tint(page))
        try ui.put(a, builder, faces.jost_bold, 20.0, "x", x + 158.0 - 4.0, y + 4.0, ui.muted())
        ui.hit(&s.hits, 520usize + i, x + 140.0, y, 44.0, 44.0)
        ui.hit(&s.hits, 510usize + i, x, y, 184.0, 214.0)
        i += 1usize
    }
    try ui.pill(a, builder, &s.hits, faces, 530usize, 16.0, 800.0, 150.0, 48.0, "New tab", ui.amber(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 531usize, 246.0, 800.0, 150.0, 48.0, "Done", ui.soft(), 17.0)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == BROWSE_SCREEN {
        try draw_browse(a, builder, s, faces)
    } else if s.screen == ENTRY_SCREEN {
        try draw_entry(a, builder, s, faces)
    } else {
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

fn submit(a: *mem.Arena, s: *State, address: str) {
    let page = resolve(address)
    if page == RESULTS {
        var t = &s.tabs[s.current]
        var i = 0usize
        while i < address.len && i < 32usize {
            t.query[i] = address[i]
            i += 1usize
        }
        t.query_len = i
        ui.say("browser search ")
        ui.say_text(address)
        ui.say("\n")
    }
    go(s, page)
    s.screen = BROWSE_SCREEN
}

// What a tap on button `id` did: true when the screen changed.
fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.screen == ENTRY_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                submit(a, s, ui.field_text(a, &s.typed))
                ret true
            }
            ret ui.field_key(&s.typed, id, false)
        }
        if id >= 450usize && id < 454usize {
            var site = "neper.dev"
            if id == 451usize { site = "news.example" }
            if id == 452usize { site = "docs.example" }
            if id == 453usize { site = "weather.example" }
            submit(a, s, site)
            ret true
        }
        ret false
    }
    if s.screen == TABS_SCREEN {
        if id >= 510usize && id < 514usize {
            if id - 510usize < s.tab_total {
                s.current = id - 510usize
                s.screen = BROWSE_SCREEN
            }
            ret true
        }
        if id >= 520usize && id < 524usize {
            let which = id - 520usize
            if s.tab_total > 1usize && which < s.tab_total {
                var k = which + 1usize
                while k < s.tab_total {
                    s.tabs[k - 1usize] = s.tabs[k]
                    k += 1usize
                }
                s.tab_total -= 1usize
                if s.current >= s.tab_total { s.current = s.tab_total - 1usize }
                ui.say("browser tab closed\n")
            }
            ret true
        }
        if id == 530usize {
            if new_tab(s) { s.screen = BROWSE_SCREEN }
            ret true
        }
        if id == 531usize {
            s.screen = BROWSE_SCREEN
            ret true
        }
        ret false
    }
    if id == 700usize {
        s.screen = ENTRY_SCREEN
        s.typed.len = 0usize
        ret true
    }
    if id == 800usize {
        var t = &s.tabs[s.current]
        if t.at > 0usize {
            t.at -= 1usize
            ui.say("browser back\n")
        }
        ret true
    }
    if id == 801usize {
        var t = &s.tabs[s.current]
        if t.at + 1usize < t.count {
            t.at += 1usize
            ui.say("browser forward\n")
        }
        ret true
    }
    if id == 802usize {
        go(s, START)
        ret true
    }
    if id == 803usize {
        s.screen = TABS_SCREEN
        ret true
    }
    if id == 804usize {
        ui.say("browser reload\n")
        ret true
    }
    if id >= 400usize && id < 404usize {
        if id == 400usize { go(s, NEPER) }
        if id == 401usize { go(s, NEWS) }
        if id == 402usize { go(s, DOCS) }
        if id == 403usize { go(s, WEATHER) }
        ret true
    }
    if id == 410usize {
        go(s, DOCS)
        ret true
    }
    if id == 411usize || id == 412usize {
        go(s, NEWS)
        ret true
    }
    if id >= 420usize && id < 424usize {
        ui.say("browser link section\n")
        ret true
    }
    if id >= 430usize && id < 433usize {
        if id == 430usize { go(s, NEPER) }
        if id == 431usize { go(s, NEWS) }
        if id == 432usize { go(s, DOCS) }
        ret true
    }
    if id == 440usize {
        go(s, START)
        ret true
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "browser")
    if kit_error != ok {
        ui.say("browser open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("browser fonts absent\n")
        ret ok
    }
    var s: State = zero
    let first = new_tab(&s)
    if !show(a, &kit, &s) {
        ui.say("browser present failed\n")
        ret ok
    }
    ui.say("browser shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            ui.say("browser home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("browser present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
