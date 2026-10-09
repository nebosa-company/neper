// `e.net.cidr` (Terraform's cidrsubnet, cidrhost, cidrnetmask and cidrsubnets over IPv4 prefixes) against
// scripts/cidr_reference.py, which answers each line with Python's `ipaddress` module and its own statement of
// the refusal order: the examples of Terraform's documentation, the edges (prefix lengths 0 and 32, the last
// subnet, hostnum and netnum at and past their limits, negative inputs, malformed prefixes) and seeded random
// cases. A line is `<kind> <args> => <result>`; the kinds are P (parse and re-format), S (subnet), H (host),
// N (netmask) and U (subnets, a list of newbits); a result is the text, or `E:<name>` for a refusal.
use e.net.cidr
use e.io
use e.mem
use e.os

fn same_text(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

// The next space-separated token at or after `at` and the position after it.
fn next_token(line: str, at: usize) -> (str, usize) {
    var p = at
    while p < line.len && line[p] == 32u8 { p += 1usize }
    let start = p
    while p < line.len && line[p] != 32u8 { p += 1usize }
    ret (line[start..p], p)
}

fn integer(token: str) -> i64 {
    var v = 0i64
    var negative = false
    var i = 0usize
    if token.len > 0usize && token[0usize] == 45u8 {
        negative = true
        i = 1usize
    }
    while i < token.len {
        v = v * 10i64 + i64(token[i] - 48u8)
        i += 1usize
    }
    if negative { ret 0i64 - v }
    ret v
}

fn error_name(e: err) -> str {
    if e == cidr.BadPrefix { ret "BadPrefix" }
    if e == cidr.BadLength { ret "BadLength" }
    if e == cidr.LengthTooLong { ret "LengthTooLong" }
    if e == cidr.NotIpv4 { ret "NotIpv4" }
    if e == cidr.BadAddress { ret "BadAddress" }
    if e == cidr.Negative { ret "Negative" }
    if e == cidr.NewbitsTooBig { ret "NewbitsTooBig" }
    if e == cidr.NetnumRange { ret "NetnumRange" }
    if e == cidr.HostRange { ret "HostRange" }
    if e == cidr.DoesNotFit { ret "DoesNotFit" }
    ret "Other"
}

// The result text the library gives for one line, `E:<name>` for a refusal.
fn answer(a: *mem.Arena, line: str) -> str {
    let kind = line[0usize]
    let (prefix, after_prefix) = next_token(line, 2usize)
    var at = after_prefix
    if kind == 80u8 {
        let (p, e) = cidr.parse(prefix)
        if e != ok { ret join2(a, "E:", error_name(e)) }
        let (text, format_error) = cidr.format(a, p)
        if format_error != ok { ret "E:format" }
        ret text
    }
    if kind == 83u8 {
        let (bits_token, after_bits) = next_token(line, at)
        let (num_token, after_num) = next_token(line, after_bits)
        let (text, e) = cidr.subnet_text(a, prefix, integer(bits_token), integer(num_token))
        if e != ok { ret join2(a, "E:", error_name(e)) }
        ret text
    }
    if kind == 72u8 {
        let (num_token, after_num) = next_token(line, at)
        let (text, e) = cidr.host_text(a, prefix, integer(num_token))
        if e != ok { ret join2(a, "E:", error_name(e)) }
        ret text
    }
    if kind == 78u8 {
        let (text, e) = cidr.netmask_text(a, prefix)
        if e != ok { ret join2(a, "E:", error_name(e)) }
        ret text
    }
    // U prefix newbits...
    var bits: [32]i64 = zero
    var count = 0usize
    var more = true
    while more {
        let (token, after) = next_token(line, at)
        at = after
        if token.len == 0usize || same_text(token, "=>") {
            more = false
        } else {
            bits[count] = integer(token)
            count += 1usize
        }
    }
    let (texts, e) = cidr.subnets_text(a, prefix, bits[0usize..count])
    if e != ok { ret join2(a, "E:", error_name(e)) }
    var joined = ""
    var i = 0usize
    while i < texts.len {
        if i > 0usize { joined = join2(a, joined, ",") }
        joined = join2(a, joined, texts[i])
        i += 1usize
    }
    ret joined
}

fn join2(a: *mem.Arena, first: str, second: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, first.len + second.len + 1usize)
    if buffer_error != ok { ret first }
    var n = 0usize
    var i = 0usize
    while i < first.len {
        buffer[n] = first[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < second.len {
        buffer[n] = second[i]
        n += 1usize
        i += 1usize
    }
    ret buffer[0usize..n]
}

// The expected result of a line: what follows ` => `.
fn expected_of(line: str) -> str {
    var i = 0usize
    while i + 3usize < line.len {
        if line[i] == 32u8 && line[i + 1usize] == 61u8 && line[i + 2usize] == 62u8 && line[i + 3usize] == 32u8 { ret line[i + 4usize..line.len] }
        i += 1usize
    }
    ret ""
}

fn run(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let line = text[start..i]
            let mark = mem.mark(a)
            let got = answer(a, line)
            let good = same_text(got, expected_of(line))
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(got)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("net cidr ok")
    ret ok
}
