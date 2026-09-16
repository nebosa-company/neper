"""Check the language card's examples with the compiler (D404, H11/H28).

    python scripts/card_examples.py COMPILER ROOT ARCH OS OUTDIR

Every ```neper fence of docs/llm-neper-card.src.md is a complete program and must
check; a fence opened as ```neper reject E-CODE must be refused with that code as its
first diagnostic. Each fence is written to OUTDIR/src/example<N>.e and run through
`check-file --json`; the exit status is 1 when any example does not do what its fence
says, with the fence's line and the compiler's first diagnostic on stderr. The suites
run this, so the card's examples cannot drift from the language.
"""
import json, os, re, subprocess, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def fences(text):
    """(line, kind, expected_code, body) for every ```neper fence, in order."""
    found = []
    lines = text.splitlines()
    at = 0
    while at < len(lines):
        opened = re.match(r'^```neper(?:\s+reject\s+(E-[A-Z]+-\d{4}))?\s*$', lines[at])
        if opened:
            start = at
            at += 1
            body = []
            while at < len(lines) and lines[at] != '```':
                body.append(lines[at])
                at += 1
            found.append((start + 1, 'reject' if opened.group(1) else 'accept', opened.group(1), '\n'.join(body) + '\n'))
        at += 1
    return found


def main(argv):
    if len(argv) != 6:
        print(__doc__, file=sys.stderr)
        return 2
    compiler, project_root, arch, host, outdir = argv[1:]
    compiler = os.path.abspath(compiler)
    source_dir = os.path.join(outdir, 'src')
    os.makedirs(source_dir, exist_ok=True)
    with open(os.path.join(root, 'docs', 'llm-neper-card.src.md'), encoding='utf-8') as f:
        card = f.read()
    examples = fences(card)
    if not examples:
        print('card_examples: the card has no ```neper fence', file=sys.stderr)
        return 1
    failures = 0
    for number, (line, kind, code, body) in enumerate(examples, 1):
        path = os.path.join(source_dir, 'example%d.e' % number)
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(body)
        run = subprocess.run([compiler, 'check-file', path, project_root, arch, host, '--json'], capture_output=True, text=True)
        diagnostics = [json.loads(l) for l in run.stdout.splitlines() if l.startswith('{"record":"diagnostic"')]
        first = diagnostics[0]['code'] if diagnostics else None
        message = diagnostics[0]['message'] if diagnostics else ''
        if kind == 'accept' and (run.returncode != 0 or diagnostics):
            print('card_examples: the example at line %d does not check: %s %s' % (line, first, message), file=sys.stderr)
            failures += 1
        if kind == 'reject' and (run.returncode == 0 or first != code):
            print('card_examples: the example at line %d should be refused with %s, got %s %s' % (line, code, first, message), file=sys.stderr)
            failures += 1
    print('card_examples: %d examples, %d wrong' % (len(examples), failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
