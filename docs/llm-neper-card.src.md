# Neper LLM editing card (grammar revision {{revision}}, language {{language_version}})

Use this compact card for source edits. The normative references are
[`grammar.ebnf`](grammar.ebnf) (revision {{revision}}), [`tooling.md`](tooling.md),
[`diagnostics.md`](diagnostics.md) and `spec.md` §§2–6 and §14. The syntax sections
below are the grammar's own productions, rendered by `scripts/render_card.py`; the
header comment carries the versions and the content hash, and a card whose hash is
not the render of its grammar revision is stale.

## Keywords

Every alphabetic terminal of the grammar: {{keywords}}. None may name a value, type,
field or module.

## Declarations

Declarations start at column 0. Blocks use braces; statements are newline-separated.
Comments are `//`. Functions, values, fields, and modules use `snake_case`; types use
`PascalCase`; constants use `SCREAMING_SNAKE`.

```ebnf
{{declarations}}
```

## Types

```ebnf
{{types}}
```

## Statements

```ebnf
{{statements}}
```

## Expressions

```ebnf
{{expressions}}
```

## Rules the grammar does not show

An author-written cross-module reference is qualified: `module.function(...)` or
`module.Type{ ... }`. `use` binds a module's qualifier; it may explicitly use `as`.
There is no overloading, no macros or preprocessor, no hidden textual generation, and
no implicit numeric conversions. Write casts explicitly, for example `u64(value)`.
Every local has an initializer (`= zero` and `= undef` are the explicit forms). A
resource -- a handle, a `resource` type, a struct holding one -- is owed its cleanup
on every exit and moves at most once (`E-SAFETY-*`, spec §11). `ret (a) || b` reads
as a tuple: bind the value first.

The examples are programs the suites check with the compiler (`scripts/card_examples.py`):
a ```` ```neper ```` fence checks clean, and a ```` ```neper reject E-CODE ```` fence is
refused with that code. The common edit shapes -- a parameter added, every call site
given it, a struct and its literal:

```neper
use e.mem

type Sensor = struct { id: u64, temp: f32 }

// after adding `gain`: every call passes it, there are no defaults and no overloads
fn adjust(reading: f32, gain: f32, offset: f32) -> f32 {
    ret reading * gain + offset
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sensor = Sensor { id: 13u64, temp: 41.8 }
    let adjusted = adjust(sensor.temp, 1.0, 0.25)
    if adjusted < 0.0 { ret mem.Exhausted }
    ret ok
}
```

The near miss: a value of one width where another is expected does not convert; the
diagnostic names both types (`expected`, `actual`) and the cast is written out:

```neper reject E-TYPE-0002
use e.mem

fn scale(reading: f32, gain: f32) -> f32 {
    ret reading * gain
}

fn main(a: *mem.Arena, args: []str) -> err {
    let reading: f64 = 41.8
    let scaled = scale(reading, 2.0)
    if scaled < 0.0 { ret mem.Exhausted }
    ret ok
}
```

## Diagnostics

Codes are `E-<FAMILY>-<NNNN>`; the registry is `diagnostics.md`, and the code, not
the message, is the machine discriminator. Each code's standing is read from the
repository when the card is rendered: `verified` -- a conformance golden or a suite
pins it; `present` -- the compiler emits it and nothing pins it yet; `planned` --
the registry alone names it. A verified code is the only kind an edit loop should
rely on:

{{diagnostics}}

## Token cost

Model tokens per grammar terminal, after a space, from the grammar-versioned
tokenizer profiles (`benchmarks/tokens/profile.py`, D375): a lexical
token is not a model token, and the corpus runs at about 1.27 model tokens per
lexical token. Prefer `usize` where the width is free; a fixed-width name costs two.

{{token_costs}}

## Tool-assisted navigation

`neper index --json` is versioned JSONL (stream version 1, tool {{tool_version}}). It
exposes every `symbol` with kind, name, qualified name, module, signature, spans,
attributes, and documentation; it also exposes every `reference` with role, spelling,
source span, and resolved target. Use it to locate definitions and all call/type/
reference sites before reading source. `neper tokens` and `neper parse` expose
lossless grammar output; `neper fmt --check` checks canonical layout without modifying
source. The semantic questions (`tooling.md` §5) have their own commands, every answer
a JSONL stream bound to the program's `snapshot`:

- `context-file --symbol module.name` -- one function's signature, the caller's
  contract (allocation, borrow, mutation, errors, threads), the rules that held, and
  what its body decided; `--symbol module.Type` a type's fields, layout and whether a
  value is a resource, a borrow or plain data; `--module module` the catalogue.
  `--budget N`, `--bytes N` and `--cursor N` page an answer.
- `uses-file --symbol module.name` -- every resolved use of a function, or of a field
  as `module.Type.field`; `explain-file` -- every dispatch, instantiation and discard.
- The plans, applied by nothing but the harness, each with file-hash preconditions
  and a re-check postcondition: `plan-rename-file --symbol m.f --to g` (a function or
  a field), `plan-add-parameter-file --symbol m.f --parameter "name: T" --argument
  EXPR`, `plan-change-signature-file --symbol m.f --order 2,0,1`,
  `plan-replace-expression-file --span START:END --with EXPR`;
  `apply-plan PLAN.jsonl --root DIR` applies one, all files hashing as recorded or none.
- `test-impact-file --changed m1,m2` -- the `@test` functions an edit reaches;
  `test-file ... --json --only n1,n2` runs those alone.
- `query-batch --batch FILE` -- many context, catalogue and uses queries over one
  check; a build takes `--deadline MS` and is cancelled between modules past it,
  and `--instances N`, a budget over the generic instances it may make.

For a surgical change: index or `uses-file` → `context-file` on what the change
touches → a plan where one exists, else edit the exact spans → apply → `check-file`,
`fmt --check` → `test-impact-file` → `test-file --only`. A diagnostic carries its
`code`, `expected`/`actual` types where they differ, `related` sites and `fixes`.
