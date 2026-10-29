use e.fmt.dom as dom
use e.fmt.html as html
use e.mem
use e.os
use e.web.script as script

type ObserverGeometry = struct { target_x: f64 }

fn observer_geom(ctx: *void, node: u32, what: u8, out: []f64) -> bool {
    let geometry = mem.cast[*ObserverGeometry](ctx)
    if what == 4u8 {
        out[0usize] = 100.0f64
        out[1usize] = 100.0f64
        ret true
    }
    if what == 0u8 {
        out[0usize] = geometry.target_x
        out[1usize] = 10.0f64
        out[2usize] = 10.0f64
        out[3usize] = 10.0f64
        ret true
    }
    ret false
}

fn observer_style(ctx: *void, node: u32, property: str) -> (str, bool) { ret ("", false) }

fn main(a: *mem.Arena, args: []str) -> err {
    let options = html.Options { max_bytes: 1048576usize, max_nodes: 4096usize, max_attributes: 64usize, max_depth: 64u16, preserve_comments: false }
    let (parsed, parse_error) = dom.parse(a, "<!doctype html><html><body></body></html>", options, 32usize)
    if parse_error != ok { os.exit(1i32) }
    var tree = parsed
    let (context, context_error) = script.new_context(a, &tree, "https://observer-filter.test/")
    if context_error != ok { os.exit(2i32) }
    var geometry = ObserverGeometry { target_x: 105.0f64 }
    script.set_view(context, mem.cast[*void](&geometry), observer_geom, observer_style)
    let setup = "const target = document.createElement('use'); window.namespacedRecords = []; const observer = new MutationObserver((records) => { window.namespacedRecords = records; }); observer.observe(target, { attributes: true, attributeFilter: ['href'] }); target.setAttributeNS('http://www.w3.org/1999/xlink', 'xlink:href', '#target');"
    if !script.run_script(context, setup, "observer-filter-setup.js") { os.exit(3i32) }
    script.pump(context, 0.0f64)
    let check = "const records = window.namespacedRecords; if (records.length !== 1 || records[0].attributeName !== 'href' || records[0].attributeNamespace !== 'http://www.w3.org/1999/xlink') throw new Error('namespaced attribute filter failed');"
    if !script.run_script(context, check, "observer-filter-check.js") { os.exit(4i32) }
    let margin_setup = "const target = document.createElement('div'); document.body.appendChild(target); window.marginTarget = target; window.marginEntries = []; const observer = new IntersectionObserver((entries) => { window.marginEntries = entries; }, { rootMargin: '0px 10%' }); window.marginObserver = observer; observer.observe(target);"
    if !script.run_script(context, margin_setup, "observer-margin-setup.js") { os.exit(5i32) }
    script.pump(context, 0.0f64)
    let margin_check = "const entry = window.marginEntries[0]; if (window.marginEntries.length !== 1 || !entry.isIntersecting || entry.rootBounds.x !== -10 || entry.rootBounds.width !== 120 || entry.intersectionRect.width !== 5 || entry.intersectionRatio !== 0.5 || window.marginObserver.rootMargin !== '0px 10% 0px 10%') throw new Error('positive rootMargin did not expand the viewport');"
    if !script.run_script(context, margin_check, "observer-margin-check.js") { os.exit(6i32) }
    geometry.target_x = 95.0f64
    let negative_setup = "window.negativeEntries = []; const observer = new IntersectionObserver((entries) => { window.negativeEntries = entries; }, { rootMargin: '-10px' }); window.negativeObserver = observer; observer.observe(window.marginTarget);"
    if !script.run_script(context, negative_setup, "observer-negative-margin-setup.js") { os.exit(7i32) }
    script.pump(context, 0.0f64)
    let negative_check = "const entry = window.negativeEntries[0]; if (window.negativeEntries.length !== 1 || entry.isIntersecting || entry.rootBounds.x !== 10 || entry.rootBounds.width !== 80 || entry.intersectionRect.width !== 0) throw new Error('negative rootMargin did not shrink the viewport'); try { new IntersectionObserver(() => {}, { rootMargin: '1em' }); throw new Error('unsupported rootMargin was accepted'); } catch (error) { if (!(error instanceof SyntaxError)) throw error; }"
    if !script.run_script(context, negative_check, "observer-negative-margin-check.js") { os.exit(8i32) }
    ret ok
}
