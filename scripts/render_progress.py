# -*- coding: utf-8 -*-
"""Render docs/progress.html from the roadmap rubric and the module plan.

Usage:  python scripts/render_progress.py     (from the repository root)

The three readiness numbers are computed, never typed: the compiler and
tooling scores come from the tables below, the module score is read out of
docs/module-apis.md, docs/modules.json, committed lib/e sources and the
intrinsics seeded in src/resolve.e.
"""
import json, re, subprocess, datetime
# Readiness rubric, rendered into docs/progress.html by this script.
# Each item scores 1 (delivered), 0 (not started), or a fraction (partial).
# Update these tables when a capability lands, then re-run this script.
compiler = {
 "Front end and language": [
  ("Lexer over the closed token registry", 1, "src/lex.e"),
  ("Parser and syntax tree", 1, "src/parse.e"),
  ("Module graph and import resolution", 1, "src/graph.e"),
  ("Order-independent name resolution", 1, "src/resolve.e"),
  ("Integer arithmetic, bitwise, shifts, division", 1, "link/bitwise, link/shifts, link/division"),
  ("if / while, break / continue, block scopes", 1, "link/control"),
  ("for over ranges, arrays and slices", 1, "tests/neper0"),
  ("Fixed arrays, zero / undef, .len", 1, "link/storage"),
  ("Slicing and mutability propagation", 1, "link/storage"),
  ("Structs: layout, literals, field places", 1, "link/aggregate"),
  ("Pointers, & / *, *const, auto-deref", 1, "link/aggregate"),
  ("Aggregate copies and ABI pass / return", 1, "link/advanced"),
  ("Enums, bare unions, union enum", 1, "link/variants"),
  ("switch, exhaustive and non-fallthrough", 1, "fixtures/variants"),
  ("defer, both forms", 1, "tests/neper0"),
  ("err / try / ok and named errors", 1, "link/error_collision"),
  ("Multi-return and destructuring", 1, "link/scalar"),
  ("const and integer comptime folding", 1, "link/generic_folding"),
  ("Generic functions [T: type], [N: usize]", 1, "link/generic_instances"),
  ("Generic aggregate types", 1, "link/generic_same_name"),
  ("Protocol resolution, spec 9 rules 3 and 5", 1, "check/protocol_*"),
  ("Iterator protocol <t>_next", 1, "tests/neper0"),
  ("Supplied cmp (rule 4)", 1, "link/sequence_cmp, tagged_union_cmp"),
  ("Supplied hash (rule 4)", 1, "link/supplied_hash, folded_hash"),
  ("Supplied eq (rule 4)", 1, "link/supplied_eq"),
  ("Supplied format (rule 4)", 0, "blocked on e.str"),
  ("Scalar floating point f32 / f64", 1, "link/float_scalar; f16 / bf16 still unlowered"),
  ("Vec[T,N] / Mask[T,N] and SIMD lowering", 0, "absent from check.e"),
  ("Atomic[T] and memory orderings", 0, "absent from check.e"),
  ("extern with @import / @cc and the C ABI", 0.25, "declared and checked; calls rejected"),
  ("Comptime str parameters and varargs", 0, "blocks str.format, io.printf"),
  ("e.meta reflection", 0, "not started"),
  ("Spec 11 debug check table and trap protocol", 0, "NIR .Trap never emitted"),
  ("General comptime interpreter", 0.25, "integer const folding only"),
 ],
 "Back end": [
  ("NIR, typed SSA-lite", 1, "src/nir.e"),
  ("Linear-scan register allocator", 1, "src/regalloc.e"),
  ("x64 emitter, System V and Win64", 1, "src/codegen_x64.e"),
  ("ELF object writer", 1, "src/object_elf.e"),
  ("COFF object writer", 1, "src/object_coff.e"),
  ("Own ELF linker", 1, "src/link_elf.e"),
  ("Own PE linker with kernel32 imports", 1, "src/link_pe.e"),
  ("Host runtime intrinsics, both platforms", 1, "runtime_pe_x64.asm, runtime_elf_x64_ext.s"),
  ("`.em` module format with Deps edges", 1, "src/em.e, fixtures/em"),
  ("Cross-module inlining, 40 NIR cap", 0, "not started"),
  ("Incremental rebuild on the edge rule", 0, "not started"),
  ("Work-stealing pool, parallel parse and codegen", 0, "single-threaded"),
  ("Determinism harness", 0.25, "compiler fixed point only; no -jN or incremental cases"),
  ("DWARF, CodeView and .nepersym debug info", 0, "bootstrap only"),
 ],
 "Self-hosting": [
  ("Self-hosted compiler emits its own source", 1, "run.ps1:623, run.sh:760"),
  ("Stage 2 == stage 3, byte-identical, both platforms", 1, "SHA-256 compare / cmp"),
  ("Bootstrap frozen and deleted", 0, "bootstrap/neper.c still builds stage 0"),
 ],
}
tooling = [
 ("JSONL v1 stream envelope and version header", 0, "no JSONL output"),
 ("build", 0, "emit-executable only, human output"),
 ("check", 0.25, "check-file, human output"),
 ("run", 0, "not started"),
 ("test and @test discovery", 0, "not started"),
 ("fmt canonical layout", 0, "not started"),
 ("tokens, lossless over 94 tokens", 0.25, "scan / scan-file, not lossless JSONL"),
 ("parse, lossless over 54 syntax nodes", 0.25, "parse / parse-file, not lossless JSONL"),
 ("index, symbols and references", 0, "not started"),
 ("dis", 0, "not started"),
 ("info", 0, "not started"),
 ("v1 schema validation of emitted records", 0, "schema written, nothing emits records"),
 ("Stable diagnostic codes from diagnostics.md", 0.35, "7 of 30 registered codes; 6 catch-all -9999"),
 ("Build manifest with versions and SHA-256", 0.25, "artifact_hash.e covers .em only"),
 ("Generated source maps", 0, "not started"),
 ("Conformance corpus accept/reject/format/tokens/parse/tools", 0, "tests/conformance absent"),
 ("Module-plan validation in CI", 1, "scripts/check_module_plan.py, 128 modules"),
 ("Reproducible-build check", 0.5, "compiler fixed point in both suites"),
 ("Generated-code benchmark corpus", 0.5, "benchmarks/llm_edit"),
 ("Self-host regression suite, both platforms", 1, "285 fixtures, run.ps1 + run.sh"),
 ("Bootstrap and self-host build scripts, both platforms", 1, "scripts/build-*"),
]


