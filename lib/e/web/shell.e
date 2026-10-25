// The browser shell's model (tracker 7.7), with no widgets: tabs, each with its own page and session history, the omnibox rules
// that turn typed text into an address or a search, `about:` pages (blank, history, bookmarks), bookmarks and a visit log with
// a profile file, and the error page a failed load leaves behind. The windowed app is a thin layer over this module; everything
// that can be wrong without a window is here, so a fixture can drive it.
//
// Each tab owns an arena carved out of the shell's (reserved, committed as it is touched). A navigation rewinds the tab's arena
// to its start and loads the new page into it, so a tab's memory is bounded by its largest page, not by how long it has been
// open. The shared `fetch.Client` allocates its responses in its own arena, which only grows (ceiling: a long session needs a
// client arena sized for it, or a recycling client).
use e.data.list as list
use e.fmt.url as url
use e.fs
use e.js.interp as js
use e.mem
use e.net.fetch as fetch
use e.str
use e.time
use e.text.fontset as fontset
use e.web.page as page

error TooManyTabs
error NoSuchTab
error BadProfile

const MAX_TABS: usize = 16usize
const TAB_ARENA_BYTES: usize = 134217728usize
const VIEW_BYTES: usize = 33554432usize
fn search_url() -> str { ret "https://duckduckgo.com/?q=" }

type Entry = struct { url: str, title: str, at: i64, count: u32 }
type Tab = struct {
    id: u32, arena: mem.Arena, mark: usize, pg: *page.Page, loaded: bool,
    history: list.List[Entry], index: usize, loading_url: str, error_text: str
}
type Shell = struct {
    a: *mem.Arena, client: *fetch.Client, fonts: *fontset.Set, width: f32, height: f32,
    tabs: list.List[*Tab], active: usize, next_id: u32, bookmarks: list.List[Entry], visits: list.List[Entry]
}

fn new(a: *mem.Arena, client: *fetch.Client, fonts: *fontset.Set, width: f32, height: f32) -> (*Shell, err) {
    let (cell, ce) = mem.alloc[Shell](a, 1usize)
    if ce != ok { ret (zero, ce) }
    let (tl, te) = list.init[*Tab](a, MAX_TABS)
    if te != ok { ret (zero, te) }
    let (bl, be) = list.init[Entry](a, 32usize)
    if be != ok { ret (zero, be) }
    let (vl, ve) = list.init[Entry](a, 64usize)
    if ve != ok { ret (zero, ve) }
    cell[0usize] = Shell { a: a, client: client, fonts: fonts, width: width, height: height, tabs: tl, active: 0usize, next_id: 1u32, bookmarks: bl, visits: vl }
    ret (&cell[0usize], ok)
}

// ---- The omnibox -------------------------------------------------------------------------------------------------------

fn is_alpha(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) }

fn has_scheme(s: str) -> bool {
    if s.len < 2usize || !is_alpha(s[0usize]) { ret false }
    var i = 1usize
    while i < s.len {
        let c = s[i]
        if c == 58u8 {
            if i < 2usize { ret false }
            // `host:8080/path` is a host and a port, not a scheme.
            var k = i + 1usize
            while k < s.len && s[k] >= 48u8 && s[k] <= 57u8 { k += 1usize }
            if k > i + 1usize && (k == s.len || s[k] == 47u8 || s[k] == 63u8 || s[k] == 35u8) { ret false }
            ret true
        }
        if !(is_alpha(c) || (c >= 48u8 && c <= 57u8) || c == 43u8 || c == 45u8 || c == 46u8) { ret false }
        i += 1usize
    }
    ret false
}

fn has_space(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] == 32u8 || s[i] == 9u8 { ret true }
        i += 1usize
    }
    ret false
}

fn hex_digit(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 55u8 + v
}

