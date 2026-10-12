#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_sse/src/main.e (C171): e.fmt.sse against an independent Python parser of
the HTML Living Standard's event-stream algorithm. Whole streams are compared field by field and, for every prefix of
every stream, the number of events the incremental reader dispatches is compared (so a half-delivered event, a CR that
may be half a CRLF and a comment are all exercised)."""
from pathlib import Path

STREAMS = {
    "plain": b"data: hello\n\ndata: a\ndata: b\n\nevent: ping\ndata: x\nid: 7\nretry: 3000\n\n",
    "mixed": b": comment\r\ndata:no space\r\n\r\nevent:e\rdata: y\r\r:tail\n\ndata: last\r\n\r\n",
    "odd": b"id: a\x00b\ndata: z\n\nretry: abc\ndata: q\n\nfoo: bar\n\ndata\n\nretry: 15\nevent: e2\n\ndata: kept\nid:\n\n",
}


def lines_of(data, upto):
    """Complete lines of data[:upto] by the incremental reader's rule: a CR at the very end is not yet a line end."""
    out = []
    i = 0
    start = 0
    n = upto
    while i < n:
        c = data[i]
        if c == 10:
            out.append((data[start:i], i + 1))
            i += 1
            start = i
        elif c == 13:
            if i + 1 >= n:
                break
            nxt = i + 2 if data[i + 1] == 10 else i + 1
            out.append((data[start:i], nxt))
            i = nxt
            start = i
        else:
            i += 1
    return out


def events_of(data, upto):
    events = []
    buf = []
    kind = b""
    last_id = None
    retry = None
    for line, _ in lines_of(data, upto):
        if line == b"":
            if buf:
                events.append((kind, b"\n".join(buf), last_id, retry))
            buf = []
            kind = b""
            last_id = None
            retry = None
            continue
        if line.startswith(b":"):
            continue
        if b":" in line:
            field, value = line.split(b":", 1)
            if value.startswith(b" "):
                value = value[1:]
        else:
            field, value = line, b""
        if field == b"data":
            buf.append(value)
        elif field == b"event":
            kind = value
        elif field == b"id":
            if b"\x00" not in value:
                last_id = value
        elif field == b"retry":
            if value.isdigit():
                retry = int(value)
    return events


def e_bytes_literal(b):
    return "[%d]u8{ %s }" % (len(b), ", ".join(str(x) + "u8" for x in b))


def e_string(s):
    out = ""
    for ch in s.decode("latin-1"):
        out += {"\n": "\\n", "\r": "\\r", "\t": "\\t", '"': '\\"', "\\": "\\\\"}.get(ch, ch)
    return '"%s"' % out


def main():
    out = ["// `e.fmt.sse` against the HTML Living Standard's event-stream algorithm as an independent Python parser\n",
           "// (scripts/gen_sse_test.py): whole streams field by field, then every prefix of every stream, counting the events\n",
           "// the incremental reader dispatches. Every check has its own exit code.\n",
           "use e.os\nuse e.mem\nuse e.str\nuse e.fmt.sse as sse\n\n",
           "fn count_events(a: *mem.Arena, data: []const u8) -> usize {\n",
           "    var at = 0usize\n    var n = 0usize\n    var more = true\n",
           "    while more {\n        let (ev, after, whole, e) = sse.next(a, data, at)\n",
           "        if e != ok || !whole {\n            more = false\n        } else {\n            at = after\n            n += 1usize\n        }\n    }\n    ret n\n}\n\n",
           "fn main(a: *mem.Arena, args: []str) -> err {\n"]
    n = 0

    def check(cond):
        nonlocal n
        n += 1
        out.append("    if %s { os.exit(%d) }\n" % (cond, n))

    for name, data in STREAMS.items():
        out.append("    let %s: %s = %s\n" % (name, "[%d]u8" % len(data), e_bytes_literal(data)))
        expected = events_of(data, len(data))
        out.append("    var at_%s = 0usize\n" % name)
        for k, (kind, d, i, r) in enumerate(expected):
            out.append("    let (ev_%s_%d, after_%s_%d, whole_%s_%d, err_%s_%d) = sse.next(a, %s[0..], at_%s)\n" % (name, k, name, k, name, k, name, k, name, name))
            check("err_%s_%d != ok || !whole_%s_%d" % (name, k, name, k))
            check("!str.eq(ev_%s_%d.kind, %s) || !str.eq(ev_%s_%d.data, %s)" % (name, k, e_string(kind), name, k, e_string(d)))
            if i is None:
                check("ev_%s_%d.has_id" % (name, k))
            else:
                check("!ev_%s_%d.has_id || !str.eq(ev_%s_%d.id, %s)" % (name, k, name, k, e_string(i)))
            if r is None:
                check("ev_%s_%d.has_retry" % (name, k))
            else:
                check("!ev_%s_%d.has_retry || ev_%s_%d.retry != %di64" % (name, k, name, k, r))
            out.append("    at_%s = after_%s_%d\n" % (name, name, k))
        out.append("    let (ev_%s_end, after_%s_end, whole_%s_end, err_%s_end) = sse.next(a, %s[0..], at_%s)\n" % ((name,) * 6))
        check("whole_%s_end" % name)
        # Every prefix.
        counts = [len(events_of(data, p)) for p in range(len(data) + 1)]
        out.append("    let counts_%s: [%d]u8 = %s\n" % (name, len(counts), e_bytes_literal(bytes(counts))))
        out.append("    var p_%s = 0usize\n    while p_%s <= %dusize {\n" % (name, name, len(data)))
        out.append("        if count_events(a, %s[0..p_%s]) != usize(counts_%s[p_%s]) { os.exit(%d) }\n" % (name, name, name, name, n + 1))
        out.append("        p_%s += 1usize\n    }\n" % name)
        n += 1
    out.append("    ret ok\n}\n")
    target = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/fmt_sse/src/main.e"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote", target, "checks", n)


main()