# Stamp the last commit that touched what this page measures, not HEAD. Stamping
# HEAD would make the page differ from itself the moment it is committed, so every
# later run would show a spurious diff. Taking that commit's own date as well keeps
# the output a pure function of its inputs.
INPUTS = ['src', 'lib', 'docs/module-apis.md', 'docs/modules.json']
stamp = subprocess.run(['git', 'log', '-1', '--format=%h %cs', '--'] + INPUTS,
                       capture_output=True, text=True).stdout.split()
rev, when = (stamp + ['unknown', str(datetime.date.today())])[:2]

# ---- module numbers, recomputed here so the page cannot drift from the plan ----
txt = open('docs/module-apis.md', encoding='utf-8').read()
blocks = dict(re.findall(r'^### `([^`]+)`\n(.*?)(?=^### |\Z)', txt, re.S | re.M))


def decl_names(body):
    out = []
    for f in re.findall(r'```neper\n(.*?)```', body, re.S):
        for line in f.splitlines():
            m = re.match(r'(fn|type|error|const)\s+([A-Za-z_][A-Za-z0-9_]*)', line.strip())
            if m:
                out.append(m.group(2))
    return out


tracked = set(subprocess.run(['git', 'ls-files', 'lib/e'],
                             capture_output=True, text=True).stdout.split())
impl = {}
for p in tracked:
    if not p.endswith('.e'):
        continue
    mod = 'e.' + p[len('lib/e/'):-2].replace('/', '.')
    impl[mod] = {m.group(2) for m in
                 (re.match(r'(fn|type|error|const)\s+([A-Za-z_][A-Za-z0-9_]*)', l)
                  for l in open(p, encoding='utf-8')) if m}

seeded = {}
for mod, nm in re.findall(r'seed\(r,\s*g,\s*"([^"]+)",\s*"([^"]+)"',
                          open('src/resolve.e', encoding='utf-8').read()):
    seeded.setdefault(mod, set()).add(nm)

