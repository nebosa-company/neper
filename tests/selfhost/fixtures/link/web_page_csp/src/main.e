// A page's Content Security Policy as the loader applies it: a `<meta http-equiv>` policy stops inline scripts without a matching
// nonce, lets the nonce'd one run, and `eval` is refused unless `'unsafe-eval'` is listed; a page with no policy runs everything.
use e.fs
use e.mem
use e.net.fetch as fetch
use e.os
use e.str
use e.text.fontset as fontset
use e.web.page as page

fn title_of(a: *mem.Arena, fonts: *fontset.Set, client: *fetch.Client, body: str) -> str {
    let (address, ae) = str.concat(a, "data:text/html,", body)
    if ae != ok { os.exit(90i32) }
    let (pg, e) = page.load(a, client, fonts, address, 400.0f32, 200.0f32, 16777216usize)
    if e != ok { os.exit(91i32) }
    ret pg.title
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
    ret ok
}
