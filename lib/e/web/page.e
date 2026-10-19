// A loaded web page (tracker M2): `load` fetches a URL through `e.net.fetch`, decodes the document by the HTML encoding rules,
// parses it, finds the `<base>`, fetches the style sheets (`<link rel=stylesheet>`, `@import`) and places them with the
// `<style>` elements in document order, rewrites relative `url()` in them to absolute, and opens an `e.ui.html_view` over the
// result. Images (`<img>`, CSS `url()` backgrounds) are fetched and decoded on demand while the page is laid out and painted,
// sized for the layout, and uploaded to the renderer as textures when it first paints them.
//
// Scripts: the page runs its classic scripts (`<script>` in document order, `src` fetched through the page's client, deferred
// and async ones afterwards) in an `e.web.script` context bound to the view's document, fires DOMContentLoaded and load, and
// lays the page out again when they changed it. `tick` is the page's event loop (timers, promise jobs), `click` delivers a
// pointer click to the scripts. There is no navigation history and no cache beyond the page's own images; those are `e.web.*`
// above this and the control `e.ui.browser`. Loading blocks the caller.
//
// Memory: the page, the document, the fetched resources and the images live in the arena given to `load`; the view gets a
// private block carved from it (`view_bytes`) that it rewinds on every paint.

use e.data.list as list
use e.fmt.css.geom as geom
use e.fmt.css.layout as layout
use e.fmt.css.paint as cpaint
use e.fmt.css.sheet as sheet
use e.fmt.css.style as style
use e.fmt.dom as dom
use e.fmt.gif as gif
use e.fmt.html as html
use e.fmt.html.encoding as sniff
use e.fmt.jpeg as jpeg
use e.fmt.png as png
use e.fmt.url as url
use e.fmt.webp as webp
use e.fmt.woff as woff
use e.fmt.woff2 as woff2
use e.gfx.image as image
use e.gfx.scene as scene
use e.gfx.svg as svg
use e.io
use e.js.interp as js
use e.mem
use e.net.fetch as fetch
use e.net.http as http
use e.str
use e.text.charset_cjk as cjk
use e.text.fontset as fontset
use e.ui.html_view as view
use e.web.cssom as cssom
use e.web.csp as csp
use e.web.script as script

error NotRenderable
error LoadFailed

// state 0: not tried, 1: decoded, 2: failed.
type ImageEntry = struct {
    url: str, state: u8, width: u32, height: u32, img: image.Image, svg: str,
    texture: scene.TextureId, uploaded: bool
}

type Page = struct {
    pa: *mem.Arena, va: mem.Arena, client: *fetch.Client, fonts: *fontset.Set,
    url: str, status: u16, charset: str, title: str, mime: str,
    base: url.Url, tree: dom.Dom, sheets: []const str,
    images: list.List[ImageEntry],
    renderer: *scene.Renderer, has_renderer: bool, font_base: usize,
    view: *view.View,
    ctx: *js.Interp, scripted: bool, seen_version: u64, view_width: f32, view_height: f32, csp: csp.PolicySet,
    box_map: []u32, box_rev: u64, has_box_map: bool
}

// --- Content Security Policy.

fn csp_url_ok(p: *Page, directive: str, u: str) -> bool {
    if !csp.enforced(p.csp) { ret true }
    ret csp.url_allowed(p.pa, p.csp, directive, u, p.url, false, false)
}

fn csp_inline_ok(p: *Page, directive: str, nonce: str, text: str) -> bool {
    if !csp.enforced(p.csp) { ret true }
    ret csp.inline_allowed(p.pa, p.csp, directive, nonce, text)
}

// The script context's question about inline content: kind 0 an inline script, 1 an event handler attribute.
fn csp_hook(ctx: *void, kind: u32, nonce: str, text: str) -> bool {
    let p = mem.cast[*Page](ctx)
    var directive = "script-src-elem"
    if kind == 1u32 { directive = "script-src-attr" }
    ret csp_inline_ok(p, directive, nonce, text)
}

// --- Small helpers.

