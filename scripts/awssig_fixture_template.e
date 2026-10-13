// `x.cloud.awssig` against botocore's `SigV4Auth` / `S3SigV4Auth`: scripts/awssig_vectors.py signs generated requests with
// botocore (a fixed clock, fixed credentials) and writes one JSON line per request with the canonical request, the string
// to sign, the signature and the headers the request ends with; the fixture signs the same request with the module and
// compares the canonical JSON of the answer. Generated; do not edit.
use e.algo.chain as chain
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.cloud.awssig as sig

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn run_case(a: *mem.Arena, line: str, c: json.Value) -> bool {
    let got = sig.sign_json(a, ir.value_of(c, "req"))
    let (got_text, ge) = chain.canonical_json(a, got)
    let (want_text, we) = chain.canonical_json(a, ir.value_of(c, "e"))
    if ge != ok || we != ok { ret false }
    if !str.eq(got_text, want_text) {
        let shown = io.print(join(a, join(a, "\nGOT  ", got_text), join(a, "\nWANT ", join(a, want_text, join(a, "\n", line)))))
        ret false
    }
    ret true
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: true, max_depth: 60u16 })
            if parse_error != ok || !run_case(a, line, root) { ret 1u8 }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("x cloud awssig ok")
    ret ok
}
