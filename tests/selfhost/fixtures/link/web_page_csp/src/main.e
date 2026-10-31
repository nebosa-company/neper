// A page's Content Security Policy as the loader applies it: a `<meta http-equiv>` policy stops inline scripts without a matching
// nonce, lets the nonce'd one run, and `eval` is refused unless `'unsafe-eval'` is listed; a page with no policy runs everything.
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
    if !script_credentials(a) { os.exit(15i32) }
    // 6. A geometry lookup before insertion does not leave the inserted node outside the box cache.
    if !str.eq(title_of(a, &fonts, &client, "<script>document.body.getBoundingClientRect();let e=document.createElement('div');e.setAttribute('style','width:37px;height:19px');document.body.appendChild(e);let r=e.getBoundingClientRect();document.title=r.width+'x'+r.height</script>"), "37x19") { os.exit(16i32) }
    // 7. viewBox accepts exponent form but rejects a token with trailing CSS text.
    if !str.eq(title_of(a, &fonts, &client, "<svg viewBox=\"0 0 1e2 25\" style=\"width:100px\"></svg><script>let r=document.querySelector('svg').getBoundingClientRect();document.title=r.width+'x'+r.height</script>"), "100x25") { os.exit(17i32) }
    if !str.eq(title_of(a, &fonts, &client, "<svg viewBox=\"0 0 10px 25\" style=\"width:100px\"></svg><script>let r=document.querySelector('svg').getBoundingClientRect();document.title=r.width+'x'+r.height</script>"), "100x50") { os.exit(18i32) }
    ret ok
}