fn lower_byte(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn eq_fold(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if lower_byte(x[i]) != lower_byte(y[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn starts_fold(s: str, prefix: str) -> bool {
    if s.len < prefix.len { ret false }
    ret eq_fold(s[0usize..prefix.len], prefix)
}

// Whether the space-separated list `list_text` has the token `want` (case-insensitively).
fn has_token(list_text: str, want: str) -> bool {
    var i = 0usize
    while i < list_text.len {
        while i < list_text.len && (list_text[i] == 32u8 || list_text[i] == 9u8 || list_text[i] == 10u8) { i += 1usize }
        let start = i
        while i < list_text.len && list_text[i] != 32u8 && list_text[i] != 9u8 && list_text[i] != 10u8 { i += 1usize }
        if i > start && eq_fold(list_text[start..i], want) { ret true }
    }
    ret false
}

fn resolve_against(a: *mem.Arena, base: *const url.Url, ref_text: str) -> (str, bool) {
    let (u, e) = url.parse(a, ref_text, base, true)
    if e != ok { ret ("", false) }
    ret (url.href(a, &u, false), true)
}

fn get_request(u: str, referrer: str, creds: fetch.Credentials) -> fetch.Request {
    let none_headers: []const http.Header = zero
    let none_body: []const u8 = zero
    ret fetch.Request { url: u, method: http.Method.Get, headers: none_headers, body: none_body, redirect: fetch.Redirect.Follow, credentials: creds, referrer: referrer }
}

// --- CSS text: decoding, imports, url() rewriting.

fn css_text(a: *mem.Arena, r: *const fetch.Response) -> str {
    var name = "UTF-8"
    let label = fetch.charset_param(r)
    var from_header = false
    if label.len > 0usize {
        let (n, good) = sniff_label(label)
        if good {
            name = n
            from_header = true
        }
    }
    let body = r.body
    if !from_header && !(body.len >= 3usize && body[0usize] == 239u8 && body[1usize] == 187u8 && body[2usize] == 191u8) {
        // @charset "x"; at the very start.
        if body.len > 10usize && starts_fold(body, "@charset \"") {
            var e = 10usize
            while e < body.len && body[e] != 34u8 { e += 1usize }
            let (n2, good2) = sniff_label(body[10usize..e])
            if good2 { name = n2 }
        }
    }
    let (text, de) = cjk.decode_sniffing_bom(a, name, body)
    if de != ok { ret "" }
    ret text
}

fn sniff_label(label: str) -> (str, bool) {
    let probe = sniff.determine("", label)
    if str.eq(probe, "windows-1252") && !eq_fold(str.trim(label), "windows-1252") && !eq_fold(str.trim(label), "latin1") && !eq_fold(str.trim(label), "iso-8859-1") && !eq_fold(str.trim(label), "ascii") && !eq_fold(str.trim(label), "us-ascii") { ret ("", false) }
    ret (probe, true)
}

// The `url()` references of a style sheet, made absolute against the sheet's own URL.
fn absolutize_css(a: *mem.Arena, text: str, base: *const url.Url) -> str {
    var out = url.zero_buf(a, text.len * 2usize + 64usize)
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c == 47u8 && i + 1usize < text.len && text[i + 1usize] == 42u8 {
            // A comment is copied through.
            var e = i + 2usize
            while e + 1usize < text.len && !(text[e] == 42u8 && text[e + 1usize] == 47u8) { e += 1usize }
            e = e + 2usize
            if e > text.len { e = text.len }
            url.buf_str(&out, text[i..e])
            i = e
            continue
        }
        if c == 34u8 || c == 39u8 {
            var e2 = i + 1usize
            while e2 < text.len && text[e2] != c {
                if text[e2] == 92u8 { e2 += 1usize }
                e2 += 1usize
            }
            if e2 < text.len { e2 += 1usize }
            if e2 > text.len { e2 = text.len }
            url.buf_str(&out, text[i..e2])
            i = e2
            continue
        }
        let prev_ok = i == 0usize || !(is_ident_byte(text[i - 1usize]))
        if prev_ok && i + 4usize <= text.len && eq_fold(text[i..i + 4usize], "url(") {
            var p = i + 4usize
            while p < text.len && (text[p] == 32u8 || text[p] == 9u8 || text[p] == 10u8) { p += 1usize }
            var lo = p
            var hi = p
            if p < text.len && (text[p] == 34u8 || text[p] == 39u8) {
                let q = text[p]
                lo = p + 1usize
                hi = lo
                while hi < text.len && text[hi] != q {
                    if text[hi] == 92u8 { hi += 1usize }
                    hi += 1usize
                }
                if hi > text.len { hi = text.len }
                p = hi + 1usize
                if p > text.len { p = text.len }
            } else {
                while hi < text.len && text[hi] != 41u8 { hi += 1usize }
                p = hi
            }
            while p < text.len && text[p] != 41u8 { p += 1usize }
            if p < text.len { p += 1usize }
            let whole = text[i..p]
            var raw = str.trim(text[lo..hi])
            if raw.len > 0usize && raw[0usize] != 35u8 && !starts_fold(raw, "data:") && !has_backslash(raw) {
                let (abs, good) = resolve_against(a, base, raw)
                if good {
                    url.buf_str(&out, "url(\"")
                    var k = 0usize
                    while k < abs.len {
                        if abs[k] == 34u8 { url.buf_str(&out, "%22") } else { url.buf_byte(&out, abs[k]) }
                        k += 1usize
                    }
                    url.buf_str(&out, "\")")
                } else {
                    url.buf_str(&out, whole)
                }
            } else {
                url.buf_str(&out, whole)
            }
            i = p
            continue
        }
        url.buf_byte(&out, c)
        i += 1usize
    }
    ret url.buf_take(a, &out)
}

fn has_backslash(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] == 92u8 { ret true }
        i += 1usize
    }
    ret false
}

fn is_ident_byte(c: u8) -> bool {
    ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 45u8 || c == 95u8 || c >= 128u8
}

// XHTML style sheets wrap their text in CDATA markers, which an HTML parse leaves in it: blank them out.
fn strip_cdata(a: *mem.Arena, text: str) -> str {
    let (out, e) = mem.alloc[u8](a, text.len + 1usize)
    if e != ok { ret text }
    var n = 0usize
    var i = 0usize
    while i < text.len {
        if i + 9usize <= text.len && text[i] == 60u8 && text[i + 1usize] == 33u8 && text[i + 2usize] == 91u8 && eq_fold(text[i + 3usize..i + 9usize], "cdata[") {
            i += 9usize
        } else if i + 3usize <= text.len && text[i] == 93u8 && text[i + 1usize] == 93u8 && text[i + 2usize] == 62u8 {
            i += 3usize
        } else {
            out[n] = text[i]
            n += 1usize
            i += 1usize
        }
    }
    ret out[0usize..n]
}

// The `@import` URLs a style sheet text lists, in order.
fn imports_of(a: *mem.Arena, text: str) -> []const str {
    var l = sheet.new_loader(a, sheet.media_env(1280.0f64, 720.0f64))
    let e = sheet.load(&l, text)
    if e != ok { ret zero }
    ret sheet.finish(&l).imports
}

// Appends a sheet and, before it, the sheets it imports (to a depth of four); `base` is the sheet's URL.
fn push_sheet(p: *Page, out: *list.List[str], text_in: str, base: *const url.Url, depth: usize) {
    let imports = imports_of(p.pa, text_in)
    var i = 0usize
    while i < imports.len && depth < 4usize {
        let (abs, good) = resolve_against(p.pa, base, imports[i])
        i += 1usize
        if !good { continue }
        if !csp_url_ok(p, "style-src-elem", abs) { continue }
        let (resp, fe) = fetch.fetch(p.client, get_request(abs, p.url, fetch.Credentials.SameOrigin))
        if fe != ok || resp.status >= 400u16 { continue }
        let (sub_base, be) = url.parse(p.pa, abs, zero, false)
        if be != ok { continue }
        push_sheet(p, out, absolutize_css(p.pa, css_text(p.pa, &resp), &sub_base), &sub_base, depth + 1usize)
    }
    let pushed = list.push[str](out, text_in)
}

// All the page's style sheets in document order: `<style>` text and fetched `<link rel=stylesheet>` sheets.
fn collect_sheets(p: *Page) -> []const str {
    let (made, me) = list.init[str](p.pa, 16usize)
    if me != ok { ret zero }
    var out = made
    let env = sheet.media_env(1280.0f64, 720.0f64)
    let d = &p.tree
    var cur = dom.next_in_tree(d, d.root, d.root)
    while cur != html.NONE {
        if dom.is_html_named(d, cur, "style") {
            let (media, has_media) = dom.get_attribute(d, cur, "media")
            if !has_media || sheet.media_matches(&env, p.pa, media) {
                let (text, te) = dom.text_content(p.pa, d, cur)
                let (nonce, has_nonce) = dom.get_attribute(d, cur, "nonce")
                var inline_ok = true
                if te == ok && !csp_inline_ok(p, "style-src-elem", nonce, text) { inline_ok = false }
                if te == ok && inline_ok { push_sheet(p, &out, absolutize_css(p.pa, strip_cdata(p.pa, text), &p.base), &p.base, 0usize) }
            }
        } else if dom.is_html_named(d, cur, "link") {
            let (rel, has_rel) = dom.get_attribute(d, cur, "rel")
            let (href, has_href) = dom.get_attribute(d, cur, "href")
            let (media2, has_media2) = dom.get_attribute(d, cur, "media")
            if has_rel && has_href && has_token(rel, "stylesheet") && !has_token(rel, "alternate") && href.len > 0usize && (!has_media2 || sheet.media_matches(&env, p.pa, media2)) {
                let (abs, good) = resolve_against(p.pa, &p.base, href)
                if good && csp_url_ok(p, "style-src-elem", abs) {
                    let (resp, fe) = fetch.fetch(p.client, get_request(abs, p.url, fetch.Credentials.SameOrigin))
                    if fe == ok && resp.status < 400u16 {
                        let (sheet_base, be) = url.parse(p.pa, abs, zero, false)
                        if be == ok { push_sheet(p, &out, absolutize_css(p.pa, css_text(p.pa, &resp), &sheet_base), &sheet_base, 0usize) }
                    }
                }
            }
        }
        cur = dom.next_in_tree(d, d.root, cur)
    }
    ret list.slice_const[str](&out)
}

// --- Web fonts.

fn face_weight(w: str) -> u32 {
    let t = str.trim(w)
    if eq_fold(t, "bold") || eq_fold(t, "bolder") { ret 700u32 }
    var n = 0u32
    var i = 0usize
    while i < t.len && t[i] >= 48u8 && t[i] <= 57u8 {
        n = n * 10u32 + u32(t[i] - 48u8)
        i += 1usize
    }
    if n == 0u32 { ret 400u32 }
    ret n
}

// Fetches every `@font-face` the page's sheets declare and registers it in the font set (WOFF/WOFF2 are unpacked to sfnt).
fn load_web_fonts(p: *Page) {
    var si = 0usize
    while si < p.sheets.len {
        var l = sheet.new_loader(p.pa, sheet.media_env(1280.0f64, 720.0f64))
        si += 1usize
        if sheet.load(&l, p.sheets[si - 1usize]) != ok { continue }
        let faces = sheet.finish(&l).fonts
        var fi = 0usize
        while fi < faces.len {
            let f = faces[fi]
            fi += 1usize
            if f.url.len == 0usize || f.family.len == 0usize { continue }
            if !csp_url_ok(p, "font-src", f.url) { continue }
            let (resp, fe) = fetch.fetch(p.client, get_request(f.url, p.url, fetch.Credentials.SameOrigin))
            if fe != ok || resp.status >= 400u16 || resp.body.len < 12usize { continue }
            var data: []const u8 = resp.body
            let b = resp.body
            if b[0] == 119u8 && b[1] == 79u8 && b[2] == 70u8 && b[3] == 70u8 {
                let (sf, we) = woff.to_sfnt(p.pa, b)
                if we != ok { continue }
                data = sf
            } else if b[0] == 119u8 && b[1] == 79u8 && b[2] == 70u8 && b[3] == 50u8 {
                let (sf2, we2) = woff2.to_sfnt(p.pa, b)
                if we2 != ok { continue }
                data = sf2
            }
            let italic = eq_fold(str.trim(f.style), "italic") || starts_fold(str.trim(f.style), "oblique")
            let added = fontset.add(p.fonts, f.family, face_weight(f.weight), italic, data, 0u32)
        }
    }
}

// --- Images.

fn image_entry(p: *Page, abs: str) -> *ImageEntry {
    var i = 0usize
    while i < p.images.len {
        if str.eq(p.images.items[i].url, abs) { ret &p.images.items[i] }
        i += 1usize
    }
    var e: ImageEntry = zero
    e.url = abs
    e.state = 2u8
    if !csp_url_ok(p, "img-src", abs) {
        let blocked = list.push[ImageEntry](&p.images, e)
        ret &p.images.items[p.images.len - 1usize]
    }
    let (resp, fe) = fetch.fetch(p.client, get_request(abs, p.url, fetch.Credentials.SameOrigin))
    if fe == ok && resp.status < 400u16 && resp.body.len > 0usize {
        var st = io.SliceReader { data: resp.body, off: 0usize }
        let src = io.slice_reader(&st)
        let b = resp.body
        var decoded: image.Image = zero
        var good = false
        if b.len >= 8usize && b[0usize] == 137u8 && b[1usize] == 80u8 && b[2usize] == 78u8 && b[3usize] == 71u8 {
            let (im, de) = png.decode(p.pa, src, png.DecodeOptions { max_width: 16384u32, max_height: 16384u32, max_pixels: 67108864u64, verify_crc: false })
            if de == ok {
                decoded = im
                good = true
            }
        } else if b.len >= 3usize && b[0usize] == 255u8 && b[1usize] == 216u8 && b[2usize] == 255u8 {
            let (im2, de2) = jpeg.decode(p.pa, src, jpeg.DecodeOptions { max_width: 16384u32, max_height: 16384u32, max_pixels: 67108864u64 })
            if de2 == ok {
                decoded = im2
                good = true
            }
        } else if b.len >= 6usize && b[0usize] == 71u8 && b[1usize] == 73u8 && b[2usize] == 70u8 {
            let (im3, de3) = gif.decode(p.pa, src, gif.DecodeOptions { max_width: 16384u32, max_height: 16384u32, max_pixels: 67108864u64, max_frames: 1u32, max_bytes: 67108864u64 })
            if de3 == ok {
                decoded = im3
                good = true
            }
        } else if b.len >= 12usize && b[0usize] == 82u8 && b[1usize] == 73u8 && b[8usize] == 87u8 && b[9usize] == 69u8 {
            let (im4, de4) = webp.decode(p.pa, src, webp.DecodeOptions { max_width: 16384u32, max_height: 16384u32, max_pixels: 67108864u64, first_frame_only: true })
            if de4 == ok {
                decoded = im4
                good = true
            }
        }
        if !good && looks_svg(b) {
            let text: str = b
            let (sw, sh, has_size) = svg.intrinsic_size(text)
            e.state = 1u8
            e.svg = text
            e.width = 300u32
            e.height = 150u32
            if has_size {
                e.width = u32(sw + 0.5f32)
                e.height = u32(sh + 0.5f32)
            }
        } else if good {
            e.state = 1u8
            e.img = decoded
            e.width = decoded.width
            e.height = decoded.height
        }
    }
    let pushed = list.push[ImageEntry](&p.images, e)
    ret &p.images.items[p.images.len - 1usize]
}

// An SVG document: `<svg` within the first kilobyte of text.
fn looks_svg(b: []const u8) -> bool {
    var n = b.len
    if n > 1024usize { n = 1024usize }
    var i = 0usize
    while i + 4usize <= n {
        if b[i] == 60u8 && b[i + 1usize] == 115u8 && b[i + 2usize] == 118u8 && b[i + 3usize] == 103u8 { ret true }
        i += 1usize
    }
    ret false
}

// The URL of the picture an `<img>` shows: `src`, else the first `srcset` candidate.
fn img_source(p: *Page, node: html.NodeId) -> (str, bool) {
    let (src, has) = dom.get_attribute(&p.tree, node, "src")
    var raw = str.trim(src)
    if !has || raw.len == 0usize {
        let (set, has_set) = dom.get_attribute(&p.tree, node, "srcset")
        if !has_set { ret ("", false) }
        let first = str.trim(set)
        var e = 0usize
        while e < first.len && first[e] != 32u8 && first[e] != 44u8 && first[e] != 9u8 && first[e] != 10u8 { e += 1usize }
        raw = first[0usize..e]
        if raw.len == 0usize { ret ("", false) }
    }
    let (abs, good) = resolve_against(p.pa, &p.base, raw)
    ret (abs, good)
}

fn attr_number(p: *Page, node: html.NodeId, name: str, fallback: f64) -> f64 {
    let (v, has) = dom.get_attribute(&p.tree, node, name)
    if !has { ret fallback }
    let (n, good) = str.parse_i64(str.trim(v))
    if good != ok || n < 0i64 { ret fallback }
    ret f64(n)
}

fn known(w: f64, h: f64, ratio: f64) -> layout.Intrinsic {
    ret layout.Intrinsic { kind: 2u8, has_width: true, width: w, has_height: true, height: h, ratio: ratio }
}

// The intrinsic size of replaced content and form controls.
fn intrinsic_of(ctx: *void, node: html.NodeId, s: *const style.Style) -> layout.Intrinsic {
    let p = mem.cast[*Page](ctx)
    let n = &p.tree.nodes[usize(node)]
    let name = n.name
    var out: layout.Intrinsic = zero
    if str.eq(name, "img") {
        let (abs, good) = img_source(p, node)
        if good {
            let e = image_entry(p, abs)
            if e.state == 1u8 {
                var ratio = 0.0f64
                if e.height > 0u32 { ratio = f64(e.width) / f64(e.height) }
                ret layout.Intrinsic { kind: 1u8, has_width: true, width: f64(e.width), has_height: true, height: f64(e.height), ratio: ratio }
            }
        }
        out.kind = 1u8
        ret out
    }
    let em = s.font_size
    let m = fontset.metrics(p.fonts, s.font_family, s.font_weight, s.font_style != .Normal, em)
    let line = m.ascent + m.descent + m.line_gap
    if str.eq(name, "input") {
        let (kind, has_kind) = dom.get_attribute(&p.tree, node, "type")
        var t = "text"
        if has_kind { t = str.trim(kind) }
        if eq_fold(t, "checkbox") || eq_fold(t, "radio") { ret known(13.0f64, 13.0f64, 1.0f64) }
        if eq_fold(t, "range") { ret known(129.0f64, 16.0f64, 0.0f64) }
        if eq_fold(t, "color") { ret known(50.0f64, 27.0f64, 0.0f64) }
        if eq_fold(t, "file") { ret known(238.0f64, line + 6.0f64, 0.0f64) }
        if eq_fold(t, "submit") || eq_fold(t, "reset") || eq_fold(t, "button") {
            let (val, has_val) = dom.get_attribute(&p.tree, node, "value")
            var label = "Submit"
            if eq_fold(t, "reset") { label = "Reset" }
            if eq_fold(t, "button") { label = "" }
            if has_val && val.len > 0usize { label = val }
            ret known(fontset.width(p.fonts, s.font_family, s.font_weight, false, em, label), line, 0.0f64)
        }
        if eq_fold(t, "image") { ret known(attr_number(p, node, "width", 20.0f64), attr_number(p, node, "height", 20.0f64), 0.0f64) }
        let size = attr_number(p, node, "size", 20.0f64)
        ret known(size * fontset.width(p.fonts, s.font_family, s.font_weight, false, em, "0") * 1.0f64, line, 0.0f64)
    }
    if str.eq(name, "textarea") {
        let cols = attr_number(p, node, "cols", 20.0f64)
        let rows = attr_number(p, node, "rows", 2.0f64)
        ret known(cols * fontset.width(p.fonts, s.font_family, s.font_weight, false, em, "0"), rows * line, 0.0f64)
    }
    if str.eq(name, "select") {
        var widest = 0.0f64
        var kid = n.first_child
        var guard = 0usize
        while kid != html.NONE && guard < 400usize {
            if p.tree.nodes[usize(kid)].kind == .Element && str.eq(p.tree.nodes[usize(kid)].name, "option") {
                let (t2, te) = dom.text_content(p.pa, &p.tree, kid)
                if te == ok {
                    let wv = fontset.width(p.fonts, s.font_family, s.font_weight, false, em, str.trim(t2))
                    if wv > widest { widest = wv }
                }
            }
            kid = p.tree.nodes[usize(kid)].next_sibling
            guard += 1usize
        }
        let (size_attr, has_size) = dom.get_attribute(&p.tree, node, "size")
        var rows2 = 1.0f64
        if has_size {
            let (rn, rg) = str.parse_i64(str.trim(size_attr))
            if rg == ok && rn > 1i64 { rows2 = f64(rn) }
        }
        ret known(widest + 24.0f64, rows2 * line, 0.0f64)
    }
    if str.eq(name, "progress") { ret known(160.0f64, 16.0f64, 0.0f64) }
    if str.eq(name, "meter") { ret known(80.0f64, 16.0f64, 0.0f64) }
    if str.eq(name, "audio") { ret known(300.0f64, 54.0f64, 0.0f64) }
    if str.eq(name, "svg") {
        let (vb, has_vb) = dom.get_attribute(&p.tree, node, "viewbox")
        out.kind = 1u8
        if has_vb {
            let parts = cv_numbers(p.pa, vb)
            if parts.len == 4usize && parts[2usize] > 0.0f64 && parts[3usize] > 0.0f64 {
                out.ratio = parts[2usize] / parts[3usize]
                out.has_width = false
                out.has_height = false
                ret out
            }
        }
        ret known(300.0f64, 150.0f64, 0.0f64)
    }
    ret known(300.0f64, 150.0f64, 0.0f64)
}

fn cv_numbers(a: *mem.Arena, text: str) -> []const f64 {
    let (out, e) = mem.alloc[f64](a, 8usize)
    if e != ok { ret zero }
    var n = 0usize
    var i = 0usize
    while i < text.len && n < 8usize {
        while i < text.len && (text[i] == 32u8 || text[i] == 44u8 || text[i] == 9u8 || text[i] == 10u8) { i += 1usize }
        let start = i
        while i < text.len && text[i] != 32u8 && text[i] != 44u8 && text[i] != 9u8 && text[i] != 10u8 { i += 1usize }
        if i > start {
            let (v, good) = parse_float(text[start..i])
            if good {
                out[n] = v
                n += 1usize
            }
        }
    }
    ret out[0usize..n]
}

fn parse_float(s: str) -> (f64, bool) {
    var i = 0usize
    var neg = false
    if i < s.len && (s[i] == 45u8 || s[i] == 43u8) {
        neg = s[i] == 45u8
        i += 1usize
    }
    var v = 0.0f64
    var any = false
    while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
        v = v * 10.0f64 + f64(s[i] - 48u8)
        any = true
        i += 1usize
    }
    if i < s.len && s[i] == 46u8 {
        i += 1usize
        var scale = 0.1f64
        while i < s.len && s[i] >= 48u8 && s[i] <= 57u8 {
            v = v + f64(s[i] - 48u8) * scale
            scale = scale / 10.0f64
            any = true
            i += 1usize
        }
    }
    if !any { ret (0.0f64, false) }
    if neg { v = -v }
    ret (v, true)
}