// Percent-encodes everything but unreserved characters (a query component or the body of a data URL).
fn percent_encode(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len * 3usize + 1usize)
    if e != ok { ret "" }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if is_alpha(c) || (c >= 48u8 && c <= 57u8) || c == 45u8 || c == 46u8 || c == 95u8 || c == 126u8 {
            out[n] = c
            n += 1usize
        } else {
            out[n] = 37u8
            out[n + 1usize] = hex_digit(c >> 4u8)
            out[n + 2usize] = hex_digit(c & 15u8)
            n += 3usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn looks_like_host(s: str) -> bool {
    var head = s
    var i = 0usize
    while i < s.len && s[i] != 47u8 && s[i] != 63u8 && s[i] != 35u8 { i += 1usize }
    head = s[0usize..i]
    if head.len == 0usize { ret false }
    var hostpart = head
    var j = head.len
    while j > 0usize && head[j - 1usize] != 58u8 { j -= 1usize }
    if j > 0usize && j < head.len {
        var digits = true
        var k = j
        while k < head.len {
            if head[k] < 48u8 || head[k] > 57u8 { digits = false }
            k += 1usize
        }
        if digits { hostpart = head[0usize..j - 1usize] }
    }
    if str.eq(hostpart, "localhost") { ret true }
    var dots = 0usize
    var m = 0usize
    while m < hostpart.len {
        if hostpart[m] == 46u8 { dots += 1usize }
        m += 1usize
    }
    ret dots > 0usize && hostpart[0usize] != 46u8 && hostpart[hostpart.len - 1usize] != 46u8
}

fn concat(a: *mem.Arena, x: str, y: str) -> str {
    let (s, e) = str.concat(a, x, y)
    if e != ok { ret x }
    ret s
}

// What the address bar does with `text`: an address stays one, a bare host or `host:port` gets a scheme (http for localhost
// and numeric hosts, https otherwise), anything else is a search.
fn omnibox_url(a: *mem.Arena, text_in: str) -> str {
    let text = str.trim(text_in)
    if text.len == 0usize { ret "about:blank" }
    if has_scheme(text) { ret text }
    if !has_space(text) && looks_like_host(text) {
        var plain = str.starts_with(text, "localhost")
        if text[0usize] >= 48u8 && text[0usize] <= 57u8 { plain = true }
        if plain { ret concat(a, "http://", text) }
        ret concat(a, "https://", text)
    }
    ret concat(a, search_url(), percent_encode(a, text))
}

// ---- about: pages and errors -------------------------------------------------------------------------------------------

fn html_escape(a: *mem.Arena, s: str) -> str {
    var out = ""
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 60u8 { out = concat(a, out, "&lt;") } else if c == 62u8 { out = concat(a, out, "&gt;") } else if c == 38u8 { out = concat(a, out, "&amp;") } else if c == 34u8 { out = concat(a, out, "&quot;") } else {
            let one = s[i..i + 1usize]
            out = concat(a, out, one)
        }
        i += 1usize
    }
    ret out
}

fn entries_page(a: *mem.Arena, heading: str, entries: []const Entry, newest_first: bool) -> str {
    var body = concat(a, "<!DOCTYPE html><meta charset=utf-8><title>", heading)
    body = concat(a, body, "</title><body style=\"font-family:sans-serif;margin:2em\"><h1>")
    body = concat(a, body, heading)
    body = concat(a, body, "</h1>")
    if entries.len == 0usize { body = concat(a, body, "<p>Nothing here yet.</p>") }
    var i = 0usize
    while i < entries.len {
        var at = i
        if newest_first { at = entries.len - 1usize - i }
        let e = entries[at]
        var title = e.title
        if title.len == 0usize { title = e.url }
        body = concat(a, body, "<p><a href=\"")
        body = concat(a, body, html_escape(a, e.url))
        body = concat(a, body, "\">")
        body = concat(a, body, html_escape(a, title))
        body = concat(a, body, "</a><br><small>")
        body = concat(a, body, html_escape(a, e.url))
        body = concat(a, body, "</small></p>")
        i += 1usize
    }
    ret body
}

fn data_url(a: *mem.Arena, html: str) -> str { ret concat(a, "data:text/html;charset=utf-8,", percent_encode(a, html)) }

fn error_page(a: *mem.Arena, address: str, reason: str) -> str {
    var h = concat(a, "<!DOCTYPE html><meta charset=utf-8><title>Can't load page</title><body style=\"font-family:sans-serif;margin:3em\"><h1>This page can't be loaded</h1><p>", html_escape(a, address))
    h = concat(a, h, "</p><p>")
    h = concat(a, h, html_escape(a, reason))
    ret concat(a, h, "</p>")
}

// The address a load actually fetches for `logical`: `about:` pages are generated here.
fn resolve_address(sh: *Shell, logical: str) -> str {
    if str.eq(logical, "about:blank") { ret data_url(sh.a, "<!DOCTYPE html><title>New tab</title>") }
    if str.eq(logical, "about:history") { ret data_url(sh.a, entries_page(sh.a, "History", sh.visits.items[0usize..sh.visits.len], true)) }
    if str.eq(logical, "about:bookmarks") { ret data_url(sh.a, entries_page(sh.a, "Bookmarks", sh.bookmarks.items[0usize..sh.bookmarks.len], false)) }
    ret logical
}

