# Rust LLM editing card

Use this compact card for source edits. It provides an equivalent tool-assisted
workflow to the Neper editing card used by the benchmark.

## Core syntax

```text
use crate::module::item;
pub struct Name { field: Type, }
const NAME: Type = value;
pub fn name(arg: Type, ...) -> Return { ... }
let value = expression;
```

Declarations and blocks use braces; ordinary statements end in `;`. Comments are
`//`. Functions, values, fields, and modules conventionally use `snake_case`; types
use `PascalCase`; constants use `SCREAMING_SNAKE`.

Imports bind names into local scope. Functions may be overloaded only through traits,
not ordinary free-function declarations. Numeric conversions are explicit, for
example `value as u64`; preserve the existing conversion style. Keep edits local and
preserve formatting.

For the common signature edit shape:

```text
pub fn adjust(reading: f32, offset: f32) -> f32 {
    reading + offset
}

// after adding gain
pub fn adjust(reading: f32, gain: f32, offset: f32) -> f32 {
    reading * gain + offset
}

let x = adjust(41.7, 1.0, 0.25);
```

## Tool-assisted navigation

The benchmark exposes a versioned structured index with definition and resolved call
reference records. Use it to locate the target definition and all call sites before
reading source. Then read only those spans, edit the exact occurrences, and validate
that no old call spelling remains.
