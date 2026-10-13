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
use e.fmt.html as html
use e.fmt.png
use e.fmt.jpeg
use e.gfx.image
use e.io
use e.data.list as list
use e.fmt.css.syntax as syntax
use e.fmt.css.selector as selector
use e.fmt.css.match as match
use e.fmt.css.cascade as cascade
use e.gfx.cssvalue as cssvalue
use appkit
use text
use ui
use scenes
use httpc
use sysettings
use vaultfs
use e.time
use e.net.cookie as cookie

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
// (C129) A page fetched over the network: LIVE_BASE plus its slot in the address table.
const LIVE_BASE: usize = 100usize
const URLS: usize = 8usize
const PAGE_LINES: usize = 64usize
const KIND_BODY: usize = 0usize
const KIND_H1: usize = 1usize
const KIND_H2: usize = 2usize
const KIND_LINK: usize = 3usize
const KIND_BULLET: usize = 4usize
const KIND_PRE: usize = 5usize
const KIND_IMAGE: usize = 6usize
// (C159) A form field shown on the page (its `aux` is the field's index) and a form's Submit (its `aux` is 1 for POST).
const KIND_FIELD: usize = 7usize
const KIND_SUBMIT: usize = 8usize
const FIELD_SCREEN: usize = 3usize

type Tab = struct {
    pages: [10]usize,
    count: usize,
    at: usize,
    query: [32]u8,
    query_len: usize,
    used: bool,
}

// A line of the loaded page: its text (wrapped to what a line holds), its kind and the link it leads to.
// (C159) The line's style from the stylesheet: a colour (ARGB), a size in px (0 for the default), bold, centred.
type PageLine = struct { text: [56]u8, len: usize, kind: usize, href: [48]u8, href_len: usize, aux: usize, has_color: bool, color: u32, px: usize, bold: bool, center: bool }

// (C159) The style rules of the page's <style> elements as cascade rules, and the matcher over its document.
type Styler = struct { m: match.Matcher, author: []const cascade.Rule, active: bool }

type Url = struct { host: [40]u8, host_len: usize, path: [64]u8, path_len: usize, used: bool }

type State = struct {
    // (C129) The addresses of the pages fetched, the page now loaded (its lines, which address it is, how far it
    // is scrolled, its title) and what is being gathered while a document is read.
    urls: [8]Url,
    url_total: usize,
    page: [64]PageLine,
    page_total: usize,
    loaded: usize,
    scroll: usize,
    title: [40]u8,
    title_len: usize,
    load_error: usize,
    cur: [56]u8,
    cur_len: usize,
    pending_space: bool,
    tabs: [4]Tab,
    tab_total: usize,
    current: usize,
    screen: usize,
    typed: ui.Field,
    // (C159) The cookie jar: its entries and their strings are kept here, so they outlive each frame's arena.
    cookie_store: [16]cookie.Cookie,
    cookie_text: [2048]u8,
    jar: cookie.Jar,
    // (C159) The form being read (its action and method) and its fields (name, value, hidden or shown): the query or
    // body is made from them when the form is submitted, so a field edited on the page goes with its new value.
    form_open: bool,
    form_post: bool,
    form_action: [40]u8,
    form_action_len: usize,
    fields: [6]Field,
    field_total: usize,
    // The field being edited on the field screen, and what has been typed into it.
    edit_field: usize,
    edit: ui.Field,
    // (C159) The first two images of the page: each an SVG kept as text or a PNG or JPEG decoded into a texture, and
    // the page line it stands at.
    images: [2]PageImage,
    // (C159) Revalidation: the last pages fetched with an ETag, so a later request can ask `If-None-Match`.
    cache: [4]CacheEntry,
    cache_next: usize,
    // (C159) The style in force while a document is read (colour, size, bold, centred), copied into each line made.
    st_has_color: bool,
    st_color: u32,
    st_px: usize,
    st_bold: bool,
    st_center: bool,
    // (C159) What /browser_tabs holds now, so it is written only when the tabs change.
    tabs_saved: [320]u8,
    tabs_saved_len: usize,
    // (C159) Bookmarks: up to four addresses (host and path), kept in /bookmarks, shown on the start page; and the
    // program a downloaded file was handed over to (Document is 40), with which the app leaves.
    marks: [4][48]u8,
    mark_len: [4]usize,
    mark_total: usize,
    handover: usize,
    hits: ui.Hits,
}

// (C159) A field of the form being read: its name, its value (24 bytes) and whether the page shows it.
type Field = struct { name: [16]u8, name_len: usize, value: [24]u8, value_len: usize, hidden: bool }

// (C159) An image of the page: its page line, how it is kept (0 none, 1 SVG text, 2 texture) and its size.
type PageImage = struct { line: usize, kind: usize, svg: [1536]u8, svg_len: usize, tex: scene.TextureId, w: f32, h: f32 }

// (C159) A page kept with its validator: the address, the ETag and the body (up to 3 KB).
type CacheEntry = struct { host: [40]u8, host_len: usize, path: [64]u8, path_len: usize, etag: [40]u8, etag_len: usize, body: [3072]u8, body_len: usize, used: bool }

