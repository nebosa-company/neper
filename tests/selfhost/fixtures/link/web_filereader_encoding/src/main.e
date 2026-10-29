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
    let (context, context_error) = script.new_context(a, &tree, "https://filereader-encoding.test/")
    if context_error != ok { os.exit(2i32) }
    let setup = "const explicit = new FileReader(); const alias = new FileReader(); const mimeAbsent = new FileReader(); const mimeInvalid = new FileReader(); const utf8Fallback = new FileReader(); const bom = new FileReader(); explicit.readAsText(new Blob([new Uint8Array([128])], { type: 'text/plain;charset=utf-8' }), 'windows-1252'); alias.readAsText(new Blob([new Uint8Array([128])]), ' Cp1252 '); mimeAbsent.readAsText(new Blob([new Uint8Array([128])], { type: 'text/plain; charset=\"windows-1252\"' })); mimeInvalid.readAsText(new Blob([new Uint8Array([128])], { type: 'text/plain;charset=windows-1252' }), 'not-a-label'); utf8Fallback.readAsText(new Blob([new Uint8Array([195, 169])]), 'not-a-label'); bom.readAsText(new Blob([new Uint8Array([255, 254, 65, 0])]), 'windows-1252'); window.fileReaders = [explicit, alias, mimeAbsent, mimeInvalid, utf8Fallback, bom];"
    if !script.run_script(context, setup, "filereader-encoding-setup.js") { os.exit(3i32) }
    script.pump(context, 0.0f64)
    let check = "const readers = window.fileReaders; if (readers.some(reader => reader.readyState !== FileReader.DONE)) throw new Error('FileReader did not finish'); if (readers[0].result.length !== 1 || readers[0].result.charCodeAt(0) !== 8364) throw new Error('explicit encoding did not override MIME charset'); if (readers[1].result.length !== 1 || readers[1].result.charCodeAt(0) !== 8364) throw new Error('encoding label aliases were not resolved'); if (readers[2].result.length !== 1 || readers[2].result.charCodeAt(0) !== 8364) throw new Error('Blob MIME charset was not used when label was absent'); if (readers[3].result.length !== 1 || readers[3].result.charCodeAt(0) !== 8364) throw new Error('Blob MIME charset was not used after an invalid label'); if (readers[4].result.length !== 1 || readers[4].result.charCodeAt(0) !== 233) throw new Error('invalid label did not fall back to UTF-8'); if (readers[5].result !== 'A') throw new Error('BOM did not override the requested encoding');"
    if !script.run_script(context, check, "filereader-encoding-check.js") { os.exit(4i32) }
    ret ok
}
