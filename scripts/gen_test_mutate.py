"""Writes tests/selfhost/fixtures/link/test_mutate/src/main.e (L143, D2685).

An independent, regex-driven enumeration of the mutants of a sample module (the
module under test, e.test.mutate, scans bytes by hand), the mutated text of three of
them, a scripted suite verdict per mutant from an LCG, and the score and report the
runner must produce. The fixture embeds all of it as vectors, so it needs no Python at
run time. Regenerate with: python scripts/gen_test_mutate.py
"""
import re
from pathlib import Path

SAMPLE = '''// clamp, an age gate and a tally; "a<b" and 99 here are not code
fn clamp(x: i64, lo: i64, hi: i64) -> i64 {
    if x < lo { ret lo }
    if x > hi { ret hi }
    ret x
}

fn is_adult(age: i64) -> bool { ret age >= 18 }

fn tally(a: i64, b: i64) -> i64 {
    var t = a + b * 2
    t -= 1
    let label = "a<b"
    let flag = true
    if a == b && t != 0 { ret 0 - t }
    while t > 10 && flag { t = t - 10 }
    let r: *u8 = zero
    ret t
}
'''

TOKEN = re.compile(r'//[^\n]*|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|[A-Za-z_]\w*|\d[\w]*(?:\.\d[\w.]*)?|==|!=|&&|\|\||->|<<|>>|\.\.|\+=|-=|<=|>=|[<>+\-*]')
KEYWORDS = {'ret', 'if', 'while', 'in', 'try'}


def after_operand(text, at):
    before = text[:at].rstrip(' \t')
    if not before:
        return False
    last = before[-1]
    if last in ')]':
        return True
    m = re.search(r'(\w+)$', before)
    if not m:
        return False
    return m.group(1) not in KEYWORDS


def mutants(text):
    out = []  # (kind, offset, len, replacement)
    for m in TOKEN.finditer(text):
        tok, at = m.group(0), m.start()
        if tok.startswith('//') or tok[0] in '"\'':
            continue
        if re.match(r'[A-Za-z_]', tok):
            if tok == 'true':
                out.append(('Constant', at, 4, 'false'))
            elif tok == 'false':
                out.append(('Constant', at, 5, 'true'))
            elif tok in ('if', 'while'):
                eol = text.find('\n', m.end())
                eol = len(text) if eol < 0 else eol
                brace = text.rfind('{', m.end(), eol)
                if brace >= 0:
                    start = m.end()
                    while start < brace and text[start] == ' ':
                        start += 1
                    end = brace
                    while end > start and text[end - 1] == ' ':
                        end -= 1
                    if end > start:
                        cond = text[start:end]
                        if tok == 'if' and cond != 'true':
                            out.append(('Branch', start, len(cond), 'true'))
                        if cond != 'false':
                            out.append(('Branch', start, len(cond), 'false'))
            continue
        if tok[0].isdigit():
            if '.' in tok or re.match(r'0[xbo]', tok):
                continue
            d = re.match(r'\d+', tok).group(0)
            out.append(('Constant', at, len(d), str(int(d) + 1)))
            continue
        simple = {'==': ['!='], '!=': ['=='], '&&': ['||'], '||': ['&&'],
                  '<': ['<=', '>='], '>': ['>=', '<='], '<=': ['<', '>'], '>=': ['>', '<'],
                  '+=': ['-='], '-=': ['+=']}
        if tok in simple:
            for r in simple[tok]:
                out.append(('Operator', at, len(tok), r))
        elif tok in ('+', '-'):
            if after_operand(text, at):
                out.append(('Operator', at, 1, '-' if tok == '+' else '+'))
        elif tok == '*':
            if after_operand(text, at):
                out.append(('Operator', at, 1, '/'))
    out.sort(key=lambda t: (t[1], 0))
    return out


def line_of(text, offset):
    return text.count('\n', 0, offset) + 1


def neper_str(s):
    bs = chr(92)
    s = s.replace(bs, bs + bs).replace('"', bs + '"').replace('\n', bs + 'n')
    return '"' + s + '"'


