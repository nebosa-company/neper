# Generates the compact Unicode 15.0 IDNA 2008 tables in lib/e/net/idna.e.
# Run with idna 3.4 on PYTHONPATH (`python -m pip install -t build/idna34 idna==3.4`).
import struct

import idna.idnadata as data


assert data.__version__ == "15.0.0"


def decoded_ranges(values):
    return [(value >> 32, value & 0xFFFFFFFF) for value in values]


def range_bytes(values):
    return b"".join(struct.pack("<I", start)[:3] + struct.pack("<I", end)[:3]
                    for start, end in decoded_ranges(values))


def literal(value):
    return '"' + "".join(
        "\\x%02x" % byte if byte < 32 or byte > 126 or byte in (34, 92) else chr(byte)
        for byte in value
    ) + '"'


joining = b"".join(
    struct.pack("<I", scalar)[:3] + bytes([kind])
    for scalar, kind in sorted(data.joining_types.items())
    if kind in b"LDRT"
)
tables = {
    "idna_pvalid_table": range_bytes(data.codepoint_classes["PVALID"]),
    "idna_greek_table": range_bytes(data.scripts["Greek"]),
    "idna_han_table": range_bytes(data.scripts["Han"]),
    "idna_hebrew_table": range_bytes(data.scripts["Hebrew"]),
    "idna_hiragana_table": range_bytes(data.scripts["Hiragana"]),
    "idna_katakana_table": range_bytes(data.scripts["Katakana"]),
    "idna_joining_table": joining,
}

generated = "// --- Generated IDNA 2008 data (Unicode 15.0; reference.py beside the fixture).\n"
for name, value in tables.items():
    generated += "fn %s() -> str { ret %s }\n" % (name, literal(value))

path = "../../../../../lib/e/net/idna.e"
source = open(path, encoding="utf-8").read()
marker = "// --- Generated IDNA 2008 data"
head = source[:source.index(marker)] if marker in source else source.rstrip() + "\n\n"
open(path, "w", encoding="utf-8", newline="\n").write(head + generated)
