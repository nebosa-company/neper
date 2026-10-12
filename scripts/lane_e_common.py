"""Shared helpers for the L100/L145/L146/L153/L155/L132 fixture generators: a Neper string literal for bytes
(`\\xHH` for anything not plain printable ASCII), and a check emitter that numbers every `os.exit` code."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def lit(data):
    """A Neper string literal for bytes or str."""
    if isinstance(data, str):
        data = data.encode("utf-8")
    out = []
    for b in data:
        c = chr(b)
        if c == '"':
            out.append('\\"')
        elif c == "\\":
            out.append("\\\\")
        elif 32 <= b < 127:
            out.append(c)
        else:
            out.append("\\x%02x" % b)
    return '"' + "".join(out) + '"'


class Checks:
    """Collects `if <cond> { os.exit(n) }` lines with consecutive codes."""

    def __init__(self):
        self.lines = []
        self.code = 0

    def add(self, cond, note=None):
        self.code += 1
        if self.code > 250:
            raise SystemExit("too many checks for distinct exit codes")
        self.lines.append("    if %s { os.exit(%d) }\n" % (cond, self.code))
        return self.code

    def raw(self, text):
        self.lines.append(text)

    def text(self):
        return "".join(self.lines)


def write_fixture(name, header, body_lines, uses):
    target = ROOT / "tests/selfhost/fixtures/link" / name / "src/main.e"
    target.parent.mkdir(parents=True, exist_ok=True)
    text = header + "".join("use %s\n" % u for u in uses) + "\n" + body_lines
    target.write_text(text, encoding="utf-8", newline="\n")
    return target
