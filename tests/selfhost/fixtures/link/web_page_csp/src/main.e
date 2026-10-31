// A page's Content Security Policy as the loader applies it: a `<meta http-equiv>` policy stops inline scripts without a matching
// nonce, lets the nonce'd one run, and `eval` is refused unless `'unsafe-eval'` is listed; a page with no policy runs everything.
use e.bytes
use e.fs
use e.fmt.dom as dom
use e.fmt.html as html
use e.mem
use e.net.fetch as fetch
use e.os
use e.str
use e.text.fontset as fontset
use e.web.page as page
use e.web.script as script

type FetchProbe = struct { requests: u32, credentialed: u32 }

fn capture_script(ctx: *void, u: str, referrer: str, include_credentials: bool) -> (str, u16, bool) {
    let probe = mem.cast[*FetchProbe](ctx)
    probe.requests += 1u32
    if include_credentials { probe.credentialed += 1u32 }
    if str.ends_with(u, "root-plain.js") { ret ("import './child-plain.js'", 200u16, true) }
    if str.ends_with(u, "root-credentials.js") { ret ("import './child-credentials.js'", 200u16, true) }
    ret ("", 200u16, true)
}

fn script_credentials(a: *mem.Arena) -> bool {
    let options = html.Options { max_bytes: 1048576usize, max_nodes: 4096usize, max_attributes: 64usize, max_depth: 64u16, preserve_comments: false }
    let source = "<!doctype html><script src=https://cdn.test/plain.js></script><script src=https://cdn.test/credentials.js crossorigin=USE-CREDENTIALS></script><script type=module src=https://cdn.test/root-plain.js></script><script type=module src=https://cdn.test/root-credentials.js crossorigin=use-credentials></script>"
    let (parsed, pe) = dom.parse(a, source, options, 32usize)
    if pe != ok { ret false }
    var tree = parsed
    let (it, ie) = script.new_context(a, &tree, "https://page.test/index.html")
    if ie != ok { ret false }
    var probe: FetchProbe = zero
    script.set_fetch(it, mem.cast[*void](&probe), capture_script)
    script.lifecycle(it, "run")
    script.pump(it, 0.0f64)
    ret probe.requests == 6u32 && probe.credentialed == 3u32
}

fn title_of(a: *mem.Arena, fonts: *fontset.Set, client: *fetch.Client, body: str) -> str {
    let (address, ae) = str.concat(a, "data:text/html,", body)
    if ae != ok { os.exit(90i32) }
    let (pg, e) = page.load(a, client, fonts, address, 400.0f32, 200.0f32, 16777216usize)
    if e != ok { os.exit(91i32) }
    ret pg.title
}