fn upload(p: *Page, e: *ImageEntry) -> cpaint.ImageRef {
    if e.state != 1u8 { ret zero }
    if e.svg.len > 0usize { ret cpaint.ImageRef { found: true, texture: zero, width: f32(e.width), height: f32(e.height), svg: e.svg } }
    if !e.uploaded {
        if !p.has_renderer { ret zero }
        let ci = image.ConstImage { pixels: e.img.pixels, width: e.img.width, height: e.img.height, stride: e.img.stride, format: e.img.format, alpha: e.img.alpha }
        let (tex, ue) = scene.upload_image(p.renderer, ci)
        if ue != ok { ret zero }
        e.texture = tex
        e.uploaded = true
    }
    ret cpaint.ImageRef { found: true, texture: e.texture, width: f32(e.width), height: f32(e.height), svg: "" }
}

fn paint_image_of(ctx: *void, node: html.NodeId) -> cpaint.ImageRef {
    let p = mem.cast[*Page](ctx)
    if !str.eq(p.tree.nodes[usize(node)].name, "img") { ret zero }
    let (abs, good) = img_source(p, node)
    if !good { ret zero }
    let e = image_entry(p, abs)
    ret upload(p, e)
}

fn paint_url_image_of(ctx: *void, u: str) -> cpaint.ImageRef {
    let p = mem.cast[*Page](ctx)
    // Inline style attributes are not rewritten like sheets are, so resolve here.
    let (abs, good) = resolve_against(p.pa, &p.base, u)
    if !good { ret zero }
    let e = image_entry(p, abs)
    ret upload(p, e)
}

