// `x.cloud.awsreq` against botocore's serializers: scripts/awsreq_vectors.py takes operations of IAM, STS, SNS, RDS, CloudFormation,
// EC2 and Lightsail from botocore's service models, draws parameter sets from each operation's input shape and serializes
// them with botocore's own `QuerySerializer`, `EC2Serializer` and `JSONSerializer`. A chunk is one operation: its first line
// the call (protocol, names, the closure of the input shape), the others a parameter set and botocore's request (method,
// path, headers, body text). Generated; do not edit.
use e.algo.chain as chain
use e.algo.ir as ir
use e.fmt.json as json
use e.io
use e.mem
use e.os
use e.str
use x.cloud.awsreq as req

fn join(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(80i32) }
    ret out
}

fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    var call: json.Value = .Null
    var have_call = false
    while i < body.len {
        if body[i] == 10u8 {
            let line = body[start..i]
            let (root, parse_error) = json.parse(a, line, json.Options { allow_duplicate_keys: true, max_depth: 80u16 })
            if parse_error != ok { ret 2u8 }
            if !have_call {
                call = root
                have_call = true
            } else {
                let mark = mem.mark(a)
                let (got, fine) = req.build(a, call, ir.value_of(root, "params"))
                if !fine { ret 3u8 }
                let (got_text, ge) = chain.canonical_json(a, got)
                let (want_text, we) = chain.canonical_json(a, ir.value_of(root, "e"))
                if ge != ok || we != ok { ret 4u8 }
                if !str.eq(got_text, want_text) {
                    let shown = io.print(join(a, join(a, "\nGOT  ", got_text), join(a, "\nWANT ", join(a, want_text, join(a, "\n", line)))))
                    ret 1u8
                }
                mem.reset(a, mark)
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("x cloud awsreq ok")
    ret ok
}
