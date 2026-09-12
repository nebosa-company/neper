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
  ("Generic aggregate types", 1, "link/generic_same_name; check/generic_instance_field and link/generic_instance_alias pin one used as a field type, named directly and through an alias; link/data_iter pins a nested instance as a type argument -- `Filter[Map[Iter[i64], i64, i64], i64]` -- which read its inner argument as the outer's until the argument block was claimed before it was filled (D145)"),
  ("Protocol resolution, spec 9 rules 3 and 5", 1, "check/protocol_*"),
  ("Iterator protocol <t>_next", 1, "tests/neper0; link/data_iter calls it through a type parameter as `I.next(&it)`, on a generic iterator whose `_next` is instantiated from the receiver's own arguments (D145)"),
  ("Supplied cmp (rule 4)", 1, "link/sequence_cmp, tagged_union_cmp"),
  ("Supplied hash (rule 4)", 1, "link/supplied_hash, folded_hash"),
  ("Supplied eq (rule 4)", 1, "link/supplied_eq; link/test_assert pins the floats, which rule 4 always listed and the compiler had not supplied: every NaN equals every other and the two zeros are one (D142)"),
  ("Supplied format (rule 4)", 0.97, "link/str_format, link/io_printf expand scalars, str, bool and err; slices and arrays recurse an element at a time as `[a, b]`, nesting included (D189); an enum prints its variant name (D190); a type's own format is what remains"),
  ("Scalar floating point f32 / f64", 1, "link/float_scalar; f16 / bf16 still unlowered. link/math_exact pins `math.sqrt` as the one float intrinsic -- `sqrtss`/`sqrtsd` behind a NIR opcode of its own, correctly rounded and checked by its bits (D146). `fma` is exact by integer arithmetic on the significands, and the thirteen transcendentals are fdlibm's over f64 with a Payne-Hanek reduction of its own, each measured within 1 ULP against mpmath at 200 bits in the four link/math_* fixtures (D147)"),
  ("Vec[T,N] / Mask[T,N] and SIMD lowering", 0.7, "`Vec[T, N]` and `Mask[T, N]` are builtins seeded into e.simd with section 4's closed table, width-aligned layout and `meta.kind/element_type/array_len` answers; every `simd.*` intrinsic but `shuffle` is library source lowered lane by lane over scalar code (D148); section 4's operator table -- IEEE `+ - * /` on float lanes, only `+% -% *%`, the bitwise ones and a scalar shift on integer lanes, `& | ^ ~` on masks -- is checked and lowered lane by lane, plain `+` on integer lanes and every comparison refused (D158); `Vec[T, N]{ ... }` is N positional lanes and `v[i]` reads or writes one, bounds-checked (D159); `shuffle`'s `IDX: [N]u8` is a comptime array parameter, bound from a literal of literals and forwardable by name (D160). Not yet: the mask register-only rule and a vector register class with SSE/AVX selection"),
  ("Atomic[T] and memory orderings", 1, "link/atomic_ops runs all thirteen across every width and both signs; link/atomic_threads proves the lock prefix under contention; check/atomic_* pin the ordering rules. e.sync and e.channel are unblocked"),
  ("extern with @import / @cc and the C ABI", 0.8, "link/extern_import binds and calls foreign symbols on both platforms: a PE import directory with one descriptor per library, and a dynamic ELF with PT_INTERP, DT_NEEDED and GLOB_DAT slots. It also pins a narrow signed return being widened, which the convention leaves undefined above the declared width -- an unwidened -1 read as 0xFFFFFFFF made every `< 0` check on a foreign call pass. What is left is the ABI mapping itself -- section 5's closed table of which types cross, and variadics"),
  ("Comptime str parameters and varargs", 0.95, "link/comptime_str, link/str_format, link/io_printf; two of the three pack intrinsics expand, `gpu.launch` does not"),
  ("e.meta reflection", 1, "link/meta_scalar answers kind, array_len and type_name; link/meta_reflect walks fields and members through comptime Field and Member values, an unrolled for and get/set at the named offset; link/meta_types answers element_type and backing_type, whose result is a type usable as a comptime argument, nested in the other question, or instantiating a generic. link/meta_field_param hands a comptime Field across a call, so the callee is instantiated per field with a return type that depends on which one it got. A type-valued answer stands where a type is written, including a local's annotation: the type grammar takes a trailing call and name resolution classifies it (D126). A comptime `Field` parameterises a function or a type, and link/meta_field_param pins each instantiation's layout to the field it was built around (D127). link/meta_generic asks the same questions from inside a generic function, where the subject is a type parameter: the template body is checked once with nothing bound, so the question stands there and the instance settles it, which is the deferral `mem.size_of` always had (D136); a `let` initialised by such a protocol call follows its declared type the same way (D143). A call whose callee is a binding's `.ty` is a conversion, the same one a written `u8(x)` is, which is how a walk over `meta.fields` puts a parsed value into the field it belongs to -- every parser answers in one width and every field has its own (D139). A bare type parameter is a conversion the same way, `T(bits)`, and its operand may itself be of a type parameter's type; a `bitcast` to `T` stands in the template pass and is checked per instance (D144)"),
  ("Merged error table", 0.5, "src/error_table.e builds it and push_err expands against it; not yet in the binary for the failure line, trap protocol or `neper test`"),
  ("Spec 11 debug check table and trap protocol", 0, "NIR .Trap never emitted"),
  ("General comptime interpreter", 0.4, "integer const folding, and a branch settled by one `meta` question. link/comptime_branch walks `meta.fields` with arms that do not type check for each other's field types, and recurses on `meta.element_type` with the guard arm as its base case -- neither could be written before, and both are what a codec over a struct is (D138). `mem.size_of[T]()` on a scalar folds the same way (D144), which is what lets one generic `load` in e.bytes hold a bitcast for each float width with the wrong one gone. The condition still has to be a `meta` or size question compared against a constant: an `if` over an arbitrary comptime expression wants the interpreter this does not have"),
 ],
 "Back end": [
  ("NIR, typed SSA-lite", 1, "src/nir.e"),
  ("Linear-scan register allocator", 1, "src/regalloc.e"),
  ("x64 emitter, System V and Win64", 1, "src/codegen_x64.e"),
  ("ELF object writer", 1, "src/object_elf.e"),
  ("COFF object writer", 1, "src/object_coff.e"),
  ("Own ELF linker", 1, "src/link_elf.e"),
  ("Own PE linker with kernel32 imports", 1, "src/link_pe.e"),
  ("Host runtime intrinsics, both platforms", 1, "runtime_pe_x64.asm, runtime_elf_x64.s"),
  ("os.syscall and mem.address_of: the raw kernel path", 1, "link/os_syscall carries a path and a stat buffer through getcwd and newfstatat; link/mem_address pins the address itself and D96 keeps it one-way. It is what lib/e/os.linux.e is written over -- six filesystem primitives in neper rather than asm. Linux only by design; the name does not resolve on Windows"),
  ("`.em` module format with Deps edges", 1, "src/em.e, fixtures/em"),
  ("Dead-function elimination", 1, "only what `main` reaches is emitted, following calls and taken addresses. Both link paths drop the same functions from the same sequence, so an image linked from `.em` artifacts stays byte-identical to one compiled from source -- which link/function_values compares by hash. A minimal e.os binary went from 221 KB to 8 KB and is freestanding again; the compiler's own stage 2 from 4,170,240 to 3,930,624 bytes (D130). Both runtimes are ordered so a function calls only what precedes it and are cut after the last one the program reaches, and the ELF code segment starts where the headers end: and the PE import table declares only what the kept runtime reaches: an empty program is 366 bytes on Linux and 2,048 on Windows, hello world 3,984 and 6,144 (D149, D150, D151)"),
  ("Cross-module inlining, 40 NIR cap", 0, "not started"),
  ("Incremental rebuild on the edge rule", 0, "not started"),
  ("os.thread_create / join / detach", 1, "link/os_thread runs and joins a real thread on both platforms: CreateThread on Windows, clone(2) over a self-allocated stack with a futex join on Linux. detach leaks its mapping, wanting a reaper"),
  ("Work-stealing pool, parallel parse and codegen", 0, "single-threaded"),
  ("Determinism harness", 0.25, "compiler fixed point only; no -jN or incremental cases"),
  ("DWARF, CodeView and .nepersym debug info", 0, "bootstrap only"),
 ],
 "Self-hosting": [
  ("Self-hosted compiler emits its own source", 1, "run.ps1:623, run.sh:760"),
  ("Stage 2 == stage 3, byte-identical, both platforms", 1, "SHA-256 compare / cmp"),
  ("Bootstrap recovery path archived", 0, "no freeze tag; stage hashes unrecorded (D95)"),
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
 ("Module-plan validation in CI", 1, "check_module_plan.py 128 modules; check_module_surfaces.py 9 sources"),
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
# `lib/e/os.linux.e` is `e.os`, not a module called `e.os.linux`: a per-target variant
# is one of the files a module may be written in (spec 2), so the trailing arch or os
# is not part of the name and the variants union into one surface.
VARIANTS = {'linux', 'windows', 'macos', 'none', 'x64', 'x86', 'aarch64', 'spv', 'ptx'}
impl = {}
for p in tracked:
    if not p.endswith('.e'):
        continue
    parts = p[len('lib/e/'):-2].replace('/', '.').split('.')
    if len(parts) > 1 and parts[-1] in VARIANTS:
        parts.pop()
    mod = 'e.' + '.'.join(parts)
    impl.setdefault(mod, set()).update(
        m.group(2) for m in
        (re.match(r'(fn|type|error|const)\s+([A-Za-z_][A-Za-z0-9_]*)', l)
         for l in open(p, encoding='utf-8')) if m)

seeded = {}
for mod, nm in re.findall(r'seed\(r,\s*g,\s*"([^"]+)",\s*"([^"]+)"',
                          open('src/resolve.e', encoding='utf-8').read()):
    seeded.setdefault(mod, set()).add(nm)

plan = json.load(open('docs/modules.json'))['modules']
surf = {}
for m in plan:
    surf[m['surface']] = surf.get(m['surface'], 0) + 1
# `docs/modules.json` is the plan and this table is the plan's, so every module in it gets a
# row whether or not a line of it exists. A page that listed only what is written cannot be
# read as a roadmap: what is missing is the part a reader is asking about.
planned = {m['name']: m for m in plan}
tier_of = {}
for tier in json.load(open('docs/modules.json'))['tiers']:
    for name in tier['modules']:
        tier_of[name] = tier['id']

mod_rows, dtot, dgot = [], 0, 0
for mod in sorted(blocks):
    d = decl_names(blocks[mod])
    have = impl.get(mod, set()) | seeded.get(mod, set())
    h = sum(1 for n in d if n in have)
    dtot += len(d)
    dgot += h
    entry = planned.get(mod, {})
    mod_rows.append((mod, h, len(d), entry.get('surface', 'planned'),
                     entry.get('milestone'), entry.get('schedule', 'later'),
                     tier_of.get(mod, ''), entry.get('blocked_by', [])))
# Written first and most complete first; then what is scheduled, by milestone; then what is not
# scheduled at all. Read top to bottom that is the order the plan intends to be worked in, which
# is the only ordering a roadmap can justify.
mod_rows.sort(key=lambda r: (-r[1] / r[2], r[4] is None, r[4] or '', r[0]))

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
for m, h, d, surface, milestone, schedule, tier, blocked in mod_rows:
    # Both of these are intrinsics plus source now, and saying only "intrinsics" understates
    # how much of them is written down: e.os is mostly its two per-target files, and e.mem gained
    # `copy` and `eq`.
    if m == 'e.mem':
        where = 'compiler intrinsics, lib/e/mem.e'
    elif m == 'e.os':
        where = 'compiler intrinsics, lib/e/os.linux.e, lib/e/os.windows.e'
    elif h:
        where = 'lib/' + m.replace('.', '/') + '.e'
    elif blocked:
        where = 'blocked: ' + ', '.join(blocked)
    elif schedule == 'scheduled':
        where = 'scheduled, not started'
    else:
        where = 'after the scheduled set'
    when = milestone if milestone else '&mdash;'
    mod_body += ('<tr><td class="nm"><code>' + esc(m) + '</code></td><td class="sc">'
                 + ('%d / %d' % (h, d)) + '</td><td class="sc">'
                 + ('%.0f%%' % (100 * h / d)) + '</td><td class="sc">' + when
                 + '</td><td class="sc">' + esc(tier) + '</td><td class="nt">'
                 + esc(surface) + ' &middot; ' + esc(where) + '</td></tr>')
mod_table = ('<table><thead><tr><th>Module</th><th class="sc">Declarations</th>'
             '<th class="sc">Share</th><th class="sc">Milestone</th><th class="sc">Tier</th>'
             '<th>Surface and where it comes from</th></tr></thead><tbody>'
             + mod_body + '</tbody></table>')

mod_pct = 100 * (surf.get(SRC, 0) + 0.5 * surf.get(PART, 0)) / len(plan)

# The prose below the table names three modules by their counts. Typing those in is
# how the page goes stale one increment after it is written, so they come from the
# same rows the table does.
counts = {row[0]: (row[1], row[2]) for row in mod_rows}
written_modules = sum(1 for row in mod_rows if row[1])


def count_of(module):
    h, d = counts[module]
    return '%d of %d' % (h, d)

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
/* Six columns rather than four, so the name gives most of its width back. */
.mods table { min-width:46rem; }
.mods .nm { width:22%; }
.mods .nt { width:34%; }
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
  and algorithm module with a count below implements its frozen surface in full. What is
  missing is breadth, not polish. The design layer is a separate story &mdash; all
  __NMOD__ modules have a frozen, mechanically extractable API, which is what makes the
  denominator meaningful.</p>
  <p>The table is the whole plan, not the part that exists: every one of the __NPLAN__
  modules in <code>docs/modules.json</code> has a row, __NWRITTEN__ of them with something
  written. The rest carry what is known about them instead &mdash; the milestone they are
  scheduled for, the tier that says what stability they will promise, and what they are
  waiting on. <strong>core</strong> is the required-first set, <strong>extended</strong> is
  stable but independently delivered, and <strong>experimental</strong> promises no
  compatibility. A module with no milestone is not scheduled yet, which is a statement
  about order and not about doubt.</p>
  <div class="tw mods">__MODTABLE__</div>
  <div class="note">
    <h4>What the two large partials mean</h4>
    <p><code>e.os</code> at __COS__ and <code>e.io</code> at __CIO__ are not stalled
    work. <code>e.os</code> is the subset the compiler needs to build itself, plus
    everything written since as neper source rather than supplied as intrinsics: the
    filesystem calls <code>e.fs</code> needs, sockets, a poller, file mappings, directory
    watches, file locks, process groups, name resolution and the loader. Those are per target,
    over <code>os.syscall</code> on Linux and <code>kernel32</code> through
    <code>@import</code> on Windows, which is what D32 said all along (D97) &mdash; and on Linux
    the resolver is a DNS client written in neper, because that host has nothing to ask (D120).
    The loader is the one place <code>os.linux.e</code> names a library instead of a syscall.
    That did cost something at first &mdash; every binary using <code>e.os</code> came out linked
    against libc, because the compiler emitted every function of every module it touched &mdash;
    which is what dead-function elimination fixed: only what <code>main</code> reaches is emitted,
    so a binary that opens no library is freestanding again and a minimal one went from 221&nbsp;KB
    to 8&nbsp;KB (D130 corrects D128). Nothing in that fence is unwritten:
    <code>last_error_detail</code> was the last, and it waited on a module-scope <code>var</code>
    in the compiler, which is now built. It is a slot per thread keyed by the thread's own
    identifier, with no atomics available inside <code>e.os</code>'s dependency budget &mdash; so a
    detail may be absent and is never another thread's (D132).
    <code>e.io</code> is the subset the compiler needs.
    <code>e.io</code> no longer waits on <code>printf</code>: that expands, over a
    4&nbsp;KiB buffer of its own drained through a generated sink.</p>
    <p><code>e.str</code> is complete at __CSTR__ and is the first module at
    <code>surface:&nbsp;"source"</code> to have needed the compiler for any of it.
    <code>format</code> expands, and so does <code>push_err</code> &mdash; the one
    declaration a library could not write, because what it prints is the qualified
    name and the merged error table is a property of the whole program, where a
    module sees one module at a time. What the expansion still cannot reach is a
    slice, an array or a named type's own <code>format</code>, each of which needs it
    to recurse into an argument.</p>
    <p>What <code>e.io</code>'s remaining declarations wait on is not a compiler
    feature but a decision. Ten of its constructors have to supply a callback of
    their own, and the shape they need &mdash;
    <code>fn(*void, []u8) -&gt; (usize, err)</code> &mdash; is not one the frozen
    surface declares. The language has no visibility mechanism (spec&nbsp;&sect;12), so
    a helper cannot be added quietly: it would be a public symbol the plan does not
    know about. <code>printf</code>'s own sink hit exactly this and was answered by
    generating the function in the compiler, which is one of the three ways the rest
    could go; widening the surface and making the constructors intrinsics are the
    others.</p>
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
  <p>One judgement is worth naming. Self-hosting is four rows out of __CN__ here, but it
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
    ('__NWRITTEN__', str(written_modules)),
    ('__NSRC__', str(surf.get(SRC, 0))), ('__NPART__', str(surf.get(PART, 0))),
    ('__MODPCT__', '%.0f' % mod_pct),
    ('__COS__', count_of('e.os')), ('__CIO__', count_of('e.io')),
    ('__CSTR__', count_of('e.str')),
    ('__DATE__', when), ('__REV__', rev),
]:
    html = html.replace(key, val)

open('docs/progress.html', 'w', encoding='utf-8', newline='\n').write(html)
print('wrote docs/progress.html')
print('compiler %.1f  modules %.1f  tooling %.1f' % (C, M, T))