// Initial style collection happens before a view exists. It must nevertheless
// use Page.load's requested viewport for style/link/import/font media rules.
fn initial_media_regression(a: *mem.Arena, fonts: *fontset.Set, client: *fetch.Client) -> bool {
    let (font_bytes, font_error) = fs.read_file(a, "tests/browser/assets/ahem.ttf", 65536usize)
    if font_error != ok { ret false }
    let (encoded_len, length_error) = bytes.base64_encoded_len(font_bytes.len, true)
    if length_error != ok { ret false }
    let (encoded, encoded_error) = mem.alloc[u8](a, encoded_len)
    if encoded_error != ok { ret false }
    let (font_text, encode_error) = bytes.base64_encode(encoded, font_bytes, .Standard, true)
    if encode_error != ok { ret false }
    let (builder0, builder_error) = str.builder(a, font_text.len + 1024usize)
    if builder_error != ok { ret false }
    var builder = builder0
    if str.push(&builder, "<style media=\"(max-width: 600px)\">.inline-narrow{color:red}</style><style media=\"(min-width: 601px)\">.inline-wide{color:blue}</style><style>@import url(\"data:text/css,.import-wide%7Bcolor%3Ablue%7D\") screen and (min-width: 601px);.base-rule{color:black}</style><link rel=\"stylesheet\" media=\"(min-width: 601px)\" href=\"data:text/css,.link-wide%7Bcolor%3Agreen%7D\"><style media=\"(min-width: 601px)\">@font-face{font-family:ViewportProbe;src:url(data:font/ttf;base64,") != ok { ret false }
    if str.push(&builder, font_text) != ok { ret false }
    if str.push(&builder, ")}</style>") != ok { ret false }
    let body = str.done(&builder)
    let (address, address_error) = str.concat(a, "data:text/html,", body)
    if address_error != ok { ret false }

    let before = fonts.faces.len
    let (narrow, narrow_error) = page.load(a, client, fonts, address, 400.0f32, 200.0f32, 16777216usize)
    if narrow_error != ok { ret false }
    if narrow.sheets.len != 2usize || !str.contains(narrow.sheets[0usize], ".inline-narrow") || !str.contains(narrow.sheets[1usize], ".base-rule") || fonts.faces.len != before { ret false }
    page.close(narrow)
    if fonts.faces.len != before { ret false }

    let (wide, wide_error) = page.load(a, client, fonts, address, 800.0f32, 200.0f32, 16777216usize)
    if wide_error != ok { ret false }
    let wide_ok = wide.sheets.len == 5usize && str.contains(wide.sheets[0usize], ".inline-wide") && str.contains(wide.sheets[1usize], ".import-wide") && str.contains(wide.sheets[2usize], ".base-rule") && str.contains(wide.sheets[3usize], ".link-wide") && str.contains(wide.sheets[4usize], "ViewportProbe") && fonts.faces.len == before + 1usize
    page.close(wide)
    if fonts.faces.len != before { ret false }
    ret wide_ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (made, me) = fontset.new(a)
    if me != ok { os.exit(1i32) }
    var fonts = made
    let (data, fe) = fs.read_file(a, "docs/ui/looks/ref/linux/fonts/Cantarell-Regular.ttf", 16777216usize)
    if fe != ok { os.exit(2i32) }
    let added = fontset.add(&fonts, "Arial", 400u32, false, data, 0u32)
    fontset.set_generic(&fonts, "sans-serif", "Arial")
    fontset.set_generic(&fonts, "serif", "Arial")
    fontset.set_generic(&fonts, "monospace", "Arial")
    let (cl, ce) = fetch.client(a, fetch.default_config(""), 16usize)
    if ce != ok { os.exit(3i32) }
    var client = cl
    // 3. A nonce lets exactly the matching script run.
    let t3 = title_of(a, &fonts, &client, "<meta http-equiv=Content-Security-Policy content=\"script-src 'nonce-abc'\"><title>t</title><script>document.title='bad'</script><script nonce=abc>document.title='good'</script>")
    if !str.eq(t3, "good") { os.exit(12i32 + i32(t3.len)) }
    // 1. No policy: an inline script runs.
    if !str.eq(title_of(a, &fonts, &client, "<title>t</title><script>document.title='ran'</script>"), "ran") { os.exit(10i32) }
    // 2. script-src 'none': it does not.
    if !str.eq(title_of(a, &fonts, &client, "<meta http-equiv=Content-Security-Policy content=\"script-src 'none'\"><title>t</title><script>document.title='ran'</script>"), "t") { os.exit(11i32) }
    // 4. eval is refused without 'unsafe-eval'.
    if !str.eq(title_of(a, &fonts, &client, "<meta http-equiv=Content-Security-Policy content=\"script-src 'unsafe-inline'\"><title>t</title><script>try{eval('1');document.title='evaled'}catch(e){document.title=e.name}</script>"), "EvalError") { os.exit(13i32) }
    if !str.eq(title_of(a, &fonts, &client, "<meta http-equiv=Content-Security-Policy content=\"script-src 'unsafe-inline' 'unsafe-eval'\"><title>t</title><script>try{eval('1');document.title='evaled'}catch(e){document.title=e.name}</script>"), "evaled") { os.exit(14i32) }
    // 5. Only an explicit crossorigin=use-credentials script/module graph asks the page to include cookies.
    if !initial_media_regression(a, &fonts, &client) { os.exit(16i32) }
    if !script_credentials(a) { os.exit(15i32) }
    // 6. A geometry lookup before insertion does not leave the inserted node outside the box cache.
    if !str.eq(title_of(a, &fonts, &client, "<script>document.body.getBoundingClientRect();let e=document.createElement('div');e.setAttribute('style','width:37px;height:19px');document.body.appendChild(e);let r=e.getBoundingClientRect();document.title=r.width+'x'+r.height</script>"), "37x19") { os.exit(16i32) }
    // 7. viewBox accepts exponent form but rejects a token with trailing CSS text.
    if !str.eq(title_of(a, &fonts, &client, "<svg viewBox=\"0 0 1e2 25\" style=\"width:100px\"></svg><script>let r=document.querySelector('svg').getBoundingClientRect();document.title=r.width+'x'+r.height</script>"), "100x25") { os.exit(17i32) }
    if !str.eq(title_of(a, &fonts, &client, "<svg viewBox=\"0 0 10px 25\" style=\"width:100px\"></svg><script>let r=document.querySelector('svg').getBoundingClientRect();document.title=r.width+'x'+r.height</script>"), "100x50") { os.exit(18i32) }
    ret ok
}