mod_rows, dtot, dgot = [], 0, 0
for mod in sorted(blocks):
    d = decl_names(blocks[mod])
    have = impl.get(mod, set()) | seeded.get(mod, set())
    h = sum(1 for n in d if n in have)
    dtot += len(d)
    dgot += h
    if h:
        mod_rows.append((mod, h, len(d)))
mod_rows.sort(key=lambda r: (-r[1] / r[2], r[0]))

plan = json.load(open('docs/modules.json'))['modules']
surf = {}
for m in plan:
    surf[m['surface']] = surf.get(m['surface'], 0) + 1

c_sum = sum(s for g in compiler.values() for _, s, _ in g)
c_n = sum(len(g) for g in compiler.values())
t_sum = sum(s for _, s, _ in tooling)
t_n = len(tooling)
C, M, T = 100 * c_sum / c_n, 100 * dgot / dtot, 100 * t_sum / t_n

SRC = 'source'
PART = 'partial'


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def mark(v):
    if v == 1:
        return '<span class="s s3" aria-hidden="true"></span>', '1'
    if v == 0:
        return '<span class="s s0" aria-hidden="true"></span>', '0'
    return '<span class="s s2" aria-hidden="true"></span>', ('%g' % v)


def table(items):
    rows = []
    for name, v, note in items:
        dot, num = mark(v)
        rows.append('<tr><td class="mk">' + dot + '</td><td class="nm">' + esc(name)
                    + '</td><td class="sc">' + num + '</td><td class="nt">'
                    + esc(note) + '</td></tr>')
    return ('<table><thead><tr><th class="mk"><span class="vh">State</span></th>'
            '<th>Capability</th><th class="sc">Score</th><th>Evidence or gap</th>'
            '</tr></thead><tbody>' + ''.join(rows) + '</tbody></table>')


def meter(label, pct, sub):
    return ('<div class="tile"><div class="lab">' + label + '</div>'
            '<div class="val">' + ('%.0f' % pct) + '<span class="pc">%</span></div>'
            '<div class="track" role="img" aria-label="' + label + ': '
            + ('%.0f' % pct) + ' percent complete"><i style="width:'
            + ('%.1f' % pct) + '%"></i></div>'
            '<div class="sub">' + sub + '</div></div>')


groups = ''
for g, items in compiler.items():
    s = sum(x for _, x, _ in items)
    groups += ('<h3>' + esc(g) + ' <em>' + ('%.2f of %d' % (s, len(items)))
               + '</em></h3>' + table(items))

mod_body = ''
for m, h, d in mod_rows:
    where = 'compiler intrinsics' if m in ('e.mem', 'e.os') else 'lib/' + m.replace('.', '/') + '.e'
    mod_body += ('<tr><td class="nm"><code>' + esc(m) + '</code></td><td class="sc">'
                 + ('%d / %d' % (h, d)) + '</td><td class="sc">'
                 + ('%.0f%%' % (100 * h / d)) + '</td><td class="nt">' + where + '</td></tr>')
mod_table = ('<table><thead><tr><th>Module</th><th class="sc">Declarations</th>'
             '<th class="sc">Share</th><th>Where it comes from</th></tr></thead><tbody>'
             + mod_body + '</tbody></table>')

mod_pct = 100 * (surf.get(SRC, 0) + 0.5 * surf.get(PART, 0)) / len(plan)

html = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>neper Readiness</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Spectral:ital,wght@0,400;0,600;1,400&amp;family=IBM+Plex+Mono:wght@400;500&amp;family=IBM+Plex+Sans:wght@400;500;600&amp;display=swap">
<style>
:root {
  --ink:#101418; --ink-2:#42505f; --ink-3:#78838f;
  --rule:#e4e8ee; --rule-2:#eef1f5; --paper:#ffffff; --panel:#f7f8fa;
  --ramp-3:#1a4fa0; --ramp-2:#7297d2; --ramp-1:#c9d8ee; --ramp-0:#dfe4ea;
  --serif:"Spectral",Georgia,"Times New Roman",serif;
  --sans:"IBM Plex Sans","Segoe UI",system-ui,-apple-system,Helvetica,Arial,sans-serif;
  --mono:"IBM Plex Mono",ui-monospace,"Cascadia Mono",Consolas,monospace;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --ink:#e7ecf3; --ink-2:#a7b3c1; --ink-3:#7d8894;
    --rule:#232c37; --rule-2:#1a222c; --paper:#0f1319; --panel:#151b23;
    --ramp-3:#8fb0e6; --ramp-2:#4a6da8; --ramp-1:#2a3a52; --ramp-0:#262f3a;
  }
}
:root[data-theme="dark"] {
  --ink:#e7ecf3; --ink-2:#a7b3c1; --ink-3:#7d8894;
  --rule:#232c37; --rule-2:#1a222c; --paper:#0f1319; --panel:#151b23;
  --ramp-3:#8fb0e6; --ramp-2:#4a6da8; --ramp-1:#2a3a52; --ramp-0:#262f3a;
}
* { box-sizing:border-box; }
body {
  margin:0; background:var(--paper); color:var(--ink);
  font:400 16px/1.6 var(--sans); -webkit-font-smoothing:antialiased;
}
.wrap { max-width:60rem; margin:0 auto; padding:3.5rem 1.5rem 5rem; }
header { border-bottom:1px solid var(--rule); padding-bottom:1.75rem; margin-bottom:2.5rem; }
.eyebrow {
  font:500 .75rem/1 var(--mono); letter-spacing:.14em; text-transform:uppercase;
  color:var(--ink-3); margin:0 0 .9rem;
}
h1 {
  font:600 2.5rem/1.15 var(--serif); margin:0 0 .6rem; letter-spacing:-.01em;
  text-wrap:balance; color:var(--ink);
}
.stand { font-size:1.0625rem; color:var(--ink-2); max-width:46rem; margin:0; }
.stand em { font-family:var(--serif); }
.kpi { display:grid; grid-template-columns:repeat(auto-fit,minmax(13rem,1fr)); gap:1.75rem; margin:0 0 2rem; }
.tile { display:flex; flex-direction:column; gap:.55rem; }
.lab { font:500 .8125rem/1 var(--sans); letter-spacing:.02em; color:var(--ink-2); }
.val { font:600 3rem/1 var(--sans); letter-spacing:-.03em; color:var(--ink); }
.pc { font-size:1.375rem; font-weight:500; color:var(--ink-3); margin-left:.08em; }
.track { height:8px; border-radius:4px; background:var(--ramp-1); overflow:hidden; }
.track i { display:block; height:100%; border-radius:4px; background:var(--ramp-3); }
.sub { font:400 .8125rem/1.45 var(--mono); color:var(--ink-3); }
section { margin:0 0 3.25rem; }
h2 {
  font:600 1.5rem/1.25 var(--serif); margin:0 0 .75rem; letter-spacing:-.005em;
  padding-top:1.5rem; border-top:2px solid var(--ink); display:flex;
  justify-content:space-between; align-items:baseline; gap:1rem; flex-wrap:wrap;
}
h2 span { font:500 .875rem/1 var(--mono); color:var(--ink-3); letter-spacing:0; }
h3 {
  font:600 .8125rem/1 var(--sans); letter-spacing:.08em; text-transform:uppercase;
  color:var(--ink-2); margin:2rem 0 .75rem; display:flex;
  justify-content:space-between; align-items:baseline; gap:1rem;
}
h3 em { font:400 .8125rem/1 var(--mono); letter-spacing:0; text-transform:none; color:var(--ink-3); }
p { max-width:46rem; color:var(--ink-2); }
.tw { overflow-x:auto; }
table { border-collapse:collapse; width:100%; font-size:.875rem; min-width:34rem; }
th {
  text-align:left; font:500 .6875rem/1 var(--mono); letter-spacing:.1em;
  text-transform:uppercase; color:var(--ink-3); padding:0 .75rem .5rem 0;
  border-bottom:1px solid var(--rule);
}
td { padding:.45rem .75rem .45rem 0; border-bottom:1px solid var(--rule-2); vertical-align:baseline; }
tbody tr:last-child td { border-bottom:0; }
.nm { color:var(--ink); width:46%; }
.nt { color:var(--ink-3); font:400 .8125rem/1.45 var(--mono); }
.sc { font-variant-numeric:tabular-nums; font-family:var(--mono); color:var(--ink-2);
      text-align:right; white-space:nowrap; width:1%; padding-right:1.25rem; }
