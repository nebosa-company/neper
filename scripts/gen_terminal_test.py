#!/usr/bin/env python3
"""Write tests/selfhost/fixtures/link/text_terminal/src/main.e: byte streams fed to e.text.terminal and to pyte (a
pure-Python terminal emulator) and the two screens compared cell by cell (character, colours, attributes), the
scrollback compared line by line, and the cursor. Set NEPER_PYLIB to a directory holding pyte."""
import os
import sys
from pathlib import Path

sys.path.insert(0, os.environ.get("NEPER_PYLIB", "D:/Temp/claude/pylib"))
import pyte  # noqa: E402
from pyte import graphics  # noqa: E402

NAMES = ["black", "red", "green", "brown", "blue", "magenta", "cyan", "white"]
PALETTE = {}
for index, value in enumerate(graphics.FG_BG_256):
    PALETTE.setdefault(value, index)


def colour(name: str) -> int:
    if name == "default":
        return 0
    if name in NAMES:
        return 1 + NAMES.index(name)
    if name.startswith("bright") and name[6:] in NAMES:
        return 9 + NAMES.index(name[6:])
    if name in PALETTE:
        return 0x100 | PALETTE[name]
    return 0x1000000 | int(name, 16)


def attrs(ch) -> int:
    return (1 if ch.bold else 0) | (2 if ch.underscore else 0) | (4 if ch.reverse else 0) | (
        8 if ch.italics else 0) | (16 if ch.blink else 0) | (32 if ch.strikethrough else 0)


def esc(data: bytes) -> str:
    return '"' + "".join("\\x%02x" % b for b in data) + '"'


def cell_text(ch) -> str:
    c = ch.data
    return "%02x" % (ord(c) if 32 <= ord(c) < 127 else 63)


def screen_dump(screen) -> str:
    out = []
    for y in range(screen.lines):
        row = screen.buffer[y]
        for x in range(screen.columns):
            ch = row[x]
            out.append("%s%07x%07x%02x" % (cell_text(ch), colour(ch.fg), colour(ch.bg), attrs(ch)))
    return "".join(out)


def history_dump(screen, columns) -> str:
    # Newest first, the first `columns` cells of each line, as screen_dump.
    out = []
    for line in reversed(list(screen.history.top)):
        for x in range(columns):
            ch = line[x]
            out.append("%s%07x%07x%02x" % (cell_text(ch), colour(ch.fg), colour(ch.bg), attrs(ch)))
    return "".join(out)


E = "\x1b"
CSI = "\x1b["
scenarios = []


def add(name, cols, rows, text, history=0):
    scenarios.append((name, cols, rows, text.encode("utf-8") if isinstance(text, str) else text, history))


add("plain", 20, 6, "hello world\r\nsecond line\r\nthird")
add("wrap", 10, 4, "0123456789ABCDEFGHIJ0123")
add("wrap_exact", 10, 3, "0123456789\r\nabc\x08\x08Z")
add("colours", 24, 4, CSI + "31mred" + CSI + "1;32m bold green" + CSI + "0m plain\r\n" + CSI + "44;37mblue bg" + CSI + "m\r\n"
    + CSI + "38;5;202mpal202" + CSI + "48;5;27m on27" + CSI + "0m " + CSI + "38;2;10;20;30mtrue" + CSI + "49m")
add("bright", 24, 3, CSI + "91mbrt red" + CSI + "102m on" + CSI + "39;49m " + CSI + "7mrev" + CSI + "27m" + CSI + "4mund" + CSI + "24m")
add("attrs", 24, 3, CSI + "1mb" + CSI + "3mi" + CSI + "4mu" + CSI + "5mk" + CSI + "9ms" + CSI + "22;23;24;25;29mx")
add("move", 20, 8, "abc\r\ndef" + CSI + "2A" + CSI + "3C" + "X" + CSI + "3B" + "Y" + CSI + "2D" + "Z" + CSI + "H" + "home"
    + CSI + "5;7H" + "at" + CSI + "3G" + "g" + CSI + "7d" + "v" + CSI + "2E" + "e" + CSI + "F" + "f")
add("clamp", 10, 5, CSI + "99;99H" + "c" + CSI + "99A" + "u" + CSI + "99D" + "l" + CSI + "99B" + "d" + CSI + "99C" + "r")
add("tabs", 24, 3, "a\tb\tc\td\r\n\t\t\t\tx")
add("erase_line", 12, 4, "abcdefghijkl\r\nabcdefghijkl\r\nabcdefghijkl" + CSI + "1;5H" + CSI + "K" + CSI + "2;5H" + CSI + "1K"
    + CSI + "3;5H" + CSI + "2K")
