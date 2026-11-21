// e.fmt.xsd.schema against R's xml2 xml_validate (libxml2's XML Schema validator): the built-in
// datatypes, facets, lists and unions, and content models. tests/oracle/xml2_xsd.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R xml2_xsd`. A case holds the schema and the
// instance ("in") and R's verdict as TRUE, FALSE or ERR (a schema or instance libxml2 refuses).

use e.fmt.xsd.schema as sx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> str {
    let (s, load_error) = sx.load_libxml2(a, c.inputs[0usize])
    if load_error != ok { ret "ERR" }
    let (r, validate_error) = sx.validate_text(a, &s, c.inputs[1usize])
    if validate_error != ok { ret "ERR" }
    if r.valid { ret "TRUE" }
    ret "FALSE"
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/xml2_xsd.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let text = answer(a, c)
        if !oracle.agrees_text(text, c) {
            failures += 1usize
            if failures <= 400usize {
                let schema = c.inputs[0usize]
                var shown = schema
                if schema.len > 150usize { shown = schema[60usize..150usize] }
                let _ = io.print(shown)
                let _ = io.print(" |")
                let _ = io.print(c.inputs[1usize])
                let _ = io.print("| got ")
                let _ = io.print(text)
                let _ = io.print(" R ")
                let _ = io.print(c.text)
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