th.sc { text-align:right; }
.mk { width:1.25rem; padding-right:.6rem; }
.s { display:inline-block; width:9px; height:9px; border-radius:2px; }
.s3 { background:var(--ramp-3); }
.s2 { background:var(--ramp-2); }
.s0 { background:var(--ramp-0); }
.vh { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0 0 0 0); }
code { font:400 .875em/1 var(--mono); color:var(--ink); }
.note {
  background:var(--panel); border-left:2px solid var(--ramp-2);
  padding:1.15rem 1.35rem; margin:2rem 0 0; font-size:.9375rem;
}
.note p { margin:0 0 .65rem; }
.note p:last-child { margin:0; }
.note h4 { font:600 .8125rem/1 var(--sans); letter-spacing:.08em; text-transform:uppercase;
           color:var(--ink-2); margin:0 0 .7rem; }
.legend { display:flex; gap:1.5rem; flex-wrap:wrap; font:400 .8125rem/1 var(--mono);
          color:var(--ink-3); margin:0 0 2rem; padding-bottom:.25rem; }
.legend span { display:inline-flex; align-items:center; gap:.45rem; }
footer { border-top:1px solid var(--rule); margin-top:3rem; padding-top:1.25rem;
         font:400 .8125rem/1.6 var(--mono); color:var(--ink-3); }
</style>
</head>
<body>
<div class="wrap">

<header>
  <p class="eyebrow">neper &middot; milestone M2</p>
  <h1>Readiness</h1>
  <p class="stand">Three numbers for three deliverables, each scored against the
  capability list the <em>roadmap</em> and <em>module plan</em> already state. Every row
  below carries its evidence or its gap, so the totals are checkable rather than
  asserted.</p>
</header>

<div class="kpi">
__KPI__
</div>

<p class="legend">
  <span><i class="s s3"></i> delivered &mdash; score 1</span>
  <span><i class="s s2"></i> partial &mdash; score 0.25 to 0.5</span>
  <span><i class="s s0"></i> not started &mdash; score 0</span>
</p>

<section>
  <h2>Compiler <span>__CSUM__ / __CN__ &middot; __CPCT__%</span></h2>
  <p>The furthest along of the three, for a narrow reason: the front end is nearly
  complete while whole back-end subsystems have not been started. It compiles its own
  source on both platforms, and stage&nbsp;2 and stage&nbsp;3 come out byte-identical
  &mdash; the strongest single result on this page.</p>
__GROUPS__
</section>

<section>
  <h2>Modules <span>__DGOT__ / __DTOT__ &middot; __MPCT__%</span></h2>
  <p>Scored by <strong>declaration</strong> rather than by module.
  <code>docs/module-apis.md</code> freezes __DTOT__ declarations across __NMOD__
  modules, and __DGOT__ of them exist in committed source or as compiler intrinsics.
  Counting whole modules gives a similar figure &mdash; __NSRC__ at
  <code>surface:"source"</code> and __NPART__ at <code>"partial"</code> out of __NPLAN__,
  or __MODPCT__%.</p>
  <p>The two framings agree because the delivered modules are finished: every container
  and algorithm module below implements its frozen surface in full. What is missing is
  breadth, not polish. The design layer is a separate story &mdash; all __NMOD__ modules
  have a frozen, mechanically extractable API, which is what makes the denominator
  meaningful.</p>
  <div class="tw">__MODTABLE__</div>
  <div class="note">
    <h4>What the two large partials mean</h4>
    <p><code>e.os</code> at 31 of 121 and <code>e.io</code> at 1 of 42 are not stalled
    work. They are exactly the subsets the compiler needs in order to build itself. The
    rest of <code>e.os</code> waits on <code>extern</code> with <code>@cc</code>; the rest
    of <code>e.io</code> waits on <code>printf</code>, and so on comptime string
    parameters and varargs.</p>
    <p><code>e.str</code> at 58 of 66 is the builder half, which
    <code>mem.view</code> unblocked and <code>mem.cast</code> completed by making a
    <code>Sink</code> context constructible, plus the read-only half and the integer
    parsers, none of which needed compiler work at all. Nothing is left that a
    library can reach today. Float lowering has landed, so the four float pushes and
    two float parsers are no longer blocked on it, but writing a shortest
    round-tripping float needs the value's bits and <code>mem.bitcast</code> is still
    unimplemented; <code>push_err</code> waits on a runtime error-name table, and
    <code>format</code> &mdash; rule&nbsp;4's supplied protocol, the one still missing
    on the compiler side &mdash; on comptime <code>str</code> parameters and
    varargs.</p>
  </div>