add("erase_display", 12, 5, "aaaaaaaaaaaa\r\nbbbbbbbbbbbb\r\ncccccccccccc\r\ndddddddddddd\r\neeeeeeeeeeee" + CSI + "3;5H" + CSI + "J"
    + CSI + "1;1H" + "+" + CSI + "4;4H" + CSI + "1J" + CSI + "5;1H" + CSI + "41m" + CSI + "2K")
add("erase_pen", 12, 3, "aaaaaaaaaaaa\r\nbbbbbbbbbbbb\r\ncccccccccccc" + CSI + "1;4H" + CSI + "44m" + CSI + "K" + CSI + "0m"
    + CSI + "2;1H" + CSI + "42m" + CSI + "2J")
add("chars", 12, 3, "abcdefghijkl" + CSI + "1;3H" + CSI + "2P" + "\r\n" + "abcdefghijkl" + CSI + "2;3H" + CSI + "3@" + "\r\n"
    + "abcdefghijkl" + CSI + "3;3H" + CSI + "4X")
add("lines", 8, 6, "1\r\n2\r\n3\r\n4\r\n5\r\n6" + CSI + "2;1H" + CSI + "2L" + "N" + CSI + "5;1H" + CSI + "M")
add("region", 8, 6, "A\r\nB\r\nC\r\nD\r\nE\r\nF" + CSI + "2;4r" + CSI + "4;1H" + "\n" + "x" + CSI + "2;1H" + E + "M" + "y"
    + CSI + "r" + CSI + "H")
add("scroll_text", 10, 4, "".join("line %d\r\n" % i for i in range(10)) + "end", history=20)
add("utf8", 12, 3, "caf\u00e9 \u00fc\u00f1\r\n\u00e9" + CSI + "1;1H" + "\u00ff")
add("save", 12, 3, "ab" + E + "7" + "cd" + E + "8" + "X" + CSI + "31m" + "Y")
add("prompt", 40, 6, "\x1b[1;34m~/src\x1b[0m $ ls --color\r\n\x1b[01;34mdir\x1b[0m  \x1b[01;32mrun.sh\x1b[0m  file.txt\r\n\x1b[1;34m~/src\x1b[0m $ ")
add("status", 40, 6, CSI + "2J" + CSI + "H" + "top - 10:11:12 up 3 days" + CSI + "3;1H" + CSI + "7mPID USER  CPU%" + CSI + "K" + CSI + "m"
    + CSI + "4;1H" + "1234 root  12.5" + CSI + "5;1H" + "5678 neper  0.3" + CSI + "6;1H" + CSI + "30;42m" + "q:quit" + CSI + "K" + CSI + "0m")
add("osc", 20, 3, E + "]0;title" + "\x07" + "ab" + E + "]2;other" + E + "\\" + "cd")

lines = []
for index, (name, cols, rows, data, history) in enumerate(scenarios, 1):
    if history:
        screen = pyte.HistoryScreen(cols, rows, history=history)
    else:
        screen = pyte.Screen(cols, rows)
    stream = pyte.ByteStream(screen)
    stream.feed(data)
    dump = screen_dump(screen)
    hist = history_dump(screen, cols) if history else ""
    hist_lines = len(screen.history.top) if history else 0
    lines.append('    r = run_case(a, %s, %d, %d, %d, "%s", %d, "%s", %d, %d, %d)\n    if r != 0usize { os.exit(%d + i32(r)) }'
                 % (esc(data), cols, rows, history, dump, hist_lines, hist, screen.cursor.x, screen.cursor.y,
                    1 if screen.cursor.hidden else 0, index * 8))

head = open(Path(__file__).with_name("gen_terminal_head.e.txt"), encoding="utf-8").read()
tail = """    // Not in pyte: the alternate screen keeps the main one, ESC c resets, a resize keeps the overlap.
    r = alt_case(a)
    if r != 0usize { os.exit(%d + i32(r)) }
    ret ok
}
""" % ((len(scenarios) + 1) * 8)
dest = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/text_terminal/src/main.e"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(head + "\n".join(lines) + "\n" + tail, encoding="utf-8", newline="\n")
print(dest, len(scenarios), "scenarios", dest.stat().st_size, "bytes")