// --- Loading.

fn html_wrapper(a: *mem.Arena, kind: u8, body: str, address: str) -> str {
    if kind == 0u8 {
        // Plain text: preformatted.
        var out = url.zero_buf(a, body.len * 6usize + 64usize)
        url.buf_str(&out, "<pre style=\"word-wrap:break-word;white-space:pre-wrap\">")
        var i = 0usize
        while i < body.len {
            let c = body[i]
            if c == 60u8 { url.buf_str(&out, "&lt;") } else if c == 38u8 { url.buf_str(&out, "&amp;") } else { url.buf_byte(&out, c) }
            i += 1usize
        }
        url.buf_str(&out, "</pre>")
        ret url.buf_take(a, &out)
    }
    var out2 = url.zero_buf(a, address.len * 2usize + 64usize)
    url.buf_str(&out2, "<img src=\"")
    url.buf_str(&out2, address)
    url.buf_str(&out2, "\">")
    ret url.buf_take(a, &out2)
}

fn find_title(p: *Page) -> str {
    let d = &p.tree
    var cur = dom.next_in_tree(d, d.root, d.root)
    while cur != html.NONE {
        if dom.is_html_named(d, cur, "title") {
            let (t, e) = dom.text_content(p.pa, d, cur)
            if e == ok { ret collapse_space(p.pa, t) }
        }
        cur = dom.next_in_tree(d, d.root, cur)
    }
    ret ""
}

