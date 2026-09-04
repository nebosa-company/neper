# Neper LLM editing card

Use this compact card for source edits. The normative references are
[`grammar.ebnf`](grammar.ebnf), [`tooling.md`](tooling.md), and `spec.md` §§2–6 and
§14.

## Core syntax

```text
use module.path [as qualifier]
type Name = struct { field: Type, }
const NAME: Type = value
fn name(arg: Type, ...) -> Return { ... }
let value = expression
ret expression
```

Declarations start at column 0. Blocks use braces; statements are newline-separated.
Comments are `//`. Functions, values, fields, and modules use `snake_case`; types use
`PascalCase`; constants use `SCREAMING_SNAKE`.

An author-written cross-module reference is qualified: `module.function(...)` or
`module.Type{ ... }`. `use` binds a module's qualifier; it may explicitly use `as`.
There is no overloading, no macros or preprocessor, no hidden textual generation, and
no implicit numeric conversions. Write casts explicitly, for example `u64(value)`.

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

## Tool-assisted navigation

`neper index --json` is versioned JSONL. It exposes every `symbol` with kind, name,
qualified name, module, signature, spans, attributes, and documentation; it also
exposes every `reference` with role, spelling, source span, and resolved target.
Use it to locate definitions and all call/type/reference sites before reading source.
`neper tokens` and `neper parse` expose lossless grammar output; `neper fmt --check`
checks canonical layout without modifying source.

For a surgical change: index → read only the definition and resolved references → edit
those exact spans → run the parser/checker and formatter check when available.