fn reason_text(e: err) -> str {
    if e == fetch.NoAddress { ret "The server could not be found." }
    if e == fetch.NetworkError { ret "The connection failed." }
    if e == fetch.BadUrl { ret "The address is not valid." }
    if e == fetch.UnsupportedScheme { ret "This kind of address is not supported." }
    if e == fetch.BlockedPort { ret "The port is blocked." }
    if e == fetch.BlockedByFilter { ret "A filter list blocks this address." }
    if e == fetch.CertificateError { ret "Your connection is not private: the server certificate is not valid for this address, so the page was not loaded." }
    if e == fetch.TooManyRedirects { ret "The server redirected too many times." }
    ret "The page could not be loaded."
}

// ---- Tabs --------------------------------------------------------------------------------------------------------------

fn active_tab(sh: *Shell) -> *Tab { ret sh.tabs.items[sh.active] }

fn tab_count(sh: *Shell) -> usize { ret sh.tabs.len }

fn current_entry(t: *Tab) -> Entry {
    if t.history.len == 0usize { ret Entry { url: "about:blank", title: "New tab", at: 0i64, count: 1u32 } }
    ret t.history.items[t.index]
}

fn tab_title(t: *Tab) -> str {
    let e = current_entry(t)
    if e.title.len > 0usize { ret e.title }
    ret e.url
}

fn dup(a: *mem.Arena, s: str) -> str {
    if s.len == 0usize { ret "" }
    let (out, e) = mem.alloc[u8](a, s.len)
    if e != ok { ret "" }
    var i = 0usize
    while i < s.len {
        out[i] = s[i]
        i += 1usize
    }
    ret out[0usize..s.len]
}

// Loads `logical` into the tab's arena (rewound first); a failed load shows an error page. Does not touch the history.
fn load_into(sh: *Shell, t: *Tab, logical: str) {
    if t.loaded {
        page.close(t.pg)
        t.loaded = false
    }
    mem.reset(&t.arena, t.mark)
    let address = resolve_address(sh, logical)
    let (pg0, e) = page.load(&t.arena, sh.client, sh.fonts, address, sh.width, sh.height, VIEW_BYTES)
    var pg = pg0
    if e != ok {
        mem.reset(&t.arena, t.mark)
        t.error_text = reason_text(e)
        let (pg2, e2) = page.load(&t.arena, sh.client, sh.fonts, data_url(sh.a, error_page(sh.a, logical, t.error_text)), sh.width, sh.height, VIEW_BYTES)
        if e2 != ok { ret }
        pg = pg2
    } else {
        t.error_text = ""
    }
    t.pg = pg
    t.loaded = true
}

const MAX_VISITS: usize = 5000usize

fn now_ms() -> i64 {
    let (t, e) = time.now()
    if e != ok { ret 0i64 }
    ret t.nanos / 1000000i64
}

// A visit is kept once per address: a revisit bumps its count and time, takes the new title and moves it to the newest end.
fn record_visit(sh: *Shell, logical: str, title: str) {
    if str.starts_with(logical, "about:") || str.starts_with(logical, "data:") { ret }
    var entry = Entry { url: dup(sh.a, logical), title: dup(sh.a, title), at: now_ms(), count: 1u32 }
    var i = 0usize
    while i < sh.visits.len {
        if str.eq(sh.visits.items[i].url, logical) {
            entry.count = sh.visits.items[i].count + 1u32
            let gone = list.remove[Entry](&sh.visits, i)
            break
        }
        i += 1usize
    }
    if sh.visits.len >= MAX_VISITS {
        let oldest = list.remove[Entry](&sh.visits, 0usize)
    }
    let pe = list.push[Entry](&sh.visits, entry)
}