def main():
    ms = mutants(SAMPLE)
    n = len(ms)
    # a scripted suite: LCG verdicts 0 Killed 1 Survived 2 Invalid 3 Timeout
    x = 12345
    verdicts = []
    for _ in range(n):
        x = (x * 1103515245 + 12345) & 0x7fffffff
        r = (x >> 8) % 10
        verdicts.append(0 if r < 5 else 1 if r < 8 else 2 if r < 9 else 3)
    killed = verdicts.count(0)
    survived = verdicts.count(1)
    invalid = verdicts.count(2)
    timeout = verdicts.count(3)
    valid = killed + survived + timeout
    permille = (killed + timeout) * 1000 // valid
    lines = []
    for (k, off, ln, rep), v in zip(ms, verdicts):
        if v == 1:
            lines.append('survived: line %d: %s -> %s\n' % (line_of(SAMPLE, off), SAMPLE[off:off + ln], rep))
    report = ''.join(lines) + '%d mutants: %d killed, %d timeout, %d survived, %d invalid; score %d.%d%%\n' % (
        n, killed, timeout, survived, invalid, permille // 10, permille % 10)
    kinds = {'Operator': 0, 'Constant': 1, 'Branch': 2}
    mutated = [SAMPLE[:o] + r + SAMPLE[o + l:] for (_, o, l, r) in ms]
    pick = [0, n // 2, n - 1]

    def arr(name, ty, items):
        return 'fn %s() -> [%d]%s { ret [%d]%s{ %s } }\n' % (name, n, ty, n, ty, ', '.join(items))

    o = []
    o.append('// Generated by scripts/gen_test_mutate.py -- do not edit. `e.test.mutate` against an\n')
    o.append('// independent regex enumeration of the %d mutants of a sample module (operator,\n' % n)
    o.append('// constant and branch families, with a comment, a string, a `->`-free pointer type and\n')
    o.append('// a unary-looking minus that must be skipped), the mutated text of three of them, a\n')
    o.append('// scripted suite, and the exact score and report. Every check has its own exit code.\n')
    o.append('use e.os\nuse e.mem\nuse e.str\nuse e.test.mutate as mutate\n\n')
    o.append('fn sample() -> str { ret %s }\n\n' % neper_str(SAMPLE))
    o.append(arr('kinds', 'u8', [str(kinds[k]) for k, _, _, _ in ms]))
    o.append(arr('offsets', 'usize', [str(o_) for _, o_, _, _ in ms]))
    o.append(arr('lengths', 'usize', [str(l) for _, _, l, _ in ms]))
    o.append(arr('replacements', 'str', [neper_str(r) for _, _, _, r in ms]))
    o.append(arr('verdicts', 'u8', [str(v) for v in verdicts]))
    for j, p in enumerate(pick):
        o.append('fn mutated_%d() -> str { ret %s }\n' % (j, neper_str(mutated[p])))
    o.append('\ntype Ctx = struct { next: usize }\n\n')
    o.append('''fn scripted(c: *Ctx, m: mutate.Mutant, source: str) -> mutate.Verdict {
    let v = verdicts()
    let at = c.next
    c.next += 1usize
    if v[at] == 0u8 { ret .Killed }
    if v[at] == 1u8 { ret .Survived }
    if v[at] == 2u8 { ret .Invalid }
    ret .Timeout
}

fn kind_code(k: mutate.Kind) -> u8 {
    if k == .Operator { ret 0u8 }
    if k == .Constant { ret 1u8 }
    ret 2u8
}

fn main(a: *mem.Arena) -> err {
''')
    o.append('    let want_count = %dusize\n' % n)
    o.append('''    var found: [128]mutate.Mutant = zero
    let (count, discover_error) = mutate.discover(a, sample(), found[0..])
    if discover_error != ok { os.exit(10i32) }
    if count != want_count { os.exit(11i32) }
    let ks = kinds()
    let os_ = offsets()
    let ls = lengths()
    let rs = replacements()
    var i = 0usize
    while i < count {
        if kind_code(found[i].kind) != ks[i] { os.exit(12i32) }
        if found[i].offset != os_[i] || found[i].len != ls[i] { os.exit(13i32) }
        if !str.eq(found[i].replacement, rs[i]) { os.exit(14i32) }
        i += 1usize
    }
    // A short output reports TooSmall with the first mutants intact.
    var few: [3]mutate.Mutant = zero
    let (cut, cut_error) = mutate.discover(a, sample(), few[0..])
    if cut_error != mutate.TooSmall || cut != 3usize || few[2].offset != os_[2] { os.exit(15i32) }
''')
    o.append('    let (m0, e0) = mutate.apply(a, sample(), found[%d])\n' % pick[0])
    o.append('    let (m1, e1) = mutate.apply(a, sample(), found[%d])\n' % pick[1])
    o.append('    let (m2, e2) = mutate.apply(a, sample(), found[%d])\n' % pick[2])
    o.append('''    if e0 != ok || e1 != ok || e2 != ok { os.exit(16i32) }
    if !str.eq(m0, mutated_0()) { os.exit(17i32) }
    if !str.eq(m1, mutated_1()) { os.exit(18i32) }
    if !str.eq(m2, mutated_2()) { os.exit(19i32) }
    var results: [128]mutate.Verdict = zero
    var ctx = Ctx { next: 0usize }
    let before = mem.mark(a)
    let (score, run_error) = mutate.run[Ctx](a, sample(), found[0..count], &ctx, scripted, results[0..])
    if run_error != ok { os.exit(20i32) }
    // Each mutated source is rewound after its call.
    if mem.mark(a) != before { os.exit(21i32) }
''')
    o.append('    if score.total != %dusize || score.killed != %dusize || score.survived != %dusize || score.invalid != %dusize || score.timeout != %dusize { os.exit(22i32) }\n' % (n, killed, survived, invalid, timeout))
    o.append('    if mutate.score_permille(score) != %du32 { os.exit(23i32) }\n' % permille)
    o.append('    if !mutate.meets(score, %du32) || mutate.meets(score, %du32) { os.exit(24i32) }\n' % (permille, permille + 1))
    o.append('    var out: [2048]u8 = zero\n')
    o.append('    let want = %s\n' % neper_str(report))
    o.append('''    if !str.eq(mutate.report(sample(), found[0..count], results[0..count], score, out[0..]), want) { os.exit(25i32) }
    // No valid mutant scores zero, not a division.
    var empty: mutate.Score = zero
    empty.invalid = 4usize
    if mutate.score_permille(empty) != 0u32 { os.exit(26i32) }
    ret ok
}
''')
    path = Path(__file__).resolve().parent.parent / 'tests' / 'selfhost' / 'fixtures' / 'link' / 'test_mutate' / 'src' / 'main.e'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(o), encoding='utf-8', newline='\n')
    print('mutants', n, 'killed', killed, 'timeout', timeout, 'survived', survived, 'invalid', invalid, 'permille', permille)


if __name__ == '__main__':
    main()