fn page_host(page: usize) -> str {
    if page >= LIVE_BASE { ret "Web page" }
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

// ----------------------------------------------------------------------------------------------
// Live pages: fetched over HTTPS, parsed as HTML and laid out as lines of text.

fn limit_of(kind: usize) -> usize {
    if kind == KIND_H1 { ret 24usize }
    if kind == KIND_H2 { ret 30usize }
    if kind == KIND_LINK { ret 40usize }
    if kind == KIND_PRE { ret 52usize }
    ret 46usize
}

// End the line being gathered: it becomes a line of the page.
fn flush_line(s: *State, kind: usize, href: str) {
    flush_line_aux(s, kind, href, 0usize)
}

// The same with the line's `aux`: the field it shows or the method of the form it submits.
fn flush_line_aux(s: *State, kind: usize, href: str, aux: usize) {
    if s.cur_len == 0usize { ret }
    if s.page_total < PAGE_LINES {
        var line: PageLine = zero
        var i = 0usize
        while i < s.cur_len && i < 56usize {
            line.text[i] = s.cur[i]
            i += 1usize
        }
        line.len = i
        line.kind = kind
        var h = 0usize
        while h < href.len && h < 48usize {
            line.href[h] = href[h]
            h += 1usize
        }
        line.href_len = h
        line.aux = aux
        line.has_color = s.st_has_color
        line.color = s.st_color
        line.px = s.st_px
        line.bold = s.st_bold
        line.center = s.st_center
        s.page[s.page_total] = line
        s.page_total += 1usize
    }
    s.cur_len = 0usize
    s.pending_space = false
}

// Add text to the line being gathered: whitespace collapses to one space and a line breaks at its limit.
fn add_text(s: *State, text_in: str, kind: usize, href: str) {
    var limit = limit_of(kind)
    // (C159) A larger font-size holds fewer characters to a line.
    if s.st_px > 17usize && kind != KIND_H1 && kind != KIND_H2 {
        limit = limit * 17usize / s.st_px
        if limit < 8usize { limit = 8usize }
    }
    var i = 0usize
    while i < text_in.len {
        let c = text_in[i]
        if c == 32u8 || c == 10u8 || c == 13u8 || c == 9u8 {
            if s.cur_len > 0usize { s.pending_space = true }
            i += 1usize
        } else {
            // A word, up to the next whitespace.
            var end = i
            while end < text_in.len && text_in[end] != 32u8 && text_in[end] != 10u8 && text_in[end] != 13u8 && text_in[end] != 9u8 { end += 1usize }
            var word_len = end - i
            // Break long words at the limit.
            while word_len > 0usize {
                var room = limit - s.cur_len
                var need = word_len
                if s.pending_space && s.cur_len > 0usize { need += 1usize }
                if need > room && s.cur_len > 0usize {
                    flush_line(s, kind, href)
                    room = limit
                }
                var take = word_len
                if take > limit { take = limit }
                if s.pending_space && s.cur_len > 0usize && s.cur_len < 55usize {
                    s.cur[s.cur_len] = 32u8
                    s.cur_len += 1usize
                }
                s.pending_space = false
                var k = 0usize
                while k < take && s.cur_len < 56usize {
                    s.cur[s.cur_len] = text_in[i + k]
                    s.cur_len += 1usize
                    k += 1usize
                }
                i += take
                word_len -= take
                if word_len > 0usize { flush_line(s, kind, href) }
            }
        }
    }
}

fn is_block(name: str) -> bool {
    ret ui.same(name, "p") || ui.same(name, "div") || ui.same(name, "ul") || ui.same(name, "ol") || ui.same(name, "li") || ui.same(name, "br") || ui.same(name, "section") || ui.same(name, "article") || ui.same(name, "header") || ui.same(name, "footer") || ui.same(name, "nav") || ui.same(name, "main") || ui.same(name, "table") || ui.same(name, "tr") || ui.same(name, "hr") || ui.same(name, "blockquote") || ui.same(name, "pre") || ui.same(name, "h1") || ui.same(name, "h2") || ui.same(name, "h3") || ui.same(name, "h4") || ui.same(name, "h5") || ui.same(name, "h6")
}

fn unreserved(c: u8) -> bool {
    ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 45u8 || c == 46u8 || c == 95u8 || c == 126u8
}

fn hex_char(n: usize) -> u8 {
    if n < 10usize { ret u8(48usize + n) }
    ret u8(55usize + n)
}

// (C159) How many bytes `piece` takes in a query string: a space is `+`, anything else not plain is `%XX`.
fn query_size(piece: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i < piece.len {
        if unreserved(piece[i]) || piece[i] == 32u8 { n += 1usize } else { n += 3usize }
        i += 1usize
    }
    ret n
}

// (C159) `piece` percent-encoded into `out` from `at` (a space is `+`); the new end. The caller has checked the room.
fn query_piece(out: []u8, at: usize, piece: str) -> usize {
    var n = at
    var i = 0usize
    while i < piece.len {
        let c = piece[i]
        if unreserved(c) {
            out[n] = c
            n += 1usize
        } else if c == 32u8 {
            out[n] = 43u8
            n += 1usize
        } else {
            out[n] = 37u8
            out[n + 1usize] = hex_char(usize(c >> 4u8))
            out[n + 2usize] = hex_char(usize(c & 15u8))
            n += 3usize
        }
        i += 1usize
    }
    ret n
}

// (C159) The `name=value&...` query of the form's fields (hidden ones too) in `out`: its length. A pair that does not
// fit is dropped whole.
fn make_query(s: *State, out: []u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < s.field_total {
        let f = &s.fields[i]
        let field_name: str = f.name[0usize..f.name_len]
        let field_value: str = f.value[0usize..f.value_len]
        var need = query_size(field_name) + 1usize + query_size(field_value)
        if n > 0usize { need += 1usize }
        if n + need <= out.len {
            if n > 0usize {
                out[n] = 38u8
                n += 1usize
            }
            n = query_piece(out, n, field_name)
            out[n] = 61u8
            n += 1usize
            n = query_piece(out, n, field_value)
        }
        i += 1usize
    }
    ret n
}

// (C159) The author rules of the document's <style> elements: each qualified rule's selectors (any pseudo-element one
// left out) with its declarations, in source order.
fn style_rules(a: *mem.Arena, doc: *const html.Document) -> []const cascade.Rule {
    let (made, made_error) = list.init[cascade.Rule](a, 8usize)
    if made_error != ok {
        var none: []const cascade.Rule = zero
        ret none
    }
    var out = made
    var order = 0i64
    var i = 0usize
    while i < doc.nodes.len {
        let n = doc.nodes[i]
        if n.kind == .Element && ui.same(n.name, "style") {
            let (source, source_error) = html.text_content(a, doc, u32(i))
            if source_error == ok && source.len <= 4096usize {
                let (tokens, token_error) = syntax.tokenize(a, source)
                if token_error == ok {
                    let (rules, rules_error) = syntax.parse_rules(a, tokens, true)
                    if rules_error == ok {
                        var r = 0usize
                        while r < rules.len {
                            let one = rules[r]
                            if !one.at && one.has_block {
                                let (chosen, chosen_error) = selector.parse_selector_list_for_rule(a, source, one.prelude)
                                let (parsed, parsed_error) = syntax.parse_declarations(a, one.block.inner)
                                if chosen_error == ok && parsed_error == ok {
                                    let (decls, decls_error) = mem.alloc[cascade.Declaration](a, parsed.len + 1usize)
                                    if decls_error == ok {
                                        var d = 0usize
                                        while d < parsed.len {
                                            decls[d] = cascade.Declaration { property: cssvalue.lower(a, parsed[d].name), value: cssvalue.trim_ws(syntax.raw_text(source, parsed[d].value)), important: parsed[d].important }
                                            d += 1usize
                                        }
                                        var q = 0usize
                                        while q < chosen.len {
                                            if !chosen[q].has_pseudo {
                                                let pushed = list.push[cascade.Rule](&out, cascade.Rule { selector: chosen[q].selector, declarations: decls[0usize..parsed.len], source: order, has_layer: false, layer: 0i64, containers: zero, scopes: zero })
                                                order += 1i64
                                            }
                                            q += 1usize
                                        }
                                    }
                                }
                            }
                            r += 1usize
                        }
                    }
                }
            }
        }
        i += 1usize
    }
    ret list.slice_const[cascade.Rule](&out)
}

// (C159) The property `name` among the winners of the cascade.
fn winner_value(ws: []const cascade.Winner, name: str) -> (str, bool) {
    var i = 0usize
    while i < ws.len {
        if ui.same(ws[i].property, name) { ret (ws[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

// Walk the element or text `id` with the style of the page's stylesheet applied: the cascade gives the element's
// winning declarations (the author rules, the element's `style` attribute and the presentational hints), `display:
// none` drops it, and colour, font-size, font-weight and text-align are inherited down the tree into the lines made.
fn walk(a: *mem.Arena, s: *State, st: *Styler, doc: *const html.Document, id: html.NodeId, kind: usize, href: str) {
    let n = html.node(doc, id)
    if n.kind != .Element || !st.active {
        walk_node(a, s, st, doc, id, kind, href)
        ret
    }
    var inline: []const cascade.Declaration = zero
    let (style_attr, has_style) = html.attribute(n, "style")
    if has_style { inline = cascade.inline_declarations(a, style_attr) }
    var no_rules: []const cascade.Rule = zero
    var no_stack: []const cascade.ContainerBox = zero
    let winners = cascade.resolve(&st.m, no_rules, st.author, id, no_stack, inline)
    let (display, has_display) = winner_value(winners, "display")
    if has_display && ui.same(display, "none") { ret }
    let had_color = s.st_has_color
    let old_color = s.st_color
    let old_px = s.st_px
    let old_bold = s.st_bold
    let old_center = s.st_center
    let (color_text, has_color) = winner_value(winners, "color")
    if has_color {
        let (argb, color_ok) = cssvalue.parse_color(a, color_text)
        if color_ok {
            s.st_has_color = true
            s.st_color = argb
        }
    }
    let (size_text, has_size) = winner_value(winners, "font-size")
    if has_size {
        let bases = cssvalue.Bases { has_em: true, em: 16.0f64, has_rem: true, rem: 16.0f64, has_percent: true, percent: 16.0f64, has_viewport_width: false, viewport_width: 0.0f64, has_viewport_height: false, viewport_height: 0.0f64 }
        let (length, length_ok) = cssvalue.parse_length(a, size_text, bases)
        if length_ok {
            let (px, px_ok) = cssvalue.to_px(length, bases)
            if px_ok && px >= 8.0f64 && px <= 64.0f64 { s.st_px = usize(px) }
        }
    }
    let (weight, has_weight) = winner_value(winners, "font-weight")
    if has_weight && (ui.same(weight, "bold") || ui.same(weight, "700") || ui.same(weight, "800") || ui.same(weight, "900")) { s.st_bold = true }
    let (align, has_align) = winner_value(winners, "text-align")
    if has_align && ui.same(align, "center") { s.st_center = true }
    let changed = s.st_has_color != had_color || s.st_color != old_color || s.st_px != old_px || s.st_bold != old_bold || s.st_center != old_center
    var inner_kind = kind
    if kind == KIND_BODY && s.st_px >= 28usize { inner_kind = KIND_H1 } else if kind == KIND_BODY && s.st_px >= 21usize { inner_kind = KIND_H2 }
    if changed {
        // What was gathered so far keeps the style it was read under.
        let now_color = s.st_color
        let now_has = s.st_has_color
        let now_px = s.st_px
        let now_bold = s.st_bold
        let now_center = s.st_center
        s.st_color = old_color
        s.st_has_color = had_color
        s.st_px = old_px
        s.st_bold = old_bold
        s.st_center = old_center
        flush_line(s, kind, href)
        s.st_color = now_color
        s.st_has_color = now_has
        s.st_px = now_px
        s.st_bold = now_bold
        s.st_center = now_center
    }
    walk_node(a, s, st, doc, id, inner_kind, href)
    if changed {
        flush_line(s, inner_kind, href)
        s.st_has_color = had_color
        s.st_color = old_color
        s.st_px = old_px
        s.st_bold = old_bold
        s.st_center = old_center
    }
}

// The document below `id`, gathering lines. `kind` and `href` come from the elements around.
fn walk_node(a: *mem.Arena, s: *State, st: *Styler, doc: *const html.Document, id: html.NodeId, kind: usize, href: str) {
    let n = html.node(doc, id)
    if n.kind == .Text {
        add_text(s, n.value, kind, href)
        ret
    }
    if n.kind != .Element && n.kind != .Document { ret }
    var child_kind = kind
    var child_href = href
    if n.kind == .Element {
        let name = n.name
        if ui.same(name, "script") || ui.same(name, "style") || ui.same(name, "head") { ret }
        if ui.same(name, "title") { ret }
        if is_block(name) { flush_line(s, kind, href) }
        if ui.same(name, "h1") { child_kind = KIND_H1 }
        if ui.same(name, "h2") || ui.same(name, "h3") || ui.same(name, "h4") || ui.same(name, "h5") || ui.same(name, "h6") { child_kind = KIND_H2 }
        if ui.same(name, "pre") { child_kind = KIND_PRE }
        if ui.same(name, "li") {
            child_kind = KIND_BULLET
            add_text(s, "-", KIND_BULLET, "")
        }
        // (C159) A form: its fields are shown as `name: value` lines (a tap edits one) and are kept in the state; its
        // end is a Submit line that makes the query (GET) or the body (POST) from the fields as they are then.
        if ui.same(name, "form") {
            flush_line(s, kind, href)
            s.form_open = true
            s.form_post = false
            s.field_total = 0usize
            s.form_action_len = 0usize
            let (action, has_action) = html.attribute(n, "action")
            if has_action {
                var k = 0usize
                while k < action.len && k < 40usize {
                    s.form_action[k] = action[k]
                    k += 1usize
                }
                s.form_action_len = k
            }
            let (method, has_method) = html.attribute(n, "method")
            if has_method && ui.same(method, "post") { s.form_post = true }
        }
        if ui.same(name, "input") && s.form_open {
            let (field, has_field) = html.attribute(n, "name")
            let (given, has_given) = html.attribute(n, "value")
            let (input_type, has_type) = html.attribute(n, "type")
            var pressed = false
            var hidden = false
            if has_type && (ui.same(input_type, "submit") || ui.same(input_type, "button")) { pressed = true }
            if has_type && ui.same(input_type, "hidden") { hidden = true }
            if has_field && !pressed && s.field_total < 6usize {
                var current_value = ""
                if has_given { current_value = given }
                var entry: Field = zero
                var k = 0usize
                while k < field.len && k < 16usize {
                    entry.name[k] = field[k]
                    k += 1usize
                }
                entry.name_len = k
                k = 0usize
                while k < current_value.len && k < 24usize {
                    entry.value[k] = current_value[k]
                    k += 1usize
                }
                entry.value_len = k
                entry.hidden = hidden
                let index = s.field_total
                s.fields[index] = entry
                s.field_total += 1usize
                if !hidden {
                    flush_line(s, kind, href)
                    add_text(s, field, KIND_FIELD, "")
                    add_text(s, ":", KIND_FIELD, "")
                    add_text(s, current_value, KIND_FIELD, "")
                    flush_line_aux(s, KIND_FIELD, "", index)
                }
            }
        }
        // (C159) An image is a line the page shows as the picture when it could be fetched, its alt text otherwise.
        if ui.same(name, "img") {
            let (source, has_source) = html.attribute(n, "src")
            let (alt, has_alt) = html.attribute(n, "alt")
            if has_source {
                flush_line(s, kind, href)
                var caption = "image"
                if has_alt && alt.len > 0usize { caption = alt }
                add_text(s, caption, KIND_IMAGE, source)
                flush_line(s, KIND_IMAGE, source)
            }
        }
        if ui.same(name, "a") {
            let (destination, has_destination) = html.attribute(n, "href")
            if has_destination {
                flush_line(s, kind, href)
                child_kind = KIND_LINK
                child_href = destination
            }
        }
    }
    var it = html.children(doc, id)
    var more = true
    while more {
        let (child, has_child) = html.children_next(&it)
        if !has_child { more = false } else { walk(a, s, st, doc, child, child_kind, child_href) }
    }
    if n.kind == .Element {
        if is_block(n.name) || ui.same(n.name, "a") { flush_line(s, child_kind, child_href) }
        if ui.same(n.name, "form") && s.form_open {
            flush_line(s, kind, href)
            s.form_open = false
            // The Submit line: its href is the form's action, its aux 1 for POST.
            var method_aux = 0usize
            if s.form_post { method_aux = 1usize }
            add_text(s, "Submit", KIND_SUBMIT, s.form_action[0usize..s.form_action_len])
            flush_line_aux(s, KIND_SUBMIT, s.form_action[0usize..s.form_action_len], method_aux)
        }
    }
}

// The page title: the text of the first <title>.
fn find_title(a: *mem.Arena, s: *State, doc: *const html.Document) {
    var i = 0usize
    while i < doc.nodes.len {
        let n = doc.nodes[i]
        if n.kind == .Element && ui.same(n.name, "title") {
            let (value, value_error) = html.text_content(a, doc, u32(i))
            if value_error == ok {
                var k = 0usize
                while k < value.len && k < 40usize {
                    s.title[k] = value[k]
                    k += 1usize
                }
                s.title_len = k
            }
            ret
        }
        i += 1usize
    }
}

// The jar is kept in /cookies: a version byte, a count, then per cookie the lengths of name, value, domain and path (a
// byte each), flags (secure 1, http-only 2, host-only 4, same-site << 3), the expiry and creation seconds (four bytes
// each, little end) and the four strings. Session cookies (no expiry) are not kept.
fn save_jar(s: *State) {
    var buf: [2048]u8 = zero
    buf[0usize] = 1u8
    var n = 2usize
    var kept = 0usize
    var i = 0usize
    while i < s.jar.count {
        let c = s.jar.cookies[i]
        let need = 14usize + c.name.len + c.value.len + c.domain.len + c.path.len
        if c.has_expires && c.expires > 0i64 && c.name.len < 256usize && c.value.len < 256usize && c.domain.len < 256usize && c.path.len < 256usize && n + need <= 2048usize {
            buf[n] = u8(c.name.len)
            buf[n + 1usize] = u8(c.value.len)
            buf[n + 2usize] = u8(c.domain.len)
            buf[n + 3usize] = u8(c.path.len)
            var flags = 0usize
            if c.secure { flags = flags | 1usize }
            if c.http_only { flags = flags | 2usize }
            if c.host_only { flags = flags | 4usize }
            if c.same_site == .Lax { flags = flags | 8usize }
            if c.same_site == .Strict { flags = flags | 16usize }
            if c.same_site == .None { flags = flags | 24usize }
            buf[n + 4usize] = u8(flags)
            var b = 0usize
            let expires = usize(c.expires)
            let created = usize(c.created)
            while b < 4usize {
                buf[n + 5usize + b] = u8((expires >> (8usize * b)) & 255usize)
                buf[n + 9usize + b] = u8((created >> (8usize * b)) & 255usize)
                b += 1usize
            }
            n += 13usize
            var p = 0usize
            while p < c.name.len {
                buf[n + p] = c.name[p]
                p += 1usize
            }
            n += c.name.len
            p = 0usize
            while p < c.value.len {
                buf[n + p] = c.value[p]
                p += 1usize
            }
            n += c.value.len
            p = 0usize
            while p < c.domain.len {
                buf[n + p] = c.domain[p]
                p += 1usize
            }
            n += c.domain.len
            p = 0usize
            while p < c.path.len {
                buf[n + p] = c.path[p]
                p += 1usize
            }
            n += c.path.len
            kept += 1usize
        }
        i += 1usize
    }
    buf[1usize] = u8(kept)
    let written = vaultfs.write_big("/cookies", mem.address_of(&buf[0usize]), n)
}

// Read /cookies into the jar (expired cookies are dropped as they are stored).
fn load_jar(s: *State, now: i64) -> usize {
    var buf: [2048]u8 = zero
    let (n, found) = vaultfs.read_big("/cookies", mem.address_of(&buf[0usize]), 2048usize)
    if !found || n < 2usize || buf[0usize] != 1u8 { ret 0usize }
    let count = usize(buf[1usize])
    var at = 2usize
    var loaded = 0usize
    var k = 0usize
    while k < count && at + 13usize <= n {
        let name_len = usize(buf[at])
        let value_len = usize(buf[at + 1usize])
        let domain_len = usize(buf[at + 2usize])
        let path_len = usize(buf[at + 3usize])
        let flags = usize(buf[at + 4usize])
        var expires = 0usize
        var created = 0usize
        var b = 0usize
        while b < 4usize {
            expires = expires | (usize(buf[at + 5usize + b]) << (8usize * b))
            created = created | (usize(buf[at + 9usize + b]) << (8usize * b))
            b += 1usize
        }
        let start = at + 13usize
        if start + name_len + value_len + domain_len + path_len > n { ret loaded }
        var c: cookie.Cookie = zero
        c.name = buf[start..start + name_len]
        c.value = buf[start + name_len..start + name_len + value_len]
        c.domain = buf[start + name_len + value_len..start + name_len + value_len + domain_len]
        c.path = buf[start + name_len + value_len + domain_len..start + name_len + value_len + domain_len + path_len]
        c.secure = (flags & 1usize) != 0usize
        c.http_only = (flags & 2usize) != 0usize
        c.host_only = (flags & 4usize) != 0usize
        let site = (flags >> 3usize) & 3usize
        if site == 1usize { c.same_site = .Lax }
        if site == 2usize { c.same_site = .Strict }
        if site == 3usize { c.same_site = .None }
        c.has_expires = true
        c.expires = i64(expires)
        c.created = i64(created)
        if cookie.store(&s.jar, c, now) == ok { loaded += 1usize }
        at = start + name_len + value_len + domain_len + path_len
        k += 1usize
    }
    ret loaded
}

// The wall clock's second.
fn wall_seconds() -> i64 {
    let (wall, wall_error) = time.now()
    if wall_error != ok || wall.nanos < 0i64 { ret 0i64 }
    ret wall.nanos / 1000000000i64
}

fn fold_byte(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

// Whether `line` starts with the header name `name` (compared without regard to case).
fn header_is(line: str, name: str) -> bool {
    if line.len < name.len { ret false }
    var i = 0usize
    while i < name.len {
        if fold_byte(line[i]) != name[i] { ret false }
        i += 1usize
    }
    ret true
}

// Every Set-Cookie of a response's header block goes into the jar.
fn absorb_cookies(a: *mem.Arena, s: *State, head: str, host: str, path: str, now: i64) -> usize {
    var stored = 0usize
    var at = 0usize
    while at < head.len {
        var end = at
        while end < head.len && head[end] != 10u8 { end += 1usize }
        var line_end = end
        if line_end > at && head[line_end - 1usize] == 13u8 { line_end -= 1usize }
        let line = head[at..line_end]
        if header_is(line, "set-cookie:") {
            let (parsed, parse_error) = cookie.parse(a, line[11usize..line.len], host, path, true, now)
            if parse_error == ok {
                if cookie.store(&s.jar, parsed, now) == ok { stored += 1usize }
            }
        }
        at = end + 1usize
    }
    ret stored
}

// The value of the header `name` (lower case, with its colon) in a response's header block, trimmed.
fn header_value(head: str, name: str) -> (str, bool) {
    var at = 0usize
    while at < head.len {
        var end = at
        while end < head.len && head[end] != 10u8 { end += 1usize }
        var line_end = end
        if line_end > at && head[line_end - 1usize] == 13u8 { line_end -= 1usize }
        let line = head[at..line_end]
        if header_is(line, name) {
            var from = name.len
            while from < line.len && (line[from] == 32u8 || line[from] == 9u8) { from += 1usize }
            ret (line[from..line.len], true)
        }
        at = end + 1usize
    }
    ret ("", false)
}

// GET with the jar's cookies, absorbing what each response sets and following up to five redirects (a `Location` that
// is a path on the same host or an absolute https address): the final reply and the host and path it came from.
fn fetch_following(a: *mem.Arena, s: *State, host: str, path: str, now: i64) -> (httpc.Reply, str, str, err) {
    let (reply, final_host, final_path, fetch_error) = fetch_with(a, s, host, path, now, "", false, "")
    ret (reply, final_host, final_path, fetch_error)
}

// The same with `validator` (header lines for the first request: `If-None-Match`) and, when `post`, a form POST of
// `post_body` as the first request; a redirect after a POST is followed with GET (303 and 302 always are).
fn fetch_with(a: *mem.Arena, s: *State, host: str, path: str, now: i64, validator: str, post: bool, post_body: str) -> (httpc.Reply, str, str, err) {
    var h = host
    var p = path
    var last: httpc.Reply = zero
    var hops = 0usize
    while hops < 5usize {
        var extra = ""
        let (sent, sent_error) = cookie.header(a, &s.jar, h, p, true, now)
        if sent_error == ok && sent.len > 0usize {
            extra = ui.join(a, "Cookie: ", sent, "\r\n")
            ui.say("browser cookie sent ")
            ui.say_num(sent.len)
            ui.say(" bytes\n")
        }
        if hops == 0usize && validator.len > 0usize { extra = ui.join(a, extra, validator, "") }
        var reply: httpc.Reply = zero
        var get_error = ok
        if hops == 0usize && post {
            let (posted, post_error) = httpc.post(a, h, p, ui.join(a, extra, "Content-Type: application/x-www-form-urlencoded\r\n", ""), post_body)
            reply = posted
            get_error = post_error
        } else {
            let (fetched, fetch_error) = httpc.get(a, h, p, extra)
            reply = fetched
            get_error = fetch_error
        }
        if get_error != ok { ret (reply, h, p, get_error) }
        last = reply
        let kept = absorb_cookies(a, s, reply.head, h, p, now)
        if kept > 0usize {
            save_jar(s)
            ui.say("browser cookies ")
            ui.say_num(s.jar.count)
            ui.say("\n")
        }
        let moved = reply.status == 301usize || reply.status == 302usize || reply.status == 303usize || reply.status == 307usize || reply.status == 308usize
        if !moved { ret (reply, h, p, ok) }
        let (location, has_location) = header_value(reply.head, "location:")
        if !has_location || location.len == 0usize { ret (reply, h, p, ok) }
        if location[0usize] == 47u8 {
            p = location
        } else if location.len > 8usize && header_is(location, "https://") {
            var slash = 8usize
            while slash < location.len && location[slash] != 47u8 { slash += 1usize }
            h = location[8usize..slash]
            if slash < location.len { p = location[slash..location.len] } else { p = "/" }
        } else {
            ret (reply, h, p, ok)
        }
        ui.say("browser redirect ")
        ui.say_text(h)
        ui.say_text(p)
        ui.say("\n")
        hops += 1usize
    }
    ret (last, h, p, httpc.Malformed)
}

// (C159) Save a download into /Downloads and make the page a note of it: its name, its size and where it went.
fn download(a: *mem.Arena, s: *State, slot: usize, path: str, body: str) -> bool {
    var start = 0usize
    var end = path.len
    var i = 0usize
    while i < path.len {
        if path[i] == 63u8 && end == path.len { end = i }
        if path[i] == 47u8 && end == path.len { start = i + 1usize }
        i += 1usize
    }
    var name = path[start..end]
    if name.len == 0usize { name = "download" }
    let made = vaultfs.mkdir("/Downloads")
    let dest = ui.join(a, "/Downloads/", name, "")
    var saved = false
    if body.len > 0usize { saved = vaultfs.write_big(dest, mem.address_of(&body[0usize]), body.len) }
    let (size, kind_of, extra, found) = vaultfs.stat(dest)
    s.page_total = 0usize
    s.cur_len = 0usize
    s.pending_space = false
    s.scroll = 0usize
    s.images[0usize].kind = 0usize
    s.images[1usize].kind = 0usize
    s.title_len = 0usize
    flush_line_text(s, "Downloaded", KIND_H1)
    flush_line_text(s, name, KIND_BODY)
    flush_line_text(s, ui.join(a, ui.number(a, size), " bytes in Downloads", ""), KIND_BODY)
    // (C159) Open in Document: a link whose target is `~open:<path>` hands the file over (Files' way).
    if saved && found && dest.len + 6usize <= 48usize {
        let opener = ui.join(a, "~open:", dest, "")
        add_text(s, "Open in Document", KIND_LINK, opener)
        flush_line(s, KIND_LINK, opener)
    }
    s.loaded = slot
    s.load_error = 0usize
    if !saved || !found || size != body.len {
        s.load_error = 4usize
        ret false
    }
    ui.say("browser downloaded ")
    ui.say_text(name)
    ui.say(" ")
    ui.say_num(size)
    ui.say("\n")
    ret true
}

// One whole line of text (a note the Browser itself shows).
fn flush_line_text(s: *State, line_text: str, kind: usize) {
    add_text(s, line_text, kind, "")
    flush_line(s, kind, "")
}

// (C159) The cache entry for host and path, or NONE.
fn cache_find(s: *State, host: str, path: str) -> usize {
    var i = 0usize
    while i < 4usize {
        let e = &s.cache[i]
        if e.used && e.host_len == host.len && e.path_len == path.len {
            var same = true
            var k = 0usize
            while k < host.len {
                if e.host[k] != host[k] { same = false }
                k += 1usize
            }
            k = 0usize
            while k < path.len {
                if e.path[k] != path[k] { same = false }
                k += 1usize
            }
            if same { ret i }
        }
        i += 1usize
    }
    ret NONE
}

// (C159) Keep a 200 reply that carries an ETag (and is a page of at most 3 KB) for a later conditional request.
fn cache_put(s: *State, host: str, path: str, etag: str, body: str) {
    if etag.len == 0usize || etag.len > 40usize || body.len > 3072usize || host.len > 40usize || path.len > 64usize { ret }
    var at = cache_find(s, host, path)
    if at == NONE {
        at = s.cache_next
        s.cache_next = (s.cache_next + 1usize) % 4usize
    }
    var e = &s.cache[at]
    var k = 0usize
    while k < host.len {
        e.host[k] = host[k]
        k += 1usize
    }
    e.host_len = host.len
    k = 0usize
    while k < path.len {
        e.path[k] = path[k]
        k += 1usize
    }
    e.path_len = path.len
    k = 0usize
    while k < etag.len {
        e.etag[k] = etag[k]
        k += 1usize
    }
    e.etag_len = etag.len
    k = 0usize
    while k < body.len {
        e.body[k] = body[k]
        k += 1usize
    }
    e.body_len = body.len
    e.used = true
    ui.say("browser cached ")
    ui.say_text(path)
    ui.say("\n")
}

// Fetch and lay out the page of address slot `slot`: false (with `load_error` set) when it could not be had.
fn load_live(a: *mem.Arena, kit: *appkit.Kit, s: *State, slot: usize) -> bool {
    let u = s.urls[slot]
    let host = ui.text_of(a, u.host[0usize..], u.host_len)
    let path = ui.text_of(a, u.path[0usize..], u.path_len)
    ret fetch_page(a, kit, s, slot, host, path, false, "") != NONE
}

// (C159) Fetch `host``path` (a form POST with `post_body` when `post`) and lay out the reply as the page of address
// slot `slot` (for a POST, the slot of the address the reply came from): the slot, or NONE with `load_error` set.
fn fetch_page(a: *mem.Arena, kit: *appkit.Kit, s: *State, hint: usize, host: str, path: str, post: bool, post_body: str) -> usize {
    var slot = hint
    s.page_total = 0usize
    s.cur_len = 0usize
    s.pending_space = false
    s.scroll = 0usize
    s.title_len = 0usize
    s.loaded = NONE
    // (C159) The cookies the jar holds go with each request, what a response sets is kept, redirects are followed. A
    // page kept with an ETag is asked for again with If-None-Match: a 304 shows the kept body.
    let now = wall_seconds()
    var validator = ""
    var kept_at = NONE
    if !post {
        kept_at = cache_find(s, host, path)
        if kept_at != NONE { validator = ui.join(a, "If-None-Match: ", ui.text_of(a, s.cache[kept_at].etag[0usize..], s.cache[kept_at].etag_len), "\r\n") }
    }
    let (fetched, final_host, final_path, get_error) = fetch_with(a, s, host, path, now, validator, post, post_body)
    var reply = fetched
    if get_error == ok && reply.status == 304usize && kept_at != NONE {
        reply.status = 200usize
        reply.body = ui.text_of(a, s.cache[kept_at].body[0usize..], s.cache[kept_at].body_len)
        ui.say("browser cache revalidated ")
        ui.say_text(path)
        ui.say("\n")
    } else if get_error == ok && reply.status == 200usize && !post {
        let (etag, has_etag) = header_value(reply.head, "etag:")
        if has_etag { cache_put(s, final_host, final_path, etag, reply.body) }
    }
    if get_error != ok {
        s.load_error = 1usize
        ui.say("browser fetch failed ")
        if get_error == httpc.NoNetwork { ui.say("no-network ") }
        if get_error == httpc.Unreachable { ui.say("unreachable ") }
        if get_error == httpc.TlsFailed { ui.say("tls ") }
        if get_error == httpc.Io { ui.say("io ") }
        if get_error == httpc.Malformed { ui.say("malformed ") }
        if get_error == httpc.TooLarge { ui.say("too-large ") }
        ui.say_text(host)
        ui.say_text(path)
        ui.say("\n")
        ret NONE
    }
    if reply.status != 200usize {
        s.load_error = 2usize
        ui.say("browser fetch status ")
        ui.say_num(reply.status)
        ui.say("\n")
        ret NONE
    }
    // A POST's reply is the page of the address it came from.
    if post { slot = url_slot(s, final_host, final_path) }
    // (C159) A reply that is not a page (its Content-Type is neither text nor XHTML) is a download: saved in /Downloads
    // under the last segment of the path and shown as a note.
    let (content_type, has_type) = header_value(reply.head, "content-type:")
    if has_type && !header_is(content_type, "text/") && !header_is(content_type, "application/xhtml") {
        if download(a, s, slot, final_path, reply.body) { ret slot }
        ret NONE
    }
    let (doc, parse_error) = html.parse(a, reply.body, html.Options { max_bytes: 98304usize, max_nodes: 2048usize, max_attributes: 16usize, max_depth: 40u16, preserve_comments: false })
    if parse_error != ok {
        s.load_error = 3usize
        ret NONE
    }
    s.form_open = false
    s.field_total = 0usize
    s.st_has_color = false
    s.st_color = 0u32
    s.st_px = 0usize
    s.st_bold = false
    s.st_center = false
    find_title(a, s, &doc)
    // (C159) The page's own stylesheet, applied through the cascade (only when it has a <style>).
    var styler: Styler = zero
    styler.author = style_rules(a, &doc)
    styler.m = match.new_matcher(a, &doc, match.no_state())
    styler.active = styler.author.len > 0usize
    if styler.active {
        ui.say("browser css ")
        ui.say_num(styler.author.len)
        ui.say(" rules\n")
    }
    walk(a, s, &styler, &doc, doc.root, KIND_BODY, "")
    flush_line(s, KIND_BODY, "")
    load_images(a, kit, s, final_host, now)
    s.loaded = slot
    s.load_error = 0usize
    ui.say("browser live ")
    ui.say_text(final_host)
    ui.say_text(final_path)
    ui.say(" ")
    ui.say_text(ui.number(a, s.page_total))
    ui.say("\n")
    ret slot
}

// (C159) The first two images of the page, fetched from the page's host: an SVG of at most 1.5 KB is kept as text; a
// PNG or JPEG of at most 32 KB is decoded and uploaded as a texture.
fn load_images(a: *mem.Arena, kit: *appkit.Kit, s: *State, final_host: str, now: i64) {
    s.images[0usize].kind = 0usize
    s.images[1usize].kind = 0usize
    var tried = 0usize
    var at_line = 0usize
    while at_line < s.page_total && tried < 2usize {
        if s.page[at_line].kind == KIND_IMAGE {
            let image_line = s.page[at_line]
            let (image_host, image_path) = split_address(a, s, ui.text_of(a, image_line.href[0usize..], image_line.href_len), final_host)
            // Each image is fetched and kept inside a mark: its 96 KB reply buffer is given back afterwards.
            let mark = mem.mark(a)
            let (picture_reply, got_host, got_path, image_error) = fetch_following(a, s, image_host, image_path, now)
            if image_error == ok && picture_reply.status == 200usize && picture_reply.body.len > 0usize && picture_reply.body.len <= 32768usize {
                keep_picture(a, kit, s, tried, at_line, picture_reply.body)
            } else {
                ui.say("browser image not fetched ")
                ui.say_text(image_path)
                ui.say("\n")
            }
            mem.reset(a, mark)
            tried += 1usize
        }
        at_line += 1usize
    }
}

// (C159) Keep the bytes of an image as picture `which` standing at page line `line`.
fn keep_picture(a: *mem.Arena, kit: *appkit.Kit, s: *State, which: usize, line: usize, data: str) {
    var is_png = false
    var is_jpeg = false
    if data.len > 8usize && data[0usize] == 137u8 && data[1usize] == 80u8 && data[2usize] == 78u8 && data[3usize] == 71u8 { is_png = true }
    if data.len > 4usize && data[0usize] == 255u8 && data[1usize] == 216u8 { is_jpeg = true }
    if is_png || is_jpeg {
        var reader_state: io.SliceReader = zero
        reader_state.data = data
        reader_state.off = 0usize
        var decoded: image.Image = zero
        var decode_error = ok
        if is_jpeg {
            let (jpeg_image, jpeg_error) = jpeg.decode(a, io.slice_reader(&reader_state), jpeg.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 262144u64 })
            decoded = jpeg_image
            decode_error = jpeg_error
        } else {
            let (png_image, png_error) = png.decode(a, io.slice_reader(&reader_state), png.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 262144u64, verify_crc: true })
            decoded = png_image
            decode_error = png_error
        }
        if decode_error != ok {
            ui.say("browser image decode failed\n")
            ret
        }
        let (view, view_error) = image.make_const(decoded.pixels, decoded.width, decoded.height, decoded.stride, decoded.format, decoded.alpha)
        if view_error != ok {
            ui.say("browser image view failed\n")
            ret
        }
        let (texture, upload_error) = scene.upload_image(&kit.renderer, view)
        if upload_error != ok {
            ui.say("browser image upload failed\n")
            ret
        }
        s.images[which].tex = texture
        s.images[which].w = f32(decoded.width)
        s.images[which].h = f32(decoded.height)
        s.images[which].kind = 2usize
        s.images[which].line = line
        if is_png { ui.say("browser image png ") } else { ui.say("browser image jpeg ") }
        ui.say_num(usize(decoded.width))
        ui.say("x")
        ui.say_num(usize(decoded.height))
        ui.say("\n")
        ret
    }
    if data.len <= 1536usize {
        var b = 0usize
        while b < data.len {
            s.images[which].svg[b] = data[b]
            b += 1usize
        }
        s.images[which].svg_len = b
        s.images[which].kind = 1usize
        s.images[which].line = line
        ui.say("browser image ")
        ui.say_num(b)
        ui.say(" bytes\n")
    }
}

// An address slot for host and path (the same one when it is known).
fn url_slot(s: *State, host: str, path: str) -> usize {
    var i = 0usize
    while i < s.url_total {
        let u = s.urls[i]
        if u.host_len == host.len && u.path_len == path.len {
            var same = true
            var k = 0usize
            while k < host.len {
                if u.host[k] != host[k] { same = false }
                k += 1usize
            }
            k = 0usize
            while k < path.len {
                if u.path[k] != path[k] { same = false }
                k += 1usize
            }
            if same { ret i }
        }
        i += 1usize
    }
    var slot = s.url_total
    if slot >= URLS {
        // The table is full: the oldest is reused.
        slot = 0usize
        var k = 1usize
        while k < URLS {
            s.urls[k - 1usize] = s.urls[k]
            k += 1usize
        }
        slot = URLS - 1usize
    } else {
        s.url_total += 1usize
    }
    var u: Url = zero
    var h = 0usize
    while h < host.len && h < 40usize {
        u.host[h] = host[h]
        h += 1usize
    }
    u.host_len = h
    var p = 0usize
    while p < path.len && p < 64usize {
        u.path[p] = path[p]
        p += 1usize
    }
    u.path_len = p
    u.used = true
    s.urls[slot] = u
    ret slot
}

// Split a typed or linked address into host and path against the current page's host.
fn split_address(a: *mem.Arena, s: *State, address_in: str, current_host: str) -> (str, str) {
    var rest = address_in
    var host = current_host
    var has_scheme = false
    if rest.len >= 8usize && ui.same(rest[0usize..8usize], "https://") {
        rest = rest[8usize..rest.len]
        has_scheme = true
    } else if rest.len >= 7usize && ui.same(rest[0usize..7usize], "http://") {
        rest = rest[7usize..rest.len]
        has_scheme = true
    }
    if has_scheme || (rest.len > 0usize && rest[0usize] != 47u8 && current_host.len == 0usize) {
        var end = 0usize
        while end < rest.len && rest[end] != 47u8 { end += 1usize }
        host = rest[0usize..end]
        rest = rest[end..rest.len]
    }
    if rest.len == 0usize { ret (host, "/") }
    if rest[0usize] != 47u8 { ret (host, ui.join(a, "/", rest, "")) }
    ret (host, rest)
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
    // (C159) The bookmarks, up to four.
    if s.mark_total > 0usize {
        try ui.put(a, builder, faces.grotesk, 12.0, "Bookmarks", 24.0, 488.0, ui.light_muted())
        var row = 0usize
        while row < s.mark_total {
            let y: f32 = 512.0 + f32(row) * 52.0
            try ui.card(a, builder, 16.0, y, 380.0, 44.0, 14.0, ui.cream())
            try ui.clipped(a, builder, faces.jost, 17.0, ui.text_of(a, s.marks[row][0usize..], s.mark_len[row]), 32.0, y + 11.0, 340.0, ui.ink())
            ui.hit(&s.hits, 460usize + row, 16.0, y, 380.0, 44.0)
            row += 1usize
        }
    }
    ret ok
}

// (C159) The address of a page as the address bar shows it: the host and path of a live page, else the site's name.
fn address_of_page(a: *mem.Arena, s: *State, page: usize) -> str {
    if page >= LIVE_BASE {
        let u = s.urls[page - LIVE_BASE]
        ret ui.join(a, ui.text_of(a, u.host[0usize..], u.host_len), ui.text_of(a, u.path[0usize..], u.path_len), "")
    }
    ret page_host(page)
}

// (C159) The index of the bookmark for `address`, or NONE.
fn bookmarked(a: *mem.Arena, s: *State, address: str) -> usize {
    var i = 0usize
    while i < s.mark_total {
        if ui.same(ui.text_of(a, s.marks[i][0usize..], s.mark_len[i]), address) { ret i }
        i += 1usize
    }
    ret NONE
}

// The bookmarks are kept in /bookmarks, one address a line.
fn save_marks(a: *mem.Arena, s: *State) {
    var buf: [200]u8 = zero
    var n = 0usize
    var i = 0usize
    while i < s.mark_total {
        var k = 0usize
        while k < s.mark_len[i] {
            buf[n] = s.marks[i][k]
            n += 1usize
            k += 1usize
        }
        buf[n] = 10u8
        n += 1usize
        i += 1usize
    }
    let written = vaultfs.write_big("/bookmarks", mem.address_of(&buf[0usize]), n)
}

fn load_marks(s: *State) -> usize {
    var buf: [200]u8 = zero
    let (n, found) = vaultfs.read_big("/bookmarks", mem.address_of(&buf[0usize]), 200usize)
    if !found || n == 0usize { ret 0usize }
    var at = 0usize
    while at < n && s.mark_total < 4usize {
        var end = at
        while end < n && buf[end] != 10u8 { end += 1usize }
        if end > at && end - at <= 48usize {
            var k = 0usize
            while at + k < end {
                s.marks[s.mark_total][k] = buf[at + k]
                k += 1usize
            }
            s.mark_len[s.mark_total] = k
            s.mark_total += 1usize
        }
        at = end + 1usize
    }
    ret s.mark_total
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

// (C159) The picture kept for page line `line`, or NONE.
fn picture_at(s: *State, line: usize) -> usize {
    if s.images[0usize].kind != 0usize && s.images[0usize].line == line { ret 0usize }
    if s.images[1usize].kind != 0usize && s.images[1usize].line == line { ret 1usize }
    ret NONE
}

// (C159) A form field being edited: its name, its value and the keyboard.
fn draw_field(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let f = &s.fields[s.edit_field]
    try ui.put(a, builder, faces.grotesk, 13.0, ui.text_of(a, f.name[0usize..], f.name_len), 24.0, 80.0, ui.light_muted())
    let value = ui.field_text(a, &s.edit)
    try ui.card(a, builder, 14.0, 100.0, 384.0, 54.0, 27.0, ui.amber())
    try ui.card(a, builder, 16.0, 102.0, 380.0, 50.0, 25.0, ui.cream())
    try ui.clipped(a, builder, faces.jost, 18.0, value, 36.0, 115.0, 340.0, ui.ink())
    var caret_x: f32 = 36.0
    if value.len > 0usize { caret_x = 36.0 + text.measure(a, faces.jost, 18.0, value) + 2.0 }
    if caret_x > 372.0 { caret_x = 372.0 }
    try ui.card(a, builder, caret_x, 113.0, 2.0, 26.0, 1.0, ui.amber())
    try ui.keyboard(a, builder, &s.hits, faces, "Done")
    ret ok
}

// (C159) The colour of a line from the stylesheet (ARGB), or `fallback`.
fn style_color(line: PageLine, fallback: paint.Color) -> paint.Color {
    if !line.has_color { ret fallback }
    ret paint.Color { red: f32((line.color >> 16u32) & 255u32) / 255.0, green: f32((line.color >> 8u32) & 255u32) / 255.0, blue: f32(line.color & 255u32) / 255.0, alpha: 1.0 }
}

// A live page: its lines from the scroll position, links as amber lines that can be tapped.
fn draw_live(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    var i = s.scroll
    while i < s.page_total && y < 800.0 {
        let line = s.page[i]
        let text_line = ui.text_of(a, line.text[0usize..], line.len)
        let tone = style_color(line, ui.light())
        if line.kind == KIND_H1 {
            if line.center { try ui.centred(a, builder, faces.jost_bold, 30.0, text_line, 206.0, y, tone) } else { try ui.put(a, builder, faces.jost_bold, 30.0, text_line, 20.0, y, tone) }
            y += 44.0
        } else if line.kind == KIND_H2 {
            if line.center { try ui.centred(a, builder, faces.jost_bold, 22.0, text_line, 206.0, y, tone) } else { try ui.put(a, builder, faces.jost_bold, 22.0, text_line, 20.0, y, tone) }
            y += 34.0
        } else if line.kind == KIND_LINK {
            try ui.put(a, builder, faces.jost, 17.0, text_line, 20.0, y, ui.amber())
            try ui.card(a, builder, 20.0, y + 22.0, 8.0 * f32(line.len) * 0.9, 1.0, 0.0, ui.amber())
            ui.hit(&s.hits, 900usize + i, 12.0, y - 4.0, 388.0, 32.0)
            y += 32.0
        } else if line.kind == KIND_PRE {
            try ui.put(a, builder, faces.grotesk, 13.0, text_line, 20.0, y, ui.light())
            y += 20.0
        } else if line.kind == KIND_FIELD {
            // (C159) A form field: its line is a box (a tap edits it).
            try ui.card(a, builder, 16.0, y - 6.0, 380.0, 34.0, 10.0, ui.soft())
            try ui.put(a, builder, faces.jost, 17.0, text_line, 28.0, y, ui.light())
            ui.hit(&s.hits, 900usize + i, 16.0, y - 6.0, 380.0, 34.0)
            y += 40.0
        } else if line.kind == KIND_SUBMIT {
            try ui.pill(a, builder, &s.hits, faces, 900usize + i, 20.0, y - 4.0, 120.0, 38.0, text_line, ui.amber(), 16.0)
            y += 48.0
        } else if line.kind == KIND_IMAGE && picture_at(s, i) != NONE {
            let which = picture_at(s, i)
            if s.images[which].kind == 1usize {
                try picture(a, builder, ui.text_of(a, s.images[which].svg[0usize..], s.images[which].svg_len), geometry.rect(20.0, y, 96.0, 96.0), ui.amber())
                y += 108.0
            } else {
                // A decoded picture, scaled to fit 96 high and 372 wide.
                var scale: f32 = 96.0 / s.images[which].h
                if s.images[which].w * scale > 372.0 { scale = 372.0 / s.images[which].w }
                let dw: f32 = s.images[which].w * scale
                let dh: f32 = s.images[which].h * scale
                try scene.push(builder, scene.Command { Image: scene.DrawImage { texture: s.images[which].tex, source: geometry.rect(0.0, 0.0, s.images[which].w, s.images[which].h), destination: geometry.rect(20.0, y, dw, dh), opacity: 1.0 } })
                y += dh + 12.0
            }
            ui.say("browser image drawn\n")
        } else if line.kind == KIND_IMAGE {
            try ui.put(a, builder, faces.jost, 17.0, ui.join(a, "[", text_line, "]"), 20.0, y, ui.light_muted())
            y += 26.0
        } else {
            // (C159) A body line in its style: the stylesheet's colour, size, weight and alignment.
            var size: f32 = 17.0
            if line.px >= 10usize { size = f32(line.px) }
            var face = faces.jost
            if line.bold { face = faces.jost_bold }
            if line.center { try ui.centred(a, builder, face, size, text_line, 206.0, y, tone) } else { try ui.put(a, builder, face, size, text_line, 20.0, y, tone) }
            y += size * 1.5
        }
        i += 1usize
    }
    if i < s.page_total {
        try ui.pill(a, builder, &s.hits, faces, 890usize, 300.0, 780.0, 96.0, 36.0, "More", ui.soft(), 15.0)
    }
    if s.scroll > 0usize {
        try ui.pill(a, builder, &s.hits, faces, 891usize, 16.0, 780.0, 96.0, 36.0, "Top", ui.soft(), 15.0)
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
        var shown = page_host(page)
        if page >= LIVE_BASE {
            let u = s.urls[page - LIVE_BASE]
            shown = ui.join(a, ui.text_of(a, u.host[0usize..], u.host_len), ui.text_of(a, u.path[0usize..], u.path_len), "")
        }
        try ui.put(a, builder, faces.jost, 17.0, shown, 62.0, 33.0, ui.ink())
    }
    ui.hit(&s.hits, 700usize, 16.0, 22.0, 380.0, 46.0)
    // (C175) Copy: the address of the page goes to the clipboard (a tap on the right end of the bar).
    if page != START {
        try ui.put(a, builder, faces.grotesk, 14.0, "Copy", 350.0, 36.0, ui.muted())
        ui.hit(&s.hits, 710usize, 340.0, 22.0, 56.0, 46.0)
        // (C159) Star: the page's address is a bookmark (taken off again by a second tap).
        var star_label = "Star"
        if bookmarked(a, s, address_of_page(a, s, page)) != NONE { star_label = "Starred" }
        try ui.put(a, builder, faces.grotesk, 14.0, star_label, 296.0, 36.0, ui.amber_dark())
        ui.hit(&s.hits, 711usize, 290.0, 22.0, 50.0, 46.0)
    }
    if page >= LIVE_BASE { try draw_live(a, builder, s, faces) }
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
    } else if s.screen == FIELD_SCREEN {
        try draw_field(a, builder, s, faces)
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

// (C159) The open tabs are kept in /browser_tabs as lines: `C<current>`, then one per tab -- `S<page>` for a sample
// page, `Q<query>` for a search, `L<host> <path>` for a live page (its history is not kept, only where it stands).
fn save_tabs(a: *mem.Arena, s: *State) {
    var buf: [320]u8 = zero
    var n = 0usize
    buf[0usize] = 67u8
    buf[1usize] = u8(48usize + s.current)
    buf[2usize] = 10u8
    n = 3usize
    var i = 0usize
    while i < s.tab_total {
        let t = s.tabs[i]
        let page = t.pages[t.at]
        var piece = ""
        if page >= LIVE_BASE {
            let u = s.urls[page - LIVE_BASE]
            piece = ui.join(a, "L", ui.join(a, ui.text_of(a, u.host[0usize..], u.host_len), " ", ""), ui.text_of(a, u.path[0usize..], u.path_len))
        } else if page == RESULTS {
            piece = ui.join(a, "Q", ui.text_of(a, t.query[0usize..], t.query_len), "")
        } else {
            piece = ui.join(a, "S", ui.number(a, page), "")
        }
        if n + piece.len + 1usize <= 320usize {
            var k = 0usize
            while k < piece.len {
                buf[n + k] = piece[k]
                k += 1usize
            }
            n += piece.len
            buf[n] = 10u8
            n += 1usize
        }
        i += 1usize
    }
    // Written only when it changed.
    var same = n == s.tabs_saved_len
    var c = 0usize
    while same && c < n {
        if s.tabs_saved[c] != buf[c] { same = false }
        c += 1usize
    }
    if same { ret }
    let written = vaultfs.write_big("/browser_tabs", mem.address_of(&buf[0usize]), n)
    c = 0usize
    while c < n {
        s.tabs_saved[c] = buf[c]
        c += 1usize
    }
    s.tabs_saved_len = n
}

// The tabs of /browser_tabs: how many came back (the current one is the one that was in front).
fn load_tabs(a: *mem.Arena, s: *State) -> usize {
    var buf: [320]u8 = zero
    let (n, found) = vaultfs.read_big("/browser_tabs", mem.address_of(&buf[0usize]), 320usize)
    if !found || n < 4usize || buf[0usize] != 67u8 { ret 0usize }
    var wanted_current = usize(buf[1usize] - 48u8)
    var at = 3usize
    var restored = 0usize
    while at < n && restored < MAX_TABS {
        var end = at
        while end < n && buf[end] != 10u8 { end += 1usize }
        if end > at {
            let line = buf[at..end]
            var page = START
            var okay = false
            if line[0usize] == 83u8 && line.len == 2usize {
                page = usize(line[1usize] - 48u8)
                okay = page < 7usize
            } else if line[0usize] == 81u8 {
                page = RESULTS
                okay = true
            } else if line[0usize] == 76u8 {
                var sp = 1usize
                while sp < line.len && line[sp] != 32u8 { sp += 1usize }
                if sp < line.len {
                    page = LIVE_BASE + url_slot(s, line[1usize..sp], line[sp + 1usize..line.len])
                    okay = true
                }
            }
            if okay {
                var t: Tab = zero
                t.pages[0usize] = page
                t.count = 1usize
                t.used = true
                if line[0usize] == 81u8 {
                    var k = 1usize
                    while k < line.len && k - 1usize < 32usize {
                        t.query[k - 1usize] = line[k]
                        k += 1usize
                    }
                    t.query_len = k - 1usize
                }
                s.tabs[s.tab_total] = t
                s.tab_total += 1usize
                restored += 1usize
            }
        }
        at = end + 1usize
    }
    if restored == 0usize { ret 0usize }
    if wanted_current >= s.tab_total { wanted_current = 0usize }
    s.current = wanted_current
    ret restored
}

// Make sure the page the tab is at is the one loaded (a live page is fetched again when it is not).
fn ensure_live(a: *mem.Arena, kit: *appkit.Kit, s: *State) {
    let page = current_page(s)
    if page >= LIVE_BASE && s.loaded != page - LIVE_BASE {
        if !load_live(a, kit, s, page - LIVE_BASE) {
            let t = &s.tabs[s.current]
            t.pages[t.at] = ERROR
        }
    }
}

fn submit(a: *mem.Arena, kit: *appkit.Kit, s: *State, address: str) {
    ui.say("browser address ")
    ui.say_text(address)
    ui.say("\n")
    var page = resolve(address)
    if page == ERROR {
        // Not one of the sample sites: a real address, fetched over the network.
        let (host, path) = split_address(a, s, address, "")
        let slot = url_slot(s, host, path)
        if load_live(a, kit, s, slot) { page = LIVE_BASE + slot }
    }
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
fn act(a: *mem.Arena, kit: *appkit.Kit, s: *State, id: usize) -> bool {
    if s.screen == ENTRY_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                submit(a, kit, s, ui.field_text(a, &s.typed))
                ret true
            }
            ret ui.field_key(&s.typed, id, false)
        }
        if id >= 450usize && id < 454usize {
            var site = "neper.dev"
            if id == 451usize { site = "news.example" }
            if id == 452usize { site = "docs.example" }
            if id == 453usize { site = "weather.example" }
            submit(a, kit, s, site)
            ret true
        }
        ret false
    }
    if s.screen == FIELD_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                // Done: the value goes back into the field and into the page line that shows it.
                let f = &s.fields[s.edit_field]
                var n = 0usize
                while n < s.edit.len && n < 24usize {
                    f.value[n] = s.edit.bytes[n]
                    n += 1usize
                }
                f.value_len = n
                var at_line = 0usize
                while at_line < s.page_total {
                    if s.page[at_line].kind == KIND_FIELD && s.page[at_line].aux == s.edit_field {
                        s.cur_len = 0usize
                        s.pending_space = false
                        add_text(s, ui.text_of(a, f.name[0usize..], f.name_len), KIND_FIELD, "")
                        add_text(s, ":", KIND_FIELD, "")
                        add_text(s, ui.text_of(a, f.value[0usize..], f.value_len), KIND_FIELD, "")
                        let kept_total = s.page_total
                        let replaced = s.page[at_line]
                        var line_copy: PageLine = replaced
                        var t = 0usize
                        while t < s.cur_len && t < 56usize {
                            line_copy.text[t] = s.cur[t]
                            t += 1usize
                        }
                        line_copy.len = t
                        s.page[at_line] = line_copy
                        s.cur_len = 0usize
                    }
                    at_line += 1usize
                }
                s.screen = BROWSE_SCREEN
                ui.say("browser field value ")
                ui.say_text(ui.text_of(a, f.value[0usize..], f.value_len))
                ui.say("\n")
                ret true
            }
            ret ui.field_key(&s.edit, id, false)
        }
        ret false
    }
    if s.screen == TABS_SCREEN {
        if id >= 510usize && id < 514usize {
            if id - 510usize < s.tab_total {
                s.current = id - 510usize
                s.screen = BROWSE_SCREEN
                ensure_live(a, kit, s)
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
            ensure_live(a, kit, s)
        }
        ret true
    }
    if id == 801usize {
        var t = &s.tabs[s.current]
        if t.at + 1usize < t.count {
            t.at += 1usize
            ui.say("browser forward\n")
            ensure_live(a, kit, s)
        }
        ret true
    }
    if id == 890usize {
        if s.scroll + 12usize < s.page_total { s.scroll += 12usize }
        ret true
    }
    if id == 891usize {
        s.scroll = 0usize
        ret true
    }
    // A link on a live page.
    if id >= 900usize && id < 900usize + PAGE_LINES {
        let line = s.page[id - 900usize]
        if line.kind == KIND_FIELD && line.aux < s.field_total {
            // (C159) A form field: its value is edited on the field screen.
            s.edit_field = line.aux
            s.edit.len = 0usize
            var c = 0usize
            while c < s.fields[line.aux].value_len {
                ui.field_type(&s.edit, s.fields[line.aux].value[c], false)
                c += 1usize
            }
            s.screen = FIELD_SCREEN
            ui.say("browser field ")
            ui.say_text(ui.text_of(a, s.fields[line.aux].name[0usize..], s.fields[line.aux].name_len))
            ui.say("\n")
            ret true
        }
        if line.kind == KIND_SUBMIT {
            // (C159) The form is submitted with its fields as they are now: GET puts them in the query of the action, POST
            // sends them as the body.
            var made: [96]u8 = zero
            let query_len = make_query(s, made[0usize..96usize])
            let current = s.urls[current_page(s) - LIVE_BASE]
            let current_host = ui.text_of(a, current.host[0usize..], current.host_len)
            let (host, path) = split_address(a, s, ui.text_of(a, line.href[0usize..], line.href_len), current_host)
            let query_text = ui.text_of(a, made[0usize..], query_len)
            var slot = NONE
            if line.aux == 1usize {
                ui.say("browser post ")
                ui.say_text(path)
                ui.say(" ")
                ui.say_num(query_len)
                ui.say("\n")
                slot = fetch_page(a, kit, s, NONE, host, path, true, query_text)
            } else {
                var goal = path
                if query_len > 0usize { goal = ui.join(a, ui.join(a, path, "?", ""), query_text, "") }
                let get_slot = url_slot(s, host, goal)
                if load_live(a, kit, s, get_slot) { slot = get_slot }
            }
            if slot != NONE { go(s, LIVE_BASE + slot) } else { go(s, ERROR) }
            ret true
        }
        if line.href_len > 6usize && ui.same(ui.text_of(a, line.href[0usize..], 6usize), "~open:") {
            // (C159) A downloaded file is opened in Document: its path goes in /handover, the app leaves with 20040.
            var opened_path: [64]u8 = zero
            var o = 0usize
            while o + 6usize < line.href_len && o < 63usize {
                opened_path[o] = line.href[6usize + o]
                o += 1usize
            }
            if vaultfs.write("/handover", mem.address_of(&opened_path[0usize]), o) {
                s.handover = 40usize
                ui.say("browser handover ")
                ui.say_text(ui.text_of(a, opened_path[0usize..], o))
                ui.say("\n")
            }
            ret true
        }
        if line.href_len > 0usize {
            let current = s.urls[current_page(s) - LIVE_BASE]
            let (host, path) = split_address(a, s, ui.text_of(a, line.href[0usize..], line.href_len), ui.text_of(a, current.host[0usize..], current.host_len))
            let slot = url_slot(s, host, path)
            if load_live(a, kit, s, slot) { go(s, LIVE_BASE + slot) } else { go(s, ERROR) }
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
    if id == 711usize {
        // (C159) Star: add the page's address to the bookmarks, or take it off when it is there.
        let star_address = address_of_page(a, s, current_page(s))
        let at = bookmarked(a, s, star_address)
        if at != NONE {
            var k = at + 1usize
            while k < s.mark_total {
                s.marks[k - 1usize] = s.marks[k]
                s.mark_len[k - 1usize] = s.mark_len[k]
                k += 1usize
            }
            s.mark_total -= 1usize
            ui.say("browser bookmark removed ")
        } else if star_address.len <= 48usize {
            if s.mark_total >= 4usize {
                var k = 1usize
                while k < 4usize {
                    s.marks[k - 1usize] = s.marks[k]
                    s.mark_len[k - 1usize] = s.mark_len[k]
                    k += 1usize
                }
                s.mark_total = 3usize
            }
            var n = 0usize
            while n < star_address.len {
                s.marks[s.mark_total][n] = star_address[n]
                n += 1usize
            }
            s.mark_len[s.mark_total] = n
            s.mark_total += 1usize
            ui.say("browser bookmark added ")
        }
        ui.say_text(star_address)
        ui.say("\n")
        save_marks(a, s)
        ret true
    }
    if id >= 460usize && id < 464usize && id - 460usize < s.mark_total {
        submit(a, kit, s, ui.text_of(a, s.marks[id - 460usize][0usize..], s.mark_len[id - 460usize]))
        ret true
    }
    if id == 710usize {
        let page = current_page(s)
        var address = page_host(page)
        if page >= LIVE_BASE {
            let u = s.urls[page - LIVE_BASE]
            address = ui.join(a, ui.text_of(a, u.host[0usize..], u.host_len), ui.text_of(a, u.path[0usize..], u.path_len), "")
        }
        let (wall, wall_error) = time.now()
        var now_s = 0usize
        if wall_error == ok { now_s = usize(wall.nanos / 1000000000i64) }
        let taken = sysettings.clip_set(4usize, now_s, address)
        ui.say("browser copied ")
        ui.say_text(address)
        ui.say("\n")
        ret true
    }
    if id == 804usize {
        ui.say("browser reload\n")
        let page = current_page(s)
        if page >= LIVE_BASE {
            let slot = page - LIVE_BASE
            s.loaded = NONE
            if !load_live(a, kit, s, slot) {
                let t = &s.tabs[s.current]
                t.pages[t.at] = ERROR
            }
        }
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
    s.jar = cookie.jar_new(s.cookie_store[0usize..16usize], s.cookie_text[0usize..2048usize])
    let restored = load_jar(&s, wall_seconds())
    if restored > 0usize {
        ui.say("browser cookies loaded ")
        ui.say_num(restored)
        ui.say("\n")
    }
    let marks_back = load_marks(&s)
    if marks_back > 0usize {
        ui.say("browser bookmarks ")
        ui.say_num(marks_back)
        ui.say("\n")
    }
    // (C159) The tabs of the last run come back, each at the page it was on; a live one is fetched as it is shown.
    let tabs_back = load_tabs(a, &s)
    if tabs_back > 0usize {
        ui.say("browser tabs restored ")
        ui.say_num(tabs_back)
        ui.say("\n")
        ensure_live(a, &kit, &s)
    } else {
        let first = new_tab(&s)
    }
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
            if id != ui.NONE && act(a, &kit, &s, id) {
                save_tabs(a, &s)
                if s.handover != 0usize {
                    appkit.leave()
                    running = false
                } else if !show(a, &kit, &s) {
                    ui.say("browser present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    if s.handover != 0usize { os.exit(i32(20000usize + s.handover)) }
    ret ok
}
