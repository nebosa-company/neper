use e.fmt.dom as dom
use e.fmt.html as html
use e.mem
use e.os
use e.web.script as script

fn main(a: *mem.Arena, args: []str) -> err {
    let options = html.Options { max_bytes: 1048576usize, max_nodes: 4096usize, max_attributes: 64usize, max_depth: 64u16, preserve_comments: false }
    let (parsed, parse_error) = dom.parse(a, "<!doctype html><html><body></body></html>", options, 32usize)
    if parse_error != ok { os.exit(1i32) }
    var tree = parsed
    let (context, context_error) = script.new_context(a, &tree, "https://formdata-pristine.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const form = document.createElement('form'); const text = document.createElement('input'); text.setAttribute('name', 'text'); text.setAttribute('value', 'hello'); const checkbox = document.createElement('input'); checkbox.setAttribute('type', 'checkbox'); checkbox.setAttribute('name', 'check'); checkbox.setAttribute('checked', ''); const radio = document.createElement('input'); radio.setAttribute('type', 'radio'); radio.setAttribute('name', 'radio'); radio.setAttribute('value', 'yes'); radio.setAttribute('checked', ''); form.appendChild(text); form.appendChild(checkbox); form.appendChild(radio); document.body.appendChild(form); window.checkboxChecked = checkbox.checked; window.radioChecked = radio.checked; window.checkboxType = checkbox.type; window.radioType = radio.type; window.textName = text.getAttribute('name'); window.checkboxName = checkbox.getAttribute('name'); window.radioName = radio.getAttribute('name'); window.formLength = form.elements.length; const data = new FormData(form); window.text = data.get('text'); window.check = data.get('check'); window.radio = data.get('radio'); window.textHas = data.has('text'); window.checkHas = data.has('check'); window.radioHas = data.has('radio');"
    if !script.run_script(context, setup, "formdata-pristine-setup.js") { os.exit(3i32) }
    let state_check = "if (window.checkboxChecked !== true || window.radioChecked !== true || window.checkboxType !== 'checkbox' || window.radioType !== 'radio' || window.textName !== 'text' || window.checkboxName !== 'check' || window.radioName !== 'radio' || window.formLength !== 3) throw new Error('pristine controls were not constructed correctly');"
    if !script.run_script(context, state_check, "formdata-pristine-state-check.js") { os.exit(6i32) }
    let text_check = "if (window.textHas !== true || window.text !== 'hello') throw new Error('ordinary form control was omitted from FormData');"
    if !script.run_script(context, text_check, "formdata-pristine-text-check.js") { os.exit(9i32) }
    let checkbox_has_check = "if (window.checkHas !== true) throw new Error('pristine checked checkbox was omitted from FormData');"
    if !script.run_script(context, checkbox_has_check, "formdata-pristine-checkbox-has-check.js") { os.exit(4i32) }
    let check = "if (window.check !== 'on') throw new Error('pristine checked checkbox has the wrong FormData value');"
    if !script.run_script(context, check, "formdata-pristine-checkbox-value-check.js") { os.exit(7i32) }
    let radio_has_check = "if (window.radioHas !== true) throw new Error('pristine checked radio was omitted from FormData');"
    if !script.run_script(context, radio_has_check, "formdata-pristine-radio-has-check.js") { os.exit(5i32) }
    let radio_check = "if (window.radio !== 'yes') throw new Error('pristine checked radio has the wrong FormData value');"
    if !script.run_script(context, radio_check, "formdata-pristine-radio-value-check.js") { os.exit(8i32) }
    ret ok
}
