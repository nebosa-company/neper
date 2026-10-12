"""Generate lib/e/fmt/magic.e from scripts/magic_table.py (L135, D2801)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fixture_common as fc  # noqa: E402
from magic_table import TABLE  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'lib' / 'e' / 'fmt' / 'magic.e'

rows = ['%d|%s|%s|%s|%s' % r for r in TABLE]
chunks_src, names = fc.vector_functions('magic_rows', rows)
calls = '\n'.join('    let (hit_%s, found_%s) = scan(%s(), data)\n    if found_%s { ret (hit_%s, true) }' % (n, n, n, n, n)
                  for n in names)

src = '''// A magic-number signature database: `sniff` names the format of a byte prefix by the
// leading (or fixed-offset) bytes the format's specification requires, the way file(1)'s
// magic database does, answering a MIME type, a conventional extension and a description.
// It is the byte-level companion to text and content-type guessing: nothing here reads
// beyond the offsets the table names, so a prefix of the file is enough (the largest offset is
// 257, for `ustar` in a tar header, so 262 bytes decide every row).
//
// The %d rows are ordered, first match wins, with wildcard bytes written `??` (RIFF sizes).
// A family sharing a prefix lists its specific members first: RIFF (WebP, WAVE, AVI), ISO
// base-media `ftyp` brands (MP4, M4A, QuickTime, AVIF, HEIC), ZIP versus the OOXML/ODF
// containers it also is (those need a directory read and are not guessed here). The rows are
// generated from `scripts/magic_table.py` by `scripts/gen_magic.py`.

type Match = struct { mime: str, extension: str, description: str, offset: u32 }

fn hex_nibble(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c - 48u8) }
    if c >= 65u8 && c <= 70u8 { ret i32(c - 55u8) }
    if c >= 97u8 && c <= 102u8 { ret i32(c - 87u8) }
    ret -1i32
}

// One `offset|HEX|mime|extension|description` row per line.
fn scan(rows: str, data: []const u8) -> (Match, bool) {
    var start = 0usize
    var i = 0usize
    while i < rows.len {
        if rows[i] == 10u8 {
            let row = rows[start..i]
            var fields: [5]usize = zero
            var count = 0usize
            var k = 0usize
            fields[0usize] = 0usize
            while k < row.len && count < 4usize {
                if row[k] == 124u8 {
                    count += 1usize
                    fields[count] = k + 1usize
                }
                k += 1usize
            }
            if count == 4usize {
                var offset = 0usize
                var d = 0usize
                while d < fields[1usize] - 1usize {
                    offset = offset * 10usize + usize(row[d] - 48u8)
                    d += 1usize
                }
                let hex = row[fields[1usize]..fields[2usize] - 1usize]
                var good = offset + hex.len / 2usize <= data.len
                var p = 0usize
                while good && p + 1usize < hex.len {
                    if hex[p] != 63u8 {
                        let hi = hex_nibble(hex[p])
                        let lo = hex_nibble(hex[p + 1usize])
                        if hi < 0i32 || lo < 0i32 || data[offset + p / 2usize] != u8(hi * 16i32 + lo) { good = false }
                    }
                    p += 2usize
                }
                if good {
                    var m: Match = zero
                    m.mime = row[fields[2usize]..fields[3usize] - 1usize]
                    m.extension = row[fields[3usize]..fields[4usize] - 1usize]
                    m.description = row[fields[4usize]..row.len]
                    m.offset = u32(offset)
                    ret (m, true)
                }
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret (zero, false)
}

fn sniff(data: []const u8) -> (Match, bool) {
''' % len(rows) + calls + '''
    ret (zero, false)
}

fn row_count() -> usize { ret %dusize }

''' % len(rows) + chunks_src

OUT.write_bytes(src.encode('utf-8'))
print('wrote', OUT, len(rows), 'rows,', len(names), 'chunks')
