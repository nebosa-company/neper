// Driving a loaded page through the browser control's eval surface (browser tracker 7.1).
//
// A host embedding the browser needs to run JavaScript in the page's own realm and read what it produced - fill a field,
// click a control, read back the result. `e.ui.browser` exposes that as `eval_js`, `eval_value`, `eval_truthy` and
// `wait_for`, which sit on `page.eval_js` / `page.eval_value`. This fixture loads a real page with `page.load` and drives
// it through the same `page` entry points the control uses, so it covers the path end to end without a window or a GPU.
//
// Each failure returns a distinct error so the exit status names the step.
use e.fs
use e.mem
use e.net.fetch as fetch
use e.str
use e.text.fontset as fontset
use e.web.page as page

error FontBytesFailed
error ClientFailed
error FontsFailed
error FontAddFailed
error LoadFailed
error Eval1
error Eval2
error Eval3
error Eval4
error ThrowReportedAsSuccess
error ThrowNotDescribed
error ValueWrong
error ValueThrew
error WaitFailed
error WaitFoundNothing
error QueryWrong
error QueryMissed
error AttrWrong
error NumberWrong
error AllWrong
error AllMissed
error SetFailed
error SetNotSeen
error SetNoEvents

// The page has no external references; a font still has to be registered or layout has no generic family to fall back to.
fn load_page(a: *mem.Arena) -> (*page.Page, err) {
    let (bytes, be) = fs.read_file(a, "tests/browser/assets/ahem.ttf", 1048576usize)
    if be != ok { ret (zero, FontBytesFailed) }
    var (client, ce) = fetch.client(a, fetch.default_config(""), 16usize)
    if ce != ok { ret (zero, ClientFailed) }
    var (fonts, fe) = fontset.new(a)
    if fe != ok { ret (zero, FontsFailed) }
    if fontset.add(&fonts, "Ahem", 400u32, false, bytes, 0u32) != ok { ret (zero, FontAddFailed) }
    fontset.set_generic(&fonts, "sans-serif", "Ahem")
    fontset.set_generic(&fonts, "serif", "Ahem")
    let html = "data:text/html,<title>t</title><div id=box>0</div><button class='primary' data-note=\"it's here\">Go</button><ul><li>a</li><li>b</li></ul><input id=q>"
    let (p, pe) = page.load(a, &client, &fonts, html, 800.0, 600.0, 134217728usize)
    ret (p, pe)
}

fn main(a: *mem.Arena, args: []str) -> err {
    page.set_scripts(true)
    let (p, le) = load_page(a)
    if le != ok { ret LoadFailed }
    // 1. A script runs and its effect survives into a later evaluation: one realm, reused.
    if !page.eval_js(p, "window.__counter = 1") { ret Eval1 }
    if !page.eval_js(p, "if (window.__counter !== 1) throw new Error('realm not reused')") { ret Eval2 }
    // 2. The DOM can be written and read back.
    if !page.eval_js(p, "document.getElementById('box').textContent = 'driven'") { ret Eval3 }
    if !page.eval_js(p, "if (document.getElementById('box').textContent !== 'driven') throw new Error('DOM write lost')") { ret Eval4 }
    // 3. An expression's value comes back as a string, which is the read half the control needs.
    let (text, usable) = page.eval_value(p, "document.getElementById('box').textContent")
    if !usable { ret ValueThrew }
    if !str.eq(text, "driven") { ret ValueWrong }
    let (sum, sum_ok) = page.eval_value(p, "1 + 41")
    if !sum_ok { ret ValueThrew }
    if !str.eq(sum, "42") { ret ValueWrong }
    // 4. A throw is reported rather than swallowed, and names the exception.
    if page.eval_js(p, "throw new Error('deliberate')") { ret ThrowReportedAsSuccess }
    let why = page.eval_error(p)
    if !str.contains(why, "deliberate") { ret ThrowNotDescribed }
    // 5. A timer the page scheduled is driven to completion by polling with the clock advanced, not starved.
    if !page.eval_js(p, "window.__later = false; setTimeout(function () { window.__later = true; }, 50)") { ret WaitFailed }
    let (before, before_ok) = page.eval_value(p, "window.__later === true")
    if !before_ok { ret ValueThrew }
    if str.eq(before, "true") { ret WaitFoundNothing }
    var now = 0.0f64
    var held = false
    var steps = 0usize
    while steps < 200usize && !held {
        let due = page.next_wakeup(p)
        if due > now {
            now = due
        }
        now = now + 1.0f64
        let changed = page.tick(p, now)
        let (now_text, now_ok) = page.eval_value(p, "window.__later === true")
        if now_ok && str.eq(now_text, "true") { held = true }
        if due < 0.0f64 && !changed { break }
        steps += 1usize
    }
    if !held { ret WaitFailed }
    // 6. Selector queries: the first match's text, an attribute, and a miss reported as a miss.
    let (label, found) = page.query_text(p, "button.primary")
    if !found { ret QueryMissed }
    if !str.eq(label, "Go") { ret QueryWrong }
    let (note, note_found) = page.query_attr(p, "button.primary", "data-note")
    if !note_found { ret QueryMissed }
    if !str.eq(note, "it's here") { ret AttrWrong }
    // A quote in the selector must not break out of the injected literal: this is a valid selector that matches nothing.
    let (missing, missing_found) = page.query_text(p, "[data-none='x']")
    if missing_found { ret QueryWrong }
    if !str.eq(missing, "") { ret QueryWrong }
    // 7. A number comes back as a number.
    let (count, count_ok) = page.eval_number(p, "document.querySelectorAll('button').length")
    if !count_ok { ret NumberWrong }
    if count != 1.0f64 { ret NumberWrong }
    // 8. Every match, joined: two list items come back separated by the separator.
    let (items, items_found) = page.query_all_text(p, "li", "|")
    if !items_found { ret AllMissed }
    if !str.eq(items, "a|b") { ret AllWrong }
    let (none, none_found) = page.query_all_text(p, "li.missing", "|")
    if none_found { ret AllWrong }
    if !str.eq(none, "") { ret AllWrong }
    // 9. Writing a value dispatches input and change, which the page's own listeners must observe.
    if !page.eval_js(p, "window.__seen = []; const q = document.getElementById('q'); q.addEventListener('input', function () { window.__seen.push('input:' + q.value); }); q.addEventListener('change', function () { window.__seen.push('change:' + q.value); });") { ret SetFailed }
    if !page.set_value(p, "#q", "hello") { ret SetFailed }
    let (seen, seen_ok) = page.eval_value(p, "window.__seen.join(',')")
    if !seen_ok { ret SetNotSeen }
    if !str.eq(seen, "input:hello,change:hello") { ret SetNoEvents }
    let (qval, qval_ok) = page.eval_value(p, "document.getElementById('q').value")
    if !qval_ok { ret SetNotSeen }
    if !str.eq(qval, "hello") { ret SetNotSeen }
    page.close(p)
    ret ok
}