</section>

<section>
  <h2>Tooling <span>__TSUM__ / __TN__ &middot; __TPCT__%</span></h2>
  <p>The lowest of the three, and the least surprising. None of the ten specified
  commands emits the JSONL v1 contract yet, and <code>tests/conformance/</code> does not
  exist. What does exist is substantial but internal: a 285-fixture self-host suite on
  both platforms, module-plan validation in CI, and a reproducible-build check. The
  schema, the diagnostic registry and the command surface are designed and frozen;
  nothing emits against them.</p>
  <div class="tw">__TTABLE__</div>
</section>

<div class="note">
  <h4>Method</h4>
  <p>Each capability scores 1 when delivered, 0 when not started, and a fraction
  between when partial, with the reason stated in its own row. Items are weighted
  equally inside a dimension; no dimension is weighted against another, and the three
  numbers are never combined into one. Compiler scope is the CPU language of M1 and M2
  &mdash; GPU (M3) and Metal (M5) are separate milestones, excluded rather than counted
  as zero.</p>
  <p>Module readiness counts declarations present in committed source or seeded as
  compiler intrinsics. Uncommitted work in the tree is deliberately not counted.</p>
  <p>One judgement is worth naming. Self-hosting is three rows out of __CN__ here, but it
  is the binary M2 exit gate. Read the compiler number as capability coverage, not as
  distance to the milestone.</p>
</div>

<div class="note">
  <h4>Keeping this current</h4>
  <p>This page is generated, never hand-edited. <strong>Every session that lands a
  capability updates it</strong>: move the affected rows in the tables at the top of
  <code>scripts/render_progress.py</code>, run <code>python
  scripts/render_progress.py</code> from the repository root, and commit the regenerated
  page with the change that earned it. The module numbers need no editing at all &mdash;
  they are read from <code>docs/module-apis.md</code>, <code>docs/modules.json</code>,
  the committed <code>lib/e</code> sources and the intrinsics seeded in
  <code>src/resolve.e</code>.</p>
  <p>A readiness figure that moves only when someone remembers to move it is worse than
  no figure. This is the single readiness document for the project; there is no second
  copy to keep in step.</p>
</div>

<footer>
  Generated by <code>scripts/render_progress.py</code> from <code>docs/roadmap.md</code>,
  <code>docs/module-apis.md</code>, <code>docs/modules.json</code> and the compiler
  sources, as they stood at <code>__REV__</code> (__DATE__).
</footer>

</div>
</body>
</html>
"""

kpi = '\n'.join([
    meter('Compiler', C, '%.2f of %d capabilities' % (c_sum, c_n)),
    meter('Modules', M, '%d of %d declarations' % (dgot, dtot)),
    meter('Tooling', T, '%.2f of %d capabilities' % (t_sum, t_n)),
])

for key, val in [
    ('__KPI__', kpi),
    ('__GROUPS__', groups),
    ('__MODTABLE__', mod_table),
    ('__TTABLE__', table(tooling)),
    ('__CSUM__', '%.2f' % c_sum), ('__CN__', str(c_n)), ('__CPCT__', '%.0f' % C),
    ('__TSUM__', '%.2f' % t_sum), ('__TN__', str(t_n)), ('__TPCT__', '%.0f' % T),
    ('__DGOT__', str(dgot)), ('__DTOT__', str(dtot)), ('__MPCT__', '%.0f' % M),
    ('__NMOD__', str(len(blocks))), ('__NPLAN__', str(len(plan))),
    ('__NSRC__', str(surf.get(SRC, 0))), ('__NPART__', str(surf.get(PART, 0))),
    ('__MODPCT__', '%.0f' % mod_pct),
    ('__DATE__', when), ('__REV__', rev),
]:
    html = html.replace(key, val)

open('docs/progress.html', 'w', encoding='utf-8', newline='\n').write(html)
print('wrote docs/progress.html')
print('compiler %.1f  modules %.1f  tooling %.1f' % (C, M, T))