fn fold_byte(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn contains_fold(hay: str, needle: str) -> bool {
    if needle.len == 0usize { ret true }
    var i = 0usize
    while i + needle.len <= hay.len {
        var k = 0usize
        while k < needle.len && fold_byte(hay[i + k]) == fold_byte(needle[k]) { k += 1usize }
        if k == needle.len { ret true }
        i += 1usize
    }
    ret false
}

// The visits whose address or title contains `needle` (any case), newest first.
fn search_visits(sh: *Shell, needle: str) -> []const Entry {
    let (out, e) = mem.alloc[Entry](sh.a, sh.visits.len + 1usize)
    if e != ok { ret zero }
    var n = 0usize
    var i = sh.visits.len
    while i > 0usize {
        i -= 1usize
        let v = sh.visits.items[i]
        if contains_fold(v.url, needle) || contains_fold(v.title, needle) {
            out[n] = v
            n += 1usize
        }
    }
    ret out[0usize..n]
}

fn delete_visit(sh: *Shell, address: str) -> bool {
    var i = 0usize
    while i < sh.visits.len {
        if str.eq(sh.visits.items[i].url, address) {
            let gone = list.remove[Entry](&sh.visits, i)
            ret true
        }
        i += 1usize
    }
    ret false
}

fn clear_visits(sh: *Shell) { list.clear[Entry](&sh.visits) }

// Navigates `t` to what the omnibox makes of `input`, cutting the forward history.
fn navigate(sh: *Shell, t: *Tab, input: str) -> err {
    let logical = omnibox_url(sh.a, input)
    if str.starts_with(logical, "javascript:") { ret fetch.UnsupportedScheme }
    load_into(sh, t, logical)
    if !t.loaded { ret NoSuchTab }
    var title = t.pg.title
    var final_url = logical
    if !str.starts_with(logical, "about:") { final_url = t.pg.url }
    if t.history.len > 0usize { t.history.len = t.index + 1usize }
    let pe = list.push[Entry](&t.history, Entry { url: dup(sh.a, final_url), title: dup(sh.a, title), at: 0i64, count: 1u32 })
    if pe != ok { ret pe }
    t.index = t.history.len - 1usize
    record_visit(sh, final_url, title)
    ret ok
}

fn open_tab(sh: *Shell, input: str) -> (*Tab, err) {
    if sh.tabs.len >= MAX_TABS { ret (zero, TooManyTabs) }
    let (cell, ce) = mem.alloc[Tab](sh.a, 1usize)
    if ce != ok { ret (zero, ce) }
    let (backing, be) = mem.alloc[u8](sh.a, TAB_ARENA_BYTES)
    if be != ok { ret (zero, be) }
    let (hl, he) = list.init[Entry](sh.a, 16usize)
    if he != ok { ret (zero, he) }
    let t = &cell[0usize]
    t.id = sh.next_id
    sh.next_id += 1u32
    t.arena = mem.arena_from(backing)
    t.mark = mem.mark(&t.arena)
    t.loaded = false
    t.history = hl
    t.index = 0usize
    t.error_text = ""
    let pe = list.push[*Tab](&sh.tabs, t)
    if pe != ok { ret (zero, pe) }
    sh.active = sh.tabs.len - 1usize
    let ne = navigate(sh, t, input)
    ret (t, ne)
}

fn select_tab(sh: *Shell, index: usize) -> err {
    if index >= sh.tabs.len { ret NoSuchTab }
    sh.active = index
    ret ok
}

fn close_tab(sh: *Shell, index: usize) -> err {
    if index >= sh.tabs.len { ret NoSuchTab }
    let t = sh.tabs.items[index]
    if t.loaded { page.close(t.pg) }
    var i = index
    while i + 1usize < sh.tabs.len {
        sh.tabs.items[i] = sh.tabs.items[i + 1usize]
        i += 1usize
    }
    sh.tabs.len -= 1usize
    if sh.active >= sh.tabs.len && sh.tabs.len > 0usize { sh.active = sh.tabs.len - 1usize }
    ret ok
}

fn can_go_back(t: *Tab) -> bool { ret t.index > 0usize }
fn can_go_forward(t: *Tab) -> bool { ret t.history.len > 0usize && t.index + 1usize < t.history.len }

fn go_back(sh: *Shell, t: *Tab) -> bool {
    if !can_go_back(t) { ret false }
    t.index -= 1usize
    load_into(sh, t, t.history.items[t.index].url)
    ret true
}

fn go_forward(sh: *Shell, t: *Tab) -> bool {
    if !can_go_forward(t) { ret false }
    t.index += 1usize
    load_into(sh, t, t.history.items[t.index].url)
    ret true
}

fn reload(sh: *Shell, t: *Tab) {
    load_into(sh, t, current_entry(t).url)
}

// A link the page's scripts or a click asked to follow, if any: navigates there.
fn follow_pending(sh: *Shell, t: *Tab) -> bool {
    if !t.loaded { ret false }
    let (dest, asked) = page.take_navigation(t.pg)
    if !asked { ret false }
    let (abs, good) = page.resolve_against(sh.a, &t.pg.base, dest)
    if !good { ret false }
    let ne = navigate(sh, t, abs)
    ret ne == ok
}

// ---- Bookmarks and the profile -----------------------------------------------------------------------------------------

fn bookmark_index(sh: *Shell, address: str) -> (usize, bool) {
    var i = 0usize
    while i < sh.bookmarks.len {
        if str.eq(sh.bookmarks.items[i].url, address) { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

fn is_bookmarked(sh: *Shell, t: *Tab) -> bool {
    let (at, found) = bookmark_index(sh, current_entry(t).url)
    ret found
}

// Adds the tab's page to the bookmarks, or removes it when it is already there; true when it was added.
fn toggle_bookmark(sh: *Shell, t: *Tab) -> bool {
    let e = current_entry(t)
    let (at, found) = bookmark_index(sh, e.url)
    if found {
        var i = at
        while i + 1usize < sh.bookmarks.len {
            sh.bookmarks.items[i] = sh.bookmarks.items[i + 1usize]
            i += 1usize
        }
        sh.bookmarks.len -= 1usize
        ret false
    }
    let pe = list.push[Entry](&sh.bookmarks, e)
    ret true
}

fn clean_field(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret "" }
    var i = 0usize
    while i < s.len {
        var c = s[i]
        if c == 9u8 || c == 10u8 || c == 13u8 { c = 32u8 }
        out[i] = c
        i += 1usize
    }
    ret out[0usize..s.len]
}

fn write_entries(a: *mem.Arena, label: str, entries: []const Entry, out: str) -> str {
    var text = out
    var i = 0usize
    while i < entries.len {
        text = concat(a, text, label)
        text = concat(a, text, "\t")
        text = concat(a, text, clean_field(a, entries[i].url))
        text = concat(a, text, "\t")
        text = concat(a, text, clean_field(a, entries[i].title))
        if str.eq(label, "V") {
            text = concat(a, text, "\t")
            text = concat(a, text, i64_text(a, entries[i].at))
            text = concat(a, text, "\t")
            text = concat(a, text, i64_text(a, i64(entries[i].count)))
        }
        text = concat(a, text, "\n")
        i += 1usize
    }
    ret text
}

// The profile as text: one `B` (bookmark) or `V` (visit) line per entry, fields separated by tabs.
fn profile_text(sh: *Shell) -> str {
    var text = write_entries(sh.a, "B", sh.bookmarks.items[0usize..sh.bookmarks.len], "")
    text = write_entries(sh.a, "V", sh.visits.items[0usize..sh.visits.len], text)
    ret text
}

fn load_profile_text(sh: *Shell, text: str) -> err {
    var pos = 0usize
    while pos < text.len {
        var end = pos
        while end < text.len && text[end] != 10u8 { end += 1usize }
        let line = text[pos..end]
        pos = end + 1usize
        if line.len == 0usize { continue }
        let (kind, rest, f1) = str.split_once(line, "\t")
        if !f1 { ret BadProfile }
        let (u, tail, f2) = str.split_once(rest, "\t")
        if !f2 { ret BadProfile }
        // A visit line may carry its time and count after the title; older profiles do not.
        let (title, stats, has_stats) = str.split_once(tail, "\t")
        var entry = Entry { url: dup(sh.a, u), title: dup(sh.a, tail), at: 0i64, count: 1u32 }
        if has_stats {
            entry.title = dup(sh.a, title)
            let (at_text, count_text, has_count) = str.split_once(stats, "\t")
            let (at_n, at_e) = str.parse_i64(at_text)
            if at_e == ok { entry.at = at_n }
            if has_count {
                let (cn, ce) = str.parse_i64(count_text)
                if ce == ok && cn > 0i64 { entry.count = u32(cn) }
            }
        }
        if str.eq(kind, "B") {
            let pe = list.push[Entry](&sh.bookmarks, entry)
        } else if str.eq(kind, "V") {
            let pe2 = list.push[Entry](&sh.visits, entry)
        } else {
            ret BadProfile
        }
    }
    ret ok
}

fn save_profile(sh: *Shell, path: str) -> err {
    ret fs.write_file(sh.a, path, profile_text(sh))
}

fn load_profile(sh: *Shell, path: str) -> err {
    let (text, e) = fs.read_file(sh.a, path, 16777216usize)
    if e != ok { ret e }
    ret load_profile_text(sh, text)
}

fn i64_text(a: *mem.Arena, n: i64) -> str {
    if n == 0i64 { ret "0" }
    var digits: [24]u8 = zero
    var at = 24usize
    var v = n
    var neg = false
    if v < 0i64 {
        neg = true
        v = -v
    }
    while v > 0i64 && at > 1usize {
        at -= 1usize
        digits[at] = u8(48i64 + v % 10i64)
        v = v / 10i64
    }
    if neg {
        at -= 1usize
        digits[at] = 45u8
    }
    let (out, e) = mem.alloc[u8](a, 24usize - at)
    if e != ok { ret "" }
    mem.copy[u8](out, digits[at..])
    ret out
}