fn collapse_space(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var n = 0usize
    var pending = false
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 || c == 12u8 {
            pending = n > 0usize
        } else {
            if pending {
                out[n] = 32u8
                n += 1usize
                pending = false
            }
            out[n] = c
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// Loads `address` and opens its view for a `width` x `height` viewport. `view_bytes` sizes the view's private arena.
// --- Scripts.

// A synchronous fetch for the page's scripts: the response body as UTF-8 text.
// The full request of XMLHttpRequest and fetch: the method, header lines and body come from the script, the response goes
// back as text lines of headers and the body bytes.
fn net_hook(ctx: *void, method: str, u: str, header_lines: str, body: []const u8, out: *script.NetResult) -> bool {
    let p = mem.cast[*Page](ctx)
    if !csp_url_ok(p, "connect-src", u) { ret false }
    var m = http.Method.Get
    if str.eq(method, "HEAD") { m = http.Method.Head }
    if str.eq(method, "POST") { m = http.Method.Post }
    if str.eq(method, "PUT") { m = http.Method.Put }
    if str.eq(method, "PATCH") { m = http.Method.Patch }
    if str.eq(method, "DELETE") { m = http.Method.Delete }
    if str.eq(method, "OPTIONS") { m = http.Method.Options }
    let (hl, hle) = list.init[http.Header](p.pa, 16usize)
    if hle != ok { ret false }
    var heads = hl
    var pos = 0usize
    while pos < header_lines.len {
        var end = pos
        while end < header_lines.len && header_lines[end] != 10u8 { end += 1usize }
        let line = header_lines[pos..end]
        pos = end + 1usize
        let (name, value, found) = str.split_once(line, ":")
        if found {
            let pe = list.push[http.Header](&heads, http.Header { name: str.trim(name), value: str.trim(value) })
        }
    }
    let none_body: []const u8 = zero
    var req = fetch.Request { url: u, method: m, headers: list.slice_const[http.Header](&heads), body: body, redirect: fetch.Redirect.Follow, credentials: fetch.Credentials.SameOrigin, referrer: p.url }
    if body.len == 0usize { req.body = none_body }
    let (resp, fe) = fetch.fetch(p.client, req)
    if fe != ok { ret false }
    var lines = ""
    var i = 0usize
    while i < resp.headers.len {
        let (l1, e1) = str.concat(p.pa, resp.headers[i].name, ": ")
        let (l2, e2) = str.concat(p.pa, l1, resp.headers[i].value)
        let (l3, e3) = str.concat(p.pa, l2, "\n")
        let (all, e4) = str.concat(p.pa, lines, l3)
        if e1 == ok && e2 == ok && e3 == ok && e4 == ok { lines = all }
        i += 1usize
    }
    out.status = resp.status
    out.status_text = resp.status_text
    out.url = resp.url
    out.headers = lines
    out.body = resp.body
    ret true
}

fn fetch_text_hook(ctx: *void, u: str, referrer: str) -> (str, u16, bool) {
    let p = mem.cast[*Page](ctx)
    if !csp_url_ok(p, "script-src-elem", u) { ret ("", 0u16, false) }
    let (resp, fe) = fetch.fetch(p.client, get_request(u, p.url, fetch.Credentials.Include))
    if fe != ok { ret ("", 0u16, false) }
    let (text, de) = cjk.decode_sniffing_bom(p.pa, "UTF-8", resp.body)
    if de != ok { ret ("", resp.status, true) }
    ret (text, resp.status, true)
}

// The layout box of a node (layout.NONE when it has none: display none, comments).
fn box_of(p: *Page, node: html.NodeId) -> u32 {
    let v = p.view
    if !p.has_box_map {
        let (m, me) = mem.alloc[u32](p.pa, v.tree.nodes.len)
        if me != ok { ret layout.NONE }
        p.box_map = m
        p.has_box_map = true
        p.box_rev = 0u64
    }
    if p.box_rev != v.revision {
        var i = 0usize
        while i < p.box_map.len {
            p.box_map[i] = layout.NONE
            i += 1usize
        }
        var b = 0usize
        while b < v.lay.boxes.len {
            let bx = &v.lay.boxes.items[b]
            if !bx.anonymous && bx.node != html.NONE && usize(bx.node) < p.box_map.len && p.box_map[usize(bx.node)] == layout.NONE { p.box_map[usize(bx.node)] = u32(b) }
            b += 1usize
        }
        p.box_rev = v.revision
    }
    if usize(node) >= p.box_map.len { ret layout.NONE }
    ret p.box_map[usize(node)]
}

// Scripts asking for geometry or style see the current document: a pending change is laid out first.
fn flush_layout(p: *Page) {
    if p.view.tree.version != p.seen_version { refresh(p) }
}

fn geom_hook(ctx: *void, node: u32, what: u8, out: []f64) -> bool {
    let p = mem.cast[*Page](ctx)
    flush_layout(p)
    let v = p.view
    if what == 4u8 {
        out[0usize] = f64(v.width)
        out[1usize] = f64(v.height)
        out[2usize] = f64(v.scroll_x)
        out[3usize] = f64(v.scroll_y)
        out[4usize] = v.lay.doc_width
        out[5usize] = v.lay.doc_height
        ret true
    }
    let b = box_of(p, node)
    if b == layout.NONE { ret false }
    let l = &v.lay
    let bx = &l.boxes.items[usize(b)]
    if what == 0u8 {
        let r = geom.bounding_rect(v.arena, l, b)
        out[0usize] = r.x - f64(v.scroll_x)
        out[1usize] = r.y - f64(v.scroll_y)
        out[2usize] = r.w
        out[3usize] = r.h
        ret true
    }
    if what == 1u8 {
        let pt = geom.offset_pos(l, b)
        out[0usize] = pt.x
        out[1usize] = pt.y
        out[2usize] = bx.w
        out[3usize] = bx.h
        let op = geom.offset_parent(l, b)
        out[4usize] = -1.0f64
        if op != layout.NONE && l.boxes.items[usize(op)].node != html.NONE { out[4usize] = f64(l.boxes.items[usize(op)].node) }
        ret true
    }
    if what == 2u8 {
        let cs = geom.client_size(l, b)
        out[0usize] = bx.border[3usize]
        out[1usize] = bx.border[0usize]
        out[2usize] = cs.x
        out[3usize] = cs.y
        ret true
    }
    let ss = geom.scroll_size(l, b)
    out[0usize] = ss.x
    out[1usize] = ss.y
    ret true
}

fn style_hook(ctx: *void, node: u32, prop: str) -> (str, bool) {
    let p = mem.cast[*Page](ctx)
    flush_layout(p)
    let v = p.view
    if usize(node) >= v.styles.len { ret ("", false) }
    let s = &v.styles[usize(node)]
    let b = box_of(p, node)
    if b != layout.NONE {
        let bx = &v.lay.boxes.items[usize(b)]
        // Used values: the content box (or border box) width and height, the used margins.
        if str.eq(prop, "width") || str.eq(prop, "height") {
            var w = bx.w
            var h = bx.h
            if s.box_sizing != .BorderBox {
                w = bx.w - bx.border[1usize] - bx.border[3usize] - bx.padding[1usize] - bx.padding[3usize]
                h = bx.h - bx.border[0usize] - bx.border[2usize] - bx.padding[0usize] - bx.padding[2usize]
            }
            if str.eq(prop, "width") { ret (cssom.px_text(p.pa, w), true) }
            ret (cssom.px_text(p.pa, h), true)
        }
        if str.eq(prop, "margin-top") { ret (cssom.px_text(p.pa, bx.margin[0usize]), true) }
        if str.eq(prop, "margin-right") { ret (cssom.px_text(p.pa, bx.margin[1usize]), true) }
        if str.eq(prop, "margin-bottom") { ret (cssom.px_text(p.pa, bx.margin[2usize]), true) }
        if str.eq(prop, "margin-left") { ret (cssom.px_text(p.pa, bx.margin[3usize]), true) }
    }
    let (text, has_value) = cssom.value(p.pa, s, prop)
    ret (text, has_value)
}

// After scripts changed the document: style sheets, title and layout follow.
fn refresh(p: *Page) {
    let v = p.view
    // Scripts grow the view's copy of the tree (node count, version); the page's own copy must follow before it is read.
    p.tree = v.tree
    p.seen_version = v.tree.version
    p.title = find_title(p)
    p.sheets = collect_sheets(p)
    v.sheets = p.sheets
    let re = view.resize(v, p.view_width, p.view_height)
}

// Page scripts run unless a tool turns them off (a page whose scripts exhaust the arena still renders as static markup).
var scripts_enabled: bool = true

fn set_scripts(enabled: bool) { scripts_enabled = enabled }

fn start_scripts(p: *Page) {
    if !scripts_enabled { ret }
    let v = p.view
    let (ctx, xe) = script.new_context(p.pa, &v.tree, p.url)
    if xe != ok { ret }
    p.ctx = ctx
    p.scripted = true
    script.set_fetch(ctx, mem.cast[*void](p), fetch_text_hook)
    if csp.enforced(p.csp) { script.set_csp(ctx, mem.cast[*void](p), csp_hook, !csp.eval_allowed(p.csp)) }
    script.set_net(ctx, mem.cast[*void](p), net_hook)
    script.set_view(ctx, mem.cast[*void](p), geom_hook, style_hook)
    p.seen_version = v.tree.version
    script.lifecycle(ctx, "run")
    let next = script.pump_once(ctx)
    if v.tree.version != p.seen_version { refresh(p) }
}

// The page's event loop: runs promise jobs and the timers that are due at `now_ms` (milliseconds on the host clock, any
// origin as long as it only grows). Answers true when the page changed and was laid out again.
fn tick(p: *Page, now_ms: f64) -> bool {
    if !p.scripted { ret false }
    script.set_clock(p.ctx, now_ms)
    let next = script.pump_once(p.ctx)
    if p.view.tree.version != p.seen_version {
        refresh(p)
        ret true
    }
    ret false
}

// When the next timer is due on the host clock, or -1 when none is pending.
fn next_wakeup(p: *Page) -> f64 {
    if !p.scripted { ret -1.0f64 }
    ret script.next_due(p.ctx)
}

// A pointer click at viewport coordinates reaches the page's scripts; answers false when a handler cancelled the default
// action (the caller then must not follow a link).
fn click(p: *Page, x: f32, y: f32) -> bool {
    if !p.scripted { ret true }
    let v = p.view
    let hit = view.node_at(v, x, y)
    if hit == html.NONE { ret true }
    let go = script.dispatch_mouse(p.ctx, hit, "click", f64(x), f64(y))
    if v.tree.version != p.seen_version { refresh(p) }
    ret go
}

// A location change the scripts asked for, if any.
fn take_navigation(p: *Page) -> (str, bool) {
    if !p.scripted { ret ("", false) }
    let (dest, asked) = script.take_navigation(p.ctx)
    ret (dest, asked)
}

fn load(a: *mem.Arena, client: *fetch.Client, fonts: *fontset.Set, address: str, width: f32, height: f32, view_bytes: usize) -> (*Page, err) {
    let (cell, ce) = mem.alloc[Page](a, 1usize)
    if ce != ok { ret (zero, ce) }
    let p = &cell[0usize]
    p.pa = a
    p.client = client
    p.fonts = fonts
    p.has_renderer = false
    p.scripted = false
    p.csp = csp.PolicySet { items: zero }
    p.has_box_map = false
    p.box_rev = 0u64
    p.seen_version = 0u64
    let (imgs, ie) = list.init[ImageEntry](a, 32usize)
    if ie != ok { ret (zero, ie) }
    p.images = imgs
    let (resp, fe) = fetch.fetch(client, get_request(address, "", fetch.Credentials.Include))
    if fe != ok { ret (zero, fe) }
    p.url = resp.url
    p.status = resp.status
    p.mime = fetch.mime_type(a, &resp)
    var ch = 0usize
    while ch < resp.headers.len {
        if eq_fold(resp.headers[ch].name, "content-security-policy") {
            let (hp, hpe) = csp.parse_set(a, resp.headers[ch].value, false)
            if hpe == ok { p.csp = csp.merge(a, p.csp, hp) }
        }
        ch += 1usize
    }
    let (final_url, ue) = url.parse(a, resp.url, zero, false)
    if ue != ok { ret (zero, LoadFailed) }
    p.base = final_url
    var source: str = ""
    if p.mime.len == 0usize || str.eq(p.mime, "text/html") || str.eq(p.mime, "application/xhtml+xml") || str.eq(p.mime, "application/xml") || str.eq(p.mime, "text/xml") {
        let (text, used, de) = sniff.decode_document(a, resp.body, fetch.charset_param(&resp))
        if de != ok { ret (zero, LoadFailed) }
        p.charset = used
        source = text
    } else if str.eq(p.mime, "text/plain") || str.eq(p.mime, "text/css") || str.eq(p.mime, "application/json") || str.eq(p.mime, "text/javascript") || str.eq(p.mime, "application/javascript") {
        let (text2, used2, de2) = sniff.decode_document(a, resp.body, fetch.charset_param(&resp))
        if de2 != ok { ret (zero, LoadFailed) }
        p.charset = used2
        source = html_wrapper(a, 0u8, text2, resp.url)
    } else if starts_fold(p.mime, "image/") {
        source = html_wrapper(a, 1u8, "", resp.url)
    } else {
        ret (zero, NotRenderable)
    }
    // The browser runs scripts, so <noscript> content is not rendered.
    html.set_xml_syntax(str.eq(p.mime, "application/xhtml+xml"))
    let (tree, pe) = dom.parse_with(a, source, view.parse_options(), 262144usize, true)
    html.set_xml_syntax(false)
    if pe != ok { ret (zero, LoadFailed) }
    p.tree = tree
    // A <meta http-equiv="Content-Security-Policy"> adds a policy for the rest of the document.
    var mcur = dom.next_in_tree(&p.tree, p.tree.root, p.tree.root)
    while mcur != html.NONE {
        if dom.is_html_named(&p.tree, mcur, "meta") {
            let (he, has_he) = dom.get_attribute(&p.tree, mcur, "http-equiv")
            let (mc, has_mc) = dom.get_attribute(&p.tree, mcur, "content")
            if has_he && has_mc && eq_fold(str.trim(he), "content-security-policy") {
                let (mp, mpe) = csp.parse_set(a, mc, false)
                if mpe == ok { p.csp = csp.merge(a, p.csp, mp) }
            }
        }
        mcur = dom.next_in_tree(&p.tree, p.tree.root, mcur)
    }
    // <base href> changes the base for relative references.
    let d = &p.tree
    var cur = dom.next_in_tree(d, d.root, d.root)
    while cur != html.NONE {
        if dom.is_html_named(d, cur, "base") {
            let (href, has) = dom.get_attribute(d, cur, "href")
            if has {
                let (nb, ne2) = url.parse(a, href, &p.base, true)
                if ne2 == ok { p.base = nb }
            }
            break
        }
        cur = dom.next_in_tree(d, d.root, cur)
    }
    p.title = find_title(p)
    p.sheets = collect_sheets(p)
    p.font_base = fonts.faces.len
    load_web_fonts(p)
    // The view's private arena.
    let (backing, be) = mem.alloc[u8](a, view_bytes)
    if be != ok { ret (zero, be) }
    p.va = mem.arena_from(backing)
    let images = view.Images { ctx: mem.cast[*void](p), intrinsic: intrinsic_of, image: paint_image_of, url_image: paint_url_image_of }
    let (v, ve) = view.open_tree(&p.va, p.tree, source, p.sheets, true, fonts, images, width, height)
    if ve != ok { ret (zero, ve) }
    p.view = v
    p.view_width = width
    p.view_height = height
    start_scripts(p)
    ret (p, ok)
}

// Drops the web fonts the page added (the font set outlives pages; the renderer keeps at most 16 faces).
fn release_fonts(p: *Page) {
    if p.fonts.faces.len > p.font_base { p.fonts.faces.len = p.font_base }
}

// Lets the page upload decoded images to `r` the first time it paints them.
fn attach_renderer(p: *Page, r: *scene.Renderer) {
    p.renderer = r
    p.has_renderer = true
    // Faces added since the renderer was set up (web fonts); a registered id is replaced, so this is idempotent.
    var i = 0usize
    while i < p.fonts.faces.len {
        let registered = scene.register_font(r, p.fonts.faces.items[i].font)
        i += 1usize
    }
}
