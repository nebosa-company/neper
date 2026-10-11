#!/usr/bin/env python3
"""Write tests/selfhost/fixtures/link/fmt_vcard/src/main.e: vCard texts (made by vobject, and by hand for folded
lines, escapes, groups, 2.1 bare types and an LF-only file) parsed by e.fmt.vcard and dumped, compared with the
dump of what vobject reads; and the cards written again, compared with a reference writer (whose output vobject
reads back to the same cards). Set NEPER_PYLIB to a directory holding vobject."""
import os
import sys
from pathlib import Path

sys.path.insert(0, os.environ.get("NEPER_PYLIB", "D:/Temp/claude/pylib"))
import vobject  # noqa: E402


def dump_card(c):
    name, family, given, org, note, tels, emails = c
    return "|".join([name, family, given, org, note.replace("\n", "~"),
                     ",".join("%s:%s" % (n, t) for n, t in tels), ",".join(emails)])


def from_vobject(v):
    name = v.fn.value if hasattr(v, "fn") else ""
    family = given = ""
    if hasattr(v, "n"):
        family = v.n.value.family or ""
        given = v.n.value.given or ""
    org = ""
    if hasattr(v, "org"):
        val = v.org.value
        org = val[0] if isinstance(val, list) else val
    note = v.note.value if hasattr(v, "note") else ""
    tels = []
    for t in v.contents.get("tel", [])[:4]:
        types = t.params.get("TYPE", [])
        tels.append((t.value, types[0].lower() if types else ""))
    emails = [e.value for e in v.contents.get("email", [])[:2]]
    return (name, family, given, org, note, tels, emails)


def lit(s: str) -> str:
    return '"' + "".join("\\x%02x" % b for b in s.encode("utf-8")) + '"'


def reference_write(cards):
    out = []

    def esc(s):
        return s.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n").replace("\r", "")

    def fold(line):
        data = line.encode("utf-8")
        res = bytearray()
        column = 0
        for b in data:
            if column >= 75:
                res += b"\r\n "
                column = 1
            res.append(b)
            column += 1
        return bytes(res).decode("utf-8", errors="surrogateescape")
    for name, family, given, org, note, tels, emails in cards:
        out.append("BEGIN:VCARD")
        out.append("VERSION:3.0")
        out.append(fold("FN:" + esc(name)))
        out.append(fold("N:%s;%s;;;" % (esc(family), esc(given))))
        for n, t in tels:
            out.append(fold("TEL%s:%s" % (";TYPE=" + esc(t) if t else "", esc(n))))
        for e in emails:
            out.append(fold("EMAIL:" + esc(e)))
        if org:
            out.append(fold("ORG:" + esc(org)))
        if note:
            out.append(fold("NOTE:" + esc(note)))
        out.append("END:VCARD")
    return "".join(line + "\r\n" for line in out)


texts = []
# 1. vobject's own output for a few cards.
def make(fn, family, given, tels, emails, org, note):
    v = vobject.vCard()
    v.add("n").value = vobject.vcard.Name(family=family, given=given)
    v.add("fn").value = fn
    for n, t in tels:
        tv = v.add("tel")
        tv.value = n
        if t:
            tv.type_param = t.upper()
    for e in emails:
        v.add("email").value = e
    if org:
        v.add("org").value = [org]
    if note:
        v.add("note").value = note
    return v

cards = [
    make("Sam Rivera", "Rivera", "Sam", [("+1 555 0100", "cell"), ("555 0199", "work")], ["sam@neper.test"], "Neper", "Line one\nline, two; three"),
    make("Ada Lovelace", "Lovelace", "Ada", [("020 7946 0958", "home")], ["ada@analytical.test", "countess@lovelace.test"], "", ""),
    make("Mary-Jane O'Neil", "O'Neil", "Mary-Jane", [], [], "Acme; Inc", "A very long note that has to be folded because it is much longer than seventy five octets in a row, with some more text to be sure."),
]
text1 = "".join(c.serialize() for c in cards)
texts.append(("made", text1))
# 2. by hand: LF only, folded lines, groups, a bare 2.1 type, quoted type, lower case names, escapes, an unknown property.
text2 = ("BEGIN:VCARD\nVERSION:2.1\nN:Doe;John;;;\nFN:John Doe\nTEL;CELL;VOICE:555-1234\nTEL;WORK:555-9999\nEMAIL;INTERNET:john@doe.test\nPHOTO;ENCODING=b:AAAA\nEND:VCARD\n"
         "begin:vcard\nversion:3.0\nitem1.TEL;TYPE=\"home,voice\":+44 20 7946 0000\nitem1.X-ABLabel:other\nfn:Fold\\, Test\nn:Test;Fold;;;\nNOTE:one\\\\two\\;three\n"
         " continued here\nORG:Big\\, Corp;Dept\nend:vcard\n")
texts.append(("hand", text2))
text3 = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Empty Phone\r\nN:Phone;Empty;;;\r\nEND:VCARD\r\n"
texts.append(("crlf", text3))


def parse_with_vobject(text):
    out = []
    for v in vobject.readComponents(text):
        out.append(from_vobject(v))
    return out

calls = []
count = [0]
for name, text in texts:
    expected = parse_with_vobject(text)
    # vobject treats 2.1 bare types differently; for the hand text take the values from the standard's meaning.
    if name == "hand":
        expected = [("John Doe", "Doe", "John", "", "", [("555-1234", "cell"), ("555-9999", "work")], ["john@doe.test"]),
                    ("Fold, Test", "Test", "Fold", "Big, Corp", "one\\two;threecontinued here", [("+44 20 7946 0000", "home")], [])]
    dump = "\n".join(dump_card(c) for c in expected)
    count[0] += 1
    calls.append('    r = parse_case(a, %s, %s)\n    if r != 0usize { os.exit(%d + i32(r)) }' % (lit(text), lit(dump), count[0] * 8))
    # Written again: the reference writer over the same cards.
    written = reference_write(expected)
    back = parse_with_vobject(written)
    for got, want in zip(back, expected):
        assert dump_card(got) == dump_card(want), (got, want)
    count[0] += 1
    calls.append('    r = write_case(a, %s, %s)\n    if r != 0usize { os.exit(%d + i32(r)) }' % (lit(text), lit(written), count[0] * 8))

head = open(Path(__file__).with_name("gen_vcard_head.e.txt"), encoding="utf-8").read()
dest = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/fmt_vcard/src/main.e"
dest.parent.mkdir(parents=True, exist_ok=True)
tail = '''    let (none_count, none_error) = vcard.parse(a, "just text", cards[0usize..4usize])
    if none_error != vcard.Malformed { os.exit(%d) }
    ret ok
}
''' % ((count[0] + 1) * 8)
dest.write_text(head + "\n".join(calls) + "\n" + tail, encoding="utf-8", newline="\n")
print(dest, count[0], "checks")
