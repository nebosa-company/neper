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

For the common edit shapes:

```text
fn adjust(reading: f32, offset: f32) -> f32 {
    ret reading + offset
}

// after adding gain
fn adjust(reading: f32, gain: f32, offset: f32) -> f32 {
    ret reading * gain + offset
}

let x = calibration.adjust(41.7, 1.0, 0.25)
type Sensor = struct { id: u64, temp: f32, }
let sensor = Sensor{ id: u64(13), temp: 41.8 }
```

## Diagnostics

Codes are `E-<FAMILY>-<NNNN>`; the registry is `diagnostics.md`, and the code, not
the message, is the machine discriminator:

{{diagnostics}}

## Tool-assisted navigation

`neper index --json` is versioned JSONL (stream version 1, tool {{tool_version}}). It
exposes every `symbol` with kind, name, qualified name, module, signature, spans,
attributes, and documentation; it also exposes every `reference` with role, spelling,
source span, and resolved target. Use it to locate definitions and all call/type/
reference sites before reading source. `neper tokens` and `neper parse` expose
lossless grammar output; `neper fmt --check` checks canonical layout without modifying
source; `explain-file`, `context-file --symbol` and `uses-file --symbol` answer the
semantic questions (`tooling.md` §5).

For a surgical change: index → read only the definition and resolved references → edit
those exact spans → run the parser/checker and formatter check when available.
